(*
  ==================================================================
  组件名 Component  : FB_DL_TwoDofPid
  分类   Category   : DL_Algo
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.1
  功能   Purpose    : 二自由度 PID（设定值加权 beta / gamma），位置式：
                      u = Kp·(beta·sp - pv) + I + Kp·Td·(gamma·dsp/dt - dpv/dt)（滤后）。
                      积分作用于全误差 (sp - pv)；微分先行经 nFilter 一阶低通；
                      抗积分饱和（输出限幅方向与误差同向时停积分）；手动/自动
                      无扰切换（手动相把积分项跟踪为 fManOut - P - D）。
  来源   Source     : t2-5-modpid（参数域 beta / gamma）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；二自由度 PID 结构为
                      公开控制理论结果（Araki 参考跟踪 / 扰动抑制双自由度组织），
                      clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL 运算，无私有库、无幂运算符）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只算控制器输出，不驱动执行器、不做自整定（属主边界）；
                      二 同拍双窗说明（R100）：本件无同拍双 TON 结构，微分滤波为一阶
                         差分实现，无定时器实例；
                      三 fTi <= 0 时积分项关闭（纯 PD 口径），fTd <= 0 时微分项关闭；
                      四 bInvalid = TRUE 时输出冻结保持末值（R191 显式声明，降级不静默）；
                      五 故障锁存（组态非法）解除路径 = bReset 上升沿（唯一路径，R188）；
                      六 无全局变量、无外部变量声明、无物理地址寻址、无定时器实例。
  输出契约 Output contract:
                      fOut 恒被钳在 [fOutMin, fOutMax]；bSatHi / bSatLo 为本拍限幅指示；
                      eFault 为锁存回放（eCfgIllegal 组态非法 / eInputBad 本拍输入非有限）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 2 · 序号 8）
    2026-11-21  v1.0.1  R57 返修：手动相入口补 fManOut 有限性闸，无效拍冻结早退不进跟踪式
  ==================================================================
*)

TYPE E_DL_TdpFault :
(
    eNone     := 0, // 无成因 / no cause
    eCfgIllegal := 1, // 组态非法：增益或限幅越域（故障级，与 bError 配对）/ illegal config, gain or limit out of domain
    eInputBad := 2  // 本拍设定值或过程量非有限（信息级，输出冻结保持）/ the setpoint or process value is non finite this scan, the output holds frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_TwoDofPid
VAR_INPUT
    bAuto    : BOOL := TRUE;     // 自动模式，假 = 手动（无扰切换）[-] / auto mode, false is manual with a bumpless transfer
    bReset   : BOOL := FALSE;    // 复位上升沿清故障锁存与积分 [-] / reset rising edge clears the fault latch and the integral
    fSp      : LREAL := 0.0;     // 设定值 [工程单位] / setpoint [engineering unit]
    fPv      : LREAL := 0.0;     // 过程量实测 [工程单位] / measured process value [engineering unit]
    fManOut  : LREAL := 0.0;     // 手动输出值 [工程单位] / manual output value [engineering unit]
    fKp      : LREAL := 1.0;     // 比例增益，域 大于零 / proportional gain, domain above zero
    fTi      : LREAL := 10.0;    // 积分时间 [秒]，0 = 积分关闭 / integral time [second], zero disables the integral
    fTd      : LREAL := 0.0;     // 微分时间 [秒]，0 = 微分关闭 / derivative time [second], zero disables the derivative
    fBeta    : LREAL := 1.0;     // 设定值比例加权（抑超调自由度），域 0..1 / setpoint proportional weight [dimensionless], domain zero to one
    fGamma   : LREAL := 0.0;     // 设定值微分加权，域 0..1 / setpoint derivative weight, domain zero to one
    nFilter  : INT := 10;        // 微分低通系数 n（Td/n 为滤波时间），域 1..100 / derivative low pass coefficient n, domain one to one hundred
    fOutMin  : LREAL := 0.0;     // 输出下限 [工程单位] / output floor [engineering unit]
    fOutMax  : LREAL := 100.0;   // 输出上限 [工程单位]，域 大于下限 / output ceiling [engineering unit], above the floor
    fDtS     : LREAL := 0.01;    // 调用周期 [秒]，域 大于零 / call period [second], domain above zero
END_VAR
VAR_OUTPUT
    fOut     : LREAL := 0.0;   // 控制器输出 [工程单位] / controller output [engineering unit]
    bSatHi   : BOOL := FALSE;  // 本拍输出顶上限 [-] / the output hit the ceiling this scan
    bSatLo   : BOOL := FALSE;  // 本拍触下限 [-] / the output hit the floor this scan
    bInvalid : BOOL := FALSE;  // 本拍输出无效（冻结保持末值）[-] / the outlet is void this scan, the last value holds frozen
    eFault   : E_DL_TdpFault := E_DL_TdpFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError   : BOOL := FALSE;  // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG;  // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    _eFaulC  : E_DL_TdpFault := E_DL_TdpFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bInOk   : BOOL := FALSE; // 本拍 sp / pv 均有限 [-] / both sp and pv are finite this scan
    _fI      : LREAL := 0.0;  // 积分项保持量 [工程单位] / the integral term holder [engineering unit]
    _fDfilt  : LREAL := 0.0;  // 微分滤波保持量 [工程单位] / the derivative filter holder [engineering unit]
    _fPvPrev : LREAL := 0.0;  // 上拍过程量快照 [工程单位] / previous scan process value snapshot [engineering unit]
    _fSpPrev : LREAL := 0.0;  // 上拍设定值快照 [工程单位] / previous scan setpoint snapshot [engineering unit]
    _fP      : LREAL := 0.0;  // 本拍比例项 [工程单位] / the proportional term this scan [engineering unit]
    _fDraw   : LREAL := 0.0;  // 微分原始量 [工程单位] / the raw derivative term [engineering unit]
    _fE      : LREAL := 0.0;  // 全误差（sp - pv）[工程单位] / the full error [engineering unit]
    _fUPre   : LREAL := 0.0;  // 限幅前输出 [工程单位] / the pre clamp output [engineering unit]
    _fFiltB  : LREAL := 0.0;  // 微分滤波权（dt/(dt+Td/n)）[无量纲] / the derivative filter weight
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detector
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）：快照与积分从确定起点起步 / segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eFaulC := E_DL_TdpFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fI := 0.0; // 积分项清零 / clear the integral term
    _fDfilt := 0.0; // 微分滤波清零 / clear the derivative filter
    _fPvPrev := fPv; // 快照取当拍 / the snapshot takes this scan
    _fSpPrev := fSp; // 快照取当拍 / the snapshot takes this scan
END_IF

// 段 2｜复位沿作用域：清锁存 / 清积分与滤波（快照同步归位，三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_TdpFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _fI := 0.0; // 作用域二：清积分项 / scope two, clear the integral term
    _fDfilt := 0.0; // 作用域二：清微分滤波 / scope two, clear the derivative filter
    _fPvPrev := fPv; // 作用域三：快照归位 / scope three, the snapshot parks
    _fSpPrev := fSp; // 作用域三：快照归位 / scope three, the snapshot parks
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, configuration domain gate over every parameter pin
IF (fKp <= 0.0) OR (fKp <> fKp) OR ((fKp - fKp) <> (fKp - fKp)) OR (fTi < 0.0) OR (fTi <> fTi) OR (fTd < 0.0) OR (fTd <> fTd) OR (fBeta < 0.0) OR (fBeta > 1.0) OR (fBeta <> fBeta) OR (fGamma < 0.0) OR (fGamma > 1.0) OR (fGamma <> fGamma) OR (nFilter < 1) OR (nFilter > 100) OR (fOutMax <= fOutMin) OR (fOutMax <> fOutMax) OR (fDtS <= 0.0) OR (fDtS <> fDtS) THEN // 任一参数越域或非有限 / any parameter out of domain or non finite
    IF (NOT _bFault) AND (_eFaulC = E_DL_TdpFault.eNone) THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_TdpFault.eCfgIllegal; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    END_IF
END_IF

// 段 4｜输入有限性闸与冻结语义 / segment 4, the input finiteness gate and the frozen semantics
_bInOk := (fSp = fSp) AND ((fSp - fSp) = (fSp - fSp)) AND (fPv = fPv) AND ((fPv - fPv) = (fPv - fPv)); // sp / pv 有限性 / finiteness of sp and pv

// 段 5｜无扰切换：手动相把积分项跟踪为 fManOut - P - D / segment 5, the bumpless transfer, the manual phase tracks the integral
IF NOT bAuto THEN // 手动相 / the manual phase
    IF (fManOut <> fManOut) OR ((fManOut - fManOut) <> (fManOut - fManOut)) THEN // 手动输出非有限（x<>x 判 NaN，x-x<>x-x 判 Inf，v1.0.1 返修）/ the manual output is non finite (v1.0.1 fix)
        IF NOT _bFault THEN // 故障锁存优先回放，信息级不覆盖故障码 / the fault latch replays first, an informational cause never overwrites a fault code
            _eFaulC := E_DL_TdpFault.eInputBad; // 信息级成因（R45 不配对 bError）/ the informational cause, not paired with bError
        END_IF
        bInvalid := TRUE; // 置无效标志 / raise the invalid flag
        bSatHi := FALSE; // 限幅指示为假 / the saturation flags are false
        bSatLo := FALSE; // 限幅指示为假 / the saturation flags are false
        eFault := _eFaulC; // 成因出口锁存回放 / the cause outlet replayed from the latch
        bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
        _fPvPrev := fPv; // 快照推进（防恢复时微分踢）/ advance the snapshot against a derivative kick
        _fSpPrev := fSp; // 快照推进 / advance the snapshot
        RETURN; // 早退，fOut 冻结保持末值，不进跟踪式（R191 已声明）/ early return, fOut holds frozen, no tracking (R191 declared)
    END_IF
    _fP := fKp * (fBeta * fSp - fPv); // 比例项同口径计算（为跟踪做准备）/ the proportional term for the tracking base
    _fI := fManOut - _fP - _fDfilt; // 积分项跟踪，自动恢复时无扰 / the integral tracks for a bumpless auto resume
    fOut := fManOut; // 手动输出直通 / the manual output passes through
    IF fOut > fOutMax THEN // 手动输出上钳 / clamp the manual output high
        fOut := fOutMax; // 钳到上限 / clamp to the ceiling
    ELSIF fOut < fOutMin THEN // 手动输出下钳 / clamp the manual output low
        fOut := fOutMin; // 钳到下限 / clamp to the floor
    END_IF
    bSatHi := FALSE; // 手动相限幅指示为假 / the saturation flags are false in manual
    bSatLo := FALSE; // 手动相限幅指示为假 / the saturation flags are false in manual
    bInvalid := (NOT _bInOk) OR _bFault; // 有效性随输入与锁存 / the validity follows the input and the latch
    eFault := _eFaulC; // 成因出口锁存回放 / the cause outlet replayed from the latch
    bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
    _fPvPrev := fPv; // 快照推进 / advance the snapshot
    _fSpPrev := fSp; // 快照推进 / advance the snapshot
    RETURN; // 手动相早退（出口段已完整施加，R94）/ the manual phase early return with a complete outlet
END_IF

// 段 6｜自动相：无效输入冻结保持 / segment 6, the auto phase, a void input holds frozen
IF (NOT _bInOk) OR _bFault THEN // 输入无效或故障锁存 / the input is void or faulted
    IF (NOT _bInOk) AND (NOT _bFault) THEN // 输入缺陷才记信息级成因（不覆盖故障码）/ only an input defect records the informational cause, never over a fault latch
        _eFaulC := E_DL_TdpFault.eInputBad; // 信息级成因，每拍重算 / the informational cause, recomputed every scan
    END_IF
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    bSatHi := FALSE; // 限幅指示为假 / the saturation flags are false
    bSatLo := FALSE; // 限幅指示为假 / the saturation flags are false
    eFault := _eFaulC; // 成因出口锁存回放 / the cause outlet replayed from the latch
    bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
    _fPvPrev := fPv; // 快照推进（防恢复时微分踢）/ advance the snapshot against a derivative kick
    _fSpPrev := fSp; // 快照推进 / advance the snapshot
    RETURN; // 早退，fOut 冻结保持末值（R191 已在头注释声明）/ early return, fOut holds frozen per the declared semantics
END_IF

// 段 7｜比例与微分先行（幂次无，显式乘法）/ segment 7, the proportional and the derivative lead terms
_fE := fSp - fPv; // 全误差 / the full error
_fP := fKp * (fBeta * fSp - fPv); // 加权比例项 / the weighted proportional term
IF fTd > 0.0 THEN // 微分开启 / the derivative is on
    _fDraw := fTd * (fGamma * (fSp - _fSpPrev) - (fPv - _fPvPrev)) / fDtS; // 加权微分原始量，除子为周期已证大于零 / the weighted raw derivative, the divisor is the proven period
    _fFiltB := fDtS / (fDtS + fTd / INT_TO_LREAL(nFilter)); // 一阶低通权，除子已证大于零 / the first order weight with a proven divisor
    _fDfilt := _fDfilt + _fFiltB * (_fDraw - _fDfilt); // 微分低通推进 / advance the derivative low pass
ELSE // 微分关闭 / the derivative is off
    _fDfilt := 0.0; // 微分项归零 / the derivative term is zeroed
END_IF

// 段 8｜积分与抗饱和：先算限幅前输出，再按方向条件积分 / segment 8, the integral with anti windup, the clamp direction gates the accumulation
_fUPre := _fP + _fI + _fDfilt; // 限幅前输出 / the pre clamp output
IF (fTi > 0.0) THEN // 积分开启 / the integral is on
    IF NOT ((_fUPre > fOutMax) AND (_fE > 0.0)) AND NOT ((_fUPre < fOutMin) AND (_fE < 0.0)) THEN // 输出未沿误差方向饱和才积分（抗 windup）/ the integration only runs when the output is not saturated in the error direction
        _fI := _fI + (fKp / fTi) * _fE * fDtS; // 积分推进，除子为积分时间已证大于零 / the integral step with the proven divisor
    END_IF
END_IF
_fUPre := _fP + _fI + _fDfilt; // 积分后重算限幅前输出 / recompute after the integral

// 段 9｜限幅与限幅指示 / segment 9, the clamp and the saturation flags
bSatHi := FALSE; // 限幅指示预置假 / preset the saturation flags to false
bSatLo := FALSE; // 限幅指示预置假 / preset the saturation flags to false
IF _fUPre > fOutMax THEN // 顶上限 / above the ceiling
    fOut := fOutMax; // 钳到上限 / clamp to the ceiling
    bSatHi := TRUE; // 置顶上限指示 / raise the ceiling flag
ELSIF _fUPre < fOutMin THEN // 触下限 / below the floor
    fOut := fOutMin; // 钳到下限 / clamp to the floor
    bSatLo := TRUE; // 置触下限指示 / raise the floor flag
ELSE // 域内 / inside the domain
    fOut := _fUPre; // 直接出口 / straight to the outlet
END_IF

// 段 10｜快照推进与统一出口 / segment 10, the snapshot advance and the unified outlet
_fPvPrev := fPv; // 过程量快照推进 / advance the process snapshot
_fSpPrev := fSp; // 设定值快照推进 / advance the setpoint snapshot
IF (_eFaulC = E_DL_TdpFault.eInputBad) AND (NOT _bFault) THEN // 输入已恢复 / the input has recovered
    _eFaulC := E_DL_TdpFault.eNone; // 信息级成因随恢复撤销 / the informational cause is revoked on recovery
END_IF
bInvalid := FALSE; // 自动有效拍 / the valid auto scan
eFault := _eFaulC; // 成因出口锁存回放 / the cause outlet replayed from the latch
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
