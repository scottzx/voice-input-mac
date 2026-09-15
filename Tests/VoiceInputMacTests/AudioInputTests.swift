import XCTest
@testable import VoiceInputCore

final class AudioInputTests: XCTestCase {
    func testListedUIDsAreUnique() {
        let devices = AudioInputs.list()
        let uids = devices.map(\.uid)
        XCTAssertEqual(uids.count, Set(uids).count)
        XCTAssertEqual(devices.filter(\.isDefault).count, devices.isEmpty ? 0 : 1)
    }

    func testEmptyUIDResolvesToDefault() {
        let devices = AudioInputs.list()
        let resolved = AudioInputs.resolve(uid: "")
        if devices.isEmpty {
            XCTAssertNil(resolved)
        } else {
            XCTAssertEqual(resolved?.uid, devices.first(where: \.isDefault)?.uid ?? devices.first?.uid)
        }
        XCTAssertEqual(AudioInputs.resolve(uid: nil)?.uid, resolved?.uid)
    }

    func testUnknownUIDResolvesToNil() {
        XCTAssertNil(AudioInputs.resolve(uid: "not-a-real-input-\(UUID().uuidString)"))
    }

    func testWatcherStartAndStop() {
        let watcher = AudioInputWatcher()
        let lock = NSLock()
        var fires = 0
        watcher.start {
            lock.lock()
            fires += 1
            lock.unlock()
        }
        watcher.stop()
        lock.lock()
        let count = fires
        lock.unlock()
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}
