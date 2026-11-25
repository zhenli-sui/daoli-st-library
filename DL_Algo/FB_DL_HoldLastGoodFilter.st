(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HoldLastGoodFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商私有库
 * 功能描述 (Function)   : 坏值保持滤波（hold last good）。上游给出质量判据 bGood
 *                         （传感器在线 / 通信正常 / 量程内 / 非冻结），本件在判据有效时
 *                         采纳输入，判据失效时**输出上一有效值并累计失效时长**。
 *                         失效时长超过 tMaxBad 置 bTimedOut=TRUE（信息级，供上游降级决策），
 *                         输出**仍然保持**（不自动回落 0，避免下游把保持值当成真实 0）。
 *                         与 FB_DL_GatedUpdateFilter 的差别：那件按时间窗门控，
 *                         本件按数据质量门控；两者可串联（先门控再质量保持）。
 * 接口     (Interface)  : 输入 bEnable 使能、bReset 清「已获得首个有效值」标志、
 *                         fIn 采样输入 [EU]、bGood 质量判据（TRUE = 本拍可信）、
 *                         tMaxBad 允许的最大坏值持续时长 [s]；
 *                         输出 fOut 输出值 [EU]、bHolding 是否处于坏值保持、
 *                         bTimedOut 坏值超时（信息级）、tBadElapsed 已保持时长 [s]、
 *                         bValid 输出是否有可信值（从未得到过有效值时为 FALSE）、
 *                         bError 故障标志、uErrorId 故障码。
 * 边界     (Boundary)   : ① 属主边界：只做质量门控与保持，不判断质量本身
 *                         （bGood 由上游传感器诊断 / 量程判定给出，本件不越权推断）。
 *                         ② **从未得到过有效值**（bGood 从未 TRUE）时 bValid=FALSE 且 fOut=0，
 *                         这是唯一把输出置 0 的情形，已在头注释显式声明（名实双出口）。
 *                         ③ 非有限防御：仅当 bGood=TRUE 时读取 fIn；此时非有限 → 故障态
 *                         16#0007_0002（判据与数值矛盾，属上游逻辑错误，必须报）。
 *                         ④ tMaxBad < 0 钳到 T#0S 并置信息码 16#0007_0001；T#0S = 不判超时。
 *                         ⑤ **TON 无条件每周期调用**（R7），位于 CASE 之外。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_GatedUpdateFilter` 分工：时间窗门控归那件、
 *                         质量门控归本件；与 `FB_DL_AnalogInputRedundancySel`（另批）分工：
 *                         双路择优归那件，本件不比较两路。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 16#0007_0000 无故障 / 16#0007_0001 坏值时长非法已钳位（信息级）/
 *                         16#0007_0002 判据有效但数值非有限（故障级）/ 16#0007_0005 非法状态（故障级）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限拒绝 + 时长域闸 + 无除法 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE 兜底 ｜ R7 ✓ TON 实例 CASE 外无条件刷新
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 13）
 * 验收向量 (Acceptance) : ① bGood=TRUE, fIn=42.5 → fOut=42.5, bHolding=FALSE, bValid=TRUE；
 *                         ② 随后 bGood=FALSE, fIn=0.0 → fOut 保持 42.5, bHolding=TRUE, bValid=TRUE；
 *                         ③ bGood 持续 FALSE 超过 tMaxBad=T#2S → bTimedOut=TRUE，fOut 仍 42.5；
 *                         ④ 上电起 bGood 一直 FALSE → fOut=0.0, bValid=FALSE, bTimedOut 视时长；
 *                         ⑤ bGood=TRUE 且 fIn=NaN → uErrorId=16#0007_0002，bError=TRUE，fOut 冻结。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HoldGoodState（坏值保持状态机，归属 DL_Algo，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HoldGoodState :
(
    eInit  := 0,    // 首扫 / 复位后：尚未获得有效值 / First scan or after reset: no valid value yet
    eRun   := 10,   // 运行态：判据有效则采纳、失效则保持 / Running: adopt when good, hold when bad
    eHold  := 20,   // 保持态：未使能，输出冻结 / Hold: disabled, output frozen
    eFault := 99    // 故障态：输出冻结，等待 bEnable 跌落或 bReset / Fault: frozen until cleared
);
END_TYPE

FUNCTION_BLOCK FB_DL_HoldLastGoodFilter
VAR_INPUT
    bEnable : BOOL := FALSE;      // 使能，FALSE 冻结输出 / Enable, FALSE freezes output
    bReset  : BOOL := FALSE;      // 复位「已获有效值」标志（单拍有效） / Reset the valid-acquired flag, single scan
    fIn     : LREAL := 0.0;       // 采样输入 [EU] / Sampling input [EU]
    bGood   : BOOL := FALSE;      // 质量判据，TRUE = 本拍输入可信 / Quality flag, TRUE means trustworthy
    tMaxBad : TIME := T#5S;       // 允许的最大坏值持续时长，T#0S = 不判超时 [s] / Max bad duration, zero disables
END_VAR
VAR_OUTPUT
    fOut        : LREAL;   // 输出值（坏值期间保持） [EU] / Output value, held while bad
    bHolding    : BOOL;    // 是否处于坏值保持 [-] / Whether holding a previous value
    bTimedOut   : BOOL;    // 坏值超时（信息级） [-] / Bad-value timeout, info level
    tBadElapsed : TIME;    // 已保持时长 [s] / Elapsed hold duration
    bValid      : BOOL;    // 输出是否有可信值 [-] / Whether the output holds a trustworthy value
    bError      : BOOL;    // 故障标志，与 uErrorId 联动 [-] / Fault flag coupled with uErrorId
    uErrorId    : UDINT;   // 故障码，0 = 无故障 [-] / Error code, zero means healthy
END_VAR
VAR
    tonBad    : TON;                  // 坏值时长计时器（无条件每周期刷新） / Bad duration timer, refreshed unconditionally
    _bHasGood : BOOL;                 // 是否已获得过有效值 [-] / Whether a good value was ever acquired
    _fLastGood: LREAL;                // 上一有效值 [EU] / Last good value
    eState    : E_DL_HoldGoodState;   // 状态机当前状态 [-] / Current state
END_VAR
VAR CONSTANT
    DL_HGF_ZERO_L : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_HGF_ZERO_T : TIME := T#0S;    // 时长零基准 [s] / Zero duration base
END_VAR

(* —— 段 1：时长域闸（不中断扫描，只钳位并置信息码） —— *)
uErrorId := 16#0007_0000;                          // 预置无故障 / Preset healthy
IF tMaxBad < DL_HGF_ZERO_T THEN
    tMaxBad := DL_HGF_ZERO_T;                      // 负时长钳到零 / Negative duration clamped
    uErrorId := 16#0007_0001;                      // 信息级：时长已钳位 / Info: duration clamped
END_IF

(* —— 段 2：非有限防御（仅判据有效时读取 fIn；判据失效时输入无意义） —— *)
IF bEnable AND bGood THEN
    IF (fIn <> fIn) OR ((fIn - fIn) <> DL_HGF_ZERO_L) THEN
        eState   := eFault;                        // 判据与数值矛盾：报故障 / Contradiction between flag and value
        uErrorId := 16#0007_0002;                  // 故障级：判据有效但数值非有限 / Fault: good flag with non-finite value
    END_IF
END_IF

(* —— 段 3：复位请求 → 回首扫并清「已获有效值」标志 —— *)
IF bReset THEN
    eState    := eInit;
    _bHasGood := FALSE;                            // 清标志：需重新获得有效值 / Clear flag, must re-acquire
END_IF

(* —— 段 4：状态派生 —— *)
IF NOT bEnable THEN
    eState := eHold;                               // 未使能：冻结 / Disabled: freeze
ELSIF eState = eFault THEN
    eState := eFault;                              // 故障态保持 / Fault holds
ELSIF eState = eInit THEN
    eState := eInit;                               // 首扫保持一拍 / Init holds one scan
ELSE
    eState := eRun;
END_IF

(* —— 段 5：计时器无条件每周期刷新（R7 硬要求，位于 CASE 之外） —— *)
(* 计时条件：已使能、非故障、且当前判据失效（bad） *)
(* Timer runs only when enabled, healthy, and the quality flag is false *)
tonBad(IN := bEnable AND (eState <> eFault) AND (NOT bGood), PT := tMaxBad);

(* —— 段 6：主状态机（CASE 覆盖 + ELSE 兜底） —— *)
CASE eState OF

    eInit:
        IF bGood THEN
            _fLastGood := fIn;                     // 首个有效值 / First good value
            _bHasGood  := TRUE;
            fOut       := fIn;
            bHolding   := FALSE;
            bValid     := TRUE;
            eState     := eRun;                    // 已获有效值，进入运行态 / Enter running
        ELSE
            fOut     := DL_HGF_ZERO_L;             // 从未获得有效值：唯一置 0 的情形 / Only case that zeroes output
            bHolding := FALSE;
            bValid   := FALSE;                     // 明确声明：无可信值 / Explicitly no trustworthy value
            eState   := eRun;
        END_IF
        tBadElapsed := tonBad.ET;
        bTimedOut   := FALSE;

    eRun:
        IF bGood THEN
            _fLastGood := fIn;                     // 刷新上一有效值 / Refresh last good value
            _bHasGood  := TRUE;
            fOut       := fIn;                     // 采纳本拍输入 / Adopt current input
            bHolding   := FALSE;
            bValid     := TRUE;
            bTimedOut  := FALSE;                   // 判据恢复：超时标志清除（可达解除路径） / Timeout cleared
        ELSE
            fOut     := _fLastGood;                // 保持上一有效值 / Hold last good value
            bHolding := TRUE;
            bValid   := _bHasGood;                 // 无有效值历史时仍不可信 / Untrustworthy without history
            IF tMaxBad = DL_HGF_ZERO_T THEN
                bTimedOut := FALSE;                // T#0S = 不判超时 / Zero disables timeout
            ELSE
                bTimedOut := tonBad.Q;             // 超时才置位 / Set only after timeout
            END_IF
        END_IF
        tBadElapsed := tonBad.ET;

    eHold:
        (* 未使能：输出、保持标志与计时全部冻结 / Disabled: output, flags and timer all frozen *)
        tBadElapsed := tonBad.ET;
        bValid      := FALSE;

    eFault:
        (* 故障态：输出冻结保持上拍值，不推 0 / Fault: output frozen, never zeroed *)
        tBadElapsed := tonBad.ET;
        bValid      := FALSE;

    ELSE
        eState    := eFault;
        bValid    := FALSE;
        bHolding  := FALSE;
        bTimedOut := FALSE;
        uErrorId  := 16#0007_0005;                 // 故障级：非法状态 / Fault: illegal state

END_CASE;

(* —— 段 7：出口映射（bError 与 uErrorId 同源；bTimedOut 为信息级不置 bError） —— *)
bError := (uErrorId <> 16#0007_0000) AND (uErrorId <> 16#0007_0001);

END_FUNCTION_BLOCK
