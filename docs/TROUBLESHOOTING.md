# 启动、60 FPS 限制与 DLAA 输入

## DX12 回退报错

2026-10-05 的本机测试中，Windows PowerShell 5.1 使用 `Set-Content -Encoding UTF8` 给 `graphics_option.ini` 写入了 `EF BB BF` 文件头。文件虽然包含 `DirectX12Enable=On`，游戏仍回退到 DX11，MHWSS 报错；日志同时记录旧 NGX D3D11 初始化调用异常。

恢复原先不带 BOM 的配置后，同一套 DLL 成功创建 DX12 设备、交换链和 DLSS 功能。无需重装驱动。安装及修复脚本现在使用 `.NET UTF8Encoding(false)` 写入游戏配置。

`tests/Test-DisplayConfig.ps1` 在 Windows PowerShell 5.1 下用 Windows 原生 `GetPrivateProfileStringW` 复现：带 UTF-8 BOM 时读不到首个 `[GraphicsOption]` 节，修复后能够读取 `DirectX12Enable=On`。测试还覆盖修复脚本、安装脚本、`-WhatIf`、缺失配置项和用户设置保留。

## 关闭 DLSS 后仍固定在 59–60 FPS

本机用户报告：同场景原来约 130 FPS，MHWSS 改为 `None` 后仍停在 59–60 FPS。检查发现游戏为无边框、游戏配置不限帧且 V-Sync 关闭，MHWFG 没有显式限帧，当前显示器刷新率为 60 Hz。用户随后报告重新进入游戏后，`None + 无帧生成` 的帧率恢复。

用于排查同步限制的配置组合为：

```ini
[Framerate]
FramerateLimit = 0

[V-Sync]
OverrideVsync = true
ForceVsync = false
```

`OverrideVsync` 使无边框交换链带允许撕裂的标志，`ForceVsync=false` 使呈现调用使用零同步间隔并在交换链支持时传入允许撕裂标志。交换链创建设置在下一次启动生效。本次恢复时仍是原进程，不能证明新写入的配置已生效；前后台切换、同步或其它运行时状态仍是待区分的因素。不能将上述现象写成“已证实 DLAA 吃掉一半帧率”或“已证实同步设置修复”。

修复后先保持 MHWSS 为 `None`，观察未生成的帧率；再比较 DLAA 开启、帧生成关闭及帧生成开启的状态。生成后的输出 FPS 不能代表输入响应速度。解除同步限制后可能看到撕裂；需要同步时，可在 Advanced → V-Sync Settings 配置。

正常退出游戏后运行 `scripts/Repair-MHWDisplay.ps1` 可应用上述配置并修复编码。备份位于游戏目录 `MHW-Display-Backups/<时间>/`。`-Presentation GameControlled` 将模组的同步覆盖改回 `auto`；需要恢复原始游戏限帧等设置时，退出游戏后复制对应备份中的两份 INI。

如果仍被固定限帧，再检查驱动的 Max Frame Rate、后台限帧、V-Sync，以及其它叠加层/模组的限帧。不要为这个现象盲目更换 DLSS 模型。

## MHWSS 1.0.2 的 DLSS 选项是什么

[MHWSS 作者的功能说明](https://www.patreon.com/huutaiii/posts/mhwss-v1-0-2-mod-142322059)列出 DLSS4 DLAA 和 FSR NativeAA。当前链路是：

```text
MHWSS 的 DLSS/DLAA 输入 → MHWFG 捕获运动矢量、深度和画面 → DLSSG SM86 帧生成
```

本机日志记录 `quality mode: 5`、输入 2560×1440、输出 2560×1440，即原生分辨率 DLAA。`DLSSRenderPreset=11` 对应模型 K，既不是 Quality 档，也不是 11 倍缩放。更改模型不改变游戏实际渲染尺寸。游戏自带 DLSS 是另一套旧实现，MHWSS 启动器会将其关闭。

DLSS 超分和 DLAA 本身负责时间抗锯齿，通常替代原生 TAA。MHWFG/MHWSS 安装说明要求游戏菜单开启 TAA，以便接入该阶段；这不意味着还需要在 DLSS/DLAA 之后叠加一次 TAA。下面的 FSR 路线也是替换抗锯齿后端，而非增加一层抗锯齿。

DLAA 会增加原生渲染之后的处理开销，帧生成也有成本。真正的 Quality/Balanced 超分需要降低游戏内部渲染尺寸，并正确处理对应深度、运动矢量和后处理；这不是当前包中已经实现或验证的功能。默认运行包仍依赖 DLAA 输入；另外提供的无 AA 实验后端及其当前限制见 [NO-AA.md](NO-AA.md)。

应以同一场景、同一机位的真实 FPS 和帧时间比较性能。FPS 叠加层的 `Upscaler Time` 在这套原生输入下是抗锯齿/重建处理耗时；Reflex 各阶段计时并非完整鼠标到光子的延迟。

### DLAA 开销与可选 FSR 原生抗锯齿

用户随后报告了同场景、关闭帧生成的对比：MHWSS 为 None 时约 130 多 FPS，开启 DLSS/DLAA 后约 80 FPS。按 130 和 80 估算，帧时间从 7.7 ms 增至 12.5 ms，差约 4.8 ms。这是整条 MHWSS DLAA 路径的差值，不能等同于单个 DLSS GPU 算子的精确耗时。

MHWFG 内置 FSR 2.2 后端，可用它替代 DLAA 处理原生输入；DLSSG 仍负责帧生成。该路径的代码已核对，但在这台 MHW 安装上的画质、性能及持续帧生成尚未验证，因此作为可选实验配置提供，默认仍为 DLAA。

退出游戏后应用：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Set-MHWAntialiasing.ps1 -Mode FSR22
```

脚本将 MHWSS 保持在 `DLSS` 输入通道，将 MHWFG 的 `Dx12Upscaler` 改为 `fsr22`，保持 `FGOutput=dlssg`。这只改变抗锯齿后端，不是将帧生成改为 FSR。游戏的 TAA 选项保持开启，供 MHWSS 挂接；帧生成开关、倍率和 UI 缩放保持原值。首先取消 MHWFG 的 Active 比较真实帧率，再开启 Active 检查输出 FPS 与运动画面。

若当前运行已检测到输入，也可用 Insert → Advanced → Upscalers 下拉框选择 FSR 2.2，点击 Change Upscaler；不要改 Frame Generation 的输出下拉框。出现黑屏、闪烁或无法检测输入时，退出游戏并回退：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Set-MHWAntialiasing.ps1 -Mode DLAA
```

这两种模式都进行抗锯齿。MHWSS 的 None 仅停用它自己的处理，若游戏仍选 TAA，画面并非完全没有抗锯齿。另有独立提供的 [Native No AA 实验后端](NO-AA.md)，请注意其中的验证范围和已知问题。
