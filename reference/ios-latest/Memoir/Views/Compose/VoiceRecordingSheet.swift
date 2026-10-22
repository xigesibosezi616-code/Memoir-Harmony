import SwiftUI

struct VoiceRecordingSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = AudioRecorderManager()
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?
    @State private var isPulsing = false
    let onInsert: (String) -> Void  // 回调返回保存后的相对路径

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 24) {
            Spacer()

            // 标题
            Text("录音")
                .font(theme.headingFont)
                .foregroundStyle(theme.textPrimary)

            // 录音按钮
            ZStack {
                if recorder.isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.5)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 88, height: 88)
                        .scaleEffect(isPulsing ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.1), value: isPulsing)
                }

                Circle()
                    .fill(recorder.isRecording ? Color.red : theme.accent)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Group {
                            if recorder.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 20, height: 20)
                            } else if recorder.recordedURL != nil {
                                // 已有录音，显示播放/暂停
                                Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                            } else {
                                // 未录音，显示红色小圆点
                                Circle()
                                    .fill(.white)
                                    .frame(width: 20, height: 20)
                            }
                        }
                    )
                    .onTapGesture {
                        if recorder.isRecording {
                            stopRecording()
                        } else if recorder.recordedURL != nil {
                            // 已录完，点击播放/暂停
                            if recorder.isPlaying {
                                recorder.stopPlayback()
                            } else {
                                recorder.startPlayback()
                            }
                        } else {
                            startRecording()
                        }
                    }
            }

            // 计时器
            Text(formatTime(elapsedSeconds))
                .font(theme.headingFont)
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()

            // 进度条（录音中显示）
            if recorder.isRecording {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.border)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: geo.size.width * min(Double(elapsedSeconds) / AudioRecorderManager.maxDuration, 1.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 40)

                    Text("最长 3 分钟")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }

            // 播放进度条（回放时显示）
            if !recorder.isRecording && recorder.recordedURL != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.border)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.accent)
                            .frame(width: geo.size.width * recorder.playbackProgress, height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 40)
            }

            // 状态文字
            Text(statusText)
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)

            if let error = recorder.errorMessage {
                Text(error)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.destructive)
            }

            Spacer()

            // 底部按钮
            HStack(spacing: 16) {
                if recorder.recordedURL != nil && !recorder.isRecording {
                    // 录完了：重录 + 插入
                    Button("重录") {
                        recorder.reset()
                        elapsedSeconds = 0
                    }
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button("插入") {
                        recorder.stopPlayback()
                        if let path = recorder.saveRecording() {
                            onInsert(path)
                        }
                        dismiss()
                    }
                    .font(theme.bodyFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // 未录或录制中：取消
                    Button("取消") {
                        recorder.reset()
                        dismiss()
                    }
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(.regularMaterial)
        .presentationDetents([.medium, .large])
        .onDisappear { recorder.reset() }
    }

    private var statusText: LocalizedStringKey {
        if recorder.isRecording {
            return "正在录音..."
        } else if recorder.recordedURL != nil {
            if recorder.isPlaying {
                return "播放中"
            }
            return "录音完成，可试听或插入"
        }
        return "点击开始录音"
    }

    private func startRecording() {
        elapsedSeconds = 0
        isPulsing = true
        recorder.startRecording()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
            if elapsedSeconds >= Int(AudioRecorderManager.maxDuration) {
                stopRecording()
            }
        }
    }

    private func stopRecording() {
        isPulsing = false
        timer?.invalidate()
        timer = nil
        recorder.stopRecording()
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
