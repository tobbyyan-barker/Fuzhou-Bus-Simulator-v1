# ASSET_LICENSES.md — 素材来源与许可登记

> 合规红线：本项目不使用任何来源不明的 3D 模型/贴图/音效。v0.1.0 阶段未引入任何外部素材文件。

| 素材 | 来源 | 许可 | 备注 |
|---|---|---|---|
| 全部几何体（客车车身/车窗/车轮/仪表台/座椅、道路/路缘/护栏/站台/站牌） | Godot 引擎内置 Primitive Mesh（BoxMesh / CylinderMesh / TorusMesh），由脚本与场景参数化生成 | Godot 引擎 MIT 许可（随引擎二进制分发） | 无外部文件引入 |
| 全部材质（车身漆面/玻璃/轮胎/路面/草地等） | 运行时创建的 StandardMaterial3D | 自建，无许可负担 | 纯参数化颜色 |
| UI 文本 | Godot 默认字体（引擎内置主题资源） | 随 Godot 引擎分发（MIT） | 未引入字体文件 |
| 灯光/天空 | ProceduralSkyMaterial + DirectionalLight3D（引擎内置） | Godot 引擎 MIT | — |
| 车辆品牌 | 虚构品牌"闽通 MT-10" | 自建 | 规避真实商标（宇通/金龙等在获授权前禁用） |
| 地图 | 虚构"鼓山测试场"，程序化生成 | 自建 | 未使用 OpenStreetMap 或任何真实地理数据 |
| 喇叭音效 | 运行时合成的 16-bit PCM（AudioStreamWAV，350+440 Hz 双音合成，`scripts/audio/horn.gd`） | 自建，无许可负担 | 未引入任何音频文件 |
| 对向车道交通车辆（轿车/货车/电动自行车） | Primitive Mesh 参数化拼装（`scripts/traffic/traffic_manager.gd`） | 自建，无许可负担 | 无外部模型引入 |

**累计外部素材引入数：0。**
