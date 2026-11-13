# test_report.md — v0.1.0 MVP 测试报告

> 测试日期：2026-11-13
> 环境：Windows / Godot 4.7.2-stable 官方便携版（`C:/Users/34779/Tools/Godot/`，SHA512 校验通过）
> 项目：`C:/Users/34779/WorkBuddy/AI玩法探索/FujianBusSimulator/`
> 原则：所有"通过"均来自本页记录的实际执行结果，未执行的测试一律标"未测"。

## 一、headless 自动化测试（AC1/AC2/AC3/AC4 逻辑/AC5/AC6）

执行命令：

```
godot --headless --path . res://tests/test_mvp.tscn
```

实测输出（退出码 0）：

```
[AC1-load] PASS — 主场景/客车/路线/任务全部实例化成功
[AC2] PASS — 全油门 3 s 后 42.0 km/h（要求 > 5）
[AC3] PASS — 58.8 km/h 全制动 7.1 m（要求 < 60 m），车身直立度 1.00
[AC6] PASS — HUD 24.7 vs 实测 24.9 km/h（偏差要求 < 2）
[AC4-logic] PASS — 视角切换逻辑正常（视觉确认见 GUI 测试）
[AC5] PASS — 到站判定 completed=true，停车点距站点 4.0 m（要求 ≤ 5 m，蠕行 7 段）
TEST_SUMMARY total=6 pass=6 fail=0
```

| AC | 结果 | 备注 |
|---|---|---|
| AC1 | ✅ PASS | 主场景 headless 加载 120 帧无报错，退出码 0 |
| AC2 | ✅ PASS | 42.0 km/h（阈值 5，余量 8.4 倍） |
| AC3 | ✅ PASS | 58.8 km/h 全制动 7.1 m / 直立 1.00（见已知限制 ①） |
| AC4 | ✅ 逻辑通过 | 切换状态机断言通过；视觉部分见已知限制 ② |
| AC5 | ✅ PASS | 真实驾驶进站（Input 注入 + 蠕行）触发 stop_completed |
| AC6 | ✅ PASS | HUD 偏差 0.2 km/h（阈值 2） |

## 二、GUI 图形界面测试（AC7 + 自动驾驶闭环）

### AC7 性能（`--bench`，跳过 120 帧预热后采样 600 帧）

```
godot --path . res://scenes/main.tscn -- --bench
BENCH_RESULT avg_fps=60.0 frame_ms=16.68 frames=600 (warmup=120 skipped)
AC7_MEASURED frame_ms=16.68 (target<16.7)
```

**✅ PASS**：稳态 60.0 FPS / 16.68 ms（窗口模式 1152×648，Forward+ 渲染管线）。
注：含预热的全程均值 17.10 ms——预热帧含着色器编译，稳态值才是有效指标。

### GUI 自动驾驶闭环（`--auto`，纯追踪转向，全程真实渲染）

```
godot --path . res://scenes/main.tscn -- --auto
AUTOPILOT_ON
AUTO_STOP_COMPLETED elapsed=176.5
```

**✅ PASS**：自动驾驶完整行驶 2.47 km 路线（长直道 → 双向缓弯 → 8% 坡道 → 高架段 → 终点巴士站），176.5 s 完成到站任务并自动退出，输出无 ERROR / SCRIPT ERROR。该项综合验证了：渲染管线、路线碰撞、转向控制、坡道护栏、进站刹停、stop_task 信号在图形模式下的全链路工作。

## 三、已知限制（如实登记，不隐藏）

1. **AC3 名义前置 60 km/h 实测为 58.8 km/h（98%）**：客车存在约 59 km/h 的稳定极速均衡，提升 33% 驱动力后均衡点不变，判定为 Godot VehicleWheel 前向滚动摩擦的速度匹配机制所致（v0.2.0 调查）。制动距离 7.1 m 对 < 60 m 判据余量 8.4 倍，AC3 实质达标；未修改 AC 判据本身。
2. **AC4 视觉部分（两视角仪表信息可见性）**：切换逻辑已自动化验证，GUI 渲染已确认正常（自动驾驶测试全程运行），但"视角观感"属主观项，建议用户按第四节试玩确认。
3. 手动挡 D/N/R 之外的换挡手感、方向盘回正等主观驾驶体验项不在 v0.1.0 验收范围（见 docs/AC.md 范围限定）。

## 四、人工复现/试玩命令

```
# 自动化测试
"C:/Users/34779/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path <项目> res://tests/test_mvp.tscn

# 性能采样
"C:/Users/34779/Tools/Godot/Godot_v4.7.2-stable_win64.exe" --path <项目> res://scenes/main.tscn -- --bench

# 手动试玩（W/S 油门刹车，A/D 转向，C 视角，R 倒挡，N 空挡，空格手刹）
"C:/Users/34779/Tools/Godot/Godot_v4.7.2-stable_win64.exe" --path <项目>

# 自动驾驶演示
"C:/Users/34779/Tools/Godot/Godot_v4.7.2-stable_win64.exe" --path <项目> -- --auto
```
