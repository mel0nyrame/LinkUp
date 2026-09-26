# `surface-user/Flutter_liquid_glass` 对 LinkUp 的适用性

调查日期：2026-09-26。只读取上游公开仓库、Flutter 官方文档及 LinkUp 代码；未安装依赖、构建、测试或测量真机帧耗时。上游核对的提交为 [`a0bc51a`](https://github.com/surface-user/Flutter_liquid_glass/tree/a0bc51acf22db1b867294f810157cfeba7e951fb)。性能判断若未标出实测，均为绘制路径推断。

## 结论

**值得作为 LinkUp 的视觉候选做受控对照，但不能直接认定会解决滑动卡顿，也不能认定 Android 兼容性已验证。** 它正好提供了[上一份调查](liquid-glass-alternatives.md)建议的“Flutter 原生定制毛玻璃”成品样式：半透明着色、渐变边缘与柔光高光。用户认可它的观感，是选择它做样板的有效理由。它的视觉目标是模拟 Liquid Glass，作者明确说明**不含真实光学折射**；与现用 `liquid_glass_renderer` 的折射效果不同。[上游 README](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/README.md)；[玻璃表面源码](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/surface.dart)。

## “轻量”具体指什么

运行时依赖只有 Flutter SDK，库代码没有原生插件、平台通道或自定义片元 shader 资源；接入不需改变 Android 原生层。主要渲染由 `ClipRRect`/`ClipOval` 裁剪、`BackdropFilter(ImageFilter.blur)` 背景模糊、`DecoratedBox` 着色、`CustomPaint` 边缘描画与可选阴影组成。若饱和度或对比度不为 1，还会组合颜色滤镜。这里“轻量”可指**依赖和实现路径简单**，不能由此推出 GPU 耗时低。[上游 pubspec](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/pubspec.yaml)；[表面实现](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/surface.dart)；[Flutter `BackdropFilter` 文档](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)。

默认 `GlassStyle` 的背景模糊 sigma 为 12，预设 `subtle` 为 6，`elevatedCard` 为 18。`GlassQuality.low` 令有效模糊上限为 0，从而跳过 `BackdropFilter`；`balanced` 和 `adaptive` 都只是把上限截在 16，`adaptive` **没有按设备性能自动测量或调档**。关闭模糊时源码使用不透明回退色，若要保留半透明观感需实际检查样式和背景渐变。噪点默认关闭；阴影默认开启。[样式预设](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/style.dart)；[性能配置](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/theme.dart)；[表面实现](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/surface.dart)。

库对滤镜做了圆角裁剪，避免无裁剪时整屏过滤；提供 `GlassGroup`，对**不重叠且滤镜参数匹配**的多个表面共享背景滤镜。Flutter 官方也说明背景模糊相对昂贵，共享 `BackdropKey` 可能减少多个滤镜的开销，但重叠表面不应共享。LinkUp 当前只有一处共用导航玻璃和一处概况页状态卡，且位置、模糊参数不同；`GlassGroup` 不应被预期为这里的主要收益。[表面实现](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/surface.dart)；[Flutter `BackdropFilter` 文档](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)；[LinkUp 导航](../../lib/navigation/MainNavigation.dart)；[LinkUp 状态卡](../../lib/components/StatusCard.dart)。

## 兼容性和证据边界

上游声明 Dart ≥3.12、Flutter ≥3.44；LinkUp 声明 Dart ≥3.13.4、Flutter 3.47.5，**版本约束在纸面上相容**。源码使用 Flutter 自带组件，没有直接绑定 Impeller API，因此没有现用折射包那种自定义 shader 路径。不过背景滤镜仍交给 Flutter 的当前渲染后端处理，不能据此保证所有 Android GPU、API 级别或平台视图组合显示一致。Flutter 官方说明 Android API 29+ 默认启用 Impeller，低版本或特定硬件存在渲染后端回退。[上游 pubspec](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/pubspec.yaml)；[LinkUp pubspec](../../pubspec.yaml)；[Flutter Impeller 文档](https://docs.flutter.dev/perf/impeller)；[上游 README 的平台限制](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/README.md)。

上游自己的[验证记录](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/doc/VERIFICATION.md)报告：Flutter 分析、组件与示例 widget tests、Web release 构建和 golden 截图已完成；**Android APK 构建因 NDK 缺文件中止，未做 Android 真机/GPU 帧耗时测量**。所以目前没有可复现的 Android Profile 基准来支持“比现用包更快”或“120 Hz 流畅”的结论，也没有 Android 构建成功记录。其 Web [在线演示](https://lightweight-liquid-glass-lab.marseille-cjh.chatgpt.site)和仓库中的[浅色](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/test/goldens/light.png)、[深色](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/test/goldens/dark.png)、[无模糊回退](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/test/goldens/fallback.png)截图能帮助选外观；演示的 [部署记录](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/doc/DEPLOYMENT.md)称其来自 Flutter Web 示例，不能代替 Android 设备观感或性能证据。本次环境未能打开在线演示，未对实际动效作独立视觉判断。

仓库于 2026-09-17 创建，当前只有 [3 个提交](https://github.com/surface-user/Flutter_liquid_glass/commits/main/)、[无 release](https://github.com/surface-user/Flutter_liquid_glass/releases)、公开 [issue 为 0](https://github.com/surface-user/Flutter_liquid_glass/issues)；这表示维护历史和外部反馈还少，不能把“无 issue”解读为兼容性已获证明。包名在调查时的 [pub.dev API](https://pub.dev/api/packages/lightweight_liquid_glass) 返回 404；上游 README 给出路径或 Git 依赖方式。许可证为 [MIT](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/LICENSE)。

## 对 LinkUp 的具体接入范围与建议

LinkUp 两处现用 `LiquidGlass.withOwnLayer`：共用浮动底部导航位于 `Stack` 顶层，配置 blur 18、圆角 28；概况页状态卡位于滚动内容，配置 blur 14、圆角 20，并包含持续脉冲动画。两处可分别替为上游的 `GlassSurface` 或卡片预设，保留原有布局、点击区域和内容；需重配 `GlassStyle` 的圆角、着色、高光与阴影。上游仅支持圆角矩形或椭圆，不提供现用的 `LiquidRoundedSuperellipse` 轮廓，视觉会略变。替换还涉及 `pubspec.yaml`、锁文件和依赖获取流程；按项目约束，此次**没有执行或实施**。[导航实现](../../lib/navigation/MainNavigation.dart)；[状态卡实现](../../lib/components/StatusCard.dart)；[上游 `GlassSurface`](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/surface.dart)；[上游样式](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/style.dart)。

建议先用**同样两处布局**做小范围候选试验：共用导航优先尝试 `subtle` 或自定义 sigma 6–8 的样式；状态卡优先试关闭背景模糊、保留半透明着色和边缘高光，并检查暗色/浅色下文字可读性。若状态卡无模糊导致上游默认不透明回退不合审美，可直接在 LinkUp 内实现同款无背景采样装饰，避免为了两个表面引入整个组件库。这是基于源码绘制路径的优化假设，仍须同一真机在 Profile 模式比较当前实现、该候选有模糊、该候选无模糊的设置页滚动与首屏表现；分别看 UI/Raster 帧耗时及超预算帧比例。[上游样式与回退](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/lib/src/surface.dart)；[Flutter Performance view](https://docs.flutter.dev/tools/devtools/performance)。

这项替换只改变玻璃表面的绘制。LinkUp 点击图标到首屏的等待还包括 `runApp` 前的日志和系统设置初始化，以及 Android 服务创建独立 FlutterEngine；玻璃库替换不会消除这些等待，启动速度要单独测量和处理。[启动入口](../../lib/main.dart)；[系统设置初始化](../../lib/utils/SystemSettingsUtil.dart)；[后台运行时服务](../../android/app/src/main/kotlin/com/mel0ny/linkup/AuthRuntimeService.kt)。

若正式采用 Git 依赖，宜固定到已审过的[提交 `a0bc51acf22db1b867294f810157cfeba7e951fb`](https://github.com/surface-user/Flutter_liquid_glass/commit/a0bc51acf22db1b867294f810157cfeba7e951fb)，避免默认分支后续变动无意改变界面实现。[上游 Git 接入说明](https://github.com/surface-user/Flutter_liquid_glass/blob/a0bc51acf22db1b867294f810157cfeba7e951fb/README.md)。
