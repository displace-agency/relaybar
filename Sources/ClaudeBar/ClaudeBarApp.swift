import SwiftUI
import AppKit
import Combine

@main
struct QuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var appearanceObservation: NSKeyValueObservation?
    private var popover: NSPopover!
    private var monitor: UsageMonitor!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor = UsageMonitor()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.behavior = []
        statusItem.autosaveName = "agency.displace.ClaudeBar.status"
        if let button = statusItem.button {
            // Render the whole menu bar label into a single bitmap image and
            // hand that to the button. This bypasses the macOS 26 bug where
            // NSStatusBarButton's cell draws attributedTitle + template images
            // at zero alpha on ad-hoc-signed apps.
            button.image = Self.renderBarImage(segments: [.init(text: "Quota", tint: .neutral)],
                textColor: button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black)
            button.imagePosition = .imageOnly
            button.title = ""
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.appearance = NSAppearance(named: .aqua)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuView(monitor: monitor)
        )

        monitor.$menuBarText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItemTitle() }
            .store(in: &cancellables)
        monitor.$menuBarSegments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItemTitle() }
            .store(in: &cancellables)
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateStatusItemTitle() }
        }
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var segments = monitor.menuBarSegments
        if segments.isEmpty {
            segments = [.init(text: monitor.menuBarText.replacingOccurrences(of: "◐ ", with: ""), tint: .neutral)]
        }
        button.image = Self.renderBarImage(segments: segments, textColor: dark ? .white : .black)
        button.imagePosition = .imageOnly
        button.title = ""
        button.contentTintColor = nil
    }

    /// Pre-renders the menu bar label into a single non-template NSImage.
    /// Works around a macOS 26 regression where NSStatusBarButton draws
    /// attributedTitle + template images at zero alpha for ad-hoc signed apps.
    private static func renderBarImage(segments: [UsageMonitor.MenuBarSegment], textColor: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        let dotFont = NSFont.systemFont(ofSize: 7)
        let attr = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { attr.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            if segment.tint != .neutral {
                let dot: NSColor = segment.tint == .red ? .systemRed : .systemOrange
                attr.append(NSAttributedString(string: "●\u{2009}", attributes: [.font: dotFont, .foregroundColor: dot, .baselineOffset: 1.5]))
            }
            attr.append(NSAttributedString(string: segment.text, attributes: [.font: font, .foregroundColor: textColor]))
        }

        let textSize = attr.size()
        let padding: CGFloat = 2
        let size = NSSize(
            width: ceil(textSize.width) + padding * 2,
            height: NSStatusBar.system.thickness
        )

        let image = NSImage(size: size)
        image.lockFocus()
        let origin = NSPoint(x: padding, y: (size.height - textSize.height) / 2)
        attr.draw(at: origin)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(from: sender)
            return
        }
        togglePopover(from: sender)
    }

    private func togglePopover(from sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            monitor.refresh()
        }
    }

    private func showContextMenu(from sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Quota", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshFromMenu() { monitor.refresh() }
}
