import Foundation

// MARK: - Screenshot file names

enum Naming {
    /// "Screenshot 2026-10-13 at 10.42.07 (Safari).png". The app part is left out when unknown.
    static func fileName(date: Date, app: String?, fileExtension: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let suffix = app.map(clean).flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
        return "Screenshot \(f.string(from: date))\(suffix).\(fileExtension)"
    }

    /// Makes an app or window name safe for a file name: no slashes or colons, single spaces, at most 40 characters.
    static func clean(_ name: String) -> String {
        let replaced = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let collapsed = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(40)).trimmingCharacters(in: .whitespaces)
    }
}
