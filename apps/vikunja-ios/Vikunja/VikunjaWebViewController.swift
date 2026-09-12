import UIKit
import WebKit

@MainActor
final class VikunjaWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
    WKDownloadDelegate, UIPopoverPresentationControllerDelegate {
    private static let startURL = URL(string: "https://todo.coultonf.com/")!
    private static let externalSchemes: Set<String> = [
        "http", "https", "mailto", "tel", "webcal", "ftp", "git", "obsidian", "notion", "message"
    ]

    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.limitsNavigationsToAppBoundDomains = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }()

    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private var urlObservation: NSKeyValueObservation?
    private var backgroundObservation: NSKeyValueObservation?
    private var lastPermittedURL: URL?
    private var mainNavigation: WKNavigation?
    private var isLoadingMainDocument = false
    private var statusBarStyle: UIStatusBarStyle = .default
    private var downloads: [ObjectIdentifier: DownloadState] = [:]
    private var pendingModals: [ModalRequest] = []
    private var activeModal: ModalRequest?
    private var modalDrainScheduled = false

    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        view.keyboardLayoutGuide.followsUndockedKeyboard = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        configureLoadingAndErrorViews()
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.rememberPermittedURL(webView.url)
            }
        }
        backgroundObservation = webView.observe(
            \.underPageBackgroundColor, options: [.initial, .new]
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateSurroundingBackground()
            }
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (controller: VikunjaWebViewController, _: UITraitCollection) in
            controller.updateSurroundingBackground()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        webView.load(URLRequest(url: Self.startURL))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        drainModalQueue()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let popover = activeModal?.controller.popoverPresentationController {
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if !downloads.isEmpty {
            let remainingDownloads = downloads
            Task { @MainActor in
                for state in remainingDownloads.values {
                    _ = await state.download.cancel()
                    state.removeTemporaryFiles()
                }
            }
        }
    }

    private func configureLoadingAndErrorViews() {
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: webView.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        ])

        errorLabel.text = "Unable to load Vikunja"
        errorLabel.font = .preferredFont(forTextStyle: .headline)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        let retryButton = UIButton(type: .system)
        retryButton.configuration = .filled()
        retryButton.setTitle("Retry", for: .normal)
        retryButton.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [errorLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorView.trailingAnchor, constant: -24)
        ])

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
        ])
    }

    private static func permits(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "todo.coultonf.com"
            && (url.port ?? 443) == 443
    }

    private func rememberPermittedURL(_ url: URL?) {
        guard let url, Self.permits(url) else { return }
        // Keep SPA queries and share fragments in memory only.
        lastPermittedURL = url
    }

    private func updateSurroundingBackground() {
        guard isViewLoaded else { return }
        let fallback = UIColor.systemBackground.resolvedColor(with: traitCollection)
        let color = webView.underPageBackgroundColor.resolvedColor(with: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let background: UIColor
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var fallbackRed: CGFloat = 0
            var fallbackGreen: CGFloat = 0
            var fallbackBlue: CGFloat = 0
            var fallbackAlpha: CGFloat = 0
            fallback.getRed(
                &fallbackRed, green: &fallbackGreen, blue: &fallbackBlue, alpha: &fallbackAlpha
            )
            red = red * alpha + fallbackRed * (1 - alpha)
            green = green * alpha + fallbackGreen * (1 - alpha)
            blue = blue * alpha + fallbackBlue * (1 - alpha)
            background = UIColor(red: red, green: green, blue: blue, alpha: 1)
        } else {
            background = fallback
            fallback.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        view.backgroundColor = background
        errorView.backgroundColor = background
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        let lightText = 1.05 / (luminance + 0.05) > (luminance + 0.05) / 0.05
        statusBarStyle = lightText ? .lightContent : .darkContent
        errorLabel.textColor = lightText ? .white : .black
        loadingIndicator.color = errorLabel.textColor
        setNeedsStatusBarAppearanceUpdate()
    }

    private func setMainDocumentLoading(_ loading: Bool) {
        isLoadingMainDocument = loading
        if loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    private func showLoadError() {
        setMainDocumentLoading(false)
        errorView.isHidden = false
    }

    @objc private func retryLoading() {
        webView.load(URLRequest(url: lastPermittedURL ?? Self.startURL))
    }

    @objc private func applicationDidBecomeActive() {
        drainModalQueue()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // A detached download anchor can have no target frame or user-gesture classification.
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if let frame = navigationAction.targetFrame, !frame.isMainFrame {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.scheme?.lowercased() == "blob" {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame == nil {
            // The UI delegate owns new-window routing so an external link opens only once.
            decisionHandler(.allow)
            return
        }
        if Self.permits(url) {
            rememberPermittedURL(url)
            decisionHandler(.allow)
        } else {
            openExternalLink(url, for: navigationAction)
            if navigationAction.navigationType != .linkActivated && isLoadingMainDocument {
                showLoadError()
            }
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if navigationAction.shouldPerformDownload || url.scheme?.lowercased() == "blob" {
            webView.startDownload(using: navigationAction.request) { [weak self] download in
                guard let self else {
                    download.cancel(nil)
                    return
                }
                self.trackDownload(download)
            }
        } else if Self.permits(url) {
            rememberPermittedURL(url)
            webView.load(navigationAction.request)
        } else {
            openExternalLink(url, for: navigationAction)
        }
        return nil
    }

    private func openExternalLink(_ url: URL, for action: WKNavigationAction) {
        guard action.navigationType == .linkActivated else { return }
        guard let scheme = url.scheme?.lowercased(), Self.externalSchemes.contains(scheme) else {
            showMessage("Unable to open link")
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            if !opened { self?.showMessage("Unable to open link") }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response as? HTTPURLResponse
        if navigationResponse.isForMainFrame, let response, response.statusCode >= 400 {
            showLoadError()
            decisionHandler(.cancel)
            return
        }
        let disposition = response?.value(forHTTPHeaderField: "Content-Disposition")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if disposition == "attachment"
            || (navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType) {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        mainNavigation = navigation
        cancelJavaScriptDialogs()
        errorView.isHidden = true
        setMainDocumentLoading(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === mainNavigation else { return }
        mainNavigation = nil
        rememberPermittedURL(webView.url)
        errorView.isHidden = true
        setMainDocumentLoading(false)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(navigation, error: error)
    }

    private func handleNavigationFailure(_ navigation: WKNavigation?, error: Error) {
        guard navigation === mainNavigation else { return }
        mainNavigation = nil
        setMainDocumentLoading(false)
        let error = error as NSError
        // Download conversion may use WebKit's legacy policy-interruption error domain.
        if (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102) {
            return
        }
        showLoadError()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        mainNavigation = nil
        cancelJavaScriptDialogs()
        showLoadError()
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        trackDownload(download)
        if navigationAction.targetFrame?.isMainFrame == true {
            setMainDocumentLoading(false)
        }
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        trackDownload(download)
        if navigationResponse.isForMainFrame { setMainDocumentLoading(false) }
    }

    @discardableResult
    private func trackDownload(_ download: WKDownload) -> DownloadState {
        let key = ObjectIdentifier(download)
        if let state = downloads[key] { return state }
        let state = DownloadState(download: download)
        downloads[key] = state
        download.delegate = self
        return state
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let state = trackDownload(download)
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "Vikunja-\(UUID().uuidString)", isDirectory: true
        )
        do {
            guard !fileManager.fileExists(atPath: directory.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            state.directoryURL = directory
            let destination = directory.appendingPathComponent(
                Self.safeFilename(suggestedFilename), isDirectory: false
            )
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            state.destinationURL = destination
            completionHandler(destination)
        } catch {
            failDownload(download)
            completionHandler(nil)
        }
    }

    private static func safeFilename(_ suggested: String) -> String {
        let start = suggested.lastIndex(where: { $0 == "/" || $0 == "\\" })
            .map { suggested.index(after: $0) } ?? suggested.startIndex
        let name = suggested[start...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != ".", name != "..",
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            return "download"
        }
        return name
    }

    func download(
        _ download: WKDownload,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let state = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        guard let destination = state.destinationURL else {
            state.removeTemporaryFiles()
            showMessage("Download failed")
            return
        }
        let sheet = UIActivityViewController(activityItems: [destination], applicationActivities: nil)
        let modal = ModalRequest(controller: sheet) { state.removeTemporaryFiles() }
        sheet.completionWithItemsHandler = { [weak self, weak sheet] _, _, _, _ in
            guard let sheet else { return }
            self?.requestModalCompletion(sheet)
        }
        enqueueModal(modal)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        failDownload(download)
    }

    private func failDownload(_ download: WKDownload) {
        guard let state = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        state.removeTemporaryFiles()
        showMessage("Download failed")
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = javaScriptAlert(message: message, frame: frame)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            guard let alert else { return }
            self?.requestModalCompletion(alert)
        })
        enqueueModal(ModalRequest(
            controller: alert, isJavaScriptDialog: true, onDismiss: completionHandler
        ))
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = javaScriptAlert(message: message, frame: frame)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self, weak alert] _ in
            guard let alert else { return }
            self?.requestModalCompletion(alert)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            guard let alert else { return }
            self?.requestModalCompletion(alert) { completionHandler(true) }
        })
        enqueueModal(ModalRequest(controller: alert, isJavaScriptDialog: true) {
            completionHandler(false)
        })
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = javaScriptAlert(message: prompt, frame: frame)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self, weak alert] _ in
            guard let alert else { return }
            self?.requestModalCompletion(alert)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            guard let alert else { return }
            let text = alert.textFields?.first?.text ?? ""
            self?.requestModalCompletion(alert) { completionHandler(text) }
        })
        enqueueModal(ModalRequest(controller: alert, isJavaScriptDialog: true) {
            completionHandler(nil)
        })
    }

    private func javaScriptAlert(message: String, frame: WKFrameInfo) -> UIAlertController {
        let host = frame.securityOrigin.host
        return UIAlertController(
            title: host.isEmpty ? "JavaScript from this page" : "JavaScript from \(host)",
            message: message,
            preferredStyle: .alert
        )
    }

    private func showMessage(_ title: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            guard let alert else { return }
            self?.requestModalCompletion(alert)
        })
        enqueueModal(ModalRequest(controller: alert))
    }

    private func enqueueModal(_ modal: ModalRequest) {
        pendingModals.append(modal)
        drainModalQueue()
    }

    private func requestModalCompletion(
        _ controller: UIViewController, response: (() -> Void)? = nil
    ) {
        guard let activeModal, activeModal.controller === controller,
              !activeModal.dismissalRequested else { return }
        if let response { activeModal.replaceCompletion(response) }
        activeModal.dismissalRequested = true
        scheduleModalDrain()
    }

    private func drainModalQueue() {
        guard isViewLoaded, view.window?.windowScene?.activationState == .foregroundActive else {
            return
        }
        if let active = activeModal {
            guard active.presentationFinished else { return }
            let controller = active.controller
            if active.cancelled, controller.presentingViewController != nil,
               !controller.isBeingDismissed {
                active.cancelled = false
                active.dismissalRequested = true
                controller.dismiss(animated: false) { [weak self] in self?.drainModalQueue() }
                return
            }
            if controller.presentingViewController != nil || controller.isBeingDismissed
                || controller.isBeingPresented {
                if active.dismissalRequested { scheduleModalDrain() }
                return
            }
            activeModal = nil
            active.finish()
        }
        guard activeModal == nil, !pendingModals.isEmpty else { return }
        guard presentedViewController == nil, !isBeingPresented, !isBeingDismissed else {
            // WebKit owns file pickers. Wait without replacing their presentation delegate.
            scheduleModalDrain()
            return
        }
        let modal = pendingModals.removeFirst()
        activeModal = modal
        if let popover = modal.controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
            popover.delegate = self
        }
        present(modal.controller, animated: true) { [weak self, weak modal] in
            modal?.presentationFinished = true
            self?.drainModalQueue()
        }
        // UIKit owns UIAlertController's presentation delegate.
        if modal.controller is UIActivityViewController {
            modal.controller.presentationController?.delegate = self
        }
    }

    private func scheduleModalDrain() {
        guard !modalDrainScheduled else { return }
        modalDrainScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.modalDrainScheduled = false
            self.drainModalQueue()
        }
    }

    private func cancelJavaScriptDialogs() {
        let cancelled = pendingModals.filter(\.isJavaScriptDialog)
        pendingModals.removeAll(where: \.isJavaScriptDialog)
        for modal in cancelled { modal.finish() }
        if let activeModal, activeModal.isJavaScriptDialog {
            activeModal.cancelled = true
        }
        drainModalQueue()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        requestModalCompletion(presentationController.presentedViewController)
    }

    func popoverPresentationControllerDidDismissPopover(
        _ popoverPresentationController: UIPopoverPresentationController
    ) {
        requestModalCompletion(popoverPresentationController.presentedViewController)
    }

    private final class DownloadState {
        let download: WKDownload
        var directoryURL: URL?
        var destinationURL: URL?

        init(download: WKDownload) {
            self.download = download
        }

        func removeTemporaryFiles() {
            guard let directoryURL else { return }
            self.directoryURL = nil
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private final class ModalRequest {
        let controller: UIViewController
        let isJavaScriptDialog: Bool
        var presentationFinished = false
        var dismissalRequested = false
        var cancelled = false
        private var onDismiss: (() -> Void)?

        init(
            controller: UIViewController,
            isJavaScriptDialog: Bool = false,
            onDismiss: (() -> Void)? = nil
        ) {
            self.controller = controller
            self.isJavaScriptDialog = isJavaScriptDialog
            self.onDismiss = onDismiss
        }

        func replaceCompletion(_ completion: @escaping () -> Void) {
            guard onDismiss != nil else { return }
            onDismiss = completion
        }

        func finish() {
            let completion = onDismiss
            onDismiss = nil
            completion?()
        }

        deinit {
            onDismiss?()
        }
    }
}
