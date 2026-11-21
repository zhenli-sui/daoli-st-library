//==============================================================================
// 功能块：FB_DL_BagFeedDancerSync ｜ 中文名称：制袋供膜摆辊同步（复杂度 H）
// 所属子库：DL_Motion ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：制袋机供膜摆辊同步——供膜速度给定 = 线速前馈 + 摆辊位置 PI
//           修正；摆辊信号不可信时前馈直通、PI 冻结（域外行为显式化）；
//           输出触顶积分冻结（抗饱和）；停链且摆辊持续偏离中位判张力故障。
//           【拓扑语义假设（R23 终审留档，符号判定的前提）】供膜单元位于
//           摆辊环下游（自环内抽膜、与线速同步），摆辊位置偏大 = 环内膜存
//           量过多 → PI 正向修正加快抽膜耗环（负反馈收敛）。若调用方拓扑
//           相反（供膜自环上游推膜），须将 fFeedKp / fFeedKi 反号接入或
//           另行适配，本件不自动判向。
// 开源溯源 (Origin)：道莅原创实现（参考包装制袋机摆辊同步工程惯例 分类与参数域）
// 单位表：摆辊位置[%]（50 = 中位）/ 线速与供膜速度[mm/s] / 增益[（mm/s）/%]
//         与[（mm/s）/(%·拍)] / 速度上限[mm/s] / 计时[ms]
// 错误码表：16#0004_01E1 信息级（摆辊域外/非有限不可信，或线速负值已钳
//           0——共码，不置 bError）/ 16#0004_01E2 预留禁用（不得挪用）/
//           16#0004_02FC 故障级（供膜速度上限组态非法 <= 0，置 bError）/
//           16#0004_02FD 故障级（张力疑似故障：线速 0 且摆辊持续偏离中位
//           超窗，断膜/卡膜疑似，置 bError）/ 16#0004_02FE 故障级兜底
//           （置 bError）
// 状态机：N/A（PI 修正 + 阈值判窗为电平逻辑，无相位状态机）
// 边界行为：① 摆辊位置域外（0~100 外）或非有限 → bDancerOk := FALSE +
//           前馈直通（PI 冻结，积分保持）+ 信息 01E1（R11 NtcTempScan 同
//           口径）；② PI 抗饱和：输出触顶（0 或上限）时积分冻结；③
//           fLineSpeedMmS < 0 → 钳 0 + 信息 01E1 复用（R90）；④
//           fFeedMaxMmS <= 0 → 故障 02FC；⑤ 线速为 0 且摆辊持续偏离中位
//           > tIdleOffTol → bTensionFault := TRUE + 故障 02FD；⑥ 积分增益
//           按拍积分（无周期引脚），有效量纲 [（mm/s）/(%·拍)]，头注释
//           单位表留档此口径。
// 依赖收窄 (R11 留档③)：Motion 不得跨库调用前馈补偿件（FeedforwardComp
//           等均为他库），前馈律（fFeedSp := fLineSpeed + PI 修正）在本件
//           内联实现，改动任一侧须复核另一侧。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 包装 P1 §377）
//           v1.0.1 2026-11-17 R23 终审补档（逻辑零改动）：头注释补拓扑
//           语义假设声明——PI 符号经推演在「抽膜」拓扑下为负反馈正确，
//           但原版未留档流向假设，反拓扑接入会翻转为正反馈发散。
//==============================================================================

FUNCTION_BLOCK FB_DL_BagFeedDancerSync
VAR_INPUT
    fDancerPosPct : LREAL;                  // 摆辊位置 [百分数]，50 = 中位，有效域 0..100 / Dancer position [percent], 50 = mid
    fLineSpeedMmS : LREAL;                  // 线速前馈源 [毫米/秒] / Line speed feedforward source [mm/s]
    fFeedKp       : LREAL := 1.5;           // 摆辊 PI 比例增益 [（毫米/秒）/%] / Dancer PI proportional gain [(mm/s)/%]
    fFeedKi       : LREAL := 0.2;           // 摆辊 PI 积分增益 [（毫米/秒）/(%·拍)]，按拍积分 / Dancer PI integral gain per scan
    fFeedMaxMmS   : LREAL := 500.0;         // 供膜速度上限 [毫米/秒]，须 > 0 / Feed speed ceiling [mm/s], must be > 0
    bEnable       : BOOL;                   // 同步使能 [—] / Sync enable
    bReset        : BOOL;                   // 故障复位 [—]，清除张力故障锁存 / Fault reset, clears the tension latch
END_VAR
VAR_OUTPUT
    fFeedSpMmS    : LREAL;                  // 供膜速度给定 [毫米/秒] = 前馈 + PI 修正 / Feed speed setpoint [mm/s] = feedforward plus PI trim
    bDancerOk     : BOOL;                   // 摆辊信号可信 [—] / Dancer signal trustworthy
    bTensionFault : BOOL;                   // 张力疑似故障 [—] / Tension suspected fault
    eErr          : UDINT;                  // 错误码，0 = 无错 / Error code, 0 = no error
    bError        : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbIdleOff     : TON;                    // 停链偏离中位判窗，段 6 无条件刷新 [ms] / Idle off-mid window
    _fPosEff      : LREAL;                  // 生效摆辊位置 [百分数] / Effective dancer position [percent]
    _fLineEff     : LREAL;                  // 钳位后的生效线速 [毫米/秒] / Effective clamped line speed [mm/s]
    _fErr         : LREAL;                  // 摆辊位置偏差 [百分数] / Dancer position error [percent]
    _fPITrim      : LREAL;                  // PI 修正量 [毫米/秒] / PI trim [mm/s]
    _fIntAcc      : LREAL;                  // 积分累加器 [毫米/秒] / Integral accumulator [mm/s]
    _bInit        : BOOL := FALSE;          // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bDancerBad   : BOOL;                   // 摆辊不可信当拍标志 / Dancer-untrustworthy flag of this scan
    _bLineClamp   : BOOL;                   // 线速钳位当拍标志 / Line clamp flag of this scan
    _bCfgBad      : BOOL;                   // 速度上限组态非法锁存 / Illegal ceiling latch
    _bTensionLatch: BOOL;                   // 张力故障锁存（bReset 清除） / Tension fault latch, cleared by bReset
    _bIllegal     : BOOL;                   // 非法状态标志 / Illegal state flag
END_VAR
VAR CONSTANT
    DL_BF_POS_MIN : LREAL := 0.0;           // 摆辊位置域下限 [百分数] / Dancer position domain floor [percent]
    DL_BF_POS_MAX : LREAL := 100.0;         // 摆辊位置域上限 [百分数] / Dancer position domain ceiling [percent]
    DL_BF_MID     : LREAL := 50.0;          // 摆辊中位 [百分数] / Dancer mid position [percent]
    DL_BF_IDLE_TOL: LREAL := 10.0;          // 停链偏离中位容差 [百分数] / Idle off-mid tolerance [percent]
    DL_BF_IDLE_WIN: TIME  := T#5S;          // 停链偏离判窗 [ms] / Idle off-mid window [ms]
    DL_BF_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_BF_EPS     : LREAL := 1.0E-6;        // 浮点判零容差 [毫米/秒] / Float zero tolerance [mm/s]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出先算后出，单拍标志预清零
 *      Outputs computed per scan, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fFeedSpMmS  := 0.0;                         // 供膜给定预置零 / Feed setpoint preset zero
bDancerOk   := FALSE;                       // 可信标志预置 FALSE / Trustworthy preset FALSE
bTensionFault := FALSE;                     // 张力故障每拍重算 / Tension fault recomputed
eErr        := 16#0000_0000;                // 错误码每拍重算 / Error code recomputed
bError      := FALSE;                       // 故障标志每拍重算 / Fault flag recomputed
bValid      := FALSE;                       // 可用标志每拍重算 / Usable flag recomputed
_bDancerBad := FALSE;                       // 摆辊标志预清零 / Dancer flag pre-cleared
_bLineClamp := FALSE;                       // 线速钳位预清零 / Line clamp pre-cleared
_bIllegal   := FALSE;                       // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _fIntAcc  := 0.0;                       // 积分累加器清零 / Integral accumulator cleared
    _bCfgBad  := FALSE;                     // 组态锁存清零 / Config latch cleared
    _bTensionLatch := FALSE;                // 张力锁存清零 / Tension latch cleared
    _bInit    := TRUE;                      // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与输入防御闸（速度上限 <= 0 → 02FC；摆辊/线速非有限 → 不可信）
 *      Configuration and input defense gates
 *-----------------------------------------------------------------------------*)
IF (fFeedMaxMmS <> fFeedMaxMmS) OR (ABS(fFeedMaxMmS) > DL_BF_INF) OR (fFeedMaxMmS <= 0.0) THEN
    _bCfgBad := TRUE;                       // 速度上限组态非法锁存 / Illegal ceiling latched
END_IF
IF (fDancerPosPct <> fDancerPosPct) OR (ABS(fDancerPosPct) > DL_BF_INF)
   OR (fLineSpeedMmS <> fLineSpeedMmS) OR (ABS(fLineSpeedMmS) > DL_BF_INF)
   OR (fFeedKp <> fFeedKp) OR (ABS(fFeedKp) > DL_BF_INF)
   OR (fFeedKi <> fFeedKi) OR (ABS(fFeedKi) > DL_BF_INF) THEN
    _bDancerBad := TRUE;                    // 任一输入非有限：摆辊判不可信（R79） / Any non-finite input, dancer untrustworthy
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜摆辊域外与线速钳位（域外行为显式化，信息级共码 01E1，R90）
 *      Out-of-domain handling with a shared info code per R90
 *-----------------------------------------------------------------------------*)
IF (NOT _bDancerBad) AND ((fDancerPosPct < DL_BF_POS_MIN) OR (fDancerPosPct > DL_BF_POS_MAX)) THEN
    _bDancerBad := TRUE;                    // 摆辊域外：不可信（前馈直通） / Dancer out of domain, untrustworthy
END_IF
IF fLineSpeedMmS < 0.0 THEN
    _fLineEff := 0.0;                       // 负线速钳 0（物理下界） / Negative line speed clamped to zero
    _bLineClamp := TRUE;                    // 钳位声明 / Clamp declared
ELSE
    _fLineEff := fLineSpeedMmS;             // 合法线速原值生效 / Valid line speed applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜PI 修正与前馈合成（可信时积分推进，不可信/触顶冻结——抗饱和）
 *      PI trim and feedforward synthesis with anti-windup freezing
 *-----------------------------------------------------------------------------*)
IF bEnable AND (NOT _bCfgBad) AND (NOT _bDancerBad) THEN
    bDancerOk := TRUE;                      // 摆辊可信 / Dancer trustworthy
    _fPosEff := fDancerPosPct;              // 生效位置原值 / Effective position as-is
    _fErr := _fPosEff - DL_BF_MID;          // 位置偏差 [百分数]，偏大 = 膜存量过多 / Position error, high means excess film stored
    _fPITrim := fFeedKp * _fErr + _fIntAcc; // PI 修正量 [毫米/秒] / PI trim [mm/s]
    fFeedSpMmS := _fLineEff + _fPITrim;     // 供膜给定 = 前馈 + 修正 / Feed setpoint = feedforward plus trim
    IF fFeedSpMmS < 0.0 THEN
        fFeedSpMmS := 0.0;                  // 下限钳 0（反向不倒转） / Lower clamp, no reverse
        (* 输出触下限：积分冻结（抗饱和） / Saturated at the floor, integral frozen *)
    ELSIF fFeedSpMmS > fFeedMaxMmS THEN
        fFeedSpMmS := fFeedMaxMmS;          // 上限钳位 / Ceiling clamp
        (* 输出触上限：积分冻结（抗饱和） / Saturated at the ceiling, integral frozen *)
    ELSE
        _fIntAcc := _fIntAcc + fFeedKi * _fErr; // 未触顶：积分推进（按拍积分） / Not saturated, integral advances per scan
    END_IF
ELSE
    (* 摆辊不可信：前馈直通（PI 冻结，积分保持不推进） / Untrustworthy, feedforward passthrough, integral held *)
    fFeedSpMmS := _fLineEff;                // 前馈直通 / Feedforward passthrough
    IF fFeedSpMmS > fFeedMaxMmS THEN
        fFeedSpMmS := fFeedMaxMmS;          // 直通仍受上限约束 / Passthrough still ceiling-clamped
    END_IF
    IF fFeedSpMmS < 0.0 THEN
        fFeedSpMmS := 0.0;                  // 直通仍受下限约束 / Passthrough still floor-clamped
    END_IF
    IF _bDancerBad OR _bLineClamp THEN
        bDancerOk := FALSE;                 // 不可信声明出口 / Untrustworthy declared
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜停链偏离判窗无条件刷新（R40：CASE 之外每拍必调）
 *      Idle off-mid window refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbIdleOff(IN := bEnable AND (NOT _bCfgBad) AND (NOT _bDancerBad)
              AND (_fLineEff <= DL_BF_EPS)
              AND (ABS(fDancerPosPct - DL_BF_MID) > DL_BF_IDLE_TOL), PT := DL_BF_IDLE_WIN); // 停链偏离中位判窗 / Idle off-mid window
IF fbIdleOff.Q THEN
    _bTensionLatch := TRUE;                 // 张力故障锁存（断膜/卡膜疑似） / Tension fault latched
END_IF
IF bReset THEN
    _bTensionLatch := FALSE;                // 复位清张力锁存 / Reset clears the tension latch
END_IF
bTensionFault := _bTensionLatch;            // 张力故障出口 / Tension fault outlet

(*------------------------------------------------------------------------------
 * 段 7｜码位出口
 *      Code outlet
 *-----------------------------------------------------------------------------*)
IF _bCfgBad THEN
    eErr   := 16#0004_02FC;                 // 故障级：速度上限组态非法 / Fault: illegal speed ceiling
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
ELSIF _bTensionLatch THEN
    eErr   := 16#0004_02FD;                 // 故障级：张力疑似故障 / Fault: tension suspected
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := TRUE;                         // 判定结果本身可用 / The verdict itself is usable
ELSIF _bDancerBad OR _bLineClamp THEN
    eErr := 16#0004_01E1;                   // 信息级：摆辊/线速已钳位或不可信（共码，R90） / Info: clamped or untrustworthy, shared code
    bValid := TRUE;                         // 前馈直通结果可用（降级口径） / Passthrough result usable
ELSE
    bValid := bEnable;                      // 使能且正常：输出可用 / Outputs usable when enabled
END_IF
END_FUNCTION_BLOCK
