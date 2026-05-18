import SwiftUI

struct CircleToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case error
        case info
    }

    let id = UUID()
    let text: String
    let style: Style
}

struct CircleToastView: View {
    let message: CircleToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)

            Text(message.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
    }

    private var iconName: String {
        switch message.style {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch message.style {
        case .success:
            return Color(red: 0.23, green: 0.68, blue: 0.28)
        case .error:
            return .red
        case .info:
            return .secondary
        }
    }
}
