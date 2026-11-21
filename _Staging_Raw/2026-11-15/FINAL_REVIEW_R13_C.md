# R13 终审报告 · 泳道 C（DL_Algo 1 + DL_Motion 1 + DL_Process 4）

- 终审人：道莅工控代码库产品总监（兜底模式）
- 日期：2026-11-16
- 规格依据：`ROUND_PLAN_R13.md` §3.0（第 126~152 行）、§7 历史范式点名（第 1548~1598 行）、§3.3 泳道 C（第 905~1349 行）
- 机检：`audit_library_r13.py`，16 条规则全 0 FAIL / 0 WARN（详见 §7）
- 边界：只修改下列 6 个对象文件与本留痕文件，未触碰其他库文件

---

## 1. FB_DL_FoulingResistanceEstimator（DL_Algo · C1）

**对照结论**：引脚（19 入 / 12 出）、5 态状态机、码位 `0002_2201~2204` / `2210~2212`、验收向量 V1~V5 全部按规格实现。

- 污垢热阻公式量纲链复核（R20）：Q = m³/h × kg/m³ × kJ/(kg·K) × K ÷ 3600 → kW ✓；K = Q[W]/(A·LMTD) 除零双守卫（面积闸门 >0 + LMTD ≥ fDtmMinEff ≥ 0.5 K）✓；LMTD 等端差退化算术平均、温度交叉置 0 → 2211 ✓。
- 对数/温差防除零防负数：`_fLmtdAbs < EPS` 退化、`_fDt1/_fDt2 <= 0` 拦截、`_fKCalc > EPS` 才做倒数 ✓。
- R19 首扫：首拍有效值只进保持量、`_bSkipSample` 不压趋势样本 ✓（V5）。
- R42/V4：流量门限每拍在段 4 对实时入参复验，不合格即拒绝更新、不累计斜率样本 ✓。
- R43：fQ/fLmtd/fK/fRf/fRfSlope 五条出口路径逐一有 LIMIT 钳位 ✓；R31 枚举映射 5 值全显式标签（eAdvice/eFault 空标签带原因注释）✓。
- 偏离裁定：① 自学习参考流量（规格未给额定流量引脚）——**采纳**，语义等价且已留档；② V1 LMTD 49.7 vs 50.0 属等温差退化口径差——**采纳**；③ 非有限输入并入 2210——**采纳**（规格只给 3 个故障码，不得自行增码）。

**缺陷列表**：无。
**升版**：维持 v1.0.0。
**终审判定**：**PASS**。

---

## 2. FB_DL_PassiveHomingMonitor（DL_Motion · C2）

**对照结论**：引脚、6 态状态机、码位 `0004_01C3~01C6` / `02D2~02D4`、V1~V5 按规格实现；未自造轴状态、未定义轴状态枚举、未发运动指令（专项纪律 4）✓。

- R40：`_fbTonArmTimeout` / `_fbTonNoMotion` 两定时器 IN 均串 `NOT _bArmBreak`，断输入拍布防时置位、段 3 无条件自清 ✓。
- R38：fActPos/fActVel 唯一消费点 = 段 4 快照，事件受理与限幅判定全读快照 ✓。
- R41/V3：超时后重新布防在段 5 从 0 重建计数与倒计 ✓；R34 倒计置位（段 5）/递减（段 6）相邻 ✓。
- 方向反转（V2）与位置超容差（01C6）双判据、计数重置语义正确 ✓。

**缺陷列表**：

| 编号 | 严重级别 | 描述 | 处置 |
|---|---|---|---|
| D-C2-1 | 中（坏值穿透） | 段 6 事件受理条件未排除本拍故障条件与掉使能：非有限值在段 4 被检出、快照置零的同一拍，若恰有参考事件沿，零化快照仍被采信；极端情形（该事件凑满一致性计数）把 0.0 锁存进 `_fRefPosHeld` 并置位 `_bRefLatched`——脏值直达 bReferenced 保持位，违背 V4「不写脏值」语义 | 已修复：受理条件补串 `AND bEnable AND (NOT _bFaultCond)` |

**修复内容**：段 6 受理门槛补两条件 + 头注释留痕。
**升版**：v1.0.0 → **v1.0.1**（修订历史追加 2026-11-16 变更行）。
**终审判定**：**PASS（修复后）**。

---

## 3. FB_DL_CapperTorqueTrend（DL_Process · C3）

**对照结论**：引脚、5 态状态机、双枚举、码位 `0005_01C5~01C7` / `02F3~02F5`、五类 NG 判据与主判定优先级（滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常）按规格实现；不内联分位/滤波（fBatchP10/P90 引脚注入）✓。

- R24/R25/V3：`bCycleStart` 沿在段 1 无条件刷新、消费后置 `_bStartConsumed`、输入回落解除，eSampling 内保持 TRUE 两拍不二次触发 ✓。
- R27/V4：eVerdict/bVerdictValid/uNgMask/三特征值逐拍由保持量重写 ✓；R44 清码点绑定新轮起点 ✓；R38 点数一次锁存 `_nPtsEff` ✓。
- 趋势窗采样时序：曲线就绪 = 点数连续两拍不变（偏离留档③，裁定**采纳**）；峰值/均值统计窗边界（峰后段、稳态带、峰前差分变号）与 V1/V2 复核一致 ✓。

**缺陷列表**：

| 编号 | 严重级别 | 描述 | 处置 |
|---|---|---|---|
| D-C3-1 | 中（状态机迁移违背规格） | 段 6 评估中检出非有限样本（02F4）置 `_bFaultCond`，但评估相出口**无条件**转 `eVerdict`——规格迁移表要求「任何态--非有限--> eFault(99)」；实际停在判定相，下一 `bCycleStart` 可绕过复位直接开新周期，故障态锁存语义失效 | 已修复：出口按 `_bFaultCond` 分流，故障时转 `eFault` 等复位 |

**修复内容**：评估相出口增加故障分流分支 + 头注释留痕。
**升版**：v1.0.0 → **v1.0.1**。
**终审判定**：**PASS（修复后）**。

---

## 4. FB_DL_EscHeLeakCheck（DL_Process · C4，R40 重点核对件）

**对照结论**：引脚、6 态状态机、码位 `0005_01C8~01CA` / `02F6~02F8`、本底（升压）/增压（稳压）/保持（测量）三段判据按规格实现。

- **R40 逐定时器核对**（本轮最高密度缺陷区）：
  - `_fbTonPress`｜IN = (相位=ePressurize) AND NOT `_bPressBreak` ✓
  - `_fbTonStab`｜IN = (相位=eStabilize) AND NOT `_bStabBreak` ✓
  - `_fbTonStabExt`｜IN = (相位=eStabilize) AND `_bStabExtended` AND NOT `_bStabExtBreak` ✓
  - `_fbTonMeas`｜IN = (相位=eMeasure) AND NOT `_bMeasBreak` ✓
  - 四实例互不共用、无跨段恒真；断输入拍在段 2 无条件自清；V3 的「共用 TON 会被 50 s 提前触发」歧义可被本实现区分 ✓。
- 中止恢复（V4）：掉使能 → eAborted + bDone 保持，重新 bStart 断输入拍保证三段计时从 0 ✓；R36/R41 精神满足；V5 非有限不写脏值 ✓；温漂修正带温差门限与系数钳位、压降上升方向故障 02F7 ✓。

**缺陷列表**：

| 编号 | 严重级别 | 描述 | 处置 |
|---|---|---|---|
| D-C4-1 | 中高（功能失效，R40 家族） | 稳压延长窗裁决条件为 `_fbTonStab.Q OR _fbTonStabExt.Q`：延长置位后主稳压定时器 IN 未断、Q 保持 TRUE，**下一拍**即落入「延长后仍不稳」分支提前进测量——`_fbTonStabExt` 全程未计时，01C8「已延长一次」名存实亡，测量起点压力取在延长窗开始而非结束时刻，且弱稳定降级提前触发 | 已修复：以 `_bStabExtended` 区分两窗——延长窗内仅由 `_fbTonStabExt.Q` 裁决，主稳压定时器不再参与；收敛路径显式清 `_bStabWeak` |

**修复内容**：段 5 eStabilize 分支重构（约 20 行）+ 头注释留痕。
**升版**：v1.0.0 → **v1.0.1**。
**终审判定**：**PASS（修复后）**。

---

## 5. FB_DL_ChamberSeasoningTrack（DL_Process · C5）

**对照结论**：引脚、5 态状态机、码位 `0005_01CB~01CE` / `02F9~02FB`、双判据（片数 ∧ 时长）放行、连续越窗降级按规格实现。

- **跨段累加语义核对（R42 家族关切）**：规格本意即**累计制**——`tAccum` 由 `tProcessTime` 引脚逐片累加（偏离留档②已论证为何不用墙钟），清零出口 = `bReset` 沿（V5：nCount=0、tAccum=T#0S、nRoundId+1、不保留 fThickSlope 基准）。与规格 V1/V2/V5 完全一致，**非跨段违规**，裁定**采纳**。
- R37/V4：`LEN` 一次锁存 → 超宽显式置 01CE → `LEFT` 取前缀写回登记缓冲（非回夹），偏离留档①（引脚提为 STRING(80) 防调用方静默截断）裁定**采纳** ✓。
- V3：配方键缺失 → 02F9 锁存，段 5 故障前置强制 `_bReleaseLatched := FALSE`（安全侧不放行）✓；R31 五值全显式标签 ✓；R19/R41 首片基准仅装一次、复位清除 ✓；溢出守卫 02FA（30000 片 / 40 天）判据与守卫同向 ✓。

**缺陷列表**：无。
**升版**：维持 v1.0.0。
**终审判定**：**PASS**。

---

## 6. FB_DL_ReactorJacketDeltaT（DL_Process · C6）

**对照结论**：引脚（含增补 `tCycle`，偏离留档①裁定**采纳**——限速步长需真实周期）、5 态状态机、码位 `0005_01CF~01D1` / `02FC~02FE` 按规格实现；不内联 PID，限速**组合调用** `FB_DL_RateLimiter`（引脚契约逐一核对：bEnable/fIn/fRateUp/fRateDown/bTrack/fTrackValue/tSampleTime → fOut/bLimiting，全匹配）✓。

- 交叉极限保护：温差触限带 0.5 K 回差锁存、eHeat 冻结目标 0、经限速器按 `fDeltaTRate` 折算速率斜坡回 0（限速非限幅，V2/V4 复核通过）✓；超温强制冷却 + 回差 ✓；冷热互斥出口（同开则保冷压热）✓。
- 传感器失效防坏值穿透（V5/02FC）：非有限/越域 → 快照置零 + 故障锁存，坏值不进控制律、不达联锁出口；两路输出经 LIMIT 夹域后写出 ✓。
- R36 跟踪首拍：头注释手算示例完整（无扰切换反算 fI），01CF 判据绑定实测温差而非指令跳变，V4 不会误报 ✓；R19 窗基准首扫只装不判、R40 统计窗断输入拍 ✓。
- 偏离裁定：②常态直通/受限限速的双工况（V1 与 V4 并存）**采纳**；③K/% 折算常量披露 **采纳**；④01CE→01CF 码位修正（防跨件撞号）**采纳**。

**缺陷列表**：无。
**升版**：维持 v1.0.0。
**终审判定**：**PASS**。

---

## 7. 机检结果

```
python audit_library_r13.py --files DL_Algo/FB_DL_FoulingResistanceEstimator.st \
  DL_Motion/FB_DL_PassiveHomingMonitor.st DL_Process/FB_DL_CapperTorqueTrend.st \
  DL_Process/FB_DL_EscHeLeakCheck.st DL_Process/FB_DL_ChamberSeasoningTrack.st \
  DL_Process/FB_DL_ReactorJacketDeltaT.st DL_Device/I_DL_DeviceHealth.st

SUMMARY: files=7 fail=0 warn=0
```

- 16 条规则全 PASS（banned_hits / placeholder / terminator / bilingual_comment / case_else / enum_case_completeness / enum_separator / nested_comment / undefined_identifier / single_colon_or_semicolon / duplicate_pou_name / r37 / r38 / r39 / r40 均 0 命中）。
- 说明：`I_DL_DeviceHealth.st`（A1 属主件）以**只读方式**加入文件集——机检脚本的跨文件符号表仅从本次传入文件构建，`E_DL_Ne107Status` 为 6 件共同引用的属主枚举，单跑 6 件时会产生 32 处同源误报；加入属主后归零。该文件未被修改。

## 8. 升版与缺陷汇总

| 文件 | 版本 | 缺陷 | 判定 |
|---|---|---|---|
| FB_DL_FoulingResistanceEstimator.st | v1.0.0（不变） | — | PASS |
| FB_DL_PassiveHomingMonitor.st | v1.0.0 → **v1.0.1** | D-C2-1 中 | PASS（修复后） |
| FB_DL_CapperTorqueTrend.st | v1.0.0 → **v1.0.1** | D-C3-1 中 | PASS（修复后） |
| FB_DL_EscHeLeakCheck.st | v1.0.0 → **v1.0.1** | D-C4-1 中高 | PASS（修复后） |
| FB_DL_ChamberSeasoningTrack.st | v1.0.0（不变） | — | PASS |
| FB_DL_ReactorJacketDeltaT.st | v1.0.0（不变） | — | PASS |

**遗留提示（移交阶段四注册前）**：6 件均无编译验证（连续 14 轮悬置），V1 手算向量已在头注释留痕；三处修复均为逻辑级，无引脚契约变更，不影响并行泳道。
