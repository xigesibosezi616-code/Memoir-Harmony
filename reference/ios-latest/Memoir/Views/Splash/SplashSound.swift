import AVFoundation

/// 开场写字的声音：笔尖在纸上「刷刷刷」，落句点「咚」（`Resources/Sounds/splash_write.wav`，
/// 由 `Scripts/make_splash_sound.py` 按 `HandwrittenMark.Script` 的时间表合成，从写第一笔那一刻开始放）。
///
/// 走 `.ambient`：跟着静音键（静音时就只有画面），也不打断用户在放的音乐 —— 同 `LetterHaptics`
@MainActor
enum SplashSound {
    private static var player: AVAudioPlayer?

    /// 先载好，写第一笔时直接响，不慢半拍
    static func prepare() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "splash_write", withExtension: "wav") else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .ambient {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.8
            player.prepareToPlay()
            self.player = player
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [SplashSound] 载入失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }

    static func play() {
        player?.play()
    }

    /// 开场提前退场（用户点了跳过）时，声音跟着淡掉，别在主界面上还响着
    static func fadeOut(_ duration: TimeInterval) {
        guard let player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: duration)
    }

    /// 开场结束后放掉播放器
    static func release() {
        player?.stop()
        player = nil
    }
}
