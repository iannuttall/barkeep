import Combine
import Foundation

@MainActor
final class StateStore: ObservableObject {
    @Published private(set) var document: BarkeepDocument
    @Published private(set) var lastError: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL? = nil) {
        let folder = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Barkeep", isDirectory: true)

        fileURL = folder.appendingPathComponent("state.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? decoder.decode(BarkeepDocument.self, from: data) {
            document = saved
        } else {
            document = BarkeepDocument()
        }
    }

    var settings: BarkeepSettings { document.settings }
    var rules: [String: ItemRule] { document.rules }

    func updateSettings(_ change: (inout BarkeepSettings) -> Void) {
        var updated = document
        change(&updated.settings)
        document = updated
        save()
    }

    func setRule(for item: MenuBarItemSnapshot, zone: VisibilityZone) {
        var updated = document
        updated.rules[item.id] = ItemRule(
            id: item.id,
            displayName: item.displayName,
            ownerName: item.ownerName,
            bundleIdentifier: item.bundleIdentifier,
            zone: zone,
            group: document.rules[item.id]?.group
        )
        document = updated
        save()
    }

    func removeRule(id: String) {
        var updated = document
        updated.rules[id] = nil
        document = updated
        save()
    }

    func saveProfile(named name: String) {
        var updated = document
        updated.profiles.append(
            BarkeepProfile(name: name, rules: document.rules, settings: document.settings)
        )
        document = updated
        save()
    }

    func loadProfile(id: UUID) {
        guard let profile = document.profiles.first(where: { $0.id == id }) else { return }
        var updated = document
        updated.rules = profile.rules
        updated.settings = profile.settings
        document = updated
        save()
    }

    func deleteProfile(id: UUID) {
        var updated = document
        updated.profiles.removeAll { $0.id == id }
        document = updated
        save()
    }

    func exportData() throws -> Data {
        try encoder.encode(document)
    }

    func importData(_ data: Data) throws {
        let imported = try decoder.decode(BarkeepDocument.self, from: data)
        guard imported.version == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = imported
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
