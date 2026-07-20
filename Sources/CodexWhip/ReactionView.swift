import SwiftUI

struct ReactionView: View {
    let kind: ReactionKind
    let startedAt: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            ZStack {
                switch kind {
                case .praise:
                    PraiseReaction(elapsed: elapsed)
                case .whip:
                    WhipReaction(elapsed: elapsed)
                }
            }
            .frame(width: ReactionKind.baseCanvasSize.width, height: ReactionKind.baseCanvasSize.height)
            .scaleEffect(kind.visualScale)
            .frame(width: kind.canvasSize.width, height: kind.canvasSize.height)
        }
        .allowsHitTesting(false)
    }
}

private struct PraiseReaction: View {
    let elapsed: TimeInterval

    var body: some View {
        let cycle = min(elapsed / 0.62, 2.999)
        let local = cycle - floor(cycle)
        let pat = sin(local * .pi)
        let horizontalStroke = sin(local * .pi * 2) * 14
        let entrance = min(1, elapsed / 0.24)

        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let delay = Double(index) * 0.16
                let life = min(max((elapsed - delay) / 1.4, 0), 1)
                Image(systemName: index.isMultiple(of: 2) ? "heart.fill" : "sparkles")
                    .font(.system(size: index.isMultiple(of: 2) ? 20 : 15, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2) ? .pink : .yellow)
                    .offset(
                        x: CGFloat(index - 3) * 28 + sin(Double(index)) * 14,
                        y: 32 + CGFloat(life) * 105
                    )
                    .scaleEffect(0.5 + life * 0.8)
                    .opacity(life == 0 ? 0 : 1 - life)
            }

            Text("🫳")
                .font(.system(size: 82))
                .rotationEffect(.degrees(-12 + pat * 7 + horizontalStroke * 0.14))
                .offset(
                    x: -8 + horizontalStroke,
                    y: 70 - pat * 28 - (1 - entrance) * 110
                )
                .shadow(color: .black.opacity(0.2), radius: 7, y: 5)

            Text("嘿嘿 ♥")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.pink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(.white.opacity(0.9), in: Capsule())
                .offset(x: -78, y: 58)
                .scaleEffect(min(1, elapsed / 0.28))
                .opacity(elapsed < 2.15 ? 1 : max(0, 1 - (elapsed - 2.15) * 4))

            Ellipse()
                .stroke(Color.pink.opacity(0.45), lineWidth: 4)
                .frame(width: 92 + pat * 18, height: 25 + pat * 5)
                .offset(y: 26)
                .opacity(0.8 - pat * 0.55)
        }
    }
}

private struct WhipReaction: View {
    let elapsed: TimeInterval

    var body: some View {
        let intro = 0.18
        let adjusted = max(0, elapsed - intro)
        let physicsState = WhipPhysics.state(at: adjusted)
        let impact = physicsState.crackIntensity
        let graphicSize = CGSize(width: 280, height: 240)
        let graphicOffset = CGPoint(x: -35, y: 12)
        let lashTip = physicsState.lashPoints.last ?? physicsState.handleTip
        let tipOffset = CGPoint(
            x: lashTip.x - graphicSize.width / 2 + graphicOffset.x,
            y: lashTip.y - graphicSize.height / 2 + graphicOffset.y
        )

        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Color.yellow : Color.orange)
                    .frame(width: 5, height: 30 + CGFloat(index % 3) * 9)
                    .rotationEffect(.degrees(Double(index) * 45))
                    .offset(x: tipOffset.x, y: tipOffset.y)
                    .rotationEffect(.degrees(Double(index) * 45))
                    .scaleEffect(0.7 + impact * 0.65)
                    .opacity(impact * 0.9)
            }

            PhysicsWhipGraphic(state: physicsState)
                .frame(width: graphicSize.width, height: graphicSize.height)
                .offset(x: graphicOffset.x, y: graphicOffset.y)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 4)

            Text("啪！")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.yellow)
                .shadow(color: .red, radius: 2)
                .rotationEffect(.degrees(-12))
                .offset(x: tipOffset.x - 18, y: tipOffset.y - 24)
                .scaleEffect(0.65 + impact * 0.8)
                .opacity(impact)

            Image(systemName: "drop.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.cyan)
                .offset(x: tipOffset.x - 8 + impact * 15, y: tipOffset.y - 36 - impact * 12)
                .opacity(min(1, adjusted * 3) * 0.9)
        }
        .opacity(elapsed < 2.18 ? 1 : max(0, 1 - (elapsed - 2.18) * 14))
    }
}

private struct PhysicsWhipGraphic: View {
    let state: WhipPhysicsState

    var body: some View {
        Canvas { context, _ in
            drawLash(in: &context)
            drawRigidHandle(in: &context)
        }
    }

    private func drawLash(in context: inout GraphicsContext) {
        guard state.lashPoints.count > 1 else { return }

        for index in 0..<(state.lashPoints.count - 1) {
            let progress = CGFloat(index) / CGFloat(state.lashPoints.count - 2)
            let width = 9.2 * pow(1 - progress, 0.72) + 1.15
            var segment = Path()
            segment.move(to: state.lashPoints[index])
            segment.addLine(to: state.lashPoints[index + 1])

            context.stroke(
                segment,
                with: .color(.black.opacity(0.72)),
                style: StrokeStyle(
                    lineWidth: width + 2.7,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            context.stroke(
                segment,
                with: .color(Color(red: 0.30, green: 0.19, blue: 0.15)),
                style: StrokeStyle(
                    lineWidth: width,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func drawRigidHandle(in context: inout GraphicsContext) {
        var handle = Path()
        handle.move(to: state.handlePivot)
        handle.addLine(to: state.handleTip)
        context.stroke(
            handle,
            with: .color(.black.opacity(0.88)),
            style: StrokeStyle(lineWidth: 21, lineCap: .round)
        )
        context.stroke(
            handle,
            with: .color(Color(red: 0.47, green: 0.26, blue: 0.12)),
            style: StrokeStyle(lineWidth: 15, lineCap: .round)
        )

        let axis = normalized(subtract(state.handleTip, state.handlePivot))
        let normal = CGPoint(x: -axis.y, y: axis.x)
        for progress in stride(from: CGFloat(0.18), through: CGFloat(0.82), by: CGFloat(0.16)) {
            let center = interpolate(state.handlePivot, state.handleTip, progress)
            var band = Path()
            band.move(to: add(center, scaled(normal, by: 8)))
            band.addLine(to: add(center, scaled(normal, by: -8)))
            context.stroke(
                band,
                with: .color(Color(red: 0.18, green: 0.12, blue: 0.09)),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
            )
        }

        context.fill(
            Path(ellipseIn: CGRect(
                x: state.handlePivot.x - 8.5,
                y: state.handlePivot.y - 8.5,
                width: 17,
                height: 17
            )),
            with: .color(Color(red: 0.16, green: 0.11, blue: 0.09))
        )
    }

    private func interpolate(_ start: CGPoint, _ end: CGPoint, _ progress: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    private func add(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    private func subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    private func scaled(_ point: CGPoint, by scalar: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scalar, y: point.y * scalar)
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        let length = max(hypot(point.x, point.y), 0.0001)
        return CGPoint(x: point.x / length, y: point.y / length)
    }
}
