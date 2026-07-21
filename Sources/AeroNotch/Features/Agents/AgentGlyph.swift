import SwiftUI

/// Per-agent identity mark. Claude gets its starburst (drawn, no assets —
/// stays monochrome and tints via foregroundStyle); everything else uses a
/// text glyph (π for pi, first letter otherwise).
struct AgentGlyph: View {
    let agent: String
    var size: CGFloat = 9

    var body: some View {
        switch agent.lowercased() {
        case "claude":
            ClaudeMark()
                .frame(width: size, height: size)
        default:
            Text(AgentStyle.glyph(for: agent))
                .font(.system(size: size, weight: .bold, design: .rounded))
        }
    }
}

/// Approximation of Claude's starburst logo as rounded rays on a Canvas.
/// Strokes use `.foreground` shading so the mark inherits `foregroundStyle`.
struct ClaudeMark: View {
    var rays: Int = 10

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            let inner = outer * 0.15
            let thickness = outer * 0.34
            for i in 0..<rays {
                let angle = Double(i) * (2 * .pi / Double(rays))
                let dir = CGVector(dx: cos(angle), dy: sin(angle))
                var ray = Path()
                ray.move(to: CGPoint(x: center.x + dir.dx * inner, y: center.y + dir.dy * inner))
                ray.addLine(to: CGPoint(x: center.x + dir.dx * outer, y: center.y + dir.dy * outer))
                ctx.stroke(ray, with: .foreground, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
            }
        }
    }
}
