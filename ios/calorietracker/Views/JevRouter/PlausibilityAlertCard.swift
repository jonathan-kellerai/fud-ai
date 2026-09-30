import SwiftUI

struct PlausibilityAlertCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var title: String
    var message: String
    var saveTitle: String = "Save anyway"
    var onSave: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    editButton
                    saveButton
                }
            } else {
                HStack {
                    editButton
                    Spacer()
                    saveButton
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 420, alignment: .leading)
        .background(AppColors.appCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plausibility.alert")
    }

    private var editButton: some View {
        Button("Edit", action: onEdit)
            .accessibilityIdentifier("plausibility.edit")
    }

    private var saveButton: some View {
        Button(saveTitle, action: onSave)
            .fontWeight(.semibold)
            .accessibilityIdentifier("plausibility.saveAnyway")
    }
}

extension View {
    /// The confirmation users see before a flagged save. Same card as visual QA.
    func plausibilityConfirmation(
        title: String,
        message: String?,
        saveTitle: String = "Save anyway",
        onSave: @escaping () -> Void,
        onEdit: @escaping () -> Void = {}
    ) -> some View {
        overlay {
            if let message {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    PlausibilityAlertCard(
                        title: title,
                        message: message,
                        saveTitle: saveTitle,
                        onSave: onSave,
                        onEdit: onEdit
                    )
                    .padding(24)
                }
            }
        }
    }
}
