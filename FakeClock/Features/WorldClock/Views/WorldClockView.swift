import SwiftUI

/// World Clock tab (§5). A large local clock header above a list of city
/// cards, with add/search, reorder, and a settings entry point.
struct WorldClockView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var viewModel: WorldClockViewModel

    init(persistence: PersistenceServicing = PersistenceService(defaults: .standard)) {
        // Both this view model and AppState talk to the same UserDefaults
        // suite, so city data stays consistent; the view model is the source
        // of truth while the tab is mounted.
        _viewModel = StateObject(wrappedValue: WorldClockViewModel(persistence: persistence))
    }

    var body: some View {
        // 1-second cadence: a wall-clock display legitimately redraws on the
        // calendar second (the monotonic-timestamp rule applies to *elapsed*
        // intervals like the stopwatch and countdown, not to "what time is it").
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: Theme.Metrics.spacingM) {
                        LocalClockHeader(now: now, settings: app.settings)
                            .padding(.top, Theme.Metrics.spacingS)

                        cityList(now: now)
                    }
                    .padding(.horizontal, Theme.Metrics.spacingL)
                    .padding(.bottom, Theme.Metrics.spacingXL)
                }
                .background(Theme.Palette.background.ignoresSafeArea())
                .navigationTitle("World Clock")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                            .accessibilityLabel("Reorder cities")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.showingSearch = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add a city")
                        .accessibilityIdentifier(A11y.addCityButton)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsLinkCompat {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .sheet(isPresented: $viewModel.showingSearch) {
                    CitySearchView(viewModel: viewModel)
                }
                .environmentObject(app)
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        .accessibilityIdentifier(A11y.worldClockScreen)
    }

    @ViewBuilder
    private func cityList(now: Date) -> some View {
        ForEach(viewModel.cities) { city in
            CityRow(
                city: city,
                now: now,
                use24Hour: app.settings.use24HourClock,
                viewModel: viewModel
            )
        }
        .onDelete { offsets in
            viewModel.remove(at: offsets)
        }
        .onMove { source, destination in
            viewModel.move(from: source, to: destination)
        }
    }
}

// MARK: - Local header

/// The default-time-zone hero clock: big time, date/day, zone line, and a
/// day/night glyph.
struct LocalClockHeader: View {
    let now: Date
    let settings: AppSettings

    @Environment(\.calendar) private var calendar

    private var timeText: String {
        TimeFormat.clockTimeWithSeconds(for: now, calendar: calendar, use24Hour: settings.use24HourClock)
    }

    private var dateText: String {
        TimeFormat.dateLine(for: now, calendar: calendar)
    }

    private var zoneText: String {
        let name = calendar.timeZone.localizedName(
            for: .standard,
            locale: .current
        ) ?? calendar.timeZone.identifier
        return "\(name) · \(TimeFormat.gmtOffset(for: calendar.timeZone, date: now))"
    }

    private var isDaytime: Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= 6 && hour < 18
    }

    var body: some View {
        VStack(spacing: Theme.Metrics.spacingS) {
            HStack(alignment: .top, spacing: Theme.Metrics.spacingM) {
                Text(timeText)
                    .font(Theme.Typography.display(46))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer(minLength: Theme.Metrics.spacingS)

                Image(systemName: isDaytime ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isDaytime ? Theme.Palette.warning : Theme.Palette.accent)
                    .accessibilityHidden(true)
            }

            HStack {
                Text(dateText)
                Spacer()
                Text(zoneText)
            }
            .font(Theme.Typography.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Metrics.spacingL)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Local time \(timeText), \(dateText), \(isDaytime ? "daytime" : "nighttime")"))
        .accessibilitySortPriority(1)
    }
}

// MARK: - City row

struct CityRow: View {
    let city: WorldCity
    let now: Date
    let use24Hour: Bool
    @ObservedObject var viewModel: WorldClockViewModel

    private var timeText: String {
        viewModel.timeString(for: city, now: now, use24Hour: use24Hour)
    }

    private var dayPrefix: String {
        let delta = viewModel.dayDifference(for: city, now: now)
        switch delta {
        case ..<0: return "Yesterday "
        case 1...: return "Tomorrow "
        default: return ""
        }
    }

    private var isDaytime: Bool {
        viewModel.isDay(for: city, now: now)
    }

    private var bigTimeFont: Font {
        // Shrink for narrow devices (SE) so 5-6 digit times never truncate.
        .system(size: 38, weight: .regular, design: .rounded).monospacedDigit()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Metrics.spacingM) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Metrics.spacingXS) {
                    Image(systemName: isDaytime ? "sun.max" : "moon.stars")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .accessibilityHidden(true)
                    Text(city.regionName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .textCase(.uppercase)
                }

                Text(city.displayName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(viewModel.offsetLabel(for: city, now: now))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer(minLength: Theme.Metrics.spacingM)

            VStack(alignment: .trailing, spacing: 2) {
                if !dayPrefix.isEmpty {
                    Text(dayPrefix.trimmingCharacters(in: .whitespaces))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.accent)
                }
                Text(timeText)
                    .font(bigTimeFont)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, Theme.Metrics.spacingL)
        .padding(.vertical, Theme.Metrics.spacingM)
        .frame(minHeight: 72)
        .cardStyle(cornerRadius: Theme.Metrics.cornerM)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        "\(city.displayName), \(city.regionName). \(timeText)\(dayPrefix.isEmpty ? "" : ", \(dayPrefix.trimmingCharacters(in: .whitespaces))"). \(isDaytime ? "Daytime" : "Nighttime"). \(viewModel.offsetLabel(for: city, now: now))"
    }
}
