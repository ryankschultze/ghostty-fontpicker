import AppKit
import SwiftUI

/// Runs the picker as a regular app even when started as a bare executable from a shell.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var window: NSWindow?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Ghostty Font Picker"
        window.contentMinSize = NSSize(width: 1040, height: 600)
        window.contentView = NSHostingView(rootView: RootView().environmentObject(state))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("FontPickerMain")
        window.makeKeyAndOrderFront(nil)
        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors are called on the main thread. The event itself can't cross
            // into the main actor, so the few fields that matter are copied out first.
            let key = KeyPress(
                code: event.keyCode, modifiers: event.modifierFlags.intersection([.command, .option, .control]).rawValue,
                characters: event.charactersIgnoringModifiers, windowNumber: event.windowNumber)
            let used = MainActor.assumeIsolated { self?.handle(key) ?? false }
            return used ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
        state.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private struct KeyPress: Sendable {
        let code: UInt16
        let modifiers: UInt
        let characters: String?
        let windowNumber: Int
    }

    /// Window-wide shortcuts. Returns true when the key was used.
    private func handle(_ key: KeyPress) -> Bool {
        // Alerts and menus are other windows; their keys are their own.
        guard let window, key.windowNumber == window.windowNumber else { return false }
        let modifiers = NSEvent.ModifierFlags(rawValue: key.modifiers)
        if modifiers == .command {
            if key.code == 36 || key.code == 76 {  // return, enter
                state.apply()
                return true
            }
            if key.characters == "f" {
                state.focusFilter += 1
                return true
            }
            return false
        }
        guard modifiers.isEmpty else { return false }
        switch key.code {
        case 125:  // down
            state.step(1)
            return true
        case 126:  // up
            state.step(-1)
            return true
        default: break
        }
        // Everything below is a plain key that a text field would want for itself.
        guard !(window.firstResponder is NSText) else { return false }
        switch key.code {
        case 124: state.step(1)  // right
        case 123: state.step(-1)  // left
        case 49: state.setDrift(state.drift.mode == .off ? .lfo : .off)  // space
        default:
            switch key.characters {
            case "j": state.step(1)
            case "k": state.step(-1)
            case "/": state.focusFilter += 1
            default: return false
            }
        }
        return true
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Hide Font Picker", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Font Picker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "Font Picker"))

        // Without an Edit menu, copy and paste don't reach the filter field.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, title: "Edit"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(windowMenu, title: "Window"))
        NSApp.windowsMenu = windowMenu
        return main
    }

    private func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }
}
