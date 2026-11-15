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
| 右侧车道同向交通车辆 | Primitive Mesh 参数化拼装（同上，v0.1.3 双向化） | 自建，无许可负担 | 无外部模型引入 |
| 红绿灯（灯杆/灯箱/三色灯/倒计时牌/停车线） | Primitive Mesh + Label3D 参数化生成（`scripts/traffic/traffic_light_manager.gd`） | 自建，无许可负担 | 无外部模型/贴图引入 |
| 车内语音播报 | Windows 系统 TTS（DisplayServer，运行时调用操作系统功能，`scripts/audio/voice_announcer.gd`） | 操作系统随附功能，非素材文件 | 未引入任何音频/语音文件 |
| V0.3 车辆音效（发动机起动/怠速/变调循环、曲轴、路面、风噪、气刹放气、驻车制动、转向灯咔嗒） | 运行时合成的 16-bit PCM（AudioStreamWAV，`scripts/audio/audio_synth.gd` + `vehicle_audio.gd`） | 自建，无许可负担 | 未引入任何音频文件；**非真实客车录音**（合成音效，如实标记）。素材选型说明：曾检索 CC0 素材（sfxmint 等，均为 AI 生成 MP3、非真实录音且循环接缝不可控），评估后维持本项目零外部素材原则 |

**累计外部素材引入数：0。**
