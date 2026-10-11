import SwiftUI
import VibeKeyCore

struct CalibrationView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    private struct StepInfo {
        let title: String
        let detail: String
        var target: Control? = nil
        var symbol: String? = nil
    }

    private static func info(_ index: Int) -> StepInfo {
        guard index > 0, index <= Calibrator.steps.count else { return StepInfo(title: "", detail: "") }
        switch Calibrator.steps[index - 1].press {
        case .knobRight: return StepInfo(title: "Turn the knob right", detail: "One click clockwise is enough.", target: .knob, symbol: "arrow.clockwise")
        case .knobLeft: return StepInfo(title: "Turn the knob left", detail: "One click counter-clockwise.", target: .knob, symbol: "arrow.counterclockwise")
        case .knobPress: return StepInfo(title: "Press the knob", detail: "Push it down and let go.", target: .knob, symbol: "hand.point.down.fill")
        case .micPress: return StepInfo(title: "Press the Mic button", detail: "Press and release.", target: .mic)
        case .checkPress: return StepInfo(title: "Press the Confirm button", detail: "The ✓ button. Press and release.", target: .check)
        case .xPress: return StepInfo(title: "Press the Cancel button", detail: "The ✕ button. Press and release.", target: .x)
        default: return StepInfo(title: Calibrator.steps[index - 1].prompt, detail: "")
        }
    }

    /// 0 before starting, 1…n = steps, n+1 = finished.
    private var current: Int {
        switch state.calibration.phase {
        case .intro: return 0
        case .step(let i): return i
        case .done: return Calibrator.steps.count + 1
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            stage
                .frame(width: 236)
                .background(Theme.canvas)
            Hairline(vertical: true)
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Test & calibrate")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Press each control when asked to confirm it reaches Vibe Key. The result is saved as your control layout, which only matters if a firmware update ever reorders the controls.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state.calibration.phase == .done {
                    doneBody
                } else {
                    stepList
                }
                Spacer(minLength: 0)
                buttons
            }
            .padding(26)
        }
        .frame(width: 680, height: 480)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .tint(Theme.teal)
    }

    // MARK: Parts

    private var stage: some View {
        let info = current >= 1 && current <= Calibrator.steps.count ? Self.info(current) : nil
        return VStack(spacing: 0) {
            DeviceArt(target: info?.target, targetSymbol: info?.symbol, interactive: false)
                .scaleEffect(0.66)
                .frame(width: DeviceArt.width * 0.66, height: DeviceArt.height * 0.66)
                .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                Circle()
                    .fill(state.connected ? Theme.teal : Theme.tertiary)
                    .frame(width: 7, height: 7)
                Text(state.connected ? "AU05 connected" : "AU05 not connected")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.bottom, 18)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(1...Calibrator.steps.count, id: \.self) { i in
                stepRow(i)
            }
            if let note = state.calibration.notes.last {
                Label(note, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
                    .padding(.top, 6)
            }
            if state.calibration.phase == .intro && !state.connected {
                Label("Plug in your AU05 to start.", systemImage: "cable.connector")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .padding(.top, 8)
            }
        }
    }

    private func stepRow(_ i: Int) -> some View {
        let info = Self.info(i)
        let isDone = i < current
        let isCurrent = i == current
        let code = state.calibration.captured.first { $0.event == Calibrator.steps[i - 1].press }?.code
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.teal)
                } else if isCurrent {
                    Circle().fill(Theme.teal).frame(width: 8, height: 8)
                    Circle().strokeBorder(Theme.teal.opacity(0.45), lineWidth: 1.5).frame(width: 16, height: 16)
                } else {
                    Circle().strokeBorder(Theme.tertiary, lineWidth: 1.2).frame(width: 14, height: 14)
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.text : isDone ? Theme.secondary : Theme.tertiary)
                if isCurrent && !info.detail.isEmpty {
                    Text(info.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.teal)
                }
            }
            Spacer()
            if let code {
                Text(String(code.prefix(8)))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isCurrent ? Theme.teal.opacity(0.08) : .clear))
    }

    private var doneBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.teal)
            Text("All controls work")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(doneSummary)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
    }

    private var doneSummary: String {
        "All \(state.calibration.captured.count) controls reached Vibe Key and the layout is saved. Press any control and it lights up in the editor."
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            switch state.calibration.phase {
            case .intro:
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Start") { state.startCalibration() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!state.connected)
            case .step:
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            case .done:
                Button("Run Again") { state.startCalibration() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
