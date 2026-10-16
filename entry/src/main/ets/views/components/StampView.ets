/**
 * 心情印章（10_BUILD_MANUAL.md 2.3 和纸版式）。对应 iOS
 * `Views/Components/StampView.swift`：56 圆环 + 竖排心情字。
 *
 * 显示条件在调用方（R-ENTRY-16）：中文界面 + 预设心情 + 显示名 ≤ 2 字；
 * 本组件只管画。
 */
@Component
export struct StampView {
  /** 心情显示名（已本地化，如「平静」），逐字竖排 */
  moodName: string = '';

  build() {
    Stack() {
      Circle({ width: 56, height: 56 })
        .fillOpacity(0)
        .stroke('#B8AD9C')
        .strokeWidth(2)
      Column({ space: 1 }) {
        ForEach(this.moodName.split(''), (char: string, index: number) => {
          Text(char)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#6B5E4A')
        }, (char: string, index: number): string => `${char}_${index}`)
      }
    }
  }
}
