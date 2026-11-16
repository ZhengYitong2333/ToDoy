import SwiftUI
import AppKit

struct CompletionBurst: Identifiable {
    let id = UUID()
    let taskID: UUID
    let start = Date()
    static let duration = 0.85
    static let sound = NSSound(named: "Complete")
}

struct CompletionFirework: View {
    let burst: CompletionBurst
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = [.mint, .yellow, .cyan, .pink, .white]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { clock in
            let progress = min(1, max(0, clock.date.timeIntervalSince(burst.start) / CompletionBurst.duration))
            ZStack {
                if !reduceMotion {
                    Canvas { context, size in
                        let travel = 1 - pow(1 - progress, 3)
                        context.opacity = min(1, (1 - progress) * 2)
                        for n in 0..<22 {
                            let angle = Double(n) * 2.39996
                            let radius = 12 + travel * Double(27 + (n * 17) % 36)
                            let point = CGPoint(x: size.width / 2 + cos(angle) * radius,
                                                y: size.height / 2 + sin(angle) * radius + 14 * progress * progress)
                            var ray = Path()
                            ray.move(to: point)
                            ray.addLine(to: CGPoint(x: point.x + cos(angle) * (5 - 3 * progress),
                                                    y: point.y + sin(angle) * (5 - 3 * progress)))
                            context.stroke(ray, with: .color(colors[n % colors.count]),
                                           style: StrokeStyle(lineWidth: n.isMultiple(of: 3) ? 3.5 : 2, lineCap: .round))
                        }
                    }
                }
                Image(systemName: "checkmark.circle.fill").font(.system(size: 25, weight: .bold))
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .teal)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.22 * sin(min(1, progress * 3) * .pi))
                    .opacity(reduceMotion ? 1 : min(1, (1 - progress) * 4))
            }
        }.frame(width: 180, height: 180)
         .allowsHitTesting(false)
         .accessibilityHidden(true)
    }
}
