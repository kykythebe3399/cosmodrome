import Foundation

/// Heuristic task classification based on event patterns within a task block.
/// Zero-LLM — uses file paths, event kinds, and command patterns.
public enum TaskClassification: String, CaseIterable {
    case refactor
    case feature
    case bugfix
    case test
    case docs
    case unknown
}

public struct TaskClassifier {

    /// Classify a task based on its events.
    public static func classify(events: [ActivityEvent]) -> TaskClassification {
        var newFiles = 0
        var editedFiles = Set<String>()
        var testFilesChanged = Set<String>()
        var docFilesChanged = 0
        var errorsBefore = false
        var hasTestCommands = false
        var totalWrites = 0

        for event in events {
            switch event.kind {
            case .fileWrite(let path, _, _):
                totalWrites += 1
                editedFiles.insert(path)
                if isTestFile(path) {
                    testFilesChanged.insert(path)
                }
                if isDocFile(path) {
                    docFilesChanged += 1
                }
            case .fileRead(let path):
                if isTestFile(path) {
                    testFilesChanged.insert(path)
                }
            case .commandRun(let cmd):
                if isTestCommand(cmd) {
                    hasTestCommands = true
                }
            case .commandCompleted(let cmd, _, _):
                if let cmd, isTestCommand(cmd) {
                    hasTestCommands = true
                }
            case .error:
                // Errors at the start of the task suggest a bugfix
                if editedFiles.isEmpty {
                    errorsBefore = true
                }
            default:
                break
            }
        }

        let nonTestFiles = editedFiles.subtracting(testFilesChanged)

        // Docs: only doc files changed
        if docFilesChanged > 0 && nonTestFiles.isEmpty && testFilesChanged.isEmpty {
            return .docs
        }

        // Test: only test files changed, or only test commands run
        if !testFilesChanged.isEmpty && nonTestFiles.isEmpty {
            return .test
        }

        // Bugfix: errors preceded the work, relatively few files changed
        if errorsBefore && nonTestFiles.count <= 5 {
            return .bugfix
        }

        // Feature: new test files + source files (suggests adding new functionality)
        if !testFilesChanged.isEmpty && !nonTestFiles.isEmpty && nonTestFiles.count >= 2 {
            return .feature
        }

        // Refactor: many file edits, no new test files, no errors
        if nonTestFiles.count >= 3 && testFilesChanged.isEmpty && !errorsBefore {
            return .refactor
        }

        // Feature: few files, but with test commands
        if !nonTestFiles.isEmpty && hasTestCommands && !errorsBefore {
            return .feature
        }

        return .unknown
    }

    // MARK: - Helpers

    private static func isTestFile(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("test") || lower.contains("spec")
            || lower.hasSuffix("_test.go") || lower.hasSuffix("_test.swift")
            || lower.hasSuffix(".test.ts") || lower.hasSuffix(".test.js")
            || lower.hasSuffix(".spec.ts") || lower.hasSuffix(".spec.js")
    }

    private static func isDocFile(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".md") || lower.hasSuffix(".rst")
            || lower.hasSuffix(".txt") || lower.contains("readme")
            || lower.contains("changelog") || lower.contains("doc/")
            || lower.contains("docs/")
    }

    private static func isTestCommand(_ cmd: String) -> Bool {
        let lower = cmd.lowercased()
        return lower.contains("test") || lower.contains("pytest")
            || lower.contains("jest") || lower.contains("mocha")
            || lower.contains("rspec") || lower.contains("cargo test")
            || lower.contains("go test") || lower.contains("swift test")
            || lower.contains("npm test") || lower.contains("yarn test")
    }
}
