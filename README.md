# MHW DLSS Frame Generation for RTX 30

这是《Monster Hunter: World》MHWSS + MHWFG + DLSSG SM86 的集成包，目标是让 RTX 30（SM86）显卡使用 DLSS 帧生成和多帧生成。

## 已验证

本地 RTX 3070 Laptop、2560×1440、NVIDIA 驱动 617.14 已验证：

- 2x：`multi_frame_count=1`，DLSS-G CreateFeature 成功。
- 4x MFG：`multi_frame_count=3`，`multi_frame_count_max=5`，CreateFeature 成功。
- SM86 路由激活，CUDA 生成链正常运行。
- FPS / 帧时间 / 抗锯齿处理耗时 / Reflex timing 叠加层可用。

## 依赖边界

MHWSS 必须单独安装。它提供 MHW 的运动矢量、深度及画面输入，本仓库不包含 `MHWSS.dll` 或 `MHWSSLauncher.exe`。本仓库提供集成配置、安装/修复脚本和运行组件；MHWFG 的 C++ 构建来源见下文。

**MHWSS 1.0.2 的 `Upscaler="DLSS"` 实际运行原生分辨率 DLAA。** [作者说明](https://www.patreon.com/huutaiii/posts/mhwss-v1-0-2-mod-142322059)也将功能列为 DLSS4 DLAA。这个输入通道必须开启才能供当前 MHWFG 使用；`None` 会停止提供输入。`DLSSRenderPreset` 选择模型，不能将 2560×1440 原生输入变成 Quality/Balanced 超分。游戏自带的旧版 `NVIDIA DLSS` 应保持关闭。

不要同时安装另一套 `d3d12.dll`、`OptiScaler.dll`、`version.dll`、`winmm.dll` 或 `sl.*.dll`。MHWSS 可以继续保留；其它项目如果只是修改 MHWSS 配置或模型，可以手动合并，但不能再加载第二个 OptiScaler Hook。

## 安装

1. 先安装 MHWSS，并确认 `MHWSSLauncher.exe` 能正常进入游戏。
2. 确认游戏为 DX12，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-MHWRTX30.ps1
```

3. 退出游戏后安装。安装器会备份现有配置，停用旧的 `nativePC\plugins\OptiScaler.dll`，开启 MHWSS 的 DLSS/DLAA 输入通道，并复制 MHWFG/SM86 运行组件。游戏配置使用不带 BOM 的 UTF-8，保留 DX12，关闭旧版 DLSS 和 CAS。
4. 使用 `MHWSSLauncher.exe` 启动。`Insert` 打开 MHWFG，`Active` 控制帧生成，倍率选择 2x–6x。

当前默认配置：

- MHWFG 主菜单 `Menu Scale=1.5`
- FPS/延迟叠加层 `FpsScale=1.3`
- FPS 叠加层 `PageUp` 开关，`PageDown` 切换模式
- `SpoofHAGS=true`，不需要修改系统注册表
- 模组不限帧，显式关闭呈现同步；需要垂直同步时可在 Advanced → V-Sync Settings 调整

## 故障修复

遇到 DX12 回退报错，或关闭 MHWSS DLSS 后仍固定在 59–60 FPS，可在正常退出游戏后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-MHWDisplay.ps1
```

修复工具备份配置、恢复 DX12 和不带 BOM 的编码，并设置不限帧及异步呈现。然后用 `MHWSSLauncher.exe` 启动。它保留 MHWSS 抗锯齿选择、帧生成开关/倍率、菜单及 FPS 缩放；不修改驱动全局设置。自定义游戏路径用 `-GameRoot "你的游戏目录"`。

本机已验证编码修复能够恢复 DX12 启动。用户也报告重新进入游戏后 `None + 无帧生成` 的基础帧率恢复，但未完成受控对照，不能将 59–60 FPS 的原因直接定为同步设置，也不能据此认定 DLAA/MFG 的性能问题已经解决。诊断依据、回退方法和 DLAA 性能限制见 [故障说明](docs/TROUBLESHOOTING.md)。

## 运行入口

只使用根目录的 `version.dll` 作为 SM86 代理。不要把 `alternatives\winmm.dll` 与它同时复制到游戏根目录；Streamline 自身依赖 WINMM，双重代理会造成递归加载。

## 构建来源

MHWFG DLL 来自 [MHW-DLSSFrameGen](https://github.com/inhm112/MHW-DLSSFrameGen) 的 `a0421ee` 树，在本机用 VS2022 Release|x64 构建。SM86 代理来自 [dlssg_for_sm86](https://github.com/sdli1995/dlssg_for_sm86) 0.3.5。构建和运行时来源、第三方声明见 `docs/BUILD.md` 与 `docs/licenses/`。

NVIDIA DLSS/Streamline 运行时属于第三方材料，保留各自声明；MHWSS 不在本仓库内重新分发。
