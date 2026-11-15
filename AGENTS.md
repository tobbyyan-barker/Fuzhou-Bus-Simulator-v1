# AGENTS.md — 《福州客车模拟器》智能体开发指南

> 本文件面向接手本项目的 AI 编码智能体（Codex / Claude Code / WorkBuddy 等）。
> 人类开发者同样适用。**接手后请先读本文件，再按文末「优先阅读顺序」深入。**

## 1. 项目概要

- **项目名**：福州客车模拟器（Fuzhou Bus Simulator）
- **绝对路径**：`C:\Users\34779\WorkBuddy\AI玩法探索\FujianBusSimulator`
- **远程仓库**：https://github.com/tobbyyan-barker/Fuzhou-Bus-Simulator-v1 （master 分支）
- **类型**：Windows 平台 3D 客车驾驶模拟游戏（参考欧洲卡车模拟 2 的驾驶体验方向）
- **当前版本**：v0.3.0（commit `720bc85`，2026-11-15）
- **核心原则**：全部代码 / 美术 / 音效为**原创程序化生成，零外部素材**（无版权风险，详见 `docs/ASSET_LICENSES.md`）

## 2. 引擎与运行环境

- **Godot 4.7.2-stable 官方便便版**（版本要求 4.3+，开发验证为 4.7.2）
- 可执行文件：
  - `C:\Users\34779\Tools\Godot\Godot_v4.7.2-stable_win64.exe`（GUI）
  - `C:\Users\34779\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`（命令行/headless，输出可见）
- 无需安装任何依赖或插件，克隆即玩。

### 常用命令（路径含中文，引号不能省）

```bat
:: 启动游戏（GUI）
"C:\Users\34779\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\34779\WorkBuddy\AI玩法探索\FujianBusSimulator"

:: 自动驾驶演示（AI 自己开完全程：等红灯、跟车、借道超车、进站）
"...\Godot_v4.7.2-stable_win64.exe" --path "<项目路径>" -- --auto

:: 性能基准（600 帧采样，输出平均帧时间）
"...\Godot_v4.7.2-stable_win64.exe" --path "<项目路径>" -- --bench

:: AC 验收测试套件（headless，6 项）
"...\Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://tests/test_mvp.tscn

:: 手感/功能量化诊断（headless，15 项）
"...\Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://tests/feel_check.tscn
```

⚠️ **坑（故障 #11）**：新增 `class_name` 脚本后，headless 直接跑测试会报 `Could not find type`——全局类缓存（`.godot/global_script_class_cache.cfg`）只在编辑器扫描时更新，**需先跑一次**：
```bat
"...\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import
```

## 3. 项目结构

```
FujianBusSimulator/
├── project.godot            # 主配置（输入映射：W/S/A/D/C/Q/R/N/H/E/逗号/句号/空格）
├── scenes/
│   ├── main.tscn            # 主场景（Map/Bus/Traffic/TrafficLights/VehicleAudio/Voice/Horn/
│   │                        #   CameraManager(5 相机)/HUD/TurnIndicator/StopTask）
│   ├── test_map.gushan.tscn # 鼓山测试场 2.47 km 程序化路线（虚构地图）
│   └── ui/hud.tscn          # HUD（速度/挡位/里程/任务/倒车雷达/手刹/红绿灯/转向灯）
├── scripts/
│   ├── main.gd              # 主编排：实例化/接线/命令行模式(--auto/--bench)/输入兜底
│   ├── vehicle/             # bus_controller(动力学)、bus_params(参数定义)、gearbox(D/N/R)、autopilot
│   ├── camera/camera_manager.gd   # 五视角循环状态机（跟车→车顶→左→右→驾驶舱）
│   ├── route/route_manager.gd     # 程序化路线 + 双车道 API
│   ├── task/stop_task.gd          # 到站判定（5m 半径 + <2km/h + 3s → stop_completed）
│   ├── traffic/             # traffic_manager(双向车流+跟车+防重叠)、traffic_light_manager(红绿灯+倒计时)
│   ├── audio/               # audio_synth(PCM 合成)、vehicle_audio(发动机/行驶/制动音效+内外听感)、
│   │                        #   turn_indicator(转向灯节拍)、horn(喇叭)、voice_announcer(TTS)
│   └── hud/hud.gd           # HUD 更新
├── data/vehicles/mt10.tres  # 闽通 MT-10 车辆参数资源（数据驱动：改参数不改代码）
├── assets/vehicles/bus_mt10.tscn  # 客车模型（图元拼装，6 轮 VehicleBody3D）
├── tests/
│   ├── test_mvp.gd/.tscn    # AC1–AC7 自动化验收（真实驾驶过程驱动，非直接调用）
│   ├── feel_check.gd/.tscn  # 15 项手感/功能量化诊断
│   └── spawn_watch.gd/.tscn # 出生点物理监视（故障 #7 排查工具，支持环境变量）
└── docs/                    # AC.md / DEVLOG.md / test_report.md / ASSET_LICENSES.md / DEVELOPMENT_STATUS.md
```

## 4. 已有功能（v0.1.0 → v0.3.0）

- **车辆**：闽通 MT-10（虚构品牌）10.5m 级城市客车，6 轮 VehicleBody3D，自动挡 D/N/R + 倒挡保护 + 手刹紧急停车
- **驾驶手感**：侧向加速度预算限角（任何车速满舵不侧翻）、踏板渐变、随速限角；油门/刹车/转向/回正
- **五视角循环**（C/Q）：第三人称跟车（默认）→ 车顶 → 左侧 → 右侧 → 第一人称驾驶舱；相机参数 Inspector 可调、切换零物理扰动
- **地图**：虚构「鼓山测试场」2.47 km（直道→缓弯→8% 坡道→长直道→终点巴士站），右侧车道行驶
- **交通**：对向 6 辆 + 同向 5 辆车流（含非机动车）、3 处红绿灯（秒数倒计时牌、停车线）、红灯 HUD 横幅 + 车内 TTS 语音播报
- **任务**：终点巴士站 5m 内停稳 3s → 到站完成；倒车雷达（车尾 12m 射线）
- **音效（V0.3）**：发动机（曲轴起动→怠速→油门驱动连续变调→松油门回落→E 键熄火，近似转速模型）、路面/风噪随车速、气刹放气（冷却防叠加）+ 停稳驻车声、H 喇叭、逗号/句号转向灯继电器节拍、第一/第三人称内外听感自动过渡
- **自动驾驶**：全路线闭环（等红灯/速度匹配跟车/借道超车/进站），`--auto` 演示
- **测试**：AC1–AC7 验收 + 15 项手感诊断，全部通过（详见 docs/test_report.md）

## 5. 开发规范（务必遵守）

1. **零外部素材红线**：不引入来源不明的模型/贴图/音效；任何新素材必须登记 `docs/ASSET_LICENSES.md`（来源/作者/许可/是否署名）。客车必须用虚构品牌「闽通 MT-10」（宇通/金龙等真实品牌在获授权前禁用）；地图未使用任何真实地理数据。
2. **数据驱动**：车辆物理/相机/音效参数全部走 `@export`（mt10.tres 或场景节点 Inspector），代码不写死数值；新增车型只需新增 `.tres`。
3. **测试纪律**：
   - 改动后跑全量回归：AC 套件（建议连跑 3 次防间歇性）+ feel_check +（涉渲染时）bench 与 GUI `--auto`
   - **不放宽任何测试判据、不造假数据**；判据见 `docs/AC.md`
   - 每轮交付必须跑全套 AC（历史教训：v0.1.4 只跑 feel_check，AC5 回归漏网一整天，故障 #10）
   - 新增 class_name 先 `--headless --import`
   - 测试协程只用确认存在的 API；协程中断会表现为「零输出假死」而非报错（故障 #3）
4. **增量开发**：不重构已调好的模块（车辆动力学/相机/音效已多轮调参验证）；监听状态用只读接口（如 `bus.get_throttle_pedal()`），不重写控制逻辑。
5. **物理/几何约束已踩过的坑**（详见 DEVLOG 故障档案，共 11 条，改动力学前必读）：
   - 悬挂 max_force 不随质量缩放 + 几何零余量 → 穿地坠落
   - VehicleWheel 前向轴与建模朝向相反 → 驱动力取负
   - 交通车必须「先定位再入树」，否则出生重叠把客车炸飞
   - 倒挡保护必须用带符号前向速度
6. **Git 约定**：commit message 用 `类型(范围): 版本——摘要` + 回归结果；推送 GitHub 网络不稳时先 `echo $http_proxy` 查当前代理端口，用 `git -c http.proxy=http://127.0.0.1:<端口> -c http.version=HTTP/1.1 push` 重试（直连时通时不通）。
7. **文档同步**：每轮功能改动同步更新 README（版本史）、DEVLOG.md（含故障记录）、test_report.md（回归数据）。

## 6. 已知限制（如实登记，未放宽判据）

- 直线极速均衡点约 58.8 km/h（疑 Godot 滚动摩擦机制，已登记未解决）
- 转向灯无方向盘回位自动取消；E 键熄火仅作用音效层（不影响驱动力）
- 音效为程序化合成近似（非真实客车录音），接口已兼容真实录音替换
- 近似转速模型无挡位台阶感；单一车型

## 7. 优先阅读顺序（Codex 接手路线）

1. 本文件（AGENTS.md）
2. `docs/DEVELOPMENT_STATUS.md` — 当前进度与下一阶段目标
3. `README.md` — 用法 + v0.1.0→v0.3.0 优化历程
4. `docs/DEVLOG.md` — 11 条故障档案（改动力学/物理前必读）
5. `docs/AC.md` — 验收标准（不放宽）
6. `scripts/main.gd` + `scenes/main.tscn` — 场景编排与接线
7. `scripts/vehicle/bus_controller.gd` + `data/vehicles/mt10.tres` — 车辆核心
8. `docs/test_report.md` / `tests/test_mvp.gd` / `tests/feel_check.gd` — 测试体系
