import SwiftUI

/// Sheet for creating or editing one alarm (§6). Hours/minutes use a native
/// wheel picker; weekday repeat is a tappable row.
struct AlarmEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var hour: Int
    @State private var minute: Int
    @State private var label: String
    @State private var repeatDays: Set<Weekday>
    @State private var sound: AlertSound
    @State private var repeatToggle: Bool

    let mode: Mode
    let save: (Alarm) -> Void

    enum Mode {
        case create
        case edit(Alarm)

        var isEdit: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    init(mode: Mode, save: @escaping (Alarm) -> Void) {
        self.mode = mode
        self.save = save
        switch mode {
        case .create:
            hour = 0
            minute = 0
            label = ""
            repeatDays = []
            sound = .default
            repeatToggle = false
        case .edit(let alarm):
            hour = alarm.hour
            minute = alarm.minute
            label = alarm.label
            repeatDays = alarm.repeatDays
            sound = alarm.sound
            repeatToggle = !alarm.repeatDays.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    Picker("Hour", selection: $hour) {
                        ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)) }
                    }
                    .pickerStyle(.wheel)

                    Picker("Minute", selection: $minute) {
                        ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section("Label") {
                    TextField("Alarm (optional)", text: $label)
                        .textAutocapitalization(.sentences)
                }

                Section("Sound") {
                    Picker("Sound", selection: $sound) {
                        ForEach(AlertSound.allCases) { sound in
                            Text(sound.label).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Repeat") {
                    Toggle("Repeat", isOn: $repeatToggle)
                    if repeatToggle {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                            ForEach(Weekday.allCases) { day in
                                let isOn = repeatDays.contains(day)
                                Button {
                                    if isOn { repeatDays.remove(day) } else { repeatDays.insert(day) }
                                } label: {
                                    Text(day.shortSymbol)
                                        .font(Theme.Typography.captionStrong)
                                        .foregroundStyle(isOn ? .white : Theme.Palette.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, Theme.Metrics.spacingS)
                                        .background(Capsule().fill(isOn ? Theme.Palette.accent : Theme.Palette.surfaceElevated))
                                }
                                .accessibilityLabel(Text(day.fullSymbol))
                                .accessibilityValue(Text(isOn ? "Selected" : "Not selected"))
                            }
                        }
                        .padding(.vertical, Theme.Metrics.spacingXS)
                    }
                }
            }
            .navigationTitle(mode.isEdit ? "Edit Alarm" : "New Alarm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save(alarmForSave())
                        dismiss()
                    }
                    .disabled(!isValid)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    private func alarmForSave() -> Alarm {
        let existing: Alarm? = {
            if case .edit(let alarm) = mode { return alarm }
            return nil
        }()
        return Alarm(
            id: existing?.id ?? UUID(),
            hour: hour,
            minute: minute,
            label: label,
            isEnabled: existing?.isEnabled ?? true,
            repeatDays: repeatToggle ? repeatDays : [],
            sound: sound,
            consumed: existing?.consumed ?? false
        )
    }
}