# BATTLE_REPORT_R41（2026-11-19 · 20 新件 + 3 返修 + 终审收尾轮）

## 1. 目标完成度
- 20 目标 4 批全部完成：批1 5/5、批2 5/5、批3 5/5、批4 5/5（**20/20 全完成**），分布 Base 3 / MathData 4 / Algo 4 / Motion 4 / Device 2 / Process 3。
- P0 返修 3 件闭环：AxisLimitRecovery（R240 解除式全当拍量）、MutexOwnerAudit（R241 比较闸上移 UDINT 域）、StringToDint（038B 配对补齐 v1.0.2）。

## 2. 机检 22/23 PASS
- 唯一 FAIL：MutexOwnerAudit 返修暴露 **4 处存量码位冲突**（0102/0202/0302/0402 与 EventCounter / TimeWindowCheck / RorLwordEx / TimeRatioCalc）——R39 前历史债，**记账不阻断**，全库码位冲突普查列 R42 候选 P1。
- JSONL：725 条（badjson=0、新增 20 行 MATCH、3 返修件原地重注入）。registry v2.32.0 → v2.33.0。

## 3. 事故与处置
- **AngleDiffWrap 清零事故**：机检补丁脚本 `io.open(p,"wb").write(表达式)` open 截断在先、表达式求值 AttributeError 在后 → FC_DL_AngleDiffWrap.st 被清空 0 字节；靠头注释规格由主控重建，机检 MATCH。教训入册 R254（先读全量到内存、单次原子写回，禁先 open 再算内容）。
- T0 头注释溯源短语（「IEC 61131-3 标准语义的道莅防御性实现」）1 件漏写，机检拦截补正（R250）。

## 4. 终审 4 抽（批 3/4 控制类件，R32~R40 缺陷族定向）
| 件 | 级 | 缺陷 | 处置 |
|---|---|---|---|
| FB_DL_ConveyorDirMismatch | **严重** | tonDiagBack/tonDiagSlide 的 IN 用 R_TRIG.Q 单拍沿脉冲直连，TON 结构性永不到时 → 036D/036E 反窜/倒滑检出整段不可达 | 战报挂账，**R42 P0 返修**：诊断窗 TON 改相位电平驱动（IN := eWatch），检出改「窗内沿直判锁存」或增设 _bDiagArm 沿锁存 |
| FB_DL_AxisInposGuard | 中 | tonWatchTo 未随故障相门控，故障期持续计时 → 复位清锁存同拍 tonWatchTo.Q 仍 TRUE，立即重锁 03AF（解除边被同拍重锁吃掉） | 挂账 R42：监视 TON 的 IN 串 (NOT _bFault) |
| FB_DL_CascadeWindupLink | 中 | 故障期（饱和锁存未退）段 6 实际仍写 fbOuter.bTrack:=TRUE，而段 7 出口 bFreeze 强制 FALSE——名实不一 | 挂账 R42：段 6 门控加 (NOT _bHiLat AND NOT _bLoLat)，或出口反映真实状态 |
| FB_DL_AxisAbortSafeSeq | 轻 | eAbortStop 相 ELSE 单拍无条件迁出，tonStopTo 超时分支结构性不可达，与头注释「等轴受理」不符（安全由 eWaitStandstill 兜底） | 挂账 R42 低优先：迁出条件加外部等待量 |
- 终审新规入册：R252（IN 含 R_TRIG*.Q 即挂账；监视 TON 串 NOT 故障锁存量）、R253（带超时 TON 的相禁「单发即迁出」）、R257（「写引用 vs 出口镜像」名实不一列为抽检第 5 式）。

## 5. 选题与合规
- 反证句机制（R40 落地）首轮生效：28 候选拒 8（3 假缺口 + 5 同义在册），**零撞名零拒单**；8 件留档 ROUND_PLAN §4 防重提。
- 所用源：**零检索轮，WebSearch 0/3**——全部复用既有 ◐ 组（t2-5/t2-1/t1-6/t1-2/t1-5/t2-2/t2-7/t1-7）语义深化，clean-room 实现，无外部协议合规风险。

## 6. 召唤模式与账本
- 召唤模式：**原生 ×2 + PLC 编码 ×1**。
- 进化账本：PLC_EXPERT_EVOLUTION **4 条（R250~R253）** / DIRECTOR_EVOLUTION **4 条（R254~R257）**，共 8 条，游标至 R257。
- 编码自检 3 处（FC 局部守卫量初始化 / 占位残留 / 切线法中间行）编码侧自修，机检零命中——正面案例入册 R251。

## 7. 进度
- 今日（11-19）：**55/200**（R40 35 + 本轮 20）。
- 总库：**725/10,000（7.25%）**；距 500 件阶段目标已超额 **+225**。JSONL 725 条。
- 子库版本：Base v1.19.0→v1.20.0 / MathData v1.20.0→v1.21.0 / Algo v1.17.0→v1.18.0 / Device v1.16.0→v1.17.0 / Motion v1.15.0→v1.16.0 / Process v1.16.0→v1.17.0。

## 8. 下轮计划（R42）
- **P0**：终审挂账件返修——ConveyorDirMismatch（严重，沿门控 TON）先行，AxisInposGuard / CascadeWindupLink（中）随批，AxisAbortSafeSeq（轻）搭车；返修后语料重注入。
- **P1**：全库码位冲突普查（4 处存量债普查扩面，口径「头部∪全文」双游标实扫）；Device 段 0003 故障带已满，启用 05xx 副故障带并在头注释写明分段理由（R192）。
- **P2**：编译验证债连欠 37 轮（R195 硬闸：闸未开不得新增编解码/数学/转换类高复杂度件）；code_segment 回填；MANUAL 补录。
