import Foundation
import NaturalLanguage

/// 笔友回信用什么语言写 —— **跟着日记写的语言走**（2026-10-09 产品定）。
///
/// 像真的笔友：你用什么语言写，它就用什么语言回，繁简也跟着日记。
/// 识别在手机上做（`NLLanguageRecognizer`），不额外上传任何东西；
/// 识别不出来（太短、混写、不是我们支持的语言）时，退回尺素的应用语言。
///
/// > 之前取的是 `Locale.current` —— 那是**系统**语言，不是尺素自己的语言设置。
/// > 系统英文、尺素繁中、日记写中文的用户，收到的是英文信（2026-10-09 真机）。
/// > 而且只分「中文 / 其他」两档：繁中当简中，日韩法西一律英文。
enum LetterLanguage {
    /// 和 `LanguageManager.supportedLanguages` 的 id 一致，也是发给后端的值
    static let supported: [String] = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "es"]

    /// 少于这么多字就不识别了：一两句话的日记，识别结果不可信
    private static let minimumLength = 12
    /// 识别结果的置信度低于它，就当没认出来
    private static let minimumConfidence = 0.6

    private static let nlToCode: [NLLanguage: String] = [
        .simplifiedChinese: "zh-Hans",
        .traditionalChinese: "zh-Hant",
        .english: "en",
        .japanese: "ja",
        .korean: "ko",
        .french: "fr",
        .spanish: "es",
    ]

    /// 这封信该用的语言代码。`texts` 是这次寄出去的日记（标题 + 正文）
    static func forLetter(texts: [String]) -> String {
        detect(in: texts.joined(separator: "\n")) ?? appLanguage
    }

    /// 识别一段文字的语言；认不出来返回 nil。
    ///
    /// 先按**文字系统**分大类，再交给 `NLLanguageRecognizer` 在大类里细分 ——
    /// 直接整段丢给识别器的话，它偏向拉丁字母：「今天 meeting 好多，deadline 又提前了，真的 so tired」
    /// 会被认成英文（2026-10-09 实测）。一个汉字大致抵一个英文单词，按这个比例数谁占多数。
    static func detect(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength else { return nil }

        var han = 0, kana = 0, hangul = 0
        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF: han += 1
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            default: break
            }
        }
        // 拉丁字母组成的词（含 é ñ 这类带音调的）
        let latinWords = trimmed
            .split { !$0.isLetter }
            .filter { word in word.unicodeScalars.allSatisfy { $0.value < 0x250 } }
            .count

        if hangul > 0, hangul >= han + kana, hangul >= latinWords {
            return "ko"   // 韩文字母不会和别的语言混淆
        }
        if han + kana > 0, han + kana >= latinWords {
            // 有假名就是日文 —— 中文里不会出现假名，日文里几乎每句都有
            if kana >= max(2, (han + kana) / 10) { return "ja" }
            // 简繁只看汉字本身：夹着的英文单词会把识别器带偏（实测「中英混写」置信度掉到一半）。
            // 剔掉之后仍分不出来（两边写法一样的字），交给应用语言
            let hanOnly = String(String.UnicodeScalarView(trimmed.unicodeScalars.filter {
                (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
                    || (0xF900...0xFAFF).contains($0.value)
            }))
            return recognize(hanOnly, among: [.simplifiedChinese, .traditionalChinese])
        }
        return recognize(trimmed, among: [.english, .french, .spanish])
    }

    private static func recognize(_ text: String, among candidates: [NLLanguage]) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence else { return nil }
        return nlToCode[language]
    }

    /// 尺素的应用语言（设置里选的那个，不是系统语言）
    private static var appLanguage: String {
        let stored = UserDefaults.standard.string(forKey: LanguageManager.storageKey) ?? ""
        return supported.contains(stored) ? stored : "en"
    }
}
