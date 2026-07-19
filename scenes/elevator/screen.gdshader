shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================
// 1. 屏幕纹理声明（Godot 4 专用）
// hint_screen_texture 告诉引擎：这个 uniform 由系统自动填充当前屏幕画面
// repeat_disable 防止 UV 超出边界时纹理重复
// filter_linear_mipmap 让反射带轻微模糊，更像真实玻璃
// ============================================================
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// ============================================================
// 2. 可调参数（在材质面板中实时调整）
// ============================================================

// 玻璃透明度：0.0 = 完全透明（不可见），1.0 = 完全不透明
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.7;

// 反射强度：0.0 = 无反射，1.0 = 镜面反射
uniform float glass_reflectivity : hint_range(0.0, 1.0) = 0.3;

// 玻璃粗糙度：0.0 = 完全光滑（镜面），1.0 = 磨砂玻璃
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.1;

// 折射强度：模拟玻璃厚度，值越大看到的背后物体偏移越多
uniform float glass_refraction : hint_range(0.0, 1.0) = 0.1;

// 玻璃色调：给玻璃染色，比如偏蓝 (0.8, 0.9, 1.0) 或偏绿 (0.8, 1.0, 0.8)
uniform vec3 glass_tint : source_color = vec3(1.0, 1.0, 1.0);

// ============================================================
// 3. 片段着色器（核心：玻璃质感渲染）
// ============================================================
void fragment() {
    // ---------- 第一步：基础颜色 ----------
    // 用玻璃色调乘以 0.8 让颜色略暗，模拟玻璃本身的吸收
    vec3 base_color = glass_tint * 0.8;

    // ---------- 第二步：环境反射 ----------
    // SCREEN_UV 是当前像素对应的屏幕坐标（0~1）
    vec2 screen_uv = SCREEN_UV;
    
    // 采样屏幕纹理，获取当前像素背后的场景颜色
    // 这就是玻璃反射效果的来源：把周围环境映在玻璃表面
    vec4 screen_color = texture(screen_texture, screen_uv);
    
    // 反射颜色 = 屏幕颜色 × 反射强度
    vec3 reflection = screen_color.rgb * glass_reflectivity;

    // ---------- 第三步：高光（模拟光源在玻璃表面的反光点） ----------
    // VIEW 是视图方向向量（从像素指向相机）
    vec3 view_dir = normalize(VIEW);
    // NORMAL 是当前像素的法线方向（世界空间）
    vec3 normal = normalize(NORMAL);
    
    // 计算反射向量：光线从视角方向射向法线，反射出去的方向
    vec3 reflect_dir = reflect(-view_dir, normal);
    
    // 计算高光角度：反射方向与视角方向的点积
    float spec_angle = max(dot(reflect_dir, view_dir), 0.0);
    
    // 用 32 次方让高光集中在一个小亮点（指数越大，高光点越小越亮）
    float specular = pow(spec_angle, 32.0) * glass_reflectivity * 2.0;
    
    // 高光颜色为白色（模拟光源反射）
    vec3 highlight = vec3(specular);

    // ---------- 第四步：折射（模拟玻璃厚度造成的图像偏移） ----------
    // 原理：根据法线方向轻微偏移屏幕 UV 坐标
    // normal.xy 是法线在屏幕平面上的投影分量
    // glass_refraction * 0.05 控制偏移量，0.05 是个经验值，防止偏移过大
    vec2 refracted_uv = screen_uv + normal.xy * glass_refraction * 0.05;
    
    // 采样偏移后的屏幕颜色，模拟透过玻璃看到的扭曲景象
    vec4 refracted_color = texture(screen_texture, refracted_uv);
    
    // 折射颜色乘 0.5 让透射部分半透明，更像真实玻璃
    vec3 refraction = refracted_color.rgb * 0.5;

    // ---------- 第五步：混合所有效果 ----------
    // 最终颜色 = 底色 + 反射 + 高光 + 折射
    vec3 final_color = base_color + reflection + highlight + refraction;

    // ---------- 第六步：输出到渲染管线 ----------
    // ALBEDO 控制漫反射颜色（这里是最终混合色）
    ALBEDO = final_color;
    
    // ALPHA 控制透明度（0.0 完全透明，1.0 完全不透明）
    ALPHA = glass_opacity;
}

// ============================================================
// 4. 可选扩展：光照函数（当前版本未使用）
// 如果你需要更复杂的光照效果（如多个光源），可以在这里添加
// ============================================================
// void light() {
//     // 自定义光照计算
// }