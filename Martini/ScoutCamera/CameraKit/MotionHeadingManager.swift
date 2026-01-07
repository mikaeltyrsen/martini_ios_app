import Foundation
import CoreMotion

@MainActor
final class MotionHeadingManager: ObservableObject {
    @Published private(set) var headingDegrees: Double = 0
    @Published private(set) var tiltDegrees: Double = 0
    @Published private(set) var rollDegrees: Double = 0
    @Published private(set) var pitchDegrees: Double = 0
    @Published private(set) var yawDegrees: Double = 0

    private let motionManager = CMMotionManager()

    var headingText: String {
        let degrees = headingDegrees.truncatingRemainder(dividingBy: 360)
        switch degrees {
        case 0..<45, 315..<360:
            return "N"
        case 45..<135:
            return "E"
        case 135..<225:
            return "S"
        default:
            return "W"
        }
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let yaw = motion.attitude.yaw
            let pitch = motion.attitude.pitch
            let roll = motion.attitude.roll
            let heading = (yaw * 180 / .pi).truncatingRemainder(dividingBy: 360)
            self.headingDegrees = heading < 0 ? heading + 360 : heading
            self.tiltDegrees = pitch * 180 / .pi
            self.rollDegrees = roll * 180 / .pi
            self.pitchDegrees = pitch * 180 / .pi
            self.yawDegrees = yaw * 180 / .pi
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}
