import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// ContentGraph.swift  (Rext Roadmap Phase 3 — Universal Content Graph)
//
// The persisted single source of truth. `ContentNode` stores one canonical
// content node; `ContentGraph` is the MainActor façade that normalizes provider
// items into the graph and reads them back as neutral `Content` values.
//
// Composite value types (metadata, availability, relationships) are persisted as
// JSON `Data` with typed accessors — robust across SwiftData versions and trivial
// to evolve, while keeping the graph a single @Model type to register.
// ---------------------------------------------------------------------------

@Model
final class ContentNode {
    @Attribute(.unique) var contentID: String
    var title: String
    var kindRaw: String
    var artworkURL: String?
    var createdAt: Date
    var updatedAt: Date

    // Encoded composites (see typed accessors below).
    private var metadataData: Data
    private var availabilityData: Data
    private var relationshipsData: Data

    init(
        contentID: String,
        title: String,
        kind: CatalogKind,
        artworkURL: String?,
        metadata: ContentMetadata,
        availability: [ProviderAvailability],
        relationships: [ContentRelationship] = [],
        createdAt: Date = .now
    ) {
        self.contentID = contentID
        self.title = title
        self.kindRaw = kind.rawValue
        self.artworkURL = artworkURL
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.metadataData = ContentCoding.encode(metadata)
        self.availabilityData = ContentCoding.encode(availability)
        self.relationshipsData = ContentCoding.encode(relationships)
    }

    var kind: CatalogKind { CatalogKind(rawValue: kindRaw) ?? .other }

    var metadata: ContentMetadata {
        get { ContentCoding.decode(metadataData) ?? ContentMetadata() }
        set { metadataData = ContentCoding.encode(newValue) }
    }

    var availability: [ProviderAvailability] {
        get { ContentCoding.decode(availabilityData) ?? [] }
        set { availabilityData = ContentCoding.encode(newValue) }
    }

    var relationships: [ContentRelationship] {
        get { ContentCoding.decode(relationshipsData) ?? [] }
        set { relationshipsData = ContentCoding.encode(newValue) }
    }

    /// The neutral value-type view the rest of the app consumes.
    var content: Content {
        Content(
            id: ContentID(rawValue: contentID),
            title: title,
            kind: kind,
            artworkURL: artworkURL,
            metadata: metadata,
            availability: availability,
            relationships: relationships
        )
    }
}

/// Shared JSON coder for the graph's composite value types.
private enum ContentCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// ---------------------------------------------------------------------------
// ContentGraph — the ingestion + query façade. MainActor because it reads the
// app's ModelContext; it returns actor-agnostic value types.
// ---------------------------------------------------------------------------

@MainActor
struct ContentGraph {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Ingestion

    /// Normalize a provider item into the graph, returning its canonical id.
    /// Re-ingesting the same locator enriches the existing node instead of
    /// duplicating it (the graph only ever grows more complete).
    @discardableResult
    func ingest(_ item: CatalogItem, extensionID: String) -> ContentID {
        let id = ContentID.provider(extensionID: extensionID, itemID: item.id)
        let availability = ProviderAvailability(extensionID: extensionID, itemID: item.id)

        if let node = node(for: id) {
            node.metadata = node.metadata.merged(with: item.resolvedMetadata)
            registerAvailability(availability, on: node)
            if !item.title.isEmpty { node.title = item.title }
            if let art = item.artworkUrl { node.artworkURL = art }
            node.updatedAt = .now
        } else {
            context.insert(ContentNode(
                contentID: id.rawValue,
                title: item.title,
                kind: item.kind,
                artworkURL: item.artworkUrl,
                metadata: item.resolvedMetadata,
                availability: [availability]
            ))
        }
        return id
    }

    /// Ingest full details plus any child episodes, linking each episode back to
    /// its parent with an `.episodeOf` relationship.
    @discardableResult
    func ingest(_ details: MediaDetails, extensionID: String) -> ContentID {
        let parentID = ingest(
            CatalogItem(
                id: details.id, title: details.title, subtitle: details.subtitle,
                artworkUrl: details.artworkUrl, kind: details.kind,
                metadata: details.metadata, canonical: details.canonical
            ),
            extensionID: extensionID
        )
        for episode in details.episodes ?? [] {
            let episodeID = ingest(episode, extensionID: extensionID)
            relate(episodeID, to: parentID, as: .episodeOf)
        }
        return parentID
    }

    // MARK: - Relationships

    /// Add a directed relationship if it isn't already present.
    func relate(_ source: ContentID, to target: ContentID, as type: ContentRelationshipType) {
        guard source != target, let node = node(for: source) else { return }
        let relationship = ContentRelationship(type: type, target: target)
        guard !node.relationships.contains(relationship) else { return }
        node.relationships.append(relationship)
        node.updatedAt = .now
    }

    /// Ids related to `id`, optionally filtered by relationship type.
    func related(to id: ContentID, type: ContentRelationshipType? = nil) -> [ContentID] {
        guard let node = node(for: id) else { return [] }
        return node.relationships
            .filter { type == nil || $0.type == type }
            .map(\.targetID)
    }

    /// Fold a duplicate node's provider availability + metadata into `primary`
    /// (the canonical superset), and record a `.sameAs` link from the duplicate
    /// back to the primary. The duplicate node is kept so any `ContentID` already
    /// held elsewhere still resolves — callers can follow `.sameAs` to the primary.
    func merge(_ duplicate: ContentID, into primary: ContentID) {
        guard duplicate != primary,
              let dupeNode = node(for: duplicate),
              let primaryNode = node(for: primary) else { return }

        primaryNode.metadata = primaryNode.metadata.merged(with: dupeNode.metadata)
        for availability in dupeNode.availability {
            registerAvailability(availability, on: primaryNode)
        }
        primaryNode.updatedAt = .now
        relate(duplicate, to: primary, as: .sameAs)
    }

    // MARK: - Queries

    func content(for id: ContentID) -> Content? { node(for: id)?.content }

    func allContent() -> [Content] {
        let nodes = (try? context.fetch(FetchDescriptor<ContentNode>())) ?? []
        return nodes.map(\.content)
    }

    // MARK: - Internals

    private func node(for id: ContentID) -> ContentNode? {
        let raw = id.rawValue
        let descriptor = FetchDescriptor<ContentNode>(predicate: #Predicate { $0.contentID == raw })
        return try? context.fetch(descriptor).first
    }

    private func registerAvailability(_ availability: ProviderAvailability, on node: ContentNode) {
        let exists = node.availability.contains {
            $0.extensionID == availability.extensionID && $0.itemID == availability.itemID
        }
        guard !exists else { return }
        node.availability.append(availability)
    }
}
