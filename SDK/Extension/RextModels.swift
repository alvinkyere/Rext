import Foundation

// ---------------------------------------------------------------------------
// RextModels.swift  (Rext Extension SDK)
//
// The standardized vocabulary every extension speaks. Because the host owns all
// UI and rendering, an extension only ever returns these neutral models — the UI
// never knows whether the data came from an RSS feed, a website, or an API.
//
// The item/episode/details/stream contracts already exist as CatalogItem /
// MediaDetails / StreamSource (RuntimeModels.swift); the SDK exposes them under
// `Rext*` names so extension authors program against a consistent vocabulary
// without a data-layer rewrite. `RextResponse` is the only genuinely new type: a
// flexible envelope for the open-ended `execute(action:payload:)` hook.
// ---------------------------------------------------------------------------

/// A content item returned by an extension (search results, listings).
public typealias RextItem = CatalogItem

/// A single episode / chapter / track — an item of `kind: .episode`.
public typealias RextEpisode = CatalogItem

/// Full details for an item, including any child episodes.
public typealias RextDetails = MediaDetails

/// A resolved playable/streamable source.
public typealias RextStream = StreamSource

/// The kind of content an item represents.
public typealias ContentType = CatalogKind

/// The result of the generic `execute(action:payload:)` extension hook. Both
/// fields are optional so source-specific actions can return structured values,
/// a list of items, or both.
public nonisolated struct RextResponse: Sendable, Codable, Equatable {
    public let data: [String: JSONScalar]?
    public let items: [CatalogItem]?

    public init(data: [String: JSONScalar]? = nil, items: [CatalogItem]? = nil) {
        self.data = data
        self.items = items
    }
}

extension JSONScalar {
    /// The underlying Foundation primitive, for handing a `payload` to JavaScript.
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        }
    }
}
