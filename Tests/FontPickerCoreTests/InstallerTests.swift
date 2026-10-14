import Foundation
import Testing

@testable import FontPickerCore

/// `install.sh` carries its own list of what to download, because it has to run before
/// anything is built. That list has to offer exactly the families the picker is curated for.
@Suite struct InstallerManifestTests {
    struct Row {
        let name: String
        let megabytes: String
        let families: [String]
        let url: String?
    }

    /// The lines between `<<'FONTS'` and `FONTS` in `install.sh`.
    private func rows() throws -> [Row] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let lines = try String(contentsOf: root.appendingPathComponent("install.sh"), encoding: .utf8).components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasSuffix("<<'FONTS'") })
        let end = try #require(lines.firstIndex(of: "FONTS"))
        return lines[(start + 1)..<end].map { line in
            let fields = line.components(separatedBy: "|")
            return Row(
                name: fields[0], megabytes: fields.count > 1 ? fields[1] : "",
                families: fields.count > 2 ? fields[2].components(separatedBy: ",") : [],
                url: fields.count > 3 ? fields[3] : nil)
        }
    }

    @Test func itInstallsExactlyTheCuratedFamilies() throws {
        let offered = Set(try rows().flatMap(\.families))
        let curated = Set(SeedCatalog.entries.map(\.family))
        #expect(curated.subtracting(offered).isEmpty, "curated but never installed")
        #expect(offered.subtracting(curated).isEmpty, "installed but not curated")
    }

    @Test func everyRowIsComplete() throws {
        let rows = try rows()
        #expect(!rows.isEmpty)
        for row in rows {
            #expect(!row.name.isEmpty && !row.name.contains(" "), "\(row.name)")
            #expect(Int(row.megabytes) != nil, "\(row.name)")
            #expect(!row.families.isEmpty && row.families.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) }, "\(row.name)")
            if let url = row.url { #expect(url.hasPrefix("https://"), "\(row.name)") }
        }
    }

    @Test func nothingIsListedTwice() throws {
        let rows = try rows()
        #expect(Set(rows.map(\.name)).count == rows.count)
        let families = rows.flatMap(\.families)
        #expect(Set(families).count == families.count)
    }
}
