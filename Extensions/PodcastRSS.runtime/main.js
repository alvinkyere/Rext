// ---------------------------------------------------------------------------
// PodcastRSS.runtime / main.js  — GOLDEN REFERENCE EXTENSION (Runtime SDK v1)
//
// The canonical example of a Runtime extension. Study this as the definitive
// pattern for connector authors.
//
// HOST CAPABILITIES (the only things available, on the injected `Runtime` global)
//   - Runtime.request(input)      -> Promise<{ status, headers, body }>
//   - Runtime.storage.get(key)    -> Promise<string | null>
//   - Runtime.storage.set(key, v) -> Promise<void>      (rejects if over quota)
//   - Runtime.storage.delete(key) -> Promise<void>
//   - Runtime.log(...args)        -> void
//
// There is NO fetch, filesystem, DOM, or access to other extensions. Requests to
// hosts not in the manifest's network allowlist are blocked by the host in Swift.
//
// CONTRACT (methods gated by the manifest's declared capabilities)
//   - search(query, page?)          -> Promise<CatalogItem[]>     (capability: search)
//   - getDetails(id)                -> Promise<MediaDetails>      (capability: details)
//   - getStreams(itemId, episodeId?)-> Promise<StreamSource[]>    (capability: streams)
//
// ERROR HANDLING
//   Throw an Error carrying a `code` property; the host maps it to a structured
//   ConnectorError (NOT_FOUND, AUTH_REQUIRED, UPSTREAM_ERROR, INVALID_RESPONSE…).
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
      throw fail("INVALID_RESPONSE", "Source returned a non-JSON body.");
    }
  }

  var connector = {
    async search(query, page) {
      var p = page || 1;
      var url = API + "/search?q=" + encodeURIComponent(query) + "&page=" + p;
      var data = await getJSON(url);

      // Demonstrate namespaced storage.
      await Runtime.storage.set("lastQuery", String(query));

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
        backdropUrl: data.artwork,
        kind: "podcast",
        metadata: {
          overview: data.description || "",
          genres: (data.categories || []).join(", "),
          firstAired: data.firstAired || ""
        },
        episodes: (data.episodes || []).map(function (e) {
          return {
            id: e.id,
            title: e.title,
            subtitle: null,
            artworkUrl: data.artwork,
            kind: "episode",
            metadata: {
              number: e.number,
              durationSec: e.durationSec,
              parentId: data.id
            }
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
          id: "audio-" + episodeId,
          url: data.streamUrl,
          quality: data.bitrate ? data.bitrate + " kbps" : null,
          format: "mp3",
          metadata: data.bitrate ? { bitrate: data.bitrate } : null
        }
      ];
    }
  };

  global.connectorInstance = connector;
})(typeof globalThis !== "undefined" ? globalThis : this);
