# PinShot

一个用 SwiftUI 构建的 macOS 小工具，目标是覆盖 Snipaste 的核心高频流程，当前已支持：

- 自定义全局快捷键截图
- 多截图结果置顶悬浮
- 本地 OCR 文字识别
- OCR 后自动翻译触发
- 图片复制与保存
- 框选后可直接复制到剪贴板
- 原生多屏框选截图
- 截图后可继续选择 Quick Edit / Pin / Copy
- 开机自启动开关（默认开启）
- 历史截图再次唤起
- 透明度调节
- 贴图马赛克打码

## 当前实现

- 默认全局快捷键：`Command + Shift + 2`，可在菜单栏里改
- 触发后调用系统框选截图
- 每次截图会先在原位置生成置顶贴图，再弹出 `Quick Edit / Pin / Copy`
- 自动识别中文和英文文字
- 支持复制图片、复制识别结果、保存 PNG
- 新增“Copy Selection” 快捷操作：框选后直接复制到剪贴板
- 使用系统原生多屏框选，支持外接屏稳定截图
- 提供开机自启动开关，打包安装后默认随登录自动启动
- 支持把 OCR 文字自动翻译成中文或英文
- 菜单栏中保留最近历史，可再次打开
- 每个贴图窗口都可以单独调节透明度
- 新增马赛克工具：在贴图上框选区域即可快速打码

## 运行

```bash
swift run
```

## 测试

```bash
swift run PinShot --unit-check
swift run PinShot --integration-check
swift run PinShot --self-check
swift run PinShot --acceptance-check
swift run PinShot --all-checks
```

- 测试用例清单：`/Users/yaolijun/Documents/PinShot/docs/testing/test-cases.md:1`
- Excel 用例表：`/Users/yaolijun/Documents/PinShot/docs/testing/PinShot-test-cases.xlsx`
- 本轮测试报告：`/Users/yaolijun/Documents/PinShot/docs/testing/test-report-0.3.2.md:1`

需要 `macOS 15+`。

首次使用时，macOS 可能会要求你授予：

- 屏幕录制权限：用于截图
- 辅助功能权限：某些系统环境下全局快捷键可能需要

## 说明

这个仓库目前是 Swift Package 形式，方便在只有 Command Line Tools 的环境里直接编译。

如果你要继续往 “更像 Snipaste” 的方向做，下一批建议功能是：

- 贴图缩放/旋转与双击还原
- 取色器
- 更多快捷操作
- 标注工具继续完善
- 多屏幕细节体验优化
