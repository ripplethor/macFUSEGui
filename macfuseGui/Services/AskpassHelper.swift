// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct AskpassContext: Sendable {
    let scriptURL: URL
    let environment: [String: String]
    let secretValues: [String]
    let temporaryDirectoryURL: URL
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class AskpassHelper {
    private let fileManager: FileManager
    private let diagnostics: DiagnosticsService?

    /// Beginner note: Initializers create valid state before any other method is used.
    init(fileManager: FileManager = .default, diagnostics: DiagnosticsService? = nil) {
        self.fileManager = fileManager
        self.diagnostics = diagnostics
    }

    /// Beginner note: This scoped helper guarantees cleanup even when callers throw.
    /// This is async and throwing: callers must await it and handle failures.
    func withContext<T>(
        password: String,
        _ operation: (AskpassContext) async throws -> T
    ) async throws -> T {
        let context = try makeContext(password: password)
        defer { cleanup(context) }
        return try await operation(context)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func makeContext(password: String) throws -> AskpassContext {
        let tempDirectoryID = UUID().uuidString
        let tmpDir = fileManager.temporaryDirectory.appendingPathComponent("macfusegui-askpass-\(tempDirectoryID)", isDirectory: true)
        try fileManager.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Directory and variable IDs are intentionally independent so one cannot be
        // derived from the other if either value is observed.
        let variableSuffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let variableName = "MACFUSEGUI_ASKPASS_PASSWORD_\(variableSuffix)"
        let allowedVariableScalars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard variableName.unicodeScalars.allSatisfy({ allowedVariableScalars.contains($0) }) else {
            throw AppError.unknown(L10n.tr("Failed to generate a safe askpass variable name."))
        }

        let scriptURL = tmpDir.appendingPathComponent("askpass.sh", isDirectory: false)

        let script = """
        #!/bin/sh
        printf "%s\\n" "${\(variableName)}"
        """

        guard fileManager.createFile(
            atPath: scriptURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw AppError.processFailure(L10n.tr("Failed to create askpass helper script."))
        }

        do {
            let handle = try FileHandle(forWritingTo: scriptURL)
            defer { try? handle.close() }
            if let data = script.data(using: .utf8) {
                try handle.write(contentsOf: data)
            } else {
                throw AppError.processFailure(L10n.tr("Failed to encode askpass helper script."))
            }
        } catch {
            throw AppError.processFailure(L10n.format("Failed to write askpass helper script: %@", error.localizedDescription))
        }

        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        // Password is delivered via one-shot environment variable consumed by SSH_ASKPASS.
        // This avoids command-line exposure, but environment values remain visible to
        // same-user process inspection for the spawned process lifetime.
        let environment: [String: String] = [
            "SSH_ASKPASS": scriptURL.path,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": "1",
            variableName: password
        ]

        return AskpassContext(
            scriptURL: scriptURL,
            environment: environment,
            secretValues: [password],
            temporaryDirectoryURL: tmpDir
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func cleanup(_ context: AskpassContext) {
        do {
            try fileManager.removeItem(at: context.temporaryDirectoryURL)
        } catch {
            let errorNS = error as NSError
            if errorNS.domain == NSCocoaErrorDomain, errorNS.code == NSFileNoSuchFileError {
                return
            }
            diagnostics?.append(
                level: .warning,
                category: "mount",
                message: "Failed to clean askpass temp directory \(context.temporaryDirectoryURL.path): \(error.localizedDescription)"
            )
        }
    }
}
