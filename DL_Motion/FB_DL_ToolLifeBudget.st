(*
  ==================================================================
  组件名 Component  : FB_DL_ToolLifeBudget
  分类   Category   : DL_Motion
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 刀具寿命预算。切削时长（bCutting 期按 fDtSec 累计）与
                      件数（bPieceDone 沿计数）双口径累计；寿命分档预警
                      eTier：eOk / eWarn（≥fWarnPct%）/ eAlert（≥fAlertPct%）
                      / eExhausted（≥100%，置 bChangeDue）；换刀沿全量复位。
                      GitHub topics 公开语义 clean-room，与
                      FB_DL_AxisLubeDistTrig 分工。
  来源   Source     : T1-8-github-topics（刀具寿命公开语义）
  溯源   Origin     : 切削时长与件数双口径寿命预算为公开工程语义，clean-room
                      自研实现，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FB_DL_AxisLubeDistTrig 分工——后者做润滑距离触发，
                      本件做刀具寿命双口径预算。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限/组态闸：fDtSec 非有限或 ∉ (0,1] 置 bBad
                         （纪律②），冻结累计不推进（不静默吞）；
                      二 累计上界钳制（时长 1E7 秒 / 件数 1E6 件，防回绕）；
                      三 换刀沿（bToolChange 上升沿）全量复位：时长 / 件数
                         / 分档全清（解除路径唯一，R188）；
                      四 分档双口径取 max（时长比与件数比孰高），分档单调
                         不回落（锁存口径：已达档位不因当拍口径回落而降档）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 4 · 序号 19）
  ==================================================================
*)

TYPE E_DL_TltTier :
(
    eTltOk       := 0,  // 寿命充足档 [-] / the healthy tier
    eTltWarn     := 10, // 预警档（≥fWarnPct%）[-] / the warn tier
    eTltAlert    := 20, // 告警档（≥fAlertPct%）[-] / the alert tier
    eTltExhausted:= 30  // 寿命耗尽档（≥100%，bChangeDue）[-] / the exhausted tier
);
END_TYPE

FUNCTION_BLOCK FB_DL_ToolLifeBudget
VAR_INPUT
    bCutting    : BOOL  := FALSE;   // 切削进行信号（时长累计闸）[-] / the cutting active signal, the time accumulation gate
    bPieceDone  : BOOL  := FALSE;   // 单件完成信号，上升沿计数 [-] / the piece done signal, the rising edge counts
    fDtSec      : LREAL := 0.1;     // 调用周期 [秒]，域 (0,1] / the call period [second]
    fLifeTimeSec: LREAL := 3600.0;  // 时长口径寿命预算 [秒] / the time budget [second]
    nLifePcs    : UDINT := 1000;    // 件数口径寿命预算 [件] / the piece budget
    fWarnPct    : LREAL := 80.0;    // 预警档阈值 [%] / the warn tier threshold [percent]
    fAlertPct   : LREAL := 95.0;    // 告警档阈值 [%] / the alert tier threshold [percent]
    bToolChange : BOOL  := FALSE;   // 换刀信号，上升沿全量复位 [-] / the tool change signal, the rising edge resets all
END_VAR
VAR_OUTPUT
    fCutTimeAcc : LREAL := 0.0;   // 切削时长累计 [秒] / the cutting time accumulated [second]
    nPieceCnt   : UDINT := 0;     // 完成件数累计 [件] / the piece count accumulated
    eTier       : E_DL_TltTier := E_DL_TltTier.eTltOk; // 寿命分档输出 [-] / the life tier outlet
    bChangeDue  : BOOL  := FALSE; // 换刀到期指示（eTltExhausted 同源）[-] / the change due indicator
    fLifePct    : LREAL := 0.0;   // 双口径寿命占用率（孰高）[%] / the life usage, the higher of the two ratios [percent]
    bBad        : BOOL  := FALSE; // 步长非有限/越域实时标志 [-] / the period fault live flag
END_VAR
VAR CONSTANT
    DL_TLT_TMAX  : LREAL := 1.0E7;  // 时长累计上界 [秒] / the time accumulation ceiling
    DL_TLT_NMAX  : UDINT := 1000000; // 件数累计上界 [件] / the piece accumulation ceiling
    DL_TLT_EPS   : LREAL := 1.0E-9; // 预算下阈值 [秒 / 件] / the budget threshold
END_VAR
VAR
    _fRatioT : LREAL; // 时长口径占用率 [%] / the time ratio [percent]
    _fRatioP : LREAL; // 件数口径占用率 [%] / the piece ratio [percent]
    _eTier   : E_DL_TltTier := E_DL_TltTier.eTltOk; // 分档锁存寄存（单调不回落）/ the tier latch, monotonic
    rtDone   : R_TRIG; // 件完成沿，段 0 无条件刷新 / the piece done edge
    rtChange : R_TRIG; // 换刀沿，段 0 无条件刷新 / the change edge
    bFinDt   : BOOL;   // 步长有限工作量 [-] / the period finiteness work flag
    bCfg     : BOOL;   // 组态域工作量 [-] / the config domain work flag
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtDone(CLK := bPieceDone); // 件完成沿 / the piece done edge
rtChange(CLK := bToolChange); // 换刀沿 / the change edge

// 段 1｜换刀沿全量复位（边界三，解除路径 = 换刀沿，R188）/ segment 1, the change edge full reset
IF rtChange.Q THEN // 换刀沿 / the change edge
    fCutTimeAcc := 0.0; // 时长清零 / clear the time
    nPieceCnt := 0; // 件数清零 / clear the pieces
    _eTier := E_DL_TltTier.eTltOk; // 分档归位 / reset the tier
END_IF

// 段 2｜步长闸（边界一，实时标志非锁存）/ segment 2, the period gate
bFinDt := (fDtSec = fDtSec) AND ((fDtSec - fDtSec) = (fDtSec - fDtSec)); // 步长有限双判据（R79）/ the finiteness dual verdicts
bCfg := (fDtSec > 0.0) AND (fDtSec <= 1.0) // 步长域 (0,1] / the period domain
    AND (fLifeTimeSec > DL_TLT_EPS) AND (nLifePcs > 0) // 双口径预算为正 / the budgets positive
    AND (fWarnPct > 0.0) AND (fAlertPct > fWarnPct) AND (fAlertPct <= 100.0); // 分档阈值序合理 / the threshold order sane
bBad := (NOT bFinDt) OR (NOT bCfg); // 闸实时标志（R191 名实双出口）/ the gate flag

// 段 3｜双口径累计（闸通过才推进，上界钳制，边界一二）/ segment 3, the dual accumulation
IF bCutting AND (NOT bBad) THEN // 切削且闸通过 / cutting and gated
    fCutTimeAcc := fCutTimeAcc + fDtSec; // 时长累计 / accumulate the time
    IF fCutTimeAcc > DL_TLT_TMAX THEN // 时长上界钳制 / clamp the time ceiling
        fCutTimeAcc := DL_TLT_TMAX; // 夹到上界 / clamp
    END_IF
END_IF
IF rtDone.Q AND (NOT bBad) THEN // 件完成沿且闸通过 / the done edge and gated
    IF nPieceCnt < DL_TLT_NMAX THEN // 件数上界钳制（防回绕）/ the piece wrap guard
        nPieceCnt := nPieceCnt + 1; // 件数推进 / advance the pieces
    END_IF
END_IF

// 段 4｜分档判定（双口径孰高 + 单调锁存，边界四）/ segment 4, the tier verdict
IF (NOT bBad) AND (fLifeTimeSec > DL_TLT_EPS) AND (nLifePcs > 0) THEN // 有效预算才判定 / the verdict with the valid budgets
    _fRatioT := (fCutTimeAcc / fLifeTimeSec) * 100.0; // 时长占用率 [%]（除子域闸保证）/ the time ratio
    _fRatioP := (UDINT_TO_LREAL(nPieceCnt) / UDINT_TO_LREAL(nLifePcs)) * 100.0; // 件数占用率 [%]/ the piece ratio
    IF _fRatioT > _fRatioP THEN // 孰高口径 / the higher ratio
        fLifePct := _fRatioT; // 取时长口径 / take the time ratio
    ELSE // 件数口径更高或持平 / the piece ratio higher or equal
        fLifePct := _fRatioP; // 取件数口径 / take the piece ratio
    END_IF
    IF fLifePct >= 100.0 THEN // 耗尽档 / the exhausted tier
        _eTier := E_DL_TltTier.eTltExhausted; // 升档（锁存单调）/ raise the tier
    ELSIF fLifePct >= fAlertPct THEN // 告警档 / the alert tier
        IF _eTier < E_DL_TltTier.eTltAlert THEN // 仅低档升档（单调不回落）/ raise only from a lower tier
            _eTier := E_DL_TltTier.eTltAlert; // 升到告警 / raise to the alert
        END_IF
    ELSIF fLifePct >= fWarnPct THEN // 预警档 / the warn tier
        IF _eTier < E_DL_TltTier.eTltWarn THEN // 仅低档升档 / raise only from a lower tier
            _eTier := E_DL_TltTier.eTltWarn; // 升到预警 / raise to the warn
        END_IF
    END_IF
END_IF
eTier := _eTier; // 分档出口 / the tier outlet
bChangeDue := (_eTier = E_DL_TltTier.eTltExhausted); // 换刀到期（R191 名实双出口）/ the change due indicator
END_FUNCTION_BLOCK
