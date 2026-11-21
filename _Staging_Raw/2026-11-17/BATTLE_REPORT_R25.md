# BATTLE REPORT — R25（含 R25-RESUME 终审与文档增量）

> 轮次：R25 + R25-RESUME ｜ 日期：2026-11-17 ｜ 库版本 **v2.14.0** ｜ 召唤模式：原生（连续第 12 轮）
> 前序：R25 首轮编码因上游异常 0/20 中止（记录见 `BATTLE_REPORT_R25_ABORT.md`，规划资产全量复用）；本报告为 R25-RESUME 收口战报。

## 1. 目标与完成（20 目标 / 4 批）

| 批次 | 件数 | 内容 | 状态 |
|---|---|---|---|
| 批 1 | 5 | Affine2DInvert(Ma) / ParticleCounterStat(Al) / CoolingTowerApproachCalc(Al) / InverterGridSync(Dv) / HeatPumpDefrost(Dv) | 全落盘 |
| 批 2 | 5 | VavBoxCtrl(Dv) / WaferMapping(Dv) / DuctStaticReset(Al) / DewpointReset(Al) / RoomClimateCtrl(Pr) | 全落盘 |
| 批 3 | 5 | StackingAlignCtrl(Mo) / WeightCheckReject(Pr) / LabelApplySync(Mo) / CasePackerPattern(Pr) / BatteryTestCycler(Pr) | 全落盘 |
| 批 4 | 5 | PalletizerLayerSeq / SplicerAutoJoint / ChillerSeqMgr / FormationChannelMgr / SolarStringGroundFault（均 Pr） | 全落盘 |

- 落盘 **7,097 行**；终审修复 6 件后 **7,174 行**（+77）。
- 今日（11-17）：**60 / 200**（R23 20 + R24 20 + 本轮 20）｜总库 **444 / 10,000**｜距 500 冲刺差 **56 件**。
- JSONL：**444 条**，全量 sha256 **0 漂移 / noPOU 0**（终审重注入 6 行后复验）。
- 码位 CLASH = **NONE**；游标 0001 `0471`/`03BF`、0002 下一 CC `0x37`、0003 `0198`/`0375`、0004 `01EF`/`0312`、0005 `0412`/`035D`。

## 2. 终审结论（8 件定向推演）

| 件 | 结论 | 关键判据 |
|---|---|---|
| `FB_DL_BatteryTestCycler` | **修 v1.0.1** | `eFault(99)` 无 CASE 标签 → 落 ELSE 兜底，每拍把 034B/034C 覆盖成 034D，激励消失后真因码丢失（安全侧不变） |
| `FB_DL_ChillerSeqMgr` | **PASS** | 机构闸单出口全撤；eWait 相均 ≥3 出口；低温保护每拍减 1 经段 7 保底回 1（不外显抖动）；轮值件 bReset 透传 |
| `FB_DL_RoomClimateCtrl` | **修 v1.0.1** | PID 失能输出回 `rOutMin=−100%` → 分程映射 100% 冷却，四阀归零等下一拍 eIdle，失能沿破坏契约 |
| `FB_DL_SolarStringGroundFault` | **修 v1.0.1** | 预警阈值可配到 ≥ 哨兵 `1.0E9 kΩ` → 退化分支哨兵被判「低于预警」误报警；补 035A 组态闸 |
| `FB_DL_SplicerAutoJoint` | **修 + 挂账** | `eSyncWait` 仅 1 个事件出口（补退回 ePreAccel）；同步相无自有超时 → 挂账 |
| `FB_DL_PalletizerLayerSeq` | **修 v1.0.1（2 处）** | 旋转层平移量用整条托盘长（首行足迹到 1500 越界）；`bPalletDone` 同拍置撤（脉冲宽度 0） |
| `FB_DL_VavBoxCtrl` | **修 v1.0.1** | 非有限闸安全侧赋值引用 `fOpenMinPct`（本闸判定集合内）→ NaN 下限把 NaN 当安全值出口 |
| `FC_DL_Affine2DInvert` | **PASS** | 4 向量回代全中（恒等 / rot90+平移 `M×M⁻¹=I` / 奇异→046F / 剪切缩放往返）；4 槽码位口径合法 |

交叉扫描另命中 **6 件同型缺陷**（`eFault` 枚举无 CASE 标签）：InverterGridSync / HeatPumpDefrost / DuctStaticReset / ParticleCounterStat / CoolingTowerApproachCalc / DewpointReset → R106 第二档整批挂账。

## 3. 两项规格勘误（独立验算，均裁定编码者正确）

1. **§4.16 层容量**：派单「1200×1000 / 400×300 → 容量 6」算术有误，实算正交 `3×3=9`、旋转 `4×2=8` → **9**；验收向量②应改 **10 → 034E**。已回写派单书勘误注记。
2. **§4.20 绝缘公式**：派单乘式分子分母倒置（完全平衡得 0 kΩ → 绝缘良好判成短路），编码者除式两端极限均正确；哨兵 `1.0E9 kΩ` 合理（高于真实读数 3 个数量级、高于预警阈值 6~7 个数量级、两极同取使失衡比恒 1）。已回写注记。

## 4. 修复件（对外引脚契约零变更，v1.0.0 → v1.0.1）

`PalletizerLayerSeq` ｜ `SolarStringGroundFault` ｜ `VavBoxCtrl` ｜ `RoomClimateCtrl` ｜ `BatteryTestCycler` ｜ `SplicerAutoJoint`。JSONL 6 行按 R19-2 五步法重注入（含 `architecture_thought` 勘误句），registry version/line_count 同步。

## 5. 挂账（进 ROADMAP P0）

- Splicer 同步相超时：新增 `tSyncMax`（MINOR）；向量「速度差恒 5% / 容差 2% → 超时 0351 且裁切指令全程 FALSE」。
- `eFault` 标签缺失 6 件批次共性：统一补标签 + 机检规则「枚举成员 ⊆ CASE 标签」。

## 6. 所用源与召唤模式

- **零检索轮（0/3）**：18 项 ROADMAP §7 勾销 + 源矩阵补口（T1-2 `ROOM_CONTROL` 开族 2 件、T2-1 仿射逆映射 1 件 → 三元闭环齐备）。
- 召唤模式：**原生召唤成功，连续第 12 轮**。

## 7. 专家进化与文档

- 新增规则 **10 条 R122~R131**（PLC 线 R127~R131 / 总监线 R122~R126），全局游标 R121 → **R132**。
- 文档：README 徽章 444/10,000 + 本轮区块 ｜ CHANGELOG v2.14.0 ｜ 五本 VERSION（1.18.0 / 1.13.0 / 0.15.0 / 0.15.0 / 0.15.0）｜ 五本 MANUAL 追加 20 件接口表 ｜ 源矩阵 T1-2 / T2-1 回写 + R25 实测行 ｜ ROADMAP 勾 18 + 补勾 2 + 新增 10 ｜ AGENT_EVOLUTION_LOG「R25-RESUME」节。

## 8. 超时说明与下轮计划

- **实际约 75 分钟 > 50 分钟上限**：20 件分两次编码调用 + 终审 6 件修复与重注入 + 十份文档增量。
- 下轮：先清 P0 挂账（Splicer `tSyncMax`、6 件 eFault 标签、三条新机检规则），再开新件；编码合并单次调用，修复/重注入独立小环。
- 距 500 冲刺：**56 件**（约 3 轮）。

## 9. 轻微留档（不硬改、随战报发布）

- `FC_DL_Affine2DInvert`：`fDetEps` 未入非有限闸（NaN 容差使相对奇异判据失效，实际落段 5 溢出闸兜底，安全侧可达）。
- `FB_DL_InverterGridSync`：`fFreqTolHz` / `fPhaseTolDeg` / `fVoltTolPct` 未入非有限闸（NaN 容差使窗判据恒 FALSE → 许可被挡，方向安全但静默）。
- `FB_DL_VavBoxCtrl`：`fFbTolPct` 未入非有限闸（NaN 使卡滞诊断静默失效）；已进 ROADMAP P1。
- `FB_DL_BatteryTestCycler`：`bCapSat` 一旦置位仅由复位清除，0407 会长期压过 0406 切相提示（语义为「曾饱和」，留档不改）。
- `FB_DL_ChillerSeqMgr`：两只延迟定时器谓词取上一拍值（单拍滞后，分钟级窗无影响）但头注释未声明；`tRotateInterval := T#24H` 为调用点字面量。
- 历史 `line_count` 口径 off-by-one：**95 条历史行**注册表值比 `splitlines()` 实测多 1（原文按 `wc -l` 口径、文件末尾无换行），本轮新增 20 件与本轮 6 修复件均与实测一致；因「不改既有 registry 行」纪律本轮不修，列下轮历史层体检项。

---

*R25-RESUME ｜ 2026-11-17 ｜ 道莅工控代码库产品总监*
