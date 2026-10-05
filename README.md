# MHW DLSS Frame Generation for RTX 30

这是《Monster Hunter: World》MHWSS + MHWFG + DLSSG SM86 的集成包，目标是让 RTX 30（SM86）显卡使用 DLSS 帧生成和多帧生成。

## 已验证

本地 RTX 3070 Laptop、2560×1440、NVIDIA 驱动 617.14 已验证：

- 2x：`multi_frame_count=1`，DLSS-G CreateFeature 成功。
- 4x MFG：`multi_frame_count=3`，`multi_frame_count_max=5`，CreateFeature 成功。
- SM86 路由激活，CUDA 生成链正常运行。
- FPS / 帧时间 / DLSS 超分耗时 / Reflex timing 叠加层可用。

## 依赖边界

MHWSS 必须单独安装。它是 MHW 的超分和资源输入层，本仓库不包含 `MHWSS.dll` 或 `MHWSSLauncher.exe`。本仓库只提供 MHWFG 集成代码、配置和可分发的运行组件。

不要同时安装另一套 `d3d12.dll`、`OptiScaler.dll`、`version.dll`、`winmm.dll` 或 `sl.*.dll`。MHWSS 可以继续保留；其它项目如果只是修改 MHWSS 配置或模型，可以手动合并，但不能再加载第二个 OptiScaler Hook。

## 安装

1. 先安装 MHWSS，并确认 `MHWSSLauncher.exe` 能正常进入游戏。
2. 确认游戏为 DX12，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-MHWRTX30.ps1
```

3. 安装器会备份现有文件，停用旧的 `nativePC\plugins\OptiScaler.dll`，把 MHWSS 超分设为 DLSS，并复制 MHWFG/SM86 运行组件。
4. 使用 `MHWSSLauncher.exe` 启动。`Insert` 打开 MHWFG，`Active` 控制帧生成，倍率选择 2x–6x。

当前默认配置：

- MHWFG 主菜单 `Menu Scale=1.5`
- FPS/延迟叠加层 `FpsScale=1.3`
- FPS 叠加层 `PageUp` 开关，`PageDown` 切换模式
- `SpoofHAGS=true`，不需要修改系统注册表

## 运行入口

只使用根目录的 `version.dll` 作为 SM86 代理。不要把 `alternatives\winmm.dll` 与它同时复制到游戏根目录；Streamline 自身依赖 WINMM，双重代理会造成递归加载。

## 构建来源

MHWFG DLL 来自 [MHW-DLSSFrameGen](https://github.com/inhm112/MHW-DLSSFrameGen) 的 `a0421ee` 树，在本机用 VS2022 Release|x64 构建。SM86 代理来自 [dlssg_for_sm86](https://github.com/sdli1995/dlssg_for_sm86) 0.3.5。构建和运行时来源、第三方声明见 `docs/BUILD.md` 与 `docs/licenses/`。

NVIDIA DLSS/Streamline 运行时属于第三方材料，保留各自声明；MHWSS 不在本仓库内重新分发。
