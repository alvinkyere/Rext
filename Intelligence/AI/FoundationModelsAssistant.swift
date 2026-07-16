import Foundation

// ---------------------------------------------------------------------------
// FoundationModelsAssistant.swift  (Rext Roadmap Phase 10 — AI Platform)
//
// The Apple Intelligence (on-device) implementation of `AIAssistant`. It uses the
// FoundationModels framework's guided generation to turn a natural-language
// request into a structured `SearchIntent`. The whole file is behind
// `#if canImport(FoundationModels)` so the app still builds on toolchains/targets
// without the framework, and every call checks runtime model availability and
// falls back to the deterministic parser when the model can't run.
// ---------------------------------------------------------------------------

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelsAssistant: AIAssistant {
    let isModelBacked = true
    private let fallback = DeterministicAIAssistant()

    /// The structured output the on-device model fills in via guided generation.
    @Generable
    struct GeneratedSearchIntent {
        @Guide(description: "Core subjects or titles to search for, lowercase, no genre or media-type words")
        var keywords: [String]
        @Guide(description: "Genres mentioned, e.g. Science Fiction, Comedy, Documentary")
        var genres: [String]
        @Guide(description: "Media kinds requested, from: movie, series, episode, video, podcast, music, track, book, stream")
        var kinds: [String]
    }

    private static let instructions = """
        You extract structured search parameters from a person's natural-language \
        request for something to watch, listen to, or read. Return only the \
        parameters present in the request; leave arrays empty when nothing applies.
        """

    func interpretSearch(_ prompt: String) async -> SearchIntent {
        guard case .available = SystemLanguageModel.default.availability else {
            return await fallback.interpretSearch(prompt)
        }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: prompt, generating: GeneratedSearchIntent.self)
            let generated = response.content
            let kinds = generated.kinds.compactMap { CatalogKind(rawValue: $0.lowercased()) }
            let genres = generated.genres.map { GenreVocabulary.canonical(for: $0) }
            let intent = SearchIntent(keywords: generated.keywords, genres: genres, kinds: kinds)
            // If the model returned nothing usable, fall back so search still works.
            return intent == SearchIntent() ? await fallback.interpretSearch(prompt) : intent
        } catch {
            return await fallback.interpretSearch(prompt)
        }
    }

    /// A label describing the current on-device model availability, for the UI.
    static var availabilityLabel: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "On-device (Apple Intelligence)"
        case .unavailable(.deviceNotEligible):
            return "Built-in understanding (device not eligible)"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Built-in understanding (turn on Apple Intelligence)"
        case .unavailable(.modelNotReady):
            return "Built-in understanding (model downloading)"
        case .unavailable:
            return "Built-in understanding"
        }
    }
}
#endif
