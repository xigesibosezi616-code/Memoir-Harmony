import Foundation
import AVFoundation

@Observable
class AudioRecorderManager: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var recordedURL: URL?
    var errorMessage: String?
    var isPlaying = false
    var playbackProgress: Double = 0
    var recordingDuration: TimeInterval = 0

    static let maxDuration: TimeInterval = 180  // 3 分钟

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?

    func startRecording() {
        guard !isRecording else { return }
        errorMessage = nil
        recordedURL = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "无法启动音频会话"
            return
        }

        let fileName = "recording_\(UUID().uuidString).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: Self.maxDuration)
            audioRecorder = recorder
            isRecording = true
        } catch {
            errorMessage = "无法开始录音"
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        recordedURL = audioRecorder?.url
        recordingDuration = audioRecorder?.currentTime ?? 0
        isRecording = false
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            recordedURL = recorder.url
            // 获取实际时长
            if let player = try? AVAudioPlayer(contentsOf: recorder.url) {
                recordingDuration = player.duration
            }
        }
        isRecording = false
    }

    func startPlayback() {
        guard let url = recordedURL else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            audioPlayer = player
            isPlaying = true
            playbackProgress = 0
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let player = self.audioPlayer else { return }
                self.playbackProgress = player.currentTime / player.duration
            }
        } catch {
            errorMessage = "无法播放录音"
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackProgress = 0
    }

    func reset() {
        stopRecording()
        stopPlayback()
        recordedURL = nil
        recordingDuration = 0
        errorMessage = nil
    }

    /// 将录音保存到 Documents/audio/ 目录，返回相对路径
    func saveRecording() -> String? {
        guard let sourceURL = recordedURL else { return nil }
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioDir = docsDir.appendingPathComponent("audio", isDirectory: true)

        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }

        let fileName = "audio_\(UUID().uuidString)_\(Int(Date.now.timeIntervalSince1970)).m4a"
        let destURL = audioDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return "audio/\(fileName)"
        } catch {
            return nil
        }
    }

    /// 从相对路径加载音频并播放
    static func playAudio(from relativePath: String) -> AVAudioPlayer? {
        // 播放前**自己声明**要的 category，不依赖"当前恰好是什么"。
        //
        // 起因：开场视频为了不打断用户的音乐，会把 category 设成 `.ambient`（可混音）。
        // 它刻意**不还原**（还原那一步会在进主页时把别人的音乐掐掉且不恢复，
        // 见 `SplashVideoPlayerView.dismantleUIView` 的注释）。
        // 所以这里必须自己设回独占语义 —— 用户点开一段录音就是想听它，
        // 而不是让它和背景音乐混在一起。
        //
        // 用 `.soloAmbient` 而不是 `.playback`：与改动前的默认行为一致
        // （静音开关依然生效，不做"忽略静音键"这种越权的事）。
        try? AVAudioSession.sharedInstance().setCategory(.soloAmbient)

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docsDir.appendingPathComponent(relativePath)
        return try? AVAudioPlayer(contentsOf: url)
    }

    /// 获取音频时长
    static func duration(of relativePath: String) -> TimeInterval {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docsDir.appendingPathComponent(relativePath)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return player.duration
    }
}

extension AudioRecorderManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackProgress = 0
    }
}
