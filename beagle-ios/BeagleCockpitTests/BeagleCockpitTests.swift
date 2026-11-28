import BeagleCore
import Foundation
import simd
import Testing
@testable import BeagleCockpit

@Suite("BodyStory & PhysioSnapshot")
struct BodyStoryTests {
    @Test("Baseline snapshot without physiological signal uses warm default greeting")
    func baselineSnapshotGreeting() {
        let idle = PhysioSnapshot()
        #expect(!idle.hasSignal)

        let normalFlow = PhysioSnapshot(sleepQuality: nil, flow: "NORMAL", restingHRElevated: false)
        #expect(!normalFlow.hasSignal)

        let opening = BodyStory.opening(normalFlow, hour: 9)
        #expect(opening.line == "Bom dia. Que bom te ver.")
        #expect(opening.follow == "Me conta como está o teu dia.")
    }

    @Test("PhysioSnapshot detects active signals across sleep, HRV flow, and resting HR")
    func physioSnapshotHasSignal() {
        #expect(PhysioSnapshot(sleepQuality: "deep").hasSignal)
        #expect(PhysioSnapshot(flow: "STRESS").hasSignal)
        #expect(PhysioSnapshot(flow: "FLOW").hasSignal)
        #expect(PhysioSnapshot(restingHRElevated: true).hasSignal)
    }

    @Test(
        "Salutation adapts to hour of day",
        arguments: [
            (5, "Bom dia"),
            (11, "Bom dia"),
            (12, "Boa tarde"),
            (17, "Boa tarde"),
            (18, "Boa noite"),
            (23, "Boa noite"),
            (2, "Ainda acordado"),
        ]
    )
    func salutationByHour(hour: Int, expectedPrefix: String) {
        let opening = BodyStory.opening(PhysioSnapshot(), hour: hour)
        #expect(opening.line.hasPrefix("\(expectedPrefix)."))
    }

    @Test("Weaves multiple clauses in Portuguese and suppresses redundant HR clause under STRESS")
    func multiClauseWeavingAndStressSuppression() {
        let calmMorning = PhysioSnapshot(sleepQuality: "deep", flow: "FLOW", restingHRElevated: false)
        let calmOpening = BodyStory.opening(calmMorning, hour: 8)
        #expect(calmOpening.line == "Bom dia. Você dormiu fundo e teu coração está sereno.")
        #expect(calmOpening.follow == "Aproveita esse fôlego — no que a gente mergulha?")

        let threeSignals = PhysioSnapshot(sleepQuality: "light", flow: "FLOW", restingHRElevated: true)
        let threeOpening = BodyStory.opening(threeSignals, hour: 14)
        #expect(threeOpening.line == "Boa tarde. Teu sono foi leve, teu coração está sereno e o corpo ainda acelerado.")

        let stressed = PhysioSnapshot(sleepQuality: "short", flow: "STRESS", restingHRElevated: true)
        let stressedOpening = BodyStory.opening(stressed, hour: 20)
        #expect(stressedOpening.line == "Boa noite. Você dormiu pouco e o coração andou tenso.")
        #expect(!stressedOpening.line.contains("acelerado"))
        #expect(stressedOpening.follow == "Como está o peito agora?")
    }
}

@Suite("Splat Matrix Math")
struct MatrixMathUtilTests {
    @Test("Translation matrix offsets homogeneous points and preserves directions")
    func translationMatrix() {
        let transform = matrix4x4_translation(2.5, -1.0, 4.0)
        let movedPoint = transform * SIMD4<Float>(1.0, 3.0, -2.0, 1.0)
        #expect(abs(movedPoint.x - 3.5) < 1e-5)
        #expect(abs(movedPoint.y - 2.0) < 1e-5)
        #expect(abs(movedPoint.z - 2.0) < 1e-5)
        #expect(abs(movedPoint.w - 1.0) < 1e-5)

        let direction = transform * SIMD4<Float>(1.0, 0.0, 0.0, 0.0)
        #expect(abs(direction.x - 1.0) < 1e-5)
        #expect(abs(direction.y) < 1e-5)
        #expect(abs(direction.z) < 1e-5)
    }

    @Test("Quarter-turn rotation around Z axis maps +X onto +Y")
    func rotationAroundZAxis() {
        let rotation = matrix4x4_rotation(radians: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let rotated = rotation * SIMD4<Float>(1, 0, 0, 1)
        #expect(abs(rotated.x) < 1e-5)
        #expect(abs(rotated.y - 1.0) < 1e-5)
        #expect(abs(rotated.z) < 1e-5)
        #expect(abs(rotated.w - 1.0) < 1e-5)
    }

    @Test("Right-handed look-at matrix places target along negative Z in view space")
    func lookAtRightHand() {
        let view = matrix_look_at_right_hand(
            eye: SIMD3<Float>(0, 0, 5),
            center: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        let targetInView = view * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(targetInView.x) < 1e-5)
        #expect(abs(targetInView.y) < 1e-5)
        #expect(abs(targetInView.z - (-5.0)) < 1e-5)
    }

    @Test("Right-handed perspective matrix maps near and far planes to Metal clip-space Z [0, 1]")
    func perspectiveRightHandMetalClipDepth() {
        let nearZ: Float = 0.1
        let farZ: Float = 100.0
        let projection = matrix_perspective_right_hand(
            fovyRadians: .pi / 3,
            aspectRatio: 16.0 / 9.0,
            nearZ: nearZ,
            farZ: farZ
        )

        let nearClip = projection * SIMD4<Float>(0, 0, -nearZ, 1)
        let nearNDCZ = nearClip.z / nearClip.w
        #expect(abs(nearNDCZ - 0.0) < 1e-5)

        let farClip = projection * SIMD4<Float>(0, 0, -farZ, 1)
        let farNDCZ = farClip.z / farClip.w
        #expect(abs(farNDCZ - 1.0) < 1e-4)
    }
}

@Suite("BuildInfo")
struct BuildInfoTests {
    @Test("Preview and detailed labels format version and build consistently")
    func formattedLabels() {
        #expect(!BuildInfo.version.isEmpty)
        #expect(!BuildInfo.build.isEmpty)
        #expect(BuildInfo.previewLabel == "Preview \(BuildInfo.build)")
        #expect(BuildInfo.detailedLabel == "v\(BuildInfo.version) (\(BuildInfo.build))")
    }
}

@Suite("iOS 27 FoundationModels & Dream Synthesis")
struct IOS27IntelligenceTests {
    @Test("FoundationModelsAgent reports coherent tier description and handles short dream input")
    @MainActor
    func foundationModelsAgentTierCoherence() async {
        let agent = FoundationModelsAgent.shared
        let tier = agent.modelTierDescription
        #expect(!tier.isEmpty)

        if agent.isAnyModelAvailable {
            #expect(tier != "Unavailable")
        } else {
            #expect(tier == "Unavailable")
        }

        agent.resetSession()
        let singleThoughtResult = await agent.synthesizeDreamBridge(thoughts: ["Only one thought"])
        #expect(singleThoughtResult == nil)
    }

    @Test("DreamSynthesisEngine prepends AFM 3 neural consolidation insight when synthesizer succeeds")
    @MainActor
    func dreamSynthesisNeuralConsolidation() async {
        let engine = DreamSynthesisEngine.shared
        let savedInsights = engine.overnightInsights
        let savedLastSession = engine.lastDreamSession
        let savedDefaultsData = UserDefaults.standard.data(forKey: "dreamInsights")
        let savedDefaultsDate = UserDefaults.standard.object(forKey: "lastDreamSession")
        defer {
            engine.overnightInsights = savedInsights
            engine.lastDreamSession = savedLastSession
            UserDefaults.standard.set(savedDefaultsData, forKey: "dreamInsights")
            UserDefaults.standard.set(savedDefaultsDate, forKey: "lastDreamSession")
        }

        engine.overnightInsights = []
        let thoughts = [
            ThoughtCapture(
                nodeId: "t1",
                refinedText: "Nonlinear vagal HRV phase transitions during REM sleep",
                rawText: nil,
                source: "unit-test",
                createdAt: nil,
                syncedToServer: false,
                syncState: .localOnly
            ),
            ThoughtCapture(
                nodeId: "t2",
                refinedText: "PBPK compartmental clearance under circadian autonomic modulation",
                rawText: nil,
                source: "unit-test",
                createdAt: nil,
                syncedToServer: false,
                syncState: .localOnly
            ),
            ThoughtCapture(
                nodeId: "t3",
                refinedText: "State space Mamba draft decoding on Apple Silicon Neural Engine",
                rawText: nil,
                source: "unit-test",
                createdAt: nil,
                syncedToServer: false,
                syncState: .localOnly
            ),
        ]

        let expectedBridge = "Circadian vagal tone could parameterize time-varying hepatic clearance in PBPK models."
        await engine.synthesize(
            thoughts: thoughts,
            cognitivePosture: .empty,
            neuralSynthesizer: { candidates in
                candidates.count == 3 ? expectedBridge : nil
            }
        )

        let afmInsight = engine.overnightInsights.first { $0.sleepStage == "afm3-dream" }
        #expect(afmInsight != nil)
        #expect(afmInsight?.text == expectedBridge)
        #expect(afmInsight?.sourceThoughtIds == ["t1", "t2", "t3"])
        #expect(engine.hasUnreadInsights)

        if let id = afmInsight?.id {
            engine.markRead(id)
            let updated = engine.overnightInsights.first { $0.id == id }
            #expect(updated?.isRead == true)
        }
    }
}
