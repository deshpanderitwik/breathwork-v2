import SwiftUI

/// Horizontal timeline: 2 segments per round (active + rest), widths
/// proportional to duration, with a fill that scales left→right as
/// elapsed time crosses each segment.
public struct TimelineView: View {
    let config: SessionConfig
    let elapsedMs: Double

    public init(config: SessionConfig, elapsedMs: Double) {
        self.config = config
        self.elapsedMs = elapsedMs
    }

    public var body: some View {
        GeometryReader { geo in
            let totalSec = Double(config.rounds) * (config.activeSec + config.restSec)
            let totalWidth = geo.size.width
            let spacing: CGFloat = 2
            let gaps = CGFloat(config.rounds * 2 - 1) * spacing
            let usable = max(0, totalWidth - gaps)
            let pxPerSec = usable / CGFloat(totalSec)

            HStack(spacing: spacing) {
                ForEach(0..<config.rounds, id: \.self) { r in
                    segment(
                        widthSec: config.activeSec,
                        startSec: Double(r) * (config.activeSec + config.restSec),
                        activeStyle: true,
                        pxPerSec: pxPerSec
                    )
                    segment(
                        widthSec: config.restSec,
                        startSec: Double(r) * (config.activeSec + config.restSec) + config.activeSec,
                        activeStyle: false,
                        pxPerSec: pxPerSec
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func segment(widthSec: Double, startSec: Double, activeStyle: Bool, pxPerSec: CGFloat) -> some View {
        let width = CGFloat(widthSec) * pxPerSec
        let elapsedSec = elapsedMs / 1000
        let frac: CGFloat = {
            if elapsedSec <= startSec { return 0 }
            if elapsedSec >= startSec + widthSec { return 1 }
            return CGFloat((elapsedSec - startSec) / widthSec)
        }()

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(activeStyle ? 0.12 : 0.04))
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(activeStyle ? 1.0 : 0.5))
                .frame(width: width * frac)
        }
        .frame(width: width)
    }
}
