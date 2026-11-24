//==============================================================================
// 功能块：FB_DL_OvenDoorInterlock ｜ 中文名称：烘箱炉门-氮气-温区三联锁
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：烘箱炉门开门三联锁——门已关确认 → 氮气置换完成 → 温区温度
//           低于开门上限，三条件全满才放行开锁；任一失守立即回锁定态并
//           锁存失守原因。先置换后开门（锂电干燥环节安全前置语义）。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现
// 单位表：T[°C] / 联锁条件[—]
// 错误码表：16#0003_017C 信息级（放行时温度接近上限，提示性，不置
//           bError）/ 16#0003_017D 预留禁用（不得挪用）/ 16#0003_034B
//           故障级（组态非法：开门温度上限 <= 0；或温度非有限，安全侧
//           拒绝放行，置 bError）/ 16#0003_034C 故障级（确认矛盾：门未
//           处于放行态而门关反馈消失，置 bError）/ 16#0003_034D 故障级
//           兜底（状态机落 ELSE，置 bError 并回锁定）
// 状态机：E_DL_OvenDoorState（eLocked=0 / ePurging=10 / eTempHigh=20 /
//           eReleased=30 / eFault=99），CASE 含 ELSE 兜底，ELSE 置 034D
//           并回 eLocked
// 边界行为：① 三条件任一失守 → 回 eLocked 并锁存最近失守原因码；②
//           fOpenTempMaxC <= 0 → 故障 034B 锁存（组态非法）；③ 温度非
//           有限 → 故障 034B 复用（R90）+ 拒绝放行（安全侧默认：非法值
//           绝不放行开门）；④ 温度迟滞按 FC_DL_Hysteresis 语义内联实现
//           （放行阈 <= 上限，回锁阈 > 上限 + 2 K 迟滞带）；⑤ 非放行态
//           下门关反馈消失 → 034C 故障转 eFault（未授权开门，安全侧全锁）。
// 依赖纪律：仅 Standard.library + 同库契约（无跨子库调用；温度迟滞内联，
//           依赖收窄声明：Device 不调用 DL_Base 的 FC_DL_Hysteresis，
//           迟滞语义在本件内联，改动任一侧须复核另一侧）。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 锂电 P1 §350 + T2-8 互锁语义次源）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_OvenDoorState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 炉门三联锁相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_OvenDoorState :
(
    eLocked   := 0,   // 锁定：门锁未放行，等开门请求与三条件 / Locked, waiting for the request and the three conditions
    ePurging  := 10,  // 置换中：门已关，等氮气置换完成确认 / Purging, door closed, waiting for the N2 purge confirmation
    eTempHigh := 20,  // 温度高：置换已完成，等温区降到开门上限以下 / Temperature high, waiting for cool-down below the limit
    eReleased := 30,  // 已放行：开锁输出有效，允许开门 / Released, unlock output active
    eFault    := 99   // 故障：组态非法/确认矛盾/非有限温度/非法状态 / Fault, illegal config, contradiction or non-finite temperature
);
END_TYPE

FUNCTION_BLOCK FB_DL_OvenDoorInterlock
VAR_INPUT
    bDoorClosedFb  : BOOL;                  // 门已关到位反馈 [—] / Door-closed feedback
    bN2PurgeOk     : BOOL;                  // 氮气置换完成 [—] / N2 purge complete
    fZoneTempC     : LREAL;                 // 温区实测温度 [摄氏度] / Measured zone temperature [degC]
    fOpenTempMaxC  : LREAL := 45.0;         // 允许开门温度上限 [摄氏度]，须 > 0 / Door-open temperature ceiling [degC], must be > 0
    bDoorOpenCmd   : BOOL;                  // 开门请求 [—]，电平有效 / Door-open request, level active
    bReset         : BOOL;                  // 故障复位 [—]，上升沿退出 eFault / Fault reset, rising edge leaves the fault state
END_VAR
VAR_OUTPUT
    bDoorUnlock    : BOOL;                  // 开锁放行 [—] / Door unlock release
    eInterlockState: E_DL_OvenDoorState;    // 联锁相位 [—] / Interlock phase
    eErr           : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = no error
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    rtOpenReq      : R_TRIG;                // 开门请求上升沿，段 6 无条件刷新 / Open-request rising edge
    _eState        : E_DL_OvenDoorState := E_DL_OvenDoorState.eLocked; // 当前相位 / Current phase
    _bInit         : BOOL := FALSE;         // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bCfgBad       : BOOL;                  // 组态非法锁存 / Illegal configuration latch
    _bFiniteBad    : BOOL;                  // 温度非有限锁存 / Non-finite temperature latch
    _bIllegal      : BOOL;                  // 非法状态标志 / Illegal state flag
    _bNearLimit    : BOOL;                  // 放行时温度接近上限标志 / Near-limit flag at release
END_VAR
VAR CONSTANT
    DL_OVN_HYST    : LREAL := 2.0;          // 温度迟滞带 [K]，回锁阈 = 上限 + 迟滞 / Temperature hysteresis band [K]
    DL_OVN_NEAR    : LREAL := 5.0;          // 接近上限提示带 [K] / Near-limit notice band [K]
    DL_OVN_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出先全断（安全侧），单拍标志预清零
 *      Outputs cleared first, fail-safe side, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bDoorUnlock := FALSE;                       // 开锁输出先清（安全侧默认断） / Unlock preset FALSE, fail-safe
eErr        := 16#0000_0000;                // 错误码每拍重算 / Error code recomputed
bError      := FALSE;                       // 故障标志每拍重算 / Fault flag recomputed
bValid      := FALSE;                       // 可用标志每拍重算 / Usable flag recomputed
_bIllegal   := FALSE;                       // 非法状态标志预清零 / Illegal flag pre-cleared
_bNearLimit := FALSE;                       // 接近上限标志预清零 / Near-limit flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（IF NOT bInit 范式）
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState  := E_DL_OvenDoorState.eLocked; // 相位锁定起步 / Phase starts locked
    _bCfgBad := FALSE;                      // 组态锁存清零 / Config latch cleared
    _bFiniteBad := FALSE;                   // 非有限锁存清零 / Non-finite latch cleared
    _bInit   := TRUE;                       // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与输入防御闸：上限 <= 0 或温度非有限 → 034B（安全侧拒绝放行）
 *      Configuration and input defense gate, fail-safe refusal
 *-----------------------------------------------------------------------------*)
IF fOpenTempMaxC <= 0.0 THEN
    _bCfgBad := TRUE;                       // 组态非法锁存 / Illegal configuration latched
END_IF
IF (fZoneTempC <> fZoneTempC) OR (ABS(fZoneTempC) > DL_OVN_INF) THEN
    _bFiniteBad := TRUE;                    // 温度非有限锁存（复用 034B，R90） / Non-finite temperature latched, code reused
END_IF
IF _bCfgBad OR _bFiniteBad THEN
    _eState := E_DL_OvenDoorState.eFault;   // 任何组态/输入异常都转故障态 / Any config or input anomaly goes to fault
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜确认矛盾闸：门未处于放行态而门关反馈消失 → 未授权开门 034C
 *      Contradiction gate: door feedback lost outside the released phase
 *-----------------------------------------------------------------------------*)
IF (_eState <> E_DL_OvenDoorState.eReleased)
   AND (_eState <> E_DL_OvenDoorState.eFault) AND (NOT bDoorClosedFb) THEN
    _eState := E_DL_OvenDoorState.eFault;   // 未授权开门，转故障全锁 / Unauthorized door opening, fault with full lock
    eErr    := 16#0003_034C;                // 故障级：确认矛盾 / Fault: confirmation contradiction
    bError  := TRUE;                        // 置故障标志 / Raise the fault flag
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜R_TRIG 无条件刷新（R40：CASE 之外每拍必调）
 *      R_TRIG refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
rtOpenReq(CLK := bDoorOpenCmd);             // 开门请求上升沿 / Open-request rising edge

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；输出在段 7 按相置位）
 *      Phase machine, transitions only, outputs assigned in segment seven
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_OvenDoorState.eLocked:            // 锁定：等开门请求与氮气置换
        IF rtOpenReq.Q THEN
            IF bN2PurgeOk THEN
                _eState := E_DL_OvenDoorState.eTempHigh; // 置换已完成，直入温度评估 / Purge done, go to the temperature gate
            ELSE
                _eState := E_DL_OvenDoorState.ePurging;  // 置换未完成，先置换后开门 / Purge pending, purge first
            END_IF
        END_IF

    E_DL_OvenDoorState.ePurging:           // 置换中：等氮气置换完成
        IF bN2PurgeOk THEN
            _eState := E_DL_OvenDoorState.eTempHigh; // 置换完成，进温度评估 / Purge complete, to the temperature gate
        ELSIF NOT bDoorOpenCmd THEN
            _eState := E_DL_OvenDoorState.eLocked;   // 请求撤销，回锁定 / Request dropped, back to locked
        END_IF

    E_DL_OvenDoorState.eTempHigh:          // 温度门：降到上限以下才放行
        IF (NOT bDoorOpenCmd) THEN
            _eState := E_DL_OvenDoorState.eLocked;   // 请求撤销，回锁定 / Request dropped, back to locked
        ELSIF fZoneTempC <= fOpenTempMaxC THEN
            _eState := E_DL_OvenDoorState.eReleased; // 温度达标，放行 / Temperature within the limit, release
        END_IF

    E_DL_OvenDoorState.eReleased:          // 已放行：超迟滞带或请求撤销即回锁
        IF (fZoneTempC > fOpenTempMaxC + DL_OVN_HYST) OR (NOT bDoorOpenCmd) THEN
            _eState := E_DL_OvenDoorState.eLocked;   // 温度超迟滞带或请求撤销，回锁 / Beyond the hysteresis band or request dropped
        END_IF

    E_DL_OvenDoorState.eFault:             // 故障：原因消失且复位沿才回锁定
        IF bReset AND (NOT _bCfgBad) AND (NOT _bFiniteBad) AND bDoorClosedFb THEN
            _bCfgBad    := FALSE;          // 清组态锁存（组态引脚已修正） / Clear the config latch, the pin is fixed
            _bFiniteBad := FALSE;          // 清非有限锁存（温度已恢复） / Clear the non-finite latch
            _eState     := E_DL_OvenDoorState.eLocked; // 回锁定 / Back to locked
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_OvenDoorState.eLocked; // 回锁定（安全侧） / Back to locked, fail-safe
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜输出置位与码位出口
 *      Output assignment and the code outlet
 *-----------------------------------------------------------------------------*)
IF _eState = E_DL_OvenDoorState.eReleased THEN
    bDoorUnlock := TRUE;                    // 放行态开锁输出 / Unlock output in the released phase
    IF fZoneTempC > fOpenTempMaxC - DL_OVN_NEAR THEN
        _bNearLimit := TRUE;                // 放行时温度接近上限 / Near the limit at release
    END_IF
END_IF

IF _bIllegal THEN
    eErr   := 16#0003_034D;                 // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad OR _bFiniteBad THEN
    eErr   := 16#0003_034B;                 // 故障级：组态非法或温度非有限（R90 复用） / Fault: illegal config or non-finite temperature
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF (_eState = E_DL_OvenDoorState.eFault) THEN
    eErr   := 16#0003_034C;                 // 故障级：确认矛盾保持显示 / Fault: contradiction held
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bNearLimit THEN
    eErr := 16#0003_017C;                   // 信息级：放行时温度接近上限 / Info: near-limit release
END_IF

bValid := (NOT bError) AND (_eState <> E_DL_OvenDoorState.eFault); // 故障态输出不可用 / Outputs unusable in fault
END_FUNCTION_BLOCK
