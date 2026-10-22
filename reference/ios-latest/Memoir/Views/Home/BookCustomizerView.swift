import SwiftUI
import PhotosUI
import UIKit

/// 新建 / 编辑封面共用的封面编辑（2026-10 P2 照片、P3b 版式 + 构图 + 副标题）。
///
/// 从上到下：预览 → 封面照片 → 版式（有照片时）→ 颜色（没照片、或版式是「贴照片」时）→ 副标题。
///
/// **照片在前、颜色在后**：皮革下架、不给选材质，就是为了把用户引向「用自己的照片做封面」。
/// 颜色只在没有照片时出现，作为「先用一种颜色」的退路；「贴照片」的底子是布面，这时颜色也要能选。
///
/// 改动都攒在 `edit` 里，点「创建 / 应用」时才由调用方落盘（见 `CoverEdit.apply`）。
struct BookCustomizerView: View {
    /// 预览封面上的书名（新建时是正在输入的名字）
    let previewName: String
    @Binding var edit: CoverEdit
    /// 这本原来的照片封面文件名；新建时为 nil
    var existingPhoto: String? = nil

    @Environment(StoreKitManager.self) private var store
    @Environment(AppEnvironment.self) private var env
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    /// 这次从相册选来的原图（已缩到 2400px）。留着给「调整构图」用 —— 从原图重裁，而不是在裁过的图上再裁
    @State private var pickedOriginal: UIImage?
    @State private var cropping: CropRequest?

    private struct CropRequest: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var previewPhoto: CoverPhotoSource? {
        edit.photo.previewSource(existing: existingPhoto)
    }

    private var showsColors: Bool {
        previewPhoto == nil || edit.layout.showsCoverColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            // 大图预览（实时反映当前选择）
            HStack {
                Spacer()
                BookCoverView(name: previewName, entryCount: 0, color: edit.color, photo: previewPhoto, layout: edit.layout)
                    .frame(width: 150)
                    .overlay {
                        if isLoadingPhoto { ProgressView() }
                    }
                Spacer()
            }
            .animation(.smooth(duration: 0.3), value: previewPhoto)
            .animation(.smooth(duration: 0.3), value: edit.layout)

            photoSection

            if previewPhoto != nil {
                layoutSection
                    .transition(.opacity)
            }

            if showsColors {
                colorSection
                    .transition(.opacity)
            }

            subtitleSection
        }
        .animation(.smooth(duration: 0.3), value: previewPhoto == nil)
        .animation(.smooth(duration: 0.3), value: showsColors)
        .onChange(of: pickerItem) { _, item in
            load(item)
        }
        .fullScreenCover(item: $cropping) { request in
            CoverCropView(
                image: request.image,
                onDone: { cropped in
                    edit.photo = .replaced(cropped)
                    cropping = nil
                },
                onCancel: { cropping = nil }
            )
        }
    }

    // MARK: - 照片

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("封面照片")

            if previewPhoto == nil {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22, weight: .light))
                        Text("从相册选一张")
                            .font(.system(size: 14, weight: .medium))
                        Text("用你自己的照片，做这本日记的封面")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundColor(.secondary.opacity(0.5))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto)
            } else {
                HStack(spacing: 18) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("更换照片", systemImage: "photo")
                    }
                    .disabled(isLoadingPhoto)

                    Button {
                        adjustComposition()
                    } label: {
                        Label("调整构图", systemImage: "crop")
                    }
                    .disabled(isLoadingPhoto)

                    Button(role: .destructive) {
                        // 原来就没照片（这次新选的）→ 回到「没改」；原来有 → 标记为移除
                        edit.photo = existingPhoto == nil ? .unchanged : .removed
                        pickedOriginal = nil
                    } label: {
                        Label("移除", systemImage: "xmark.circle")
                    }
                }
                .font(.system(size: 14))
                .labelStyle(.titleAndIcon)
            }
        }
    }

    /// 读相册里那张 → 后台按 2400px 解码 → 直接打开「调整构图」。
    ///
    /// 4800 万像素的原图整张解进内存要近 200MB，所以按长边 2400px 解码；放后台线程，主线程不卡
    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingPhoto = true
        Task {
            defer {
                isLoadingPhoto = false
                pickerItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    presentLoadFailure(nil)
                    return
                }
                let image = await Task.detached(priority: .userInitiated) {
                    NotebookCoverStore.downsample(data: data, maxPixels: 2400)
                }.value
                guard let image else {
                    presentLoadFailure(nil)
                    return
                }
                pickedOriginal = image
                cropping = CropRequest(image: image)
            } catch {
                presentLoadFailure(error)
            }
        }
    }

    /// 调整构图：这次新选的照片从原图重裁；原来就有的封面只能在已裁好的那张里再调（原图没留）
    private func adjustComposition() {
        if case .replaced = edit.photo, let original = pickedOriginal {
            cropping = CropRequest(image: original)
            return
        }
        if case .replaced(let image) = edit.photo {
            cropping = CropRequest(image: image)
            return
        }
        guard let existingPhoto else { return }
        isLoadingPhoto = true
        Task {
            let image = await NotebookCoverStore.fullImage(existingPhoto)
            isLoadingPhoto = false
            if let image {
                cropping = CropRequest(image: image)
            } else {
                presentLoadFailure(nil)
            }
        }
    }

    private func presentLoadFailure(_ error: Error?) {
        let message = NSLocalizedString("照片加载失败", bundle: .appLanguage, comment: "封面照片读不出来")
        if let error {
            let ns = error as NSError
            NSLog("❌ [Cover] 读取相册照片失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            env.errors.present(error, fallback: message)
        } else {
            NSLog("❌ [Cover] 读取照片失败：拿不到数据或解码失败")
            env.errors.present(message)
        }
    }

    // MARK: - 版式

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("版式")
            HStack(alignment: .top, spacing: 18) {
                ForEach(CoverLayout.allCases, id: \.self) { layout in
                    let selected = edit.layout == layout
                    VStack(spacing: 8) {
                        BookCoverView(name: previewName, entryCount: 0, color: edit.color, photo: previewPhoto, layout: layout)
                            .frame(width: 66)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(selected ? Color(hex: "#3D3428") : Color.clear, lineWidth: 2)
                                    .padding(-4)
                            )
                            // 会员版式：照样能选、能在上面的大预览里看效果，保存时才问（尺素会员）
                            .overlay(alignment: .topTrailing) {
                                if layout.isMemberOnly && !store.isMember { MemberBadge(size: 16).offset(x: 6, y: -6) }
                            }
                        Text(layout.displayName)
                            .font(.system(size: 12))
                            .foregroundColor(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.smooth(duration: 0.3)) { edit.layout = layout }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    // MARK: - 颜色

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 没照片：颜色就是封面；贴照片：颜色是照片底下的布面；杂志：颜色是那张纸
            sectionTitle(previewPhoto == nil ? "或者选一种颜色" : (edit.layout == .framed ? "纸面颜色" : "布面颜色"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(BookColor.allCases, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color.hex))
                            .frame(width: 36, height: 36)
                            // 象牙白本身浅，加细描边让它在浅背景上可见
                            .overlay(
                                Circle()
                                    .stroke(
                                        color == .ivory ?
                                        Color(hex: "#D4C9B8") : Color.clear,
                                        lineWidth: 0.5
                                    )
                            )
                            // 选中态：2pt 外环 padding(-4) 外凸
                            .overlay(
                                Circle()
                                    .stroke(
                                        edit.color == color ?
                                        Color(hex: "#3D3428") : Color.clear,
                                        lineWidth: 2
                                    )
                                    .padding(-4)
                            )
                            .contentShape(Circle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                edit.color = color
                            }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)   // 给选中环 padding(-4) 留垂直空间
            }
        }
    }

    // MARK: - 副标题

    private var subtitleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("副标题（可选）")
            TextField("例如：2025 · 京都", text: $edit.subtitle)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: edit.subtitle) { _, value in
                    if value.count > CoverEdit.subtitleMaxLength {
                        edit.subtitle = String(value.prefix(CoverEdit.subtitleMaxLength))
                    }
                }
            Text("写在日记本主页的书名下面；不写就显示这本日记跨越的年月")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }
}
