// BEGINNER FILE GUIDE
// Layer: SwiftUI view layer
// Purpose: This file defines visual layout and interaction controls shown to the user.
// Called by: Instantiated by parent views, window controllers, or app bootstrap code.
// Calls into: Reads observed state from view models and triggers callbacks for actions.
// Concurrency: Contains async functions; these can suspend and resume without blocking the calling thread.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import SwiftUI

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct RemotesListView: View {
    let remotes: [RemoteConfig]
    let statuses: [UUID: RemoteStatus]
    let badgeStateForRemote: (UUID) -> RemoteStatusBadgeState
    @Binding var selectedRemoteID: UUID?
    let onConnect: (UUID) -> Void
    let onDisconnect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(remotes) { remote in
                        row(remote)
                            .id(remote.id)
                    }
                }
            }
            .padding(.vertical, 2)
            .onValueChange(of: selectedRemoteID) {
                scrollSelectionToTop(using: scrollProxy)
            }
            .onValueChange(of: remotes) {
                scrollSelectionToTop(using: scrollProxy)
            }
        }
    }

    @ViewBuilder
    /// Beginner note: This method is one step in the feature workflow for this file.
    private func row(_ remote: RemoteConfig) -> some View {
        let status = status(for: remote.id)
        let badgeState = badgeStateForRemote(remote.id)
        let isSelected = selectedRemoteID == remote.id

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(remote.displayName)
                        .font(.headline.weight(.semibold))

                    Text("\(remote.username)@\(remote.host):\(remote.port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                StatusBadgeView(state: badgeState)
            }

            infoLine(
                title: "Remote",
                systemImage: "folder",
                value: remote.remoteDirectory
            )

            infoLine(
                title: "Local",
                systemImage: "internaldrive",
                value: remote.localMountPoint
            )

            if let error = status.lastError, !error.isEmpty {
                Text(shortError(error))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.10))
                    )
            }

            HStack(spacing: 8) {
                primaryActionButton(for: remote, status: status)

                if isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            selectedRemoteID = remote.id
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isSelected
                        ? Color.blue.opacity(0.12)
                        : Color(NSColor.controlBackgroundColor).opacity(0.74)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.blue.opacity(0.38)
                        : badgeStateOutlineColor(badgeState),
                    lineWidth: 1
                )
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func shortError(_ message: String) -> String {
        message.collapsedAndTruncatedForDisplay(limit: 180)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func scrollSelectionToTop(using scrollProxy: ScrollViewProxy) {
        guard let selectedRemoteID else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(selectedRemoteID, anchor: .top)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func status(for remoteID: UUID) -> RemoteStatus {
        statuses[remoteID] ?? .initial
    }

    @ViewBuilder
    private func primaryActionButton(for remote: RemoteConfig, status: RemoteStatus) -> some View {
        switch status.state {
        case .connected:
            Button {
                onDisconnect(remote.id)
            } label: {
                Label("Disconnect", systemImage: "bolt.slash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
            .accessibilityLabel("Disconnect from \(remote.displayName)")
        case .connecting:
            Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                )
        case .disconnecting:
            Label("Disconnecting", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
        case .disconnected, .error:
            Button {
                onConnect(remote.id)
            } label: {
                Label("Connect", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.small)
            .disabled(!status.canConnect)
            .accessibilityLabel("Connect to \(remote.displayName)")
        }
    }

    private func infoLine(title: String, systemImage: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func badgeStateOutlineColor(_ state: RemoteStatusBadgeState) -> Color {
        switch state {
        case .connected:
            return Color.green.opacity(0.22)
        case .reconnecting, .connecting, .disconnecting:
            return Color.orange.opacity(0.22)
        case .error:
            return Color.red.opacity(0.24)
        case .disconnected:
            return Color.primary.opacity(0.08)
        }
    }
}

private extension View {
    @ViewBuilder
    func onValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping () -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, _ in
                action()
            }
        } else {
            onChange(of: value) { _ in
                action()
            }
        }
    }
}
