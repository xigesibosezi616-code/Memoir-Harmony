#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 转得动的邮筒：把部件层（投信口、铭牌、筒身上的 m.、小门、一颗样子铆钉）按圆筒的曲率绕到当前角度（2026-10-20）。
//
// 筒身层（轮廓、明暗排线、帽顶、领圈、底座）绕竖轴转一圈样子不变，由 SwiftUI 直接画在下面；
// 这里只画会动的部件，叠在上面。所有几何量都是原图（678×1498）的像素，和 Scripts/make_mailbox_layers.py 的框一起看。
//
// 原图当成圆筒的正视图（正交投影）：屏幕上横坐标 x 对应筒面上的角度 α = asin((x − 中心) / 半径)。
// 转过 yaw 之后，此刻在 α 处的筒面原来在 θ = α − yaw，回原图 x' = 中心 + 半径·sin θ 取色 —— yaw = 0 时和原图一模一样。

constant float2 kImage = float2(678.0, 1498.0);

// 筒身：中心、内半径（到轮廓线内沿，部件转到这里正好被轮廓吃掉）
constant float kBodyX = 339.0;
constant float kBodyR = 208.0;
constant float kBodyTop = 226.0;

// 帽檐那圈铆钉：帽檐比筒身宽；从下往上看，帽檐是一圈往两边垂下去的弧 —— 铆钉中心高度 y = y0 + h·(1 − cos α)
constant float kCapX = 340.5;
constant float kCapR = 240.0;
constant float kRivetY0 = 181.3;
constant float kRivetDrop = 26.5;
constant float kRivetCount = 20.0;
// 部件层里留着当样子的那一颗（几乎在正中，没有透视压缩）
constant float2 kRivetSample = float2(361.0, 181.5);
constant float2 kRivetHalf = float2(14.0, 15.0);
constant float kCapTop = 150.0;

constexpr sampler partsSampler(coord::normalized, address::clamp_to_zero, filter::linear);

// 横向取三下平均：部件转到边上被压扁时，一个屏幕像素盖住原图好几个像素，只取一下会闪
static half4 sampleRow(texture2d<half> parts, float2 src, float footprint) {
    float spread = clamp(footprint, 0.0, 6.0) / 3.0;
    half4 c = parts.sample(partsSampler, src / kImage);
    c += parts.sample(partsSampler, float2(src.x - spread, src.y) / kImage);
    c += parts.sample(partsSampler, float2(src.x + spread, src.y) / kImage);
    return c / 3.0h;
}

// 把角度折回 (−π, π]
static float wrapAngle(float a) {
    return a - 2.0 * M_PI_F * floor((a + M_PI_F) / (2.0 * M_PI_F));
}

/// - position: 这个像素在视图里的位置（点）
/// - parts: 部件层
/// - size: 视图大小（点），和原图同比例
/// - yaw: 转过的角度（弧度），正 = 筒面往右走
/// - scale: 屏幕的像素密度（取样宽度用）
[[ stitchable ]] half4 mailboxSurface(float2 position, half4 color, texture2d<half> parts, float2 size, float yaw, float scale) {
    float2 p = position / size * kImage;
    // 一个屏幕像素在原图里多宽
    float pixel = kImage.x / (size.x * scale);

    if (p.y >= kBodyTop) {
        float s = (p.x - kBodyX) / kBodyR;
        if (abs(s) >= 1.0) return half4(0.0h);
        float a = asin(s);
        float th = wrapAngle(a - yaw);
        // 转到背面了：背面是素的
        if (abs(th) >= M_PI_2_F) return half4(0.0h);
        float src = kBodyX + kBodyR * sin(th);
        float footprint = pixel * cos(th) / max(cos(a), 0.05);
        // 贴着轮廓那一点淡掉，边上不起锯齿
        half fade = half(smoothstep(1.0, 0.965, abs(s)));
        return sampleRow(parts, float2(src, p.y), footprint) * fade;
    }

    if (p.y >= kCapTop) {
        float s = (p.x - kCapX) / kCapR;
        if (abs(s) >= 1.0) return half4(0.0h);
        float a = asin(s);
        float dy = p.y - (kRivetY0 + kRivetDrop * (1.0 - cos(a)));
        if (abs(dy) > kRivetHalf.y) return half4(0.0h);
        // 离最近那颗铆钉的中心，沿筒面量有多远
        float step = 2.0 * M_PI_F / kRivetCount;
        float th = a - yaw;
        float d = kCapR * (th - step * round(th / step));
        if (abs(d) > kRivetHalf.x) return half4(0.0h);
        float footprint = pixel / max(cos(a), 0.05);
        half fade = half(smoothstep(1.0, 0.95, abs(s)));
        return sampleRow(parts, kRivetSample + float2(d, dy), footprint) * fade;
    }

    return half4(0.0h);
}
