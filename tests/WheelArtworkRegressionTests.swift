import Foundation
import AppKit

@MainActor
enum WheelArtworkRegressionTests {
    static func run(expect: (Bool, String) -> Void) {
        var calibration = ColorCalibration.identity
        _ = calibration.addSample(target: RGB8(r: 255, g: 0, b: 0),
                                  observed: RGB8(r: 255, g: 190, b: 30))
        let start = ProcessInfo.processInfo.systemUptime
        let cold = ColorWheelArtwork.image(for: calibration)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let warm = ColorWheelArtwork.image(for: calibration)
        expect(cold === warm, "unchanged calibration reuses its wheel bitmap")
        expect(cold.size.width == 256 && cold.size.height == 256,
               "the calibrated wheel keeps its logical size")
        expect(ColorWheelArtwork.image(for: nil) === ColorWheelArtwork.image,
               "an uncalibrated wheel uses the shared base image")
        print(String(format: "Wheel cold-render sample: %.1f ms (not an Instruments profile)", elapsed * 1000))
    }
}
