(*
  ==================================================================
  组件名 Component  : FB_DL_LossInWeightFeeder
  分类   Category   : DL_Algo
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.1
  功能   Purpose    : 失重式给料控制。称重 w(t) 一阶差分求失重速率（负变化为正
                      给料率），一阶低通滤波后进 PI 闭环调节螺旋输出；低料位触发
                      补料相（输出冻结归零、计量与速率估计暂停），补料完成沿或
                      超时退出；批量累计达目标判批次结束。速率长期为零而输出非零
                      判 eNoLossRate；称重突跳超物理限判 eWeightNoise。
  来源   Source     : t2-2-lbp（与 FB_DL_BatchDosingControl 分工：连续失重 vs 批次定量）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；失重秤连续给料为公开
                      工艺语义，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / LREAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  同拍双窗配比约束（R100）：tRefillTo（补料超时窗）与 tNoRateTo（无速率确认窗）
                      职责分离、分属不同相，IN 串各自相位闸，无同拍并跑；
                      配比约束 tRefillTo > tNoRateTo 在组态域闸内判故障。
  边界 Boundary     :
                      一 本件只算给料输出与批量累计，不驱动螺旋电机本体、不控补料阀
                         （补料阀由外部按 bRefilling 执行，属主边界）；
                      二 失重速率方向约定：w(t) 递减 = 给料，速率为正；
                      三 补料相冻结语义（R191 显式声明）：输出归零、累计与速率估计
                         全部暂停，恢复后从冻结点继续；
                      四 相级看门狗使能只用相驻留本身（R145）；
                      五 故障锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fRateOut 为 PI 后给料输出（0..fOutMax）；bDosing / bRefilling
                      为相位派生电平；fBatchAcc 为批量累计 [千克]；
                      eFault 为锁存回放；ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 4 · 序号 16）
    2026-11-21  v1.0.1  R57 返修：空闲相 / 失能迁移 / 故障锁存三路径输出安全侧归零
  ==================================================================
*)

TYPE E_DL_LwfPhase :
(
    eIdle   := 0,  // 空闲：等启动沿 / idle, waiting for the start edge
    eDose   := 10, // 给料：PI 闭环与批量累计 / dosing, the PI loop and the batch accumulation
    eRefill := 20, // 补料：计量冻结，等补料完成 / refilling, the metering freezes until the refill completes
    eDone   := 30, // 批次完成：驻留等复位或新启动 / done, held until reset or a new start
    eFault  := 90  // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_LwfFault :
(
    eNone         := 0, // 无成因 / no cause
    eNoLossRate   := 1, // 输出非零而速率长期为零（故障级，与 bError 配对）/ a nonzero output with a void loss rate, fault grade paired with bError
    eWeightNoise  := 2, // 称重突跳超物理限（故障级，与 bError 配对）/ a weight jump beyond the physical limit, fault grade paired with bError
    eRefillTimeout:= 3, // 补料超时（故障级，与 bError 配对）/ the refill timed out, fault grade paired with bError
    eSensorBad    := 4, // 称重非有限或组态非法（故障级，与 bError 配对）/ the weight is non finite or the config illegal, fault grade paired with bError
    ePhaseBad     := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_LossInWeightFeeder
VAR_INPUT
    bEnable     : BOOL := TRUE;    // 使能，失能时停给料回空闲 [-] / enable, the feeding stops when disabled
    bReset      : BOOL := FALSE;   // 复位上升沿清故障锁存与批量累计 [-] / reset rising edge clears the fault latch and the batch accumulation
    bStart      : BOOL := FALSE;   // 批次启动脉冲，上升沿受理 [-] / the batch start pulse, accepted on the rising edge
    bRefillDone : BOOL := FALSE;   // 补料完成脉冲（外部给出）[-] / the refill done pulse from the outside
    fWeightKg   : LREAL := 100.0;  // 称重实测 [千克] / the measured weight [kilogram]
    fRateSp     : LREAL := 10.0;   // 目标给料速率 [千克每小时]，域 大于零 / the target feed rate [kilogram per hour], domain above zero
    fKp         : LREAL := 2.0;    // PI 比例增益 [输出每速率误差] / the PI proportional gain [output per rate error]
    fTi         : LREAL := 30.0;   // PI 积分时间 [秒]，域 大于零 / the PI integral time [second], domain above zero
    fOutMax     : LREAL := 100.0;  // 输出上限 [百分比] / the output ceiling [percent]
    fRateFiltT  : LREAL := 2.0;    // 速率低通时间常数 [秒]，0 = 直通 / the rate low pass time constant [second], zero is a passthrough
    fNoiseLim   : LREAL := 500.0;  // 称重突跳物理限（速率口径）[千克每小时] / the weight jump physical limit in rate terms [kilogram per hour]
    fLowWeightKg: LREAL := 20.0;   // 低料位补料阈值 [千克] / the low weight refill threshold [kilogram]
    fBatchTarget: LREAL := 500.0;  // 批量目标 [千克]，域 大于零 / the batch target [kilogram], domain above zero
    tRefillTo   : TIME := T#120S;  // 补料超时窗 [毫秒]，域 大于 tNoRateTo / the refill timeout window, above the no rate window
    tNoRateTo   : TIME := T#10S;   // 无速率确认窗 [毫秒]，域 大于零 / the no rate confirm window [millisecond], domain above zero
    fDtS        : LREAL := 0.1;    // 调用周期 [秒]，域 大于零 / the call period [second], domain above zero
END_VAR
VAR_OUTPUT
    fRateOut  : LREAL := 0.0;  // 给料输出（PI 后，0..上限）[百分比] / the feed output after the PI [percent]
    bDosing   : BOOL := FALSE; // 给料中（相位派生电平）[-] / dosing, a phase derived level
    bRefilling: BOOL := FALSE; // 补料中（相位派生电平）[-] / refilling, a phase derived level
    fBatchAcc : LREAL := 0.0;  // 批量累计 [千克] / the batch accumulation [kilogram]
    ePhase    : E_DL_LwfPhase := E_DL_LwfPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault    : E_DL_LwfFault := E_DL_LwfFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError    : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStart   : R_TRIG; // 启动沿检测，段 0 无条件刷新 / start edge, refreshed unconditionally in segment zero
    rtRefillD : R_TRIG; // 补料完成沿检测，段 0 无条件刷新 / refill done edge, refreshed unconditionally in segment zero
    rtReset   : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonRefill : TON;    // 补料超时窗，段 0 无条件刷新 / the refill timeout window, refreshed unconditionally
    tonNoRate : TON;    // 无速率确认窗，段 0 无条件刷新 / the no rate confirm window, refreshed unconditionally
    _ePhase   : E_DL_LwfPhase := E_DL_LwfPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC   : E_DL_LwfFault := E_DL_LwfFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault   : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit    : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgOk   : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bInOk    : BOOL := FALSE; // 称重有限 [-] / the weight is finite
    _fWPrev   : LREAL := 0.0;  // 上拍称重快照 [千克] / previous scan weight snapshot [kilogram]
    _fRateRaw : LREAL := 0.0;  // 原始失重速率 [千克每小时] / the raw loss rate [kilogram per hour]
    _fRateF   : LREAL := 0.0;  // 滤后失重速率 [千克每小时] / the filtered loss rate [kilogram per hour]
    _fE       : LREAL := 0.0;  // 速率误差 [千克每小时] / the rate error [kilogram per hour]
    _fI       : LREAL := 0.0;  // 积分项保持量 [百分比] / the integral term holder [percent]
    _fUPre    : LREAL := 0.0;  // 限幅前输出 [百分比] / the pre clamp output [percent]
    _fW       : LREAL := 0.0;  // 一阶低通权 [无量纲] / the first order weight
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸（FB50-1）/ segment 0, unconditional refresh, no instance call inside a branch
rtStart(CLK := bStart); // 启动沿 / the start edge
rtRefillD(CLK := bRefillDone); // 补料完成沿 / the refill done edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonRefill(IN := (_ePhase = E_DL_LwfPhase.eRefill) AND (NOT _bFault), PT := tRefillTo); // 补料超时窗，IN 串补料相闸 / the refill timeout with the refill phase gate
tonNoRate(IN := (_ePhase = E_DL_LwfPhase.eDose) AND (fRateOut > 1.0) AND (NOT _bFault), PT := tNoRateTo); // 无速率确认窗，IN 串给料相闸与输出非零判据 / the no rate window with the dose phase gate

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_LwfPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaulC := E_DL_LwfFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fWPrev := fWeightKg; // 快照取当拍 / the snapshot takes this scan
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清批量累计与积分（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_LwfFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_LwfPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    fBatchAcc := 0.0; // 作用域三：清批量累计 / scope three, clear the batch accumulation
    _fI := 0.0; // 作用域三：清积分项 / scope three, clear the integral term
    _fRateF := 0.0; // 作用域三：清滤后速率 / scope three, clear the filtered rate
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖）/ segment 3, the configuration and input domain gates
_bInOk := (fWeightKg = fWeightKg) AND ((fWeightKg - fWeightKg) = (fWeightKg - fWeightKg)); // 称重有限性 / the weight finiteness
_bCfgOk := (fRateSp > 0.0) AND (fRateSp = fRateSp) AND (fKp > 0.0) AND (fKp = fKp) AND (fTi > 0.0) AND (fTi = fTi) AND (fOutMax > 0.0) AND (fOutMax = fOutMax) AND (fRateFiltT >= 0.0) AND (fRateFiltT = fRateFiltT) AND (fNoiseLim > 0.0) AND (fNoiseLim = fNoiseLim) AND (fBatchTarget > 0.0) AND (fBatchTarget = fBatchTarget) AND (tRefillTo > T#0S) AND (tNoRateTo > T#0S) AND (tRefillTo > tNoRateTo) AND (fDtS > 0.0) AND (fDtS = fDtS); // 组态参数域判定（含 R100 配比）/ the configuration verdict with the window pairing
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 输入非有限或组态非法 / a non finite input or an illegal configuration
    IF NOT _bFault THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_LwfFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_LwfPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF
END_IF

// 段 4｜失重速率计算（含噪声闸）：快照推进无条件执行，防恢复时速率踢 / segment 4, the loss rate computation with the noise gate, the snapshot advances unconditionally
_fRateRaw := 0.0; // 原始速率预置零 / preset the raw rate to zero
IF _bInOk AND _bCfgOk THEN // 输入与组态合法 / the input and the config are legal
    _fRateRaw := (_fWPrev - fWeightKg) / fDtS * 3600.0; // 失重速率 = 负变化 / 周期，转千克每小时（除子为周期已证大于零）/ the loss rate converted to kilogram per hour with a proven divisor
    IF ABS(_fRateRaw) > fNoiseLim THEN // 称重突跳超物理限 / the weight jump exceeds the physical limit
        IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_LwfFault.eWeightNoise; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_LwfPhase.eFault; // 迁故障相 / migrate to the fault phase
        END_IF
        _fRateRaw := 0.0; // 本拍噪声样本不参与 / the noisy sample does not participate
    END_IF
END_IF
_fWPrev := fWeightKg; // 快照推进（无条件）/ the snapshot advances unconditionally

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_LwfPhase.eIdle: // 空闲相：等启动沿 / the idle phase, waiting for the start edge
    fRateOut := 0.0; // 空闲相输出强制安全侧归零（v1.0.1 返修）/ the outlet is force-zeroed on the safe side while idle (v1.0.1 fix)
    IF bEnable AND (NOT _bFault) AND rtStart.Q THEN // 启动沿受理 / the start edge is accepted
        _ePhase := E_DL_LwfPhase.eDose; // 迁给料相 / migrate to the dose phase
    END_IF

E_DL_LwfPhase.eDose: // 给料相：PI 闭环 + 批量累计 + 低料位切换 / the dose phase, the PI loop, the accumulation and the refill switch
    IF NOT bEnable THEN // 失能 / disabled
        fRateOut := 0.0; // 迁移前先归零（安全侧，v1.0.1 返修）/ zeroed on the safe side before the migration (v1.0.1 fix)
        _ePhase := E_DL_LwfPhase.eIdle; // 回空闲相 / back to idle
    ELSE // 正常给料 / the normal feeding
        IF fRateFiltT > 0.0 THEN // 低通开启 / the low pass is on
            _fW := fDtS / (fDtS + fRateFiltT); // 一阶低通权，除子已证大于零 / the first order weight with a proven divisor
            _fRateF := _fRateF + _fW * (_fRateRaw - _fRateF); // 速率低通推进 / advance the rate low pass
        ELSE // 直通口径 / the passthrough
            _fRateF := _fRateRaw; // 原始速率直通 / the raw rate passes through
        END_IF
        fBatchAcc := fBatchAcc + _fRateF * fDtS / 3600.0; // 批量累计（千克每小时 × 秒 / 3600）/ accumulate the batch
        _fE := fRateSp - _fRateF; // 速率误差 / the rate error
        _fUPre := fKp * _fE + _fI; // 限幅前输出（比例 + 积分保持量）/ the pre clamp output
        IF NOT ((_fUPre >= fOutMax) AND (_fE > 0.0)) THEN // 未沿误差方向饱和才积分（抗 windup）/ the integration is gated against the saturation direction
            _fI := _fI + (fKp / fTi) * _fE * fDtS; // 积分推进，除子为积分时间已证大于零 / the integral step with the proven divisor
        END_IF
        _fUPre := fKp * _fE + _fI; // 积分后重算 / recompute after the integral
        IF _fUPre < 0.0 THEN // 下限钳零 / clamp the floor to zero
            fRateOut := 0.0; // 输出归零 / the output is zeroed
        ELSIF _fUPre > fOutMax THEN // 上限钳制 / clamp the ceiling
            fRateOut := fOutMax; // 钳到上限 / clamp to the ceiling
        ELSE // 域内 / inside the domain
            fRateOut := _fUPre; // 直接出口 / straight to the outlet
        END_IF
        IF fBatchAcc >= fBatchTarget THEN // 批量达标 / the batch target is reached
            _ePhase := E_DL_LwfPhase.eDone; // 迁完成相 / migrate to the done phase
        ELSIF fWeightKg <= fLowWeightKg THEN // 低料位触发补料 / the low weight triggers the refill
            fRateOut := 0.0; // 补料前输出归零（冻结语义）/ the output zeroes before the refill
            _ePhase := E_DL_LwfPhase.eRefill; // 迁补料相 / migrate to the refill phase
        ELSIF tonNoRate.Q THEN // 输出非零而速率长期为零 / a nonzero output with a void rate
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_LwfFault.eNoLossRate; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_LwfPhase.eFault; // 迁故障相 / migrate to the fault phase
        END_IF
    END_IF

E_DL_LwfPhase.eRefill: // 补料相：计量冻结，等完成沿（退出条件 ≥2：完成沿 / 超时 / 失能，R98）/ the refill phase with the metering frozen, at least two exit conditions
    fRateOut := 0.0; // 输出保持归零（R191 冻结语义显式声明）/ the output holds zeroed per the declared frozen semantics
    bRefilling := TRUE; // 补料指示 / the refilling indicator
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_LwfPhase.eIdle; // 回空闲相 / back to idle
    ELSIF rtRefillD.Q THEN // 补料完成沿 / the refill done edge
        _fI := 0.0; // 积分项清零（恢复后重新爬坡）/ clear the integral for a fresh ramp
        _ePhase := E_DL_LwfPhase.eDose; // 迁回给料相 / migrate back to the dose phase
    ELSIF tonRefill.Q THEN // 补料超时 / the refill timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_LwfFault.eRefillTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_LwfPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_LwfPhase.eDone: // 完成相：输出归零，等复位或新启动 / the done phase, the output zeroes until reset or a new start
    fRateOut := 0.0; // 输出归零 / the output is zeroed
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_LwfPhase.eIdle; // 回空闲相 / back to idle
    ELSIF rtStart.Q THEN // 新启动沿 / a new start edge
        fBatchAcc := 0.0; // 批量累计清零 / clear the batch accumulation
        _fI := 0.0; // 积分项清零 / clear the integral term
        _ePhase := E_DL_LwfPhase.eDose; // 迁给料相 / migrate to the dose phase
    END_IF

E_DL_LwfPhase.eFault: // 故障相：输出归零，成因锁存，等复位沿 / the fault phase, the output zeroes until the reset edge
    fRateOut := 0.0; // 输出安全侧归零 / the output takes the safe side zero
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_LwfPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_LwfFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_LwfPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜统一出口 / segment 6, the unified outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    fRateOut := 0.0; // 故障拍输出安全侧归零（v1.0.1 返修）/ the outlet is zeroed on the safe side while faulted (v1.0.1 fix)
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_LwfFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
bDosing := (_ePhase = E_DL_LwfPhase.eDose); // 给料指示（相位派生）/ the dosing indicator derived from the phase
bRefilling := (_ePhase = E_DL_LwfPhase.eRefill); // 补料指示（相位派生）/ the refilling indicator derived from the phase
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
