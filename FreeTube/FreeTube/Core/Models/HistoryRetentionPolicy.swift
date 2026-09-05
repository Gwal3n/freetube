import Foundation

enum HistoryRetentionPolicy: String, CaseIterable, Identifiable {
    case forever
    case oneWeek
    case oneMonth
    case threeMonths
    case oneYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever: "Forever"
        case .oneWeek: "1 Week"
        case .oneMonth: "1 Month"
        case .threeMonths: "3 Months"
        case .oneYear: "1 Year"
        }
    }

    func cutoffDate(relativeTo date: Date = Date()) -> Date? {
        let component: DateComponents
        switch self {
        case .forever: return nil
        case .oneWeek: component = DateComponents(day: -7)
        case .oneMonth: component = DateComponents(month: -1)
        case .threeMonths: component = DateComponents(month: -3)
        case .oneYear: component = DateComponents(year: -1)
        }
        return Calendar.current.date(byAdding: component, to: date)
    }
}
