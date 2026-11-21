(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LamCtrlDualZone
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 层压机双腔真空协调与差压保护。四段顺控（粗抽→平衡→精抽→
 *                         保压），差压越限时只降抽得快的一侧（双侧同降会把时长翻倍且不
 *                         解决差压）；段超时只报码并保持当前抽速（归零即放弃已有真空度）。
 *                         双腔达标判据为「双侧都不高于目标」。不做泵启停时序、不做阀门
 *                         驱动、不做真空泄漏率诊断（另有专件）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_LamSeg / FUNCTION_BLOCK FB_DL_LamCtrlDualZone
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS / MIN / MAX）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         差压上限判零防除零 ｜ 目标 ≥ 大气压即组态错 ｜ 单侧非有限按该侧
 *                         0 处理、双侧非有限停车 ｜ 段超时定时器无条件周期刷新 ｜ 枚举显式
 *                         赋值 ｜ CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0003_03BB 就绪（各段正常或本拍无事件）
 *                         16#0003_03BC 故障级 差压上限 ≤0 或非有限
 *                         16#0003_03BD 故障级 目标真空 ≥ 当地大气压（物理不可达）
 *                         16#0003_03BE 故障级 段超时（保持当前抽速，不归零）
 *                         16#0003_03BF 故障级 单侧真空读数非有限（该侧按 0，双侧齐发即停车）。
 *                                    本件 5 槽全用、无预留槽，已登记待裁定
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 3
 * 验收向量 (Acceptance) : 正向 目标 0.5 kPa、差压上限 3 kPa、上腔 5 / 下腔 12 → 差压 7 越限
 *                         → bDpGuardActive 且降上泵；双腔到 0.5 → bVacOk
 *                         反向 目标设 105 kPa（≥ 大气压）→ 16#0003_03BD；差压上限 0 →
 *                         16#0003_03BC；上腔给 NaN → 16#0003_03BF 且上腔按 0；段拖满 →
 *                         16#0003_03BE 且抽速保持
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LamSeg（归属本功能块，同文件发布，全库唯一定义；数值即 uSeg 出口值）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LamSeg :
(
    eIdle    := 0,    // 待机：未启动 / Idle, not started
    eRough   := 1,    // 粗抽：双泵全速 / Rough pumping, both pumps at full speed
    eBalance := 2,    // 平衡：差压保护优先 / Balancing, the differential guard has priority
    eFine    := 3,    // 精抽：双泵趋近目标 / Fine pumping toward the target
    eHold    := 4,    // 保压：双腔达标保持 / Hold, both chambers at the target
    eFault   := 9     // 故障：抽速保持当前值 / Fault, the speeds keep their present values
);
END_TYPE

FUNCTION_BLOCK FB_DL_LamCtrlDualZone
VAR_INPUT
    bEnable        : BOOL := FALSE;       // 使能 / Enable
    bStartSeq      : BOOL := FALSE;       // 启动顺控，上升沿 / Start the sequence, rising edge
    fVacUpper_kPa  : REAL := 101.3;       // 上腔真空 [kPa(abs)]，域 0~101.3 / Upper chamber vacuum
    fVacLower_kPa  : REAL := 101.3;       // 下腔真空 [kPa(abs)]，域 0~101.3 / Lower chamber vacuum
    fVacTarget_kPa : REAL := 0.5;         // 目标真空 [kPa(abs)]，域 0.1~101 / Target vacuum
    fAmbient_kPa   : REAL := 101.3;       // 当地大气压 [kPa(abs)] / Local atmospheric pressure
    fDpMax_kPa     : REAL := 3.0;         // 差压上限 [kPa]，域 0.5~20 / Differential pressure limit
    fSpeedUpper    : REAL := 100.0;       // 上泵抽速给定 [%]，域 0~100 / Upper pump speed setpoint in percent
    fSpeedLower    : REAL := 100.0;       // 下泵抽速给定 [%]，域 0~100 / Lower pump speed setpoint in percent
    tSegMax        : TIME := T#60S;       // 各段超时 [ms]，域 1~600 s / Per-segment timeout
END_VAR
VAR_OUTPUT
    bVacOk         : BOOL;                // 双腔达标（双侧都不高于目标） / Both chambers at or below the target
    fDp_kPa        : REAL;                // 实时差压（上减下）[kPa] / Differential pressure, upper minus lower
    uSeg           : UINT;                // 当前段 1 粗抽 2 平衡 3 精抽 4 保压 0 待机 9 故障 [—] / Current segment
    fSpeedUpCmd    : REAL;                // 上泵指令 [%] / Upper pump command in percent
    fSpeedLowCmd   : REAL;                // 下泵指令 [%] / Lower pump command in percent
    bDpGuardActive : BOOL;                // 差压保护介入 / Differential guard active
    eErr           : UDINT;               // 错误码，段位 16#0003_xxxx / Error code in segment 16#0003_xxxx
END_VAR
VAR
    _eSeg          : E_DL_LamSeg := E_DL_LamSeg.eIdle; // 当前段 / Current segment
    _bInit         : BOOL := FALSE;       // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCfgOk        : BOOL;                // 组态合法标志 / Configuration valid flag
    _bUpOk         : BOOL;                // 上腔读数有限 / Upper reading finite
    _bLowOk        : BOOL;                // 下腔读数有限 / Lower reading finite
    _fUp           : REAL;                // 上腔生效值（非有限按 0）[kPa(abs)] / Effective upper value
    _fLow          : REAL;                // 下腔生效值（非有限按 0）[kPa(abs)] / Effective lower value
    _fSpeedUp      : REAL := 100.0;       // 上泵内部指令 [%] / Internal upper command
    _fSpeedLow     : REAL := 100.0;       // 下泵内部指令 [%] / Internal lower command
    _fSegSec       : REAL;                // 段超时换算秒 [s] / Segment timeout in seconds
    _rtrigStart    : R_TRIG;              // 启动上升沿 / Rising edge of the start command
    _tonSeg        : TON;                 // 段超时计时 / Segment timeout timer
END_VAR
VAR CONSTANT
    DL_LAM_READY   : UDINT := 16#0003_03BB;  // 就绪码 / Ready code
    DL_LAM_DP_BAD  : UDINT := 16#0003_03BC;  // 故障级差压上限非法码 / Fault code for an invalid limit
    DL_LAM_TGT_BAD : UDINT := 16#0003_03BD;  // 故障级目标不可达码 / Fault code for an unreachable target
    DL_LAM_SEG_TO  : UDINT := 16#0003_03BE;  // 故障级段超时码 / Fault code for a segment timeout
    DL_LAM_SIDE_BAD : UDINT := 16#0003_03BF; // 故障级单侧非有限码 / Fault code for a non-finite side
    DL_LAM_DP_LO   : REAL := 0.5;            // 差压上限下限 [kPa] / Differential limit lower bound
    DL_LAM_DP_HI   : REAL := 20.0;           // 差压上限上限 [kPa] / Differential limit upper bound
    DL_LAM_TGT_LO  : REAL := 0.1;            // 目标真空下限 [kPa(abs)] / Target lower bound
    DL_LAM_SPD_MIN : REAL := 20.0;           // 差压保护降速后的保底抽速 [%] / Minimum speed kept by the guard
    DL_LAM_BAL_K   : REAL := 2.0;            // 平衡相触发倍率（压力 ≤ 倍率×目标即转平衡） / Balancing trigger factor
END_VAR

// 段 1｜输出与单拍标志预置
bVacOk := FALSE;                                    // 达标标志预清 / Target-reached flag pre-cleared
bDpGuardActive := FALSE;                            // 差压保护标志预清 / Guard flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜沿检测与段超时定时器无条件周期刷新
_rtrigStart(CLK := bStartSeq);                      // 启动沿 / Start edge
_tonSeg(IN := (_eSeg <> E_DL_LamSeg.eIdle) AND (_eSeg <> E_DL_LamSeg.eHold) AND (_eSeg <> E_DL_LamSeg.eFault), PT := tSegMax);

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eSeg := E_DL_LamSeg.eIdle;                     // 段待机起步 / Segment starts idle
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜组态闸（差压上限判零防除零；目标必须低于大气压）
_bCfgOk := NOT ((fDpMax_kPa <> fDpMax_kPa) OR ((fDpMax_kPa - fDpMax_kPa) <> (fDpMax_kPa - fDpMax_kPa)))
        AND (fDpMax_kPa >= DL_LAM_DP_LO) AND (fDpMax_kPa <= DL_LAM_DP_HI)
        AND (fVacTarget_kPa >= DL_LAM_TGT_LO)
        AND NOT ((fVacTarget_kPa <> fVacTarget_kPa) OR ((fVacTarget_kPa - fVacTarget_kPa) <> (fVacTarget_kPa - fVacTarget_kPa)))
        AND (fAmbient_kPa > 0.0);
IF _bCfgOk AND (fVacTarget_kPa >= fAmbient_kPa) THEN
    eErr := DL_LAM_TGT_BAD;                         // 故障级：目标不可达（≥ 大气压） / Fault, the target is unreachable
    _eSeg := E_DL_LamSeg.eFault;
ELSIF NOT _bCfgOk THEN
    eErr := DL_LAM_DP_BAD;                          // 故障级：差压上限非法 / Fault, the differential limit is invalid
    _eSeg := E_DL_LamSeg.eFault;
END_IF

// 段 5｜单侧读数闸（非有限侧按 0 = 最好真空；双侧齐发则停车保压）
_bUpOk := NOT ((fVacUpper_kPa <> fVacUpper_kPa) OR ((fVacUpper_kPa - fVacUpper_kPa) <> (fVacUpper_kPa - fVacUpper_kPa)));
_bLowOk := NOT ((fVacLower_kPa <> fVacLower_kPa) OR ((fVacLower_kPa - fVacLower_kPa) <> (fVacLower_kPa - fVacLower_kPa)));
IF _bUpOk THEN
    _fUp := fVacUpper_kPa;                          // 上腔有效值 [kPa(abs)] / Effective upper value
ELSE
    _fUp := 0.0;                                    // 上腔按 0（保守：视为最好真空）/ Upper side treated as zero, the conservative assumption
    eErr := DL_LAM_SIDE_BAD;                        // 故障级：上腔非有限 / Fault, the upper reading is not finite
END_IF
IF _bLowOk THEN
    _fLow := fVacLower_kPa;                         // 下腔有效值 [kPa(abs)] / Effective lower value
ELSE
    _fLow := 0.0;                                   // 下腔按 0 / Lower side treated as zero
    eErr := DL_LAM_SIDE_BAD;                        // 故障级：下腔非有限 / Fault, the lower reading is not finite
END_IF
IF (NOT _bUpOk) AND (NOT _bLowOk) THEN
    _fSpeedUp := 0.0;                               // 双侧非有限：上泵停车 [%] / Both sides invalid, the upper pump stops
    _fSpeedLow := 0.0;                              // 双侧非有限：下泵停车 [%] / Both sides invalid, the lower pump stops
    _eSeg := E_DL_LamSeg.eFault;
END_IF

// 段 6｜差压求取与保护（只降抽得快的一侧）
fDp_kPa := _fUp - _fLow;                            // 差压 = 上 − 下 [kPa] / Differential pressure
IF ABS(fDp_kPa) > fDpMax_kPa THEN
    bDpGuardActive := TRUE;                         // 差压保护介入 / The guard intervenes
    IF _fUp < _fLow THEN
        _fSpeedUp := MAX(DL_LAM_SPD_MIN, _fSpeedUp * 0.5);   // 上腔抽得快：降上泵 [%] / The upper chamber pumps faster, slow it down
    ELSE
        _fSpeedLow := MAX(DL_LAM_SPD_MIN, _fSpeedLow * 0.5); // 下腔抽得快：降下泵 [%] / The lower chamber pumps faster, slow it down
    END_IF
END_IF

// 段 7｜失能闸
IF NOT bEnable THEN
    _eSeg := E_DL_LamSeg.eIdle;                     // 段回待机 / Segment back to idle
    _fSpeedUp := 0.0;                               // 上泵指令 0 [%] / Upper command zeroed
    _fSpeedLow := 0.0;                              // 下泵指令 0 [%] / Lower command zeroed
    eErr := DL_LAM_READY;                           // 失能为正常停机 / Disable is a normal stop
END_IF

// 段 8｜双腔达标判据（双侧都不高于目标）
bVacOk := (_fUp <= fVacTarget_kPa) AND (_fLow <= fVacTarget_kPa) AND _bUpOk AND _bLowOk;

// 段 9｜四段顺控（ENUM + CASE + ELSE 兜底）
IF bEnable THEN
    CASE _eSeg OF

        E_DL_LamSeg.eIdle:                          // 待机：启动沿开粗抽
            _fSpeedUp := 0.0;
            _fSpeedLow := 0.0;
            IF _rtrigStart.Q THEN
                _fSpeedUp := LIMIT(0.0, fSpeedUpper, 100.0);   // 上泵按给定 [%] / Upper pump at the setpoint
                _fSpeedLow := LIMIT(0.0, fSpeedLower, 100.0);  // 下泵按给定 [%] / Lower pump at the setpoint
                _eSeg := E_DL_LamSeg.eRough;                   // 进入粗抽 / Enter rough pumping
            END_IF

        E_DL_LamSeg.eRough:                         // 粗抽：任一侧到 2×目标即转平衡
            IF (_fUp <= (fVacTarget_kPa * DL_LAM_BAL_K)) OR (_fLow <= (fVacTarget_kPa * DL_LAM_BAL_K)) THEN
                _eSeg := E_DL_LamSeg.eBalance;
            ELSIF _tonSeg.Q THEN
                eErr := DL_LAM_SEG_TO;              // 故障级：粗抽段超时（抽速保持） / Fault, the rough segment timed out
                _eSeg := E_DL_LamSeg.eFault;
            END_IF

        E_DL_LamSeg.eBalance:                       // 平衡：差压回到限内即转精抽
            _fSpeedUp := MAX(_fSpeedUp, DL_LAM_SPD_MIN);       // 平衡段保底抽速 [%] / Minimum speed while balancing
            _fSpeedLow := MAX(_fSpeedLow, DL_LAM_SPD_MIN);
            IF ABS(fDp_kPa) <= fDpMax_kPa THEN
                _eSeg := E_DL_LamSeg.eFine;
            ELSIF _tonSeg.Q THEN
                eErr := DL_LAM_SEG_TO;              // 故障级：平衡段超时 / Fault, the balancing segment timed out
                _eSeg := E_DL_LamSeg.eFault;
            END_IF

        E_DL_LamSeg.eFine:                          // 精抽：双腔达标即保压
            _fSpeedUp := MAX(_fSpeedUp, DL_LAM_SPD_MIN);
            _fSpeedLow := MAX(_fSpeedLow, DL_LAM_SPD_MIN);
            IF bVacOk THEN
                _eSeg := E_DL_LamSeg.eHold;
            ELSIF _tonSeg.Q THEN
                eErr := DL_LAM_SEG_TO;              // 故障级：精抽段超时 / Fault, the fine segment timed out
                _eSeg := E_DL_LamSeg.eFault;
            END_IF

        E_DL_LamSeg.eHold:                          // 保压：保持当前抽速，达标仍然成立
            IF NOT bVacOk THEN
                _eSeg := E_DL_LamSeg.eFine;         // 真空劣化：回精抽 / Vacuum degraded, back to fine pumping
            END_IF

        E_DL_LamSeg.eFault:                         // 故障：抽速保持当前值（不归零）
            eErr := DL_LAM_SEG_TO;                  // 故障级：故障段以段超时码承载 / The fault segment is carried by the timeout code
            IF _rtrigStart.Q THEN
                _fSpeedUp := LIMIT(0.0, fSpeedUpper, 100.0);   // 重启：按给定恢复 [%] / Restart restores the setpoint
                _fSpeedLow := LIMIT(0.0, fSpeedLower, 100.0);
                _eSeg := E_DL_LamSeg.eRough;
            END_IF

        ELSE
            // 非法段兜底（故障级，差压上限码承载）
            eErr := DL_LAM_DP_BAD;                  // 故障级：非法段值 / Fault, illegal segment value
            _eSeg := E_DL_LamSeg.eFault;
    END_CASE
END_IF

uSeg := 0;                                     // 段出口预置 / Segment output pre-set
CASE _eSeg OF
    E_DL_LamSeg.eIdle:    uSeg := 0;                // 待机 / Idle
    E_DL_LamSeg.eRough:   uSeg := 1;                // 粗抽 / Rough
    E_DL_LamSeg.eBalance: uSeg := 2;                // 平衡 / Balance
    E_DL_LamSeg.eFine:    uSeg := 3;                // 精抽 / Fine
    E_DL_LamSeg.eHold:    uSeg := 4;                // 保压 / Hold
    E_DL_LamSeg.eFault:   uSeg := 9;                // 故障 / Fault
    ELSE
        uSeg := 9;                                  // 非法段按故障段出口 / Illegal segments are reported as fault
END_CASE
fSpeedUpCmd := _fSpeedUp;                           // 上泵指令出口 [%] / Upper command output
fSpeedLowCmd := _fSpeedLow;                         // 下泵指令出口 [%] / Lower command output
END_FUNCTION_BLOCK
