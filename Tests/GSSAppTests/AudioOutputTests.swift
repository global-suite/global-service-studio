import XCTest
@testable import GSSApp

final class AudioOutputTests: XCTestCase {
    func testTheAudioOutputDeviceIsStored() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GSSAudioOutputTests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.audioOutputDeviceUID, "the system default when unset")
        settings.audioOutputDeviceUID = "Invented-Device-UID"
        XCTAssertEqual(AppSettings(defaults: defaults).audioOutputDeviceUID, "Invented-Device-UID")
        settings.audioOutputDeviceUID = nil
        XCTAssertNil(AppSettings(defaults: defaults).audioOutputDeviceUID)
    }

    func testTheSystemDefaultChoiceIsTranslated() {
        XCTAssertEqual(Strings.text("System default", language: "en"), "System default")
        XCTAssertEqual(Strings.text("System default", language: "es"), "Predeterminado del sistema")
    }
}
