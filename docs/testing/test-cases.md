# PinShot 测试用例清单

- 版本范围：`0.3.2`
- 最近更新：`2026-03-26`
- 工作区：`/Users/yaolijun/Documents/PinShot`

## 自动化用例

这些用例由仓库内置检查入口执行：

```bash
swift run PinShot --unit-check
swift run PinShot --integration-check
swift run PinShot --self-check
swift run PinShot --acceptance-check
swift run PinShot --all-checks
```

### 单元测试用例

| ID | 层级 | 检查点 | 执行入口 | 期望结果 |
| --- | --- | --- | --- | --- |
| UT-001 | Unit | 开机自启动默认值 | `--unit-check` | `launchAtLoginEnabled == true` |
| UT-002 | Unit | 快捷键配置持久化 | `--unit-check` | 保存后读取结果一致 |
| UT-003 | Unit | 非法快捷键配置回退 | `--unit-check` | 读取结果回退到默认快捷键 |
| UT-004 | Unit | OCR 历史标题裁剪 | `--unit-check` | 标题去除首尾空白并截取前缀 |
| UT-005 | Unit | OCR 占位文本回退标题 | `--unit-check` | 标题回退为 `Capture <time>` |
| UT-006 | Unit | 截图初始摆放边界 | `--unit-check` | 截图矩形被限制在可视区域内 |
| UT-007 | Unit | 操作面板底部翻转 | `--unit-check` | 靠近底边时面板显示到锚点下方 |
| UT-008 | Unit | Pin 面板尺寸约束 | `--unit-check` | 编辑态尺寸仍位于可视区内 |
| UT-009 | Unit | 修饰键 Carbon 映射 | `--unit-check` | `command/shift/option/control` 全部保留 |
| UT-010 | Unit | 快捷键展示文案顺序 | `--unit-check` | 顺序固定为 `Command + Shift + Option + Control + Key` 子集 |
| UT-011 | Unit | 未知按键展示兜底 | `--unit-check` | 返回 `KeyCode <n>` |
| UT-012 | Unit | 无效 OCR 文本不生成翻译计划 | `--unit-check` | 返回 `nil` |
| UT-013 | Unit | 英文翻译方向 | `--unit-check` | 规划为 `English -> Chinese (Simplified)` |
| UT-014 | Unit | 中文翻译方向 | `--unit-check` | 规划为 `Chinese (Simplified) -> English` |

### 集成测试用例

| ID | 层级 | 检查点 | 执行入口 | 期望结果 |
| --- | --- | --- | --- | --- |
| IT-001 | Integration | 标注渲染 PNG 导出 | `--integration-check` | 可生成非空 PNG 数据 |
| IT-002 | Integration | 标注导出内容发生变化 | `--integration-check` | 导出 PNG 与原始图片数据不同 |
| IT-003 | Integration | 马赛克渲染 | `--integration-check` | 可对归一化区域生成有效 CGImage |

### 系统测试用例

| ID | 层级 | 检查点 | 执行入口 | 期望结果 |
| --- | --- | --- | --- | --- |
| ST-001 | System | 偏好设置自检 | `--self-check` | 默认值与快捷键读写通过 |
| ST-002 | System | 截图标题与摆放自检 | `--self-check` | 标题、Chooser、摆放逻辑通过 |
| ST-003 | System | Pin 面板布局自检 | `--self-check` | 普通态与编辑态布局通过 |
| ST-004 | System | 开机自启动环境自检 | `--self-check` | `isSupported` 与运行环境状态一致 |

### 验收测试用例

| ID | 层级 | 检查点 | 执行入口 | 期望结果 |
| --- | --- | --- | --- | --- |
| AT-001 | Acceptance | 快捷键设置工作流 | `--acceptance-check` | 业务偏好可按用户动作保存并恢复 |
| AT-002 | Acceptance | 标注后导出工作流 | `--acceptance-check` | 标注图可渲染、导出、写盘并回读 |
| AT-003 | Acceptance | OCR 翻译规划工作流 | `--acceptance-check` | 中英文识别后翻译方向符合产品预期 |
| AT-004 | Acceptance | Pin 编辑面板布局工作流 | `--acceptance-check` | 编辑态尺寸在屏幕内且保留工具区空间 |

## 手工回归用例

下面这些是真实 UI / 系统权限相关场景，适合发版前手工跑一轮。

| ID | 层级 | 操作步骤 | 期望结果 |
| --- | --- | --- | --- |
| MT-001 | Manual | 启动 `PinShot.app` | 菜单栏出现 PinShot 图标 |
| MT-002 | Manual | 按默认快捷键 `Command + Shift + 2` | 出现系统原生框选截图交互 |
| MT-003 | Manual | 截图后选择 `Pin` | 贴图出现在原位置并置顶 |
| MT-004 | Manual | 在贴图上拖动、滚轮/触控板缩放、调透明度 | 拖动流畅，缩放生效，透明度立即更新 |
| MT-005 | Manual | 用 `Samples/ocr-demo.txt` 做 OCR 对比 | 识别结果与样例文本主体一致 |
| MT-006 | Manual | 触发自动翻译 | 中英文翻译方向符合界面文案 |
| MT-007 | Manual | 使用矩形、文字、马赛克工具后导出图片 | 导出的 PNG 含标注内容 |
| MT-008 | Manual | 菜单中重新打开最近一张截图 | 历史截图能再次打开并可继续编辑 |
| MT-009 | Manual | 退出并重新启动 App | 快捷键和开机启动偏好保持不变 |

## 样例数据

- OCR 文本样例：`/Users/yaolijun/Documents/PinShot/Samples/ocr-demo.txt:1`
- 手工回归清单：`/Users/yaolijun/Documents/PinShot/Samples/workflow-checklist.md:1`

## 自动化实现位置

- 统一检查入口：`/Users/yaolijun/Documents/PinShot/Sources/PinShot/QualityCheckRunner.swift:7`
- 验收检查实现：`/Users/yaolijun/Documents/PinShot/Sources/PinShot/AcceptanceCheckRunner.swift:6`
- 系统自检实现：`/Users/yaolijun/Documents/PinShot/Sources/PinShot/SelfCheckRunner.swift:5`
