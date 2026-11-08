import Testing

@testable import FlitchCharacter

@Test func moduleLoads() {
    #expect(FlitchCharacterModule.name == "FlitchCharacter")
}
