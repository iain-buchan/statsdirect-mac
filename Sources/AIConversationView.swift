import Cocoa
import WebKit

/// A local, read-only HTML transcript. Native state survives WebKit termination;
/// recreating this view never resubmits a question or grants document access.
@MainActor final class AIConversationView: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let view=NSView()
    private(set) var web: WKWebView!
    private let root: URL
    private var ready=false
    private var state: [String:Any]=[:]
    var openR: ((String,String,Int)->Void)?
    var copyCode: ((String,String,String)->Void)?
    init(root: URL) { self.root=root;super.init();install() }
    private var page: URL { root.appendingPathComponent("AI/index.html").standardizedFileURL }
    private func install() {
        if let web {
            web.stopLoading();web.navigationDelegate=nil;web.uiDelegate=nil
            web.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectAI");web.removeFromSuperview()
        }
        ready=false
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically=false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(self,name:"statsDirectAI")
        web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self;web.uiDelegate=self
        web.setAccessibilityLabel("AI conversation");web.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(web)
        NSLayoutConstraint.activate([web.topAnchor.constraint(equalTo:view.topAnchor),web.bottomAnchor.constraint(equalTo:view.bottomAnchor),web.leadingAnchor.constraint(equalTo:view.leadingAnchor),web.trailingAnchor.constraint(equalTo:view.trailingAnchor)])
        web.loadFileURL(page,allowingReadAccessTo:root)
    }
    func render(_ value: [String:Any]) { state=value;flush() }
    private func flush() {
        guard ready,!state.isEmpty else { return }
        let target=web!,payload=state
        Task { @MainActor in _ = try? await target.callAsyncJavaScript("window.StatsDirectAIConversation.render(payload)",arguments:["payload":payload],in:nil,contentWorld:.page) }
    }
    func userContentController(_ controller: WKUserContentController,didReceive message: WKScriptMessage) {
        guard message.webView === web,message.frameInfo.isMainFrame,message.frameInfo.request.url?.standardizedFileURL == page,
              let body=message.body as? [String:Any],let action=body["action"] as? String else { return }
        if action=="ready" { ready=true;flush();return }
        guard let generation=body["generation"] as? String,let id=body["messageID"] as? String else { return }
        if action=="openR",let index=body["blockIndex"] as? Int,index>=0 { openR?(generation,id,index) }
        else if action=="copyCode",let code=body["code"] as? String { copyCode?(generation,id,code) }
    }
    func webView(_ webView: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        guard let url=action.request.url else { decisionHandler(.cancel);return }
        if action.navigationType == .other,action.targetFrame?.isMainFrame == true,url.standardizedFileURL==page { decisionHandler(.allow);return }
        if action.navigationType == .linkActivated,["https","http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView,createWebViewWith configuration: WKWebViewConfiguration,for action: WKNavigationAction,windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView,requestMediaCapturePermissionFor origin: WKSecurityOrigin,initiatedByFrame frame: WKFrameInfo,type: WKMediaCaptureType,decisionHandler: @escaping (WKPermissionDecision)->Void) { decisionHandler(.deny) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === web { install() } }
    func shutdown() { web.stopLoading();web.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectAI");web.navigationDelegate=nil;web.uiDelegate=nil }
}
