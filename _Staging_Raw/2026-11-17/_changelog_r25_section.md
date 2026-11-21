
---

## [v2.14.0] — 2026-11-17 ｜ R25 暖通深度 + 洁净室/锂电/光伏工艺 20 件 / Round 25 — HVAC Depth, Cleanroom, Lithium and PV Process Templates

**阶段**：Phase 1 第二十五轮 ｜ **新增组件**：20（`DL_MathData` 1 ｜ `DL_Algo` 4 ｜ `DL_Device` 4 ｜ `DL_Motion` 2 ｜ `DL_Process` 9，合计 **7,097 行**（终审修复后 **7,174 行**））｜ **累计**：**444 / 10,000** ｜ **子库版本**：`DL_MathData` v1.17.0→**v1.18.0**、`DL_Algo` v1.12.0→**v1.13.0**、`DL_Device` v0.14.0→**v0.15.0**、`DL_Motion` v0.14.0→**v0.15.0**、`DL_Process` v0.14.0→**v0.15.0** ｜ **码位**：0001 `0471`/`03BF`、0002 下一 CC `0x37`、0003 `0198`/`0375`、0004 `01EF`/`0312`、0005 `0412`/`035D`（CLASH=NONE）｜ **机检**：19/20 PASS，1 项为**纯函数件 4 槽码位口径误报**（`FC_DL_Affine2DInvert` 按 §3.1 只分配 4 码，「5~6 槽」规则对纯函数件不适用，裁定 PASS，规则口径列入待修）｜ **JSONL**：**444 条**全量 sha256 MATCH ｜ **终审**：8 件定向推演 → 4 PASS / 3 修 / 1 挂账，交叉扫描另命中 3 件同类缺陷一并修，合计 **6 件升 v1.0.1** ｜ **距 500 冲刺**：差 56 件

### 新增 / Added

| 子库 | 组件 | 类型 | 说明 |
|---|---|---|---|
| DL_MathData | `FC_DL_Affine2DInvert` | FC×1 | 二维仿射矩阵求逆（2×2 伴随 + 平移列反算），奇异输出全零矩阵、不泄半逆；仿射「合成-应用-逆」三元闭环齐备 |
| DL_Algo | `FB_DL_ParticleCounterStat` | FB×1 | 洁净室粒子计数 ISO 14644-1 等级判定（表驱动免幂运算 + 失采识别 + 等级清零安全侧） |
| DL_Algo | `FB_DL_CoolingTowerApproachCalc` | FB×1 | 冷却塔逼近度与加/减风机台数建议（湿球组合调用 + 逼近度为负判传感器可疑） |
| DL_Algo | `FB_DL_DuctStaticReset` | FB×1 | 风管静压设定重置（最不利阀位 + 死区 + 限斜率 + 能力不足如实上报） |
| DL_Algo | `FB_DL_DewpointReset` | FB×1 | 冷冻水供水温度按露点重置（露点 + 安全余量 + 斜率限制；除湿能力不足报出而非静默顶上限） |
| DL_Device | `FB_DL_InverterGridSync` | FB×1 | 逆变器并网四窗核对与合闸许可（只出许可不控合闸，四窗映射 WORD 掩码） |
| DL_Device | `FB_DL_HeatPumpDefrost` | FB×1 | 空气源热泵三条件除霜（最小间隔 + 超时强制退出回制热） |
| DL_Device | `FB_DL_VavBoxCtrl` | FB×1 | 压力无关型 VAV 风量闭环（PI 组合调用 + 设定/开度双限幅 + 反馈无效保持开度） |
| DL_Device | `FB_DL_WaferMapping` | FB×1 | 晶圆盒槽位 Mapping（片位图 + 空位/双片/斜插三分型 + 边界防护） |
| DL_Motion | `FB_DL_StackingAlignCtrl` | FB×1 | 叠片机 CCD 纠偏（标定阵经 `FC_DL_Affine2DInvert` 求逆 + 行程限幅 + NG 锁存至复位） |
| DL_Motion | `FB_DL_LabelApplySync` | FB×1 | 贴标同步出标（编码器提前量 + 饱和钳位 + 低速暂停出标） |
| DL_Process | `FB_DL_RoomClimateCtrl` | FB×1 | 房间温湿度双回路耦合（双 PID 带符号分程 + 防结露联锁 + 冷侧优先互斥仲裁） |
| DL_Process | `FB_DL_WeightCheckReject` | FB×1 | 动态称重与剔除（滤波窗 + 剔除器拒动诊断 + 无料跳过 + 停线判据） |
| DL_Process | `FB_DL_CasePackerPattern` | FB×1 | 装箱排列图案（容量钳位 + 交错/层旋转 + 末层留空位提示） |
| DL_Process | `FB_DL_BatteryTestCycler` | FB×1 | 单通道充放电工步机（恒流/恒压/静置七步 + 安时积分饱和 + 温度电压硬判断流） |
| DL_Process | `FB_DL_PalletizerLayerSeq` | FB×1 | 码垛层排布顺控（层容量两取向自算 + 奇偶层旋转走 `FC_DL_Affine2Apply` + 取放握手重试） |
| DL_Process | `FB_DL_SplicerAutoJoint` | FB×1 | 自动接膜零停机顺控（余量按面积折算 + 速度同步双条件 + **未同步绝不裁切**） |
| DL_Process | `FB_DL_ChillerSeqMgr` | FB×1 | 冷水机组群控（双延迟加减机 + 轮值委托 `FB_DL_DutyStandbyRotation` + 供水低温强制减机） |
| DL_Process | `FB_DL_FormationChannelMgr` | FB×1 | 化成/分容多通道调度（分配 + 异常通道隔离锁存 + 批次台账） |
| DL_Process | `FB_DL_SolarStringGroundFault` | FB×1 | 光伏组串对地绝缘阻抗（不平衡电桥 + 完全平衡退化显式分支 + 分级确认锁存） |

### 修复 / Fixed（R25 终审，对外引脚契约零变更，均升 v1.0.1）

| 组件 | 版本 | 级别 | 缺陷 | 处置 |
|---|---|---|---|---|
| `FB_DL_PalletizerLayerSeq` | v1.0.0→**v1.0.1** | 中等 | 旋转层阵外平移量用整条托盘长（1200×1000 配 400×300 箱体时首行落点得 1200，加足迹 300 越界到 1500）；且 `bPalletDone` 在 `ePalletEnd` 相内先置 TRUE 再同拍置 FALSE，脉冲永不外显 | 平移量改为 `(nRowsEff−1)×箱宽`；撤销点移交 `eIdle` 相（恰好一拍 TRUE） |
| `FB_DL_SolarStringGroundFault` | v1.0.0→**v1.0.1** | 轻微（域端点） | 预警阈值可被配到 ≥ 上限哨兵 `1.0E9 kΩ`，完全平衡退化分支的哨兵值会被判成「低于预警阈值」而误报警 | 组态闸补 `fWarnKOhm >= DL_SGF_R_MAX → 035A` |
| `FB_DL_VavBoxCtrl` | v1.0.0→**v1.0.1** | 中等 | 非有限闸的安全侧赋值写 `fOpenMinPct`，而下限脚本身在本闸判定集合内 → 下限脚为 NaN 时把 NaN 当安全值出口（安全侧自我失效） | 先算可用下限 `fFloorPct`（脚非有限回默认 20%），闸内统一用 `fFloorPct` |
| `FB_DL_RoomClimateCtrl` | v1.0.0→**v1.0.1** | 中等（安全侧） | PID 件失能时输出回 `rOutMin=−100%`，经带符号分程映射成 100% 冷却；四阀归零要等下一拍 `eIdle`，失能沿那一拍破坏「失能=四阀回 0%」契约 | CASE 之后补段 11 失能出口收口，失能电平期间四阀强制 0% |
| `FB_DL_BatteryTestCycler` | v1.0.0→**v1.0.1** | 中等（诊断保真） | `eFault(99)` 无 CASE 标签，落进 ELSE 兜底支路每拍把 034B/034C 覆盖成 034D「非法状态」，激励消失后真因码丢失 | 补 `eFault` 独立 CASE 标签，故障码改写权归入口闸 |
| `FB_DL_SplicerAutoJoint` | v1.0.0→**v1.0.1** | 中等 | `eSyncWait` 只有 `bSyncOk` 一个事件出口，`bNewRollReady` 撤销后滞留且预加速指令长期拉住空卷（R98 家族缺「进相前置消失」出口） | 补 `ELSIF NOT bNewRollReady → ePreAccel`（两相裁切指令均 FALSE，安全铁律不受影响） |

### 挂账 / Carried Over（R106 第二档，下轮立项）

| 项 | 级别 | 复现条件 | 拟修方案 |
|---|---|---|---|
| `FB_DL_SplicerAutoJoint` 同步相无自有超时 | 中等 | 新卷就绪但速度差持续超容差 → 同步相无限期停留（`tPreAccelMax` 只在预加速相计时） | 新增 `tSyncMax`（MINOR）或把同步相并入 `tPreAccelMax` 计时窗；验收向量：速度差恒定 5%、容差 2% → 超时后置 0351 且裁切指令全程 FALSE |
| 批次共性：`eFault` 枚举无 CASE 标签（6 件） | 轻-中（诊断保真） | `ParticleCounterStat` / `CoolingTowerApproachCalc` / `InverterGridSync` / `HeatPumpDefrost` / `DuctStaticReset` / `DewpointReset`：激励消失后 ELSE 兜底码覆盖真因码（安全侧不变，故障仍锁存） | 统一补 `eFault` 标签（安全侧输出照抄 ELSE、码保持、零码兜底），并新增机检规则「枚举成员集合 ⊆ CASE 标签集合」 |

### 勘误 / Spec Errata（总监独立验算裁定）

- **§4.16 层容量算术**：派单验收向量①写「托盘 1200×1000、箱 400×300 → 容量 6」，实测 `floor(1200/400)×floor(1000/300)=3×3=9`（旋转取向 `4×2=8`），编码者判定「派单算术有误」**正确**；原向量②「`nCasePerLayer=8` → 034E」随之失效（8 ≤ 9 通过），应改为大于 9 才触发 034E。
- **§4.20 绝缘公式方向**：派单乘式（`Rb×(Vbus/(Vp+Vn) − 1)`）分子分母倒置——完全平衡得 0 kΩ，等于把绝缘良好判成对地短路；单极短路得无穷。编码者改除式 `R = Rb×(Vp+Vn)/(Vbus − Vp − Vn)` **正确**：`D→0 ⇒ R→∞`、`Vp+Vn→0 ⇒ R→0` 两端极限均对，且 `Rp/Rn = Vp/Vn` 与并联自洽式 `1/(1/Rp+1/Rn) = R_t` 同时成立。退化分支哨兵 `1.0E9 kΩ`（1 TΩ）**合理**：高于真实最高读数（1e5~1e6 kΩ）3 个数量级、高于告警阈值 7 个数量级，且两极同取哨兵使失衡比恒为 1（不误报失衡）。

### 收口 / Closeout

- registry v2.13.0→**v2.14.0**，424→**444** 件（counts Base 73 / MathData 152 / Algo 48 / Device 76 / Motion 38 / Process 57）；JSONL **444 行全量 sha256 MATCH**（终审重注入 6 行后全量复验，noPOU 行 0、真漂移 0）；码位 CLASH=NONE。
- 源矩阵回写：**T2-1 仿射族逆映射补口**（三元闭环齐备）、**T1-2 ROOM_CONTROL 子族开族 2 件**。
- 五本 MANUAL 各追加 R25 接口表节（引脚名与类型由 `.st` 源码机读提取，20 件全覆盖）；ROADMAP 勾选 18 项为 `[x]` 并写落地版本，增补 10 条待办。

*Last updated: 2026-11-17（R25 追加 v2.14.0 条目）*
