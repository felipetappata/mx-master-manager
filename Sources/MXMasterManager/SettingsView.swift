import AppKit
import SwiftUI

private enum DeviceSection: String, CaseIterable, Identifiable {
    case buttons = "Buttons", pointer = "Pointer", device = "Device"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .buttons: return "computermouse"
        case .pointer: return "cursorarrow.motionlines"
        case .device: return "gearshape"
        }
    }
}

private enum MouseControl: String, CaseIterable, Identifiable {
    case gesture = "Gesture Button", forward = "Forward", back = "Back"
    case middle = "Middle Click", mode = "Mode Shift", thumbwheel = "Thumb Wheel"
    var id: String { rawValue }
    var point: CGPoint {
        switch self {
        case .middle: return CGPoint(x: 0.71, y: 0.15)
        case .mode: return CGPoint(x: 0.81, y: 0.34)
        case .thumbwheel: return CGPoint(x: 0.55, y: 0.515)
        case .forward: return CGPoint(x: 0.35, y: 0.43)
        case .back: return CGPoint(x: 0.45, y: 0.60)
        case .gesture: return CGPoint(x: 0.08, y: 0.58)
        }
    }
    var isLeft: Bool { self == .gesture || self == .forward || self == .back }
    var labelY: CGFloat {
        switch self {
        case .gesture: return 0.30
        case .forward: return 0.52
        case .back: return 0.74
        case .middle: return 0.20
        case .mode: return 0.47
        case .thumbwheel: return 0.78
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: ManagerModel
    @State private var section: DeviceSection = .buttons
    @State private var selected: MouseControl = .gesture

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(DeviceSection.allCases) { item in
                        Button {
                            section = item
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 12)
                                .background(section == item ? Color.accentColor.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(section == item ? Color.accentColor : Color.primary)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Text("MX Master Manager").font(.caption).foregroundStyle(.secondary).padding(12)
                }.padding(12).frame(width: 168).background(Color(nsColor: .windowBackgroundColor))
                Divider()
                Group {
                    switch section {
                    case .buttons: buttonsWorkspace
                    case .pointer: pointerWorkspace
                    case .device: deviceWorkspace
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "computermouse.fill").font(.system(size: 23)).foregroundStyle(.secondary)
            Text(model.mouse?.name ?? "MX Master 3").font(.system(size: 15, weight: .semibold))
            Circle().fill(model.mouse?.connected == true ? Color.green : Color.secondary).frame(width: 6, height: 6)
            Text(model.mouse?.connected == true ? "Bluetooth" : "Disconnected").font(.callout).foregroundStyle(.secondary)
            if let battery = model.mouse?.battery {
                Image(systemName: "battery.100percent").foregroundStyle(.secondary)
                Text("\(battery)%").monospacedDigit().font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.captureActive {
                Label("Active", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
            } else {
                Button("Check access") { section = .device }.buttonStyle(.borderless)
            }
        }.padding(.horizontal, 24).frame(height: 64)
    }

    private var buttonsWorkspace: some View {
        HStack(spacing: 0) {
            mouseCanvas
                .background(workspaceBackground)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(selected.rawValue).font(.system(size: 22, weight: .semibold))
                    switch selected {
                    case .gesture:
                        Text("Gestures").font(.callout).foregroundStyle(.secondary)
                        directionRow("Forward", action: "Zoom in", symbol: "arrow.up")
                        directionRow("Backward", action: "Zoom out", symbol: "arrow.down")
                        directionRow("Left", action: "No action", symbol: "arrow.left")
                        directionRow("Right", action: "No action", symbol: "arrow.right")
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tap").font(.callout).foregroundStyle(.secondary)
                            actionPicker($model.tapAction)
                        }
                        Divider()
                        Text("Zoom speed").font(.callout)
                        Slider(value: $model.zoomSensitivity, in: 0.25...3).accessibilityLabel("Gesture zoom speed")
                    case .back:
                        actionPicker($model.backAction)
                    case .forward:
                        actionPicker($model.forwardAction)
                    case .middle:
                        directionRow("Current action", action: "Middle Click", symbol: "computermouse")
                    case .mode:
                        directionRow("Current action", action: "Toggle wheel mode", symbol: "arrow.triangle.2.circlepath")
                        Button("Wheel settings…") { section = .pointer }
                    case .thumbwheel:
                        directionRow("Current action", action: "Horizontal scrolling", symbol: "arrow.left.and.right")
                    }
                    Spacer(minLength: 20)
                    if !model.inputStatus.isEmpty {
                        Text(model.inputStatus).font(.caption).foregroundStyle(.red)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 300).background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var mouseCanvas: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let imageHeight = min(h - 62, 540)
            let imageWidth = imageHeight * 636 / 1024
            let frame = CGRect(x: (w - imageWidth) / 2, y: (h - imageHeight) / 2, width: imageWidth, height: imageHeight)
            ZStack(alignment: .topLeading) {
                if let url = Bundle.main.url(forResource: "MXMaster3", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                        .accessibilityHidden(true)
                }
                Canvas { context, _ in
                    for control in MouseControl.allCases {
                        let p = CGPoint(x: frame.minX + frame.width * control.point.x, y: frame.minY + frame.height * control.point.y)
                        let edge = CGPoint(x: control.isLeft ? 153 : w - 153, y: h * control.labelY)
                        var path = Path()
                        path.move(to: edge)
                        path.addLine(to: CGPoint(x: edge.x + (control.isLeft ? 14 : -14), y: p.y))
                        path.addLine(to: p)
                        context.stroke(path, with: .color(control == selected ? .accentColor : .secondary.opacity(0.3)), lineWidth: control == selected ? 1.5 : 1)
                    }
                }.allowsHitTesting(false)
                ForEach(MouseControl.allCases) { control in
                    let p = CGPoint(x: frame.minX + frame.width * control.point.x, y: frame.minY + frame.height * control.point.y)
                    Button { selected = control } label: {
                        Circle().fill(control == selected ? Color.accentColor : Color.black.opacity(0.65))
                            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                            .frame(width: 12, height: 12).frame(width: 36, height: 36)
                    }.buttonStyle(.plain).position(p).accessibilityLabel(control.rawValue)
                    Button { selected = control } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(control.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
                            HStack(spacing: 5) {
                                Text(summary(control)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            }
                        }.padding(10).frame(width: 138, alignment: .leading)
                            .background(control == selected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(control == selected ? Color.accentColor : Color.secondary.opacity(0.2)))
                    }.buttonStyle(.plain).position(x: control.isLeft ? 84 : w - 84, y: h * control.labelY)
                }
            }
        }
    }

    private func summary(_ control: MouseControl) -> String {
        switch control {
        case .gesture: return "Zoom gestures"
        case .forward: return model.forwardAction.title
        case .back: return model.backAction.title
        case .middle: return "Middle Click"
        case .mode: return "Wheel mode"
        case .thumbwheel: return "Scroll left / right"
        }
    }

    private func directionRow(_ label: String, action: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 20).font(.system(size: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 14, weight: .medium))
                Text(action).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func actionPicker(_ action: Binding<ButtonAction>) -> some View {
        Picker("Current action", selection: action) {
            ForEach(ButtonAction.allCases) { item in Label(item.title, systemImage: item.symbol).tag(item) }
        }.pickerStyle(.menu)
    }

    private var pointerWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Pointer").font(.title2.weight(.semibold))
                card("Sensitivity") {
                    HStack { Text("DPI"); Spacer(); Text("\(Int(model.dpi))").monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: $model.dpi,
                           in: Double(model.mouse?.minDPI ?? 200)...Double(max(model.mouse?.maxDPI ?? 4000, 201)),
                           step: Double(max(model.mouse?.dpiStep ?? 50, 1)),
                           onEditingChanged: { model.editingDPI = $0; if !$0 { model.applyDPI() } })
                        .accessibilityLabel("Pointer sensitivity")
                }.disabled(!model.canWriteSettings || model.mouse?.dpi == nil)
                card("SmartShift") {
                    Toggle("SmartShift", isOn: Binding(get: { model.smartShift }, set: { model.smartShift = $0; model.applySmartShift() }))
                    if model.smartShift {
                        HStack { Text("Sensitivity"); Spacer(); Text("\(Int(model.shiftThreshold))").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $model.shiftThreshold, in: 1...254, step: 1,
                               onEditingChanged: { model.editingThreshold = $0; if !$0 { model.applySmartShift() } })
                            .accessibilityLabel("SmartShift threshold")
                        HStack { Text("Lighter flick"); Spacer(); Text("Stronger flick") }.font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Wheel mode"); Spacer()
                            Button("Ratchet") { model.setWheelMode(freeSpin: false) }
                            Button("Free spin") { model.setWheelMode(freeSpin: true) }
                        }
                    }
                }.disabled(!model.canWriteSettings || model.mouse?.smartShiftEnabled == nil)
                card("Thumb wheel") { LabeledContent("Current action", value: "Scroll left / right") }
                status
            }.padding(32).frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(workspaceBackground)
    }

    private var deviceWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Device").font(.title2.weight(.semibold))
                card("Access") {
                    if let conflict = model.conflict { LabeledContent("Mouse access", value: "Quit \(conflict)") }
                    HStack {
                        Text("Accessibility"); Spacer()
                        if model.accessibility { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        else { Button("Allow…", action: model.requestAccessibility) }
                    }
                    HStack {
                        Text("Input Monitoring"); Spacer()
                        if model.inputMonitoring { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        else { Button("Allow…", action: model.requestInputMonitoring) }
                    }
                    if !model.inputMonitoring { Button("Restart after granting access", action: model.restart) }
                }
                card("General") {
                    Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                }
                if let error = model.serviceError { Text(error).foregroundStyle(.red).font(.caption) }
                status
            }.padding(32).frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(workspaceBackground)
    }

    private var workspaceBackground: some View {
        Color(nsColor: .controlBackgroundColor).overlay(Color.primary.opacity(0.035))
    }

    private var status: some View {
        Group {
            if let message = model.mouse?.status, !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
    }
}
