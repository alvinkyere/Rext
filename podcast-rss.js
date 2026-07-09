// ---------------------------------------------------------------------------
// podcast-rss.js - GOLDEN REFERENCE CONNECTOR
//
// This is the canonical implementation of the Runtime SDK. Study this as the
// definitive example of how to write a connector.
//
// CAPABILITIES:
// The ONLY capabilities available are on the injected `Runtime` global:
//   - Runtime.request(input) -> Promise<RuntimeResponse>
//   - Runtime.storage.get(key) -> Promise<string | null>
//   - Runtime.storage.set(key, value) -> Promise<void>
//   - Runtime.storage.delete(key) -> Promise<void>
//   - Runtime.log(...args) -> void
//
// There is NO fetch, filesystem, DOM, or access to other connectors.
// Requests to domains not in manifest.json are blocked by the host.
//
// CONTRACT:
// A connector implements:
//   - search(query, page?) -> Promise<CatalogItem[]>
//   - getDetails(id) -> Promise<MediaDetails>
//   - getStreams(itemId, episodeId?) -> Promise<StreamSource[]>
//
// ERROR HANDLING:
// Throw structured errors with a `code` property for better host UI:
//   - NOT_FOUND, AUTH_REQUIRED, UPSTREAM_ERROR, etc.
// ---------------------------------------------------------------------------

(function (global) {
  "use strict";

  var API = "https://api.example-podcasts.com";

  function fail(code, message) {
    var e = new Error(message);
    e.code = code;
    return e;
  }

  async function getJSON(url) {
    var res = await Runtime.request({ url: url });
    if (res.status === 404) throw fail("NOT_FOUND", "Resource not found: " + url);
    if (res.status === 401 || res.status === 403)
      throw fail("AUTH_REQUIRED", "The source requires authentication.");
    if (res.status >= 400)
      throw fail("UPSTREAM_ERROR", "Source returned HTTP " + res.status);
    try {
      return JSON.parse(res.body);
    } catch (_) {
      throw fail("INVALID_RESPONSE", "Source returned non-JSON body.");
    }
  }

  var connector = {
    async search(query, page) {
      var p = page || 1;
      var url = API + "/search?q=" + encodeURIComponent(query) + "&page=" + p;
      var data = await getJSON(url);

      // Demonstrate namespaced storage
      await Runtime.storage.set("lastQuery", query);

      return (data.results || []).map(function (r) {
        return {
          id: r.id,
          title: r.title,
          subtitle: r.author,
          artworkUrl: r.artwork,
          kind: "podcast",
          metadata: { episodeCount: r.episodeCount }
        };
      });
    },

    async getDetails(id) {
      var data = await getJSON(API + "/show/" + encodeURIComponent(id));
      return {
        id: data.id,
        title: data.title,
        subtitle: data.author,
        artworkUrl: data.artwork,
        kind: "podcast",
        description: data.description,
        tags: data.categories,
        releaseDate: data.firstAired,
        episodes: (data.episodes || []).map(function (e) {
          return {
            id: e.id,
            title: e.title,
            number: e.number,
            durationSec: e.durationSec
          };
        })
      };
    },

    async getStreams(itemId, episodeId) {
      if (!episodeId)
        throw fail("NOT_FOUND", "A podcast episode id is required to stream.");
      var data = await getJSON(
        API + "/episode/" + encodeURIComponent(episodeId) + "/stream"
      );
      if (!data.streamUrl)
        throw fail("NOT_FOUND", "No stream available for this episode.");
      return [
        {
          url: data.streamUrl,
          type: "progressive",
          quality: data.bitrate ? data.bitrate + "kbps" : undefined
        }
      ];
    }
  };

  global.connectorInstance = connector;
})(typeof globalThis !== "undefined" ? globalThis : this);
