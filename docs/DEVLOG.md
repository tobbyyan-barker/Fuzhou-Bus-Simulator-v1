# DEVLOG.md — 开发日志

## 2026-11-13

### 环境配置（Step 0）

- 目标引擎：Godot ≥ 4.3。查官方 GitHub releases：最新稳定版 **4.7.2-stable**（tag `4.7.2-stable`）。
- 下载源：`https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip`（官方仓库直接下载）。
- 下载问题与解决：本机代理（127.0.0.1:57279）对 GitHub 大文件传输中途断流（首次得到 48.5 MB 不完整文件，unzip 报"cannot find zipfile directory"；断点续传亦被切断）。TuxFamily 官方镜像未收录 4.7.2（404）。**解决：curl 绕过代理直连（`--noproxy "*"`）完整下载 82 MB。**
- 完整性校验：SHA512 与官方 `SHA512-SUMS.txt` 中 `Godot_v4.7.2-stable_win64.exe.zip` 条目一致：
  `83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993` → 校验 **OK**。
- 安装位置：`C:/Users/34779/Tools/Godot/`（用户批准路径），解压出 `Godot_v4.7.2-stable_win64.exe` 与 `Godot_v4.7.2-stable_win64_console.exe`。
- 运行验证：`--version --headless` → `4.7.2.stable.official.ed1daf0bf`。

### Step 1 — 项目骨架

- 创建目录树（scenes/ scripts/ data/ assets/ tests/ docs/），git init（分支 master，全局用户配置已存在）。
- `project.godot`：应用名 FujianBusSimulator，主场景 `res://scenes/main.tscn`（Step 6 前不存在属预期），渲染管线 Forward Plus，物理默认 60 Hz。
- InputMap：accelerate=W、brake=S、steer_left=A、steer_right=D、toggle_camera=C、handbrake=Space、gear_r=R、gear_n=N。
  - 修正一处：初版把 gear_d 映射到 D 键，与 steer_right 冲突——已移除，R 键直接在 D/R 间切换。
- docs/AC.md：AC1–AC7 量化验收标准（v0.1.0 仅自动挡 D/N/R，手动挡 v0.2.0）。
- docs/ASSET_LICENSES.md：当前外部素材引入数 0（全部为引擎图元程序化生成）。
