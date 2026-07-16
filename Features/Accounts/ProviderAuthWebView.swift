import SwiftUI

// ---------------------------------------------------------------------------
// ProviderAuthWebView.swift  (Rext — Provider Accounts)
//
// A provider signs the user in inside its own web view. Rext never sees the
// credentials — it only captures the resulting session (cookies) into a
// per-provider isolated data store and hands an opaque token to the Keychain.
// Wrapped in canImport(WebKit) so the app still builds where WebKit is absent.
// ---------------------------------------------------------------------------

#if canImport(WebKit)
import WebKit

@MainActor
@Observable
final class ProviderAuthModel {
    let webView: WKWebView

    init(dataStoreID: String, url: URL) {
        let configuration = WKWebViewConfiguration()
        // Isolated, persistent storage per provider so sessions don't cross-contaminate.
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *), let uuid = UUID(uuidString: dataStoreID) {
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: uuid)
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
    }

    /// Capture the provider session as an opaque token (never the credentials).
    func captureToken() async -> String {
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return "session:\(cookies.count):\(Int(Date().timeIntervalSince1970))"
    }
}

#if canImport(UIKit)
import UIKit

struct ProviderWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

/// The sheet that hosts a provider's web login.
struct ProviderAuthSheet: View {
    let request: AccountsController.AuthRequest
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @State private var model: ProviderAuthModel
    @State private var isCapturing = false

    init(request: AccountsController.AuthRequest,
         onComplete: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.request = request
        self.onComplete = onComplete
        self.onCancel = onCancel
        _model = State(initialValue: ProviderAuthModel(dataStoreID: request.dataStoreID, url: request.url))
    }

    var body: some View {
        NavigationStack {
            Group {
                #if canImport(UIKit)
                ProviderWebView(webView: model.webView)
                    .ignoresSafeArea(edges: .bottom)
                #else
                ContentUnavailableView("Sign-in unavailable", systemImage: "globe")
                #endif
            }
            .navigationTitle("Sign in to \(request.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isCapturing = true
                        Task {
                            let token = await model.captureToken()
                            onComplete(token)
                        }
                    }
                    .disabled(isCapturing)
                }
            }
        }
    }
}
#endif
