# 开发与验证手册

以下命令从 Flutter 仓库根目录执行。使用 Flutter 3.50.0、Dart 3.14.0 和 Node.js 22.13 以上版本。两个 Node 服务均使用标准库，可以直接运行测试或启动服务。

## 原生开发

```powershell
flutter doctor -v
flutter pub get
flutter devices
flutter run -d windows
flutter run -d 'ANDROID_DEVICE_ID'
```

运行 Android 时，将 `ANDROID_DEVICE_ID` 替换为 `flutter devices` 列出的 ID。

Windows 需要 Visual Studio 的 C++ 桌面开发组件和 Windows SDK。插件注册需要系统支持符号链接。已有可用的本机依赖解析结果时，分析、测试和构建可加 `--no-pub`。需要重新解析依赖时，用 `flutter pub get` 和锁文件对应的包源，并检查 `pubspec.lock` 是否发生了预期之外的改动。

用 Windows PowerShell 5.1 读写源码或文档时显式指定 UTF-8，并检查包含中文的差异，避免系统代码页改写文案。

Android 需要已安装的 Android SDK 和 JDK 17。项目和 Pub 缓存在 Windows 不同磁盘时，Kotlin 增量编译可能无法计算相对路径。遇到 `Could not close incremental caches` 时，可把 `PUB_CACHE` 指向项目所在磁盘的缓存目录并重新执行 `flutter pub get`。`android/gradle.properties` 当前禁用了 Kotlin 增量编译，Gradle Wrapper 下载地址以 `android/gradle/wrapper/gradle-wrapper.properties` 为准。

如果终端可以访问 Maven 仓库而 Gradle 长时间等待下载，检查 JVM 的网络代理是否与终端一致。可以向 Gradle Wrapper 临时传入 `-Dhttps.proxyHost=...` 和 `-Dhttps.proxyPort=...`，或在开发者本机的 Gradle 配置中设置代理。

```powershell
flutter build apk --debug
```

调试 APK 输出至 `build/app/outputs/flutter-apk/app-debug.apk`。Android 应用 ID 是 `com.lovemachine.deepseek_chat`。当前 release 构建配置使用调试签名，正式发布需要设置发布签名并单独验证。真机上的 `127.0.0.1` 指向手机本身，连接开发机上的账号服务时要使用真机可达的 HTTPS 地址或明确配置调试端口转发。

## 账号服务

从仓库根目录进入 `server/`，将 `.env.example` 复制为 `.env`，配置 `OPENAI_API_KEY`、以 `/v1` 结尾的 `OPENAI_BASE_URL`，按需开启 `ALLOW_REGISTRATION`。浏览器跨域访问时在 `CORS_ORIGINS` 中填页面的完整源。

```powershell
Set-Location server
node --env-file=.env --disable-warning=ExperimentalWarning src/index.js
```

`server/README.md` 定义路由、凭据、数据库、请求大小和部署边界。默认 SQLite 文件位于 `server/data/`，现有数据库随本机部署保留。仓库忽略各服务的 `.env` 与账号数据库。验证客户端时使用本地假账号和测试凭据。

## 浏览器模拟联调

以下三个代码块分别在不同终端从仓库根目录运行。使用 `proxy/dev` 的模拟上游可以重现 DeepSeek 思考、搜索引用和 Markdown 逐步返回。

```powershell
node proxy/dev/mock-upstream.mjs
```

```powershell
$env:DEEPSEEK_API_KEY = 'local-demo-key'
$env:PROXY_TOKEN = 'client-token'
$env:DEEPSEEK_API_ORIGIN = 'http://127.0.0.1:8788'
node proxy/src/index.mjs
```

```powershell
flutter build web --dart-define=DEMO_UI=true --no-web-resources-cdn
node tool/serve_web.mjs build/web
```

打开 `http://127.0.0.1:8090`。`/mobile` 提供多种手机视口外框。`DEMO_UI` 仅在 Web 注入示例会话和本地代理配置。改用其他本地地址时传入 `--dart-define=PROXY_ORIGIN=...`，需要覆盖令牌时传入本地测试值 `--dart-define=PROXY_TOKEN=...`。Dart define 会编入 Web 文件，只能放测试值。

验证浏览器操作时，Flutter 语义树可能先显示 `Enable accessibility`。可将该入口聚焦后按 Enter，再检查业务节点。输入后实际提交并确认目标 HTTP 请求与页面结果，尤其是输入框的 `fill` 只更新了语义节点的情况。验证流式效果时检查响应结束前已有可见文本，再确认完成状态、正文和引用。

Web 预览的会话和附件使用内存存储，刷新后重置演示数据。用于 API 与账户联调时应配合本地假上游，正式服务的用户凭据与密钥由本地环境单独管理。

如果浏览器报告连接被拒绝，先检查预览服务和模拟上游是否仍在监听。端到端检查结束后由启动服务的任务负责关闭。Node 测试使用独立的临时监听端口和 SQLite 数据库，清理完成后才能删除数据库所在的临时目录。

## 验证命令

```powershell
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
npm --prefix server run check
npm --prefix server test
npm --prefix proxy test
```

Flutter 依赖已解析时可使用 `--no-pub`。修改账号、协议或代理后，根据受影响路径追加浏览器或原生端联调。发布候选还应在对应设备验证安装、账号连接、附件选取、流式取消、存储恢复和主题布局。

测试覆盖及验证结论的适用范围见[工程交接报告](ENGINEERING_HANDOFF.md)。模型协议单测和本机模拟网络只能证明已覆盖的应用行为，服务商真实模型、Android 真机、Windows 发布包和生产负载需要各自的验收。
