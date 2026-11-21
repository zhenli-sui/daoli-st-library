# RAW_NOTES_R41（2026-11-19 · 规划轮原始笔记）

## 0. 本轮来源说明

- **检索：零检索**。WebSearch 0/3，零外部仓库抓取、零代码行复制。
- 全部选题来源两类：
  1. 源矩阵既有 ◐ 组语义深化（零检索复用）：t2-1 LGF（Math/DataHandling/Measurement/Comparator）、t2-5 ModPID、t2-2 LBP、t1-6 PLCopen、t2-4 S7 Motion、t1-5 TcOpen、t1-2 OSCAT Building、t1-7 PLCnext、t2-7 PackML。
  2. ROADMAP 未勾项实证真缺口（逐名三段 grep 复核后入选）：ShrinkTunnelCtrl / VavDischargeAirReset / ConveyorDirMismatch 等。
- T0 组 R40 已清账（7/7 ✔），本轮无真实零命中词干，未硬凑 T0（R244 纪律）。
- 状态列变更：本轮为规划轮，源矩阵状态列不动；待编码轮收口后回写台账行。

## 1. 盘点数字

- registry v2.32.0，705 件，counts：Base 80 / MathData 193 / Algo 70 / Device 138 / Motion 66 / Process 158。
- ROADMAP 未勾 159 条（有名 138）。批量脚本初判真缺口 104 —— **抽查 5 条即证伪 3 条**（PumpDryRunGuard / TrackBarcodeTrace / StepperMicroFeedPulseEquiv 均已注册），真缺口池实际规模存疑，后续轮逐名复核后再从池中取件。

## 2. 码位实测记录（头部 1504B ∪ 全文口径）

- Level 0 段 0001 为 Base∪MathData **共用游标**（两库头注释均出现 0001_xxxx，实测交叉连续），信息 04xx 至 049D、故障 03xx 至 03DA。R40 口述「0491/03C8」为单侧时点值，本轮实扫已推进，**游标以全库 grep 实扫为准（R75②）**。
- Algo 0002：03A2 / 0488。Device 0003：**03FB 将满（余 4 位）**、041B、05xx 051B。Motion 0004：03A7 / 04A7。Process 0005：0366 / 048E；0006 B 带 3035。
- Device 故障带紧张 → R42 规划议题：启用 05xx 副故障带，头注释须写分段理由（R192）。

## 3. R41 新经验（待编码轮结束后正式入 DIRECTOR_EVOLUTION）

- **R41-1 选题**：批量脚本单查不可信——一轮脚本漏检导致 104 条「真缺口」掺假（抽查 5 条 3 假）。规划侧一律「registry 精确名 + 全库 .st 文本 + 同义词干」三段逐名独立 grep，命中即拒。本轮候选 28 件，拒 8 件（3 条假缺口 + 5 条同义在册：HistogramAccum / GainScheduler+PidGainScheduler / BumplessTransfer / AxisLoadTorqueMonitor / TankN2BlanketCtrl / BacklashCompensator / LamHeaterZoneSync）。
- **R41-2 观察**：ROADMAP 假缺口率再次上升（R38 实测 138/183，本轮抽样 3/5），三向一致专项回写（R192）债务仍未清，建议 R42 排程首位出「ROADMAP 未勾项全量逐名复核 + 回写」专项轮。
- **R41-3 观察**：进位点向量候选——FC_DL_AngleDiffWrap 的 ±180.0 正好边界、FC_DL_QuantileCalc 的 (n-1)*q 正好整除点，已在派单规格写入向量，编码轮终审按 R28-2 逐条核。

## 4. P0 返修件（3 件，registry 实测路径）

1. `C:\Library\DL_Motion\FB_DL_AxisLimitRecovery.st` —— R240 锁存解除恒假。
2. `C:\Library\DL_Base\FB_DL_MutexOwnerAudit.st` —— R241 UDINT→DINT 降型溢出 + 饱和闸不可达。
3. `C:\Library\DL_MathData\FC_DL_StringToDint.st` —— R40 出口 038B 未配对 bError。

## 5. 待编码轮执行提醒

- 收口链固定：落盘 → CRLF → 六项机检 → 演进账本（R40 固化），缺一步不许回报完成。
- 单窗 ≤15 件（R239）；20 新件超时即双窗拆分。
- 终审 5 抽挂账 ≥3 即扩族全量返修（R193/R194）；机检 PASS 轮抽检深度不下调（R243）。
- 故障码单轨检查：Motion/Device/Process 段新件码段与本轮窗口连续，无跨段断点，分段理由无需另写（除 Device 05xx 溢出情形）。
