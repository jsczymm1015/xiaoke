import Foundation
import CoreGraphics

/// Keeps a floating pet inside a current display's visible frame.
enum PetWindowPlacement {
    private static let defaultFrame = CGRect(x: 0, y: 0, width: 280, height: 296)

    static func fit(_ frame: CGRect, in screens: [CGRect], preferred: CGRect?) -> CGRect {
        let validScreens = screens.filter(isValid)
        let validFrame = isValid(frame)
        let safeFrame = validFrame ? frame : defaultFrame
        guard !validScreens.isEmpty else { return safeFrame }

        // An invalid origin has no meaningful overlap with any display. Prefer
        // a current main display instead of using the fallback origin to pick one.
        var target: CGRect?
        var greatestOverlap = -Double.infinity
        if validFrame {
            for screen in validScreens {
                let overlap = safeFrame.intersection(screen)
                guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
                // Log area preserves ordering without overflowing for huge,
                // otherwise finite rectangles. Equal areas retain screen order.
                let score = log(Double(overlap.width)) + log(Double(overlap.height))
                if score > greatestOverlap {
                    greatestOverlap = score
                    target = screen
                }
            }
        }
        if target == nil, let preferred, isValid(preferred), validScreens.contains(preferred) {
            target = preferred
        }
        let screen = target ?? validScreens[0]
        let size = CGSize(width: min(safeFrame.width, screen.width),
                          height: min(safeFrame.height, screen.height))
        let origin = CGPoint(x: min(max(safeFrame.minX, screen.minX), screen.maxX - size.width),
                             y: min(max(safeFrame.minY, screen.minY), screen.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && !rect.isEmpty &&
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
        rect.size.width.isFinite && rect.size.height.isFinite &&
        rect.size.width > 0 && rect.size.height > 0 &&
        rect.maxX.isFinite && rect.maxY.isFinite
    }
}
