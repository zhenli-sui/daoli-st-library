//==============================================================================
// 功能块：FB_DL_WindingAlignEdge ｜ 中文名称：卷绕极片边缘跟随与蛇形抑制
// 所属子库：DL_Motion ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：极片边缘跟随纠偏——边缘传感器上升沿锁存轴位置为边缘基准，
//           偏差 = 锁存边缘 - 目标边缘，经一阶低通滤波（alpha 加权，滤
//           高频毛刺）与每拍步进限幅（蛇形抑制：禁止纠偏输出大幅摆动）
//           后乘增益输出纠偏百分比；纠偏输出受行程窗口拦截（超限钳位
//           + 信息提示）。相邻边沿间轴位移超过物理上限判传感器跳变/
//           双沿，锁存故障（防假边缘基准污染纠偏链）。
// 遗留假设（R95 代理阈值三句）：① 代理值 = fCycleTimeS 组态扫描周期
//           [秒]（步进限幅的换算基量）；② 覆盖 0.001~0.1 秒任务周期
//           范围；③ 覆盖不到的区间由调用方按实际任务周期重设该引脚
//           负责，该假设挂编译验证债。
// 开源溯源 (Origin)：道莅原创实现（参考卷绕纠偏（边缘跟随）工程惯例 分类与参数域）
// 单位表：轴位置[毫米] / 边缘目标[毫米] / 传感器偏置[毫米] / 偏差[毫米] /
//         增益[百分数每毫米] / 行程限[毫米] / 跳变限[毫米] / 增益系数[无量纲]
// 错误码表：16#0004_01E5 信息级（边缘锁存更新：新边沿被锁存为基准，不置
//           bError）/ 16#0004_01E6 信息级（纠偏输出达行程限幅，不置
//           bError）/ 16#0004_0303 故障级（组态非法：增益系数/行程限/
//           跳变限域、周期 <= 0 或任一输入非有限，置 bError）/
//           16#0004_0304 故障级（边沿跳变超物理上限：相邻边沿间轴位移
//           超 fMaxJumpMm，判传感器跳变/双沿，锁存故障，置 bError——
//           该场景不可由 0303 的组态类判据观测，属运行信号独立域）/
//           16#0004_0305 故障级兜底（状态机落 ELSE，置 bError）
// 状态机：E_DL_WindAlignState（四态：eIdle=0 / eFollow=10 / eFault=99），
//           实际为三态，CASE 含 ELSE 兜底，ELSE 置 0305 并冻结输出零
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 未锁存边缘前
//           纠偏输出保持 0（无基准不放行）；③ 滤波系数域 [0, 1]，= 0
//           即冻结滤波值（等于不更新）；④ 纠偏输出钳 +/- 行程限 + 信息
//           01E6；⑤ 未使能输出冻结零并 bValid := FALSE（锁存基准保持，
//           复能即续走）；⑥ 安全侧 = 跳变故障冻结纠偏输出为 0，禁止
//           假基准驱动机构。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §806）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_WindAlignState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 边缘跟随相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_WindAlignState :
(
    eIdle   := 0,   // 空闲：未使能 / Idle, not enabled
    eFollow := 10,  // 跟随：纠偏闭环运行 / Follow, correction loop running
    eFault  := 99   // 故障：组态非法/边沿跳变/非法状态 / Fault, config, edge jump or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_WindingAlignEdge
VAR_INPUT
    bEnable       : BOOL;                   // 跟随使能 [—] / Follow enable
    bReset        : BOOL;                   // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    bEdgeSensor   : BOOL;                   // 边缘传感器电平 [—]（TRUE = 检出极片边缘） / Edge sensor level, TRUE on the edge
    fAxisPosMm    : LREAL;                  // 轴位置实测 [毫米]（纠偏机构位置基准） / Axis position [mm]
    fTargetEdgeMm : LREAL := 0.0;           // 目标边缘位置 [毫米] / Target edge position [mm]
    fSensorOffsetMm : LREAL := 0.0;         // 传感器安装偏置 [毫米]（锁存值补偿） / Sensor mounting offset [mm]
    fFilterAlpha  : LREAL := 0.2;           // 一阶滤波系数 [无量纲]，域 [0, 1]，0 = 冻结滤波值 / First-order filter alpha, domain 0..1
    fGainPctPerMm : LREAL := 10.0;          // 纠偏增益 [百分数每毫米] / Correction gain [percent/mm]
    fTravelLimitMm: LREAL := 20.0;          // 纠偏行程限 [毫米]，须 > 0 / Correction travel limit [mm], must be > 0
    fMaxJumpMm    : LREAL := 5.0;           // 相邻边沿位移物理上限 [毫米]，须 > 0 / Max inter-edge displacement [mm], must be > 0
    fCycleTimeS   : LREAL := 0.01;          // 任务扫描周期 [秒]，须 > 0（R95 代理阈值） / Task scan cycle [s], must be > 0, R95 proxy
END_VAR
VAR_OUTPUT
    fCorrectOutPct : LREAL;                 // 纠偏输出 [百分数]，-100..100，行程限内 / Correction output [percent], within the travel limit
    fOffsetMm      : LREAL;                 // 滤波后边缘偏差 [毫米]（诊断出口） / Filtered edge offset [mm], diagnostics outlet
    bEdgeLatch     : BOOL;                  // 边缘锁存有效 [—] / Edge latch valid
    eState         : E_DL_WindAlignState;   // 相位出口 [—] / Phase outlet
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0004_01E5 起信息级、16#0004_0303 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbEdge    : R_TRIG;                     // 边缘沿检测（待机/故障分支同样无条件刷新） / Edge detector, refreshed unconditionally
    _eState   : E_DL_WindAlignState := E_DL_WindAlignState.eIdle; // 当前相位 / Current phase
    _bCfgBad  : BOOL;                       // 组态非法锁存 / Illegal config latch
    _bJumpBad : BOOL;                       // 边沿跳变锁存 / Edge jump fault latch
    _bInfoLatch: BOOL;                      // 锁存更新信息当拍标志 / Latch-update info flag of this scan
    _bInfoClip: BOOL;                       // 限幅信息当拍标志 / Clamp info flag of this scan
    _fEdgeCap : LREAL;                      // 锁存边缘基准 [毫米] / Latched edge reference [mm]
    _fEdgePrev: LREAL;                      // 上次锁存边缘基准 [毫米]（跳变判据基准） / Previous latched edge [mm]
    _fOffFilt : LREAL;                      // 滤波后偏差内部量 [毫米] / Filtered offset internal [mm]
    _fOutPrev : LREAL;                      // 上拍纠偏输出快照 [百分数]（步进限幅基准） / Previous-scan correction snapshot [percent]
    _bHaveL   : BOOL;                       // 已锁存标志 / Latch-present flag
    _bIllegal : BOOL;                       // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_WAE_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_WAE_EPS     : LREAL := 1.0E-6;       // 浮点判零容差 [毫米] / Float zero tolerance [mm]
    DL_WAE_SLEW_PCTS: LREAL := 50.0;        // 纠偏最大变化率 [百分数每秒]（蛇形抑制硬限） / Max correction slew rate [percent/s]
    DL_WAE_OUT_MAX : LREAL := 100.0;        // 纠偏输出满幅 [百分数] / Correction full scale [percent]
    DL_WAE_ZERO    : LREAL := 0.0;          // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
    DL_WAE_ONE     : LREAL := 1.0;          // 单位常量 [无量纲] / Unity constant
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：纠偏输出先清（安全侧），单拍标志预清零
 *      Correction cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fCorrectOutPct := DL_WAE_ZERO;           // 纠偏输出先清（跟随态在段 5 重置） / Correction cleared first
fOffsetMm := DL_WAE_ZERO;                // 偏差出口每拍重算 / Offset outlet recomputed
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoLatch := FALSE;                    // 锁存信息预清零 / Latch info pre-cleared
_bInfoClip  := FALSE;                    // 限幅信息预清零 / Clamp info pre-cleared
_bIllegal   := FALSE;                    // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState   := E_DL_WindAlignState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad  := FALSE;                  // 组态锁存清零 / Config latch cleared
    _bJumpBad := FALSE;                  // 跳变锁存清零 / Jump latch cleared
    _bHaveL   := FALSE;                  // 锁存标志清零 / Latch flag cleared
    _fOffFilt := DL_WAE_ZERO;            // 滤波值从零起步 / Filter starts at zero
    _fOutPrev := DL_WAE_ZERO;            // 输出快照从零起步 / Output snapshot starts at zero
    _bInit    := TRUE;                   // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 增益/行程/跳变/周期域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fAxisPosMm <> fAxisPosMm) OR (ABS(fAxisPosMm) > DL_WAE_INF)
   OR (fFilterAlpha <> fFilterAlpha) OR (ABS(fFilterAlpha) > DL_WAE_INF)
   OR (fGainPctPerMm <> fGainPctPerMm) OR (ABS(fGainPctPerMm) > DL_WAE_INF)
   OR (fTravelLimitMm <> fTravelLimitMm) OR (ABS(fTravelLimitMm) > DL_WAE_INF)
   OR (fMaxJumpMm <> fMaxJumpMm) OR (ABS(fMaxJumpMm) > DL_WAE_INF)
   OR (fCycleTimeS <> fCycleTimeS) OR (ABS(fCycleTimeS) > DL_WAE_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fFilterAlpha < DL_WAE_ZERO) OR (fFilterAlpha > DL_WAE_ONE)
   OR (fTravelLimitMm <= DL_WAE_EPS) OR (fMaxJumpMm <= DL_WAE_EPS)
   OR (fCycleTimeS <= DL_WAE_EPS)) THEN
    _bCfgBad := TRUE;                    // 增益系数/行程限/跳变限/周期域非法锁存 / Gain, travel, jump and cycle domains latched
END_IF
IF bReset THEN
    _bCfgBad  := FALSE;                  // 复位清组态锁存 / Reset clears the config latch
    _bJumpBad := FALSE;                  // 复位清跳变锁存 / Reset clears the jump latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜边缘沿检测无条件刷新（R40：CASE 之外每拍必调）
 *      Edge detection refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbEdge(CLK := bEdgeSensor);              // 边缘沿检测 / Edge detection

(*------------------------------------------------------------------------------
 * 段 5｜相位机与纠偏链（CASE 含 ELSE 兜底；未使能/异常落故障态）
 *      Phase machine and the correction chain
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR _bCfgBad OR _bJumpBad THEN
    _eState := E_DL_WindAlignState.eFault; // 未使能或异常转故障态（输出零） / Not enabled or anomaly, fault, output zero
ELSE
CASE _eState OF

    E_DL_WindAlignState.eIdle:             // 空闲：使能进跟随（基准未锁存则输出保持零）
        IF bEnable THEN
            _eState := E_DL_WindAlignState.eFollow; // 进跟随 / To follow
        END_IF

    E_DL_WindAlignState.eFollow:           // 跟随：沿锁存 + 滤波 + 步进限幅 + 行程拦截
        IF NOT bEnable THEN
            _eState := E_DL_WindAlignState.eFault; // 使能撤销转故障 / Enable dropped, fault
        END_IF
        IF fbEdge.Q THEN                   // 新边沿：跳变校验通过才锁存（R80 三段式）
            IF _bHaveL AND (ABS(fAxisPosMm - _fEdgePrev) > fMaxJumpMm) THEN
                _bJumpBad := TRUE;         // 相邻边沿位移超物理上限（拍 N 进入） / Inter-edge displacement beyond the physical limit
                _eState := E_DL_WindAlignState.eFault; // 本拍转出：进故障冻结 / To fault, frozen
            ELSE
                _fEdgeCap := fAxisPosMm - fSensorOffsetMm; // 锁存边缘基准（含安装偏置补偿） [毫米] / Latch the edge with offset compensation
                _fEdgePrev := _fEdgeCap;   // 跳变判据基准推进 / Jump-reference advanced
                _bHaveL := TRUE;           // 锁存有效 / Latch valid
                _bInfoLatch := TRUE;       // 锁存更新提示（信息级） / Latch-update notice, info
            END_IF
        END_IF
        IF (_eState = E_DL_WindAlignState.eFollow) AND _bHaveL THEN
            fOffsetMm := _fEdgeCap - fTargetEdgeMm; // 原始偏差 [毫米] / Raw offset [mm]
            _fOffFilt := _fOffFilt + fFilterAlpha * (fOffsetMm - _fOffFilt); // 一阶低通滤波 [毫米] / First-order low-pass filter
            fOffsetMm := _fOffFilt;        // 滤波后偏差出口 / Filtered offset outlet
            fCorrectOutPct := fGainPctPerMm * _fOffFilt; // 增益映射 [百分数] / Gain mapping
            fCorrectOutPct := MIN(MAX(fCorrectOutPct,
                _fOutPrev - DL_WAE_SLEW_PCTS * fCycleTimeS),
                 _fOutPrev + DL_WAE_SLEW_PCTS * fCycleTimeS); // 每拍步进限幅（蛇形抑制：变化率受限） / Per-scan slew clamp, anti-serpentine
            fCorrectOutPct := MIN(MAX(fCorrectOutPct,
                -MIN(fTravelLimitMm * fGainPctPerMm, DL_WAE_OUT_MAX),
                 MIN(fTravelLimitMm * fGainPctPerMm, DL_WAE_OUT_MAX))); // 行程窗拦截钳位（变化率限后二次钳位） / Travel-window clamp after the slew
            IF ABS(fCorrectOutPct) >= (MIN(fTravelLimitMm * fGainPctPerMm, DL_WAE_OUT_MAX) - DL_WAE_EPS) THEN
                _bInfoClip := TRUE;        // 达行程限幅提示（信息级） / Travel-limit notice, info
            END_IF
            _fOutPrev := fCorrectOutPct;   // 上拍输出快照推进（步进限幅基准） / Previous-output snapshot advanced
        END_IF

    E_DL_WindAlignState.eFault:            // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bCfgBad) AND (NOT _bJumpBad) THEN
            _eState := E_DL_WindAlignState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        fCorrectOutPct := DL_WAE_ZERO;     // 输出冻结零（安全侧） / Output frozen at zero
        _eState := E_DL_WindAlignState.eFault; // 回故障态 / Back to fault
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0004_0305;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bJumpBad THEN
    eErr   := 16#0004_0304;                // 故障级：边沿跳变超物理上限 / Fault: edge jump beyond the physical limit
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0004_0303;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoClip THEN
    eErr := 16#0004_01E6;                  // 信息级：纠偏输出达行程限幅 / Info: correction at the travel limit
ELSIF _bInfoLatch THEN
    eErr := 16#0004_01E5;                  // 信息级：边缘锁存更新 / Info: edge latch updated
END_IF

bEdgeLatch := _bHaveL AND (NOT bError);  // 锁存有效出口（故障时不放行） / Latch-valid outlet, gated in fault
bValid := (NOT bError) AND bEnable AND (_eState = E_DL_WindAlignState.eFollow); // 仅跟随态放行 / Usable only in the follow phase
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
