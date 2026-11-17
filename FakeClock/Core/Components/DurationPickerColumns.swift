import SwiftUI

/// Two-column hour/minute wheel picker styled after the Clock app's timer
/// setup. Used by both the authentication flow and the secret-duration editor,
/// which is what lets the lock screen read as a legitimate timer interface
/// rather than a PIN keypad.
struct DurationPickerColumns: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    var hourRange: ClosedRange<Int> = 0...23
    var minuteRange: ClosedRange<Int> = 0...59
    var columnTitles: (hours: String, minutes: String) = ("Hours", "Minutes")

    private var hourValues: [Int] { Array(hourRange) }
    private var minuteValues: [Int] { Array(minuteRange) }

    var body: some View {
        VStack(spacing: Theme.Metrics.spacingXS) {
            HStack(spacing: 0) {
                Text(columnTitles.hours)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                Text(columnTitles.minutes)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                Picker(columnTitles.hours, selection: $hours) {
                    ForEach(hourValues, id: \.self) { value in
                        Text(Self.padded(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Picker(columnTitles.minutes, selection: $minutes) {
                    ForEach(minuteValues, id: \.self) { value in
                        Text(Self.padded(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            .frame(height: 160)
        }
        .accessibilityElement(children: .contain)
    }

    static func padded(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

/// Three-column hour/minute/second wheel picker for the countdown timer.
struct TimeOfDurationPicker: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int

    var body: some View {
        VStack(spacing: Theme.Metrics.spacingXS) {
            HStack(spacing: 0) {
                columnTitle("Hours")
                columnTitle("Minutes")
                columnTitle("Seconds")
            }

            HStack(spacing: 0) {
                Picker("Hours", selection: $hours) {
                    ForEach(0...23, id: \.self) { value in
                        Text(DurationPickerColumns.padded(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Picker("Minutes", selection: $minutes) {
                    ForEach(0...59, id: \.self) { value in
                        Text(DurationPickerColumns.padded(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Picker("Seconds", selection: $seconds) {
                    ForEach(0...59, id: \.self) { value in
                        Text(DurationPickerColumns.padded(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            .frame(height: 160)
        }
        .accessibilityElement(children: .contain)
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity)
    }
}
