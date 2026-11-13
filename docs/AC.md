# AC.md — MVP（v0.1.0）可量化验收标准

> 本文件是 v0.1.0 MVP 的验收唯一依据。任何一条 AC 未通过，本阶段不得标记完成。
> 状态由实际执行的测试更新（docs/test_report.md 存原始输出）。

| 编号 | 验收条件（EARS） | 验证方式 | 状态 |
|---|---|---|---|
| AC1 | 当执行 `godot --headless --path . --quit-after 120 res://scenes/main.tscn` 时，进程退出码为 0，且输出中无 `SCRIPT ERROR` / `Parse Error` | headless 命令行 | 未测 |
| AC2 | 当按住油门（W / action `accelerate`）持续 3 s（180 个物理帧）后，客车车速应 > 5 km/h | headless 自动化测试 | 未测 |
| AC3 | 当客车以 60 km/h 行驶并施加全制动（S / action `brake`）时，应在水平距离 < 60 m 内停稳，且车身直立度（basis.y · UP）> 0.7（不侧翻） | headless 自动化测试 | 未测 |
| AC4 | 当按下 C 键（action `toggle_camera`）时，相机应在第一人称驾驶舱与第三人称跟车视角间切换；两种视角下速度/挡位信息均可见。逻辑部分 headless 断言，视觉部分 GUI 测试确认 | headless + GUI | 未测 |
| AC5 | 当客车位于巴士站点 5 m 半径内、车速 < 2 km/h 且持续 3 s 时，`stop_task.gd` 应发出 `stop_completed` 信号（headless 由真实驾驶过程触发，非直接调用） | headless 自动化测试 | 未测 |
| AC6 | 当客车行驶中，HUD 显示速度与物理体实际速度（linear_velocity 长度）偏差应 < 2 km/h | headless 自动化测试 | 未测 |
| AC7 | 当场景加载完成后，平均帧渲染时间应 < 16.7 ms（等效平均 FPS ≥ 60），GUI 模式 `--bench` 采样 600 帧输出 | GUI 测试 | 未测 |

## 范围限定（v0.1.0）

- 仅实现自动挡 D / N / R；手动挡与离合模型留至 v0.2.0。
- 图形界面驾驶测试（含 AC4 视觉部分、AC7、自动驾驶演示）单独执行并记录，与 headless 自动化测试结果分开登记。
- 未实际执行的测试不得标记为通过。
