# PinShot 0.3.5

## 更新内容

- 新增 Smart Mask，支持自动识别手机号、邮箱、链接、长编号与二维码并批量打码
- 优化贴图编辑工具栏，为小尺寸贴图补充更紧凑的操作布局
- 将最低系统版本降级到 `macOS 14.1`，并在 `macOS 14.x` 上对系统翻译能力做安全降级
- 补充敏感信息打码与兼容性相关检查，提升发布稳定性

## 验证

- `swift build`
- `swift run PinShot --all-checks`
- `swift build -c release --product PinShot`
