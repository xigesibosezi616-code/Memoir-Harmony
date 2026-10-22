import SwiftUI
import AVFoundation

struct AudioPlayerCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let audioURL: String
    var onDelete: (() -> Void)?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 12) {
            // 播放/暂停按钮
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(theme.accent)
                    .clipShape(Circle())
            }

            // 进度条 + 时长
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.border)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.accent)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)

                Text(formatDuration(duration))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .monospacedDigit()
            }

            // 删除按钮
            if let onDelete {
                Button {
                    stopPlayback()
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .padding(12)
        .background(theme.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border, lineWidth: 0.5)
        )
        .onAppear { loadDuration() }
        .onDisappear { stopPlayback() }
    }

    private func loadDuration() {
        duration = AudioRecorderManager.duration(of: audioURL)
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let p = AudioRecorderManager.playAudio(from: audioURL) else { return }
        player = p
        p.play()
        isPlaying = true
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player, player.isPlaying else {
                stopPlayback()
                return
            }
            progress = player.currentTime / player.duration
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        timer?.invalidate()
        timer = nil
        progress = 0
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}
