// BEGINNER FILE GUIDE
// Layer: SwiftUI view layer
// Purpose: This file defines visual layout and interaction controls shown to the user.
// Called by: Instantiated by parent views, window controllers, or app bootstrap code.
// Calls into: Reads observed state from view models and triggers callbacks for actions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import SwiftUI

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct StatusBadgeView: View {
    private let state: RemoteStatusBadgeState

    /// Beginner note: Initializers create valid state before any other method is used.
    init(state: RemoteStatusBadgeState) {
        self.state = state
    }

    /// Beginner note: This initializer is compatibility-only.
    @available(*, deprecated, message: "Prefer init(state:) for compile-time safety.")
    init(stateRawValue: String) {
        if let state = RemoteStatusBadgeState(rawValue: stateRawValue) {
            self.state = state
        } else {
            assertionFailure("Unknown status badge state raw value: \(stateRawValue)")
            self.state = .disconnected
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.badgeColor)
                .frame(width: 6, height: 6)

            Text(state.displayLabel)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(state.badgeColor.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(state.badgeColor.opacity(0.20), lineWidth: 1)
        )
        .foregroundStyle(state.badgeColor)
            .accessibilityLabel(L10n.format("Status: %@", state.displayLabel))
    }
}

private extension RemoteStatusBadgeState {
    var displayLabel: String {
        switch self {
        case .connected:
            return L10n.tr("Connected")
        case .reconnecting:
            return L10n.tr("Reconnecting")
        case .connecting:
            return L10n.tr("Connecting")
        case .disconnecting:
            return L10n.tr("Disconnecting")
        case .error:
            return L10n.tr("Error")
        case .disconnected:
            return L10n.tr("Disconnected")
        }
    }

    var badgeColor: Color {
        switch self {
        case .connected:
            return .green
        case .reconnecting, .connecting, .disconnecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .secondary
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        StatusBadgeView(state: .connected)
        StatusBadgeView(state: .connecting)
        StatusBadgeView(state: .reconnecting)
        StatusBadgeView(state: .disconnecting)
        StatusBadgeView(state: .error)
        StatusBadgeView(state: .disconnected)
    }
    .padding()
}
