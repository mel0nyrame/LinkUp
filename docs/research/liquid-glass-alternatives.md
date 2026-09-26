# Flutter Android 玻璃效果替代方案调查

调查日期：2026-09-26。范围：LinkUp 的 Android 界面；只读调查，未运行构建、测试或真机性能采样。下面的“性能”若无设备数据，均为 API 和绘制路径推断，不能当成帧率结论。

## 项目现状与判断标准

项目锁定 Flutter 3.47.5，`liquid_glass_renderer` 0.2.0-dev.4。[`pubspec.yaml`](../../pubspec.yaml)；[`pubspec.lock`](../../pubspec.lock)。概况页状态卡和两页共用的浮动底部导航各调用一次 `LiquidGlass.withOwnLayer`；前者在滚动内容内，后者覆盖滚动内容。[`StatusCard.dart`](../../lib/components/StatusCard.dart)；[`MainNavigation.dart`](../../lib/navigation/MainNavigation.dart)。因此设置页也持续滑动卡这一现象，优先关联共用导航层；这仍是待 Profile 验证的推断。

现用包的作者明确标为 **experimental**；真实折射效果要求 Impeller，作者提示 GPU 计算、纹理内存、多个独立层及移动形状的成本，并提供 `FakeGlass` 作为无折射的轻量选项。[官方包说明](https://pub.dev/packages/liquid_glass_renderer)。Flutter 文档说明 Android API 29+ 默认使用 Impeller；更低 API 或不支持 Vulkan 的设备会回退到旧 OpenGL 渲染器。[Flutter Impeller 文档](https://docs.flutter.dev/perf/impeller)。这意味着不同设备可能显示不同的玻璃效果；仅凭包页不能确定具体机型的卡顿来源。

## 候选对比

| 候选 | 实现与视觉上限 | 兼容性与维护信号 | 性能证据及本项目适配 |
| --- | --- | --- | --- |
| **项目内自建 Flutter 毛玻璃组件** | `ClipRRect` 限定区域 + `BackdropFilter(ImageFilter.blur)` + 半透明颜色、渐变描边和轻微高光，可做精细的磨砂玻璃；没有液态折射。`ImageFiltered` 只过滤自己的 child，不能替代覆盖滚动内容时的背景模糊。[BackdropFilter API](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)；[ImageFiltered API](https://api.flutter.dev/flutter/widgets/ImageFiltered-class.html)。 | 只用 Flutter 自带 API，无第三方 shader 和新增依赖；仍应在目标 Android 设备检查视觉和性能。[Flutter API](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)。 | 可精确控制模糊范围、强度、启用条件。Flutter 文档说明未裁剪的 `BackdropFilter` 会作用于整个屏幕，并建议多个**不重叠**滤镜使用共享 `BackdropKey`/`BackdropGroup`；重叠区域共享 key 可能错误。它仍会采样背景，不能宣称一定达到 120 Hz。[BackdropFilter API](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)；[BackdropGroup API](https://api.flutter.dev/flutter/widgets/BackdropGroup-class.html)。 |
| **`glass_kit` 4.0.2** | 提供 `GlassContainer.clearGlass/frostedGlass`、渐变和边框。其 API 与源码显示底层仍是 `BackdropFilter`、`ClipRRect`/`ClipOval` 和 `CustomPaint`，属于毛玻璃封装，无液态折射。[包页](https://pub.dev/packages/glass_kit)；[API](https://pub.dev/documentation/glass_kit/latest/glass_kit/GlassContainer-class.html)；[源码](https://github.com/bharat-1809/glass_kit/blob/main/lib/src/glass_container.dart)。 | pub.dev 当前显示 4.0.2、六平台、约 535 likes、12k 周下载量，距上次发布约 12 个月；这些是采用/维护线索，不是质量或性能保证。[pub.dev score](https://pub.dev/packages/glass_kit/score)。 | 本项目只需两个定制表面，包的预设能省样式代码，但绘制仍走 Flutter 原生背景滤镜，未找到与项目自建实现的可复现性能对比；不能推断它更快。[源码](https://github.com/bharat-1809/glass_kit/blob/main/lib/src/glass_container.dart)。 |
| **`liquid_glass_plus` 0.3.2** | 从现用方案的上游分叉，仍保留 Impeller 自定义 shader 的真实折射，并为 Skia 提供 `BackdropFilter` 近似模式；接近现有视觉模型。[包页](https://pub.dev/packages/liquid_glass_plus)；[仓库](https://github.com/vespr-wallet/flutter_liquid_glass_plus)。 | 包声明 Flutter ≥3.32.4，本项目的 3.47.5 满足；pub.dev 当前约 4 likes、152 周下载量，距上次发布约 2 个月。[pubspec](https://github.com/vespr-wallet/flutter_liquid_glass_plus/blob/main/packages/liquid_glass_renderer/pubspec.yaml)；[pub.dev score](https://pub.dev/packages/liquid_glass_plus/score)。 | 作者称 Skia 近似效果更接近 Impeller，但在 Impeller 上强制 fake 模式性能相近或略差；未提供可复现实测。由于仍沿用相似折射路径，直接换包没有足够证据能解决滑动卡。[官方说明](https://pub.dev/packages/liquid_glass_plus)。 |
| **`just_liquid_glass` 0.8.0** | SDF blob 合并形状，Impeller 上使用 `BackdropFilter`、`ImageFilter.shader` 和高斯模糊组合形成折射；不支持时转为无背景模糊的平面填充。其形状不是自动按 child 成型，迁移现有两处卡片需要自行描述 blob/布局。[包页](https://pub.dev/packages/just_liquid_glass)；[渲染源码](https://github.com/makoConstruct/just_liquid_glass/blob/main/lib/src/glass_layer.dart)。 | 声明 Flutter ≥3.41、Dart ^3.12，项目锁定版本满足 Flutter 下限。包页目前显示 0.8.0、0 likes、约 20 周下载量、发布约 40 天；作者公开称代码全部由模型生成，仍需独立审查和设备验证。[pubspec](https://github.com/makoConstruct/just_liquid_glass/blob/main/pubspec.yaml)；[pub.dev score](https://pub.dev/packages/just_liquid_glass/score)；[官方说明](https://pub.dev/packages/just_liquid_glass)。 | 源码支持其“不为几何单独生成中间纹理”的实现描述，但**背景滤镜仍存在**；作者建议多层共享 backdrop key，同时承认重叠区域可能不准确。这只能说明它避开某类纹理分配，不能证明本项目滚动更快。首次 shader 未加载时只显示 child，预加载可避免这一视觉缺口，却需要核查首屏时延影响。[源码](https://github.com/makoConstruct/just_liquid_glass/blob/main/lib/src/glass_layer.dart)；[官方说明](https://pub.dev/packages/just_liquid_glass)。 |

另一个低成本对照是现有包自带的 `FakeGlass`。作者称其用 backdrop filter 代替折射 shader、视觉保真度较低但更轻量；这减少迁移风险，仍需测量滚动时的背景模糊开销。[现用包说明](https://pub.dev/packages/liquid_glass_renderer)。

## 建议的项目取舍

1. **首选：项目内小组件做定制毛玻璃**。底部导航保留现有尺寸和交互，先用窄范围、较低 sigma 的 `BackdropFilter` 加轻微边框/高光；状态卡先采用无背景采样的半透明或实色渐变表面，因为它随页面滚动。若目标是优先保证 120 Hz，可把导航也做成无背景采样的半透明表面。这里的性能预期基于减少背景读取和滤镜范围的绘制路径推断，需要真机检验。[Flutter BackdropFilter API](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)；[Flutter Performance View](https://docs.flutter.dev/tools/devtools/performance)。
2. **若希望快速验证视觉**，先在两个位置分别试现有包的 `FakeGlass`，或以 `glass_kit` 做毛玻璃样式样板。`glass_kit` 的意义是现成外观 API，并无已证实的速度优势。[现用包说明](https://pub.dev/packages/liquid_glass_renderer)；[`glass_kit` API](https://pub.dev/documentation/glass_kit/latest/glass_kit/GlassContainer-class.html)。
3. **若“明显液态折射”是必须保留的效果**，`just_liquid_glass` 比现用包更值得做受控试验：有不同的几何路径及跨后端平面回退。不过它处于早期，低采用量且作者自述模型生成，暂不建议未经源码复核与多机测试就替换生产实现。`liquid_glass_plus` 的分叉改动目前不足以证明能解决滑动性能。[`just_liquid_glass` 包页](https://pub.dev/packages/just_liquid_glass)；[`liquid_glass_plus` 包页](https://pub.dev/packages/liquid_glass_plus)。

## 如何验证这些取舍

保持同一台真机、同一 Flutter 版本、同一设置页滑动动作，分别测现用、无背景采样、项目内 `BackdropFilter`、现用 `FakeGlass`；只有确实需要折射时再加入 `just_liquid_glass`。在 Profile 模式记录 UI/Raster 帧耗时、超预算帧比例及首屏表现，分别查看导航覆盖滚动与概况页状态卡。Flutter DevTools 可区分 UI 与 Raster 负担，并可临时关闭裁剪、透明、阴影等层效果定位成本；任何包的“高性能”描述都不能替代这组数据。[Flutter Performance View](https://docs.flutter.dev/tools/devtools/performance)；[Flutter UI 性能指南](https://docs.flutter.dev/perf/ui-performance)。
