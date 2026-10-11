import AVFoundation

/// Records from the AU05 microphone (selected by name; system default input untouched).
public final class VoiceRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    public var settings = VoiceSettings()
    public var onStateChange: ((Bool) -> Void)?
    public var log: ((String) -> Void)?

    private var session: AVCaptureSession?
    private var output: AVCaptureAudioFileOutput?
    private var wantRecording = false

    public var isRecording: Bool { output?.isRecording ?? false }

    public func toggle() { isRecording || wantRecording ? stop() : start() }

    public func start() {
        guard !wantRecording else { return }
        wantRecording = true
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok else { self.wantRecording = false; self.log?("Microphone permission denied."); return }
                if self.wantRecording { self.begin() }
            }
        }
    }

    public func stop() {
        wantRecording = false
        if let out = output, out.isRecording { out.stopRecording() } else { teardown() }
    }

    public static func inputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    private func begin() {
        guard let device = Self.inputDevices().first(where: { $0.localizedName.localizedCaseInsensitiveContains(settings.deviceName) }) else {
            wantRecording = false
            log?("Audio input '\(settings.deviceName)' not found.")
            return
        }
        do {
            let s = AVCaptureSession()
            let input = try AVCaptureDeviceInput(device: device)
            guard s.canAddInput(input) else { throw NSError(domain: "vibekey", code: 1) }
            s.addInput(input)
            let out = AVCaptureAudioFileOutput()
            // 16 kHz mono 16-bit PCM: what whisper.cpp and most STT tools expect.
            out.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            guard s.canAddOutput(out) else { throw NSError(domain: "vibekey", code: 2) }
            s.addOutput(out)
            s.startRunning()
            session = s
            output = out
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd-HHmmss"
            let url = saveDir.appendingPathComponent("vibekey-\(fmt.string(from: Date())).wav")
            out.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)
            onStateChange?(true)
        } catch {
            log?("Could not start recording: \(error)")
            teardown()
        }
    }

    private var saveDir: URL {
        if settings.saveDirectory.isEmpty { return Paths.recordingsDir }
        let u = URL(fileURLWithPath: (settings.saveDirectory as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func teardown() {
        session?.stopRunning()
        session = nil
        output = nil
        onStateChange?(false)
    }

    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                           from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.teardown()
            if let error { self.log?("Recording error: \(error.localizedDescription)") }
            self.log?("Saved \(url.path)")
            self.postProcess(url)
        }
    }

    private func postProcess(_ url: URL) {
        let s = settings
        guard !s.command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let cmd = s.command.replacingOccurrences(of: "{file}", with: Shell.quote(url.path))
        DispatchQueue.global(qos: .userInitiated).async {
            let (status, out) = Shell.capture(cmd)
            DispatchQueue.main.async {
                if status != 0 { self.log?("Voice command exited \(status)"); return }
                let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.typeResult, !text.isEmpty { KeySender.type(text) }
                if s.deleteAfterCommand { try? FileManager.default.removeItem(at: url) }
            }
        }
    }
}
