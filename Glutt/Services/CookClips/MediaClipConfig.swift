import Foundation

/// Switches for the step-synced technique clip pipeline.
enum MediaClipConfig {

    /// Whether importing a recipe kicks off clip generation for it.
    ///
    /// Off for the App Store build: import clipping isn't reliable enough to put
    /// in front of a reviewer yet. Nothing about the pipeline has been deleted —
    /// the ingest client, the media worker, the Supabase schema and the whole
    /// analyze path are all still here — so turning this back to `true` is the
    /// only edit needed to resume the work.
    ///
    /// What this does NOT touch, deliberately: playback of clips that already
    /// exist. The bundled chef recipes' clips were generated and reviewed
    /// previously and are read through `NativeClipService`, which asks the server
    /// for approved segments and never enqueues anything. Those keep working.
    static let generatesClipsForImports = false

    /// Whether this recipe may use clips at all — generate, poll, show progress
    /// for, or play.
    ///
    /// With generation off, the answer is yes only for bundled chef dishes. Those
    /// carry clips that were produced and reviewed in an earlier release, and
    /// they must keep playing. A user's own import gets nothing: not a job, not a
    /// progress banner, and not a clip during Cook Mode.
    ///
    /// That last exclusion matters more than it looks. The pipeline is keyed by
    /// media id, not by user, so importing a video someone else already processed
    /// would otherwise surface clips on an import — the exact thing that's meant
    /// to be switched off, appearing only for whichever videos happen to be warm.
    static func clipsAllowed(for recipe: Recipe) -> Bool {
        generatesClipsForImports || recipe.isCuratedRecipe
    }
}
