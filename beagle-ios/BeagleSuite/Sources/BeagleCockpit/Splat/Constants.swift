import Foundation
import SwiftUI

enum Constants {
    static let maxSimultaneousRenders = 1   // one frame in flight → CPU splat deform never races the GPU read
    static let rotationPerSecond = Angle(degrees: 0)
    static let rotationAxis = SIMD3<Float>(0, 1, 0)
    // TRELLIS render_utils camera (its exact convention: Z-up, look-at origin,
    // eye = r·[sin(yaw)cos(pitch), cos(yaw)cos(pitch), sin(pitch)]). The front the user approved
    // is render-frame v3 of the 8-frame turntable.
    // Canon makes the dog upright (+Y) & front→+Z, so the default view is a level
    // shot down +Z. --splat-yaw orbits horizontally / --splat-pitch vertically to
    // FIND the face angle for a given seed (TRELLIS canonical orientation varies per
    // seed); the found yaw is then BAKED into the ply via canon (Ry∘R).
    static let frontYaw = Angle(degrees: 0)
    static let frontPitch = Angle(degrees: 0)
    static let frontRadius: Float = 2.0   // closer, more present face (canon: Rx180, ~1.1 tall)
    static let frontFov = Angle(degrees: 40)
    // (legacy orient* — superseded by the look-at camera)
    static let orientX = Angle(degrees: -20)
    static let orientY = Angle(degrees: 135)
    static let orientZ = Angle(degrees: 180)
#if !os(visionOS)
    static let fovy = Angle(degrees: 65)
#endif
    static let modelCenterZ: Float = -1.2

    // Procedural splat geometry
    static let proceduralCubeSize: Float = 1.0
    static let proceduralCubeDistance: Float = 1.0
    static let proceduralCubeGridSizes: [Int] = [10, 20, 50]
    static let proceduralCubeSplatRelativeRadius: Float = 0.1
    static let proceduralCubeSwapDelay: TimeInterval = 2.0
}

