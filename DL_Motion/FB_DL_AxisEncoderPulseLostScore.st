(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisEncoderPulseLostScore
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 编码器脉冲丢失率在线评分分档。调用方在观测窗内累计脉冲数
 *                         nPulseCntWindow（窗口起点清零，由调用方负责）与本窗期望脉冲数
 *                         fExpectWindow（= |参考速度| × 每毫米脉冲数 × 窗口时长，由调用方换算）。
 *                         本件在 bWindowEnd 上升沿取一次快照，算比值 fRatio = 实测/期望，
 *                         再折成 0~100 分：fRatio >= 1.0 记 100 分；fRatio 在 [0,1) 段线性
 *                         衰减到 0 分（100 × fRatio）；fRatio > 1.0 按 100 分封顶（超发不奖分，
 *                         但另出 bOverRun 提示，防"丢脉冲与多脉冲相互掩盖"）。
 *                         评分分三档：>= nScoreGood 良好、>= nScoreWarn 关注、< nScoreWarn 劣化。
 * 接口     (Interface)  : 输入 nPulseCntWindow 窗内实测脉冲数、fExpectWindow 窗内期望脉冲数、
 *                         bWindowEnd 窗口结束沿、fRatioMin 有效比值下界（防期望值过小病态放大）、
 *                         nScoreGood / nScoreWarn 分档线；输出 fRatio 实测/期望、nScore 0~100、
 *                         eGrade 分档、bValid 本窗评分有效、eState / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只评分，不判故障、不发报警、不改轴**。
 *                         故障级判定唯一属主为轴级监控链（`FB_DL_AxisFollowingErrorMonitor` 等）；
 *                         本件输出 nScore / eGrade 供上层做趋势与维护决策。
 *                         ② 组态闸：nScoreGood <= nScoreWarn、分档线 > 100 或 < 0、
 *                         fRatioMin <= 0.0、fExpectWindow 为 NaN → 故障（ELSE 兜底 + 成因归因）。
 *                         ③ 期望值为 0 或低于 fExpectWindow 下界 → 本窗不评分（bValid=FALSE，
 *                         nScore 保持上窗值不清零），并在 eCause 说明"激励不足"，严禁把
 *                         "无期望"记成 100 分（那会把停机的轴伪装成健康）。
 *                         ④ R_TRIG 一枚段 0 无条件周期刷新；无 TON，故无跨相不复位风险。
 *                         ⑤ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_FrequencyMeasure`（测频）分工——那件给频率本身，本件给
 *                         "窗内实测/期望"的**比率与评分**，输入是已由调用方累计的脉冲计数。
 * 来源标签 (Source Tag) : T1-6 ◐（开源参考：脉冲丢失率在线评估参数域，零代码行复制）
 * 解除式   (Release)    : 本件无锁存故障相：bError 每拍重算（组态非法/非有限即置），
 *                         组态修正后下一拍自动消失——信息级与故障级的边界写死在此（R189 例外条款：
 *                         无锁存即无解除式，只有当拍判据）。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 USINT 评分 + ENUM 分档 + BOOL，
 *                         数字码位待主控收口阶段统一派号（R46 码位规则）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零前判零 + 浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 1 · 序号 2）
 *==============================================================================*)

TYPE E_DL_EplGrade :
(
    eUnknown := 0,    // 本窗未评分（激励不足或组态非法） / Not scored this window
    eGood    := 10,   // 评分良好 / Score good
    eWatch   := 20,   // 评分关注（趋势劣化起点） / Score watch, degradation starting
    ePoor    := 30    // 评分劣化 / Score poor
);
END_TYPE

TYPE E_DL_EplState :
(
    eIdle := 0,    // 未取得首窗数据 / Awaiting first window
    eRun  := 10,   // 逐窗评分运行 / Scoring per window
    eBad  := 90    // 组态非法相（当拍可自愈） / Illegal configuration phase
);
END_TYPE

TYPE E_DL_EplCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（分档线倒置/越界/比值下界非正） / Illegal configuration
    eNonFin     := 2,   // 期望值或下界非有限（NaN/Inf） / Non-finite expectation or floor
    eExcLow     := 3,   // 激励不足：期望脉冲数未过下界，本窗不评分 / Insufficient excitation, window not scored
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisEncoderPulseLostScore
VAR_INPUT
    nPulseCntWindow : DINT := 0;          // 窗内实测脉冲数（调用方累计，窗口起点清零） [cnt] / Measured pulses in window [cnt]
    fExpectWindow   : REAL := 0.0;        // 窗内期望脉冲数（|参考速度|×每毫米脉冲×窗长） [cnt] / Expected pulses in window [cnt]
    bWindowEnd      : BOOL := FALSE;      // 窗口结束触发，上升沿取一次快照 [-] / Window end trigger, snapshot on rising edge
    fRatioMin       : REAL := 0.01;       // 有效比值下界，域 > 0.0（防期望过小病态放大） [-] / Valid ratio lower bound, > 0.0
    nScoreGood      : INT := 98;          // 良好分档线，域 0..100 且 > nScoreWarn [分] / Good threshold, 0..100, > warn
    nScoreWarn      : INT := 90;          // 关注分档线，域 0..100 且 < nScoreGood [分] / Watch threshold, < good
    bReset          : BOOL := FALSE;      // 复位，上升沿回初始等待 [-] / Reset, rising edge returns to idle
END_VAR
VAR_OUTPUT
    fRatio  : REAL;                 // 本窗实测/期望比值（未评分时为 0.0） [-] / Measured over expected ratio this window
    nScore  : USINT;                // 本窗评分 0..100（未评分保持上窗值） [分] / Score 0..100, held when not scored
    eGrade  : E_DL_EplGrade;        // 评分分档出口 [-] / Score grade outlet
    bValid  : BOOL;                 // 本窗评分有效 [-] / Score valid this window
    bOverRun: BOOL;                 // 实测超期望（多脉冲，可能与丢脉冲相互掩盖） [-] / Pulses above expectation
    eState  : E_DL_EplState;        // 状态出口 [-] / State outlet
    eCause  : E_DL_EplCause;        // 本窗异常成因出口（信息级，当拍重算） [-] / Window anomaly cause, recomputed each scan
    bError  : BOOL;                 // 组态/输入非法标志（当拍重算，不锁存） [-] / Illegal config/input flag
END_VAR
VAR
    _eState  : E_DL_EplState := E_DL_EplState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    rtWin    : R_TRIG;              // 窗口结束沿实例，段 0 无条件调用 / Window-end edge instance
    rtReset  : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _nScore  : USINT;               // 评分锁存（未评分时保持） [分] / Held score
    _eCause  : E_DL_EplCause := E_DL_EplCause.eNone;   // 成因锁存前的当拍量（每拍重算） / Per-scan cause, recomputed
    _bNonFin : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad : BOOL;                // 组态非法当拍量 [-] / Illegal configuration this scan
    _bExcite : BOOL;                // 激励充足当拍量（期望值过下界） [-] / Sufficient excitation this scan
    _fRatio  : REAL;                // 当拍比值中间量 [-] / Ratio intermediate
END_VAR
VAR CONSTANT
    DL_EPL_EPS      : REAL := 1.0E-6;   // 浮点判零容差 [无量纲] / Float epsilon
    DL_EPL_SCORE_MAX: REAL := 100.0;    // 评分上限 [分] / Score ceiling
    DL_EPL_SCORE_MIN: REAL := 0.0;      // 评分下限 [分] / Score floor
END_VAR

(* —— 段 0：当拍量派生 + 沿实例无条件周期刷新 —— *)
_bNonFin := (fExpectWindow <> fExpectWindow) OR (fRatioMin <> fRatioMin);   // NaN 自反判 / NaN self-reflexive tests
_bCfgBad := (nScoreGood <= nScoreWarn) OR (nScoreGood > 100) OR (nScoreWarn < 0)   // 分档线几何闸 / Grade threshold geometry gate
         OR (nScoreWarn > 100) OR (fRatioMin <= 0.0) OR _bNonFin;                  // 比值下界闸 + 非有限 / Ratio floor and non-finite
_bExcite := (NOT _bNonFin) AND (fExpectWindow > DL_EPL_EPS)                 // 期望值须为正且有限 / Expectation must be positive and finite
         AND (fExpectWindow > (fRatioMin * DL_EPL_SCORE_MAX));              // 期望值下界 = 比值下界 × 100 脉冲口径 / Expectation floor in pulse counts
rtWin(CLK := bWindowEnd);                                                   // 窗口结束沿，每拍必调（R228A） / Window-end edge
rtReset(CLK := bReset);                                                     // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量 _nScore 不入清单，R107） —— *)
fRatio   := DL_EPL_SCORE_MIN;    // 比值每拍预清，评分分支同拍回填 / Ratio preset
nScore   := _nScore;             // 评分出口先回放锁存值，本窗有效时覆盖 / Score outlet replays held value
eGrade   := E_DL_EplGrade.eUnknown;   // 分档每拍预清 / Grade preset
eCause   := E_DL_EplCause.eNone;      // 成因每拍预清（信息级可重算，R189 例外条款） / Cause preset
bValid   := FALSE;               // 有效位每拍预清 / Validity preset
bOverRun := FALSE;               // 超发位每拍预清 / Over-run preset
bError   := FALSE;               // 非法标志每拍预清 / Error flag preset

(* —— 段 2：复位沿 —— *)
IF rtReset.Q THEN
    _eState := E_DL_EplState.eIdle;     // 回初始等首窗（无锁存故障，故只需相位复位） / Back to idle, no latch to clear
    _nScore := 0;                       // 评分锁存清零（复位是有意清历史） / Clear held score on explicit reset
END_IF

(* —— 段 3：组态/输入非法（当拍置位，不锁存；信息级不外溢为故障） —— *)
IF _bCfgBad THEN
    bError := TRUE;                     // 非法标志置位（同拍配对，R45） / Illegal flag set, same-scan pairing
    IF _bNonFin THEN
        eCause := E_DL_EplCause.eNonFin;    // 归因：输入非有限（优先于组态几何闸） / Cause: non-finite input, takes precedence
    ELSE
        eCause := E_DL_EplCause.eCfgIllegal;    // 归因：组态几何非法 / Cause: illegal configuration geometry
    END_IF
    _eState := E_DL_EplState.eBad;      // 入非法相（下拍自动回运行相） / Enter bad phase, self-heals next scan
END_IF

(* —— 段 4：窗口结束沿评分（单点写入评分锁存，避免同拍抹除，R187） —— *)
IF rtWin.Q AND (NOT _bCfgBad) THEN
    IF _bExcite THEN                                                          // 激励充足：真实评分 / Sufficient excitation: real scoring
        IF fExpectWindow > DL_EPL_EPS THEN                                    // 除零闸（双保险：_bExcite 已含下界） / Division guard
            _fRatio := INT_TO_REAL(nPulseCntWindow) / fExpectWindow;          // 实测 / 期望 / Measured over expected
        ELSE
            _fRatio := DL_EPL_SCORE_MIN;                                      // 病态期望值：比值记 0 / Degenerate expectation: ratio zero
        END_IF
        fRatio := _fRatio;                                                    // 比值出口（本窗有效值） / Ratio outlet for a valid window
        IF _fRatio >= 1.0 THEN                                                // 达到或超过期望 / At or above expectation
            _nScore := 100;                                                   // 满分封顶（超发不奖分） / Ceiling at full score
            bOverRun := _fRatio > 1.02;                                       // 超发 2% 以上给提示（防双向掩盖） / Over-run hint above 2 percent
        ELSE
            IF _fRatio < DL_EPL_SCORE_MIN THEN
                _fRatio := DL_EPL_SCORE_MIN;                                  // 负计数（脏数据）钳到下限 / Clamp dirty negative count
            END_IF
            _nScore := REAL_TO_USINT(_fRatio * DL_EPL_SCORE_MAX);             // 线性折分 0..100 / Linear score scaling
        END_IF
        IF _nScore > 100 THEN
            _nScore := 100;                                                   // 类型上限再兜一层（USINT 溢出前置） / Second ceiling before USINT range
        END_IF
        bValid := TRUE;                                                       // 本窗评分有效 / Window scored
        nScore := _nScore;                                                    // 评分出口与锁存同源 / Score outlet from latch
    ELSE
        bValid := FALSE;                                                      // 激励不足：本窗不评分（禁记 100 分） / No excitation: no scoring, never 100
        eCause := E_DL_EplCause.eExcLow;                                      // 归因：激励不足（与本窗不评分同因） / Cause: insufficient excitation
    END_IF
END_IF

(* —— 段 5：分档映射（与 nScale 同源，出口单点） —— *)
IF bValid THEN
    IF INT_TO_USINT(nScoreGood) <= nScore THEN
        eGrade := E_DL_EplGrade.eGood;         // 良好档 / Good grade
    ELSIF INT_TO_USINT(nScoreWarn) <= nScore THEN
        eGrade := E_DL_EplGrade.eWatch;        // 关注档 / Watch grade
    ELSE
        eGrade := E_DL_EplGrade.ePoor;         // 劣化档 / Poor grade
    END_IF
ELSE
    eGrade := E_DL_EplGrade.eUnknown;          // 未评分档 / Unknown grade
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_EplState.eIdle:
    IF (NOT _bCfgBad) AND (rtWin.Q OR _bExcite) THEN    // 出口 1：组态合法且已来窗/已见激励 / Legal config and a window seen
        _eState := E_DL_EplState.eRun;
    ELSIF _bCfgBad THEN                                 // 出口 2：组态非法 / Illegal configuration
        _eState := E_DL_EplState.eBad;
    END_IF

E_DL_EplState.eRun:
    IF _bCfgBad THEN                                    // 出口 1：组态转非法 / Configuration went illegal
        _eState := E_DL_EplState.eBad;
    ELSIF rtReset.Q THEN                                // 出口 2：复位回等首窗 / Reset back to first window
        _eState := E_DL_EplState.eIdle;
    END_IF

E_DL_EplState.eBad:
    IF NOT _bCfgBad THEN                                // 出口：组态恢复即自愈回运行 / Self-heal once configuration is legal
        _eState := E_DL_EplState.eRun;
    END_IF

ELSE
    bError  := TRUE;                                    // 非法相位兜底：置非法标志 / Illegal-phase fallback flag
    eCause  := E_DL_EplCause.ePhaseBad;                 // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_EplState.eBad;                      // 强拉非法相 / Force bad phase

END_CASE

eState := _eState;                                      // 状态出口 / State outlet

END_FUNCTION_BLOCK
