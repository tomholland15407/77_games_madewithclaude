//
//  StickFigure.swift
//  A Banana Game
//
//  A reusable vector stick figure — clean rounded-cap strokes + a filled head, drawn from a small
//  set of posed joint points, with a dark contour so it reads on any background (like
//  OutlinedPixelSprite, but smooth vector art). Author poses facing RIGHT; mirror with
//  `.scaleEffect(x: -1)` to face left. Scales to fill its frame keeping aspect (height-driven,
//  horizontally centered), so just give it a `.frame(width:height:)`.
//

import SwiftUI

/// A pose = joint points in a 0…1 unit box (x right, y down), authored facing right.
struct StickPose {
    var head: CGPoint
    var headR: CGFloat
    var neck: CGPoint
    var hip: CGPoint
    var lElbow: CGPoint
    var lHand: CGPoint
    var rElbow: CGPoint
    var rHand: CGPoint
    var lKnee: CGPoint
    var lFoot: CGPoint
    var rKnee: CGPoint
    var rFoot: CGPoint

    /// Neutral standing gunslinger — front (right) hand ready near the hip.
    static let standing = StickPose(
        head: CGPoint(x: 0.50, y: 0.15), headR: 0.10,
        neck: CGPoint(x: 0.50, y: 0.27), hip: CGPoint(x: 0.50, y: 0.60),
        lElbow: CGPoint(x: 0.42, y: 0.40), lHand: CGPoint(x: 0.40, y: 0.52),
        rElbow: CGPoint(x: 0.58, y: 0.40), rHand: CGPoint(x: 0.61, y: 0.54),
        lKnee: CGPoint(x: 0.45, y: 0.78), lFoot: CGPoint(x: 0.42, y: 0.97),
        rKnee: CGPoint(x: 0.56, y: 0.78), rFoot: CGPoint(x: 0.60, y: 0.97))

    /// Firing — front arm punched out to the right, back arm counter-balancing, feet braced.
    static let firing = StickPose(
        head: CGPoint(x: 0.50, y: 0.15), headR: 0.10,
        neck: CGPoint(x: 0.50, y: 0.27), hip: CGPoint(x: 0.50, y: 0.60),
        lElbow: CGPoint(x: 0.42, y: 0.40), lHand: CGPoint(x: 0.37, y: 0.46),
        rElbow: CGPoint(x: 0.62, y: 0.35), rHand: CGPoint(x: 0.76, y: 0.35),
        lKnee: CGPoint(x: 0.44, y: 0.78), lFoot: CGPoint(x: 0.38, y: 0.97),
        rKnee: CGPoint(x: 0.58, y: 0.78), rFoot: CGPoint(x: 0.64, y: 0.97))

    /// Run frame A — right leg driving forward, left arm forward (opposite limbs).
    static let runA = StickPose(
        head: CGPoint(x: 0.55, y: 0.14), headR: 0.095,
        neck: CGPoint(x: 0.52, y: 0.27), hip: CGPoint(x: 0.47, y: 0.58),
        lElbow: CGPoint(x: 0.55, y: 0.40), lHand: CGPoint(x: 0.63, y: 0.46),
        rElbow: CGPoint(x: 0.43, y: 0.38), rHand: CGPoint(x: 0.37, y: 0.33),
        lKnee: CGPoint(x: 0.58, y: 0.72), lFoot: CGPoint(x: 0.66, y: 0.83),
        rKnee: CGPoint(x: 0.44, y: 0.74), rFoot: CGPoint(x: 0.34, y: 0.92))

    /// Run frame B — mirror gait (left leg driving forward, right arm forward).
    static let runB = StickPose(
        head: CGPoint(x: 0.55, y: 0.14), headR: 0.095,
        neck: CGPoint(x: 0.52, y: 0.27), hip: CGPoint(x: 0.47, y: 0.58),
        lElbow: CGPoint(x: 0.43, y: 0.38), lHand: CGPoint(x: 0.37, y: 0.33),
        rElbow: CGPoint(x: 0.55, y: 0.40), rHand: CGPoint(x: 0.63, y: 0.46),
        lKnee: CGPoint(x: 0.44, y: 0.74), lFoot: CGPoint(x: 0.34, y: 0.92),
        rKnee: CGPoint(x: 0.58, y: 0.72), rFoot: CGPoint(x: 0.66, y: 0.83))

    /// Hurdle leap — knees tucked up, arms up, leaning forward.
    static let jumping = StickPose(
        head: CGPoint(x: 0.56, y: 0.16), headR: 0.095,
        neck: CGPoint(x: 0.52, y: 0.28), hip: CGPoint(x: 0.50, y: 0.56),
        lElbow: CGPoint(x: 0.44, y: 0.34), lHand: CGPoint(x: 0.39, y: 0.26),
        rElbow: CGPoint(x: 0.60, y: 0.36), rHand: CGPoint(x: 0.68, y: 0.28),
        lKnee: CGPoint(x: 0.46, y: 0.66), lFoot: CGPoint(x: 0.54, y: 0.64),
        rKnee: CGPoint(x: 0.58, y: 0.64), rFoot: CGPoint(x: 0.66, y: 0.60))
}

struct StickFigure: View {
    var pose: StickPose
    var color: Color = .black
    var outline: Color = Color(red: 0.05, green: 0.05, blue: 0.09)
    /// Stroke width as a fraction of the frame height.
    var lineFrac: CGFloat = 0.055
    /// Draw a small pistol in the front (right) hand, aimed along the forearm.
    var gun: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let cx: CGFloat = w / 2
            let map: (CGPoint) -> CGPoint = { p in CGPoint(x: cx + (p.x - 0.5) * h, y: p.y * h) }
            let lw: CGFloat = h * lineFrac
            let headD: CGFloat = pose.headR * 2 * h
            let outlineExtra: CGFloat = h * 0.022
            let body = limbPath(map)
            let barrel = gunPath(map)

            ZStack {
                // Dark contour underlay.
                body.stroke(outline, style: StrokeStyle(lineWidth: lw + outlineExtra, lineCap: .round, lineJoin: .round))
                Circle().fill(outline).frame(width: headD + outlineExtra, height: headD + outlineExtra)
                    .position(map(pose.head))
                if gun {
                    barrel.stroke(outline, style: StrokeStyle(lineWidth: lw * 0.9 + outlineExtra, lineCap: .round, lineJoin: .round))
                }
                // Colored figure on top.
                body.stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                Circle().fill(color).frame(width: headD, height: headD).position(map(pose.head))
                if gun {
                    barrel.stroke(Color(white: 0.22), style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: w, height: h)
        }
    }

    private func limbPath(_ map: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        // Torso.
        path.move(to: map(pose.neck)); path.addLine(to: map(pose.hip))
        // Arms + legs (shoulder = neck, hips = hip).
        func chain(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) {
            path.move(to: map(a)); path.addLine(to: map(b)); path.addLine(to: map(c))
        }
        chain(pose.neck, pose.lElbow, pose.lHand)
        chain(pose.neck, pose.rElbow, pose.rHand)
        chain(pose.hip, pose.lKnee, pose.lFoot)
        chain(pose.hip, pose.rKnee, pose.rFoot)
        return path
    }

    private func gunPath(_ map: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        let hand = pose.rHand, elbow = pose.rElbow
        let dx = hand.x - elbow.x, dy = hand.y - elbow.y
        let len = max(0.0001, hypot(dx, dy))
        let ux = dx / len, uy = dy / len
        let tip = CGPoint(x: hand.x + ux * 0.13, y: hand.y + uy * 0.13)
        path.move(to: map(hand)); path.addLine(to: map(tip))
        // A short grip dropping from the hand.
        let grip = CGPoint(x: hand.x - uy * 0.06, y: hand.y + abs(ux) * 0.06 + 0.02)
        path.move(to: map(hand)); path.addLine(to: map(grip))
        return path
    }
}
