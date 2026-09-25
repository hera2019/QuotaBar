import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var chat = ProviderState()
    private var claude = ProviderState()
    private var claudeFileDate: Date?
    private var chatFetching = false

    private var statusItem: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    private var panel: NSPanel?
    private var usageView: UsageView?
    private let menu = NSMenu()
    private var timers: [Timer] = []

    private var style: DisplayStyle {
        get { DisplayStyle(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .menuBar }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "style") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        menu.autoenablesItems = false
        applyStyle()
        reloadClaude(force: true)
        refreshChat()

        timers = [
            // The Claude file is cheap to check; reread only when it changes.
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.reloadClaude(force: false) },
            Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in self?.refreshChat() },
            // Keep reset times and "past reset" states current.
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.redraw() },
        ]
    }

    // MARK: - Data

    private func reloadClaude(force: Bool) {
        let date = ClaudeSource.modificationDate()
        guard force || date != claudeFileDate else { return }
        claudeFileDate = date
        switch ClaudeSource.load() {
        case .success(let u): claude = ProviderState(usage: u, error: nil)
        case .failure(let e): claude = ProviderState(usage: nil, error: e.text)
        }
        redraw()
    }

    private func refreshChat() {
        guard !chatFetching else { return }
        chatFetching = true
        CodexSource.fetch { [weak self] result in
            guard let self else { return }
            self.chatFetching = false
            switch result {
            case .success(let u): self.chat = ProviderState(usage: u, error: nil)
            case .failure(let e):
                // Keep the last good numbers; just record the error.
                self.chat.error = e.text
            }
            self.redraw()
        }
    }

    @objc private func refreshNow() {
        reloadClaude(force: true)
        refreshChat()
    }

    private func rings() -> [RingInfo] {
        let now = Date()
        func make(_ name: String, _ tint: NSColor, _ state: ProviderState, _ span: Span) -> RingInfo {
            let raw = span == .fiveHour ? state.usage?.fiveHour : state.usage?.weekly
            let window = raw?.effective(now: now)
            let caption: String
            if state.failed { caption = L10n.failed }
            else if state.usage == nil { caption = "…" }
            else if let w = window { caption = w.resetsAt.map { Fmt.short($0, now: now) } ?? L10n.wasReset }
            else { caption = L10n.notOnPlan }
            return RingInfo(provider: name, span: span, tint: tint, window: window, failed: state.failed, caption: caption)
        }
        return [
            make("GPT", Tint.gpt, chat, .fiveHour),
            make("GPT", Tint.gpt, chat, .weekly),
            make("Claude", Tint.claude, claude, .fiveHour),
            make("Claude", Tint.claude, claude, .weekly),
        ]
    }

    private func redraw() {
        let rings = rings()
        usageView?.rings = rings
        updateStatusImage(rings)
        let tip = summaryLines(rings).joined(separator: "\n")
        usageView?.toolTip = tip
        statusItem?.button?.toolTip = tip
    }

    private func summaryLines(_ rings: [RingInfo]) -> [String] {
        rings.map { r in
            let label = "\(r.provider) \(r.span.rawValue)"
            if let w = r.window {
                return L10n.used(label, Int(w.usedPercent.rounded()), resets: w.resetsAt.map(Fmt.long))
            }
            return L10n.captionLine(label, r.caption)
        }
    }

    // MARK: - Display styles

    private func applyStyle() {
        switch style {
        case .menuBar:
            closePanel()
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.menu = menu
                appearanceObservation = item.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.redraw() }
                }
                statusItem = item
            }
        case .strip, .card:
            if let item = statusItem {
                appearanceObservation = nil
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            showPanel()
        }
        redraw()
    }

    private func updateStatusImage(_ rings: [RingInfo]) {
        guard let button = statusItem?.button else { return }
        let appearance = button.effectiveAppearance
        let image = NSImage(size: Layout.size(for: .menuBar), flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                Layout.draw(.menuBar, rings: rings, in: rect)
            }
            return true
        }
        image.isTemplate = false
        button.image = image
    }

    private func showPanel() {
        let size = Layout.size(for: style)
        let radius: CGFloat = style == .strip ? 8 : 16

        let panel = self.panel ?? {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.delegate = self
            self.panel = p
            return p
        }()

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: radius)

        let view = UsageView(frame: effect.bounds)
        view.autoresizingMask = [.width, .height]
        view.style = style
        view.menu = menu
        effect.addSubview(view)
        usageView = view

        panel.contentView = effect
        panel.setFrame(NSRect(origin: savedOrigin(for: style, size: size), size: size), display: true)
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        usageView = nil
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Each style remembers its own position. First time: the strip sits top-center (where title bars are), the card top-right.
    private func savedOrigin(for style: DisplayStyle, size: NSSize) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: "origin.\(style.rawValue)") {
            let p = NSPointFromString(s)
            let frame = NSRect(origin: p, size: size)
            if NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) { return p }
        }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        switch style {
        case .card: return NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 12)
        default: return NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 4)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, style != .menuBar else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "origin.\(style.rawValue)")
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = DisplayStyle(rawValue: raw), s != style else { return }
        style = s
        applyStyle()
    }

    // MARK: - Menu (rebuilt every time it opens, so it is always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rings = rings()
        let lines = summaryLines(rings)

        func info(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        lines[0...1].forEach(info)
        if let e = chat.error { info("GPT：\(e)") }
        menu.addItem(.separator())
        lines[2...3].forEach(info)
        if let e = claude.error { info("Claude：\(e)") }
        else if let u = claude.usage { info(L10n.claudeUpdated(Fmt.long(u.updatedAt))) }
        menu.addItem(.separator())

        let styleItem = NSMenuItem(title: L10n.display, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for s in DisplayStyle.allCases {
            let item = NSMenuItem(title: s.title, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.rawValue
            item.state = s == style ? .on : .off
            sub.addItem(item)
        }
        styleItem.submenu = sub
        menu.addItem(styleItem)

        let refresh = NSMenuItem(title: L10n.refresh, action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
