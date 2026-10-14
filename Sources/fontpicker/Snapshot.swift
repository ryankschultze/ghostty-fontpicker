import AppKit
import FontPickerCore
import SwiftUI

/// Renders the picker window to a PNG without showing it. A development aid for checking
/// the layout; it isn't listed in the usage text.
///
///   fontpicker snapshot --out window.png [--font "Fira Code"] [--dark] [--light-pane]
///       [--shortlist "Monoid,Victor Mono"] [--drift tour|lfo|random] [--all]
///       [--width 1360] [--height 880] [--scale 2]
enum Snapshot {
    @MainActor
    static func run(_ args: inout Arguments) throws -> Int32 {
        let out = args.value("--out") ?? "fontpicker.png"
        let font = args.value("--font")
        let shortlist = args.value("--shortlist")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let drift = args.value("--drift").flatMap(DriftMode.init(rawValue:))
        let width = Double(args.value("--width") ?? "") ?? 1360
        let height = Double(args.value("--height") ?? "") ?? 880
        let scale = Double(args.value("--scale") ?? "") ?? 2
        let dark = args.flag("--dark"), lightPane = args.flag("--light-pane"), all = args.flag("--all")
        try args.finish()

        _ = NSApplication.shared
        let state = AppState(persists: false)
        state.prefs.lightPane = lightPane
        if all { state.prefs.scope = .all }
        state.loadNow(selecting: font)
        for name in shortlist {
            guard let family = state.families.first(where: { $0.short == name || $0.family == name }) else { continue }
            state.prefs.shortlist.append(family.id)
        }
        state.loadNow(selecting: font)
        if let drift {
            state.setDrift(drift)
        }

        let root = RootView()
            .environmentObject(state)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.displayScale, scale)
            .frame(width: width, height: height)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle: lazy rows, the scroll-to-selection, and a drift beat if asked for.
        RunLoop.main.run(until: Date().addingTimeInterval(drift == nil ? 0.6 : 2.2))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CLIError("couldn't allocate the bitmap") }
        bitmap.size = NSSize(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CLIError("couldn't encode the PNG") }
        try png.write(to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath))
        print("Wrote \(out) (\(Int(width * scale)) × \(Int(height * scale)))")
        return 0
    }
}
