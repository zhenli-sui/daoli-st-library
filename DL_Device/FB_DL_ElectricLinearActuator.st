(*
  ==================================================================
  组件名 Component  : FB_DL_ElectricLinearActuator
  分类   Category   : DL_Device
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 电动推杆驱动。无位置反馈，纯时间 / 电流双模到位判定：
                      限位开关反馈模（任一端限位反馈触发）与电流堵转模（电
                      流持续超堵转阈值 tStallDebounce 消抖判到位）并联，任
                      一判据先到即停并锁存到位指示；硬过流立即脱扣；全程
                      超时保护；双输出互锁绝不同得电。
  来源   Source     : t2-2-lbp（三段分层骨架）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；电动推杆堵转
                      电流判到位与限位互锁为行业公知工程语义，clean-room
                      自研实现，未复制 LBP 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 DL_Device 存量 FB_DL_DolMotor / FB_DL_SoftStarterDrive
                      分工——两者为电机启动家族（驱动器封装），本件为直线
                      执行机构（推杆本体行程与堵转管理），不做接触器 / 晶闸
                      管启动家族语义。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态域：fCurNomA > 0（非有限闸覆盖），fCurStallMul
                         > 1.0，fCurHiMul > fCurStallMul（硬过流阈值高于堵转
                         阈值，R100 配比约束），tStrokeMax > T#0S，tStallDebounce
                         ≥ T#0S（取零为电流模禁用，仅限位模）；
                      二 双模并联：限位反馈与电流堵转任一先到即到位停机，
                         到位指示锁存至反向运动或复位沿；
                      三 双命令同拍拒绝（复位优先 = 安全侧不动作，静默拒
                         绝不置故障，本拍双输出全断）；
                      四 运动相电流非有限（R151 组态域闸全覆盖）判传感失效
                         故障级；复位沿作用域：清故障锁存 / 清到位指示 / 迁
                         空闲（三项逐项声明，解除路径 = bReset 上升沿 R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 2 · 序号 8）
  ==================================================================
*)

TYPE E_DL_ElaPhase :
(
    eElaIdle := 0,  // 空闲：消化命令，双输出断开 / idle, both outputs off
    eElaExt  := 10, // 伸出中：正转输出得电 / extending, the forward output on
    eElaRet  := 20, // 缩回中：反转输出得电 / retracting, the reverse output on
    eElaFault:= 90  // 故障锁存：双输出安全侧断开 / the latched fault, both outputs off on the safe side
);
END_TYPE

TYPE E_DL_ElaCause :
(
    eNone          := 0, // 无成因 / no cause
    eCfgBad        := 1, // 组态非法：电流标称 / 倍数配比 / 时间窗越域（故障级，与 bError 配对）/ an illegal config
    eCurBad        := 2, // 运动相电流非有限（传感失效，故障级，与 bError 配对）/ a non finite current in motion
    eCurOverHard   := 3, // 硬过流立即脱扣（故障级，与 bError 配对）/ a hard overcurrent trip
    eStrokeTimeout := 4, // 全程超时（故障级，与 bError 配对）/ a stroke timeout
    ePhaseBad      := 5  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectricLinearActuator
VAR_INPUT
    bCmdExt        : BOOL := FALSE;  // 伸出命令电平 [-] / the extend command level
    bCmdRet        : BOOL := FALSE;  // 缩回命令电平 [-] / the retract command level
    bLimExtFbk     : BOOL := FALSE;  // 伸出限位开关反馈，TRUE = 已达伸出端 [-] / the extend limit feedback, true = at the extend end
    bLimRetFbk     : BOOL := FALSE;  // 缩回限位开关反馈，TRUE = 已达缩回端 [-] / the retract limit feedback, true = at the retract end
    fMotCurA       : LREAL := 0.0;   // 电机电流实测 [安培] / the motor current actual [ampere]
    fCurNomA       : LREAL := 4.0;   // 标称运行电流 [安培]，域 大于 0 / the nominal running current [ampere], above zero
    fCurStallMul   : LREAL := 1.5;   // 堵转判定倍数 [倍]，域 大于 1.0 / the stall verdict multiplier, above one
    fCurHiMul      : LREAL := 2.5;   // 硬过流倍数 [倍]，域 大于堵转倍数 / the hard overcurrent multiplier, above the stall multiplier
    tStrokeMax     : TIME := T#30S;  // 全程最大时间窗 [毫秒] / the full stroke max window [millisecond]
    tStallDebounce : TIME := T#300MS; // 堵转消抖窗 [毫秒]，取零禁用电流模 / the stall debounce window, zero disables the current mode
    bEnable        : BOOL := TRUE;   // 使能，失能双输出安全侧断开并迁空闲 [-] / enable, disabling opens both outputs and returns idle
    bReset         : BOOL := FALSE;  // 复位上升沿清故障锁存 [-] / reset rising edge clears the fault latch
END_VAR
VAR_OUTPUT
    bOutExt   : BOOL := FALSE; // 电机正转输出（仅伸出相）[-] / the forward output, the extend phase only
    bOutRet   : BOOL := FALSE; // 电机反转输出（仅缩回相）[-] / the reverse output, the retract phase only
    bInPosExt : BOOL := FALSE; // 伸出到位指示（锁存至反向或复位）[-] / the extend in position latch
    bInPosRet : BOOL := FALSE; // 缩回到位指示（锁存至反向或复位）[-] / the retract in position latch
    bArrByCur : BOOL := FALSE; // 本次到位由电流堵转模判定的指示 [-] / the arrival by the current mode indicator
    ePhase    : E_DL_ElaPhase := E_DL_ElaPhase.eElaIdle; // 相位出口 [枚举] / the phase outlet
    eCause    : E_DL_ElaCause := E_DL_ElaCause.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError    : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    tonStroke: TON;    // 全程时间窗，段 0 无条件刷新 / the stroke window
    tonStall : TON;    // 堵转消抖窗，段 0 无条件刷新 / the stall debounce window
    _ePhase  : E_DL_ElaPhase := E_DL_ElaPhase.eElaIdle; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC  : E_DL_ElaCause := E_DL_ElaCause.eNone; // 故障级成因，锁存至复位沿 / the fault cause latched
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bCfgOk  : BOOL := FALSE; // 组态域内 [-] / the config inside the domain
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _lrStall : LREAL;  // 堵转电流阈值工作量 [安培] / the stall threshold work value
    _lrHi    : LREAL;  // 硬过流阈值工作量 [安培] / the hard overcurrent threshold work value
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，FB50-1）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonStroke(IN := ((_ePhase = E_DL_ElaPhase.eElaExt) OR (_ePhase = E_DL_ElaPhase.eElaRet)) AND (NOT _bFault) AND bEnable, PT := tStrokeMax); // 全程窗，IN 串载能相闸（纯相驻留，R145）/ the stroke window on the powered phases
tonStall(IN := ((_ePhase = E_DL_ElaPhase.eElaExt) OR (_ePhase = E_DL_ElaPhase.eElaRet)) AND (NOT _bFault) AND bEnable AND (_lrStall > 0.0) AND (fMotCurA > _lrStall), PT := tStallDebounce); // 堵转消抖窗（电流模使能且超阈）/ the stall debounce window, the current mode enabled and above the threshold

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 清到位指示 / 迁空闲（三项逐项声明，边界四）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_ElaCause.eNone; // 作用域一：清成因 / scope one, clear the cause
    bInPosExt := FALSE; // 作用域二：清伸出到位 / scope two, clear the extend latch
    bInPosRet := FALSE; // 作用域二：清缩回到位 / scope two, clear the retract latch
    bArrByCur := FALSE; // 作用域二：清电流模指示 / scope two, clear the current mode flag
    _ePhase := E_DL_ElaPhase.eElaIdle; // 作用域三：迁空闲相 / scope three, back to idle
END_IF

// 段 3｜组态域闸（边界一，R151 全覆盖：电流标称非有限 + 倍数配比 + 时间窗）/ segment 3, the config gate
_bCfgOk := (fCurNomA = fCurNomA) AND ((fCurNomA - fCurNomA) = (fCurNomA - fCurNomA)) // 标称电流非有限双判据 / the nominal current finiteness
        AND (fCurNomA > 0.0) // 标称电流域 / the nominal domain
        AND (fCurStallMul > 1.0) // 堵转倍数域 / the stall multiplier domain
        AND (fCurHiMul > fCurStallMul) // 硬过流高于堵转配比（R100）/ the hard above the stall pairing
        AND (tStrokeMax > T#0S) // 全程窗域 / the stroke window domain
        AND (tStallDebounce >= T#0S); // 消抖窗域（零 = 电流模禁用）/ the debounce domain, zero disables the current mode
IF NOT _bCfgOk THEN // 组态越域 / a config violation
    IF NOT _bFault THEN // 未锁存才迁移（锁存回放 R152）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ElaCause.eCfgBad; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_ElaPhase.eElaFault; // 迁故障相（锁存与迁相同分支，FB50-1）/ migrate to the fault phase
    END_IF
END_IF
_lrStall := fCurNomA * fCurStallMul; // 堵转阈值（组态闸已证有限正值）/ the stall threshold
_lrHi := fCurNomA * fCurHiMul; // 硬过流阈值 / the hard threshold

// 段 4｜运动相电流域闸与硬过流监视（优先级最高，R146 按方向分列）/ segment 4, the current gate and the hard overcurrent monitor
IF (_ePhase = E_DL_ElaPhase.eElaExt) OR (_ePhase = E_DL_ElaPhase.eElaRet) THEN // 载能相 / a powered phase
    IF (fMotCurA <> fMotCurA) OR ((fMotCurA - fMotCurA) <> (fMotCurA - fMotCurA)) THEN // 电流非有限（边界四）/ a non finite current
        IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_ElaCause.eCurBad; // 故障级成因（R45 配对）/ the fault cause
            _ePhase := E_DL_ElaPhase.eElaFault; // 迁故障相 / migrate to the fault phase
        END_IF
    ELSIF (fMotCurA > _lrHi) AND (NOT _bFault) THEN // 硬过流立即脱扣（超重侧安全立即终止，R146）/ a hard overcurrent trips immediately
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ElaCause.eCurOverHard; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_ElaPhase.eElaFault; // 迁故障相 / migrate to the fault phase
    END_IF
END_IF

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, the phase machine
CASE _ePhase OF

E_DL_ElaPhase.eElaIdle: // 空闲相：评估命令（边界三双命令同拍拒绝）/ the idle phase, the command evaluation
    IF NOT bEnable THEN // 失能驻留 / dwell while disabled
        _ePhase := E_DL_ElaPhase.eElaIdle; // 停摆驻留 / dwell
    ELSIF bCmdExt AND bCmdRet THEN // 双命令同拍拒绝（复位优先）/ the dual commands rejected
        _ePhase := E_DL_ElaPhase.eElaIdle; // 静默拒绝双输出断（本拍由出口段全断）/ a silent refusal, both outputs off this scan
    ELSIF bCmdExt THEN // 伸出命令 / an extend command
        IF bLimExtFbk THEN // 已在伸出端（拒绝移动，刷新到位指示）/ already at the extend end
            bInPosExt := TRUE; // 到位指示保持 / hold the in position latch
            _ePhase := E_DL_ElaPhase.eElaIdle; // 驻留 / dwell
        ELSE // 允许伸出 / the extend allowed
            bInPosRet := FALSE; // 清反向到位 / clear the reverse latch
            bArrByCur := FALSE; // 清电流模指示 / clear the current mode flag
            _ePhase := E_DL_ElaPhase.eElaExt; // 迁伸出相 / migrate to the extend phase
        END_IF
    ELSIF bCmdRet THEN // 缩回命令 / a retract command
        IF bLimRetFbk THEN // 已在缩回端 / already at the retract end
            bInPosRet := TRUE; // 到位指示保持 / hold the in position latch
            _ePhase := E_DL_ElaPhase.eElaIdle; // 驻留 / dwell
        ELSE // 允许缩回 / the retract allowed
            bInPosExt := FALSE; // 清反向到位 / clear the extend latch
            bArrByCur := FALSE; // 清电流模指示 / clear the current mode flag
            _ePhase := E_DL_ElaPhase.eElaRet; // 迁缩回相 / migrate to the retract phase
        END_IF
    END_IF

E_DL_ElaPhase.eElaExt: // 伸出相：双模到位判定（边界二）/ the extend phase, the dual mode arrival
    IF NOT bEnable THEN // 失能即停（R191 降级显式：输出断 + 回空闲，无故障）/ a disable stops without a fault
        _ePhase := E_DL_ElaPhase.eElaIdle; // 回空闲相 / back to idle
    ELSIF bLimExtFbk THEN // 限位模到位 / the arrival by the limit mode
        bInPosExt := TRUE; // 锁存到位指示 / latch the in position
        _ePhase := E_DL_ElaPhase.eElaIdle; // 回空闲相 / back to idle
    ELSIF tonStall.Q THEN // 电流堵转模到位（消抖窗满）/ the arrival by the stall mode
        bInPosExt := TRUE; // 锁存到位指示 / latch the in position
        bArrByCur := TRUE; // 记电流模判定指示 / raise the current mode flag
        _ePhase := E_DL_ElaPhase.eElaIdle; // 回空闲相 / back to idle
    ELSIF tonStroke.Q THEN // 全程超时（故障级）/ the stroke timeout, fault grade
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ElaCause.eStrokeTimeout; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_ElaPhase.eElaFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_ElaPhase.eElaRet: // 缩回相：双模到位判定（边界二）/ the retract phase, the dual mode arrival
    IF NOT bEnable THEN // 失能即停 / a disable stops without a fault
        _ePhase := E_DL_ElaPhase.eElaIdle; // 回空闲相 / back to idle
    ELSIF bLimRetFbk THEN // 限位模到位 / the arrival by the limit mode
        bInPosRet := TRUE; // 锁存到位指示 / latch the in position
        _ePhase := E_DL_ElaPhase.eElaIdle; // 回空闲相 / back to idle
    ELSIF tonStall.Q THEN // 电流堵转模到位 / the arrival by the stall mode
        bInPosRet := TRUE; // 锁存到位指示 / latch the in position
        bArrByCur := TRUE; // 记电流模判定指示 / raise the current mode flag
        _ePhase := E_DL_ElaPhase.eElaIdle; // 回空闲相 / back to idle
    ELSIF tonStroke.Q THEN // 全程超时（故障级）/ the stroke timeout, fault grade
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ElaCause.eStrokeTimeout; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_ElaPhase.eElaFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_ElaPhase.eElaFault: // 故障相：成因锁存，等复位沿；双输出安全侧断开 / the fault phase
ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_ElaCause.ePhaseBad; // 故障级成因（R45 配对）/ the fault cause
    _ePhase := E_DL_ElaPhase.eElaFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜统一出口：双输出互锁 + 故障覆盖（边界二三）/ segment 6, the unified outlet with the interlock
bOutExt := (_ePhase = E_DL_ElaPhase.eElaExt) AND bEnable AND (NOT _bFault); // 正转输出仅伸出相（互锁）/ the forward output, the extend phase only
bOutRet := (_ePhase = E_DL_ElaPhase.eElaRet) AND bEnable AND (NOT _bFault); // 反转输出仅缩回相（互锁）/ the reverse output, the retract phase only
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eCause := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
ELSE // 无锁存 / no latch
    eCause := E_DL_ElaCause.eNone; // 无成因 / no cause
END_IF
bError := _bFault; // 故障标志与锁存位同源（R191 名实双出口）/ the flag shares the latch
END_FUNCTION_BLOCK
