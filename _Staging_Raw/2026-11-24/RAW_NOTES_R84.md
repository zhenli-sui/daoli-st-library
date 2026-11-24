# R84 采集原始笔记（2026-11-24 · 五族垂直 + 复杂件方向）

> 通道：`raw.githubusercontent.com` **仍 000 不可达**；`api.github.com` 可用（只读 token，core 5000/5000）；
> 代码检索用 **code search（token，10/min）共 52 条定向查询**；文件获取一律 **codeload 整仓 tar.gz**（REST 零消耗）。

## 1. 来源表

| # | 仓 | 许可 | tier | ST/XML 文件 | 落地 | 本轮到角色 |
|---|---|---|---|---|---|---|
| 1 | `mutito/PV-RTPP` | MIT | 绿 | 8（4 个 TwinCAT XML POU） | 2 条 | 族A 光伏：屋顶电站性能比 RTPP（双面系数/POA 辐照/组件背温/逆变器可用率）+ 在线增量回归 |
| 2 | `Beckhoff-USA-Community/PackML_PLC_Example` | MIT | 绿 | 21（TcPOU/TcDUT） | 5 条 | 族B 涂布/膜线：VFFS 制袋线的放卷、牵引轮、封口设备模块 + 两套配方 DUT |
| 3 | `Inxton/tcopen-app-templates` | MIT | 绿 | 170 | 1 条 | 族E 制药：泡罩线摆动给料输送（OscillatingConveyorFeeder） |
| 4 | `Gorke07/OpenDVP` | MIT | 绿 | 7 | 0 条 | 通用 stdlib（RAMP/DOSING/HEATER/MOV_AVG/TOTALIZER/SPLIT_RANGE…）**全部撞语义邻件拒** |
| 5 | `joyautomation/nautilus` | Apache-2.0 | 绿 | 209 | 0 条 | `.st` 是 Go 程序的测试数据，非 IEC 61131-3，弃采 |
| 6 | `Beckhoff-USA-Community/SPT-Libraries` | MIT | 绿 | 0 | 0 条 | 代码在 `.library` 二进制内（105 个），无文本 ST，弃采 |
| 7 | `Beckhoff-USA-Community/XPlanarApplicationLibrary` | MIT | 绿 | 0 | 0 条 | 无 ST 文本 |
| 8 | `EsraaMOH1/plc-chemical-process-project` | **GPL-3.0** | 红 | — | **零拉取** | 化学工艺梯形图；红区只记思想：加料→搅拌→放热联锁的判据顺序（不上代码） |

## 2. 拒收（许可不可判定 = 一律拒，零代码入队）

| 仓 | 情况 | ST | 价值评估（仅记录，不采） |
|---|---|---|---|
| `Billal-MOKHTARI/ics_battery_manufacturing_under_normal_and_attack_conditions` | 无 LICENSE、README 无许可声明 | 11 | **本轮最可惜**：唯一含锂电池涂布 dancer/张力语义的实件（族B）|
| `NiklasEngineering/Jacob-Formschaumtechnik-ISEL-CNC-Retrofit` | 无 LICENSE | 48 | 族C CNC 改造（含主轴/刀补） |
| `dberlin/Beckhoff-CNC-PLC` | 无 LICENSE | 21 | 族C CNC 主轴 |
| `DziadekMateusz/Przewijarka_BR_Praktyki` | 无 LICENSE | 48 | 族B 分切/收卷（波兰语注释） |
| `Prathap20/siemens-s7-1500-robotic-cnc-cell` | 无 LICENSE | 3 | 族C 机器人上下料单元 |
| `trianglexx/fse` | 无 LICENSE | 428 | 通用工艺库（428 文件） |
| `komatic1/SCL_PCS7_AdvLib` | 无 LICENSE | 43 | 族D 投料计量（PCS7 AdvLib DoseL.scl） |
| `AutomacaoLS/Coamo-UBS1-CLP` / `Coamo-Furnas-B300-CLP` | 无 LICENSE | 95 / 98 | 族D 计量/配方（DiscrepDosagem） |
| `yhl4095822731/std_i2980_v2.06_cp053` | 无 LICENSE | 71 | 族C 注塑机（IMM）SPC 曲线 |
| `Po-Yu-Chang/TcDigitalTwin` | 无 LICENSE | 459 | 数字孪生（459 文件） |
| `muqsithanif/reactor-plc-trainer` / `MadMods96/industrial-batch-reactor-digital-shadow` / `ZengLLQ/galen-pulse` | 有 MIT 但**零 ST**（Python/VB/TS） | 0 | 族D/E 只到文档层，无 ST 实件 |

> **口径不一致预警**：`Dariusz791/Rybno` API 现报 `spdx=null`（R82 记作 NOASSERTION 黄区并已采）。
> 本轮按"不可判定即拒"未采其 `FB_GranulationProcess.TcPOU`（族E 制粒，唯一命中的制粒实件）。
> 建议对 R82 黄区 28 条做一次许可复核，或统一口径后回补该件。

## 3. 五族命中与实证空白

| 族 | 命中条数 | 说明 |
|---|---|---|
| A 光伏组件生产 | **1**（+1 在线回归） | 只有电站侧（RTPP/PR/辐照），**串焊/层压/EL/IV 分档 0 命中**（`electroluminescence`=0、`"IV curve"`=0、`stringer` 全词被 LLVM 噪声淹没） |
| B 锂电池极片涂布 | **5** | 实为**膜/卷材通用线**（VFFS 放卷-牵引-封口），涂布面密度/辊压/分切 0 命中；`"areal density"`=2 且均非 ST |
| C 汽车零部件机加工 | **0** | 6 条查询全空或全为无证仓；含"刀具寿命"语义的实件全在无 LICENSE 仓 |
| D 化工间歇反应釜 | **0** | 唯一"batch reactor"实件是 VB/Python 仿真；`exotherm`/`jacket` 命中全在 md 文档 |
| E 制药固体制剂 | **1** | `"tablet press"`=0、`"fluid bed"`=0、`"film coating"`=0、`"coating drum"`=0；只得泡罩线给料 1 件 |
| 复杂件 4 向 | **0** | 涂布面密度闭环 / 反应釜放热失控 / 刀具寿命 / 压片片重 **四向皆 0**；可借的只有 `FB_RTPP` 的「物理模型 + 在线回归修正」架构（已写入其 note，作面密度闭环的骨） |

## 4. 拆件裁定（重要，供复核）

- `FB_RTPP` **内部实例化** `FB_RTPP_CALC` 与 `RTPP_REG`（`PlantCalc : FB_RTPP_CALC` / `Reg : RTPP_REG`）。
- **入队 `FB_RTPP`（复合体）+ `RTPP_REG`（在线增量回归）**，**剔除 `FB_RTPP_CALC`**（纯数值折层，独立价值≈0，属"拆件凑数"，R63 `AllpassFilter` 先例）。
- `RTPP_REG` 保留理由：`FC_DL_LinearRegression2Var` 是**批式两变量**，`RTPP_REG` 是**流式增量**（M/C 全局保持 + 1000 点缓冲 + 自适应采样 15s/60s），非同一功能；已在 `dedup.semantic` 留 `warn-neighbor` 供编码席复核。
- 若总监认为应严格"一仓一件"，可只留 `FB_RTPP`（删 `RTPP_REG` 一行，先备份）。

## 5. 语义邻件拒（有据可查）

`FB_Machine`（↔ MachineGuardAudit/NailMachineSeq）、`FB_MOVING_AVG`（↔ ExpMovingAvg/WeightedMovingAvg）、
`FB_Sealer` 曾误判邻 `CaseSealerFlapFoldSeq`（纸箱封箱翻盖 ≠ 立式膜封口）→ **人工裁定保留**；
`TcoPlb/Pls/PlrPaletizator` 三件（↔ PalletizerLayerSeq/Station/LayerBuildSeq 已在册）→ **拒**；
OpenDVP 的 `RAMP/SETPOINT_RAMP/TOTALIZER/SPLIT_RANGE/DOSING/HEATER/GATE`（registry 均有属主）→ 拒；
`LOWPASS`（↔ LowPassFilter）、`MOV_AVG`（↔ 两个 MovingAvg）→ 拒。

## 6. 工具缺陷（如实记录）

1. `oss_harvest.py` 的 `SIG` 正则 `(?:\w+\.)+\s+)?` 可选组会把 `EXTENDS`/`PUBLIC`/`PRIVATE` 捕获成块名 → 本轮 20 条垃圾名（已修，见 `_r84_harvest2.py` v4）。
2. `--search` 会**覆盖** `_Staging_Raw/_harvest_manifest.json`（不追加），R83 的 14 仓台账被重置后仅剩 3 仓。
3. 工具只查 registry 不查**队列**，同轮两次跑必产重复行（本轮 +2 条 `VAR_INPUT`/`E_SMStatus`，已标 `status=rejected` 未删行）。
4. `--max-files-per-repo` 按体积升序取件，TcPOU 本体常被小 DUT 挤掉（本轮 PackML 前 12 件全是小 DUT，改按语义加权后才取到 `FB_Unwind`）。
5. `org:PLCnext-Community` 查询稳定 **422**（R74 复现）。

## 7. 本轮文件清单

- 采集脚本：`_r84_cs.py` `_r84_cs2.py` `_r84_cs3.py` `_r84_repos.py` `_r84_lic.py` `_r84_harvest.py` `_r84_harvest2.py` `_r84_filter.py` `_r84_final.py` `_r84_enqueue.py`
- 数据：`_r84_cs.json` `_r84_cs2.json` `_r84_cs3.json` `_r84_repos*.json` `_r84_repohits.json` `_r84_build.json` `_r84_build_f.json` `_r84_final.json`
- 队列：`candidate_queue.jsonl`（200 → 210 行，净入队 8）；备份 `candidate_queue.jsonl.backup_R84_pre.jsonl`
- 指纹：`_Staging_Raw/_dedup_fingerprints.json`（51 → 59）
