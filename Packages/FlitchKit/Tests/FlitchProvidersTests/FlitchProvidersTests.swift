import Testing

@testable import FlitchProviders

@Test func moduleLoads() {
    #expect(FlitchProvidersModule.name == "FlitchProviders")
}
