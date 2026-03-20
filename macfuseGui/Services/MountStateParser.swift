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
final class MountStateParser {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func parseMountOutput(_ output: String) -> [MountRecord] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let lineString = String(line)
                guard let typeStart = lineString.range(of: " (", options: .backwards) else {
                    return nil
                }
                guard let onRange = lineString.range(
                    of: " on ",
                    options: .backwards,
                    range: lineString.startIndex..<typeStart.lowerBound
                ) else {
                    return nil
                }
                guard let typeEnd = lineString[typeStart.upperBound...].firstIndex(of: ")") else {
                    return nil
                }

                let source = decodeEscapedMountField(
                    lineString[..<onRange.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let mountPoint = decodeEscapedMountField(
                    lineString[onRange.upperBound..<typeStart.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let fsType = lineString[typeStart.upperBound..<typeEnd]
                    .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard !source.isEmpty, !mountPoint.isEmpty, !fsType.isEmpty else {
                    return nil
                }

                return MountRecord(source: source, mountPoint: mountPoint, filesystemType: fsType)
            }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func record(forMountPoint mountPoint: String, from records: [MountRecord]) -> MountRecord? {
        let normalizedTarget = normalize(mountPoint)
        return records.first { normalize($0.mountPoint) == normalizedTarget }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func normalize(_ path: String) -> String {
        // Keep this lexical-only (no symlink resolution) so status probes avoid filesystem I/O.
        LocalPathNormalizer.normalize(path)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func decodeEscapedMountField(_ value: String) -> String {
        let characters = Array(value)
        var output = String()
        output.reserveCapacity(characters.count)
        var index = 0

        while index < characters.count {
            let current = characters[index]
            guard current == "\\" else {
                output.append(current)
                index += 1
                continue
            }

            guard index + 1 < characters.count else {
                output.append("\\")
                index += 1
                continue
            }

            let next = characters[index + 1]
            if next == "\\" {
                output.append("\\")
                index += 2
                continue
            }

            if index + 3 < characters.count {
                let octal1 = characters[index + 1]
                let octal2 = characters[index + 2]
                let octal3 = characters[index + 3]
                if octal1.isOctalDigit, octal2.isOctalDigit, octal3.isOctalDigit {
                    let octalText = String([octal1, octal2, octal3])
                    if let scalarValue = UInt32(octalText, radix: 8),
                       let scalar = UnicodeScalar(scalarValue) {
                        output.unicodeScalars.append(scalar)
                        index += 4
                        continue
                    }
                }
            }

            // Preserve unknown escapes as-is.
            output.append("\\")
            output.append(next)
            index += 2
        }

        return output
    }
}

private extension Character {
    var isOctalDigit: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }
        return scalar.value >= 48 && scalar.value <= 55
    }
}
