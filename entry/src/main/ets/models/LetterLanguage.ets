/**
 * 回信语言识别（10_BUILD_MANUAL.md 5.5；R-LETTERLANG-01~07）。
 * 对应 iOS `Environment/LetterLanguage.swift`。
 *
 * 像真的笔友：日记用什么语言写，回信就用什么语言回，繁简也跟着日记。
 * 识别在本机做，不额外上传任何东西；认不出（太短 / 混写 / 不支持的语言）
 * 退回尺素的应用语言，App 语言不在七种里 → `en`（R-LETTERLANG-07）。
 *
 * 平台没有 NLLanguageRecognizer：先按**文字系统**数票分大类（与 iOS 完全一致，
 * 防整段丢识别器偏拉丁），细分按任务卡预案用启发式——
 * - 简繁：简体专用字 / 繁体专用字表数票（SIMP_ONLY 与 TRAD_ONLY 同序对照），
 *   两边写法一样的字分不出来 → 交给 App 语言（iOS 同款兜底）
 * - en/fr/es：三语高频虚词表 + 重音字符（ñ/á/í/ó/ú/ü → es；ç/è/à/ù/â/ê/î/ô/û/œ → fr；
 *   é 两边都用不投票）
 * - 置信度比较用整数（best × 10 ≥ total × 6），避免 0.6 浮点误差
 */
export const SIMP_ONLY = '们这说记过么对会时里后发见听风龙爱关开门问让双书长车马鸟鱼贝页汉语读写体达标经现层确认训优丝继约钱铁银错钟头买卖饭馆肠东练纸绿线责备虑务创寻库庙压币态墙够蓝红结给绝终传伟仅从众伤决净办动医单华协历县参变号叶员响团园围国图圆场坏块坚声处复独献环电画离种积称稳笔简类紧纯纳纷组细织绍绕绘统绪维编网罗罚义习联肤胆脑艺节药营补装观规觉览计讨讲许论设访证评识诉词试诗诚话询该详误请课谈谐谓谢负财贴贵费贺资赛赞赠迁运还进远连迟适选遗钢锁锅键闪闲间闻阅队阳阴陈险随隐难雾韩飞饮饱饼驱验麦齿龟个乐乡乱争两严丰丽举万无与专业机权来极树桥梦检楼欢战担损换据数断晓显暂惊惯愿虽职胜艰荐触谁调较轮软轻输边铃铜军农为吗气热凉厅汤视议领导项报划学师烧妈频郁应儿';

/** 繁体专用字。与 SIMP_ONLY 同序对照：第 i 个字互为简繁异写 */
export const TRAD_ONLY = '們這說記過麼對會時裡後發見聽風龍愛關開門問讓雙書長車馬鳥魚貝頁漢語讀寫體達標經現層確認訓優絲繼約錢鐵銀錯鐘頭買賣飯館腸東練紙綠線責備慮務創尋庫廟壓幣態牆夠藍紅結給絕終傳偉僅從眾傷決淨辦動醫單華協歷縣參變號葉員響團園圍國圖圓場壞塊堅聲處復獨獻環電畫離種積稱穩筆簡類緊純納紛組細織紹繞繪統緒維編網羅罰義習聯膚膽腦藝節藥營補裝觀規覺覽計討講許論設訪證評識訴詞試詩誠話詢該詳誤請課談諧謂謝負財貼貴費賀資賽贊贈遷運還進遠連遲適選遺鋼鎖鍋鍵閃閒間聞閱隊陽陰陳險隨隱難霧韓飛飲飽餅驅驗麥齒龜個樂鄉亂爭兩嚴豐麗舉萬無與專業機權來極樹橋夢檢樓歡戰擔損換據數斷曉顯暫驚慣願雖職勝艱薦觸誰調較輪軟輕輸邊鈴銅軍農為嗎氣熱涼廳湯視議領導項報劃學師燒媽頻鬱應兒';

/** 英语高频虚词（lowercase 精确匹配） */
const EN_WORDS: string[] = ['the', 'a', 'an', 'and', 'of', 'to', 'in', 'is', 'it', 'you',
  'that', 'was', 'for', 'are', 'with', 'this', 'have', 'from', 'i', 'he', 'she', 'they', 'we',
  'my', 'me', 'him', 'her', 'them', 'at', 'on', 'or', 'as', 'be', 'do', 'not', 'no', 'so',
  'if', 'but', 'about', 'there', 'here', 'what', 'when', 'why', 'how', 'all', 'can', 'will',
  'has', 'had', 'been', 'were', 'our', 'your', 'their', 'its', 'out', 'up', 'down', 'just',
  'than', 'then', 'because', 'while', 'very', 'too', 'also', 'get', 'got', 'would', 'should',
  'could', 'did', 'does', 'am', 'going'];

/** 法语高频虚词（与西语同形的 de/la/que… 两边各计一票，如实分票） */
const FR_WORDS: string[] = ['le', 'la', 'les', 'un', 'une', 'des', 'du', 'de', 'et', 'est',
  'en', 'je', 'tu', 'il', 'elle', 'nous', 'vous', 'ils', 'elles', 'on', 'que', 'qui', 'mais',
  'ou', 'donc', 'pas', 'plus', 'très', 'tout', 'tous', 'toute', 'toutes', 'avec', 'sans',
  'pour', 'par', 'sur', 'sous', 'dans', 'entre', 'vers', 'chez', 'mon', 'ma', 'mes', 'ton',
  'ta', 'tes', 'son', 'sa', 'ses', 'notre', 'votre', 'leur', 'ne', 'au', 'aux', 'où', 'été',
  'être', 'avait', 'était', 'suis', 'es', 'ici', 'oui', 'encore', 'toujours', 'si'];

/** 西语高频虚词（重音词 más/está/qué… 靠重音字符再加分） */
const ES_WORDS: string[] = ['el', 'los', 'las', 'una', 'unos', 'unas', 'del', 'de', 'y', 'es',
  'en', 'que', 'no', 'se', 'por', 'con', 'para', 'pero', 'más', 'muy', 'yo', 'tú', 'él',
  'ella', 'nosotros', 'vosotros', 'ellos', 'ellas', 'usted', 'ustedes', 'mi', 'mis', 'tus',
  'sus', 'nuestro', 'vuestro', 'me', 'te', 'le', 'lo', 'aquí', 'allí', 'como', 'cuando',
  'donde', 'porque', 'si', 'también', 'este', 'esta', 'estos', 'estas', 'ese', 'esa', 'esos',
  'esas', 'hay', 'era', 'fue', 'está', 'están', 'tiene', 'tengo', 'al', 'sin', 'sobre',
  'hasta', 'desde', 'tan', 'tanto', 'otro', 'otros', 'qué', 'cómo', 'sí', 'mí', 'os', 'vos'];

export class LetterLanguage {
  /** 七种语言 id，与 LanguageManager.SUPPORTED_IDS 一致，也是发给后端的值 */
  static readonly SUPPORTED: string[] = ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'fr', 'es'];

  /** 少于 12 个字不识别：一两句话的日记，识别结果不可信（R-LETTERLANG-02） */
  static readonly MINIMUM_LENGTH = 12;

  /** 这封信该用的语言代码。`texts` 是这次寄出去的日记（标题 + 正文），
   *  认不出退 App 语言；App 语言不在七种里 → en（R-LETTERLANG-07） */
  static forLetter(texts: string[], appLanguage: string): string {
    const detected = LetterLanguage.detect(texts.join('\n'));
    if (detected !== null) {
      return detected;
    }
    return LetterLanguage.SUPPORTED.indexOf(appLanguage) >= 0 ? appLanguage : 'en';
  }

  /** 识别一段文字的语言；认不出返回 null。先按文字系统分大类，再在大类里细分 */
  static detect(text: string): string | null {
    const trimmed = text.trim();
    if (trimmed.length < LetterLanguage.MINIMUM_LENGTH) {
      return null;
    }
    let han = 0;
    let kana = 0;
    let hangul = 0;
    for (let i = 0; i < trimmed.length; i++) {
      const code = trimmed.charCodeAt(i);
      if (LetterLanguage.isHanCode(code)) {
        han += 1;
      } else if (code >= 0x3040 && code <= 0x30FF) {
        kana += 1;
      } else if (LetterLanguage.isHangulCode(code)) {
        hangul += 1;
      }
    }
    const words = LetterLanguage.latinWordsOf(trimmed);

    // 韩文字母不会和别的语言混淆（R-LETTERLANG-04）
    if (hangul > 0 && hangul >= han + kana && hangul >= words.length) {
      return 'ko';
    }
    if (han + kana > 0 && han + kana >= words.length) {
      // 有假名就是日文——中文里不会出现假名，日文里几乎每句都有（R-LETTERLANG-05）
      if (kana >= Math.max(2, Math.floor((han + kana) / 10))) {
        return 'ja';
      }
      // 简繁只看汉字本身：夹着的英文单词会把识别带偏
      return LetterLanguage.detectHan(trimmed);
    }
    // 否则在 en/fr/es 里识别（R-LETTERLANG-06）
    return LetterLanguage.detectLatin(words);
  }

  /** 简繁细分：专用字表数票；两边写法一样的字分不出来 → null（交给 App 语言） */
  private static detectHan(text: string): string | null {
    let simp = 0;
    let trad = 0;
    for (let i = 0; i < text.length; i++) {
      if (!LetterLanguage.isHanCode(text.charCodeAt(i))) {
        continue;
      }
      const ch = text.charAt(i);
      if (SIMP_ONLY.indexOf(ch) >= 0) {
        simp += 1;
      } else if (TRAD_ONLY.indexOf(ch) >= 0) {
        trad += 1;
      }
    }
    const total = simp + trad;
    if (total === 0) {
      return null;
    }
    const best = Math.max(simp, trad);
    if (best * 10 < total * LetterLanguage.CONFIDENCE_NUMERATOR) {
      return null;
    }
    return simp >= trad ? 'zh-Hans' : 'zh-Hant';
  }

  /** en/fr/es 细分：虚词 + 重音字符数票，置信不足 → null */
  private static detectLatin(words: string[]): string | null {
    let en = 0;
    let fr = 0;
    let es = 0;
    for (const raw of words) {
      const word = raw.toLowerCase();
      if (EN_WORDS.indexOf(word) >= 0) {
        en += 1;
      }
      if (FR_WORDS.indexOf(word) >= 0) {
        fr += 1;
      }
      if (ES_WORDS.indexOf(word) >= 0) {
        es += 1;
      }
      for (let i = 0; i < word.length; i++) {
        const ch = word.charAt(i);
        if (ch === 'ñ') {
          es += 3;
        } else if (ch === 'á' || ch === 'í' || ch === 'ó' || ch === 'ú') {
          es += 2;
        } else if (ch === 'ü') {
          es += 1;
        } else if (ch === 'ç' || ch === 'è' || ch === 'à' || ch === 'ù' || ch === 'â' ||
          ch === 'ê' || ch === 'î' || ch === 'ô' || ch === 'û' || ch === 'œ') {
          fr += 2;
        }
        // é：法西都用，不投票
      }
    }
    const total = en + fr + es;
    if (total === 0) {
      return null;
    }
    const best = Math.max(en, fr, es);
    if (best * 10 < total * LetterLanguage.CONFIDENCE_NUMERATOR) {
      return null;
    }
    if (best === en) {
      return 'en';
    }
    if (best === fr) {
      return 'fr';
    }
    return 'es';
  }

  /** 拉丁字母组成的词（含 é ñ 这类带音调的），词里所有字符 < 0x250 才算 */
  private static latinWordsOf(text: string): string[] {
    const words: string[] = [];
    let current = '';
    let tainted = false;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (LetterLanguage.isWordLetterCode(code)) {
        current += text.charAt(i);
        if (code >= 0x250) {
          tainted = true;
        }
      } else {
        if (current.length > 0 && !tainted) {
          words.push(current);
        }
        current = '';
        tainted = false;
      }
    }
    if (current.length > 0 && !tainted) {
      words.push(current);
    }
    return words;
  }

  /** 置信度 0.6 的整数分子（best × 10 ≥ total × 6，避开浮点误差） */
  private static readonly CONFIDENCE_NUMERATOR = 6;

  private static isHanCode(code: number): boolean {
    return (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0xF900 && code <= 0xFAFF);
  }

  private static isHangulCode(code: number): boolean {
    return (code >= 0xAC00 && code <= 0xD7AF) || (code >= 0x1100 && code <= 0x11FF) ||
      (code >= 0x3130 && code <= 0x318F);
  }

  /** 是不是「字母」（断词用）：拉丁 / 希腊 / 西里尔 / 希伯来 / 阿拉伯 / 假名 / 汉字 / 韩文…
   *  拉丁字母组成的词全 < 0x250，其余文字系统的字母会把词「污染」掉不算拉丁词 */
  private static isWordLetterCode(code: number): boolean {
    if (code >= 0x41 && code <= 0x5A) {
      return true;
    }
    if (code >= 0x61 && code <= 0x7A) {
      return true;
    }
    if (code === 0xAA || code === 0xB5 || code === 0xBA) {
      return true;
    }
    if (code >= 0xC0 && code <= 0x24F && code !== 0xD7 && code !== 0xF7) {
      return true;
    }
    if (code >= 0x370 && code <= 0x52F) {
      return true;
    }
    if (code >= 0x531 && code <= 0x58A) {
      return true;
    }
    if (code >= 0x5D0 && code <= 0x5EA) {
      return true;
    }
    if (code >= 0x620 && code <= 0x64A) {
      return true;
    }
    if (code >= 0x1100 && code <= 0x11FF) {
      return true;
    }
    if (code >= 0x3040 && code <= 0x30FF) {
      return true;
    }
    if (code >= 0x3105 && code <= 0x312F) {
      return true;
    }
    if (code >= 0x3130 && code <= 0x318F) {
      return true;
    }
    if (code >= 0x31F0 && code <= 0x31FF) {
      return true;
    }
    if (code >= 0x3400 && code <= 0x4DBF) {
      return true;
    }
    if (code >= 0x4E00 && code <= 0x9FFF) {
      return true;
    }
    if (code >= 0xA000 && code <= 0xA48F) {
      return true;
    }
    if (code >= 0xAC00 && code <= 0xD7AF) {
      return true;
    }
    if (code >= 0xF900 && code <= 0xFAFF) {
      return true;
    }
    if (code >= 0xFF21 && code <= 0xFF3A) {
      return true;
    }
    if (code >= 0xFF41 && code <= 0xFF5A) {
      return true;
    }
    if (code >= 0xFF66 && code <= 0xFF9D) {
      return true;
    }
    return false;
  }
}
