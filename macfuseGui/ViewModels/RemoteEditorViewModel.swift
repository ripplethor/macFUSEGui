// BEGINNER FILE GUIDE
// Layer: View model orchestration layer
// Purpose: This file transforms service-level behavior into UI-ready state and user actions.
// Called by: Called by SwiftUI views and menu controllers in response to user input.
// Calls into: Calls into services and publishes state changes back to the UI.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class RemoteEditorViewModel: ObservableObject {
    @Published var draft: RemoteDraft {
        didSet {
            guard draft != oldValue else {
                return
            }
            clearDraftFeedback()
        }
    }
    @Published var validationErrors: [String] = []
    @Published var isSaving: Bool = false
    @Published var isTestingConnection: Bool = false
    @Published var testResultMessage: String?
    @Published var testResultIsSuccess: Bool = false

    var isEditingExistingRemote: Bool { draft.id != nil }

    /// Beginner note: Initializers create valid state before any other method is used.
    init(draft: RemoteDraft) {
        self.draft = draft
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func save(using remotesViewModel: RemotesViewModel) async -> Result<UUID, AppError> {
        guard !isSaving else {
            if !validationErrors.isEmpty {
                return .failure(.validationFailed(validationErrors))
            }
            return .failure(.unknown(L10n.tr("Save is already in progress.")))
        }

        isSaving = true
        defer { isSaving = false }
        clearTestResult()

        let draftSnapshot = draft
        await Task.yield()

        let resolvedID = draftSnapshot.id ?? UUID()
        var draftForSave = draftSnapshot
        draftForSave.id = resolvedID

        let errors = remotesViewModel.saveDraft(draftForSave)
        validationErrors = errors

        if errors.isEmpty {
            draft.id = resolvedID
            return .success(resolvedID)
        }

        return .failure(.validationFailed(errors))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func runConnectionTest(using remotesViewModel: RemotesViewModel) async {
        isTestingConnection = true
        testResultMessage = nil
        testResultIsSuccess = false
        defer { isTestingConnection = false }

        let result = await remotesViewModel.testConnection(for: draft)
        switch result {
        case .success(let message):
            validationErrors = []
            testResultMessage = message
            testResultIsSuccess = true
        case .failure(let error):
            validationErrors = []
            testResultMessage = error.localizedDescription
            testResultIsSuccess = false
        }
    }

    private func clearTestResult() {
        testResultMessage = nil
        testResultIsSuccess = false
    }

    private func clearDraftFeedback() {
        validationErrors = []
        clearTestResult()
    }
}
