import Testing

@testable import FlitchCore

@Test func moduleLoads() {
    #expect(FlitchCoreModule.name == "FlitchCore")
}
