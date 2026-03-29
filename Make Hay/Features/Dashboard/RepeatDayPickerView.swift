//
//  RepeatDayPickerView.swift
//  Make Hay
//
//  Created by Ethan Olson on 3/27/26.
//

import SwiftUI

/// A sub-screen listing all seven days of the week with toggles.
///
/// **Why a dedicated view?** The repeat picker is a navigation destination pushed
/// from `GoalConfigurationView`. Isolating it keeps the parent view lean and lets
/// users focus on day selection without distraction.
struct RepeatDayPickerView: View {

    @Binding var selectedDays: Set<Weekday>

    var body: some View {
        List {
            ForEach(Weekday.orderedCases) { day in
                Button {
                    toggleDay(day)
                } label: {
                    HStack {
                        Text(day.fullName)
                            .foregroundStyle(.primary)

                        Spacer()

                        if selectedDays.contains(day) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityIdentifier("repeatDay.\(day.rawValue)")
            }
        }
        .navigationTitle(String(localized: "Repeat"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if selectedDays.isEmpty {
                Text("With no days selected, the goal will apply today only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private func toggleDay(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}

// MARK: - Preview

#Preview("All Days Selected") {
    NavigationStack {
        RepeatDayPickerView(selectedDays: .constant(Set(Weekday.allCases)))
    }
}

#Preview("Weekdays Only") {
    NavigationStack {
        RepeatDayPickerView(selectedDays: .constant([.monday, .tuesday, .wednesday, .thursday, .friday]))
    }
}

#Preview("No Days Selected") {
    NavigationStack {
        RepeatDayPickerView(selectedDays: .constant([]))
    }
}
