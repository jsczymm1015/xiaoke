import Foundation
import CoreGraphics

@main
struct WindowPlacementTests {
    static func main() {
        let main = CGRect(x: 0, y: 24, width: 1440, height: 852)
        let left = CGRect(x: -1920, y: 24, width: 1920, height: 1056)
        let right = CGRect(x: 1440, y: 24, width: 1920, height: 1056)
        var passed = 0

        func check(_ name: String, _ frame: CGRect, screens: [CGRect], preferred: CGRect?, expected: CGRect) {
            let actual = PetWindowPlacement.fit(frame, in: screens, preferred: preferred)
            precondition(actual == expected, "\(name): expected \(expected), got \(actual)")
            precondition(actual.origin.x.isFinite && actual.origin.y.isFinite &&
                         actual.width.isFinite && actual.height.isFinite &&
                         actual.maxX.isFinite && actual.maxY.isFinite,
                         "\(name): returned a non-finite frame")
            passed += 1
        }

        let resting = CGRect(x: 1050, y: 60, width: 280, height: 296)
        check("keep an already visible window", resting, screens: [main, right], preferred: right, expected: resting)
        check("recover after the external display is removed",
              CGRect(x: 2000, y: 80, width: 280, height: 296), screens: [main], preferred: main,
              expected: CGRect(x: 1160, y: 80, width: 280, height: 296))
        let onLeft = CGRect(x: -1500, y: 40, width: 280, height: 296)
        check("keep a window on a negative-coordinate display", onLeft, screens: [main, left], preferred: main, expected: onLeft)
        check("choose the greatest overlap rather than the first intersecting screen",
              CGRect(x: 1350, y: 80, width: 400, height: 296), screens: [main, right], preferred: main,
              expected: CGRect(x: 1440, y: 80, width: 400, height: 296))
        check("equal overlap retains screen order",
              CGRect(x: 1340, y: 80, width: 200, height: 296), screens: [main, right], preferred: right,
              expected: CGRect(x: 1240, y: 80, width: 200, height: 296))
        check("use the preferred current screen when there is no overlap",
              CGRect(x: 5000, y: 5000, width: 280, height: 296), screens: [main, left], preferred: left,
              expected: CGRect(x: -280, y: 784, width: 280, height: 296))
        check("ignore a stale preferred screen",
              CGRect(x: 5000, y: 5000, width: 280, height: 296), screens: [main], preferred: right,
              expected: CGRect(x: 1160, y: 580, width: 280, height: 296))
        check("shrink an oversized window to the screen",
              CGRect(x: -100, y: -100, width: 2500, height: 2000), screens: [main], preferred: main, expected: main)
        check("clamp both edges of a negative-coordinate screen",
              CGRect(x: -2100, y: 1000, width: 280, height: 296), screens: [left], preferred: nil,
              expected: CGRect(x: -1920, y: 784, width: 280, height: 296))
        check("discard non-finite and empty screens", resting,
              screens: [.null, .infinite, .zero, CGRect(x: 0, y: 0, width: -20, height: 800),
                        CGRect(x: CGFloat.nan, y: 0, width: 1000, height: 800), main], preferred: .infinite, expected: resting)
        check("never treat the finite-valued CGRect.infinite sentinel as a display",
              CGRect(x: 5000, y: 5000, width: 280, height: 296), screens: [.infinite, main], preferred: .infinite,
              expected: CGRect(x: 1160, y: 580, width: 280, height: 296))
        check("normalize an invalid input frame on the preferred screen",
              CGRect(x: CGFloat.nan, y: 40, width: 280, height: 296), screens: [main, left], preferred: left,
              expected: CGRect(x: -280, y: 24, width: 280, height: 296))
        check("preserve a finite frame if no screens are available", resting,
              screens: [], preferred: main, expected: resting)
        check("return a finite default if neither frame nor screens are usable", .null,
              screens: [.zero, .infinite], preferred: main, expected: CGRect(x: 0, y: 0, width: 280, height: 296))
        check("normalize an empty frame", .zero, screens: [], preferred: nil,
              expected: CGRect(x: 0, y: 0, width: 280, height: 296))
        check("normalize an infinite frame sentinel", .infinite, screens: [], preferred: nil,
              expected: CGRect(x: 0, y: 0, width: 280, height: 296))
        check("normalize an overflowing frame",
              CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                     width: CGFloat.greatestFiniteMagnitude, height: 296), screens: [], preferred: nil,
              expected: CGRect(x: 0, y: 0, width: 280, height: 296))
        print("PASS: \(passed) window placement cases (visible, removed screen, negative coordinates, overlap, oversized, invalid input)")
    }
}
