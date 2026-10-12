import Foundation

/// The parts of the dashboard that can be minimised.
enum DashboardSection: String, CaseIterable {
    case summary, chart, monthToDate, owed, byMonth, recent
}

/// Which sections are minimised, as a comma-separated string so it can live
/// in a single `@AppStorage` value. Unknown names (from an older or newer
/// version of the app) are ignored.
struct CollapsedSections: Equatable {
    private(set) var sections: Set<DashboardSection>

    init(raw: String) {
        sections = Set(raw.split(separator: ",").compactMap { DashboardSection(rawValue: String($0)) })
    }

    var raw: String {
        sections.map(\.rawValue).sorted().joined(separator: ",")
    }

    func contains(_ section: DashboardSection) -> Bool { sections.contains(section) }

    mutating func toggle(_ section: DashboardSection) {
        if sections.contains(section) { sections.remove(section) } else { sections.insert(section) }
    }
}
