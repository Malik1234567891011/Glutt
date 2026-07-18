import Foundation

/// Photo food logging: a picture of the plate → meal name + honest calorie
/// range + protein estimate. Always editable before it's logged — the AI
/// proposes, the user disposes.
enum MealPhotoEstimator {

    struct Estimate: Decodable {
        let title: String
        let calories: Int
        let caloriesLow: Int?
        let caloriesHigh: Int?
        let proteinGrams: Int
        /// One short sentence on what drove the estimate ("large portion, fried").
        let note: String?

        var rangeLabel: String? {
            guard let caloriesLow, let caloriesHigh, caloriesLow < caloriesHigh else { return nil }
            return "likely \(caloriesLow)–\(caloriesHigh) cal"
        }
    }

    static func estimate(imageData: Data, client: LLMClient = .live) async throws -> Estimate {
        let system = """
        You estimate nutrition from a photo of a meal someone is about to eat.
        Return JSON: {"title": str, "calories": int, "caloriesLow": int, "caloriesHigh": int,
         "proteinGrams": int, "note": str}

        Rules:
        - title: short, natural meal name ("Chicken burrito bowl", "Big Mac meal").
        - calories: your single best estimate for the WHOLE visible portion.
        - caloriesLow/caloriesHigh: an honest range; food photos are ambiguous, don't fake precision.
        - proteinGrams: best estimate.
        - note: one short sentence about portion or preparation that drove the numbers.
        - If the photo clearly contains no food, return {"title": ""}.
        """

        let estimate = try await client.chatJSON(
            Estimate.self,
            system: system,
            user: "Estimate this meal.",
            imageData: imageData,
            timeout: 45
        )
        guard !estimate.title.isEmpty, estimate.calories > 0 else {
            throw LLMClient.LLMError.badResponse("No food recognized in the photo")
        }
        return estimate
    }
}
