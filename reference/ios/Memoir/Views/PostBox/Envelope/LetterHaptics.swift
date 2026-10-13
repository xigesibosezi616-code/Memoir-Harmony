import AVFoundation
import CoreHaptics

/// 信件的手感：震动 + 声音放在同一个时钟上（声音是编排里的 audioCustom 事件）。拆信、投信共用。
///
/// - 声音走 `.ambient`：跟着静音键（静音时只有震动），也不打断用户在放的音乐
/// - 设备不支持 Core Haptics（iPad 等）时只放声音
///
/// ## 全 App 共用一台引擎
///
/// 🔴 **不要改回每个页面各自建引擎、离开时 stop()。**
/// 新页面的 onAppear 会跑在旧页面的 onDisappear **之前**：新引擎先建好，旧引擎随后 stop()
/// —— stop 会把两台引擎共用的音频会话一起停掉，新引擎的声音就没了（震动还在、播放也不报错）。
/// 而上一台若从没出过声，它 stop 时不碰会话，于是下一台又正常：表现成「单数有声、双数无声」
/// （2026-10-11 连拆两封实测，日志里 prepare(新) 在 stop(旧) 前面）。
/// 所以只建一台、谁也不主动 stop：最后一个用它的页面关掉后让它闲下来自己关（`isAutoShutdownEnabled`）。
/// 投信（邮筒页）和拆信（信封页）也是同一台 —— 从邮筒页点进信箱拆信，正是「新页面先出现」的情形
enum LetterHaptics {
    /// 一段编排。时间都从开始播放那一刻算起
    struct Pattern {
        var events: [CHHapticEvent]
        var curves: [CHHapticParameterCurve] = []
        /// 声音文件（`Resources/Sounds` 下的 wav，不带扩展名），从 0 秒开始放
        var sound: String?
        var volume: Float = 0.75
    }

    private static var engine: CHHapticEngine?
    /// 按名字缓存的播放器。引擎被系统重置后清空，下次播放时重建
    private static var players: [String: CHHapticAdvancedPatternPlayer] = [:]
    /// 没有 Taptic Engine 的设备只放声音
    private static var hapticsUnsupported = false
    private static var audioPlayers: [String: AVAudioPlayer] = [:]
    /// 开着的、要用手感的页面数。>0 时引擎不许闲下来自己关（拆信三下之间可能隔好几秒，关了下一下就慢半拍）
    private static var users = 0

    /// 页面出现时调：把引擎热起来，等到点下去再启动，第一下震动会慢半拍
    static func acquire() {
        users += 1
        // 每次都确认一遍：录音结束时会把会话改成 .soloAmbient（不混音），
        // 不改回来的话，之后的信件音效会打断用户在放的音乐
        useAmbientSession()
        setUpIfNeeded()
        engine?.isAutoShutdownEnabled = false
        try? engine?.start()
    }

    /// 页面离开时调。**不打断正在放的**，最后一个页面也走了就让引擎闲下来自己关
    static func release() {
        users = max(0, users - 1)
        if users == 0 { engine?.isAutoShutdownEnabled = true }
    }

    /// 先把编排和声音登记好，点下去时不用现做
    static func preload(_ name: String, pattern: () -> Pattern) {
        if hapticsUnsupported {
            if let sound = pattern().sound { _ = audioPlayer(sound) }
            return
        }
        guard let engine, players[name] == nil else { return }
        do {
            players[name] = try makePlayer(engine, pattern: pattern())
        } catch {
            log("登记失败 \(name)", error)
        }
    }

    /// 播一段（同名的只建一次播放器）
    static func play(_ name: String, pattern: () -> Pattern) {
        if hapticsUnsupported {
            guard let sound = pattern().sound, let player = audioPlayer(sound) else { return }
            player.volume = pattern().volume
            player.currentTime = 0
            player.play()
            return
        }
        guard let engine else { return }
        do {
            try engine.start()   // 被系统停过（打断、闲置自动关）的话重新起来；正在跑时什么也不做
            if players[name] == nil { players[name] = try makePlayer(engine, pattern: pattern()) }
            try players[name]?.start(atTime: CHHapticTimeImmediate)
        } catch {
            log("播放失败 \(name)", error)
        }
    }

    /// 只震不响的一小下，不缓存（「减弱动态效果」下的轻轻一顿、邮筒不收信时的一顿）
    static func tap(intensity: Float, sharpness: Float) {
        guard let engine else { return }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: [transient(0, intensity: intensity, sharpness: sharpness)], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            log("播放失败 tap", error)
        }
    }

    private static func setUpIfNeeded() {
        guard engine == nil, !hapticsUnsupported else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            hapticsUnsupported = true
            return
        }
        do {
            let engine = try CHHapticEngine(audioSession: .sharedInstance())
            engine.playsHapticsOnly = false
            // 被系统打断（来电、切后台）后重置：重新启动，登记过的声音和编排都作废，下次播放时重建
            engine.resetHandler = {
                Task { @MainActor in
                    try? LetterHaptics.engine?.start()
                    LetterHaptics.players = [:]
                }
            }
            engine.stoppedHandler = { reason in
                NSLog("ℹ️ [LetterHaptics] 震动引擎停止 reason=%ld", reason.rawValue)
            }
            try engine.start()
            self.engine = engine
        } catch {
            log("震动引擎启动失败", error)
            engine = nil
        }
    }

    private static func useAmbientSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .ambient else { return }
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } catch {
            log("音频会话设置失败", error)
        }
    }

    private static func makePlayer(_ engine: CHHapticEngine, pattern: Pattern) throws -> CHHapticAdvancedPatternPlayer {
        var events = pattern.events
        if let sound = pattern.sound, let url = soundURL(sound) {
            let resource = try engine.registerAudioResource(url, options: [:])
            events.append(CHHapticEvent(audioResourceID: resource,
                                        parameters: [CHHapticEventParameter(parameterID: .audioVolume, value: pattern.volume)],
                                        relativeTime: 0))
        }
        return try engine.makeAdvancedPlayer(with: CHHapticPattern(events: events, parameterCurves: pattern.curves))
    }

    private static func audioPlayer(_ sound: String) -> AVAudioPlayer? {
        if let player = audioPlayers[sound] { return player }
        guard let url = soundURL(sound) else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayers[sound] = player
            return player
        } catch {
            log("声音载入失败 \(sound)", error)
            return nil
        }
    }

    private static func soundURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav")
    }

    private static func log(_ what: String, _ error: any Error) {
        let ns = error as NSError
        NSLog("⚠️ [LetterHaptics] %@ domain=%@ code=%ld %@", what, ns.domain, ns.code, "\(error)")
    }

    // MARK: - 零件

    static func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    static func continuous(_ time: TimeInterval, duration: TimeInterval,
                           intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time, duration: duration)
    }

    /// 强度曲线（乘在持续震动的强度上）。points 的时间相对 `start`
    static func curve(start: TimeInterval, points: [(TimeInterval, Float)]) -> CHHapticParameterCurve {
        CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: points.map { CHHapticParameterCurve.ControlPoint(relativeTime: $0.0, value: $0.1) },
            relativeTime: start
        )
    }

    /// 动画用的是 smoothstep，速度曲线是中间高两头低的钟形 —— 震动强度跟着速度走。
    /// `floor`：两头也留一点，摸得到纸一直在动。一条曲线最多 16 个控制点
    static func bell(duration: TimeInterval, floor: Float, samples: Int) -> [(TimeInterval, Float)] {
        (0...samples).map { i in
            let u = Double(i) / Double(samples)
            return (u * duration, floor + (1 - floor) * Float(4 * u * (1 - u)))
        }
    }
}
