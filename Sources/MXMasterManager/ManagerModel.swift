import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement
import SwiftUI

final class ManagerModel: ObservableObject {
    @Published var mouse: MouseSnapshot?
    @Published var dpi = 1000.0
    @Published var smartShift = true
    @Published var shiftThreshold = 30.0
    @Published var zoomSensitivity = 1.0 {
        didSet {
            defaults.set(zoomSensitivity, forKey: "zoomSensitivity")
            input.zoomSensitivity = zoomSensitivity
        }
    }
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var conflict: String?
    @Published var inputStatus = ""
    @Published var captureActive = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var serviceError: String?
    @Published var backAction: ButtonAction = .back {
        didSet { defaults.set(backAction.rawValue, forKey: "backAction"); input.backAction = backAction }
    }
    @Published var forwardAction: ButtonAction = .forward {
        didSet { defaults.set(forwardAction.rawValue, forKey: "forwardAction"); input.forwardAction = forwardAction }
    }
    @Published var tapAction: ButtonAction = .smartZoom {
        didSet { defaults.set(tapAction.rawValue, forKey: "tapAction"); input.tapAction = tapAction }
    }

    private let defaults = UserDefaults.standard
    private let device = MouseDevice()
    private let input = InputController()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var wasConnected = false
    private var desiredCapture = false
    private var preferencesApplied = false
    var editingDPI = false
    var editingThreshold = false

    init() {
        zoomSensitivity = defaults.object(forKey: "zoomSensitivity") as? Double ?? 1.0
        input.zoomSensitivity = zoomSensitivity
        backAction = ButtonAction(rawValue: defaults.string(forKey: "backAction") ?? "") ?? .back
        forwardAction = ButtonAction(rawValue: defaults.string(forKey: "forwardAction") ?? "") ?? .forward
        tapAction = ButtonAction(rawValue: defaults.string(forKey: "tapAction") ?? "") ?? .smartZoom
        input.backAction = backAction
        input.forwardAction = forwardAction
        input.tapAction = tapAction
        device.onSnapshot = { [weak self] snapshot in
            DispatchQueue.main.async { self?.receive(snapshot) }
        }
        device.onInput = { [weak self] event in
            DispatchQueue.main.async { self?.input.handle(event) }
        }
        input.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.inputStatus = status }
        }
    }

    func start() {
        refreshPermissions()
        device.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.device.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        device.setInputCaptureEnabled(false)
        input.stop()
        device.stop()
    }

    private func receive(_ snapshot: MouseSnapshot) {
        mouse = snapshot
        captureActive = snapshot.inputCaptureEnabled
        if snapshot.connected {
            if !wasConnected {
                preferencesApplied = false
            }
            if !editingDPI, let value = snapshot.dpi { dpi = Double(value) }
            smartShift = snapshot.smartShiftEnabled ?? true
            if !editingThreshold, let threshold = snapshot.smartShiftThreshold {
                shiftThreshold = Double(threshold)
            }
        } else {
            preferencesApplied = false
            input.stop()
        }
        wasConnected = snapshot.connected
        applySavedPreferences()
        updateCapture()
    }

    func refreshPermissions() {
        accessibility = InputController.accessibilityGranted
        let previouslyGranted = inputMonitoring
        inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if inputMonitoring && !previouslyGranted { device.refresh() }
        let conflicts = NSWorkspace.shared.runningApplications.filter { application in
            guard let id = application.bundleIdentifier?.lowercased() else { return false }
            return id.hasPrefix("org.openlogi.") || id.hasPrefix("com.logi.optionsplus")
                || id.hasPrefix("com.logitech.logioptions")
        }
        conflict = conflicts.isEmpty ? nil : (conflicts.first?.localizedName ?? "Another mouse manager")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        applySavedPreferences()
        updateCapture()
    }

    private func updateCapture() {
        let ready = accessibility && inputMonitoring && conflict == nil && mouse?.connected == true
        guard ready != desiredCapture else { return }
        desiredCapture = ready
        device.setInputCaptureEnabled(ready)
        if !ready { input.stop() }
    }

    var canWriteSettings: Bool { mouse?.connected == true && inputMonitoring && conflict == nil }

    private func applySavedPreferences() {
        guard canWriteSettings, !preferencesApplied else { return }
        preferencesApplied = true
        if defaults.object(forKey: "dpi") != nil {
            device.setDPI(defaults.integer(forKey: "dpi"))
        }
        if defaults.object(forKey: "smartShift") != nil {
            device.setSmartShift(enabled: defaults.bool(forKey: "smartShift"),
                                 threshold: defaults.integer(forKey: "shiftThreshold"))
        }
    }

    func applyDPI() {
        guard canWriteSettings else { return }
        let lower = mouse?.minDPI ?? 200
        let upper = mouse?.maxDPI ?? 4000
        let step = max(mouse?.dpiStep ?? 50, 1)
        let value = max(lower, min(upper, Int((dpi / Double(step)).rounded()) * step))
        dpi = Double(value)
        defaults.set(value, forKey: "dpi")
        device.setDPI(value)
    }

    func applySmartShift() {
        guard canWriteSettings else { return }
        defaults.set(smartShift, forKey: "smartShift")
        defaults.set(shiftThreshold, forKey: "shiftThreshold")
        device.setSmartShift(enabled: smartShift, threshold: Int(shiftThreshold))
    }

    func setWheelMode(freeSpin: Bool) {
        guard canWriteSettings else { return }
        device.setWheelMode(freeSpin: freeSpin)
    }

    func requestAccessibility() {
        InputController.requestAccessibility()
        openPrivacy("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        openPrivacy("Privacy_ListenEvent")
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            serviceError = nil
        } catch { serviceError = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath, "--args", "--delayed-start"]
        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch { serviceError = error.localizedDescription }
    }
}
