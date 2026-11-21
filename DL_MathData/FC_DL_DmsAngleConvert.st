(*
  ==================================================================
  组件名 Component  : FC_DL_DmsAngleConvert
  分类   Category   : DL_MathData
  复杂度 Complexity  : 轻
  版本   Version    : 1.0.0
  功能   Purpose    : 度分秒 ↔ 十进制度双向换算。eToDecimal 方向：度/分/秒
                      组 → 十进制度（分秒进位钳制：秒≥60 进位到分，分≥60 进
                      位到度，符号取度分量符号）；eToDms 方向：十进制度 →
                      度/分/秒（分秒取下整，秒保留小数）。Converter 组角度
                      细分，与 FC_DL_WrapAngleDeg 归一化分工。
  来源   Source     : T2-1-lgf-converter（LGF Converter 组角度细分语义）
  溯源   Origin     : 度分秒换算为公开算术语义，clean-room 自研实现，未复制
                      LGF 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_WrapAngleDeg 分工——后者做角度 ±180 归一化，
                      本件做度分秒/十进制双向细分换算。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限入参闸（自反双判据）：命中置 bError 早退，
                         输出安全侧零（四段式 R45）；
                      二 进位钳制（信息级）：秒 ∈ [0,60) 分 ∈ [0,60) 之外
                         进位归整并置 bClamped，不静默吞掉（本库纪律②）；
                      三 秒/分取值域闸：eToDecimal 方向分量绝对值 > 10000
                         视为非法置 bError（防溢出滥用）；
                      四 除法仅除正常量 60.0 / 3600.0（无除零风险）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 1 · 序号 4）
  ==================================================================
*)

TYPE E_DL_DmsMode :
(
    eToDecimal := 0, // 度分秒 → 十进制度 / the dms to decimal direction
    eToDms     := 1  // 十进制度 → 度分秒 / the decimal to dms direction
);
END_TYPE

FUNCTION FC_DL_DmsAngleConvert : BOOL
VAR_INPUT
    eMode   : E_DL_DmsMode; // 换算方向枚举 [-] / the conversion direction enum
    fDeg    : LREAL := 0.0; // 度分量 [度]，eToDecimal 方向入口 / the degree component, the to decimal entry
    fMin    : LREAL := 0.0; // 分分量 [角分]，域 [0,60) / the arc minute component
    fSec    : LREAL := 0.0; // 秒分量 [角秒]，域 [0,60) / the arc second component
    fDecDeg : LREAL := 0.0; // 十进制度 [度]，eToDms 方向入口 / the decimal degrees, the to dms entry
END_VAR
VAR_OUTPUT
    fDecOut : LREAL := 0.0; // 十进制度输出 [度] / the decimal degrees outlet
    fDOut   : DINT  := 0;   // 度分量输出（带符号）[度] / the signed degree component outlet
    fMOut   : DINT  := 0;   // 分分量输出 [角分] / the arc minute outlet
    fSOut   : LREAL := 0.0; // 秒分量输出 [角秒] / the arc second outlet
    bValid  : BOOL := FALSE; // 结果可用标志 [-] / the result usable flag
    bClamped: BOOL := FALSE; // 分秒进位钳制发生（信息级）[-] / a carry clamp happened, informational
    bError  : BOOL := FALSE; // 故障标志（非有限或分量滥值）[-] / the fault flag
END_VAR
VAR
    lrAbsDeg : LREAL; // 度分量绝对值工作量 [度] / the absolute degree work value
    lrMinW   : LREAL; // 分工作量 [角分] / the minute work value
    lrSecW   : LREAL; // 秒工作量 [角秒] / the second work value
    lrAbsDec : LREAL; // 十进制绝对值工作量 [度] / the absolute decimal work value
    lrMinTot : LREAL; // 总分钟工作量 [角分] / the total minutes work value
    lrSecTot : LREAL; // 总秒工作量 [角秒] / the total seconds work value
    nCarry   : DINT;  // 进位整数量 [次] / the carry integer count
    bNeg     : BOOL;  // 符号寄存，TRUE = 负 [-] / the sign register, true = negative
END_VAR

// 段 1｜返回值与输出预置安全值（四段式第一段，R45）/ segment 1, preset the return and the outputs
FC_DL_DmsAngleConvert := FALSE; // 受理标志预置假 / preset the accepted flag false
fDecOut := 0.0; // 十进制输出预置零 / preset the decimal output zero
fDOut := 0; // 度分量预置零 / preset the degree zero
fMOut := 0; // 分分量预置零 / preset the minute zero
fSOut := 0.0; // 秒分量预置零 / preset the second zero
bValid := FALSE; // 有效预置假 / preset the valid false
bClamped := FALSE; // 钳制预置假 / preset the clamp false
bError := FALSE; // 故障预置假 / preset the fault false

// 段 2｜非有限入参闸（自反双判据，R79）/ segment 2, the non finite gate
IF (fDeg <> fDeg) OR ((fDeg - fDeg) <> (fDeg - fDeg)) THEN // 度分量非有限 / a non finite degree
    bError := TRUE; // 置故障 / raise the fault
END_IF
IF (fMin <> fMin) OR ((fMin - fMin) <> (fMin - fMin)) THEN // 分分量非有限 / a non finite minute
    bError := TRUE; // 置故障 / raise the fault
END_IF
IF (fSec <> fSec) OR ((fSec - fSec) <> (fSec - fSec)) THEN // 秒分量非有限 / a non finite second
    bError := TRUE; // 置故障 / raise the fault
END_IF
IF (fDecDeg <> fDecDeg) OR ((fDecDeg - fDecDeg) <> (fDecDeg - fDecDeg)) THEN // 十进制非有限 / a non finite decimal
    bError := TRUE; // 置故障 / raise the fault
END_IF
IF bError THEN // 非有限命中：早退（输出保持安全侧零）/ a non finite hit, return early
    RETURN; // 早退 / return early
END_IF

// 段 3｜方向一：度分秒 → 十进制度（进位钳制 + 符号取度分量，边界二三）/ segment 3, the dms to decimal direction
IF eMode = E_DL_DmsMode.eToDecimal THEN // 方向一受理 / the direction one
    IF (ABS(fDeg) > 10000.0) OR (ABS(fMin) > 10000.0) OR (ABS(fSec) > 10000.0) THEN // 分量滥值闸 / the component abuse gate
        bError := TRUE; // 置故障（防溢出滥用）/ raise the fault
        RETURN; // 早退 / return early
    END_IF
    bNeg := fDeg < 0.0; // 符号取度分量 / the sign from the degree component
    lrAbsDeg := ABS(fDeg); // 取绝对值 / take the absolute
    lrMinW := ABS(fMin); // 分绝对值 / the minute absolute
    lrSecW := ABS(fSec); // 秒绝对值 / the second absolute
    nCarry := LREAL_TO_DINT(TRUNC(lrSecW / 60.0)); // 秒到分进位量 [次] / the second to minute carry
    IF nCarry > 0 THEN // 有进位则钳制 / a carry means the clamp
        lrSecW := lrSecW - 60.0 * DINT_TO_LREAL(nCarry); // 秒回夹 [0,60) / re-clamp the seconds
        lrMinW := lrMinW + DINT_TO_LREAL(nCarry); // 分进位 / carry into the minutes
        bClamped := TRUE; // 信息级钳制 / the informational clamp
    END_IF
    nCarry := LREAL_TO_DINT(TRUNC(lrMinW / 60.0)); // 分到度进位量 [次] / the minute to degree carry
    IF nCarry > 0 THEN // 有进位则钳制 / a carry means the clamp
        lrMinW := lrMinW - 60.0 * DINT_TO_LREAL(nCarry); // 分回夹 [0,60) / re-clamp the minutes
        lrAbsDeg := lrAbsDeg + DINT_TO_LREAL(nCarry); // 度进位 / carry into the degrees
        bClamped := TRUE; // 信息级钳制 / the informational clamp
    END_IF
    fDecOut := lrAbsDeg + lrMinW / 60.0 + lrSecW / 3600.0; // 十进制组装（常量除法无除零）/ assemble the decimal
    IF bNeg THEN // 负角 / the negative angle
        fDecOut := -fDecOut; // 施加符号 / apply the sign
    END_IF
    fDOut := TRUNC(fDecOut); // 度分量（带符号下整）/ the signed truncated degree
    fMOut := LREAL_TO_DINT(TRUNC(ABS(fDecOut - DINT_TO_LREAL(fDOut)) * 60.0)); // 分分量 / the minute component
    fSOut := (ABS(fDecOut - DINT_TO_LREAL(fDOut)) * 60.0) - DINT_TO_LREAL(fMOut); // 秒分量（余量小数）/ the second component
    bValid := TRUE; // 结果可用 / the result usable
    FC_DL_DmsAngleConvert := TRUE; // 受理 / accept

// 段 4｜方向二：十进制度 → 度分秒（分秒取下整，秒留小数）/ segment 4, the decimal to dms direction
ELSIF eMode = E_DL_DmsMode.eToDms THEN // 方向二受理 / the direction two
    bNeg := fDecDeg < 0.0; // 符号寄存 / register the sign
    lrAbsDec := ABS(fDecDeg); // 绝对值 / the absolute
    fDOut := TRUNC(lrAbsDec); // 度分量下整 / the truncated degree
    lrMinTot := (lrAbsDec - DINT_TO_LREAL(fDOut)) * 60.0; // 总分钟 [角分] / the total minutes
    fMOut := TRUNC(lrMinTot); // 分分量下整 / the truncated minute
    lrSecTot := (lrMinTot - DINT_TO_LREAL(fMOut)) * 60.0; // 总秒 [角秒] / the total seconds
    fSOut := lrSecTot; // 秒分量留小数 / the second with decimals
    IF fSOut >= 59.999999 THEN // 秒满进位钳制（浮点容差防 60.000 溢出）[角秒] / the second rollover clamp with a tolerance
        fSOut := 0.0; // 秒归零 / zero the second
        fMOut := fMOut + 1; // 分进一 / advance the minute
        IF fMOut >= 60 THEN // 分满 / the minute full
            fMOut := 0; // 分归零 / zero the minute
            fDOut := fDOut + 1; // 度进一 / advance the degree
        END_IF
        bClamped := TRUE; // 信息级钳制 / the informational clamp
    END_IF
    IF bNeg THEN // 负角 / the negative angle
        fDOut := -fDOut; // 符号施加于度分量 / the sign on the degree
    END_IF
    fDecOut := fDecDeg; // 十进制直通回显 / the decimal echo
    bValid := TRUE; // 结果可用 / the result usable
    FC_DL_DmsAngleConvert := TRUE; // 受理 / accept
ELSE // 非法方向枚举兜底 / the illegal direction fallback
    bError := TRUE; // 置故障 / raise the fault
END_IF
END_FUNCTION
