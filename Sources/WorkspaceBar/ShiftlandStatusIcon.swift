import AppKit

enum ShiftlandStatusIcon {
    @MainActor
    static func makeImage() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            hareSilhouette().fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppBrand.name
        return image
    }

    private static func hareSilhouette() -> NSBezierPath {
        let hare = NSBezierPath()
        hare.move(to: NSPoint(x: 6.15, y: 2.05))
        hare.curve(to: NSPoint(x: 14.75, y: 6.02),
                   controlPoint1: NSPoint(x: 10.55, y: 2.58), controlPoint2: NSPoint(x: 12.54, y: 3.56))
        hare.curve(to: NSPoint(x: 17.05, y: 7.36),
                   controlPoint1: NSPoint(x: 15.49, y: 6.21), controlPoint2: NSPoint(x: 16.25, y: 6.7))
        hare.curve(to: NSPoint(x: 16.66, y: 8.46),
                   controlPoint1: NSPoint(x: 17.0, y: 8.31), controlPoint2: NSPoint(x: 16.99, y: 8.47))
        hare.curve(to: NSPoint(x: 13.52, y: 9.75),
                   controlPoint1: NSPoint(x: 15.25, y: 8.35), controlPoint2: NSPoint(x: 14.3, y: 8.35))
        hare.curve(to: NSPoint(x: 17.24, y: 10.76),
                   controlPoint1: NSPoint(x: 15.35, y: 9.53), controlPoint2: NSPoint(x: 16.49, y: 9.58))
        hare.curve(to: NSPoint(x: 16.03, y: 11.44),
                   controlPoint1: NSPoint(x: 17.61, y: 11.36), controlPoint2: NSPoint(x: 16.88, y: 11.68))
        hare.curve(to: NSPoint(x: 11.29, y: 10.8),
                   controlPoint1: NSPoint(x: 14.49, y: 10.66), controlPoint2: NSPoint(x: 12.94, y: 11.56))
        hare.curve(to: NSPoint(x: 4.65, y: 12.33),
                   controlPoint1: NSPoint(x: 8.66, y: 9.74), controlPoint2: NSPoint(x: 6.94, y: 11.6))
        hare.curve(to: NSPoint(x: 0.94, y: 13.86),
                   controlPoint1: NSPoint(x: 2.91, y: 12.75), controlPoint2: NSPoint(x: 2.02, y: 14.24))
        hare.curve(to: NSPoint(x: 3.08, y: 11.48),
                   controlPoint1: NSPoint(x: 0.11, y: 13.39), controlPoint2: NSPoint(x: 1.4, y: 12.19))
        hare.curve(to: NSPoint(x: 4.61, y: 9.25),
                   controlPoint1: NSPoint(x: 4.02, y: 11.12), controlPoint2: NSPoint(x: 4.16, y: 10.14))
        hare.addTailAndEars()
        hare.close()
        return hare
    }
}

private extension NSBezierPath {
    func addTailAndEars() {
        line(to: NSPoint(x: 4.16, y: 9.53))
        curve(to: NSPoint(x: 3.63, y: 8.13),
              controlPoint1: NSPoint(x: 3.77, y: 9.17), controlPoint2: NSPoint(x: 3.67, y: 8.65))
        line(to: NSPoint(x: 5.0, y: 8.4))
        curve(to: NSPoint(x: 9.61, y: 7.78),
              controlPoint1: NSPoint(x: 6.45, y: 7.27), controlPoint2: NSPoint(x: 7.61, y: 7.21))
        curve(to: NSPoint(x: 13.08, y: 7.02),
              controlPoint1: NSPoint(x: 11.43, y: 8.24), controlPoint2: NSPoint(x: 12.41, y: 7.81))
        curve(to: NSPoint(x: 5.83, y: 4.72),
              controlPoint1: NSPoint(x: 11.5, y: 5.73), controlPoint2: NSPoint(x: 7.2, y: 7.49))
        curve(to: NSPoint(x: 13.83, y: 6.46),
              controlPoint1: NSPoint(x: 9.4, y: 5.12), controlPoint2: NSPoint(x: 12.22, y: 5.38))
        curve(to: NSPoint(x: 6.93, y: 3.33),
              controlPoint1: NSPoint(x: 12.17, y: 4.23), controlPoint2: NSPoint(x: 8.09, y: 5.14))
        line(to: NSPoint(x: 6.15, y: 2.05))
    }
}
