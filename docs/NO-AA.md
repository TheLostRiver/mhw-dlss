# Native No AA 实验后端

这是“跳过 DLAA/FSR 抗锯齿，只保留帧生成输入”的研究版本。默认安装器继续使用原先的稳定 DLL，实验 DLL 单独放在 `runtime/experimental/no-aa/d3d12.dll`。

## 实现

- MHWSS 继续选择 DLSS，向 NGX 接口提交当前画面、深度、运动矢量。
- MHWFG 的 `native` 后端用原尺寸 `CopyResource` 复制当前画面，不创建或执行 DLSS SR、DLAA、FSR、锐化或历史帧混合。
- MHWSS 1.0.2 的 TAA bypass 仍作为输入入口；游戏菜单保留 TAA，并不让原生 TAA 与模组 AA 叠加。
- MHWSS 会给投影添加采样抖动。实验后端在内存中挂接其 jitter float2 回调，将实际投影抖动归零；不会只把传给帧生成的数值伪装成零。切回其它后端或释放 Native 后端时，回调恢复原行为。
- 抖动兼容处理要求 MHWSS DLL 的完整 SHA256 为 `55d52caf2e7bba5220ec721149bc067679bf9391bbf55d62bed3ec9522ccd09a`，并核对已加载函数的指令前缀。其它版本拒绝启用。不会修改磁盘上的 MHWSS DLL，也不重新分发它。
- 仅接受等尺寸、等格式、单采样的完整二维画面；不支持用这个模式做超分。检测到不兼容尺寸会报错并停止 FG，不偷偷回退到另一种 AA。

## 使用与回退

正常退出游戏后：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Set-MHWAntialiasing.ps1 -Mode NativeNoAA
```

脚本会备份当前 DLL 和配置，复制实验 DLL，并设置 `Dx12Upscaler=native`、`FGInput=upscaler`、`FGOutput=dlssg`。帧生成开关、倍率、菜单 1.5 和 FPS 叠加层 1.3 保持原值。

启动后按 Insert，首页 Antialiasing 可选 `Off (Native, experimental)` 或 `DLAA`；Active 和倍率仍独立控制。MHWSS 自己的选项保持 DLSS。将 MHWSS 改成 None 会停止输入，帧生成也应随之关闭。

需要恢复 DLAA 后端时，退出游戏运行 `-Mode DLAA`。要完整回滚实验 DLL，退出游戏后将 `MHW-Display-Backups/AA-<时间>/` 内原先的 `d3d12.dll`、`OptiScaler.ini`、`graphics_option.ini` 和 `MHWSS/MHWSS_config.toml` 复制回游戏目录。

## 验证范围与当前问题

- Release x64 构建通过；源码及上游集成补丁随仓库提供。
- 独立 D3D12 WARP 测试连续四帧逐字节核对原图复制，验证重复调用、状态恢复和不兼容输入拒绝。该机器未安装 D3D12 debug layer，测试没有声称通过 GPU validation。
- 首次 MHW 实机日志证明 Native 后端运行、没有创建 DLSS SR 功能，稳定后输入 jitter 为 `(0, 0)`；切回 DLAA 后抖动重新出现。
- SM86 日志确认 4x（3 张生成帧）和 2x（1 张生成帧）创建成功。
- 用户发现首次实验版关闭输入/帧生成后基础帧率降到约 43，且 2x 输出约等于原生帧率。这两个报告属于实际缺陷/性能限制，不能把“创建成功”视为性能验证通过。
- 后续版本补上输入释放时及 Present 中的停用检查、暂停状态清理、生成倍率/Reflex 限帧重置，并加入每 3 秒的呈现计时日志。关闭恢复和净性能收益仍需同场景复测。

### 性能复测

更新 DLL 后需要正常退出并重新启动游戏，已运行的进程仍使用旧映射。固定同一场景、机位和分辨率，每次切换后等待约 10 秒，再记录以下状态；保持游戏在前台。

| 状态 | MHWSS | MHWFG 抗锯齿 | 帧生成 |
| --- | --- | --- | --- |
| A | None | 不运行 | 关闭 |
| B | DLSS | Off (Native) | 关闭 |
| C | DLSS | Off (Native) | 2x |
| D | 切回 None | 不运行 | 关闭 |

B 与 A 的差值用于分离 MHWSS 输入/复制路径的开销；C 与 B 比较帧生成；D 与 A 比较关闭后的残留影响。MHWSS None 时游戏仍可能运行自身 TAA，A 是停用模组 AA 的基线，不能称作已验证的完全无 AA 基线。

诊断时在 `OptiScaler.ini` 的 `[Log]` 中开启 `LogToFile=true`、`LogLevel=2`。`[MHWFG timing]` 每 3 秒记录：

- `app_fps` / `frame_ms`：游戏侧 Present 调用频率/间隔，独立计时，不用输出 FPS 除倍率推算，也不是屏幕实际显示帧率。
- `fg_work_ms`：Present 中帧生成资源处理与提交的 CPU 耗时，**不是**帧生成内核的 GPU 耗时。
- `present_ms`、`reflex_sleep_ms`、`limiter_ms`：呈现调用、Reflex 等待、模组软件限帧的 CPU 耗时。
- `game_wait_ms`、`wait_calls`、`wait_bypassed`：游戏原有交换链等待的累计耗时（除以采样帧数）及实际等待/跳过次数。
- `generated_frames`：NGX 请求的插帧数，不能当作已显示成功的帧数；`backend=12` 为 Native，`9` 为 DLSS，`-1` 为没有输入对象。

计时项位于不同阶段，不能简单相加当作 GPU 时间。现有叠加层的基础 FPS 是根据倍率推算的，异常状态下需要用 `app_fps` 交叉检查。复测结束后可关闭 `LogToFile`。

另外，[NVIDIA Streamline 集成说明第 18 节](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md#180-how-to-avoid-unnecessary-overhead-when-dlss-g-is-turned-off)说明：仅将 DLSSG mode 设成 Off，仍会保留代理交换链的额外复制和队列同步；完全消除这部分开销需要卸载该功能并重建交换链。本实验版修复了停用状态，尚未实现游戏运行中安全重建交换链。因此 Off 请求成功本身也不能保证恢复到原始帧率，需以上述 D/A 对照判断。

无 AA 本身会暴露细线、植被和毛发的锯齿、闪烁。抖动归零并不能消除没有抗锯齿时的空间采样闪烁。

## 重建

先克隆 [MHW-DLSSFrameGen](https://github.com/inhm112/MHW-DLSSFrameGen)，然后：

```powershell
.\scripts\Build-MHWNoAA.ps1 -SourceRoot D:\Tools\MHW-DLSSFrameGen
cmake -S tests/native -B build/native-copy-tests -G "Visual Studio 17 2022" -A x64
cmake --build build/native-copy-tests --config Release
ctest --test-dir build/native-copy-tests -C Release --output-on-failure
```

构建脚本创建独立 worktree，固定上游 `a0421ee5937eb2d803f67a89d6993fb13c670c04`，应用 `patches/native-no-aa.patch` 和 `src/native/`。不修改原源码目录，不自动安装进游戏。
