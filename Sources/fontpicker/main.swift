import AppKit

// With arguments this is a command-line tool; without, it opens the picker window.
// Top-level code runs on the main thread, which is all `assumeIsolated` needs to hear.
MainActor.assumeIsolated {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if !arguments.isEmpty {
        exit(CLI.run(arguments))
    }

    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    // A bare executable has no bundle to say so, and would otherwise get no Dock icon or menu bar.
    app.setActivationPolicy(.regular)
    app.run()
}
