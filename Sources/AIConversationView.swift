import Cocoa
import WebKit

/// A local, read-only HTML transcript. Native state survives WebKit termination;
/// recreating this view never resubmits a question or grants document access.
@MainActor final class AIConversationView: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    let view=NSView()
    private(set) var web: WKWebView!
    private let root: URL
    private var ready=false
    private var retried=false
    private var stopped=false
    private var renderPending=false
    private var renderInFlight=false
    private var displayTimeout: Task<Void,Never>?
    private var state: [String:Any]=[:]
    private var failureNotice: NSStackView!
    /// Open in R on a block: generation, message, the block's place among the message's R blocks, and the code as the page shows it.
    var openR: ((String,String,Int,String?)->Void)?
    /// Copy on a block: generation, message and the code as the page shows it. Answers whether anything was copied.
    var copyCode: ((String,String,String)->Bool)?
    init(root: URL) {
        // WebKit checks the requested file against its read-access directory.
        // Use the same path spelling for both (including /private/var aliases).
        self.root=root.resolvingSymlinksInPath().standardizedFileURL;super.init()
        let message=NSTextField(wrappingLabelWithString:"The conversation could not be displayed. Your messages are kept.")
        let retry=NSButton(title:"Reload Conversation",target:self,action:#selector(retryDisplay))
        failureNotice=NSStackView(views:[message,retry])
        failureNotice.orientation = .vertical;failureNotice.alignment = .leading
        failureNotice.translatesAutoresizingMaskIntoConstraints=false;failureNotice.isHidden=true
        view.addSubview(failureNotice)
        NSLayoutConstraint.activate([failureNotice.topAnchor.constraint(equalTo:view.topAnchor,constant:8),
            failureNotice.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:8),
            failureNotice.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-8),
            message.widthAnchor.constraint(equalTo:failureNotice.widthAnchor)])
        install()
    }
    private var page: URL { root.appendingPathComponent("AI/index.html").standardizedFileURL }
    private func install() {
        displayTimeout?.cancel();renderInFlight=false
        if let web {
            web.navigationDelegate=nil;web.uiDelegate=nil;web.stopLoading()
            web.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectAI")
            web.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectAICopy",contentWorld:.page);web.removeFromSuperview()
        }
        ready=false;failureNotice.isHidden=true
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically=false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(self,name:"statsDirectAI")
        // Copy answers the page, so that "Copied" is shown only when something was copied.
        config.userContentController.addScriptMessageHandler(self,contentWorld:.page,name:"statsDirectAICopy")
        web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self;web.uiDelegate=self
        web.setAccessibilityLabel("AI conversation");web.translatesAutoresizingMaskIntoConstraints=false;web.isHidden = !state.isEmpty
        view.addSubview(web,positioned:.below,relativeTo:failureNotice)
        NSLayoutConstraint.activate([web.topAnchor.constraint(equalTo:view.topAnchor),web.bottomAnchor.constraint(equalTo:view.bottomAnchor),web.leadingAnchor.constraint(equalTo:view.leadingAnchor),web.trailingAnchor.constraint(equalTo:view.trailingAnchor)])
        web.loadFileURL(page,allowingReadAccessTo:root)
        watchDisplay(web)
    }
    private func watchDisplay(_ target: WKWebView) {
        displayTimeout?.cancel()
        displayTimeout=Task { @MainActor [weak self, weak target] in
            try? await Task.sleep(for:.seconds(5))
            guard !Task.isCancelled, let self, let target else { return }
            self.recoverDisplay(target)
        }
    }
    @objc private func retryDisplay() { guard !stopped else { return };retried=false;install() }
    private func recoverDisplay(_ target: WKWebView) {
        guard !stopped,target === web,failureNotice.isHidden else { return }
        ready=false;displayTimeout?.cancel();renderInFlight=false
        if !retried { retried=true;install();return }
        target.stopLoading();target.isHidden=true;failureNotice.isHidden=false
    }
    private func displayReady(_ target: WKWebView) {
        guard !stopped,target === web,!ready,failureNotice.isHidden else { return }
        ready=true;displayTimeout?.cancel();flush()
    }
    func render(_ value: [String:Any]) {
        if value["generation"] as? String != state["generation"] as? String {
            retried=false
            // A pending render must not leave the old document's transcript
            // on screen while the new conversation is loaded.
            web.isHidden=true
        }
        state=value;renderPending=true;flush()
    }
    private func flush() {
        guard ready,!state.isEmpty,!renderInFlight else { return }
        renderPending=false;renderInFlight=true
        let target=web!,payload=state
        watchDisplay(target)
        // A formatting error must not hide a received reply. Render text
        // safely in the local browser if the rich renderer fails.
        target.callAsyncJavaScript("""
                try {
                    await window.StatsDirectAIConversation.render(payload);
                } catch {
                    const container = document.getElementById('messages');
                    if (!container) return false;
                    const fragment = document.createDocumentFragment();
                    const note = document.createElement('p');
                    note.textContent = 'Rich formatting is unavailable.';
                    fragment.append(note);
                    if (!payload.messages.length) {
                        const intro = document.createElement('p');
                        intro.textContent = payload.introduction;
                        fragment.append(intro);
                    }
                    for (const row of payload.messages) {
                        const heading = document.createElement('strong');
                        heading.textContent = row.role === 'user' ? 'You' : 'ChatGPT';
                        fragment.append(heading);
                        if (row.context) {
                            const scope = document.createElement('p');
                            scope.className = 'scope';
                            scope.textContent = row.context;
                            fragment.append(scope);
                        }
                        const body = document.createElement('p');
                        body.style.whiteSpace = 'pre-wrap';
                        body.textContent = row.text;
                        fragment.append(body);
                    }
                    container.replaceChildren(fragment);
                    container.scrollTop = container.scrollHeight;
                }
                return true;
                """,arguments:["payload":payload],in:nil,in:.page) { [weak self, weak target] result in
            guard let self,let target,self.ready,target === self.web else { return }
            self.displayTimeout?.cancel();self.renderInFlight=false
            guard case let .success(value)=result,value as? Bool==true else { self.recoverDisplay(target);return }
            if payload["generation"] as? String == self.state["generation"] as? String { target.isHidden=false }
            if self.renderPending { self.flush() }
        }
    }
    func userContentController(_ controller: WKUserContentController,didReceive message: WKScriptMessage) {
        guard message.webView === web,message.frameInfo.isMainFrame,message.frameInfo.request.url?.standardizedFileURL == page,
              let body=message.body as? [String:Any],let action=body["action"] as? String else { return }
        if action=="ready" { displayReady(web);return }
        guard let generation=body["generation"] as? String,let id=body["messageID"] as? String else { return }
        // A click sends the block's text; a page that sent none could only go by a real position.
        if action=="openR",let index=body["blockIndex"] as? Int,body["code"] is String || index>=0 { openR?(generation,id,index,body["code"] as? String) }
    }
    func userContentController(_ controller: WKUserContentController,didReceive message: WKScriptMessage,replyHandler: @escaping @MainActor @Sendable (Any?,String?)->Void) {
        guard message.name=="statsDirectAICopy",message.webView === web,message.frameInfo.isMainFrame,message.frameInfo.request.url?.standardizedFileURL == page,
              let body=message.body as? [String:Any],let generation=body["generation"] as? String,let id=body["messageID"] as? String,
              let code=body["code"] as? String else { replyHandler(false,nil);return }
        replyHandler(copyCode?(generation,id,code) ?? false,nil)
    }
    func webView(_ webView: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        guard let url=action.request.url else { decisionHandler(.cancel);return }
        if action.navigationType == .other,action.targetFrame?.isMainFrame == true,url.standardizedFileURL==page { decisionHandler(.allow);return }
        if action.navigationType == .linkActivated,["https","http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView,createWebViewWith configuration: WKWebViewConfiguration,for action: WKNavigationAction,windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView,requestMediaCapturePermissionFor origin: WKSecurityOrigin,initiatedByFrame frame: WKFrameInfo,type: WKMediaCaptureType,decisionHandler: @escaping (WKPermissionDecision)->Void) { decisionHandler(.deny) }
    func webView(_ webView: WKWebView,didFinish navigation: WKNavigation!) {
        if webView.url?.standardizedFileURL == page { displayReady(webView) }
    }
    func webView(_ webView: WKWebView,didFail navigation: WKNavigation!,withError error: Error) { recoverDisplay(webView) }
    func webView(_ webView: WKWebView,didFailProvisionalNavigation navigation: WKNavigation!,withError error: Error) { recoverDisplay(webView) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { recoverDisplay(webView) }
    func shutdown() { stopped=true;ready=false;displayTimeout?.cancel();web.navigationDelegate=nil;web.uiDelegate=nil;web.stopLoading();web.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectAI");web.configuration.userContentController.removeScriptMessageHandler(forName:"statsDirectAICopy",contentWorld:.page) }
}
