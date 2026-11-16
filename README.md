# Lightroom Classic HEIC HDR 导出插件（中文增强版）

这是 [fengshenx/LR_GainMap_HDR_Export_Plugin](https://github.com/fengshenx/LR_GainMap_HDR_Export_Plugin) 的 fork，保留原项目历史并增加中文界面、格式控制和导出保护。当前插件版本为 **1.0.0.8**。

A Chinese-language fork with Apple/ISO gain maps, independent ISO gain-map quality, 8/10-bit base images, gain-map scaling, direct PQ/HLG HDR, and safe output naming. The Swift source and universal macOS executables are included.

## 功能

| 输出模式 | 主图位深 | 增益图 | 可调参数 |
|---|---|---|---|
| Apple 增益图 HEIC | 8 / 10 位 | Apple 格式 | 主图品质、增益图缩放 |
| ISO 增益图 HEIC | 8 / 10 位 | ISO 21496-1 | 主图品质、增益图缩放、独立增益图品质 |
| 直接 PQ HDR HEIC | 固定 10 位 | 无 | 图像品质 |
| 直接 HLG HDR HEIC | 固定 10 位 | 无 | 图像品质 |
| macOS SIPS HEIC | 系统决定 | 无 | 图像品质 |

- 中文导出界面，可保存 Lightroom 导出预设。
- 增益图缩小倍数 **1–2**，支持小数；2 表示宽、高各减半，主图尺寸不变。奇数尺寸向上取整。
- ISO 增益图品质 **0–100**：勾选「单独设置」后生效，初始数值 80；默认关闭，旧预设继续使用系统默认编码。该数值是编码品质，不是 QP，没有固定换算公式。
- HDR 模式在渲染前自动配置 TIFF 16 位、HDR 色彩空间、HDR 输出开启和最大兼容关闭，并检查实际中间文件。
- 最终 HEIC 重名可选「自动改名」「跳过」「覆盖」，默认自动改名。编码先在独立暂存目录完成，成功后再原子发布；失败保留中间文件。

**自动匹配照片的 SDR／HDR 状态，无需切换导出设置。** 未开启 HDR 编辑的照片导出普通 SDR HEIC，不附带增益图；开启 HDR 编辑的照片按所选 HDR 模式导出。同一批照片可以混合 SDR 和 HDR。

「使用上次设置导出」遇到 Lightroom 缓存的 JPEG 或 8 位中间文件时，会从原照片重新渲染一次 16 位 TIFF，再使用已保存的 HEIC 参数编码；失败保留中间文件。已在 Lightroom Classic 15.5.1 连续两次验证快捷导出及一次普通窗口导出。

自动判断以每张照片实际渲染的 TIFF 色彩编码为准。SDR 路径保留 Lightroom 已渲染的外观及色彩配置，不再额外做 HDR 色调映射；主图位深和品质沿用当前设置，忽略增益图参数。导出选项不会修改照片的 HDR 编辑开关。

## 环境

- macOS 15 或更新版本。
- 1.0.0.7 的 SDR 自动识别在 macOS 27.2.1、Lightroom Classic 15.5.1 验证。
- Lightroom Classic 14 或更新版本；本机实测 Lightroom Classic 15.5.1、macOS 27.0.1。
- 随仓库提供 arm64 + x86_64 通用程序；Intel 已编译，尚未在 Intel Mac 实机验证。
- 随附程序使用本地临时签名，未作 Developer ID 公证。

## 安装

1. 下载本 fork 的源码 ZIP，或克隆仓库。
2. 把其中的 **`export_heic.lrdevplugin` 整个文件夹**放到固定位置。
3. 在 Lightroom Classic 中打开「文件 → 增效工具管理器 → 添加」，选择该文件夹。
4. 更新已有版本后，在增效工具管理器点击「重新载入增效工具」。

也可将插件文件夹放入 `~/Library/Application Support/Adobe/Lightroom/Modules/`。请先保存旧版本的副本，避免覆盖自己的其他改动。

## 使用

1. 完成照片编辑，打开导出窗口。HDR 开关按照片需要设置即可。
2. 顶部「导出到」选择 **「导出为 HEIC（HDR）」**。
3. 选择输出模式、Apple／ISO 标准、主图位深和增益图缩放。
4. 如需控制 ISO 增益图体积，勾选「单独设置」，调节增益图品质。低品质可能损失高光或渐变细节；100 表示最高编码品质，不承诺绝对无损。
5. 选择输出目录与重名策略，开始导出。

直接 PQ／HLG 模式没有增益图，因此标准、缩放和增益图品质选项会禁用。

## 编译

安装 Xcode Command Line Tools 后运行：

```sh
make
make verify
```

默认分别编译 `toGainMapHDR` 和 `HEICExport` 的 arm64、x86_64 版本，合成通用程序，使用本地临时签名，再写入插件文件夹。默认使用仓库中已有的 Metal 库；需要重新编译着色器时，安装完整 Xcode 的 Metal 工具，再运行 `make metal`。

其他命令：

```sh
make zip                     # 打包插件
make SIGN_ID="你的签名证书"    # 可选 Developer ID 签名
```

主转换程序的源码是 `main.swift`、`CustomFilter/GainMapFilter.swift`、`ISOExport.swift` 和 `GainMapCompression.swift`。`HEICExport.swift` 是 Lightroom 调用的校验及安全发布入口。

命令行示例（输出文件夹须已存在）：

```sh
export_heic.lrdevplugin/HEICExport input.tif output-folder \
  --mode iso --depth 10 --scale 2 --quality 0.7 \
  --gain-quality 0.8 --collision rename
```

`--gain-quality` 仅适用于 ISO HEIC；省略则使用系统默认。直接调用转换程序时，对应参数为 `-Q 0.8`。`HEICExport` 退出码为 0（成功）、10（跳过）、2（中间文件格式或位深不符合要求）、1（其他失败）。

## 测试与实现说明

开发测试需要 Python 3、Lua（包含 `luac`）和 `heif-info`；例如通过 Homebrew 安装 `lua`、`libheif`，然后运行：

```sh
make test
```

测试使用自动生成的 HDR／SDR 图像，不依赖私人照片或 Lightroom 目录，覆盖元数据、HDR 重建、8/10 位、奇数尺寸、分数缩放、品质独立性、参数校验、重名与并发保护。产物写入被 Git 忽略的 `build/tests/`。

独立品质控制通过系统 HEIC 编码器重编码增益值，再替换 HEIF 内的增益图 item graph，保留主图压缩码流和 ISO 参数。自定义品质路径用中性 RGB 承载同一标量增益，系统编码为 8 位 YCbCr 4:2:0；它不是三个独立的彩色增益。关闭「单独设置」时保持原来的单通道增益图路径。详见 [验证记录与限制](docs/VALIDATION.md)。

## 来源

- Lightroom 插件原仓库：[fengshenx/LR_GainMap_HDR_Export_Plugin](https://github.com/fengshenx/LR_GainMap_HDR_Export_Plugin)。
- 原转换程序及增益图算法：Luyao Peng / [chemharuka](https://github.com/chemharuka/toGainMapHDR)。Swift 主文件保留原作者及 MIT 声明，Metal 源码保留原作者署名。
- 原项目说明保存在 [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md)。

本 fork 没有替上游未明确声明许可的文件追加统一许可证。各文件保留其原有许可及作者信息。
