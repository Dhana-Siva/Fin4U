import SwiftUI
import Charts

/// Spend for each month of one year as bars. Tap a bar to open that month.
struct MonthlyChart: View {
    let series: [MonthPoint]
    let currency: String
    /// The month number to highlight (the current one, in the current year).
    let highlightedMonth: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        Chart(series) { point in
            BarMark(
                x: .value("Month", point.label),
                y: .value("Spent", Double(point.cents) / 100)
            )
            .foregroundStyle(point.month == highlightedMonth ? Color.accentColor : Color.accentColor.opacity(0.55))
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: currency).precision(.fractionLength(0)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                // A plain tap (not a drag), so scrolling the page still works.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geometry[plot].origin.x
                        if let label = proxy.value(atX: x, as: String.self),
                           let point = series.first(where: { $0.label == label }),
                           point.cents != 0 {
                            onSelect(point.month)
                        }
                    }
            }
        }
        .frame(height: 190)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spend by month")
    }
}
