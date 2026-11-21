(*
  ==================================================================
  组件名 Component  : FB_DL_UvDoseCtrl
  分类   Category   : DL_Algo
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : UV 剂量控制。剂量 = 光强 × 曝晒时间（D = ∫I·kLamp·dt），
                      按剩余剂量误差 PI 闭环调光强输出（0..100%），累计达目标置
                      bDoseDone 单拍脉冲；灯管老化补偿系数 kLamp 外部给定；光强
                      非有限 / 负值闸；累计溢出保护；满输出长期照度不足判
                      eLampWeak；过冲超容差判 eDoseOvershoot。
  来源   Source     : 自研线（公开物理定义：剂量 = 强度 × 时间积分）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；UV 剂量定义为公开
                      光化学语义，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / LREAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只算调光输出与剂量累计，不驱动灯管电源本体（属主边界）；
                      二 bRun = FALSE 时调光输出归零、累计冻结保持（R191 显式声明）；
                      三 剂量累计溢出保护：累计达 1.0E9 mJ/cm² 上限即饱和（远超
                         任何工艺目标，防长跑溢出，R63 反算：1.0E9 在 LREAL 精确可表）；
                      四 故障锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fDimPct 恒在 [0, 100]；fDoseAcc 为累计剂量 [毫焦每平方厘米]；
                      bDoseDone 为单拍脉冲（内部 _bDoneInt 置位、统一出口映射后撤销，
                      R187 两段式）；eFault 为锁存回放；
                      ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 4 · 序号 17）
  ==================================================================
*)

TYPE E_DL_UdcPhase :
(
    eIdle  := 0,  // 空闲：等运行电平 / idle, waiting for the run level
    eDose  := 10, // 照射：闭环调光与剂量累计 / dosing, the closed loop dimming and the accumulation
    eDone  := 20, // 达标：脉冲已出，灯关驻留 / done, the pulse was raised and the lamp is off
    eFault := 90  // 故障：成因锁存，灯关 / fault, the cause is latched with the lamp off
);
END_TYPE

TYPE E_DL_UdcFault :
(
    eNone          := 0, // 无成因 / no cause
    eLampWeak      := 1, // 满输出照度不足（灯管老化，故障级，与 bError 配对）/ the intensity is weak at a full output, an aged lamp, fault grade paired with bError
    eDoseOvershoot := 2, // 剂量过冲超容差（故障级，与 bError 配对）/ the dose overshot the tolerance, fault grade paired with bError
    eSensorBad     := 3, // 光强非有限或负值（故障级，与 bError 配对）/ the intensity is non finite or negative, fault grade paired with bError
    ePhaseBad      := 4  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_UvDoseCtrl
VAR_INPUT
    bEnable    : BOOL := TRUE;    // 使能，失能时停判级回空闲 [-] / enable, the grading stops when disabled
    bReset     : BOOL := FALSE;   // 复位上升沿清故障锁存并剂量归零重批 [-] / reset rising edge clears the latch and zeroes the dose for a fresh batch
    bRun       : BOOL := FALSE;   // 运行电平，真 = 曝晒窗开 [-] / the run level, true opens the exposure window
    fIntensity : LREAL := 0.0;    // 光强实测 [毫瓦每平方厘米] / the measured intensity [milliwatt per square centimetre]
    fDoseTarget: LREAL := 100.0;  // 目标剂量 [毫焦每平方厘米]，域 大于零 / the target dose [millijoule per square centimetre], domain above zero
    kLamp      : LREAL := 1.0;    // 灯管老化补偿系数（有效光强占比），域 0..1 / the lamp ageing compensation factor, domain zero to one
    fKp        : LREAL := 5.0;    // PI 比例增益 [百分比每毫焦] / the PI proportional gain [percent per millijoule]
    fKi        : LREAL := 0.5;    // PI 积分增益 [百分比每毫焦每秒] / the PI integral gain
    fIntMin    : LREAL := 5.0;    // 最小有效照度 [毫瓦每平方厘米]，域 大于零 / the minimum effective intensity, domain above zero
    fOverTolPct: LREAL := 5.0;    // 过冲容差 [百分比]，域 大于零 / the overshoot tolerance [percent], domain above zero
    tWeakTo    : TIME := T#30S;   // 灯弱确认窗 [毫秒]，域 大于零 / the weak lamp confirm window [millisecond], domain above zero
    fDtS       : LREAL := 0.1;    // 调用周期 [秒]，域 大于零 / the call period [second], domain above zero
END_VAR
VAR_OUTPUT
    fDimPct   : LREAL := 0.0;  // 调光输出 [百分比] / the dimming output [percent]
    bDoseDone : BOOL := FALSE; // 剂量达标单拍脉冲 [-] / the dose done single shot pulse
    fDoseAcc  : LREAL := 0.0;  // 累计剂量 [毫焦每平方厘米] / the accumulated dose [millijoule per square centimetre]
    ePhase    : E_DL_UdcPhase := E_DL_UdcPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault    : E_DL_UdcFault := E_DL_UdcFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError    : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonWeak  : TON;    // 灯弱确认窗，段 0 无条件刷新 / the weak lamp window, refreshed unconditionally
    _ePhase  : E_DL_UdcPhase := E_DL_UdcPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_UdcFault := E_DL_UdcFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bDoneInt: BOOL := FALSE; // 达标脉冲内部位，统一出口映射 / internal done bit, mapped at the unified outlet
    _bInOk   : BOOL := FALSE; // 光强有限且非负 [-] / the intensity is finite and non negative
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bWeakRaw: BOOL := FALSE; // 满输出照度不足原始判据 [-] / the raw weak lamp verdict
    _fRate   : LREAL := 0.0;  // 剂量率 [毫焦每平方厘米每秒] / the dose rate
    _fE      : LREAL := 0.0;  // 剩余剂量误差 [毫焦每平方厘米] / the remaining dose error
    _fUPre   : LREAL := 0.0;  // 限幅前调光输出 [百分比] / the pre clamp dimming output
    _fI      : LREAL := 0.0;  // 积分项保持量 [百分比] / the integral term holder [percent]
    _fTol    : LREAL := 0.0;  // 过冲绝对容差 [毫焦每平方厘米] / the absolute overshoot tolerance
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与状态闸 / segment 0, unconditional refresh with the phase and state gates
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonWeak(IN := _bWeakRaw AND (_ePhase = E_DL_UdcPhase.eDose) AND (NOT _bFault), PT := tWeakTo); // 灯弱确认窗，IN 串原始判据与相位闸 / the weak lamp window with the raw verdict and the phase gate

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_UdcPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaulC := E_DL_UdcFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fI := 0.0; // 积分项清零 / clear the integral term
    fDoseAcc := 0.0; // 剂量清零 / clear the dose
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清剂量与积分（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_UdcFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_UdcPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    fDoseAcc := 0.0; // 作用域三：清剂量累计 / scope three, clear the dose accumulation
    _fI := 0.0; // 作用域三：清积分项 / scope three, clear the integral term
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖）/ segment 3, the configuration and input domain gates
_bInOk := (fIntensity = fIntensity) AND ((fIntensity - fIntensity) = (fIntensity - fIntensity)) AND (fIntensity >= 0.0); // 光强有限且非负 / the intensity is finite and non negative
_bCfgOk := (fDoseTarget > 0.0) AND (fDoseTarget = fDoseTarget) AND (kLamp >= 0.0) AND (kLamp <= 1.0) AND (kLamp = kLamp) AND (fKp > 0.0) AND (fKp = fKp) AND (fKi >= 0.0) AND (fKi = fKi) AND (fIntMin > 0.0) AND (fIntMin = fIntMin) AND (fOverTolPct > 0.0) AND (fOverTolPct = fOverTolPct) AND (tWeakTo > T#0S) AND (fDtS > 0.0) AND (fDtS = fDtS); // 组态参数域判定 / the configuration domain verdict
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 光强无效或组态非法 / a void intensity or an illegal configuration
    IF NOT _bFault THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_UdcFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_UdcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_UdcPhase.eIdle: // 空闲相：等运行电平 / the idle phase, waiting for the run level
    fDimPct := 0.0; // 灯关 / the lamp is off
    IF bEnable AND (NOT _bFault) AND bRun THEN // 运行电平受理 / the run level is accepted
        _fI := 0.0; // 积分项清零 / clear the integral term
        _ePhase := E_DL_UdcPhase.eDose; // 迁照射相 / migrate to the dose phase
    END_IF

E_DL_UdcPhase.eDose: // 照射相：闭环调光 + 剂量累计（退出条件 ≥2：达标 / 过冲 / 灯弱 / 失能 / 停运行，R98）/ the dose phase with at least two exit conditions
    IF NOT bEnable THEN // 失能 / disabled
        fDimPct := 0.0; // 灯关 / the lamp is off
        _ePhase := E_DL_UdcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF NOT bRun THEN // 曝晒窗关：调光归零、累计冻结保持（R191 显式声明）/ the window closed, the dimming zeroes and the dose freezes
        fDimPct := 0.0; // 灯关 / the lamp is off
        _fI := 0.0; // 积分项清零（防恢复时积分踢）/ clear the integral against a kick on resume
    ELSE // 曝晒中 / exposing
        IF _bInOk AND _bCfgOk THEN // 输入与组态合法 / the input and the config are legal
            _fRate := fIntensity * kLamp; // 剂量率 = 光强 × 老化补偿系数 / the dose rate, the intensity times the factor
            fDoseAcc := fDoseAcc + _fRate * fDtS; // 剂量累计 / accumulate the dose
            IF fDoseAcc > 1.0E9 THEN // 累计溢出保护（饱和口径，R63 反算）/ the overflow protection with the saturation basis
                fDoseAcc := 1.0E9; // 饱和到上限 / saturate at the ceiling
            END_IF
            _fTol := fDoseTarget * fOverTolPct / 100.0; // 过冲绝对容差，除子为常量一百 / the absolute tolerance with the constant divisor
            _fE := fDoseTarget - fDoseAcc; // 剩余剂量误差 / the remaining dose error
            _fUPre := fKp * _fE + _fI; // 限幅前调光输出 / the pre clamp dimming output
            IF NOT ((_fUPre >= 100.0) AND (_fE > 0.0)) THEN // 未沿误差方向饱和才积分（抗 windup）/ the integration is gated against the saturation direction
                _fI := _fI + fKi * _fE * fDtS; // 积分推进 / the integral step
            END_IF
            _fUPre := fKp * _fE + _fI; // 积分后重算 / recompute after the integral
            IF _fUPre < 0.0 THEN // 下限钳零 / clamp the floor to zero
                fDimPct := 0.0; // 输出归零 / the output is zeroed
            ELSIF _fUPre > 100.0 THEN // 上限钳百 / clamp the ceiling to one hundred
                fDimPct := 100.0; // 输出满幅 / the output is full
            ELSE // 域内 / inside the domain
                fDimPct := _fUPre; // 直接出口 / straight to the outlet
            END_IF
            _bWeakRaw := (fDimPct >= 99.0) AND (_fRate < fIntMin); // 满输出照度不足原始判据 / the raw weak lamp verdict
            IF fDoseAcc > fDoseTarget + _fTol THEN // 过冲超容差（优先归因，R190 独立成因）/ the overshoot takes the cause priority
                _bFault := TRUE; // 置故障锁存 / raise the fault latch
                _eFaulC := E_DL_UdcFault.eDoseOvershoot; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
                _ePhase := E_DL_UdcPhase.eFault; // 迁故障相 / migrate to the fault phase
            ELSIF tonWeak.Q THEN // 灯弱确认窗到 / the weak lamp window elapsed
                _bFault := TRUE; // 置故障锁存 / raise the fault latch
                _eFaulC := E_DL_UdcFault.eLampWeak; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
                _ePhase := E_DL_UdcPhase.eFault; // 迁故障相 / migrate to the fault phase
            ELSIF fDoseAcc >= fDoseTarget THEN // 剂量达标 / the dose target is reached
                _bDoneInt := TRUE; // 达标脉冲内部位置位（统一出口映射，R187）/ raise the internal done bit
                _ePhase := E_DL_UdcPhase.eDone; // 迁达标相 / migrate to the done phase
            END_IF
        ELSE // 输入或组态非法：灯关防御 / a void input or config, the lamp is off as a defence
            fDimPct := 0.0; // 灯关 / the lamp is off
        END_IF
    END_IF

E_DL_UdcPhase.eDone: // 达标相：灯关驻留，等运行撤或复位 / the done phase, the lamp is off until the run drops or a reset
    fDimPct := 0.0; // 灯关 / the lamp is off
    IF (NOT bEnable) OR (NOT bRun) THEN // 失能或运行撤 / disabled or the run dropped
        _ePhase := E_DL_UdcPhase.eIdle; // 回空闲相 / back to idle
    END_IF

E_DL_UdcPhase.eFault: // 故障相：灯关，成因锁存，等复位沿 / the fault phase, the lamp is off until the reset edge
    fDimPct := 0.0; // 灯关（安全侧）/ the lamp is off, the safe side
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_UdcPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_UdcFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_UdcPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口 / segment 5, the unified outlet
bDoseDone := _bDoneInt; // 达标脉冲映射本拍值 / map the done pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_UdcFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
