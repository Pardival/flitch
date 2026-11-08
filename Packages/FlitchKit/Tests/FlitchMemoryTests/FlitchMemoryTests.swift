import Testing

@testable import FlitchMemory

@Test func moduleLoads() {
    #expect(FlitchMemoryModule.name == "FlitchMemory")
}
