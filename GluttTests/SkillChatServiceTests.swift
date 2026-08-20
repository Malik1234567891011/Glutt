import Testing
@testable import Glutt

struct SkillChatServiceTests {

    private var skill: Skill {
        SkillCatalog.authoredSkills.first { $0.lesson?.watchFors.isEmpty == false }!
    }

    // MARK: - Thread identity

    /// Skill threads share `RecipeChatMessage` with recipe threads. The prefix
    /// is the only thing keeping a lesson's conversation out of a recipe's.
    @Test func threadKeysArePrefixedAndUnique() {
        let keys = SkillCatalog.authoredSkills.map(SkillChatService.familyKey(for:))
        #expect(keys.allSatisfy { $0.hasPrefix("skill:") })
        #expect(Set(keys).count == keys.count)
    }

    // MARK: - Chips

    /// Three at most, and none of them a question the lesson already answers in
    /// a section header. "Why does this work?" used to sit directly under "Why
    /// this matters" and reliably got back a paraphrase of it.
    @Test func chipsAreFewAndDoNotDuplicateTheLesson() {
        for skill in SkillCatalog.authoredSkills {
            let chips = SkillChatService.suggestions(for: skill)
            #expect(chips.count <= 3)
            #expect(!chips.isEmpty)
            #expect(!chips.contains("Why does this work?"))
        }
    }

    // MARK: - Prompt

    @Test func promptCarriesTheLessonTheCookIsLookingAt() throws {
        let skill = skill
        let lesson = try #require(skill.lesson)
        let prompt = SkillChatService.systemPrompt(skill: skill, prefs: UserPrefs())

        #expect(prompt.contains(skill.title))
        #expect(prompt.contains(lesson.summary))
        #expect(prompt.contains(lesson.whyItMatters))
        for step in lesson.steps { #expect(prompt.contains(step)) }
        for watch in lesson.watchFors { #expect(prompt.contains(watch)) }
    }

    /// A mapped but unwritten skill still opens. Polly has to be told the screen
    /// is a placeholder, or she answers as though a lesson were on it.
    @Test func promptSaysWhenTheLessonIsNotWrittenYet() throws {
        let unwritten = try #require(SkillCatalog.allSkills.first { $0.lesson == nil })
        let prompt = SkillChatService.systemPrompt(skill: unwritten, prefs: UserPrefs())
        #expect(prompt.contains("not finished yet"))
    }

    /// Examples have to be food they would actually cook.
    @Test func promptCarriesFoodRules() {
        var prefs = UserPrefs()
        prefs.dietaryRules = [.vegetarian]
        prefs.allergies = ["peanuts"]
        let prompt = SkillChatService.systemPrompt(skill: skill, prefs: prefs)
        #expect(prompt.contains("Vegetarian"))
        #expect(prompt.contains("peanuts"))
    }

    /// No preferences means no section, rather than an empty heading burning
    /// tokens on every single turn.
    @Test func promptOmitsFoodRulesWhenThereAreNone() {
        let prompt = SkillChatService.systemPrompt(skill: skill, prefs: UserPrefs())
        #expect(!prompt.contains("# The cook"))
    }

    /// The house rule is in `.claude/rules/ui-copy.md` and applies to anything
    /// a cook reads, which includes whatever Polly writes back.
    @Test func promptForbidsDashes() {
        let prompt = SkillChatService.systemPrompt(skill: skill, prefs: UserPrefs())
        #expect(prompt.contains("Never use dashes"))
    }

    /// Skill chat is billed separately from recipe chat so its cost can be read
    /// on its own in `ai_usage`.
    @Test func spendIsTaggedSeparatelyFromRecipeChat() {
        #expect(SkillChatService.usageFeature != RecipeChatService.usageFeature)
    }
}
