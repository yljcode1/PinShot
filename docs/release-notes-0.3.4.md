# PinShot 0.3.4

## 更新内容

- 补齐 `RELEASE.md` 的正式发布流程说明，方便后续稳定执行合并、打包与发布
- 新增可直接运行的 DMG 构建脚本，支持生成带安装指引背景图的发布镜像
- 新增 DMG 背景图生成脚本，统一安装包视觉与拖拽安装提示

## 验证

- `swift build`
- `swift run PinShot --all-checks`
- `swift build -c release --product PinShot`
