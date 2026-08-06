import SwiftUI

/// GitHub-style contribution heatmap of completed to-dos. Columns are weeks
/// (oldest → newest, left → right), rows are weekdays (Mon → Sun). The more
/// completions on a day, the brighter the rounded square — scaled against
/// the period's max in four tiers. Hovering a square floats a card listing
/// that day's completed tasks; a Less→More legend sits below the grid.
struct CompletionHeatmapView: View {
    /// Day (`yyyy-MM-dd`) → completed task texts.
    let tasksByDay: [String: [String]]
    /// How many weeks to show (columns).
    var weeks: Int = 12
    /// Square edge length.
    var cell: CGFloat = 10
    var spacing: CGFloat = 3

    @State private var hovered: Date?

    /// Brightness tiers: empty, then 1st–4th quartile of the period's max.
    private static let tiers: [Double] = [0.06, 0.3, 0.5, 0.75, 1.0]

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private func key(for date: Date) -> String {
        ObsidianTodoScanner.dateString(for: date)
    }

    private func count(for date: Date) -> Int {
        tasksByDay[key(for: date)]?.count ?? 0
    }

    /// Days laid out as [week][weekday], oldest first. Future days are nil.
    private var columns: [[Date?]] {
        let today = calendar.startOfDay(for: Date())
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeekStart)
        else { return [] }
        return (0..<weeks).map { week in
            (0..<7).map { day in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: firstWeekStart),
                      date <= today else { return nil }
                return date
            }
        }
    }

    private var maxCount: Int {
        tasksByDay.values.map(\.count).max() ?? 0
    }

    private func brightness(for date: Date) -> Double {
        let completions = count(for: date)
        guard completions > 0, maxCount > 0 else { return Self.tiers[0] }
        let level = min(4, Int(ceil(4.0 * Double(completions) / Double(maxCount))))
        return Self.tiers[max(1, level)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            grid
            legend
        }
        .overlay(alignment: .topLeading) {
            if let hovered {
                hoverCard(for: hovered)
                    .fixedSize()
                    .alignmentGuide(.top) { $0[.bottom] }
                    .offset(y: -6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { day in
                        if let date = week[day] {
                            RoundedRectangle(cornerRadius: cell * 0.28)
                                .fill(.white.opacity(brightness(for: date)))
                                .frame(width: cell, height: cell)
                                .onHover { isHovering in
                                    if isHovering {
                                        hovered = date
                                    } else if hovered == date {
                                        hovered = nil
                                    }
                                }
                        } else {
                            RoundedRectangle(cornerRadius: cell * 0.28)
                                .fill(.clear)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hover card

    private func hoverCard(for date: Date) -> some View {
        let tasks = tasksByDay[key(for: date)] ?? []
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(date.formatted(date: .abbreviated, time: .omitted)) — \(tasks.isEmpty ? "none" : "\(tasks.count) completed")")
                .font(.notch(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            ForEach(Array(tasks.prefix(5).enumerated()), id: \.offset) { _, task in
                Text(task)
                    .font(.notch(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            if tasks.count > 5 {
                Text("+\(tasks.count - 5) more")
                    .font(.notch(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less")
                .font(.notch(size: 8))
                .foregroundStyle(.white.opacity(0.3))
            ForEach(Array(Self.tiers.enumerated()), id: \.offset) { _, opacity in
                RoundedRectangle(cornerRadius: cell * 0.22)
                    .fill(.white.opacity(opacity))
                    .frame(width: cell * 0.8, height: cell * 0.8)
            }
            Text("More")
                .font(.notch(size: 8))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}
