# Codex Whip

一个贴在 Codex 桌面宠物旁边的 macOS 菜单栏应用。任务完成后显示“太棒了！”和“真差劲！”两个按钮，并分别播放摸头或三次皮鞭动画。

## 构建

只需要 macOS Command Line Tools。构建脚本会把编译缓存保存在项目内部，以兼容受限环境：

```bash
cd codex-whip
zsh scripts/build-app.sh
open "dist/Codex Whip.app"
```

宠物定位不读取屏幕画面，也不需要“屏幕录制”权限。鼠标 Hover 仅在已有“辅助功能”授权时生效，应用不会在定位或播放期间主动弹出权限请求；也可以从菜单关闭 Hover。

## 使用

1. 点击菜单栏魔杖图标。
2. 在 Codex 中使用 `/pet` 唤醒桌面宠物并保持可见。
3. 应用会依次读取 WindowServer 窗口元数据、Accessibility 顶层窗口和 Electron 保存的浮窗位置。
4. 选择“检测宠物并显示评价”测试评价面板。
5. 点击评价按钮播放对应动画。

首次启动或再次双击应用时，会显示欢迎面板；因此即使菜单栏图标被刘海或其他图标遮挡，也能确认应用已经运行。

## 任务完成触发

当前 Codex 没有公开稳定的任务完成事件，因此应用提供两个松耦合入口：

```bash
open "codexwhip://task-completed"
```

或者从另一个 macOS 进程发送分布式通知：

```swift
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.codexwhip.taskCompleted"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
```

开发时也可以绕过评价按钮直接试播动画：

```bash
open "codexwhip://play-whip"
open "codexwhip://play-praise"
```

未来 Codex Hook 可直接调用 URL Scheme，不需要修改动画应用。

## 当前边界

- 反应效果是透明覆盖层，不会修改 Codex 宠物自身的骨骼或动画状态。
- 自动定位优先从 `CGWindowListCopyWindowInfo` 读取 Codex 进程的透明浮窗，按宠物浮窗的已知尺寸和层级筛选。
- 如果 WindowServer 没有暴露候选窗口，则读取 Accessibility 顶层窗口；最后尝试 Codex Electron 持久化的 `electron-avatar-overlay-bounds`。
- 不截图、不扫描屏幕像素，也不声明或申请“屏幕录制”权限。
- 定位失败时会明确提示，不会用当前鼠标位置冒充宠物位置。
- 鼠标 Hover 会真实移动系统光标；如果用户在动画期间移动鼠标，应用不会把光标强行拉回。

## 自检

```bash
.build/debug/CodexWhip --self-check
```

该检查同时验证定位管线与鞭子物理模型：手柄长度保持刚性、鞭身距离约束稳定，并且三次抽击都能让鞭梢在蓄力后明显加速。

如果宠物可见但未被识别，可输出 WindowServer 的只读诊断信息：

```bash
.build/debug/CodexWhip --diagnose-pet
```
