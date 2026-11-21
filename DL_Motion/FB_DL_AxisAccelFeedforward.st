(*
  ==================================================================
  组件名 Component  : FB_DL_AxisAccelFeedforward
  分类   Category   : DL_Motion
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.1
  功能   Purpose    : 轴加速度前馈注入。前馈叠加值 = Ka·aCmd + Kv·fVelAct，经一阶
                      低通平滑（滤波时间常数 fTauS）防抖后输出；bEnable 为假时
                      输出冻结保持并显式声明；参数（增益为负、周期非正、增益非
                      有限）一律回钳或判无效。
  来源   Source     : t1-6-plcopen
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；加速度前馈偏置为公开
                      运动控制结构（规划加速度 × 折算增益），clean-room 自研实现，
                      未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL 运算，无私有库、无幂运算符、无定时器实例）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只算前馈叠加值，不做限幅策略、不做轴使能仲裁（属主边界）；
                      二 bEnabled = FALSE 时输出冻结保持末值（R191 显式声明）；
                      三 输入非有限时输出安全侧归零并冻结滤波保持量（R127 常量安全侧）；
                      四 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fFfOut 在有效拍为滤后前馈值；bEnabled 为本拍前馈有效指示；
                      eFault 为锁存回放（eCfgBad 组态非法 / eInputBad 本拍输入非有限）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 2 · 序号 9）
    2026-11-21  v1.0.1  R57 返修：有效拍内补 eInputBad 信息级成因恢复撤销（对齐 TwoDofPid 段 10 范式）
  ==================================================================
*)

TYPE E_DL_AffFault :
(
    eNone     := 0, // 无成因 / no cause
    eCfgBad   := 1, // 组态非法：增益或周期越域（故障级，与 bError 配对）/ illegal config, gain or period out of domain
    eInputBad := 2  // 本拍指令加速度或实际速度非有限（信息级，输出归零）/ the command acceleration or the actual velocity is non finite this scan, the outlet is zeroed
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisAccelFeedforward
VAR_INPUT
    bEnable : BOOL := TRUE;   // 前馈使能，假时输出冻结保持 [-] / feedforward enable, false freezes the outlet
    bReset  : BOOL := FALSE;  // 复位上升沿清故障锁存与滤波保持 [-] / reset rising edge clears the fault latch and the filter holder
    aCmd    : LREAL := 0.0;   // 规划指令加速度 [单位每平方秒] / planned command acceleration [unit per square second]
    fVelAct : LREAL := 0.0;   // 实际速度 [单位每秒] / actual velocity [unit per second]
    fKa     : LREAL := 0.0;   // 加速度前馈增益（负值回钳零）[前馈每单位加速度] / acceleration feedforward gain, negatives clamp to zero [feedforward per unit acceleration]
    fKv     : LREAL := 0.0;   // 速度前馈增益（负值回钳零）[前馈每单位速度] / velocity feedforward gain, negatives clamp to zero [feedforward per unit velocity]
    fTauS   : LREAL := 0.02;  // 低通滤波时间常数 [秒]，0 = 直通 / low pass time constant [second], zero is a passthrough
    fDtS    : LREAL := 0.01;  // 调用周期 [秒]，域 大于零 / call period [second], domain above zero
END_VAR
VAR_OUTPUT
    fFfOut  : LREAL := 0.0;  // 前馈叠加值出口 [前馈单位] / the feedforward outlet [feedforward unit]
    bEnabled: BOOL := FALSE; // 本拍前馈有效指示 [-] / the feedforward valid indicator this scan
    bInvalid: BOOL := FALSE; // 本拍输出无效（归零或冻结）[-] / the outlet is void this scan
    eFault  : E_DL_AffFault := E_DL_AffFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError  : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    _eFaulC : E_DL_AffFault := E_DL_AffFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bInOk  : BOOL := FALSE; // 本拍两输入均有限 [-] / both inputs are finite this scan
    _fKaUse : LREAL := 0.0;  // 钳定后的加速度增益 [前馈每单位加速度] / the clamped acceleration gain
    _fKvUse : LREAL := 0.0;  // 钳定后的速度增益 [前馈每单位速度] / the clamped velocity gain
    _fRaw   : LREAL := 0.0;  // 滤波前前馈值 [前馈单位] / the pre filter feedforward
    _fW     : LREAL := 0.0;  // 一阶低通权 [无量纲] / the first order weight
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detector
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eFaulC := E_DL_AffFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
END_IF

// 段 2｜复位沿作用域：清锁存 / 清滤波保持量（两项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_AffFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    fFfOut := 0.0; // 作用域二：出口归零 / scope two, the outlet is zeroed
END_IF

// 段 3｜组态域闸与参数回钳（R117 两级回退）/ segment 3, the configuration gate and the parameter clamps
_fKaUse := fKa; // 增益直通 / the gain passes through
_fKvUse := fKv; // 增益直通 / the gain passes through
IF (fKa <> fKa) OR ((fKa - fKa) <> (fKa - fKa)) OR (fKv <> fKv) OR ((fKv - fKv) <> (fKv - fKv)) OR (fDtS <= 0.0) OR (fDtS <> fDtS) OR (fTauS < 0.0) OR (fTauS <> fTauS) THEN // 增益或时间参数非有限 / a gain or a time parameter is non finite
    IF NOT _bFault THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_AffFault.eCfgBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    END_IF
END_IF
IF _fKaUse < 0.0 THEN // 加速度增益负值回钳零（一级回默认，R117）/ a negative gain clamps to the default zero
    _fKaUse := 0.0; // 钳到零 / clamp to zero
END_IF
IF _fKvUse < 0.0 THEN // 速度增益负值回钳零 / a negative gain clamps to zero
    _fKvUse := 0.0; // 钳到零 / clamp to zero
END_IF

// 段 4｜输入有限性闸 / segment 4, the input finiteness gate
_bInOk := (aCmd = aCmd) AND ((aCmd - aCmd) = (aCmd - aCmd)) AND (fVelAct = fVelAct) AND ((fVelAct - fVelAct) = (fVelAct - fVelAct)); // 两输入有限性 / finiteness of both inputs

// 段 5｜前馈计算与低通平滑 / segment 5, the feedforward computation and the low pass
IF (NOT _bInOk) OR _bFault OR (NOT bEnable) THEN // 非有限、故障或未使能 / non finite, faulted or disabled
    IF (NOT _bInOk) AND (NOT _bFault) THEN // 输入缺陷才记信息级成因（故障锁存优先回放，不覆盖故障码）/ only an input defect records the informational cause, never over a fault latch
        _eFaulC := E_DL_AffFault.eInputBad; // 信息级成因 / the informational cause
    END_IF
    bEnabled := FALSE; // 前馈无效指示 / the feedforward is not valid
    IF NOT bEnable THEN // 失能拍：冻结保持末值（R191 显式声明）/ the disabled scan holds the last value frozen
        bInvalid := FALSE; // 失能保持不算无效 / a disable is not an invalidity
    ELSE // 非有限或故障拍：输出安全侧归零（R127 常量）/ a non finite or faulted scan zeroes the outlet
        fFfOut := 0.0; // 输出归零 / the outlet is zeroed
        bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    END_IF
ELSE // 有效拍 / the valid scan
    _fRaw := _fKaUse * aCmd + _fKvUse * fVelAct; // 前馈叠加原始值 / the raw feedforward composition
    IF fTauS > 0.0 THEN // 低通开启 / the low pass is on
        _fW := fDtS / (fDtS + fTauS); // 一阶低通权，除子为周期加时间常数已证大于零 / the first order weight with a proven divisor
        fFfOut := fFfOut + _fW * (_fRaw - fFfOut); // 低通推进（出口即保持量）/ advance the low pass, the outlet is the holder
    ELSE // 直通口径 / the passthrough
        fFfOut := _fRaw; // 原始值直出 / the raw value passes out
    END_IF
    bEnabled := TRUE; // 前馈有效指示 / the feedforward is valid
    bInvalid := FALSE; // 无效标志为假 / the invalid flag is false
    IF (_eFaulC = E_DL_AffFault.eInputBad) AND (NOT _bFault) THEN // 输入已恢复 / the input has recovered
        _eFaulC := E_DL_AffFault.eNone; // 信息级成因随恢复撤销（v1.0.1 返修，对齐 TwoDofPid 段 10 范式）/ the informational cause is revoked on recovery (v1.0.1 fix)
    END_IF
END_IF

// 段 6｜统一出口 / segment 6, the unified outlet
eFault := _eFaulC; // 成因出口锁存回放 / the cause outlet replayed from the latch
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
