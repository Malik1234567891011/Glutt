import Foundation
import SwiftData

/// Live cook-session state that the realtime tools read and mutate.
/// Owned by the registry; the controller reads it when writing the cook log.
struct CookState: Equatable {
    var stepIndex: Int = 0
    var completedStepIDs: Set<String> = []
    var substitutions: [String] = []
    var servings: Int
    /// Moments Polly prevented or recovered a kitchen mishap this session.
    var pollySaves: [String] = []
    /// Checklist action ids the cook (or Polly) has marked done on-screen.
    var checkedActionIDs: Set<String> = []
}

/// Polly's hands: maps Realtime function calls onto Glutt's existing pure
/// services (plan steps, timers, pantry, substitutions, nutrition, memory).
/// Every handler returns a compact JSON string ready to ship back as a
/// `function_call_output` item.
@MainActor
final class PollyToolRegistry {

    // MARK: - State

    private(set) var state: CookState
    /// Controller hook: capture + send a camera frame; true on success.
    var onRequestFrame: (() async -> Bool)?
    /// Controller hook: the model asked to end the session.
    var onEndSession: (() -> Void)?

    private let plan: CookPlan
    private let recipe: Recipe
    private let pantry: [PantryItem]
    private let prefs: UserPrefs
    private let timers: TimerManager
    private let context: ModelContext

    init(plan: CookPlan, recipe: Recipe, pantry: [PantryItem], prefs: UserPrefs,
         timers: TimerManager, context: ModelContext) {
        self.plan = plan
        self.recipe = recipe
        self.pantry = pantry
        self.prefs = prefs
        self.timers = timers
        self.context = context
        self.state = CookState(servings: plan.servings > 0 ? plan.servings : max(1, recipe.servings))
    }

    // MARK: - Tool definitions (15, names locked)

    static let toolDefinitions: [RealtimeToolDefinition] = [
        RealtimeToolDefinition(
            name: "get_current_step",
            description: "Get the step the cook is on right now: title, instruction, kind, timer, and the ingredients it uses.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "mark_step_done",
            description: "Mark the current step complete and move to the next one. Returns the next step, or {\"done\":true} after the final step.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "check_step_actions",
            description: "Check off on-screen checklist actions when the cook says they finished something (e.g. cut the tomatoes and cucumbers). Prefer item ids from get_current_step.actions; you may also pass short match words like \"tomato\". Call this BEFORE marking the whole step done when only some actions are finished.",
            parameters: schema(
                properties: [
                    "item_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Exact action ids from get_current_step.actions"),
                    ]),
                    "matches": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Short words/phrases to match action text, e.g. tomato, cucumber"),
                    ]),
                    "checked": .object([
                        "type": .string("boolean"),
                        "description": .string("true (default) to check off, false to uncheck"),
                    ]),
                ],
                required: []
            )
        ),
        RealtimeToolDefinition(
            name: "go_to_step",
            description: "Jump to a step by zero-based index. Out-of-range indexes clamp to the first or last step.",
            parameters: schema(
                properties: ["index": .object([
                    "type": .string("integer"),
                    "description": .string("Zero-based step index"),
                ])],
                required: ["index"]
            )
        ),
        RealtimeToolDefinition(
            name: "start_timer",
            description: "Start a countdown timer with a short label the cook will recognize.",
            parameters: schema(
                properties: [
                    "label": .object([
                        "type": .string("string"),
                        "description": .string("Short label, e.g. 'Simmer sauce'"),
                    ]),
                    "seconds": .object([
                        "type": .string("integer"),
                        "description": .string("Countdown length in seconds"),
                    ]),
                ],
                required: ["label", "seconds"]
            )
        ),
        RealtimeToolDefinition(
            name: "check_timers",
            description: "List every running timer and its remaining seconds.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "cancel_timer",
            description: "Cancel a running timer by label (case-insensitive).",
            parameters: schema(
                properties: ["label": .object(["type": .string("string")])],
                required: ["label"]
            )
        ),
        RealtimeToolDefinition(
            name: "check_pantry",
            description: "Check the recipe's ingredients against the cook's pantry: how many they own, and what's missing.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "find_substitutes",
            description: "Find substitutes for an ingredient that the cook has on hand and that respect their dietary rules and allergies.",
            parameters: schema(
                properties: ["ingredient": .object([
                    "type": .string("string"),
                    "description": .string("Ingredient name as written in the recipe"),
                ])],
                required: ["ingredient"]
            )
        ),
        RealtimeToolDefinition(
            name: "get_nutrition",
            description: "Get per-serving calories and protein for this recipe, with a confidence score when the numbers are estimated.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "adjust_servings",
            description: "Change the number of servings being cooked. Returns the scale factor versus the recipe as written.",
            parameters: schema(
                properties: ["servings": .object([
                    "type": .string("integer"),
                    "description": .string("New serving count, at least 1"),
                ])],
                required: ["servings"]
            )
        ),
        RealtimeToolDefinition(
            name: "remember_fact",
            description: "Save one durable fact about the cook's kitchen, technique, habits, or how this dish turned out. When the cook substitutes an ingredient, call this with text starting: Substituted X for Y in <recipe>.",
            parameters: schema(
                properties: [
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("equipment"), .string("technique"), .string("pantryHabit"),
                            .string("preference"), .string("outcome"),
                        ]),
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("One short sentence, third person"),
                    ]),
                    "confidence": .object([
                        "type": .string("number"),
                        "description": .string("0 to 1, how sure you are"),
                    ]),
                ],
                required: ["kind", "text"]
            )
        ),
        RealtimeToolDefinition(
            name: "record_polly_save",
            description: "Record a moment you prevented or recovered a cooking problem (burning, splitting sauce, undercooked protein, bad timing, missing ingredient workaround). Short past-tense phrase for the end-of-cook recap. Call when you actually change the outcome — not for routine tips.",
            parameters: schema(
                properties: [
                    "moment": .object([
                        "type": .string("string"),
                        "description": .string("Short phrase, e.g. 'Stopped garlic from burning' or 'Recovered a split sauce'"),
                    ]),
                ],
                required: ["moment"]
            )
        ),
        RealtimeToolDefinition(
            name: "request_camera_frame",
            description: "Request a fresh photo from the cook's camera when you need to see the food before answering.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "end_session",
            description: "End the cooking session. Call only when the cook says they are finished or asks to stop.",
            parameters: emptySchema
        ),
    ]

    private static let emptySchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "required": .array([]),
    ])

    private static func schema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
        ])
    }

    // MARK: - Dispatch

    func handle(name: String, argumentsJSON: String) async -> String {
        guard let args = Self.parseArguments(argumentsJSON) else {
            return Self.json(["error": "bad arguments"])
        }
        switch name {
        case "get_current_step": return getCurrentStep()
        case "mark_step_done": return markStepDone()
        case "check_step_actions": return checkStepActions(args)
        case "go_to_step": return goToStep(args)
        case "start_timer": return startTimer(args)
        case "check_timers": return checkTimers()
        case "cancel_timer": return cancelTimer(args)
        case "check_pantry": return checkPantry()
        case "find_substitutes": return findSubstitutes(args)
        case "get_nutrition": return getNutrition()
        case "adjust_servings": return adjustServings(args)
        case "remember_fact": return rememberFact(args)
        case "record_polly_save": return recordPollySave(args)
        case "request_camera_frame": return await requestCameraFrame()
        case "end_session": return endSession()
        default: return Self.json(["error": "unknown tool"])
        }
    }

    // MARK: - Steps

    private func clampedIndex(_ index: Int) -> Int {
        min(max(index, 0), max(plan.steps.count - 1, 0))
    }

    private func stepPayload(at index: Int) -> [String: Any] {
        let step = plan.steps[index]
        let actions = StepActionChecklist.items(for: step, plan: plan)
        let actionPayload: [[String: Any]] = actions.map { item in
            [
                "id": item.id,
                "text": item.text,
                "checked": state.checkedActionIDs.contains(item.id),
                "isVisualCheck": item.isVisualCheck,
            ]
        }
        var payload: [String: Any] = [
            "index": index,
            "total": plan.steps.count,
            "title": step.title,
            "instruction": step.instruction,
            "kind": step.kind.rawValue,
            "ingredients": step.ingredientNames,
            "actions": actionPayload,
            "actionsRemaining": actions.filter { !state.checkedActionIDs.contains($0.id) }.count,
        ]
        if let timerSeconds = step.timerSeconds { payload["timerSeconds"] = timerSeconds }
        if let visualCheck = step.visualCheck { payload["visualCheck"] = visualCheck }
        return payload
    }

    private func getCurrentStep() -> String {
        guard !plan.steps.isEmpty else { return Self.json(["done": true]) }
        return Self.json(stepPayload(at: clampedIndex(state.stepIndex)))
    }

    private func markStepDone() -> String {
        guard !plan.steps.isEmpty else { return Self.json(["done": true]) }
        let current = clampedIndex(state.stepIndex)
        let step = plan.steps[current]
        // Checking the whole step off also clears its checklist rows.
        for item in StepActionChecklist.items(for: step, plan: plan) {
            state.checkedActionIDs.insert(item.id)
        }
        state.completedStepIDs.insert(step.id)
        guard current + 1 < plan.steps.count else {
            state.stepIndex = current
            return Self.json(["done": true])
        }
        state.stepIndex = current + 1
        return Self.json(stepPayload(at: state.stepIndex))
    }

    private func checkStepActions(_ args: [String: Any]) -> String {
        guard !plan.steps.isEmpty else { return Self.json(["error": "no plan"]) }
        let checked = (args["checked"] as? Bool) ?? true
        var ids = (args["item_ids"] as? [String]) ?? []
        let matches = (args["matches"] as? [String]) ?? []

        let step = plan.steps[clampedIndex(state.stepIndex)]
        let items = StepActionChecklist.items(for: step, plan: plan)
        let known = Set(items.map(\.id))

        ids = ids.filter { known.contains($0) }
        ids.append(contentsOf: StepActionChecklist.matchingIDs(matches: matches, in: items))

        // Dedupe while preserving order.
        var seen = Set<String>()
        ids = ids.filter { seen.insert($0).inserted }

        guard !ids.isEmpty else {
            return Self.json([
                "error": "no matching actions",
                "hint": "Use ids or match words from get_current_step.actions",
                "actions": items.map { ["id": $0.id, "text": $0.text] },
            ])
        }

        for id in ids {
            if checked {
                state.checkedActionIDs.insert(id)
            } else {
                state.checkedActionIDs.remove(id)
            }
        }

        let remaining = items.filter { !state.checkedActionIDs.contains($0.id) }.count
        return Self.json([
            "updated": ids,
            "checked": checked,
            "actionsRemaining": remaining,
            "allDone": remaining == 0,
        ])
    }

    private func goToStep(_ args: [String: Any]) -> String {
        guard !plan.steps.isEmpty else { return Self.json(["done": true]) }
        guard let index = (args["index"] as? NSNumber)?.intValue else {
            return Self.json(["error": "bad arguments"])
        }
        state.stepIndex = clampedIndex(index)
        return Self.json(stepPayload(at: state.stepIndex))
    }

    /// Touch / swipe navigation from the session UI (same clamp as the tool).
    func jumpToStep(_ index: Int) {
        guard !plan.steps.isEmpty else { return }
        state.stepIndex = clampedIndex(index)
    }

    func toggleActionChecked(_ id: String) {
        if state.checkedActionIDs.contains(id) {
            state.checkedActionIDs.remove(id)
        } else {
            state.checkedActionIDs.insert(id)
        }
    }

    // MARK: - Timers

    private func startTimer(_ args: [String: Any]) -> String {
        guard let label = args["label"] as? String, !label.isEmpty,
              let seconds = (args["seconds"] as? NSNumber)?.intValue, seconds > 0 else {
            return Self.json(["error": "bad arguments"])
        }
        timers.start(label: label, seconds: seconds)
        return Self.json(["started": true, "label": label, "seconds": seconds])
    }

    private func checkTimers() -> String {
        let now = Date()
        let running: [[String: Any]] = timers.timers.map { timer in
            ["label": timer.label, "remainingSeconds": timer.remainingSeconds(at: now)]
        }
        return Self.json(["timers": running])
    }

    private func cancelTimer(_ args: [String: Any]) -> String {
        guard let label = args["label"] as? String, !label.isEmpty else {
            return Self.json(["error": "bad arguments"])
        }
        guard let timer = timers.timers.first(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        }) else {
            return Self.json(["error": "no such timer"])
        }
        timers.cancel(timer)
        return Self.json(["cancelled": true, "label": timer.label])
    }

    // MARK: - Pantry + substitutions

    private func checkPantry() -> String {
        let match = PantryMatcher.match(recipe: recipe, pantry: pantry)
        return Self.json([
            "ownedCount": match.ownedCount,
            "totalCount": match.totalCount,
            "missing": match.missing.map(\.name),
            "missingOptional": match.missingOptional.map(\.name),
        ])
    }

    private func findSubstitutes(_ args: [String: Any]) -> String {
        guard let ingredient = args["ingredient"] as? String, !ingredient.isEmpty else {
            return Self.json(["error": "bad arguments"])
        }
        let substitutes = SubstitutionService.availableSubstitutions(
            for: ingredient,
            pantry: pantry,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies
        )
        return Self.json([
            "substitutes": substitutes.map { ["name": $0.name, "explanation": $0.explanation] },
            "isEssential": SubstitutionService.isEssential(ingredient),
        ])
    }

    // MARK: - Nutrition + servings

    private func getNutrition() -> String {
        if let calories = recipe.calories {
            var payload: [String: Any] = ["available": true, "calories": calories]
            if let protein = recipe.proteinGrams { payload["protein"] = protein }
            return Self.json(payload)
        }
        guard let estimate = NutritionEstimator.estimate(for: recipe) else {
            return Self.json(["available": false])
        }
        return Self.json([
            "available": true,
            "calories": estimate.calories,
            "protein": estimate.proteinGrams,
            "confidence": estimate.confidence,
        ])
    }

    private func adjustServings(_ args: [String: Any]) -> String {
        guard let servings = (args["servings"] as? NSNumber)?.intValue, servings > 0 else {
            return Self.json(["error": "bad arguments"])
        }
        state.servings = servings
        return Self.json([
            "servings": servings,
            "scaleFromOriginal": Double(servings) / Double(max(1, recipe.servings)),
        ])
    }

    // MARK: - Memory

    private func rememberFact(_ args: [String: Any]) -> String {
        guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return Self.json(["error": "bad arguments"])
        }
        let kind = (args["kind"] as? String).flatMap(MemoryKind.init(rawValue:)) ?? .outcome
        let confidence = (args["confidence"] as? NSNumber)?.doubleValue ?? 0.7
        PollyMemoryStore.upsert(
            kind: kind,
            text: text,
            confidence: min(max(confidence, 0), 1),
            sourceRecipeTitle: recipe.title,
            in: context
        )
        if text.lowercased().hasPrefix("substituted") {
            state.substitutions.append(text)
            appendSave("Worked around a missing ingredient")
        }
        return Self.json(["remembered": true])
    }

    private func recordPollySave(_ args: [String: Any]) -> String {
        guard let moment = (args["moment"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              moment.count >= 6 else {
            return Self.json(["error": "bad arguments"])
        }
        appendSave(moment)
        return Self.json(["saved": true, "count": state.pollySaves.count])
    }

    private func appendSave(_ moment: String) {
        let cleaned = moment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 6 else { return }
        let key = cleaned.lowercased()
        if state.pollySaves.contains(where: { $0.lowercased() == key }) { return }
        state.pollySaves.append(cleaned)
    }

    // MARK: - Camera + session

    private func requestCameraFrame() async -> String {
        guard let onRequestFrame else {
            return Self.json(["captured": false, "reason": "camera unavailable"])
        }
        let captured = await onRequestFrame()
        return captured
            ? Self.json(["captured": true])
            : Self.json(["captured": false, "reason": "camera is off or no frame yet — ask the cook to tap the camera button to show you"])
    }

    private func endSession() -> String {
        onEndSession?()
        return Self.json(["ending": true])
    }

    // MARK: - JSON plumbing

    /// Lenient argument parsing: empty string means "no arguments"; anything
    /// that isn't a JSON object is rejected (the caller answers the model
    /// with {"error":"bad arguments"} so it can retry).
    private static func parseArguments(_ json: String) -> [String: Any]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"encoding failed"}"#
        }
        return string
    }
}
