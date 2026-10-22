import SwiftUI

/// 调整构图（2026-10 P3b）：在封面比例（`NotebookCoverStore.aspect`）的框里拖动、双指缩放，
/// 框住的那一块就是封面。双击回到居中、不放大。
///
/// 照片永远铺满框：缩放不小于「刚好铺满」，拖动不会拖出空白 —— 存下来的封面不会有黑边。
/// 点「完成」时按框住的区域重新裁一张（`NotebookCoverStore.render`），后台线程做。
struct CoverCropView: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragging: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var isRendering = false

    private let aspect = NotebookCoverStore.aspect
    private let maxZoom: CGFloat = 4

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let window = windowSize(in: geo.size)
                let base = baseScale(for: window)
                let z = clampZoom(zoom * pinch)
                let o = clampOffset(offset + dragging, zoom: z, base: base, window: window)
                ZStack {
                    Color.black

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * base * z, height: image.size.height * base * z)
                        .offset(o)

                    // 框外压暗：一眼看出封面会是哪一块
                    Color.black.opacity(0.6)
                        .mask {
                            Rectangle()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3)
                                        .frame(width: window.width, height: window.height)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                        .frame(width: window.width, height: window.height)
                        .allowsHitTesting(false)

                    VStack {
                        Spacer()
                        Text("拖动调整位置，双指缩放")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.bottom, 28)
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .updating($dragging) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                offset = clampOffset(offset + value.translation, zoom: zoom, base: base, window: window)
                            },
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in
                                zoom = clampZoom(zoom * value.magnification)
                                // 缩小之后原来的位置可能露出空白，收回到边界内
                                offset = clampOffset(offset, zoom: zoom, base: base, window: window)
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.smooth(duration: 0.35)) {
                        zoom = 1
                        offset = .zero
                    }
                }
                .onAppear { containerSize = geo.size }
                .onChange(of: geo.size) { _, size in containerSize = size }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("调整构图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { finish() }
                        .disabled(isRendering || containerSize == .zero)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 几何

    /// 取景框：封面比例，左右各留 24pt，上下给提示文字留位置
    private func windowSize(in size: CGSize) -> CGSize {
        let width = max(1, min(size.width - 48, (size.height - 120) * aspect))
        return CGSize(width: width, height: width / aspect)
    }

    /// 「刚好铺满取景框」的缩放（图的点 → 屏幕点）
    private func baseScale(for window: CGSize) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        return max(window.width / image.size.width, window.height / image.size.height)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), maxZoom)
    }

    /// 拖动范围：图的边不能拖进取景框里（不露空白）
    private func clampOffset(_ value: CGSize, zoom: CGFloat, base: CGFloat, window: CGSize) -> CGSize {
        let maxX = max(0, (image.size.width * base * zoom - window.width) / 2)
        let maxY = max(0, (image.size.height * base * zoom - window.height) / 2)
        return CGSize(width: min(max(value.width, -maxX), maxX), height: min(max(value.height, -maxY), maxY))
    }

    // MARK: - 完成

    /// 把取景框换算回原图上的区域，后台重新裁一张
    private func finish() {
        let window = windowSize(in: containerSize)
        let k = baseScale(for: window) * zoom
        let width = window.width / k
        let height = window.height / k
        let centerX = image.size.width / 2 - offset.width / k
        let centerY = image.size.height / 2 - offset.height / k
        let rect = CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        let source = image
        isRendering = true
        Task {
            let cropped = await Task.detached(priority: .userInitiated) {
                NotebookCoverStore.render(source, crop: rect)
            }.value
            isRendering = false
            onDone(cropped)
        }
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
