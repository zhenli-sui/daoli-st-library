//==============================================================================
// 功能块：FB_DL_DuctStaticReset ｜ 中文名称：风管静压设定重置
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：风管静压设定重置（TSP 修剪侧单件）：最不利末端阀位落在目
//           标带 [100−band, 100) 视为合适（带内保持）；阀位顶满 100%
//           （超带）→ 设定按增益上抬；阀位低于带下沿 → 设定按增益下
//           调。设定变化经斜率限制（fRatePaPerS，由 uDeltaTimeMs 显式
//           积分，禁系统时间函数），上下限钳位。阀位反馈无效（bFbValid
//           为假）→ 保持上次设定并发 3502（信息级，不置 bError）；设
//           定已顶上限而阀位仍满开 → 3501 能力不足，不再继续抬设定。
//           只算设定值，不控变频器（风机调速由上位裁决，本件零执行输
//           出）。规格 §4.8 引脚表未给反馈有效性输入、但其边界行为③
//           与输出表均要求 bFbInvalid/3502 语义，故增补 VAR_INPUT
//           bFbValid（默认 TRUE）承载上游质量位（主动偏离披露，见修
//           订历史）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：阀位[百分数] / 静压[Pa] / 目标带[百分数] / 增益[Pa每百分数] / 斜率[Pa每s] / 扫描间隔[ms]
// 错误码表：16#0002_3501 信息级（静压设定已顶上限且阀位仍全开，风机能
//           力不足，不再抬设定，不置 bError）/ 16#0002_3502 信息级（阀
//           位反馈无效，保持上次设定，不置 bError）/ 16#0002_3505 预留
//           禁用（不得挪用）/ 16#0002_3510 故障级（静压上下限倒置或
//           算法组态非法（带宽/增益/斜率非正），置 bError）/
//           16#0002_3511 故障级（输入非有限，置 bError，设定回下限安
//           全侧防过压）/ 16#0002_3512 预留禁用（不得挪用）
// 状态机：E_DL_DuctStaticState（eIdle=0 / eInBand=10 / eAdjustUp=20 /
//           eAdjustDown=30 / eFbHold=40 / eFault=99），CASE 含 ELSE 兜
//           底，ELSE 复用 3511（§3 未为本件单列兜底槽，不得越段加码）
//           并回下限安全侧
// 边界行为：① fStaticMinPa 大于等于 fStaticMaxPa 或带宽/增益/斜率非正
//           → 故障 3510；② 阀位域钳 0~100（轻域外按边界值照算）；
//           ③ 阀位反馈无效（bFbValid 为假）→ 保持上次设定 + 信息 3502，
//           挂 eFbHold 相，退出条件两条：反馈恢复（按带位回归工作相）
//           或失能（回待机）；④ 设定已达上限而阀位仍 100% → 信息 3501
//           + bAtLimit，不再继续抬设定；⑤ 斜率限制用 uDeltaTimeMs 显
//           式积分（LREAL 中间量，禁系统时间函数），uDeltaTimeMs 为 0
//           时本拍不动；⑥ 非有限（NaN 自反判 + Inf 幅值上限判，R79）
//           → 故障 3511，设定回 fStaticMinPa 安全侧（防过压）；⑦ 失
//           能 → 保持设定（静压突变会导致末端振荡）+ bValid := FALSE；
//           ⑧ 带语义披露：阀位落在 [100−band, 100) 带内保持，阀位 =
//           100% 视为顶带超限（需上抬），与验收向量 ①② 口径一致；
//           ⑨ 首拍设定从下限起坡（首拍不出未知值）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.8）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_DuctStaticState（归属 DL_Algo，与 FB_DL_DuctStaticReset 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DuctStaticState :
(
    eIdle       := 0,   // 失能/待机：设定保持，静压不突变 / Idle: setpoint held, no static jump
    eInBand     := 10,  // 阀位带内：设定保持 / In-band: damper within target band, setpoint held
    eAdjustUp   := 20,  // 阀位顶带：设定按斜率上抬 / Damper at band top: setpoint raised by rate
    eAdjustDown := 30,  // 阀位低于带：设定按斜率下调 / Damper below band: setpoint lowered by rate
    eFbHold     := 40,  // 反馈无效保持：设定保持，等反馈恢复 / Feedback-invalid hold: setpoint held
    eFault      := 99   // 故障兜底态：组态非法/非有限/非法状态，设定回下限 / Fault fallback, setpoint at floor
);
END_TYPE
FUNCTION_BLOCK FB_DL_DuctStaticReset
VAR_INPUT
    fWorstDamperPct : LREAL;                   // 最不利末端阀位 [百分数] / Worst-zone damper position [percent]
    fStaticMinPa  : LREAL;                     // 静压设定下限 [Pa] / Static setpoint floor [Pa]
    fStaticMaxPa  : LREAL;                     // 静压设定上限 [Pa] / Static setpoint ceiling [Pa]
    fBandPct      : LREAL := 10.0;             // 阀位目标带 [百分数]，带 = [100−band, 100) / Damper target band [percent]
    fGainPaPerPct : LREAL := 2.0;              // 增益 [Pa每百分数] / Gain [Pa per percent]
    fRatePaPerS   : LREAL := 5.0;              // 设定斜率 [Pa每s] / Setpoint rate limit [Pa per s]
    bFbValid      : BOOL := TRUE;              // 阀位反馈有效性质量位（规格补遗引脚，见修订历史）/ Damper feedback validity, spec-gap pin
    uDeltaTimeMs  : UDINT;                     // 扫描间隔 [ms]，调用方注入，禁用系统时间函数 / Scan interval [ms], caller-injected
    bEnable       : BOOL;                      // 总使能 / Master enable
    bReset        : BOOL;                      // 复位，上升沿清状态与设定 / Reset, rising edge clears state and setpoint
END_VAR
VAR_OUTPUT
    fStaticSetPa  : LREAL;                     // 静压设定 [Pa]，失能保持 / Static setpoint [Pa], held on disable
    bAtLimit      : BOOL;                      // 设定顶上限且阀位仍全开，能力不足 / Setpoint at ceiling with damper full open
    fErrPct       : LREAL;                     // 带偏差 [百分数]，阀位减带下沿，负 = 低于带 / Band deviation [percent], damper minus band floor
    bFbInvalid    : BOOL;                      // 阀位反馈无效标志 / Damper feedback invalid flag
    eErr          : UDINT;                     // 错误码，0 = 无错，码位 16#0002_3501 起信息级、16#0002_3510 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError        : BOOL;                      // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                      // 设定数据可用标志，失能/故障闸显式 FALSE / Setpoint usable flag, explicit FALSE on disable/fault gates
    eState        : E_DL_DuctStaticState;      // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset       : R_TRIG;                    // 复位上升沿检测实例 / Reset rising edge detector
    fDamperClamped : LREAL;                    // 钳位后阀位 [百分数] / Clamped damper position [percent]
    fBandFloor    : LREAL;                     // 带下沿 [百分数] / Band floor [percent]
    fStepPa       : LREAL;                     // 本拍允许步长 [Pa]（斜率乘时长）/ Allowed step this scan [Pa]
    fDeltaPa      : LREAL;                     // 本拍目标增量 [Pa]（增益乘带偏差）/ Target delta this scan [Pa]
    fDeltaApplied : LREAL;                     // 本拍实际增量 [Pa]（步长限幅后）/ Applied delta after rate limit [Pa]
    fSetTarget    : LREAL;                     // 限幅前目标设定 [Pa] / Pre-limit target setpoint [Pa]
    bFirstScan    : BOOL := TRUE;              // 首拍初始化标志 / First-scan initialization flag
END_VAR
VAR CONSTANT
    DL_DSR_CODE_INFO_1 : UDINT := 16#0002_3501;   // 信息级槽 1（顶上限且阀位全开） / info slot 1
    DL_DSR_CODE_INFO_2 : UDINT := 16#0002_3502;   // 信息级槽 2（反馈无效保持设定） / info slot 2
    DL_DSR_CODE_RSV_1  : UDINT := 16#0002_3505;   // 预留禁用（不得挪用） / reserved, do not use
    DL_DSR_CODE_FLT_1  : UDINT := 16#0002_3510;   // 故障级槽 1（静压界倒置或组态非法） / fault slot 1
    DL_DSR_CODE_FLT_2  : UDINT := 16#0002_3511;   // 故障级槽 2（输入非有限） / fault slot 2
    DL_DSR_CODE_RSV_2  : UDINT := 16#0002_3512;   // 预留禁用（不得挪用） / reserved, do not use
    DL_DS_ZERO    : LREAL := 0.0;              // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_DS_TOL     : LREAL := 1.0E-6;           // 浮点比较容差 [—] / Float comparison tolerance
    DL_DS_INF     : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_DS_PCT_MAX : LREAL := 100.0;            // 阀位域上限 [百分数] / Damper domain ceiling [percent]
    DL_DS_MS_PER_S : LREAL := 1000.0;          // 毫秒转秒系数 [s/ms] / Ms-to-s factor
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿检测在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState  := E_DL_DuctStaticState.eIdle;
    eErr    := 16#0000_0000;                   // 复位清码 / reset clears code
    bError  := FALSE;                          // 复位清故障 / reset clears fault
    bAtLimit := FALSE;                         // 贴限标志清 / at-limit flag cleared
    bFbInvalid := FALSE;                       // 反馈无效标志清 / invalid flag cleared
    bFirstScan := TRUE;                        // 重新首拍化 / re-initialize first scan
    fStaticSetPa := DL_DS_ZERO;                // 设定清零待首拍初始化 / setpoint zeroed, awaits first-scan init
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（浮点引脚逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *       命中即设定回下限安全侧（防过压）
 *----------------------------------------------------------------------------*)
IF (fWorstDamperPct <> fWorstDamperPct) OR (ABS(fWorstDamperPct) >= DL_DS_INF)
   OR (fStaticMinPa <> fStaticMinPa) OR (ABS(fStaticMinPa) >= DL_DS_INF)
   OR (fStaticMaxPa <> fStaticMaxPa) OR (ABS(fStaticMaxPa) >= DL_DS_INF)
   OR (fBandPct <> fBandPct) OR (ABS(fBandPct) >= DL_DS_INF)
   OR (fGainPaPerPct <> fGainPaPerPct) OR (ABS(fGainPaPerPct) >= DL_DS_INF)
   OR (fRatePaPerS <> fRatePaPerS) OR (ABS(fRatePaPerS) >= DL_DS_INF) THEN
    eState       := E_DL_DuctStaticState.eFault;
    eErr         := DL_DSR_CODE_FLT_2;             // 故障级：输入非有限 / fault: non-finite input
    bError       := TRUE;                      // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid       := FALSE;                     // 输出不可用 / outputs unusable
    fStaticSetPa := fStaticMinPa;              // 设定回下限安全侧（防过压）/ setpoint to floor, safe side against overpressure
    bAtLimit := FALSE;                         // 故障态不判贴限 / at-limit not judged in fault
    bFbInvalid := FALSE;                       // 故障态不判反馈无效 / invalid not judged in fault
    fErrPct := DL_DS_ZERO;                     // 带偏差出口清零 / band deviation zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸（静压界倒置/带宽/增益/斜率非正）
 *----------------------------------------------------------------------------*)
IF (fStaticMinPa >= fStaticMaxPa) OR (fBandPct <= DL_DS_TOL)
   OR (fGainPaPerPct <= DL_DS_TOL) OR (fRatePaPerS <= DL_DS_TOL) THEN
    eState       := E_DL_DuctStaticState.eFault;
    eErr         := DL_DSR_CODE_FLT_1;             // 故障级：静压上下限倒置或组态非法 / fault: static band inverted or config invalid
    bError       := TRUE;                      // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid       := FALSE;                     // 输出不可用 / outputs unusable
    fStaticSetPa := fStaticMinPa;              // 设定回下限安全侧（防过压）/ setpoint to floor, safe side
    bAtLimit := FALSE;                         // 故障态不判贴限 / at-limit not judged in fault
    bFbInvalid := FALSE;                       // 故障态不判反馈无效 / invalid not judged in fault
    fErrPct := DL_DS_ZERO;                     // 带偏差出口清零 / band deviation zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜首拍初始化：设定从下限起坡（首拍不出未知值）
 *----------------------------------------------------------------------------*)
IF bFirstScan THEN
    fStaticSetPa := fStaticMinPa;              // 首拍设定 = 下限 / first-scan setpoint = floor
    bFirstScan := FALSE;                       // 初始化完成 / initialization done
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜阀位钳位与带偏差计算（域钳 0~100，带下沿 = 100 − band）
 *----------------------------------------------------------------------------*)
fDamperClamped := fWorstDamperPct;             // 阀位工作副本 / working copy
IF fDamperClamped < DL_DS_ZERO THEN
    fDamperClamped := DL_DS_ZERO;              // 低于 0 钳入 / below zero clamped
END_IF
IF fDamperClamped > DL_DS_PCT_MAX THEN
    fDamperClamped := DL_DS_PCT_MAX;           // 高于 100 钳入 / above 100 clamped
END_IF
fBandFloor := DL_DS_PCT_MAX - fBandPct;        // 带下沿 = 100 − band [百分数] / band floor
fErrPct := fDamperClamped - fBandFloor;        // 带偏差：负 = 低于带，0~band = 带内，band = 顶带 / band deviation

(*------------------------------------------------------------------------------
 * 段 7｜状态机：CASE 含 ELSE 兜底（非法状态 → 复用 3511 + 回下限，安全侧）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_DuctStaticState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        bAtLimit := FALSE;                     // 贴限标志清 / at-limit flag cleared
        bFbInvalid := FALSE;                   // 失能不判反馈无效 / invalid not judged in idle
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable THEN
            IF bFbValid THEN
                eState := E_DL_DuctStaticState.eInBand;        // 反馈有效进带内相 / valid feedback enters in-band
            ELSE
                eState := E_DL_DuctStaticState.eFbHold;        // 反馈无效进保持相 / invalid feedback enters hold
            END_IF
        END_IF

    E_DL_DuctStaticState.eInBand:
        bValid := TRUE;                        // 带内设定可用 / setpoint usable in band
        bAtLimit := FALSE;                     // 带内不判贴限 / at-limit not judged in band
        bFbInvalid := FALSE;                   // 反馈有效 / feedback valid
        eErr := 16#0000_0000;                  // 带内无错 / no error in band
        bError := FALSE;                       // 带内无故障 / no fault in band
        IF NOT bEnable THEN
            eState := E_DL_DuctStaticState.eIdle;      // 失能回待机（设定保持）/ disable returns to idle, setpoint held
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
        ELSIF NOT bFbValid THEN
            eState := E_DL_DuctStaticState.eFbHold;    // 反馈无效转保持相 / invalid feedback to hold phase
        ELSIF fErrPct >= fBandPct - DL_DS_TOL THEN     // 阀位顶满 100%（fErrPct 达 band 上沿即阀位 = 100）
            eState := E_DL_DuctStaticState.eAdjustUp;  // 顶带超限转上调相 / at band top enters adjust-up
        ELSIF fErrPct < -DL_DS_TOL THEN                // 阀位低于带下沿
            eState := E_DL_DuctStaticState.eAdjustDown;        // 低于带转下调相 / below band enters adjust-down
        END_IF

    E_DL_DuctStaticState.eAdjustUp:
        bValid := TRUE;                        // 上调相设定可用 / setpoint usable in adjust-up
        bFbInvalid := FALSE;                   // 反馈有效 / feedback valid
        IF NOT bEnable THEN
            eState := E_DL_DuctStaticState.eIdle;
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
        ELSIF NOT bFbValid THEN
            eState := E_DL_DuctStaticState.eFbHold;    // 反馈无效转保持相 / invalid feedback to hold phase
        ELSE
            fStepPa := fRatePaPerS * UDINT_TO_LREAL(uDeltaTimeMs) / DL_DS_MS_PER_S;  // 本拍步长 = 斜率乘时长 [Pa]，间隔 0 即不动 / step = rate times interval
            fDeltaPa := fGainPaPerPct * fErrPct;       // 目标增量 = 增益乘带偏差 [Pa] / target delta = gain times deviation
            IF fDeltaPa > fStepPa THEN
                fDeltaApplied := fStepPa;      // 斜率限幅 / rate-limited
            ELSE
                fDeltaApplied := fDeltaPa;     // 未触斜率 / within rate
            END_IF
            fSetTarget := fStaticSetPa + fDeltaApplied;        // 限幅前目标 [Pa] / pre-limit target
            IF fSetTarget >= fStaticMaxPa - DL_DS_TOL THEN
                fStaticSetPa := fStaticMaxPa;  // 钳到上限 / clamped to ceiling
                IF fDamperClamped >= DL_DS_PCT_MAX - DL_DS_TOL THEN
                    bAtLimit := TRUE;          // 设定顶上限且阀位仍全开：能力不足 / at ceiling with full-open damper
                    eErr := DL_DSR_CODE_INFO_1;        // 信息级：能力不足，不再抬设定 / info: capacity insufficient
                    bError := FALSE;           // 信息级不置 bError / info never raises bError
                ELSE
                    bAtLimit := FALSE;         // 阀位未满开，仅钳位 / damper not full, clamp only
                    eErr := 16#0000_0000;      // 清码 / clear code
                END_IF
            ELSE
                fStaticSetPa := fSetTarget;    // 未触上限照算 / below ceiling, apply
                bAtLimit := FALSE;             // 未贴限 / not at limit
                eErr := 16#0000_0000;          // 清码 / clear code
            END_IF
            IF fErrPct < fBandPct - DL_DS_TOL THEN     // 阀位离开顶带（需求消失退出）/ damper left band top
                IF fErrPct >= -DL_DS_TOL THEN
                    eState := E_DL_DuctStaticState.eInBand;    // 回带内相 / back to in-band
                ELSE
                    eState := E_DL_DuctStaticState.eAdjustDown;        // 落到带下方向 / fell below band
                END_IF
            END_IF
        END_IF

    E_DL_DuctStaticState.eAdjustDown:
        bValid := TRUE;                        // 下调相设定可用 / setpoint usable in adjust-down
        bAtLimit := FALSE;                     // 下调相不判贴限 / at-limit not judged in adjust-down
        bFbInvalid := FALSE;                   // 反馈有效 / feedback valid
        IF NOT bEnable THEN
            eState := E_DL_DuctStaticState.eIdle;
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
        ELSIF NOT bFbValid THEN
            eState := E_DL_DuctStaticState.eFbHold;    // 反馈无效转保持相 / invalid feedback to hold phase
        ELSE
            fStepPa := fRatePaPerS * UDINT_TO_LREAL(uDeltaTimeMs) / DL_DS_MS_PER_S;  // 本拍步长 [Pa] / step this scan
            fDeltaPa := fGainPaPerPct * (DL_DS_ZERO - fErrPct);        // 目标减量 = 增益乘带偏差绝对值 [Pa] / target decrement
            IF fDeltaPa > fStepPa THEN
                fDeltaApplied := fStepPa;      // 斜率限幅 / rate-limited
            ELSE
                fDeltaApplied := fDeltaPa;     // 未触斜率 / within rate
            END_IF
            fSetTarget := fStaticSetPa - fDeltaApplied;        // 限幅前目标 [Pa] / pre-limit target
            IF fSetTarget <= fStaticMinPa + DL_DS_TOL THEN
                fStaticSetPa := fStaticMinPa;  // 钳到下限 / clamped to floor
                eErr := 16#0000_0000;          // 清码 / clear code
            ELSE
                fStaticSetPa := fSetTarget;    // 未触下限照算 / above floor, apply
                eErr := 16#0000_0000;          // 清码 / clear code
            END_IF
            IF (fErrPct >= -DL_DS_TOL) AND (fErrPct < fBandPct - DL_DS_TOL) THEN
                eState := E_DL_DuctStaticState.eInBand;        // 回带相（需求消失退出）/ back to in-band when need gone
            END_IF
        END_IF

    E_DL_DuctStaticState.eFbHold:
        bValid := TRUE;                        // 保持相设定输出仍可用（保持值）/ usable in hold (held setpoint)
        bAtLimit := FALSE;                     // 保持相不判贴限 / at-limit not judged in hold
        bFbInvalid := TRUE;                    // 反馈无效标志保持 / invalid flag held
        eErr := DL_DSR_CODE_INFO_2;            // 信息级：反馈无效保持上次设定 / info: invalid feedback, setpoint held
        bError := FALSE;                       // 信息级不置 bError / info never raises bError
        IF NOT bEnable THEN
            eState := E_DL_DuctStaticState.eIdle;      // 失能回待机（第二条退出条件）/ disable returns to idle, second exit
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
            bFbInvalid := FALSE;               // 失能清标志 / flag cleared on disable
        ELSIF bFbValid THEN
            bFbInvalid := FALSE;               // 反馈恢复（第一条退出条件）/ feedback recovered, first exit
            IF fErrPct >= fBandPct - DL_DS_TOL THEN
                eState := E_DL_DuctStaticState.eAdjustUp;      // 按带位回归上调相 / re-enter by band position
            ELSIF fErrPct < -DL_DS_TOL THEN
                eState := E_DL_DuctStaticState.eAdjustDown;    // 按带位回归下调相 / re-enter by band position
            ELSE
                eState := E_DL_DuctStaticState.eInBand;        // 按带位回归带内相 / re-enter by band position
            END_IF
        END_IF

    ELSE
        eState := E_DL_DuctStaticState.eFault; // 非法状态兜底 / illegal-state fallback
        eErr := DL_DSR_CODE_FLT_2;                 // 兜底复用故障级槽 2（§3 未单列兜底槽，不得越段加码）/ fallback reuses fault slot 2
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        fStaticSetPa := fStaticMinPa;          // 设定回下限安全侧（防过压）/ setpoint to floor, safe side
        bAtLimit := FALSE;                     // 贴限标志清 / at-limit flag cleared
        bFbInvalid := FALSE;                   // 标志清 / flag cleared
END_CASE
END_FUNCTION_BLOCK
