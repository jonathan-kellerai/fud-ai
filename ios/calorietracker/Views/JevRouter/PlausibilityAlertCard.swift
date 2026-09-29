import SwiftUI

struct PlausibilityAlertCard: View {
    var title: String
    var message: String
    var saveTitle: String = "Save anyway"
    var onSave: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Edit", action: onEdit)
                    .accessibilityIdentifier("plausibility.edit")
                Spacer()
                Button(saveTitle, action: onSave)
                    .accessibilityIdentifier("plausibility.saveAnyway")
            }
        }
        .padding(20)
        .frame(maxWidth: 420, alignment: .leading)
        .background(AppColors.appCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("plausibility.alert")
    }
}

extension View {
    func plausibilityConfirmation(
        title: String,
        message: String?,
        saveTitle: String = "Save anyway",
        onSave: @escaping () -> Void,
        onEdit: @escaping () -> Void = {}
    ) -> some View {
        alert(title, isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { onEdit() } }
        )) {
            Button(saveTitle, action: onSave)
                .accessibilityIdentifier("plausibility.saveAnyway")
            Button("Edit", role: .cancel, action: onEdit)
                .accessibilityIdentifier("plausibility.edit")
        } message: {
            Text(message ?? "")
                .accessibilityIdentifier("plausibility.alert")
        }
    }
}
