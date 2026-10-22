#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 信封封舌像纸页一样卷（2026-10-21 产品定：像电子书翻页，不再整片绕上沿直直地翻）。
//
// 卷纸的标准画法：纸上一条卷轴（一点 + 法向 n，n 指向「卷起来的那边」），轴这边平铺；
// 轴那边先绕着一根半径 R 的圆柱卷上去，卷过半圈以后背面朝上、平躺着翻回来，压在平铺那截上面。
// 每个像素倒着找它来自封舌的哪一点（沿 n 方向的距离变了，沿轴方向不变），看到的是正面（封舌外面）还是背面（里面的衬纸）：
//
//   层（从上往下）           投影到轴的距离 d          原来离轴多远 s            看到哪面
//   翻回来平躺的那截         d ≤ 0                     πR − d                    背面
//   圆柱的上半圈             0 ≤ d ≤ R                 R·(π − asin(d/R))         背面
//   圆柱的下半圈             0 ≤ d ≤ R                 R·asin(d/R)               正面
//   还平着的那截             d < 0                     d                         正面
//
// R = 0 时就是沿轴对折（翻开到底就是沿上沿对折，和原来翻到 180° 一模一样）。
// 两张贴图是封舌合着时的外面 / 里面（`SealedEnvelope` 截的），按 alpha 当纸的轮廓，从上往下叠着画（边缘不起锯齿）。

constexpr sampler faceSampler(coord::normalized, address::clamp_to_zero, filter::linear);

static half4 face(texture2d<half> tex, float2 src, float4 sheet) {
    float2 uv = (src - sheet.xy) / sheet.zw;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return half4(0.0h);
    return tex.sample(faceSampler, uv);
}

/// 前面的盖在后面的上面（颜色都是预乘过 alpha 的）
static half4 over(half4 top, half4 bottom) {
    return top + bottom * (1.0h - top.a);
}

static half4 shaded(half4 c, float brightness) {
    return half4(c.rgb * half(brightness), c.a);
}

/// - position: 这个像素在画布上的位置（点）
/// - front / back: 封舌外面 / 里面，合着时的样子，铺满信封那么大
/// - sheet: 信封在画布上的位置和大小 (x, y, w, h)
/// - axis: 卷轴上一点 (x, y) 和法向 (nx, ny)，法向指向卷起来的那边
/// - radius: 卷的半径（点）
/// - hinge: 信封上沿（折痕）在画布上的 y
/// - part: 0 = 只画上沿以上（在信纸后面），1 = 只画上沿及以下（在口袋前面）—— 和原来封舌翻过 90° 前后的层次一样
[[ stitchable ]] half4 flapCurl(float2 position, half4 color, texture2d<half> front, texture2d<half> back,
                                float4 sheet, float4 axis, float radius, float hinge, float part) {
    if (part < 0.5 && position.y >= hinge) return half4(0.0h);
    if (part >= 0.5 && position.y < hinge) return half4(0.0h);

    const float PI = 3.14159265;
    float2 n = axis.zw;
    float d = dot(position - axis.xy, n);
    float R = max(radius, 0.0);
    half4 out = half4(0.0h);

    // 翻回来平躺的那截：最上面，露里面
    if (d <= 0.0) {
        float s = PI * R - d;
        out = over(out, shaded(face(back, position + n * (s - d), sheet), 0.97));
    }
    // 卷在圆柱上的那截：上半圈露里面，下半圈露外面；越往圆柱侧面越暗
    if (R > 0.0001 && d >= 0.0 && d <= R) {
        float a = asin(clamp(d / R, 0.0, 1.0));
        float upper = PI - a;
        out = over(out, shaded(face(back, position + n * (R * upper - d), sheet), 0.80 - 0.20 * cos(upper)));
        out = over(out, shaded(face(front, position + n * (R * a - d), sheet), 0.80 + 0.20 * cos(a)));
    }
    // 还平着的那截：最下面，露外面；挨着卷轴有一点卷起来投下的影子
    if (d < 0.0) {
        float shadow = R > 0.0001 ? 1.0 - 0.16 * (1.0 - smoothstep(0.0, 1.8 * R, -d)) : 1.0;
        out = over(out, shaded(face(front, position, sheet), shadow));
    }
    return out;
}
