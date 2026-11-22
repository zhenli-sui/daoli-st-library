# REVIEW_R66 — 五抽终审报告（2026-11-22 02:50，两段式 R279）

抽件：FC_DL_QuadPolyFit(7) / FB_DL_AnalogOutFailsafe(6) / FB_DL_LotMergeGate(7) / FB_DL_TaktPaceMonitor(6) / FC_DL_BilinearInterp(6) + 补抽 FB_DL_FeedOverrideRamp(6)（覆盖 MathData×2/Device/Process×2/Motion 共 4 分类）。先按模板模式定向扫查（闸覆盖率 / 相迁移闸位复检 / 同拍竞态 / 冻结分支出口 / 锁存解除可达 / 整数进位点），再剩余项快速通读。

## 一、逐件定级

| 组件 | 严重 | 中 | 轻 | 处置 |
|---|---|---|---|---|
| FC_DL_QuadPolyFit | 0 | 1 | 1 | 中/轻挂账 R67 |
| FB_DL_AnalogOutFailsafe | 3 | 0 | 0 | **就地修 v1.0.1** |
| FC_DL_BilinearInterp | 0 | 0 | 0 | PASS |
| FB_DL_FeedOverrideRamp | 0 | 0 | 0 | PASS |
| FB_DL_LotMergeGate | 0 | 0 | 2 | 轻挂账 R67 |
| FB_DL_TaktPaceMonitor | 0 | 1 | 1 | **中就地修 v1.0.1**；轻挂账 R67 |

## 二、缺陷明细

### FB_DL_AnalogOutFailsafe v1.0.0 → v1.0.1（3 严重，全部就地修）
- **S1（R302 第三支·声明断言被证伪）**：tonWd `IN := bWatchdog` 反相——TON 语义下「心跳在位持续达整定」才置 Q，健康通道上电 2s 即误锁 1001；真断线期间 Q=FALSE 反而永不检测。修：`IN := NOT bWatchdog`，段 0 注释与 R7 行同步订正。
- **S2（冻结分支出口扫查命中）**：段 6 整体包于 `IF NOT _bFaultLatch` 而锁存期段 5 每拍强制 `_eState := eFault`，eFrozen/eSafeHold 分支的保持/回程动作永不执行——「冻结/安全值二选一」在运行路径退化为恒冻结，头注 Purpose 与 V6/V7 验收断言被证伪。修：段 5 改锁存起点单次迁入（仅 eIdle/eNormal 相回写），段 6 弃整体旁路使 CASE 锁存期照常推进；失能回空闲加 `NOT _bFaultLatch` 闸（锁存期失保动作优先于失能，NE43 语义）。
- **S3（终审两式 #1·锁存解除可达）**：解除式含 rtWdRecover.Q（上升沿），bWatchdog 恒 TRUE（含缺省组态）时无恢复沿 → 成因 1002/1003 锁存永不可解除。修：解除式改电平式（bEnable + bWatchdog + NOT tonWd.Q + _bCfgOk + 请求有限），删 rtWdRecover 实例；三成因解除条件均恒可满足，向量自证：V-Rel1 配置修恢复即解 / V-Rel2 心跳回归即解（tonWd IN 随 NOT 反相自动复位）/ V-Rel3 请求恢复有限即解。

### FB_DL_TaktPaceMonitor v1.0.0 → v1.0.1（1 中就地修）
- **M1（R258 家族·静默降级）**：`_bTimeOk`（评估窗 ≤ T#0MS / fCallCycleS ≤ 0 或非有限）失效时仅 bValid=FALSE + RETURN，不置 bError 不置码——头注码表却把「评估窗非法」声明在码 01 内。触发向量：`tEvalWindow := T#0MS` → 永久无输出且零诊断。修：段 2 判式改 `(NOT _bTgtOk) OR (NOT _bTimeOk)` 并入码 01；头注码 01 行同步扩写（含 fCallCycleS 面）。语料重注入挂账 R67（R248）。

### FC_DL_QuadPolyFit（1 中 1 轻，挂账 R67 不改码）
- **M2**：列主元闸只覆盖第 0/1 列（消元主轮 2 轮），aM[2,2] 舒尔补未闸——两个相异 x 值（高度可达：传感器两态卡值）时正规方程秩 2，回代除零出 NaN/Inf 落码 02 而非头注声明的 03（安全行为不变：不输出系数、bValid=FALSE，属码归因错位非安全侧 R317，故不就地修）。修法建议：段 7 前补 `IF ABS(aM[2,2]) < QPF_PIV_MIN → 码 03`。
- **L1**：段 4 ABS 溢出复核仅覆盖 s4/t2，s1/s2/s3/t0/t1 的 Inf 依赖段 8 回代复核兜底（结果正确、归因延迟一跳）。

### FB_DL_LotMergeGate（2 轻，挂账 R67）
- **L2**：eIdle 相 `uLotQty > LMG_U_MAX` 结构性不可达（UDINT 自身上限），已注释留档——裁决**保留**（防御性声明面，删除反增 churn），R67 起统一「结构性不可达防御」记账口径。
- **L3**：eFault 分支 `IF NOT _bFaultLatch → eIdle` 迁出式不可达（迁入 eFault 必伴锁存，清锁存的复位沿同拍已置 eIdle）——死代码，R67 点修删除。

## 三、上报定位点裁决（5/5）

1. **注入引脚口径**：纪律一致（不读平台时刻、调用方注入），但**形态三轨并存**——CycleTimeMeasure `uDeltaTimeMs:UDINT[ms]` / OeeCalculator `tCycleTime:TIME` / 本轮 4 件 `fCallCycleMs|fCallCycleS:LREAL`。非缺陷，一致性观察项：R67 在 coding-standard 固化「时间注入引脚三形态选型表」（历史 UDINT ms / KPI TIME / 斜坡 LREAL s），新件按用途选型并头注声明理由。
2. **ATAN2（CircularMeanCalc）**：**保留**。头注 Platform 行已声明三平台 MATH 内建归属，属标准数学集非厂商依赖。
3. **结构性不可达留档防御**：WeekNumIsoCalc jdn<1970 闸与 LotMergeGate uLotQty 闸**均保留**（均已留档声明）；LotMergeGate eFault 死迁出（L3）不同——其未声明留档，挂账点修。
4. **BilinearInterp 容量 32×32**：头注「表格口径 Table」节 + 常量段双重声明，充分。极端 fX0 量级输入经段 6 末端闸确定性收敛，无缺陷。
5. **TIME_TO_DINT 毫秒口径**：头注设计偏差节已声明（TIME 本义 ms、三平台一致），充分。但本件轻项 L4：fExpectR 闸界 4.294967295E9 与转换链 DINT 中转域 2^31−1 不齐（仅在窗/目标比 >2.1e9 s 的组态下可达，挂账 R67 钳位点前移）。

## 四、机检逃逸复盘（R303）

本轮机检 10/10 PASS 下逃逸 3 严重 1 中：tonWd IN 极性（语义级）、失保相死路径（结构级）、沿式解除可达性（可达性级）、窗面静默降级（码面配对）。候选机检锚点：①TON IN 含「看门狗/心跳/断线」语义词时断言 IN 表达式含 NOT；②CASE 外层 IF 条件与段 5 强制赋值的「覆盖互斥」检查；③解除式含 `.Q` 沿引用时断言该沿信号存在电平翻转路径声明。

## 五、R193 判定

挂账 4 处（中 1 + 轻 3）分散 3 族（数值判据 / 死代码 / 域界），单族 <2 → 按 R309 分散型处理：只做配额下调 20%（R67 新件 16→12），不扩族返修。

*R66 终审线 ｜ 2026-11-22 02:55 ｜ 道莅工控代码库产品总监*
