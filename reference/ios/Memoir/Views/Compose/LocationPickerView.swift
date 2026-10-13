import SwiftUI
import MapKit

/// 这篇日记要记哪个地点。
enum PlaceChoice: Equatable {
    /// 用自动解析出来的（按设置里的精度档位）
    case auto
    /// 明确不记位置
    case none
    /// 用户从附近列表里挑的
    case manual(String)
}

/// 地点选择器 —— 微信式：顶部「不显示位置 / 当前位置」，下面是按距离排序的附近地点，可搜索。
///
/// 数据全部来自 **Apple 原生**：附近 POI 走 MapKit `MKLocalSearch`
/// （大陆地区 Apple 地图的数据源是高德，POI 覆盖够用），不依赖任何第三方 SDK 或 API key。
struct LocationPickerView: View {
    let coordinate: CLLocationCoordinate2D?
    /// 自动解析出的地名，显示在「当前位置」那行
    let autoName: String?
    let current: PlaceChoice
    let onSelect: (PlaceChoice) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            List {
                Section {
                    row(title: Text("不显示位置"), subtitle: nil, selected: current == .none) {
                        choose(.none)
                    }
                    if let autoName {
                        // autoName 是解析出来的地名（数据），副标题才是文案
                        row(title: Text(autoName), subtitle: Text("当前位置"), selected: current == .auto) {
                            choose(.auto)
                        }
                    }
                }
                .listRowBackground(theme.cardBackground)

                Section {
                    if isLoading && results.isEmpty {
                        HStack {
                            ProgressView().tint(theme.accent)
                            Text("正在找附近的地点…")
                                .font(theme.labelFont)
                                .foregroundStyle(theme.textTertiary)
                        }
                    } else if results.isEmpty {
                        Text(query.isEmpty ? "附近没有找到地点" : "没有匹配的地点")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        ForEach(results, id: \.self) { item in
                            let name = item.name ?? ""
                            // 搜索结果全是数据（店名 / 距离 + 街道），不查本地化表
                            row(
                                title: Text(name),
                                subtitle: subtitle(for: item).map { Text($0) },
                                selected: current == .manual(name)
                            ) {
                                choose(.manual(name))
                            }
                        }
                    }
                } header: {
                    Text(query.isEmpty ? "附近" : "搜索结果")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .listRowBackground(theme.cardBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .searchable(text: $query, prompt: "搜索地点")
            .onChange(of: query) { _, _ in scheduleSearch() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("选择地点")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .task { await loadNearby() }
            .onDisappear { searchTask?.cancel() }
        }
    }

    // MARK: - 行

    /// 收 `Text` 而不是 `String`：这一行的标题**有时是文案、有时是用户数据**
    /// （「不显示位置」是文案，POI 名和当前地名是数据）。
    /// 收 `String` 的话 `Text(String)` 一律不查本地化表，文案就永远是中文；
    /// 收 `Text` 则由调用处决定 —— 字面量自动本地化，数据显式包一层，一眼能分辨。
    private func row(title: Text, subtitle: Text?, selected: Bool, action: @escaping () -> Void) -> some View {
        let theme = themeManager.current
        return Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        subtitle
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 副标题：距离 + 街道，帮用户在同名店铺间分辨
    private func subtitle(for item: MKMapItem) -> String? {
        var parts: [String] = []
        if let coordinate {
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let there = CLLocation(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            let meters = here.distance(from: there)
            parts.append(meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000))
        }
        let address = [item.placemark.subLocality, item.placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        if !address.isEmpty { parts.append(address) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - 动作

    private func choose(_ choice: PlaceChoice) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSelect(choice)
        dismiss()
    }

    /// 输入停顿 300ms 再搜，避免每敲一个字打一次请求
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadNearby()
        }
    }

    private func loadNearby() async {
        guard let coordinate else {
            results = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        // 无关键词用周边专用请求（空关键词的 naturalLanguageQuery 搜不出东西）；
        // 有关键词时以当前位置为中心放宽到 5km 做文本搜索。
        let search: MKLocalSearch
        if query.isEmpty {
            search = MKLocalSearch(
                request: MKLocalPointsOfInterestRequest(center: coordinate, radius: 500)
            )
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
            search = MKLocalSearch(request: request)
        }

        do {
            let response = try await search.start()
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            results = response.mapItems
                .filter { $0.name?.isEmpty == false }
                .sorted {
                    let a = CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
                    let b = CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude)
                    return here.distance(from: a) < here.distance(from: b)
                }
        } catch {
            // 搜不到不是错误（郊野、室内很常见），静默留空
            results = []
        }
    }
}
