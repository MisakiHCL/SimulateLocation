import Foundation

enum ExportFileNameFormatter {
    private static let baseName = "SelectedLocation"
    private static let fileExtension = "gpx"
    private static let timestampFormat = "MM-dd_HH:mm"

    static func gpxFileName(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = timestampFormat

        return "\(baseName)_\(formatter.string(from: date)).\(fileExtension)"
    }
}
