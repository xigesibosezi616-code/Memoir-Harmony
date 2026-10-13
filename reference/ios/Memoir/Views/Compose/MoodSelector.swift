import SwiftUI
import SwiftData

/// 写日记时选心情。**只读 —— 心情是产品预设的，用户只能选，不能新建/改名/改色。**
///
/// 2026-08-12 移除了这里的「+ 自建心情」按钮与 `CreateMoodSheet`，
/// 同时删掉了设置页的「心情管理」整页。理由是产品决策：
/// 心情是一套精心挑过的预设词表（12 个，各带图标与配色，且是**七种语言的翻译单元**），
/// 让用户自建会同时破坏三件事 —— 语言一致性（自建的没有译名）、
/// 视觉一致性（配色随手挑）、以及统计的可比性（每个人一套词表就没法横向看了）。
struct MoodSelector: View {
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \MoodTag.sortOrder) private var moodTags: [MoodTag]
    @Binding var selectedMoodName: String
    @Binding var selectedMoodColorHex: String?

    var body: some View {
        let theme = themeManager.current
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moodTags) { moodTag in
                    let isSelected = selectedMoodName == moodTag.name
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            selectedMoodName = moodTag.name
                            selectedMoodColorHex = moodTag.colorHex
                        }
                    } label: {
                        Text(moodTag.displayName)
                            .font(theme.captionFont)
                            .foregroundStyle(isSelected ? .white : theme.moodText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color(hex: moodTag.colorHex) : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color(hex: moodTag.colorHex) : theme.moodBorder, lineWidth: 0.5)
                            )
                            .scaleEffect(isSelected ? 1.05 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedMoodName)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
