# HARVEST R73（2026-11-23）· oss_harvest 真采集轮

> 工具：`C:\Library\_tools\oss_harvest.py`（本轮真跑，非空转）
> 队列：`C:\Library\_Staging_Raw\2026-11-23\candidate_queue.jsonl`，终态 **29 条**
> 注意：总监指令时队列显示 0，实际本轮开始前已有存量 21 条（同日早间采集，manifest _harvest_manifest.json 可证）；本轮在其上继续补料 +8（含 1 条垃圾名修复、1 条重复剔除后净 +7）。

## 1 扫描量

- 尝试仓数：7（search 模式 3 + 定向 4）
  - 成功 listed：4 —— `tkucic/brOscatLib`、`RWTH-EBC/AixOCAT`、`OttoMeister/Siemens-Tia-Portal-PID-Controller`、`TcOpenGroup/TcOpen`
  - meta-null（404）：`TcOpen/TcOpen`、`tc-oss/TcOpen`、`PLCnext-Community/PLCnext_GetStarted`（仓已迁移/不存在，正确名 = `TcOpenGroup/TcOpen`）
  - 无关命中：`NathanLi/iOSCategoryPropertyDynamicSupport`（iOS 主题，0 文件，直接弃）
- listed / fetched / failed：**40 / 40 / 0**（本轮新增部分：search 8+12、定向 20）
- search 侧：1 条 query HTTP 422（org:PLCnext-Community）；API 限流健康（core 剩余 29/60），未触发减仓。

## 2 本轮新增（+8，净 +7）

| 原名 | 建议道莅重命名 | 借鉴点 | 许可证 |
|---|---|---|---|
| FB_PI_Regler_Legacy（原抽取名 VAR_INPUT，已修复） | `FB_DL_PiReglerLegacy` | P/I 分离、手自动切换、复位语义的接口参数域与德语命名惯例（ir_/ib_/ii_ 前缀）；实现 clean-room | WTFPL（黄区，只借骨） |
| InputBase / OutputBase / EtcSlaveBase / EtcMasterBase / SyncUnit(s)Base 等 7 个 TcOpen codegen TYPE | `I_DL_IoPortBase` 等 | TcoIo 端口抽象四元组（PLCnext port-based 范式的 TwinCAT 侧对照）；借接口分层不借 codegen | MIT（绿区） |

## 3 存量 21 条（同日早间，已复核）

- brOscatLib（OSCAT Basic 的 B&R 移植镜像，MIT）：18 条（F_LIN / F_POWER / SCALE / HYPOT / SWAP_BYTE / BYTE_TO_GRAY / FT_IMP / MANUAL / WINDOW2 / ISC_NUM+ISC_CTRL / 单位换算族等）
- AixOCAT（RWTH-EBC，MIT）：2 条（E_SMStatus 状态枚举、CONTROL_MODE 模式枚举）

## 4 许可证分布（终态 29 条）

- 绿区 MIT：28 条 ｜ 黄区 WTFPL：1 条 ｜ 红区：0 ｜ unknown：0
- 拒收数：0（红区隔离仓 0 仓；本轮无 NOASSERTION 命中入队）
- 质量门自纠：`E_SMStatus` 重复入队 1 条 → 已剔除（保持「重复入队 = 0」）；`VAR_INPUT` 垃圾名 → 已修复为 `FB_PI_Regler_Legacy`。

## 5 红区隔离

本轮红区（GPL/AGPL/LGPL）命中：0 仓。`red_quarantine: []`。零 GPL 源码行接触。

## 6 建议下轮优先消耗的 5 个候选

1. `FB_PI_Regler_Legacy` → `FB_DL_PiReglerLegacy`（手自动切换+复位仲裁防御，对应 T2-5 PID 线补口）
2. `SCALE` → `FC_DL_ScaleLin`（量程线性标定，加输入域钳位 + 除零闸）
3. `WINDOW2` → `FC_DL_WindowCompare`（窗口比较开闭区间语义，对应 LGF Comparator 组）
4. `FT_IMP` → `FB_DL_ImpulseKeeper`（脉冲成形/保持，对应 T0-2 定时器族变体）
5. `E_SMStatus` / `CONTROL_MODE` → 状态机枚举命名范式（借枚举语义组织，非代码）

## 7 合规与边界

- 未写任何 .st 文件；未改 INDEX_REGISTRY.json；未触碰 SOURCE_HUNTING_MATRIX 台账主体（仅文末追加一行）。
- 黄区 WTFPL 条目只提取接口参数域与命名惯例，未复制实现。
