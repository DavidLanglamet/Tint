import AppKit

// Menu-bar-only app: after an interval the screen is washed in a color.
// Left-click the icon clears the color and restarts the interval.
// Right-click (or Control-click) opens the menu to change the color, intensity
// and interval, or quit.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let presets: [(name: String, color: NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow),
        ("Green", .systemGreen), ("Blue", .systemBlue), ("Purple", .systemPurple),
        ("Pink", .systemPink), ("Gray", .systemGray),
    ]

    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var overlays: [NSWindow] = []
    private var timer: Timer?

    // Seconds until the color appears, set from the menu's interval slider.
    private var interval: TimeInterval {
        get {
            let value = defaults.double(forKey: "intervalSeconds")
            return value > 0 ? min(max(value, 60), 60 * 60) : 30 * 60
        }
        set { defaults.set(newValue, forKey: "intervalSeconds") }
    }
    private var intervalChanged = false
    private weak var intervalLabel: NSTextField?

    // Refreshes the countdown item every second while the menu is open.
    private var countdownTimer: Timer?
    private weak var countdownItem: NSMenuItem?

    // How strongly the color covers the screen (0...1), set from the menu's Intensity slider.
    private var opacity: CGFloat {
        get {
            let value = defaults.double(forKey: "opacity")
            return value > 0 ? CGFloat(min(value, 0.75)) : 0.35
        }
        set {
            defaults.set(Double(newValue), forKey: "opacity")
            refreshOverlayColor()
        }
    }

    // True while the tint is shown only to preview the Intensity slider.
    private var previewing = false
    private weak var intensityLabel: NSTextField?

    private var color: NSColor {
        get {
            guard let c = defaults.array(forKey: "color") as? [Double], c.count == 3 else {
                return NSColor.systemRed.usingColorSpace(.sRGB)!
            }
            return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
        }
        set {
            let c = newValue.usingColorSpace(.sRGB) ?? newValue
            defaults.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: "color")
            refreshOverlayColor()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Tint")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(reset), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        reset()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
        } else {
            reset()
        }
    }

    // Detach the menu again so the next left-click resets instead of opening it.
    // Common run loop mode so the countdown keeps ticking while the menu is tracking.
    func menuWillOpen(_ menu: NSMenu) {
        updateCountdown()
        let refresh = Timer(
            timeInterval: 1, target: self, selector: #selector(updateCountdown),
            userInfo: nil, repeats: true)
        RunLoop.main.add(refresh, forMode: .common)
        countdownTimer = refresh
    }

    func menuDidClose(_ menu: NSMenu) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        statusItem.menu = nil
        if previewing {
            previewing = false
            hideOverlays()
        }
        // A new interval restarts the countdown, unless the screen is already tinted.
        if intervalChanged {
            intervalChanged = false
            if overlays.isEmpty { reset() }
        }
    }

    @objc private func reset() {
        hideOverlays()
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: interval, target: self, selector: #selector(timerFired),
            userInfo: nil, repeats: false)
        timer?.tolerance = 5
    }

    @objc private func timerFired() {
        showOverlays(animated: true)
    }

    // MARK: Overlay

    private func showOverlays(animated: Bool) {
        hideOverlays()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = color.withAlphaComponent(opacity)
            window.setFrame(screen.frame, display: false)
            window.alphaValue = animated ? 0 : 1
            window.orderFrontRegardless()
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 1.5
                    window.animator().alphaValue = 1
                }
            }
            overlays.append(window)
        }
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }

    private func refreshOverlayColor() {
        overlays.forEach { $0.backgroundColor = color.withAlphaComponent(opacity) }
    }

    @objc private func screensChanged() {
        if !overlays.isEmpty { showOverlays(animated: false) }
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let countdown = NSMenuItem(title: "", action: #selector(reset), keyEquivalent: "")
        countdown.target = self
        countdownItem = countdown
        menu.addItem(countdown)
        menu.addItem(.separator())

        let current = color
        var matchedPreset = false
        for (index, preset) in Self.presets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(pickPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.attributedTitle = swatchTitle(preset.name, preset.color)
            if Self.sameColor(preset.color, current) {
                item.state = .on
                matchedPreset = true
            }
            menu.addItem(item)
        }
        let custom = NSMenuItem(title: "Custom…", action: #selector(pickCustom), keyEquivalent: "")
        custom.target = self
        if !matchedPreset {
            custom.state = .on
            custom.attributedTitle = swatchTitle("Custom…", current)
        }
        menu.addItem(custom)
        menu.addItem(.separator())
        menu.addItem(intensityItem())
        menu.addItem(intervalItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func pickPreset(_ sender: NSMenuItem) {
        color = Self.presets[sender.tag].color
    }

    @objc private func pickCustom() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        color = sender.color
    }

    private func intensityItem() -> NSMenuItem {
        let (item, label, _) = sliderItem(
            title: "Intensity", value: Double(opacity * 100), range: 5...75,
            text: Self.percent(opacity), action: #selector(intensityChanged(_:)))
        intensityLabel = label
        return item
    }

    // 1 to 60 minutes in 1-minute steps.
    private func intervalItem() -> NSMenuItem {
        let (item, label, _) = sliderItem(
            title: "Remind after", value: interval / 60, range: 1...60,
            text: Self.minutes(interval), action: #selector(intervalSliderChanged(_:)))
        intervalLabel = label
        return item
    }

    private func sliderItem(
        title: String, value: Double, range: ClosedRange<Double>, text: String, action: Selector
    ) -> (NSMenuItem, NSTextField, NSSlider) {
        // Insets line the labels up with the text of ordinary menu items.
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 50))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.frame = NSRect(x: 28, y: 28, width: 140, height: 17)
        view.addSubview(titleLabel)

        let valueLabel = NSTextField(labelWithString: text)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 186, y: 28, width: 72, height: 17)
        view.addSubview(valueLabel)

        let slider = NSSlider(
            value: value, minValue: range.lowerBound, maxValue: range.upperBound,
            target: self, action: action)
        slider.isContinuous = true
        slider.frame = NSRect(x: 28, y: 4, width: 228, height: 22)
        view.addSubview(slider)

        let item = NSMenuItem()
        item.view = view
        return (item, valueLabel, slider)
    }

    @objc private func intervalSliderChanged(_ sender: NSSlider) {
        interval = sender.doubleValue.rounded() * 60
        intervalLabel?.stringValue = Self.minutes(interval)
        intervalChanged = true
    }

    // Zero while the screen is tinted, since the countdown timer has already fired.
    @objc private func updateCountdown() {
        let remaining = timer?.isValid == true ? max(0, timer!.fireDate.timeIntervalSinceNow) : 0
        let total = Int(remaining.rounded(.up))
        let text = String(format: "Restart timer (%d:%02d left)", total / 60, total % 60)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)
        countdownItem?.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }

    // Shows the tint while dragging so the strength can be judged; menuDidClose removes a preview.
    @objc private func intensityChanged(_ sender: NSSlider) {
        opacity = CGFloat(sender.doubleValue.rounded()) / 100
        intensityLabel?.stringValue = Self.percent(opacity)
        if overlays.isEmpty {
            previewing = true
            showOverlays(animated: false)
        }
    }

    private static func percent(_ opacity: CGFloat) -> String {
        "\(Int((opacity * 100).rounded()))%"
    }

    // A colored dot before the name; recent macOS versions don't draw menu item images.
    private func swatchTitle(_ name: String, _ color: NSColor) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: "● ", attributes: [.font: font, .foregroundColor: color])
        title.append(NSAttributedString(string: name, attributes: [.font: font]))
        return title
    }

    private static func sameColor(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
