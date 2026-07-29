import XCTest
@testable import Glutt

final class StepActionChecklistTests: XCTestCase {

    func testSplitsInstructionIntoActions() {
        let step = CookPlan.PlanStep(
            id: "s1",
            index: 1,
            title: "Sauté onions",
            instruction: "Heat the oil. Add the diced onion. Cook until translucent.",
            kind: .active
        )
        let plan = CookPlan(title: "Pasta", servings: 2, steps: [step])
        let items = StepActionChecklist.items(for: step, plan: plan)

        XCTAssertGreaterThanOrEqual(items.count, 3)
        XCTAssertTrue(items[0].text.localizedCaseInsensitiveContains("heat"))
        XCTAssertTrue(items.contains(where: { $0.text.localizedCaseInsensitiveContains("onion") }))
    }

    func testPrepStepUsesMise() {
        let prep = CookPlan.PlanStep(
            id: CookPlan.prepStepID,
            index: 1,
            title: "Prep",
            instruction: "Before any heat: dice the onion.",
            kind: .prep
        )
        let tools = CookPlan.PlanStep(
            id: CookPlan.toolsStepID,
            index: 0,
            title: "Tools",
            instruction: "Pull out your skillet.",
            kind: .prep
        )
        let plan = CookPlan(
            title: "Pasta",
            servings: 2,
            mise: [
                .init(name: "onion", prep: "dice"),
                .init(name: "garlic", prep: "mince"),
                .init(name: "cumin", prep: "measure"),
            ],
            equipment: ["skillet"],
            steps: [tools, prep]
        )
        // Sanitize path is on ensuringLeadingPrep; checklist for prep uses plan.mise as-is.
        // Tools step = gear only.
        let toolItems = StepActionChecklist.items(for: tools, plan: plan)
        XCTAssertTrue(toolItems.contains(where: { $0.text.localizedCaseInsensitiveContains("skillet") }))
        XCTAssertFalse(toolItems.contains(where: { $0.text.localizedCaseInsensitiveContains("onion") }))

        let prepItems = StepActionChecklist.items(for: prep, plan: plan)
        XCTAssertTrue(prepItems.contains(where: { $0.text.localizedCaseInsensitiveContains("dice the onion") }))
        XCTAssertTrue(prepItems.contains(where: { $0.text.localizedCaseInsensitiveContains("mince the garlic") }))
        XCTAssertFalse(prepItems.contains(where: { $0.text.localizedCaseInsensitiveContains("skillet") }),
                       "tools must not appear on the Prep checklist")
    }

    func testBoardWorkOnlyDropsSpiceMeasuring() {
        let mise: [CookPlan.MiseItem] = [
            .init(name: "onion", prep: "dice"),
            .init(name: "cumin", prep: "measure"),
            .init(name: "paprika", prep: "1 tsp"),
            .init(name: "chicken thighs", prep: "pat dry"),
        ]
        let cleaned = CookPlan.boardWorkOnly(mise)
        XCTAssertEqual(cleaned.map(\.name), ["onion", "chicken thighs"])
    }

    func testVisualCheckAppended() {
        let step = CookPlan.PlanStep(
            id: "s2",
            index: 2,
            title: "Sear",
            instruction: "Sear the chicken 4 minutes per side.",
            kind: .active,
            visualCheck: "Deep golden crust, not pale"
        )
        let plan = CookPlan(title: "Chicken", servings: 2, steps: [step])
        let items = StepActionChecklist.items(for: step, plan: plan)
        XCTAssertTrue(items.contains(where: { $0.isVisualCheck }))
        XCTAssertTrue(items.last?.text.localizedCaseInsensitiveContains("done when") == true)
    }

    func testDoesNotCapLongSteps() {
        let long = (0..<12).map { "Do action number \($0) carefully now." }.joined(separator: ". ")
        let step = CookPlan.PlanStep(
            id: "s3", index: 0, title: "Long", instruction: long, kind: .active
        )
        let plan = CookPlan(title: "x", servings: 1, steps: [step])
        let items = StepActionChecklist.items(for: step, plan: plan)
        XCTAssertGreaterThanOrEqual(items.count, 10, "every instruction bite should appear")
    }

    func testMatchingFindsPluralForms() {
        let items = [
            StepActionChecklist.Item(id: "a", text: "Dice the tomatoes"),
            StepActionChecklist.Item(id: "b", text: "Slice the cucumbers"),
            StepActionChecklist.Item(id: "c", text: "Mince the garlic"),
        ]
        let ids = StepActionChecklist.matchingIDs(
            matches: ["tomatoes", "cucumber"],
            in: items
        )
        XCTAssertEqual(ids, ["a", "b"])
    }
}
