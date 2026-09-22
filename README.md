# PinShot

一个原生 macOS 截图与贴图工具。它把常用截图、置顶、标注、OCR、翻译和隐私打码放在同一条轻量流程中，适合日常沟通、文档整理和快速分享。

> 当前项目以 Swift Package 形式提供，适合本地运行和继续开发。

## 功能一览

- 智能区域截图：自动识别鼠标下的窗口和 UI 元素，也可拖拽自由框选，支持多显示器
- 截图后选择 `Quick Edit`、`Pin` 或 `Copy`
- 多张截图可分别置顶、拖动、缩放和调节透明度
- 标注工具：画笔、矩形、箭头、文字与马赛克
- 本地 OCR，支持识别中英文文字
- 系统翻译：中文与英文之间自动选择目标语言
- Smart Mask：识别手机号、邮箱、链接、长编号和二维码，并生成可编辑的马赛克
- 复制、保存 PNG/JPEG、导出 OCR/翻译文本，以及导出截图资料包
- 菜单栏历史记录，支持搜索、筛选和重新打开
- 自定义全局快捷键与开机自启动

## 系统要求

- macOS 14.1 或更高版本
- Xcode Command Line Tools，或完整 Xcode
- macOS 15 或更高版本可使用系统翻译；较低版本会保留截图、贴图、OCR、标注和导出等核心能力

## 快速开始

在终端运行：

```bash
git clone https://github.com/yljcode1/PinShot.git
cd PinShot
swift run
```

PinShot 是菜单栏应用。启动后，在 Mac 顶部菜单栏找到图钉图标，点击即可打开控制面板。

开发模式下请保持 `swift run` 所在终端开启；按 `Control + C` 可退出应用。

## 首次授权

首次使用时，按照应用内引导授权：

| 权限 | 用途 | 位置 |
| --- | --- | --- |
| 屏幕录制 | 截取屏幕内容 | `系统设置 > 隐私与安全性 > 屏幕录制` |
| 辅助功能 | 让全局快捷键在部分环境中稳定工作 | `系统设置 > 隐私与安全性 > 辅助功能` |

截图空白、无法截图或快捷键没有反应时，优先检查以上两项权限。授予权限后请退出并重新启动 PinShot。

## 基本使用

### 1. 截图

- 默认快捷键是 `Command + Shift + 2`，可在菜单栏面板的 `Global Hotkey` 中修改。
- 也可以点击 `Capture Selection`。移动鼠标会自动识别窗口或 UI 元素，单击即可截图；按 `Tab` 切换父级范围，拖拽可自由框选。
- 按 `Esc` 或再次按截图快捷键可取消当前截图。
- 截图完成后，图片会先以置顶贴图出现，并显示以下操作：

| 操作 | 说明 |
| --- | --- |
| `Quick Edit` | 打开标注、OCR、翻译、缩放和导出工具 |
| `Pin` | 保留图片为桌面置顶贴图 |
| `Copy` | 将原始截图复制到剪贴板 |

如果只想复制，使用 `Copy Selection` 可以跳过贴图编辑流程。

### 2. 贴图与缩放

- 直接拖动贴图可调整位置。
- 点击贴图右上角的工具图标，可展开或收起编辑工具栏。
- 工具栏中的 `+`、`-` 和 `100%` 可放大、缩小或还原图片。
- 也可在贴图上使用双指缩放手势。
- 在 Inspector 中可单独调整每张贴图的透明度。

### 3. 标注与隐私打码

在 `Quick Edit` 的工具栏中选择画笔、矩形、箭头、文字或马赛克，再在图片上操作。

`Smart Mask` 会扫描截图中的手机号、邮箱、链接、长编号和二维码，自动添加马赛克。识别结果是可编辑标注：可以继续调整、撤销，或在导出前清空后重新处理。建议在分享前人工检查一次打码范围。

### 4. OCR、翻译和导出

- 打开 Inspector 查看已识别文字。
- 有翻译能力的系统会显示翻译操作；中文内容默认翻译为英文，英文内容默认翻译为中文。
- 可复制图片、OCR 文本或翻译文本。
- 导出支持 PNG、JPEG、文本和资料包；资料包包含图片、可用文本与元数据。

### 5. 历史记录

菜单栏面板的 `Pinned History` 会保留本次运行期间的截图。你可以按 OCR、已翻译、已标注筛选，搜索内容，并重新打开、导出或移除截图。

## 快捷操作

| 操作 | 入口 |
| --- | --- |
| 框选截图 | `Command + Shift + 2` 或 `Capture Selection` |
| 直接复制框选 | `Copy Selection` |
| 重新打开最近一张贴图 | `Reopen Latest` |
| 关闭所有贴图 | `Clear All Pins` |
| 修改全局快捷键 | 菜单栏面板的 `Global Hotkey` |
| 设置开机自启动 | 菜单栏面板的 `Preferences` |

## 测试

```bash
swift run PinShot --unit-check
swift run PinShot --integration-check
swift run PinShot --self-check
swift run PinShot --acceptance-check
swift run PinShot --all-checks
```

- [测试用例清单](docs/testing/test-cases.md)
- [Excel 用例表](docs/testing/PinShot-test-cases.xlsx)
- [测试报告](docs/testing/test-report-2026-03-26-feature-refresh.md)

## 当前范围

- PinShot 目前不提供滚动/长截图功能。
- 翻译依赖 macOS 系统能力，macOS 14.1 环境会自动降级，不影响其他功能。
- Smart Mask 用于辅助发现敏感信息，不应替代人工复核。

## 开发说明

```bash
swift build
swift run
```

项目使用 SwiftUI 和 AppKit 构建。欢迎提交 Issue 或 Pull Request，尤其是多显示器、权限流程、OCR 准确性和贴图交互方面的改进。
