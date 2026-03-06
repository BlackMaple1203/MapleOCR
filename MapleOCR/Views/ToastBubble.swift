import SwiftUI

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let isSuccess: Bool
}

struct ToastBubble: View {
    let toast: ToastItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.isSuccess
                  ? "checkmark.circle.fill"
                  : "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(toast.isSuccess ? .green : .red)
                .padding(.top, 1)

            Text(toast.message)
                .font(.system(size: 12.5))
                .foregroundColor(.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    toast.isSuccess
                        ? Color.green.opacity(0.25)
                        : Color.red.opacity(0.25),
                    lineWidth: 1
                )
        )
    }
}
