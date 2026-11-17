import SwiftUI

/// Sheet for finding and adding cities (§5). Searches Foundation's IANA zone
/// catalog offline — no network, no external service (§2).
struct CitySearchView: View {
    @ObservedObject var viewModel: WorldClockViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    /// Cities already in the list are dimmed and non-selectable so the user
    /// sees *why* a row is unresponsive — never color alone (§15).
    private var results: [WorldCity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Sensible starting point: popular zones, already-added removed.
            return Array(CitySearchIndex.shared.popular.filter { !viewModel.contains($0) }.prefix(40))
        }
        return CitySearchIndex.shared.catalog
            .filter { $0.matches(query: trimmed) }
            .filter { !viewModel.contains($0) }
            .prefix(80)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        ForEach(results) { city in
                            row(city)
                        }
                    } header: {
                        Text("Popular")
                    }
                } else {
                    Section {
                        if results.isEmpty {
                            Text("No matches for “\(query)”.")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        } else {
                            ForEach(results) { city in
                                row(city)
                            }
                        }
                    } header: {
                        Text("Results")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search city")
            .navigationTitle("Add City")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ city: WorldCity) -> some View {
        Button {
            viewModel.add(city)
            HapticsService.shared.light()
        } label: {
            HStack(spacing: Theme.Metrics.spacingM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.displayName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(city.regionName)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundStyle(Theme.Palette.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search index

/// Offline city catalog plus fuzzy matching, isolated so view code stays thin
/// and the matching rules are unit-testable.
final class CitySearchIndex {
    static let shared = CitySearchIndex()

    let catalog: [WorldCity]
    /// Curated first-run list so the sheet is useful with an empty query.
    let popular: [WorldCity]

    private static let popularIdentifiers = [
        "Asia/Kolkata",
        "Asia/Dubai",
        "Asia/Singapore",
        "Asia/Tokyo",
        "Asia/Shanghai",
        "Australia/Sydney",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "Europe/Moscow",
        "America/New_York",
        "America/Chicago",
        "America/Los_Angeles",
        "America/Sao_Paulo",
        "Africa/Cairo",
        "Pacific/Auckland",
    ]

    init() {
        let built = WorldCity.catalog()
        self.catalog = built
        let byIdentifier = Dictionary(uniqueKeysWithValues: built.map { ($0.timeZoneIdentifier, $0) })
        self.popular = Self.popularIdentifiers.compactMap { byIdentifier[$0] }
    }
}

extension WorldCity {
    /// Case/diacritic-insensitive match against the city, region, and the
    /// full IANA identifier (so "kolkata", "cal", "india" style queries all
    /// work reasonably).
    func matches(query: String) -> Bool {
        let haystack = "\(displayName) \(regionName) \(timeZoneIdentifier)"
        return haystack.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .contains(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
    }
}
