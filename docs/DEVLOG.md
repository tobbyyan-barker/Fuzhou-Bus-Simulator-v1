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

### Step 2–6 — 客车/相机/HUD/地图/任务开发

- `data/vehicles/mt10.tres` + `scripts/vehicle/bus_params.gd`：数据驱动车辆参数（质量 12000 kg、重心 0.95 m、驱动 2 轮 ×35000 N、轮胎摩擦 μ=2.0、悬挂刚度 40/阻尼 1.2/1.5）。
- `assets/vehicles/bus_mt10.tscn`：图元拼装 10.5 m 客车（车身/玻璃带/裙边/保险杠/仪表台/座椅/方向盘/6 轮），**含底盘碰撞箱兜底**（见故障 #1）。
- `scripts/vehicle/bus_controller.gd`：油门/制动/转向/手刹/滚动阻力，参数全部来自 .tres；支持外部控制（自动驾驶）。
- `scripts/vehicle/gearbox.gd`：自动挡 D/N/R（R 键切换，N 空挡，空挡踩油门自动回 D）。
- `scripts/camera/camera_manager.gd`：第一人称刚性绑定 + 第三人称阻尼跟车，C 键切换。
- `scenes/ui/hud.tscn` + `scripts/hud/hud.gd`：速度/挡位/里程/任务提示。
- `scripts/route/route_manager.gd`：程序化路线（700 m 直道 → R22° 缓弯 → 8% 上坡 250 m → 高架 300 m → L22° 缓弯 → 8% 下坡 → 820 m 终点直道，全长 2474.3 m），运行时生成路面/路缘/中央线/坡道护栏/站台/站牌/地面碰撞。
- `scripts/task/stop_task.gd`：到站判定（5 m 半径 + <2 km/h + 3 s 保持 → `stop_completed` 信号），与渲染解耦保证 headless 可测。
- `scripts/main.gd` + `scenes/main.tscn`：场景编排、命令行模式（`--auto` 自动驾驶演示 / `--bench` 性能采样）、InputMap 兜底校验。
- `scripts/vehicle/autopilot.gd`：纯追踪转向 + 速度控制 + 蠕行进站（GUI 自动测试用）。

### 故障档案

**#1 客车穿透地面（自由落体）** — 现象：客车出生后 3 s 速度 ≈ 自由落体（126 km/h），穿过路面与地面。定位过程：最小复现（1000 kg 四轮）正常 → 质量改 12000 kg 复现穿透 → 读 Godot 源码 `vehicle_body_3d.cpp`。根因（复合）：
- 悬挂力公式为 `刚度 × 压缩量 × 车体质量`，再被 `suspension_max_force` 独立钳制（不乘质量）——大质量车辆极易悬挂"塌陷"；
- 原悬挂几何（连接点 0.75 = 静止长度 0.25 + 轮半径 0.5）射线检测余量为零，车身必须沉入地面才有第一帧接触；
- 原阻尼 0.85/0.9 在质量缩放下严重欠阻尼（ζ≈0.16），接触后弹跳失控、姿态发散沉底；
- 车体无碰撞形状，悬挂一旦失效即永久坠落。
修复：连接点降至 0.65 + 静止长度 0.35（余量 0.2 m）+ 行程 5.0 + 阻尼 1.2/1.5（近临界）+ **新增底盘 BoxShape 碰撞兜底**。修复后 6 轮持续接触、0.1 m 幅内稳定收敛。

**#2 客车倒着开** — 现象：AC5 中客车头朝站点（fwd_dot=1.0）却越开越远。根因：Godot VehicleWheel 的前向摩擦轴由"车轴×接触法线"决定，本车布局下为 +Z，而车头建模在 -Z，正 `engine_force` 推向车尾。修复：控制器中驱动力取负并注释依据；R 挡同步反向。附带发现：AC3 翻车（直立度 -0.59）为高速制动前俯 + 高重心 + 原制动力过大（抱死减速度 4g）联合所致——制动力 5500→800、重心 1.15→0.95、底盘碰撞箱抬高后解决。

**#3 "无输出崩溃"实为超时挂起** — 现象：某几轮测试进程零输出、exit 1 SIGTERM。根因：测试协程中调用了 4.7.2 不存在的方法（`get_suspension_force`）→ SCRIPT ERROR 中断协程 → 永不调用 quit() → headless 死循环到超时。教训：测试脚本必须使用看门狗式退出（`_physics_process` 帧计数强制 quit），或只用确认存在的 API。

**#4 极速均衡 ~58.8 km/h** — 现象：无论提升调速器目标（90→110）或驱动力（+33%），加速均衡点稳定在 58.8 km/h。已排除：线性阻尼（显式置零无效）、调速器、滚动阻力。疑似 Godot VehicleWheel 前向滚动摩擦的速度匹配机制限制。按故障处理纪律（3 次迭代即停）登记为已知限制，v0.2.0 调查。AC3 制动判据余量 8.4 倍，实质达标（详见 test_report 已知限制①）。

### Step 7–9 — 测试与验收

- headless 自动化测试 `tests/test_mvp.gd`（AC1/2/3/4 逻辑/5/6）：**6/6 通过**，退出码 0。测试均为真实驾驶过程（Input 注入 + 物理仿真）触发，非直接调用被测方法。
- 调参历程（3 轮，均通过回归测试验证）：驱动力 10000→16000→30000→40000→35000 N/轮（终值低于轮胎抓地上限 39200 N/轮，避免起步打滑）；制动力 9000→5500→1200→800（抱死后由 μ=2 决定实际减速度）；摩擦 μ 4.0→2.0。
- GUI 测试：`--bench` 稳态 60.0 FPS / 16.68 ms（AC7 ✅，跳过 120 帧预热）；`--auto` 自动驾驶 176.5 s 完整跑完 2.47 km 并到站（渲染/转向/坡道/进站闭环 ✅）。
- 全部记录见 docs/test_report.md；AC 状态见 docs/AC.md；tag `v0.1.0-mvp`。

### 交付简报

启动游戏：`"C:/Users/34779/Tools/Godot/Godot_v4.7.2-stable_win64.exe" --path "C:/Users/34779/WorkBuddy/AI玩法探索/FujianBusSimulator"`
操作：W/S 油门刹车、A/D 转向、C 切换视角、R 倒挡、N 空挡、空格手刹；任务：开到终点巴士站，站牌 5 m 内停稳 3 秒。
已知限制：极速 58.8 km/h（见故障 #4）；驾驶手感（转向灵敏度/悬挂软硬）为程序初值，需人工试驾反馈后调。
