import AppKit
import QuartzCore

final class LumoView: NSView {
    private let body = CALayer()
    private let silhouette = CAShapeLayer()
    private let leftEye = CALayer()
    private let rightEye = CALayer()

    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval?
    private var lastMovement = -Double.infinity
    private var previousCursor: NSPoint?
    private var look = CGPoint.zero
    private var attention: CGFloat = 0
    private var nextBlinkTime: CFTimeInterval = 0
    var isPositionLocked = true

    private var center: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    init(style: BotStyle) {
        super.init(frame: NSRect(x: 0, y: 0, width: 176, height: 168))
        wantsLayer = true
        makeArtwork()
        setStyle(style)
    }

    func setStyle(_ style: BotStyle) {
        var translation = CGAffineTransform(translationX: center.x, y: center.y)
        let outline = style.shape.outline.copy(using: &translation)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.path = outline
        silhouette.fillColor = style.color.nsColor.cgColor
        leftEye.backgroundColor = style.color.eyeColor.cgColor
        rightEye.backgroundColor = leftEye.backgroundColor
        CATransaction.commit()
        applyPose()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init()")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else if !isPositionLocked {
            window?.performDrag(with: event)
        }
    }

    func startTracking() {
        guard displayLink == nil else { return }

        previousCursor = NSEvent.mouseLocation
        nextBlinkTime = CACurrentMediaTime() + Double.random(in: 2.5...5.5)
        let link = displayLink(target: self, selector: #selector(updateFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopTracking() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTime = nil
        lastMovement = -.infinity
        look = .zero
        attention = 0
        leftEye.removeAnimation(forKey: "blink")
        rightEye.removeAnimation(forKey: "blink")
        applyPose()
    }

    @objc private func updateFrame(_ link: CADisplayLink) {
        guard let window else { return }

        let now = link.timestamp
        if now >= nextBlinkTime {
            blink()
            nextBlinkTime = now + Double.random(in: 2.5...5.5)
        }
        let elapsed = min(0.1, max(0, now - (lastFrameTime ?? now - link.duration)))
        lastFrameTime = now

        let cursor = NSEvent.mouseLocation
        if cursor != previousCursor {
            lastMovement = now
            previousCursor = cursor
        }

        let x = (cursor.x - window.frame.midX) / 78
        let y = (cursor.y - window.frame.midY) / 66
        let distance = hypot(x, y)
        let isAttentive = distance < 1.4 || now - lastMovement < 0.8
        let smoothing = 1 - exp(-elapsed / 0.055)

        let previousLook = look
        let previousAttention = attention
        look.x += (x / max(1, distance) - look.x) * smoothing
        look.y += (y / max(1, distance) - look.y) * smoothing
        let targetAttention: CGFloat = isAttentive ? 1 : 0
        attention += (targetAttention - attention) * (1 - exp(-elapsed / 0.085))

        if abs(targetAttention - attention) < 0.001 {
            attention = targetAttention
        }
        if attention != previousAttention || (attention > 0 && look != previousLook) {
            applyPose()
        }
    }

    private func blink() {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = [1, 0.12, 0.12, 1]
        animation.keyTimes = [0, 0.30, 0.48, 1]
        animation.duration = 0.17
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        leftEye.add(animation, forKey: "blink")
        rightEye.add(animation, forKey: "blink")
    }

    private func applyPose() {
        let idle = 1 - attention
        let roll = (19 * .pi / 180) * idle - 0.055 * look.x * attention

        // Perspective moves the cloud gently while the eyes travel farther across its face.
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 320
        transform = CATransform3DRotate(transform, roll, 0, 0, 1)
        transform = CATransform3DRotate(transform, 0.12 * look.x * attention, 0, 1, 0)
        transform = CATransform3DRotate(transform, -0.10 * look.y * attention, 1, 0, 0)
        let scale = 1 - 0.045 * idle
        transform = CATransform3DScale(transform, scale, scale, 1)

        let eyeX = center.x + 23 * idle + 24 * look.x * attention
        let eyeY = center.y + 7 * idle + (13 * look.y - 4) * attention
        let halfSpacing = (29 - 3 * abs(look.x) * attention) / 2
        let gaze = fittedGaze(CGPoint(x: eyeX, y: eyeY), halfSpacing: halfSpacing)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.position = CGPoint(
            x: center.x - idle + 4 * look.x * attention,
            y: center.y + 3 * idle + 3 * look.y * attention
        )
        body.transform = transform
        leftEye.position = CGPoint(x: gaze.x - halfSpacing, y: gaze.y)
        rightEye.position = CGPoint(x: gaze.x + halfSpacing, y: gaze.y)
        CATransaction.commit()
    }

    private func fittedGaze(_ target: CGPoint, halfSpacing: CGFloat) -> CGPoint {
        guard let outline = silhouette.path else { return target }

        let horizontal = halfSpacing + 6.5
        let vertical: CGFloat = 14.5
        func fits(_ point: CGPoint) -> Bool {
            outline.contains(CGPoint(x: point.x - horizontal, y: point.y - vertical))
                && outline.contains(CGPoint(x: point.x - horizontal, y: point.y + vertical))
                && outline.contains(CGPoint(x: point.x + horizontal, y: point.y - vertical))
                && outline.contains(CGPoint(x: point.x + horizontal, y: point.y + vertical))
        }
        guard !fits(target) else { return target }

        // Shorten eye travel when a narrower outline would put the eyes past its edge.
        var inside = CGPoint(x: center.x, y: center.y - 4)
        var outside = target
        for _ in 0..<6 {
            let middle = CGPoint(x: (inside.x + outside.x) / 2, y: (inside.y + outside.y) / 2)
            if fits(middle) {
                inside = middle
            } else {
                outside = middle
            }
        }
        return inside
    }

    private func makeArtwork() {
        guard let layer else { return }

        let badgeCenter = CGPoint(x: center.x + 43, y: center.y - 44)
        let badgeRadius: CGFloat = 16

        let portrait = CALayer()
        portrait.frame = bounds
        layer.addSublayer(portrait)

        // Leave a transparent gap around the badge as the cloud turns behind it.
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        cutout.addEllipse(in: circle(at: badgeCenter, radius: badgeRadius + 5))
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = cutout
        mask.fillRule = .evenOdd
        portrait.mask = mask

        body.bounds = bounds
        body.position = center
        portrait.addSublayer(body)

        silhouette.frame = bounds
        body.addSublayer(silhouette)

        for eye in [leftEye, rightEye] {
            eye.bounds = CGRect(x: 0, y: 0, width: 13, height: 29)
            eye.cornerRadius = 6.5
            body.addSublayer(eye)
        }

        let badge = CAShapeLayer()
        badge.frame = bounds
        badge.path = CGPath(ellipseIn: circle(at: badgeCenter, radius: badgeRadius), transform: nil)
        badge.fillColor = NSColor(srgbRed: 246 / 255, green: 147 / 255, blue: 18 / 255, alpha: 1).cgColor
        layer.addSublayer(badge)

        let star = CAShapeLayer()
        star.frame = bounds
        star.path = starOutline(at: badgeCenter)
        star.fillColor = NSColor.white.cgColor
        layer.addSublayer(star)
    }

    private func starOutline(at center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<10 {
            let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            let radius: CGFloat = index.isMultiple(of: 2) ? 9 : 4.4
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func circle(at center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}
