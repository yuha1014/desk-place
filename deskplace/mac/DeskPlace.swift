import AppKit
import WebKit
import ServiceManagement
import UniformTypeIdentifiers

final class DeskPlaceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PassthroughWKWebView: WKWebView {
    var interactiveRegions: [NSRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        // NSView.hitTest receives a point in the superview's coordinate space.
        // Region rectangles are stored in this WKWebView's own coordinate space.
        // Convert before checking, otherwise the flipped WebKit view can make every
        // button appear to be at a different Y coordinate and silently pass clicks through.
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard interactiveRegions.contains(where: { $0.contains(localPoint) }) else { return nil }
        return super.hitTest(point)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    private var mainWindow: DeskPlaceWindow?
    private var mainWebView: PassthroughWKWebView?
    private var wallpaperWebView: WKWebView?
    private var wallpaperContainer: NSView?
    private var awakeActivity: NSObjectProtocol?
    private var lifetimeActivity: NSObjectProtocol?
    private let appRoot = Bundle.main.resourceURL!.appendingPathComponent("app", isDirectory: true)
    private var queuedHTML: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["deskplace.keepAwake": true])
        lifetimeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "DeskPlace is a persistent desktop workspace"
        )
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        buildMenu()
        showMainWindow()
        if let queuedHTML { self.queuedHTML = nil; setWallpaperHTML(queuedHTML) }
        else if let path = UserDefaults.standard.string(forKey: "deskplace.wallpaperPath") {
            let savedURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: savedURL.path) { setWallpaperHTML(savedURL) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyEdgeToEdgePresentation(UserDefaults.standard.object(forKey: "deskplace.edgeToEdge") as? Bool ?? true)
        updateAwakeActivity()
    }

    func applicationDidResignActive(_ notification: Notification) {
        NSApp.presentationOptions = []
    }

    func applicationDidHide(_ notification: Notification) {
        updateAwakeActivity()
    }

    func applicationDidUnhide(_ notification: Notification) {
        updateAwakeActivity()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let awakeActivity { ProcessInfo.processInfo.endActivity(awakeActivity) }
        if let lifetimeActivity { ProcessInfo.processInfo.endActivity(lifetimeActivity) }
        awakeActivity = nil
        lifetimeActivity = nil
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if NSApp.isRunning { setWallpaperHTML(url) } else { queuedHTML = url }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showMainWindow() {
        guard mainWindow == nil else { mainWindow?.makeKeyAndOrderFront(nil); return }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "deskplace")
        let bridge = """
        (() => {
          let sequence = 0;
          const waiting = new Map();
          window.__deskplaceReply = (id, value) => { const resolve = waiting.get(id); if (resolve) { waiting.delete(id); resolve(value); } };
          window.__deskplaceSetWallpaperMode = (enabled, name) => {
            const workspace = document.querySelector('.workspace');
            workspace?.classList.toggle('wallpaper-mode', Boolean(enabled));
            const dateLine = document.querySelector('#date-line');
            if (dateLine && enabled) dateLine.textContent = `배경 HTML · ${name}`;
            window.dispatchEvent(new Event('resize'));
          };
          window.__deskplaceSetWallpaperColor = color => {
            if (!color) return;
            document.documentElement.style.setProperty('--wallpaper-panel-color', color);
            window.dispatchEvent(new CustomEvent('deskplace:wallpaper-color', { detail: color }));
          };
          const send = (method, value) => new Promise(resolve => {
            const id = ++sequence; waiting.set(id, resolve);
            window.webkit.messageHandlers.deskplace.postMessage({ id, method, value });
          });
          window.deskplace = {
            getLoginItem: () => send('getLoginItem'),
            setLoginItem: enabled => send('setLoginItem', Boolean(enabled)),
            getEdgeToEdge: () => send('getEdgeToEdge'),
            setEdgeToEdge: enabled => send('setEdgeToEdge', Boolean(enabled)),
            getKeepAwake: () => send('getKeepAwake'),
            setKeepAwake: enabled => send('setKeepAwake', Boolean(enabled)),
            openHtml: () => send('openHtml'),
            resetWallpaper: () => send('resetWallpaper'),
            setInteractiveRegions: regions => send('setInteractiveRegions', regions),
            setWallpaperScale: scale => send('setWallpaperScale', Number(scale)),
            showDesktop: () => send('showDesktop')
          };
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let webView = PassthroughWKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.loadFileURL(appRoot.appendingPathComponent("index.html"), allowingReadAccessTo: appRoot)

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = DeskPlaceWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "DeskPlace"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // Desktop-level windows do not receive mouse input reliably on macOS.
        // Keep this as a normal window so controls and imported HTML receive
        // physical pointer events; transparent regions pass hit testing through.
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        window.contentView = container
        window.delegate = self
        mainWindow = window
        mainWebView = webView
        wallpaperContainer = container
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.updateAwakeActivity() }
    }

    private func buildMenu() {
        let root = NSMenu()
        let appMenuItem = NSMenuItem(); root.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "DeskPlace 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "DeskPlace 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "다른 앱 숨기기", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "DeskPlace 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileItem = NSMenuItem(); root.addItem(fileItem)
        let fileMenu = NSMenu(title: "파일")
        let open = NSMenuItem(title: "HTML 파일 열기…", action: #selector(openHTMLFromMenu), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)
        fileItem.submenu = fileMenu
        NSApp.mainMenu = root
    }

    @objc private func openHTMLFromMenu() { _ = chooseHTMLFile() }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let id = payload["id"] as? Int,
              let method = payload["method"] as? String else { return }
        let rawValue = payload["value"]
        let value = rawValue as? Bool ?? false
        switch method {
        case "getLoginItem":
            let isEnabled = SMAppService.mainApp.status == .enabled
            reply(id, ["supported": true, "enabled": isEnabled], in: message.webView)
        case "setLoginItem":
            do {
                if value { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                reply(id, ["supported": true, "enabled": SMAppService.mainApp.status == .enabled], in: message.webView)
            } catch {
                reply(id, ["supported": false, "enabled": SMAppService.mainApp.status == .enabled, "error": error.localizedDescription], in: message.webView)
            }
        case "getEdgeToEdge":
            let enabled = UserDefaults.standard.object(forKey: "deskplace.edgeToEdge") as? Bool ?? true
            reply(id, ["enabled": enabled], in: message.webView)
        case "getKeepAwake":
            let enabled = UserDefaults.standard.object(forKey: "deskplace.keepAwake") as? Bool ?? true
            reply(id, ["enabled": enabled, "active": awakeActivity != nil], in: message.webView)
        case "setKeepAwake":
            UserDefaults.standard.set(value, forKey: "deskplace.keepAwake")
            updateAwakeActivity()
            reply(id, ["enabled": value, "active": awakeActivity != nil], in: message.webView)
        case "setEdgeToEdge":
            UserDefaults.standard.set(value, forKey: "deskplace.edgeToEdge")
            applyEdgeToEdgePresentation(value)
            reply(id, ["enabled": value], in: message.webView)
        case "openHtml":
            let openedURL = chooseHTMLFile()
            reply(id, ["opened": openedURL != nil, "name": openedURL?.lastPathComponent ?? ""], in: message.webView)
        case "resetWallpaper":
            clearWallpaperHTML()
            reply(id, ["reset": true], in: message.webView)
        case "setInteractiveRegions":
            let regions = rawValue as? [[String: NSNumber]] ?? []
            let height = wallpaperContainer?.bounds.height ?? mainWebView?.bounds.height ?? 0
            mainWebView?.interactiveRegions = regions.compactMap { region in
                guard let x = region["x"]?.doubleValue,
                      let y = region["y"]?.doubleValue,
                      let width = region["width"]?.doubleValue,
                      let regionHeight = region["height"]?.doubleValue,
                      width > 0, regionHeight > 0 else { return nil }
                let viewY = mainWebView?.isFlipped == true ? CGFloat(y) : height - CGFloat(y) - CGFloat(regionHeight)
                return NSRect(x: CGFloat(x), y: viewY, width: CGFloat(width), height: CGFloat(regionHeight))
            }
            reply(id, ["updated": true], in: message.webView)
        case "setWallpaperScale":
            let scale = rawValue as? Double ?? 100
            let boundedScale = min(150, max(50, scale))
            UserDefaults.standard.set(boundedScale, forKey: "deskplace.wallpaperScale")
            wallpaperWebView?.pageZoom = CGFloat(boundedScale / 100)
            reply(id, ["scale": boundedScale], in: message.webView)
        case "showDesktop":
            reply(id, ["supported": true], in: message.webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.hideOtherApplications(nil)
                NSApp.hide(nil)
            }
        default:
            reply(id, ["supported": false], in: message.webView)
        }
    }

    private func reply(_ id: Int, _ result: [String: Any], in webView: WKWebView?) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__deskplaceReply(\(id), \(json))")
    }

    private func applyEdgeToEdgePresentation(_ enabled: Bool) {
        // AppKit requires autoHideDock to accompany autoHideMenuBar.
        NSApp.presentationOptions = enabled ? [.autoHideMenuBar, .autoHideDock] : []
    }

    private func updateAwakeActivity() {
        let shouldKeepAwake = UserDefaults.standard.bool(forKey: "deskplace.keepAwake")
            && mainWindow?.isVisible == true
            && mainWindow?.occlusionState.contains(.visible) == true
        if shouldKeepAwake, awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "DeskPlace is keeping the selected desktop visible"
            )
        } else if !shouldKeepAwake, let awakeActivity {
            ProcessInfo.processInfo.endActivity(awakeActivity)
            self.awakeActivity = nil
        }
    }

    private func chooseHTMLFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "화면 배경으로 표시할 HTML 선택"
        panel.allowedContentTypes = [.html]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        setWallpaperHTML(url)
        return url
    }

    private func setWallpaperHTML(_ url: URL) {
        guard ["html", "htm"].contains(url.pathExtension.lowercased()) else { return }
        guard let container = wallpaperContainer else { return }
        wallpaperWebView?.removeFromSuperview()
        let configuration = WKWebViewConfiguration()
        let fitStyle = """
        (() => {
          const fit = () => {
            const root = document.documentElement;
            if (!root) return;
            let style = document.getElementById('deskplace-wallpaper-fit');
            if (!style) { style = document.createElement('style'); style.id = 'deskplace-wallpaper-fit'; (document.head || root).appendChild(style); }
            style.textContent = 'html,body{width:100%!important;min-height:100%!important;margin:0!important}body{min-height:100vh!important;overflow-x:hidden!important;overflow-y:auto!important;-webkit-overflow-scrolling:touch}';
            let viewport = document.querySelector('meta[name=viewport]');
            if (!viewport) { viewport = document.createElement('meta'); viewport.name = 'viewport'; root.querySelector('head')?.appendChild(viewport); }
            viewport.content = 'width=device-width, initial-scale=1, maximum-scale=1';
          };
          fit(); document.addEventListener('DOMContentLoaded', fit, { once: true });
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: fitStyle, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        let savedScale = UserDefaults.standard.double(forKey: "deskplace.wallpaperScale")
        webView.pageZoom = CGFloat(savedScale > 0 ? savedScale / 100 : 1)
        container.addSubview(webView, positioned: .below, relativeTo: mainWebView)
        wallpaperWebView = webView
        UserDefaults.standard.set(url.path, forKey: "deskplace.wallpaperPath")
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        applyWallpaperMode(true, name: url.lastPathComponent)
    }

    private func clearWallpaperHTML() {
        wallpaperWebView?.stopLoading()
        wallpaperWebView?.removeFromSuperview()
        wallpaperWebView = nil
        UserDefaults.standard.removeObject(forKey: "deskplace.wallpaperPath")
        applyWallpaperMode(false, name: "")
    }

    private func applyWallpaperMode(_ enabled: Bool, name: String) {
        guard let mainWebView,
              let nameData = try? JSONSerialization.data(withJSONObject: name, options: [.fragmentsAllowed]),
              let safeName = String(data: nameData, encoding: .utf8) else { return }
        mainWebView.evaluateJavaScript("window.__deskplaceSetWallpaperMode && window.__deskplaceSetWallpaperMode(\(enabled), \(safeName))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === wallpaperWebView {
            let source = "(() => { const isClear = color => !color || color === 'transparent' || color === 'rgba(0, 0, 0, 0)'; const body = getComputedStyle(document.body).backgroundColor; const html = getComputedStyle(document.documentElement).backgroundColor; const color = !isClear(body) ? body : (!isClear(html) ? html : 'rgb(255, 250, 244)'); const canvas = document.createElement('canvas'); const context = canvas.getContext('2d'); context.fillStyle = color; context.fillRect(0, 0, 1, 1); return { color, components: Array.from(context.getImageData(0, 0, 1, 1).data) }; })()"
            webView.evaluateJavaScript(source) { result, _ in
                guard let colorResult = result as? [String: Any],
                      let color = colorResult["color"] as? String,
                      let components = colorResult["components"] as? [NSNumber], components.count >= 3,
                      let data = try? JSONSerialization.data(withJSONObject: color, options: [.fragmentsAllowed]),
                      let json = String(data: data, encoding: .utf8) else { return }
                let rgba = components.map { CGFloat($0.doubleValue / 255) }
                self.wallpaperWebView?.underPageBackgroundColor = NSColor(calibratedRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba.count > 3 ? rgba[3] : 1)
                self.mainWebView?.evaluateJavaScript("window.__deskplaceSetWallpaperColor && window.__deskplaceSetWallpaperColor(\(json))")
            }
            return
        }
        guard webView === mainWebView else { return }
        let saved = UserDefaults.standard.string(forKey: "deskplace.wallpaperPath")
        applyWallpaperMode(saved != nil, name: saved.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "")
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow,
              let screen = window.screen else { return }
        window.setFrame(screen.frame, display: true)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow,
              let screen = window.screen else { return }
        window.setFrame(screen.frame, display: true)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        updateAwakeActivity()
    }

    @objc private func screenParametersChanged() {
        guard let mainWindow else { return }
        let screen = mainWindow.screen ?? NSScreen.main
        if let screen { mainWindow.setFrame(screen.frame, display: true) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
