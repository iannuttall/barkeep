import AppKit
import SwiftUI

struct SearchPanelView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filteredItems: [MenuBarItemSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return coordinator.items }
        return coordinator.items.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
            $0.ownerName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find a menu bar item", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if coordinator.isScanning {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            List(filteredItems) { item in
                Button {
                    Task { await coordinator.activate(item) }
                } label: {
                    HStack(spacing: 10) {
                        AppIconForSearch(bundleIdentifier: item.bundleIdentifier)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayName)
                            Text("\(item.ownerName) · \(coordinator.currentZone(for: item).title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)

            if filteredItems.isEmpty && !coordinator.isScanning {
                Text("No matching items")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(minWidth: 380, minHeight: 360)
        .onAppear { searchFocused = true }
    }
}

private struct AppIconForSearch: View {
    let bundleIdentifier: String?

    var body: some View {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 24, height: 24)
        }
    }
}
