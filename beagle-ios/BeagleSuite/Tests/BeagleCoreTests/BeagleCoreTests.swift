import Testing
@testable import BeagleCore

@Test func truthModeValues() {
    #expect(TruthMode.observed.rawValue == "observed")
    #expect(TruthMode.remembered.rawValue == "remembered")
    #expect(TruthMode.declared.rawValue == "declared")
}

@Test func postureCountsInit() {
    let counts = PostureCounts(totalProjects: 5, alwaysOn: 1, warm: 2, cold: 2)
    #expect(counts.totalProjects == 5)
    #expect(counts.alwaysOn == 1)
    #expect(PostureCounts.empty.totalProjects == 0)
}
