import AVFoundation
import XCTest
@testable import Glutt

final class PollyAudioSessionTests: XCTestCase {

    func testBluetoothPortsRecognized() {
        XCTAssertTrue(PollyAudioSession.isBluetoothPort(.bluetoothHFP))
        XCTAssertTrue(PollyAudioSession.isBluetoothPort(.bluetoothA2DP))
        XCTAssertTrue(PollyAudioSession.isBluetoothPort(.bluetoothLE))
        XCTAssertFalse(PollyAudioSession.isBluetoothPort(.builtInSpeaker))
        XCTAssertFalse(PollyAudioSession.isBluetoothPort(.builtInMic))
        XCTAssertFalse(PollyAudioSession.isBluetoothPort(.headphones))
    }

    func testCategoryOptionsAllowBluetoothDuplex() {
        let options = PollyAudioSession.categoryOptions
        XCTAssertTrue(options.contains(.allowBluetooth), "HFP required for AirPods mic+speaker")
        XCTAssertTrue(options.contains(.defaultToSpeaker), "built-in path still prefers loudspeaker")
    }
}
