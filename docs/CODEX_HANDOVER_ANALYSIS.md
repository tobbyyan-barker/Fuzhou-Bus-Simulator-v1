# CODEX_HANDOVER_ANALYSIS.md — Codex 项目接手分析报告

> 接手时间：2026-11-15（晚）｜ 接手基线：v0.3.0（commit `720bc85`，master，已与 origin 同步）
> 本报告为 Codex 接手首轮产出：仅分析与验证，**未修改任何代码、未下载任何资源**。

## 一、接手验证结论

| 检查项 | 结果 |
|---|---|
| 工作目录确认 | ✅ `C:\Users\34779\WorkBuddy\AI玩法探索\FujianBusSimulator`（project.godot / scripts / tests / docs 结构完整） |
| Git 状态 | ✅ master 分支，基线 `720bc85`，与 origin 同步；接手时仅 2 个未跟踪交接文档（AGENTS.md、docs/DEVELOPMENT_STATUS.md），无已跟踪文件被修改 |
| 环境测试复跑 | ✅ AC 套件 headless 复跑 6/6 全绿，数值与 v0.3.0 交接记录逐项一致（AC2 38.6 km/h、AC3 60.2 km/h/20.7 m、AC5 2.0 m、AC6 偏差 0.2 km/h）——环境与基线行为可复现 |
| 交接文档阅读 | ✅ AGENTS.md / DEVELOPMENT_STATUS.md / README.md / DEVLOG.md（11 条故障档案）/ AC.md / main.gd / main.tscn / bus_controller.gd / mt10.tres 全部通读 |

## 二、项目架构理解（接手视角总结）

### 分层结构

- **编排层**：`scripts/main.gd` + `scenes/main.tscn` —— 实例化并接线 Map/Bus/CameraManager/HUD/StopTask/Traffic/TrafficLights/VehicleAudio/TurnIndicator/Voice/Horn；命令行模式 `--auto`（自动驾驶演示）/ `--bench`（600 帧性能采样）；`_ensure_input_map()` 对 12 个输入动作做运行时兜底（含 C/Q 双键）。
- **车辆层**：`BusController`（VehicleBody3D，6×VehicleWheel3D）—— 参数全部来自 `data/vehicles/mt10.tres`（数据驱动，代码零硬编码）；侧向加速度预算限角、踏板渐变、速度调速器；外部控制接口 `set_external_control()` 供自动驾驶复用。**驱动力取负**（VehicleWheel 前向轴 +Z vs 车头 -Z，故障 #2）。
- **感知/只读接口模式**：V0.3 音效系统示范了正确增量姿势——`bus_controller.gd` 仅暴露 `get_throttle_pedal()` / `get_brake_pedal()` 只读 getter，音效层监听状态、绝不触碰动力学。**后续一切新功能应沿用此模式。**
- **测试体系**：`tests/test_mvp.gd`（AC1–AC7，真实驾驶过程驱动）+ `tests/feel_check.gd`（15 项手感诊断，含真实 Input 事件注入）。改动后必须全量回归，不放宽判据。

### 运行方式速查

```bat
"C:\Users\34779\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\34779\WorkBuddy\AI玩法探索\FujianBusSimulator"          # 启动
"...\_console.exe" --headless --path . --import            # 新增 class_name 后必跑（故障 #11）
"...\_console.exe" --headless --path . res://tests/test_mvp.tscn    # AC 套件
"...\_console.exe" --headless --path . res://tests/feel_check.tscn  # 手感诊断
"...\Godot_v4.7.2-stable_win64.exe" --path . -- --auto / -- --bench # GUI 自动驾驶 / 性能
```

### 已锁定的红线（接手后不可触碰）

1. 车辆动力学参数（`mt10.tres` 物理部分）——多轮试驾调定，AC 数值逐项一致是回归锚点；
2. 相机系统（`camera_manager.gd` 五视角）——已验证零物理扰动；
3. 测试判据（AC.md）——不放宽、不造假；
4. 零外部素材原则——任何新素材必须先过 `docs/ASSET_LICENSES.md` 登记；
5. 真实品牌（宇通/金龙/比亚迪等）授权前禁用。

## 三、下一阶段最小可执行开发计划（MVP 路径）

按 DEVELOPMENT_STATUS.md 既定双目标，建议拆成 4 个可独立验收的增量步骤，每步全量回归后提交：

**Step A（0.5 天）：高模替换的沙盒验证**
- 目标：不改现有客车，新增 `assets/vehicles/` 一个试验车型场景副本，验证「换可视 Mesh、保物理骨架」的替换管线。
- 验收：AC 套件 6/6 保持全绿（物理骨架未动 → 数值应逐项一致）；新模型六轮可见且不穿模。

**Step B（1–2 天）：真实客车模型集成**
- 目标：Blender 自建（或合规授权模型）城市客车外观，替换图元拼装车身；碰撞形状与底盘兜底同步调整；`data/vehicles/` 保持数据驱动。
- 验收：AC + feel_check 全绿；GUI `--auto` 全路线闭环；bench < 16.7 ms（模型面数预算内）。

**Step C（0.5 天）：福大路网导入管线原型（离线）**
- 目标：写一个独立导入工具（GDScript 或 Python），把一段真实路网折线（ODbL 合规来源）转换为 `route_manager.gd` 可消费的车道中心线数据；先离线生成数据文件，不接入主场景。
- 验收：生成的路线数据可在单独测试场景中渲染并驾驶。

**Step D（1–2 天）：旗山校区小段道路接入主场景**
- 目标：1–2 km 试验路段接入 main.tscn（可选模式或替换鼓山地图），红绿灯/站点数据挂接。
- 验收：AC5 到站任务在新路线可完成；`--auto` 闭环。

## 四、目标 A「真实客车模型」技术方案（优先）

### 推荐方案：Blender 自建高保真模型（低风险路线）

1. **物理骨架不动**：保留 `VehicleBody3D + 6×VehicleWheel3D` 及全部连接点/悬挂参数——这是 AC 数值的来源，动即回归失败。
2. **只换可视层**：新建 `bus_body_pbr.tscn`（或 glTF 导入），车身用 Blender 建模（10.5 m 级城市客车造型，可参考公开车型照片的比例轮廓，**不复制商标/标识**）；PBR 材质（金属漆 + 玻璃 + 轮胎橡胶）；品牌继续用虚构「闽通 MT-10」或新虚构标识。
3. **碰撞形状同步**：按新外形更新底盘 BoxShape 兜底（注意故障 #1 的教训：碰撞箱抬高与悬挂余量耦合）；车轮可视 Mesh 与 VehicleWheel3D 半径一致（0.5 m）。
4. **面数预算**：整车 < 3 万三角（Forward Plus 管线单场景富余充足，bench 判据 <16.7 ms 有 7 ms+ 余量）。
5. **保留旧模型**：图元版作为低配/回退车型并存（`data/vehicles/` 多车型架构已就绪）。

### 备选方案：第三方 CC 授权模型

- Sketchfab CC0/CC-BY 滤选、Kenney/Quaternius 风格化车辆包——**必须在 ASSET_LICENSES.md 登记来源/作者/许可/署名**，并在 README 修订「零外部素材」表述。
- 风险：许可验证成本、发布合规不确定性、风格与现有程序化场景割裂。

### 潜在风险清单

| 风险 | 等级 | 缓解 |
|---|---|---|
| 模型比例/坐标轴向不符（Blender +Y up vs Godot -Z forward） | 高 | 导出用 glTF + Godot 官方 Blender 插件；先做 1:1 尺寸参考块验证轴向 |
| 碰撞形状与新外形不匹配 → 穿模/悬挂失效（故障 #1 同类） | 高 | 底盘兜底碰撞箱按新外形重调；AC1/AC2/AC3 立即复跑 |
| 车轮可视与物理轮不同步（半径/连接点偏移） | 中 | 车轮 Mesh 挂 VehicleWheel3D 节点下由物理驱动 |
| 面数/材质超标拖垮 bench | 中 | 面数预算 + 每次 GUI bench 复测 |
| 第三方模型许可不可商用/需署名遗漏 | 高（若选第三方） | 优先自建；第三方必须逐项登记 |
| 车内视角（cab_eye_offset）与新驾驶室几何不匹配 | 低 | 参数 Inspector 可调，实车微调即可 |

## 五、目标 B「福大附近真实道路」方案要点与合规红线

- **数据源**：OpenStreetMap（ODbL）——署名 + 同类许可共享义务，README/ASSET_LICENSES 登记；**注意中国地图测绘合规**（位置精度处理、不含敏感区域），发布前必要时咨询法务。
- **技术管线**：OSM 折线（道路中心线）→ 离线转换脚本（分段/曲线拟合/车道中心线偏移）→ 生成 `route_manager.gd` 可消费的路网数据（Array/JSON）→ 主场景挂接红绿灯/站点。
- **范围控制**：先做旗山校区周边 1–2 km 单条道路闭环，管线验证后再扩展路网拓扑。
- 风险：OSM 中国区域数据密度/精度不均；双向车道/路口拓扑超出当前 `route_manager` 单线路 API，可能需要小规模扩展（不重构，只加 API）。

## 六、需要用户决定的事项

1. **目标 A / 目标 B 的先后顺序**（本报告建议 A 先：管线风险低、见效快；两目标也可并行——A 做模型、B 做离线管线互不冲突）。
2. **模型路线选择**：Blender 自建（无风险但需建模工作量）vs 第三方 CC 模型（快但需许可登记与 README 修订）。
3. **福大具体路段范围**：旗山校区哪个门到哪条路（如学园路某段），决定 OSM 数据裁剪范围。
4. **新地图与鼓山地图的关系**：替换、并存（选关）还是默认切新？
5. 是否本轮把两个交接文档 + 本报告提交 GitHub（若用户已确认提交，见下节记录）。

## 七、本次接手的 Git 提交记录

- 本报告 + `AGENTS.md` + `docs/DEVELOPMENT_STATUS.md` 一并提交至 master 并推送 origin（用户明确要求）。
- 提交内容仅文档，**未修改任何代码**；提交前工作区基线 `720bc85` 干净。
