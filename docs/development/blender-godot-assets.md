# Blender → Godot 视觉资产边界

正式入口仍为 `scenes/main/main_3d.tscn`。玩家始终在固定操作舱工作；更换美术不改变路线、输入、UI 或业务状态。

## 源文件与运行资产

- 主操作台 V2 的正式源文件为 `art_source/main_console_v2.blend`，与运行资产一起沿用仓库现有 Git LFS 规则跟踪；`art_source/.gdignore` 阻止 Godot 自动导入 .blend，局部 `.gitignore` 排除 Blender 备份。源文件与 GLB 的用途、来源、大小和 SHA-256 记录在对应 Issue REVIEW；新增其他资产或改变跟踪规则仍需对应方案，不将临时项目外探针目录作为正式源位置。
- 临时管线探针可使用项目外的 Blender 测试源文件，不提交；不保存或覆盖用户已有正式源文件。
- 运行资产使用 `assets/art/models/<asset>.glb`，小写 snake_case，例如 `main_console_shell.glb`。只有具体正式资产 Issue 批准后才添加二进制文件。
- 本地导入探针使用 `assets/art/models/_pipeline_probe/`。该目录及其 `.import` sidecar 不提交；截图、日志、`.godot/`、Blender 备份和测试导出同样不提交。

## Godot 拥有稳定的节点

现有主、左、右“操作台定位”是稳定的台位根。保留当前 Transform 和 Gameplay 路径，只有存在实际耦合时才迁移，不要求所有物件拥有相同的中间层级。

- 台体、背板和边框可放在台位根的“视觉资产”子树。
- 热点 `Area3D`、`CollisionShape3D`、action_id、Label3D、SubViewport、动态屏面与指示灯是 Godot 自有节点，留在可替换模型之外。
- MIC/OPEN/CLOSE 的现有视觉子树及 CAM 的“视觉”负责外形和可选视觉反馈；CAM 的“交互反馈”保留悬停高亮与无 Mesh 的选中兼容标记，帽材质由视觉组件更新。稳定反馈节点不放入 GLB 内。
- 左台“滚轮转轴”由 Godot 驱动；其“视觉资产”装滚轮外形，碰撞不随滚动旋转。
- 右台拨杆轴保留 Godot 所有，其“视觉资产”装杆柄；执行热点、busy 和业务提交不依赖杆柄内部结构。
- 信息屏底面、LCD 底面、文字、书的动态页面继续由 Godot 管理。Blender 提供外壳、边框、玻璃等静态外形。
- 已有楼层书移动根、封面/翻页轴、视口和热点，以及摄影棚门的动画根与 Mesh 子节点边界保持原职责。不为层级统一重建这些组件，也不移动舱壁/地板或重做灯光。

允许表现脚本更新自己负责的 Godot 动态 Mesh/Label；禁止业务脚本读取可替换 GLB 内部的节点名称、层级或材质槽来决定行为。

## 替换与重导入

1. 保留 Godot 台位、热点、动画轴与动态显示节点。只在对应视觉挂载下替换外形子节点；不能替换包含 Gameplay 的台位根。
2. 当前灰盒可直接留在挂载下。需要可复用 wrapper 时使用 `scenes/visuals/<asset>_visual.tscn`，新增 Godot 节点使用中文；不复制业务控制器或另建完整舱体。
3. Blender 使用米制尺寸，静态台体相对台位本地原点制作，滚轮/拨杆等组件相对 Godot 稳定轴制作。保留当前台位缩放；先核对世界尺寸再导出。
4. 使用标准 glTF 导出坐标转换；不额外添加未经核实的 90° 补偿，不修改项目坐标体系。不得顺手 Apply 用户已有正式对象的 Transform/Modifier。
5. 仅导出批准的对象，默认不导出 Camera/Light。不得使用触发碰撞生成的命名后缀或把业务 metadata 放入模型；需要真实碰撞时在 Godot 单独维护。
6. 重导出到同一 GLB 路径并触发 Godot import。内部对象名、数量和层级可改变，现有 Gameplay NodePath 不应需要重新绑定。
7. 在正式 `main_3d` 的实际玩家视角验证，不以 Blender 视口或 headless 退出码替代视觉验收。

## 临时探针与验收

先核实 Blender MCP、当前 `.blend`、Scene、Collection、未保存修改、导出范围和路径。只新增本任务的 `AgentGenerated_ART01_PipelineProbe` Collection；默认不修改、删除或保存已有用户对象。

验证两轮：导出简单外壳 → Godot import → 临时替换主台外壳 → 正式场景运行；修改探针尺寸/内部名称 → 覆盖同一个临时 GLB → reimport → 再运行。每轮检查热点射线、MIC/CAM/OPEN/CLOSE、监控纹理与状态条、左右台、书和手柄动作，以及脚本/viewport/动画轴身份和路径。

验证结束恢复原灰盒，并清理仅本次生成的临时接线/导出。只有确认测试 Collection 归本任务且没有用户追加修改时才清理它。正式资产的保存、导出、覆盖和二进制提交需要其对应 Issue 的批准范围。

REVIEW 分别记录自动逻辑检查、Godot AI 视觉/运行时自检和用户体验验收；任何一项不能冒充另一项。

## 主操作台 V2 Blockout（#62）

- 源 Scene 为“主操作台体块”，模型范围为 `AgentGenerated_ART02_1_Blockout`；使用米制单位、主台局部原点与标准 glTF Y-up 转换。只导出外壳模型，不导出 Camera、Light、碰撞、动态屏面或业务 metadata。
- `main_console_shell.glb` 包含机身、CRT/CASE 外壳及 COMM/CAMERA/DOOR 板壳；通过 `scenes/visuals/main_console_shell_visual.tscn` 接入既有主台“视觉资产”。所有 Gameplay、热点、反馈、CASE 动态文字和监控纹理链保持 Godot 所有。
- CRT 最前方物理孔口为 1.32×0.99 米（4:3），中心约 Y=1.827 米、前缘 Z=-1.39 米；内框向后渐扩，前孔为 1.36×1.02 米（Z=-1.425），后孔留出裕量为 1.46×1.095 米（Z=-1.524）。后方仍预留以 Y=1.86 米为中心的 1.44×1.08 米屏幕空间与占位衬底。前框孔口与实际动态内容是两层：#62 阶段保留 640×360 feed、1.44×0.81 米（16:9）QuadMesh、`center_offset=(0, 0.16913, 0)` 及原主监视器 Transform，#65 已将同一动态屏面改为 4:3，最终规格见末节。
- 上柜外宽仍为 2.42 米、外侧壁宽 6 厘米；CRT 两侧可见机柜带由 37 收至 28 厘米，其中前面板由 31 收至 22 厘米。新增 CRT 模组壳体外宽 1.86 米、纵深 22 厘米（Z=-1.65 至 -1.43 米），相对柜前面 Z=-1.50 米前凸 7 厘米；bezel 再前伸 4 厘米至 Z=-1.39 米。原屏面 Z=-1.529 米不动，相对 bezel 最前沿内凹 13.9 厘米，形成“主机柜 → CRT 模组壳体 → 厚 bezel → 内凹屏幕”。
- 柜顶由 Y=2.454 降至 2.424 米，顶盖外侧厚度由 4 收至 3 厘米；中央隐藏下表面为 Y=2.410 米，保留 1.4 厘米顶壳厚度与未来屏幕顶部 Y=2.400 米的空间。bezel 顶带约由 12 收至 9 厘米，仅使用 2–3 毫米单段边缘折角，无 Modifier。
- 主台控件斜面仍为 55°，下端约 Y=0.823 米；水平前沿延伸由 15 收至 7 厘米，厚度由 2 收至 1.2 厘米。操作楔体前裙下端后收 10 厘米（相对竖直约 18.27°）；下部底座前面上端后收 10 厘米、下端后收 23 厘米（约 15.46°），底宽由 2.56 收至 2.36 米。三块操作面沿用原高度与边界，前端边厚由 2.5 收至 2 厘米，COMM 留空、DOOR 保持较宽。Godot 场景、Gameplay、五个热点、碰撞、action_id、反馈、CASE、玩家位置与 FOV 均未改变。
- #62 的几何基线为 20 个 Mesh 与一个根 Empty、4 个中性灰 Blockout 材质；当时本体不含 UV、贴图、正式材质、按钮/麦克风模型或表面细节。#64 在原几何上加入下节所述 UV/材质，#65 的 CRT shader 和 CASE 动态屏面见末节。#63 控制件在同一源文件的独立 Collection 制作，见下节；后续 #64 Material / #65 Screen 阶段仍按对应 Issue 审批。
- #62 审批允许 Codex 新建该专用文件，并只保存自身生成的修改；写前仍核对 filepath、Scene、Collection、对象与用户未保存修改。禁止覆盖身份不明的源文件、将用户已有场景 Save As 到正式源路径，或对用户文件 Revert。

## 主操作台 V2 控制件（#63）

- 沿用 `art_source/main_console_v2.blend` 与“主操作台体块”Scene；专属 `AgentGenerated_ART02_2_Controls` Collection 包含 6 个控制件 Mesh 与 6 个导出根。#62 的 Collection、20 个 shell Mesh、根 Empty 与 `main_console_shell.glb` 保留，控制件不并入 shell。
- 本阶段只新增以下 6 个运行 GLB，这是允许的最大拆分粒度；不把单个控制件继续拆成更多独立运行资产。#63 基线模型使用中性或低饱和占位材质，各 GLB 为单位 Transform 的根与静态 Mesh；当时只含位置和法线数据，无 UV、贴图。#64 仅补充 UV/表面数据，持续不含 Camera、Light、动画、skin、碰撞或业务 metadata。

| 控制件 | `assets/art/models/` 运行资产 | `scenes/visuals/` wrapper |
| --- | --- | --- |
| 固定桌面调度麦克风 | `desk_microphone.glb` | `desk_microphone_visual.tscn` |
| CAM 共享方形按钮 | `button_square.glb`、`button_square_cap.glb` | `button_square_visual.tscn` |
| OPEN/CLOSE 共享大型按钮 | `button_large.glb`、`button_large_cap.glb` | `button_large_visual.tscn` |
| 三灯共享静态安装壳 | `indicator_lamp.glb` | `indicator_lamp_visual.tscn` |

- 四个 wrapper 只装配外形与可选视觉反馈，继续挂在既有“麦克风视觉”“开门视觉”“关门视觉”、CAM“视觉”和原灯根内。CAM 两实例共享标准框/帽几何，OPEN/CLOSE 两实例共享大型框/帽几何；按钮占位色由 Godot 场景内材质覆盖，OPEN 使用低饱和工业绿、CLOSE 使用低饱和深红。CAM 旧选中背光为无 Mesh 的兼容标记，选中表现改为按钮帽变亮和微弱发光，暗/亮帽材质按实例隔离；功能文字均移到固定面板小铭牌，按钮帽上没有文字；Label3D 与悬停高亮仍由 Godot 管理，麦克风与门控沿用 CAM 的青色薄安装座边缘形式，不复制 Gameplay 节点。门按钮对既有父级非均匀 Basis 的补偿仅写入视觉 wrapper。
- 按钮机械层级为“台面 → 安装法兰 → 固定壳体 / bezel → 独立凸起帽”，帽与框之间留真实阴影缝，边缘只有轻微倒角。沿台面法线计，CAM 占地为 0.17×0.17 米，视觉中心距 0.21 米（两 wrapper 先各向内偏移 40 毫米，再整体向右 27.5 毫米对齐原 CAMERA 板块中心，原热点不动），安装座净高 23 毫米、帽顶 33 毫米；大型按钮安装座净高 33 毫米、帽顶 45 毫米，外占地为 0.25×0.24 米，采用更厚安装座与更宽 bezel，并非整套 CAM 同比放大。
- 麦克风是固定底座、鹅颈与短圆柱麦头组成的独立整体，不可拿起，沿用原 toggle microphone。底座为 0.264×0.176 米，杆径 0.0225 米（比上一版增加 50%），麦杆弧长约 206 毫米，向上 120 毫米并向玩家侧弯出 130 毫米，麦头朝玩家约 65°，麦头直径 0.0675 米；没有真实网孔阵列。原大号“麦克风热点/设备标识”Label3D 隐藏，原 wrapper 的独立 COMM 字移到面板的 COMM 小铭牌；原 COMM 灯标识为 TX，并从原灯位向麦座靠近 136.6 毫米，沿用同一灯面与 `mic_enabled_changed`。不新增录音或发射状态，也不在麦座复制第二个灯。麦杆加长为向玩家弯出的鹅颈，原玩家 FOV70 下与完整 CASE 条留空；底座的安装位置不动。三灯沿用同一简单灯壳并以 0.7 视觉比例呈现，DOOR / FAULT 置于门控右侧；灯面继续由原信号更新。
- 按钮 wrapper 内的“固定安装框”静止；Godot 自有“按钮按压轴”只带动“按钮帽模型”。功能文字与薄铭牌挂在固定视觉根，帽轴不含 Label3D，按压时铭牌不随动。`ConsoleButtonVisual3D` 用一个 Tween 引用与初始位置实现 CAM 4 毫米、大型按钮 5 毫米下压，仍为 0.06 秒下压和 0.10 秒回位；快速重入从原位重新播放并回位。反馈可禁用，空或缺失按压轴静默降级；热点、碰撞、action_id、铭牌和灯不随动，不新增业务状态机。
- `MainConsolePresentation3D` 通过导出路径引用可选按钮组件，只订阅原 `camera_selected` 与 `presentation_effects_requested` 的成功开/关门 effect；初始化状态同步不播放按压。原 TX/MIC、DOOR 真实四态、FAULT 预留入口、监控纹理和 CASE 更新链保持，业务不读取 GLB 内部名称、层级或材质槽。
- COMM / CAMERA SELECT / DOOR CONTROL / STATUS 四个固定小铭牌表达功能组，CAM 01 / CAM 02、OPEN / CLOSE、TX / DOOR / FAULT 都使用独立铭牌；采用 Godot 原生薄静态几何与 Label3D 占位，不新增 GLB、不做最终材质或螺丝。铭牌贴合原模块顶面；按钮 wrapper 补偿已有资产接触面高度，使安装框实际落到台面，不移动 Gameplay。
- 六个 GLB 与既有 `.blend` 沿用现有 Git LFS 规则，不新增跟踪规则。源文件/运行资产大小、SHA、验证结果及提交状态记录在 #63 REVIEW，不将截图、日志、`.godot/` 或 Blender 备份提交为资产。
- #62/#63 造型与体验及 #64 材质已获用户人工验收；表面和屏面实现见下节。最终整体验收状态以 #65 / #61 为准，自动测试与 Godot AI 自检不得代替人工验收。


## 主操作台 V2 UV / 材质（#64）

- 原26 Mesh、7导出根、Collection、Transform/Origin、面拓扑及材质槽数量保持；仅按用户批准修补“状态窗下框”的局部顶点，其法线随局部面变化重算；最终尺寸见下述托边记录。shell五个共享材质（CRT右厚框使用独立的细节保留材质），每个Mesh仍为一槽；麦克风三槽，其余控制件一槽。大型按钮复制材质资源以使用512图，没有增加槽或拆分GLB。
- 静态机身为米白/暖灰，CRT/面板为中性中灰，CAMERA后装模块为偏冷深灰，安装框/鹅颈近黑、麦座深灰、PTT中灰。历史材质名“灰绿底座”保留，实际颜色为中性灰。CAM未选中帽为炭灰，原选中/OPEN/CLOSE/hover/TX/DOOR/FAULT功能颜色与信号保持。
- 最新实施补充采用官方CC0微表面和项目自制Atlas混合。仅采用ambientCG Metal028、Plastic013A的1K NormalGL/Roughness；不采用外部Albedo、NormalDX、Displacement、Metalness或外部blend/tres，不使用生成式图片。来源URL、许可证、日期、下载包/使用map的SHA和派生图记录在 `assets/art/textures/main_console_v2/material_provenance.json`。
- `art_source/main_console_texture_source.py` 使用Pillow 12.3.0、NumPy 2.3.5和内置字体。将provenance记录的两个1K-PNG zip下载到仓库外目录，运行 `python art_source/main_console_texture_source.py assets/art/textures/main_console_v2 --sources <仓库外素材目录>`。可直接读取zip中的所用map，或读取解出的PNG；每次先检查记录的SHA，不执行远程下载或外部资产脚本。
- 分辨率是上限：shell/Atlas1024，麦克风/大按钮512，小按钮/灯256。只制作实际使用通道；色板/金属度/基础粗糙度由材质参数控制。Normal在向量空间BOX缩放、降低XY并重建Z，采用OpenGL +Y。Roughness取8px Gaussian高通后的细颗粒，剔除大尺度斑纹，压到247±6，再乘基础参数；帽面微弱磨亮掩膜小于2%，最多降低4/255，无锈、掉漆、油泥或大面积划痕。
- 正式视角下喷漆Normal为0.45，控制件0.75，麦克风底座/PTT为0.85、鹅颈/麦头为0.75；CRT右厚框保留0.24，避免放大通风条、螺丝和UNIT01。派生PNG已先降低XY幅度。paint Normal额外使用GaussianBlur半径1.2像素预过滤，消除增强后在正式视角出现的高频斜纹；原图矩形(88,24,176,490)逐像素保留功能细节。基础Roughness目标为机身0.48、模块0.50–0.54、安装框/麦座0.46–0.48、按钮帽/PTT0.78、鹅颈/麦头0.90，乘图前按247/255中值补偿。麦头规则网孔Normal为自制，底座/鹅颈没有网孔。512项目自制Albedo只负责麦克风四个颜色区，底座64灰、PTT110灰、鹅颈/麦头32近黑。
- shell普通平面仍为368.64 texel/米的正交UV重复；控制件在0–1内。C仅将CRT右厚框的已有前脸UV映射到保留区，使用一个散热/检修条、两个固定螺丝和UNIT01小标记；自制 `module_detail_albedo.png` 和paint Normal中的保留区配合，其他面仍为统一项目颜色。不加网孔阵列或greeble几何，不把所有Atlas tile铺到主台。Atlas索引记录该表面与单元矩形；动态CASE/Camera Feed不进入Atlas。
- 源几何不为导出切线而三角化。GLB保留NORMAL/UV；Godot原 `meshes/ensure_tangents` 从导入三角面生成切线，运行时已核实Normal和切线存在。七个GLB Embedded Image Handling沿用Embed as Uncompressed（3），不向模型目录抽取重复PNG。独立PNG使用lossless/mipmaps，关闭3D自动改变压缩模式，不增加LFS规则。
- 11个固定铭牌沿用原薄盒的顶点、法线、尺寸和位置，带独立UV的ArrayMesh共用 `assets/art/materials/main_console_v2/nameplate_atlas.tres`。COMM文字沿用左移65毫米排版。原Label3D名称、文本、父级与Transform保留隐藏，必要时可恢复；文字不在按钮帽或按压轴上。CAM与OPEN/CLOSE四个外部覆盖材质引用同源256/512 Roughness/Normal，状态仍按实例隔离，GLB reimport不覆盖这些Godot资源。
- 执行顺序为A基础材质→B微表面→C功能细节→D固定铭牌；各阶段正式main_3d/FOV70/原灯光截图通过后才继续下一层。实际完成与阻塞、自动测试、Godot运行时和用户体验验收状态以#64有效评论为准。用户批准的CASE边缘修补保持：背景厚2毫米、前面内嵌外壳2毫米（背景局部z=0.007），宽2.304米、两端各搭入侧壁2毫米。STATUS下托边最终仍为8顶点/6面：前下沿X=±1.26米、Blender Y=1.444米；全部后缘及全部上沿X=±1.175米，后缘Y=1.505米、前上沿Y=1.465米。顶面保留沿X左高右低4毫米/2.52米的安装微坡，后侧另加8毫米搭接；收窄侧面以清除COMM上沿三角突出，后缘回缩与前上沿回切避免遮挡DOOR CONTROL。UV、材质槽、Transform/Origin和层级保持，仅派生法线重算。按钮、灯、铭牌、热点、碰撞、action_id、按压/hover、CASE逻辑、Camera/FOV、左右台、舱体和灯光保持；后续动态屏面规格见 #65 小节。

## 主操作台 V2 CRT / CASE（#65）

- 原监控仍为唯一 Camera / SubViewport / 共享 World3D 链，尺寸 320×240；Camera 保持 KEEP_HEIGHT、FOV60 和原两个锚点。主屏原节点 Transform、center_offset 与外壳不动，Quad 从 1.44×0.81 改为 1.44×1.08 米，4:3 四边完整落在既有孔口内。
- 仅主屏使用 assets/art/shaders/main_console_crt.gdshader / assets/art/materials/main_console_v2/crt_screen.tres。feed_texture 为原 ViewportTexture，source_color、nearest、repeat_disable，unshaded 只输出 ALBEDO；没有额外照明、双重发光或全屏效果。
- 默认曲率0.015、扫描线0.04、暗角0.08、亮度1.0；shader 内分别 clamp 到0–0.03、0–0.08、0–0.15、0.9–1.1。扫描线对应240行，以 fwidth 在缩小时衰减，优先避免摩尔纹；没有噪声、滚动、闪烁、色差或 VHS 抖动。参数归零可对照原材质。
- 设备状态条/状态视口是 disable_3d=true 的512×64 SubViewport，内部状态文字为2D Label；状态屏面是独立 nearest / unshaded StandardMaterial3D 的1.024×0.128米Quad。原2.304×0.14米背景与父级保持，不横向拉满黑条，CASE没有CRT扫描线。字色浅青，font_size24，四边8px安全区、单行居中。24个真实阶段的最长文字宽364px，字体高度34px，适合496×48px内容区，无需512×96。
- MainConsolePresentation3D 保留 status_label_path 字段名，目标迁到上述 Label，新增 status_subviewport_path / status_mesh_path。绑定只复制材质并更新纹理、原信号文字和指示灯，不重置屏面 Mesh / Transform，不在隐藏节点保存业务数据。
- #65 不修改 Blender 源文件或任何 GLB，原七个运行资产与静态材质沿用；同路径reimport后的监控/CASE绑定和热点不依赖模型内部命名。全局分辨率、左右台、COMM、楼层书、Input、灯光与其他材质过滤不变。

## 主操作台最终装配细节（#67，修订 v2）

- 基于 #65 已验收的 `84267b2`；原两个 Collection、33 对象 / 26 Mesh / 12 材质、所有几何、法线、Transform/Origin、材质槽、Modifier、隐藏状态与导出根保持。#67 v1 仅在 7 个目标对象分配固定表面 UV；v2 保留这些 UV，不新增对象或螺丝 Mesh，只重导出原 `main_console_shell.glb` 与 `desk_microphone.glb`。
- 用户要求将弱凹点改为可辨认螺丝贴图。CRT 左 / 右前脸各 2 颗约 11mm，连同既有检修条 2 颗共 6 颗；COMM / CAMERA / DOOR 各 2 颗约 9 / 8 / 9mm，错开位置；STATUS 无固定件；麦座原上表面 2 颗约 5.5mm。新固定件有灰色头部、细暗色沉头座及明确槽口，搭配浅 Normal；CAMERA 用十字槽，其余为一字槽。原检修条、通风槽和 UNIT01 不变，可选 SERV.04 省略。
- CRT/CAMERA 沿用 `module_detail_albedo.png`，麦座沿用 `microphone_albedo.png`。COMM/DOOR 原共享 `体块模块灰` 材质只新增 `panel_fastener_albedo.png` Base Color 绑定，不新增材质槽；贴图背景 128 sRGB 等于原线性 BaseColorFactor 0.2158605，普通板面底色保持。螺丝是固定装配标记，触摸磨亮区仍不改 Base Color。
- 为让实机小螺丝的头部/槽口不糊为亮点，module/panel Albedo 使用 2048px、microphone Albedo 使用 1024px；Normal/Roughness 继续 1024px / microphone Normal 512px，功能铭牌 Atlas PNG 1024px 不变。`assembly_detail_pass` 的 rect 使用原 Normal 布局坐标，Albedo 绘制乘 2；归一化 UV、物理尺寸与材质 Normal 强度不变。
- 密封带仍在 CRT 原四个内坡面后缘、约 3.5mm 近黑色，显示面/孔口几何和 4:3 feed 不变。面板与 DOOR/STATUS 分界仅约 1.2mm 浅 Normal 接缝，无 Albedo 黑描边。前沿及 CAM/OPEN/CLOSE 旁磨亮只使用 Roughness，最大减少 4/255，新增可见掩膜约占目标表面 0.3203%；无锈、掉漆、白划痕、油污或大面积使用痕迹。
- `main_console_texture_source.py` 的 `build_assembly_details` 在原 #64 派生步骤后执行，沿用原已校验 CC0 微表面与本地绘制细节，不需要新下载或生成图片；布局、螺丝表现、分辨率和输出 hash 记录于 Atlas JSON / provenance。普通机身 UV 仍采样下半区，固定装配面使用预留上半区；麦座只改变原上表面，避免标记重复到其他面。
- 导出验证对照展开三角形 POSITION/NORMAL、UV、节点层级/Transform、primitive/材质槽；v2 相对 v1 仅图片与 `体块模块灰` 的上述 Albedo 绑定变化，其他材质参数不变。活动 Blender 的未保存内存现场保留；源/导出在校验过身份的独立进程处理，保存源再以独立只读进程复核。
- `control_normal_256.png.import` 与 `control_normal_512.png.import` 明确设 `compress/normal_map=1`（Enable），保留原 OpenGL 方向与强度，避免每次从 Detect 重新自动启用；Godot 的 RG 法线压缩提示属于正常导入优化，非运行 ERROR。固定 Godot AI v4.1.0 不改。原生 stderr 已捕获 6 条节点离树路径 ERROR，发生在正式场景打开后的导入收尾期间；Godot AI 日志过滤不能替代原生日志。资源元数据/EOL 收尾改在编辑器关闭时执行，导入扫描完成后才打开正式 main_3d；该流程的最终原生日志验证记录于 #67 最新 REVIEW。编辑器实例重载是当前推断，尚未确认具体 C++ 调用点，不声称已定位永久引擎根因。
- 正式场景、Gameplay、CRT shader/ViewportTexture、CASE、Camera/FOV70、热点/碰撞与灯光不变。正式截图与独立的自动/视觉/人工验收状态记录于 #67 最新 REVIEW；停在本地 commit/push/merge 前。

## 操作舱与监控乘客舱材质 V1（#66）

- 原生方案：操作舱六个 CSGBox3D、摄影棚已有三壁/地面、两门框与门槛只绑定外部材质；两扇门保持原 BoxMesh、3×2 UV、动画根和轨道。没有舱体 GLB、新 Blender 源或导出。旧共享 4K 文件保留，仅移除操作舱场景已失去引用的三个旧墙/地/顶材质及其独占资源声明。
- 六个共享 StandardMaterial3D 位于 `assets/art/materials/elevator_cabin_v1/`。四墙灰绿 #939B93，天花浅暖灰 #B7B7AF，橡胶地面 #3E4241，涂层门 #939797，门框/门槛 #737B79，橡胶收边 #3A403E；metallic 均为 0。有效粗糙度基准依次为 0.68/0.76/0.88/0.54/0.62/0.86；有图材质的 roughness 参数除以 247/255，以抵消数据图基准。Normal 强度依次为 0.18/0.10/0.35/0.24/0.18，收边无贴图；没有 heightmap。
- 六张 1024 PNG 位于 `assets/art/textures/elevator_cabin_v1/`，总计 3,643,139 字节。喷漆 Normal/Roughness 供墙、顶、框共用；地面一组自制周期颗粒；门一组原生六面 atlas。大面局部 triplanar，4m/tile、256 texel/m；地面 offset=(0.5,0.5,0.5)，使图中的两条磨亮落在舱内中央、避免 tile 原点将其推到墙边。门正面约 341×512px 对应 1.04×2.35m。过滤为 linear mipmapped anisotropic；法线明确 Enable/OpenGL +Y，数据图不标 source_color，lossless/mipmaps，不改变全局或 ART-02 过滤。
- 喷漆只重用已校验的 ambientCG Metal028 CC0 原始 NormalGL/Roughness，未修改 ART-02 成品图。下载来源、许可、原图和压缩包 SHA、派生参数、尺寸/大小及每张输出 SHA 在 `material_provenance.json`。地面随机种子 66，抛光可见掩膜约 3.50%、有效 roughness 最大减少 0.0392；门边约 1.94%、最大减少 0.0262。只改 roughness，没有白色划痕、锈、油污或 Albedo 大斑。
- `灰盒环境/基础收边` 新增后、左、右三条无碰撞 MeshInstance3D，共享 3.396×0.035×0.002m BoxMesh；底边 Y=0，墙内表面相隔 1mm。省略主台遮挡的前条和摄影棚视角外的门上横条；不改变原门洞、门扇运动包络或通行边界。
- PLAN v1 的现状描述漏掉玩家后墙外 `操作台占位/电梯门` 旧静态 CSG（Z=2.85；后墙中心 Z=1.8）。它没有材质、动画或碰撞，也不是业务乘客舱门，本轮保持。正式业务门仍在 X=100 的摄影棚，经原 320×240 feed 观察；CAM01 朝舱门，CAM02 朝门外，不为材质验收改锚点。
- 同路径重导入六张 PNG 后，外部材质引用继续生效，无 Gameplay 重接。玩家 FOV70、监控 FOV60、Camera/Viewport/CRT/CASE、原灯光和 WorldEnvironment 保持；项目 viewport 配置 2560×1080，当前设备正式 framebuffer 实测 2560×1440，二者在验收记录中区分。固定视角地面大多在画外，只在转向角落少量可见；微表面与最终质感仍需用户实机判断。

重建需 Python、Pillow 12.3.0、NumPy 2.3.5 与 provenance 记录中 SHA 匹配的原始包；包放在仓库外，不提交下载缓存：

```powershell
python art_source/elevator_cabin_texture_source.py assets/art/textures/elevator_cabin_v1 --source-archive <仓库外路径>/Metal028_1K-PNG.zip
```

生成器拒绝不匹配的源 SHA；重建后比较输出 hash，再按上述新 PNG 导入配置 reimport。资源元数据/EOL 收尾在 Editor 关闭时执行，原生日志与 Godot AI 日志共同复核；自动逻辑验证、视觉运行时自检、用户体验验收的实际状态以 #66 最新 REVIEW 为准。
