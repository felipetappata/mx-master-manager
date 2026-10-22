import Foundation
import IOKit.hid

// HID++ framing and collection selection follow OpenLogi's openlogi-hid and
// openlogi-hidpp implementations. Protocol background: Logitech's public HID++
// specifications and the Solaar project. See THIRD_PARTY_NOTICES.md.

enum HIDError: Error, LocalizedError, Equatable {
    case disconnected
    case timeout
    case io(IOReturn)
    case protocolError(UInt8)
    case invalidReply
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .disconnected: return "MX Master is disconnected."
        case .timeout: return "MX Master did not respond. Wake the mouse and try again."
        case .io(let code): return "HID access failed (\(String(format: "0x%08x", code))). Check Input Monitoring."
        case .protocolError(let code): return "MX Master rejected the request (HID++ \(code))."
        case .invalidReply: return "MX Master returned an unsupported response."
        case .unsupported(let name): return "This mouse does not expose \(name)."
        }
    }
}

struct HIDMessage {
    let device: UInt8
    let feature: UInt8
    let functionAndSoftware: UInt8
    let payload: [UInt8]

    var function: UInt8 { functionAndSoftware >> 4 }
    var softwareID: UInt8 { functionAndSoftware & 0x0f }

    init?(bytes: [UInt8]) {
        guard let reportID = bytes.first,
              (reportID == 0x10 && bytes.count >= 7) || (reportID == 0x11 && bytes.count >= 20) else { return nil }
        device = bytes[1]
        feature = bytes[2]
        functionAndSoftware = bytes[3]
        payload = Array(bytes[4..<(reportID == 0x10 ? 7 : 20)])
    }

    func response(toFeature feature: UInt8, functionAndSoftware header: UInt8) -> Result<[UInt8], HIDError>? {
        if self.feature == feature && functionAndSoftware == header { return .success(payload) }
        // An HID++ 2 error shifts the rejected feature to byte 3, the
        // function/software byte to byte 4, and the error code to byte 5.
        if self.feature == 0xff, functionAndSoftware == feature,
           payload.count >= 2, payload[0] == header {
            return .failure(.protocolError(payload[1]))
        }
        return nil
    }
}

/// One physical Bluetooth mouse's vendor HID collection. Reads arrive on the
/// transport run loop; requests wait only on MouseDevice's background worker.
final class HIDSession: @unchecked Sendable {
    private final class Pending {
        let feature: UInt8
        let functionAndSoftware: UInt8
        let ready = DispatchSemaphore(value: 0)
        var result: Result<[UInt8], Error>?

        init(feature: UInt8, functionAndSoftware: UInt8) {
            self.feature = feature
            self.functionAndSoftware = functionAndSoftware
        }
    }

    let device: IOHIDDevice
    let name: String
    let registryID: UInt64
    private var eventHandler: ((HIDMessage) -> Void)?
    var onEvent: ((HIDMessage) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return eventHandler }
        set { lock.lock(); eventHandler = newValue; lock.unlock() }
    }
    private let lock = NSLock()
    private let requestLock = NSLock()
    private var connected = true
    private var pending: Pending?
    private var softwareID: UInt8 = UInt8.random(in: 1...15)
    private var abandoned: [UInt16: Date] = [:] // serialized request owner
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int

    init(device: IOHIDDevice) {
        self.device = device
        name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "MX Master 3"
        var identifier: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &identifier)
        registryID = identifier
        let reported = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64
        bufferSize = min(4096, max(64, reported))
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit { buffer.deallocate() }

    func registerInput() {
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, result, _, _, reportID, report, length in
            guard result == kIOReturnSuccess, let context, length > 0 else { return }
            let session = Unmanaged<HIDSession>.fromOpaque(context).takeUnretainedValue()
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            // IOKit normally includes the report ID; accept the documented
            // callback reportID separately on implementations that omit it.
            if bytes.first != UInt8(truncatingIfNeeded: reportID) {
                bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0)
            }
            session.receive(bytes)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Called on the HID run loop after callbacks have been unscheduled.
    func close() {
        lock.lock()
        connected = false
        if let pending, pending.result == nil {
            pending.result = .failure(HIDError.disconnected)
            pending.ready.signal()
        }
        lock.unlock()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func cancelPendingRequest() {
        lock.lock()
        if let pending, pending.result == nil {
            pending.result = .failure(HIDError.disconnected)
            pending.ready.signal()
        }
        lock.unlock()
    }

    func request(deviceIndex: UInt8 = 0xff, feature: UInt8, function: UInt8,
                 parameters: [UInt8] = [], timeout: TimeInterval = 0.8) throws -> [UInt8] {
        precondition(!Thread.isMainThread, "HID++ exchanges must stay off the main thread")
        guard parameters.count <= 16, function < 16 else { throw HIDError.invalidReply }
        requestLock.lock()
        defer { requestLock.unlock() }
        lock.lock()
        guard connected else { lock.unlock(); throw HIDError.disconnected }
        let now = Date()
        abandoned = abandoned.filter { now.timeIntervalSince($0.value) < 10 }
        var header: UInt8?
        for _ in 0..<15 {
            softwareID = softwareID % 15 + 1
            let candidate = function << 4 | softwareID
            let key = UInt16(feature) << 8 | UInt16(candidate)
            if abandoned[key] == nil { header = candidate; break }
        }
        guard let header else { lock.unlock(); throw HIDError.timeout }
        let transaction = Pending(feature: feature, functionAndSoftware: header)
        pending = transaction
        lock.unlock()

        // Always use the long report: this works on classic Bluetooth and on
        // HID++ collections that expose no short report. Include its report ID.
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = feature
        report[3] = header
        report.replaceSubrange(4..<(4 + parameters.count), with: parameters)
        let written = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, $0.baseAddress!, $0.count)
        }
        if written != kIOReturnSuccess {
            lock.lock()
            pending = nil
            lock.unlock()
            throw HIDError.io(written)
        }
        _ = transaction.ready.wait(timeout: .now() + timeout)
        lock.lock()
        let result = transaction.result
        if pending === transaction { pending = nil }
        lock.unlock()
        if result == nil { abandoned[UInt16(feature) << 8 | UInt16(header)] = Date() }
        return try (result ?? .failure(HIDError.timeout)).get()
    }

    private func receive(_ bytes: [UInt8]) {
        guard let message = HIDMessage(bytes: bytes), message.device == 0xff else { return }
        lock.lock()
        guard connected else { lock.unlock(); return }
        if let waiting = pending, waiting.result == nil {
            if let response = message.response(toFeature: waiting.feature, functionAndSoftware: waiting.functionAndSoftware) {
                waiting.result = response.mapError { $0 as Error }
                waiting.ready.signal()
                lock.unlock()
                return
            }
        }
        let handler = eventHandler
        lock.unlock()
        if message.softwareID == 0 { handler?(message) }
    }
}

/// A single long-lived IOKit manager, limited to this user's MX Master 3.
/// No HID seizure, generic event tap, helper process, polling enumeration,
/// network traffic, receiver pairing, or unrelated device handling.
final class HIDTransport: @unchecked Sendable {
    var onConnect: ((HIDSession) -> Void)?
    var onDisconnect: ((UInt64) -> Void)?
    var onError: ((String) -> Void)?

    private let stateLock = NSLock()
    private var shouldStop = false
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var manager: IOHIDManager?
    private var sessions: [UInt64: HIDSession] = [:] // HID run loop only

    func start() {
        stateLock.lock()
        guard thread == nil else { stateLock.unlock(); return }
        shouldStop = false
        let worker = Thread { [self] in run() }
        worker.name = "MX Master HID"
        thread = worker
        stateLock.unlock()
        worker.start()
    }

    func stop() {
        stateLock.lock()
        shouldStop = true
        let loop = runLoop
        stateLock.unlock()
        if let loop { CFRunLoopWakeUp(loop) }
    }

    /// Reattempt denied opens after the user grants Input Monitoring, without
    /// rebuilding the manager or prompting for permission from this layer.
    func retryConnection() {
        stateLock.lock()
        let loop = runLoop
        let currentManager = manager
        let stopping = shouldStop
        stateLock.unlock()
        guard !stopping, let loop, let currentManager else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            guard let self,
                  let devices = IOHIDManagerCopyDevices(currentManager) as? Set<IOHIDDevice> else { return }
            for device in devices { self.attach(device) }
        }
        CFRunLoopWakeUp(loop)
    }

    private func run() {
        let loop = CFRunLoopGetCurrent()!
        stateLock.lock(); runLoop = loop; stateLock.unlock()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        stateLock.lock(); self.manager = manager; stateLock.unlock()
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: 0x046d, kIOHIDProductIDKey: 0xb023, kIOHIDDeviceUsagePageKey: 0xff00, kIOHIDDeviceUsageKey: 2],
            [kIOHIDVendorIDKey: 0x046d, kIOHIDProductIDKey: 0xb023, kIOHIDDeviceUsagePageKey: 0xff43, kIOHIDDeviceUsageKey: 0x0202]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if opened != kIOReturnSuccess { onError?(HIDError.io(opened).localizedDescription) }
        while true {
            stateLock.lock(); let stop = shouldStop; stateLock.unlock()
            if stop { break }
            CFRunLoopRunInMode(.defaultMode, 0.25, false)
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue)
        for session in sessions.values { session.close() }
        sessions.removeAll()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        stateLock.lock(); self.manager = nil; runLoop = nil; thread = nil; stateLock.unlock()
    }

    private func attach(_ device: IOHIDDevice) {
        let session = HIDSession(device: device)
        guard sessions[session.registryID] == nil else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { onError?(HIDError.io(result).localizedDescription); return }
        sessions[session.registryID] = session
        session.registerInput()
        onConnect?(session)
    }

    private func detach(_ device: IOHIDDevice) {
        var identifier: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &identifier)
        guard let session = sessions.removeValue(forKey: identifier) else { return }
        session.close()
        onDisconnect?(identifier)
    }
}
