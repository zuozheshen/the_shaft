shader_type spatial;
render_mode unshaded;

// 只采样原监控视口；低清过滤不扩散到全局 UI。
uniform sampler2D feed_texture : source_color, filter_nearest, repeat_disable;
uniform float curvature : hint_range(0.0, 0.03) = 0.015;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.04;
uniform float vignette_strength : hint_range(0.0, 0.15) = 0.08;
uniform float brightness : hint_range(0.9, 1.1) = 1.0;

void fragment() {
    vec2 centered = UV * 2.0 - 1.0;
    vec2 feed_uv = 0.5 + centered * 0.5 *
        (1.0 + clamp(curvature, 0.0, 0.03) * dot(centered, centered));
    vec3 feed = texture(feed_texture, clamp(feed_uv, vec2(0.0), vec2(1.0))).rgb;
    float inside = step(0.0, feed_uv.x) * step(feed_uv.x, 1.0) *
        step(0.0, feed_uv.y) * step(feed_uv.y, 1.0);
    float line_y = feed_uv.y * 240.0;
    // 缩小时先衰减扫描线，避免接近屏幕采样极限时产生摩尔纹。
    float line_visibility = 1.0 - smoothstep(0.25, 0.75, fwidth(line_y));
    float line_darkening = (0.5 + 0.5 * cos(line_y * 6.2831853)) *
        clamp(scanline_strength, 0.0, 0.08) * line_visibility;
    float edge_darkening = clamp(dot(centered, centered) * 0.5, 0.0, 1.0) *
        clamp(vignette_strength, 0.0, 0.15);
    ALBEDO = feed * inside * (1.0 - line_darkening) * (1.0 - edge_darkening) *
        clamp(brightness, 0.9, 1.1);
}
