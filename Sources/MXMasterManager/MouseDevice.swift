import Foundation

// Protocol layouts are adapted from OpenLogi, including its 0BSD HID++ crate
// (Copyright 2025 Lukas Schulte Pelkum). Credit also to Logitech's public HID++
// feature specifications and Solaar. See THIRD_PARTY_NOTICES.md.

struct MouseSnapshot {
    var name = "MX Master 3"
    var connected = false
    var battery: Int?
    var dpi: Int?
    var minDPI = 200
    var maxDPI = 4000
    var dpiStep = 50
    var smartShiftEnabled: Bool?
    var smartShiftThreshold: Int?
    var inputCaptureEnabled = false
    var status = "Connect your MX Master 3 over Bluetooth."
}

enum MouseInput {
    case gesturePressed
    case gestureReleased
    case gestureCancelled
    case gestureMoved(dx: Int, dy: Int)
    case backPressed
    case forwardPressed
}

/// Small, host-independent packet helpers. Unknown/malformed fields are errors,
/// never silently interpreted as a supported device configuration.
enum MouseProtocol {
    static let gesture: UInt16 = 0x00c3
    static let backIDs: [UInt16] = [0x0053, 0x00bd, 0x00ce, 0x00db]
    static let forwardIDs: [UInt16] = [0x0056, 0x00cf]

    static func word(_ bytes: [UInt8], at index: Int = 0) -> UInt16 {
        UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
    }

    static func dpiValues(_ bytes: [UInt8]) throws -> [Int] {
        guard bytes.count >= 3, bytes[0] == 0 else { throw HIDError.invalidReply }
        var values: [Int] = []
        var offset = 1
        while offset + 1 < bytes.count {
            let value = Int(word(bytes, at: offset))
            if value == 0 { break }
            if value & 0xe000 == 0xe000 {
                let step = value & 0x1fff
                guard step > 0, let first = values.last, offset + 3 < bytes.count else { throw HIDError.invalidReply }
                let last = Int(word(bytes, at: offset + 2))
                guard last >= first, last & 0xe000 != 0xe000 else { throw HIDError.invalidReply }
                values.append(contentsOf: stride(from: first + step, to: last, by: step))
                values.append(last)
                offset += 4
            } else {
                values.append(value)
                offset += 2
            }
        }
        guard !values.isEmpty else { throw HIDError.invalidReply }
        return Array(Set(values)).sorted()
    }

    /// getCidReporting uses value bits, setCidReporting uses value/valid pairs.
    /// Change only temporary diversion and (for the gesture source) raw XY;
    /// persistent diversion, remaps, analytics and raw wheel stay untouched.
    static func reportingChange(cid: UInt16, diverted: Bool, rawXY: Bool?) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8(cid >> 8)
        bytes[1] = UInt8(cid & 0xff)
        bytes[2] = 0x02 | (diverted ? 0x01 : 0)
        if let rawXY { bytes[2] |= 0x20 | (rawXY ? 0x10 : 0) }
        return bytes
    }
}

final class MouseDevice: @unchecked Sendable {
    /// Both callbacks run on the main queue.
    var onSnapshot: ((MouseSnapshot) -> Void)?
    var onInput: ((MouseInput) -> Void)?

    private struct Control {
        let cid: UInt16
        let flags: UInt16
        var divertable: Bool { flags & 0x20 != 0 }
        var rawXY: Bool { flags & 0x100 != 0 }
    }
    private struct BorrowedControl {
        let cid: UInt16
        let diverted: Bool
        let rawXY: Bool?
    }

    private let worker = DispatchQueue(label: "MX Master device", qos: .userInteractive)
    private let transport = HIDTransport()
    private let lifecycle = NSLock()
    private var stopping = false // lifecycle lock
    private var interruptibleSession: HIDSession? // lifecycle lock
    private var session: HIDSession? // worker only below
    private var features: [UInt16: UInt8] = [:]
    private var controls: [Control] = []
    private var supportedDPI: [Int] = []
    private var borrowedControls: [BorrowedControl] = []
    private var desiredCapture = false
    private var pressed: Set<UInt16> = []
    private var skipNextRawXY = false
    private var timer: DispatchSourceTimer?
    private var snapshot = MouseSnapshot()
    private var lastSettingsRead = Date.distantPast
    private var recovering = false

    init() {
        transport.onConnect = { [weak self] session in
            self?.worker.async { [weak self] in self?.connected(session) }
        }
        transport.onDisconnect = { [weak self] identifier in
            self?.worker.async { [weak self] in self?.disconnected(identifier) }
        }
        transport.onError = { [weak self] message in
            self?.worker.async { [weak self] in
                guard let self else { return }
                self.snapshot.status = message
                self.publish()
            }
        }
    }

    /// Enumerates and reads only. Capturing buttons is a separate opt-in write.
    func start() {
        lifecycle.lock(); stopping = false; lifecycle.unlock()
        worker.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.worker)
            timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
            timer.setEventHandler { [weak self] in self?.recoverOrRefresh() }
            self.timer = timer
            timer.resume()
            self.publish()
            self.transport.start()
        }
    }

    /// Call after system wake or a permission change. The recovery scan is
    /// otherwise deliberately infrequent to let Bluetooth hardware sleep.
    func refresh() {
        worker.async { [weak self] in
            guard let self, !self.isStopping else { return }
            if self.session == nil { self.transport.retryConnection() }
            else { self.recoverOrRefresh() }
        }
    }

    /// Gives borrowed button reporting state back before closing IOKit. The
    /// caller may use this from applicationWillTerminate; waits at most 2.4 s.
    func stop() {
        lifecycle.lock()
        stopping = true
        let current = interruptibleSession
        lifecycle.unlock()
        current?.cancelPendingRequest()
        let finished = DispatchSemaphore(value: 0)
        worker.async { [self] in
            timer?.cancel(); timer = nil
            desiredCapture = false
            restoreCapture()
            session?.onEvent = nil
            session = nil
            lifecycle.lock(); interruptibleSession = nil; lifecycle.unlock()
            transport.stop()
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + 2.4)
    }

    func setInputCaptureEnabled(_ enabled: Bool) {
        worker.async { [weak self] in
            guard let self, !self.isStopping else { return }
            self.desiredCapture = enabled
            do {
                if enabled {
                    try self.armCapture()
                } else if !self.restoreCapture() {
                    throw HIDError.unsupported("restoring native button reporting; wake the mouse and retry")
                }
                self.snapshot.status = self.session == nil ? "Connect your MX Master 3 over Bluetooth." : "Connected over Bluetooth."
            } catch {
                self.restoreCapture()
                self.snapshot.status = "Button setup failed: \(error.localizedDescription)"
            }
            self.publish()
        }
    }

    func setDPI(_ value: Int) {
        performWrite { mouse in
            guard let index = mouse.features[0x2201] else { throw HIDError.unsupported("adjustable DPI") }
            guard let nearest = mouse.supportedDPI.min(by: { abs($0 - value) < abs($1 - value) }) else { throw HIDError.invalidReply }
            _ = try mouse.call(index, 3, [0, UInt8(nearest >> 8), UInt8(nearest & 0xff)])
            let reply = try mouse.call(index, 2)
            guard reply.count >= 3 else { throw HIDError.invalidReply }
            let applied = Int(MouseProtocol.word(reply, at: 1))
            guard applied == nearest else { throw HIDError.invalidReply }
            mouse.snapshot.dpi = applied
        }
    }

    func setSmartShift(enabled: Bool, threshold: Int) {
        performWrite { mouse in
            let (index, enhanced) = try mouse.smartShiftFeature()
            let threshold = enabled ? UInt8(clamping: max(1, min(254, threshold))) : 0xff
            // Ratchet mode + threshold gives automatic disengagement. 0xff
            // disables automatic disengagement; third byte 0 keeps defaults
            // (2110) / torque (2111) unchanged.
            _ = try mouse.call(index, enhanced ? 2 : 1, [2, threshold, 0])
            let status = try mouse.readSmartShift()
            guard status.mode == 2, status.threshold == threshold else { throw HIDError.invalidReply }
        }
    }

    func setWheelMode(freeSpin: Bool) {
        performWrite { mouse in
            let (index, enhanced) = try mouse.smartShiftFeature()
            let mode: UInt8 = freeSpin ? 1 : 2
            _ = try mouse.call(index, enhanced ? 2 : 1, [mode, 0, 0])
            let status = try mouse.readSmartShift()
            guard status.mode == mode else { throw HIDError.invalidReply }
        }
    }

    private var isStopping: Bool {
        lifecycle.lock(); defer { lifecycle.unlock() }; return stopping
    }

    private func performWrite(_ write: @escaping (MouseDevice) throws -> Void) {
        worker.async { [weak self] in
            guard let self, !self.isStopping else { return }
            do {
                guard self.snapshot.connected else { throw HIDError.disconnected }
                try write(self)
                self.snapshot.status = "Settings applied to your MX Master."
            } catch { self.snapshot.status = error.localizedDescription }
            self.publish()
        }
    }

    private func connected(_ newSession: HIDSession) {
        guard !isStopping else { return }
        // A Bluetooth MX Master should have one long-report vendor collection.
        // Do not switch away from a live session if IOKit presents a duplicate.
        guard session == nil else { return }
        session = newSession
        lifecycle.lock(); interruptibleSession = newSession; lifecycle.unlock()
        snapshot.name = newSession.name
        newSession.onEvent = { [weak self, weak newSession] message in
            self?.worker.async { [weak self, weak newSession] in
                guard let self, let newSession, self.session === newSession else { return }
                self.handle(message)
            }
        }
        probe()
    }

    private func probe() {
        guard session != nil, !isStopping else { return }
        features.removeAll(); controls.removeAll(); supportedDPI.removeAll()
        do {
            let ping = try call(0, 1, [0, 0, 0xa7])
            guard ping.count >= 3, ping[0] >= 2, ping[2] == 0xa7 else { throw HIDError.invalidReply }
            for id: UInt16 in [0x2201, 0x2111, 0x2110, 0x1004, 0x1000, 0x1b04, 0x2150] {
                let response = try call(0, 0, [UInt8(id >> 8), UInt8(id & 0xff), 0])
                guard response.count >= 3 else { throw HIDError.invalidReply }
                if response[0] != 0 { features[id] = response[0] }
            }
            if let index = features[0x1b04] {
                let count = try call(index, 0)[0]
                guard count <= 64 else { throw HIDError.invalidReply }
                for position in 0..<count {
                    let info = try call(index, 1, [position])
                    guard info.count >= 9 else { throw HIDError.invalidReply }
                    controls.append(Control(cid: MouseProtocol.word(info), flags: UInt16(info[4]) | UInt16(info[8]) << 8))
                }
            }
            snapshot.connected = true
            try readSettings()
            snapshot.status = "Connected over Bluetooth."
            if desiredCapture { try armCapture() }
        } catch {
            snapshot.connected = false
            snapshot.inputCaptureEnabled = false
            snapshot.status = error.localizedDescription
        }
        publish()
    }

    private func disconnected(_ identifier: UInt64) {
        guard session?.registryID == identifier else { return }
        releaseGesture()
        session?.onEvent = nil
        session = nil
        lifecycle.lock(); interruptibleSession = nil; lifecycle.unlock()
        borrowedControls.removeAll(); pressed.removeAll()
        features.removeAll(); controls.removeAll()
        snapshot.connected = false
        snapshot.inputCaptureEnabled = false
        snapshot.status = "MX Master is disconnected. Reconnect it over Bluetooth."
        publish()
    }

    private func call(_ feature: UInt8, _ function: UInt8, _ parameters: [UInt8] = [], timeout: TimeInterval = 0.8) throws -> [UInt8] {
        guard let session else { throw HIDError.disconnected }
        if isStopping && timeout >= 0.8 { throw HIDError.disconnected }
        return try session.request(feature: feature, function: function, parameters: parameters, timeout: timeout)
    }

    private func readSettings() throws {
        if let index = features[0x2201] {
            supportedDPI = try MouseProtocol.dpiValues(call(index, 1))
            snapshot.minDPI = supportedDPI.first!
            snapshot.maxDPI = supportedDPI.last!
            let gaps = zip(supportedDPI, supportedDPI.dropFirst()).map { $1 - $0 }
            snapshot.dpiStep = gaps.min() ?? 1
            let reply = try call(index, 2)
            guard reply.count >= 3 else { throw HIDError.invalidReply }
            snapshot.dpi = Int(MouseProtocol.word(reply, at: 1))
        }
        if features[0x2111] != nil || features[0x2110] != nil { _ = try readSmartShift() }
        try readBattery()
        lastSettingsRead = Date()
    }

    private func smartShiftFeature() throws -> (UInt8, Bool) {
        if let feature = features[0x2111] { return (feature, true) }
        if let feature = features[0x2110] { return (feature, false) }
        throw HIDError.unsupported("SmartShift")
    }

    @discardableResult
    private func readSmartShift() throws -> (mode: UInt8, threshold: UInt8) {
        let (index, enhanced) = try smartShiftFeature()
        let reply = try call(index, enhanced ? 1 : 0)
        guard reply.count >= 3, reply[0] == 1 || reply[0] == 2 else { throw HIDError.invalidReply }
        snapshot.smartShiftEnabled = reply[1] > 0 && reply[1] < 0xff
        snapshot.smartShiftThreshold = reply[1] == 0xff ? nil : Int(reply[1])
        return (reply[0], reply[1])
    }

    private func readBattery() throws {
        if let index = features[0x1004] {
            let capability = try call(index, 0)
            let info = try call(index, 1)
            guard info.count >= 3, capability.count >= 2 else { throw HIDError.invalidReply }
            // A level-only battery reports percentage=0 meaning unknown.
            snapshot.battery = capability[1] & 2 != 0 && info[0] <= 100 ? Int(info[0]) : nil
        } else if let index = features[0x1000] {
            let info = try call(index, 0)
            guard info.count >= 3 else { throw HIDError.invalidReply }
            // Legacy charging replies use zero for unknown charge.
            snapshot.battery = info[2] == 0 && info[0] <= 100 ? Int(info[0]) : nil
        }
    }

    private func armCapture() throws {
        guard snapshot.connected, !snapshot.inputCaptureEnabled else { return }
        // Failed rollbacks retain their owner records. Finish handing those
        // controls back before borrowing them again with a fresh snapshot.
        if !borrowedControls.isEmpty, !restoreCapture() {
            throw HIDError.unsupported("restoring native button reporting; wake the mouse and retry")
        }
        guard let index = features[0x1b04] else { throw HIDError.unsupported("button diversion") }
        guard controls.contains(where: { $0.cid == MouseProtocol.gesture && $0.divertable && $0.rawXY }),
              let back = controls.first(where: { MouseProtocol.backIDs.contains($0.cid) && $0.divertable }),
              let forward = controls.first(where: { MouseProtocol.forwardIDs.contains($0.cid) && $0.divertable }) else {
            throw HIDError.unsupported("the required gesture and side-button controls")
        }
        let requested = [MouseProtocol.gesture, back.cid, forward.cid]
        do {
            for cid in requested {
                let original = try call(index, 2, [UInt8(cid >> 8), UInt8(cid & 0xff), 0])
                guard original.count >= 6, MouseProtocol.word(original) == cid else { throw HIDError.invalidReply }
                // Borrow only native controls. Concurrent HID++ writers race
                // on device state; taking another client's diverted control
                // would make restoration and command injection unreliable.
                guard original[2] & 0x05 == 0 else {
                    throw HIDError.unsupported("exclusive button access; quit other mouse managers")
                }
                let rawXY: Bool? = cid == MouseProtocol.gesture ? original[2] & 0x10 != 0 : nil
                borrowedControls.append(BorrowedControl(cid: cid, diverted: original[2] & 1 != 0, rawXY: rawXY))
                _ = try call(index, 3, MouseProtocol.reportingChange(cid: cid, diverted: true, rawXY: cid == MouseProtocol.gesture ? true : nil))
                let verified = try call(index, 2, [UInt8(cid >> 8), UInt8(cid & 0xff), 0])
                guard verified.count >= 3, MouseProtocol.word(verified) == cid, verified[2] & 1 != 0,
                      cid != MouseProtocol.gesture || verified[2] & 0x10 != 0 else { throw HIDError.invalidReply }
            }
            // Horizontal scrolling stays in firmware's native HID path. We
            // do not divert its reports or change the user's wheel direction.
            if let wheel = features[0x2150] {
                let status = try call(wheel, 1)
                guard status.first == 0 else {
                    throw HIDError.unsupported("native thumbwheel access; quit other mouse managers")
                }
            }
            pressed.removeAll()
            skipNextRawXY = false
            snapshot.inputCaptureEnabled = true
        } catch {
            restoreCapture()
            throw error
        }
    }

    @discardableResult
    private func restoreCapture() -> Bool {
        snapshot.inputCaptureEnabled = false
        releaseGesture()
        var failed: [BorrowedControl] = []
        if let index = features[0x1b04] {
            for original in borrowedControls.reversed() {
                do {
                    _ = try call(index, 3, MouseProtocol.reportingChange(cid: original.cid, diverted: original.diverted, rawXY: original.rawXY), timeout: 0.25)
                    let restored = try call(index, 2, [UInt8(original.cid >> 8), UInt8(original.cid & 0xff), 0], timeout: 0.25)
                    guard restored.count >= 3, MouseProtocol.word(restored) == original.cid,
                          (restored[2] & 1 != 0) == original.diverted,
                          original.rawXY == nil || (restored[2] & 0x10 != 0) == original.rawXY else {
                        throw HIDError.invalidReply
                    }
                } catch { failed.append(original) }
            }
        } else { failed = borrowedControls }
        borrowedControls = failed.reversed()
        if !failed.isEmpty {
            snapshot.status = "Could not restore native buttons. Wake the mouse and retry, or power it off and on."
        }
        pressed.removeAll()
        return failed.isEmpty
    }

    private func recoverOrRefresh() {
        guard !isStopping, !recovering else { return }
        guard session != nil else { transport.retryConnection(); return }
        recovering = true
        defer { recovering = false }
        if !snapshot.connected { probe(); return }
        do {
            // Wireless firmware can forget temporary diversion across sleep.
            // Re-arm only if the user still requested capture.
            if desiredCapture, snapshot.inputCaptureEnabled, let index = features[0x1b04] {
                for original in borrowedControls {
                    let status = try call(index, 2, [UInt8(original.cid >> 8), UInt8(original.cid & 0xff), 0])
                    guard status.count >= 3, MouseProtocol.word(status) == original.cid else { throw HIDError.invalidReply }
                    if status[2] & 1 == 0 || original.rawXY != nil && status[2] & 0x10 == 0 {
                        _ = try call(index, 3, MouseProtocol.reportingChange(cid: original.cid, diverted: true, rawXY: original.rawXY == nil ? nil : true))
                        let verified = try call(index, 2, [UInt8(original.cid >> 8), UInt8(original.cid & 0xff), 0])
                        guard verified.count >= 3, MouseProtocol.word(verified) == original.cid,
                              verified[2] & 1 != 0,
                              original.rawXY == nil || verified[2] & 0x10 != 0 else { throw HIDError.invalidReply }
                    }
                }
            }
            if desiredCapture, !snapshot.inputCaptureEnabled { try armCapture() }
            if !desiredCapture, !borrowedControls.isEmpty { _ = restoreCapture() }
        } catch {
            // A control read failure must never make the UI inactive while
            // silently leaving firmware buttons diverted and unhandled.
            let restored = restoreCapture()
            if restored { snapshot.status = "Button capture paused: \(error.localizedDescription)" }
        }
        if Date().timeIntervalSince(lastSettingsRead) >= 60 {
            do { try readSettings() }
            catch {
                // Battery/DPI reads are independent of an already verified
                // capture session. Their timeout must not disable its buttons.
                snapshot.status = "Settings refresh failed: \(error.localizedDescription)"
            }
        }
        publish()
    }

    private func handle(_ message: HIDMessage) {
        guard !isStopping else { return }
        if message.feature == features[0x1b04], !borrowedControls.isEmpty {
            let bytes = message.payload
            if message.function == 0, bytes.count >= 8 {
                // If a rollback could not be confirmed, keep handling the
                // controls still owed restoration until the bounded retry.
                let owned = Set(borrowedControls.map(\.cid))
                let now = Set(stride(from: 0, to: 8, by: 2).map { MouseProtocol.word(bytes, at: $0) }.filter { owned.contains($0) })
                if now.contains(MouseProtocol.gesture), !pressed.contains(MouseProtocol.gesture) {
                    skipNextRawXY = true
                    emit(.gesturePressed)
                }
                if !now.contains(MouseProtocol.gesture), pressed.contains(MouseProtocol.gesture) {
                    skipNextRawXY = false
                    emit(.gestureReleased)
                }
                for cid in now.subtracting(pressed) {
                    if MouseProtocol.backIDs.contains(cid) { emit(.backPressed) }
                    if MouseProtocol.forwardIDs.contains(cid) { emit(.forwardPressed) }
                }
                pressed = now
            } else if message.function == 1, bytes.count >= 4, pressed.contains(MouseProtocol.gesture) {
                // MX Master firmware's first report of a fresh hold can carry
                // movement accumulated before the press, including the return
                // stroke since the last gesture. OpenLogi drops this sample
                // on every hold; it must never become a zoom delta.
                if skipNextRawXY {
                    skipNextRawXY = false
                    return
                }
                emit(.gestureMoved(dx: Int(Int16(bitPattern: MouseProtocol.word(bytes))), dy: Int(Int16(bitPattern: MouseProtocol.word(bytes, at: 2)))))
            }
        } else if message.function == 0,
                  message.feature == features[0x1004] || message.feature == features[0x1000] {
            // Coalesce battery broadcasts through the existing background timer.
            lastSettingsRead = .distantPast
        }
    }

    private func releaseGesture() {
        if pressed.contains(MouseProtocol.gesture) { emit(.gestureCancelled) }
        pressed.removeAll()
        skipNextRawXY = false
    }

    private func emit(_ input: MouseInput) {
        DispatchQueue.main.async { [weak self] in self?.onInput?(input) }
    }

    private func publish() {
        let value = snapshot
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(value) }
    }
}
