# SimulateLocation

无需手动编辑 GPX 文件的 iPhone 到 Xcode 交互式模拟定位工具。

[English](README.md)

SimulateLocation 由一个 iOS App 和一个 Mac bridge 组成。iPhone App 负责在 Apple 地图上交互选点，Mac bridge 负责把选中的坐标写入 GPX 文件，并尽量自动应用到 Xcode 的定位模拟流程。

## 功能

- 使用 Apple Maps 直接选择任意位置。
- 支持定位并选择手机真实当前位置。
- 通过 Bonjour 自动发现 Mac bridge。
- 可使用 macOS 菜单栏控制器启动/停止 bridge，不需要一直保留终端窗口。
- 生成固定文件 `Generated/SelectedLocation.gpx`，供 Xcode 菜单识别。
- 在 `Generated/History/` 保存带分钟时间戳的历史 GPX。
- 通过 `simctl location set` 应用到已启动的 iOS Simulator。
- 尝试自动切换 Xcode 的 `Debug > Simulate Location` 菜单。
- 在中国大陆自动处理 WGS84 和 GCJ-02 坐标转换，让地图标记、手机蓝点和 GPX 输出保持一致。

## 环境要求

- 安装 Xcode 的 macOS。
- 用于运行 App 的 iPhone，或用于开发调试的 iOS Simulator。
- 使用真机时，iPhone 和 Mac 需要在同一个局域网。
- iOS App 需要允许本地网络权限。
- Mac 上的 Xcode 菜单自动化需要辅助功能权限。

## 快速开始

推荐的菜单栏流程：

1. 用 Xcode 打开 `SimulateLocation.xcodeproj`。
2. 选择 `SimulateLocationMenuBar` scheme，并在 **My Mac** 上运行。
3. 在菜单栏中点击 **启动**。它会启动 `Scripts/location-bridge` 并打开当前 Xcode 项目。
4. 切换到 `SimulateLocation` scheme，并选择你的 iPhone 作为运行设备。
5. 在 `Signing & Capabilities` 中配置你的开发者 Team。
6. 运行 iPhone App。
7. iPhone 弹出权限时，允许本地网络访问。
8. 等待 App 显示已连接 Mac bridge。
9. 在地图上点击目标位置，然后点击“自动应用”。

命令行备选流程：

1. 启动 Mac bridge：

   ```bash
   ./Scripts/location-bridge
   ```

2. 用 Xcode 打开 `SimulateLocation.xcodeproj`。
3. 选择你的 iPhone 作为运行设备。
4. 在 `Signing & Capabilities` 中配置你的开发者 Team。
5. 运行 App。
6. iPhone 弹出权限时，允许本地网络访问。
7. 等待 App 显示已连接 Mac bridge。
8. 在地图上点击目标位置，然后点击“自动应用”。

## 菜单栏控制器

`SimulateLocationMenuBar` macOS target 提供三个操作：

- **启动**：在默认端口启动 bridge，处理端口冲突，并打开 `SimulateLocation.xcodeproj`。
- **停止**：停止当前运行的 bridge。
- **退出**：先停止当前 bridge，再退出菜单栏 App。

菜单会显示当前 bridge 状态。如果默认端口上运行的是旧的 SimulateLocation bridge，会自动停止旧进程并复用端口。如果端口被其他进程占用，控制器会询问是否强制关闭或改用下一个可用端口。退出控制器不会强制关闭 Xcode。

## Mac Bridge

bridge 默认监听 `0.0.0.0:8765`，并通过 Bonjour 广播 `_location-gpx._tcp.` 服务。

生成文件：

- `Generated/SelectedLocation.gpx`：固定文件名，供 Xcode 定位模拟菜单使用。
- `Generated/History/SelectedLocation_MM-dd_HH:mm.gpx`：每次应用时保存的历史文件。
- `Generated/latest.json`：最近一次坐标元数据，不纳入 Git。

常用参数：

```bash
./Scripts/location-bridge --port 8765
./Scripts/location-bridge --no-xcode
./Scripts/location-bridge --no-simulator
./Scripts/location-bridge --stop
```

Xcode 菜单自动化通过 `osascript` 执行 AppleScript。如果 macOS 拦截，请在 `System Settings > Privacy & Security > Accessibility` 中允许启动 bridge 的终端应用或进程。没有该权限时，bridge 仍会写入 GPX 并更新 Simulator，但 Xcode 可能不会自动切换当前模拟位置。

如果 bridge 是通过 launchd job 或其他脱离终端的后台进程启动的，在另一个终端里按 `Control+C` 只会停止那个前台命令，不会关闭真正监听端口的 bridge。运行 `./Scripts/location-bridge --stop` 可以移除已知 launchd job，并停止指定端口上的 bridge 进程。

## 当前位置

“当前位置”按钮会读取手机真实 GPS，选中该位置并移动地图。运行这个选择器 App 时，不要给选择器本身开启 Xcode Location Simulation；如果 Xcode 覆盖了手机真实定位，App 会拒绝这个模拟定位结果。

## 中国大陆坐标

中国大陆 Apple Maps 底图使用 GCJ-02 显示坐标，而 Xcode GPX 需要 WGS84/GPS 坐标。SimulateLocation 内部会同时保存两套坐标：

- 地图上的红色标记使用地图显示坐标。
- 发送给 Mac bridge 的 GPX 使用 WGS84/GPS 坐标。

在中国大陆以外，坐标不会做偏移转换。

## 限制

iOS App 不能直接写入 Mac 项目目录，也不能独立修改整台手机的系统定位。本项目通过本机 Mac bridge 和 Xcode 现有调试链路实现自动化。完整自动应用依赖 Xcode 当前状态、正在调试的设备、项目中存在 GPX 文件，以及 macOS 辅助功能权限。

## 许可证

MIT License，见 [LICENSE](LICENSE)。
