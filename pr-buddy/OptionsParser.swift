import ArgumentParser
import Foundation

enum OptionsParser {
    private enum ParsedIntRange {
        case exact(String)
        case bounds(min: String, max: String)
        case invalid

        init(parts: [String]) {
            if parts.count == 1 {
                self = .exact(parts[0])
            } else if parts.count == 2 {
                self = .bounds(min: parts[0], max: parts[1])
            } else {
                self = .invalid
            }
        }
    }

    static func validate(_ options: Options) throws {
        if let minChangedFiles = options.changedFilesRange.min,
           let maxChangedFiles = options.changedFilesRange.max,
           minChangedFiles > maxChangedFiles {
            throw ValidationError("--min-files cannot be greater than --max-files.")
        }

        if let minReviews = options.reviewsRange.min,
           let maxReviews = options.reviewsRange.max,
           minReviews > maxReviews {
            throw ValidationError("--reviews minimum cannot be greater than maximum.")
        }

        if options.limit < 1 {
            throw ValidationError("--limit must be greater than zero.")
        }

        if let repo = options.repo, repo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--repo cannot be empty.")
        }

#if DEBUG
        if let debugJSONPath = options.debugJSONPath,
           debugJSONPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--debug-json cannot be empty.")
        }
#endif
    }

    static func splitCSV(_ values: [String]) -> [String] {
        values.flatMap(splitCSV)
    }

    static func splitCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func applyChangedFilesRange(_ value: String, to options: inout Options) throws {
        let range = try parseIntRange(value, option: "--changed-files")
        options.minChangedFiles = range.min
        options.maxChangedFiles = range.max
    }

    static func applyReviewsRange(_ value: String, to options: inout Options) throws {
        let range = try parseIntRange(value, option: "--reviews")
        options.minReviews = range.min
        options.maxReviews = range.max
    }

    private static func parseInt(_ value: String, option: String) throws -> Int {
        guard let integer = Int(value) else {
            throw ValidationError("\(option) expects a number.")
        }

        return integer
    }

    private static func parseIntRange(_ value: String, option: String) throws -> CountRange {
        if value.contains("...") {
            throw ValidationError("\(option) uses two dots, for example 2..8.")
        }

        let parts = value.components(separatedBy: "..")

        switch ParsedIntRange(parts: parts) {
        case .exact(let value):
            let count = try parseInt(value, option: option)
            return CountRange(min: count, max: count)
        case .bounds(let minValue, let maxValue):
            let min = minValue.isEmpty ? nil : try parseInt(minValue, option: option)
            let max = maxValue.isEmpty ? nil : try parseInt(maxValue, option: option)
            return CountRange(min: min, max: max)
        case .invalid:
            throw ValidationError("\(option) expects a number or range, for example 3, 2..8, ..5, or 10..")
        }
    }
}
