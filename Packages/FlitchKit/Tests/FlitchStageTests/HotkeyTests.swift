import Carbon.HIToolbox
import Testing

@testable import FlitchStage

struct RightOptionDetectorTests {
    @Test func pressAndRelease() {
        var d = RightOptionDetector()
        #expect(d.flagsChanged(keyCode: kVK_RightOption, rightOptionDown: true, otherModifiersDown: false) == .press)
        #expect(d.flagsChanged(keyCode: kVK_RightOption, rightOptionDown: false, otherModifiersDown: false) == .release)
    }

    @Test func leftOptionDoesNothing() {
        var d = RightOptionDetector()
        #expect(d.flagsChanged(keyCode: kVK_Option, rightOptionDown: false, otherModifiersDown: false) == nil)
    }

    @Test func typingWithOptionCancels() {
        var d = RightOptionDetector()
        _ = d.flagsChanged(keyCode: kVK_RightOption, rightOptionDown: true, otherModifiersDown: false)
        #expect(d.keyDown() == .cancel)
        #expect(d.keyDown() == nil)  // only once
        #expect(d.flagsChanged(keyCode: kVK_RightOption, rightOptionDown: false, otherModifiersDown: false) == nil)
    }

    @Test func addingCommandCancels() {
        var d = RightOptionDetector()
        _ = d.flagsChanged(keyCode: kVK_RightOption, rightOptionDown: true, otherModifiersDown: false)
        #expect(d.flagsChanged(keyCode: kVK_Command, rightOptionDown: true, otherModifiersDown: true) == .cancel)
    }

    @Test func pressingRightOptionWhileCommandHeldIsIgnored() {
        var d = RightOptionDetector()
        #expect(d.flagsChanged(keyCode: kVK_RightOption, rightOptionDown: true, otherModifiersDown: true) == nil)
    }

    @Test func keyDownWithoutHoldingIsIgnored() {
        var d = RightOptionDetector()
        #expect(d.keyDown() == nil)
    }

    @Test func comboDisplay() {
        #expect(KeyCombo.controlOptionSpace.displayString == "⌃⌥Space")
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey)).displayString == "⇧⌘F")
        #expect(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: UInt32(controlKey)).displayString == "⌃F5")
    }
}
