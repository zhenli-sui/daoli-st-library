(*
  ==================================================================
  组件名 Component  : FB_DL_MracAdaptiveCtrl
  分类   Category   : DL_Algo
  复杂度 Complexity  : 重
  版本   Version    : 1.0.0
  功能   Purpose    : 模型参考自适应控制器（MRAC）。一阶参考模型
                      dModel/dt = (fRefCmd − Model)/Tm；跟踪误差 e = Model −
                      YMeas 驱动可调增益 σ 修正更新：dKp/dt = γ·e·fRefCmd −
                      σ·Kp（防参数漂移），增益钳位 [fKmin, fKmax]；控制输出
                      fU = Kp·fRefCmd。欧拉离散，步长 fDtSec 由调用方给定。
                      与 FB_DL_RlsEstimator 参数辨识分工互引。
  来源   Source     : self（MRAC 公开控制理论）
  溯源   Origin     : MIT 规则 MRAC 与 σ 修正为公开控制理论语义，clean-room
                      自研实现，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FB_DL_RlsEstimator 分工——后者做递推参数辨识，
                      本件做参考模型驱动的在线增益自适应。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限/组态闸（自反双判据 + 域闸）：fDtSec ∉ (0,0.1]
                         或 Tm ≤ eps 或入参非有限 → bBad 置位（本库纪律②），
                         状态冻结、fU 安全侧零；
                      二 增益硬钳位 [fKmin, fKmax] 单点回夹（防自适应发散）；
                      三 复位沿：Model/Kp/输出全清（解除路径 = bReset 沿，
                         R188）；
                      四 首拍初始化（R310 真实使用）：Model 预置取当前测量
                         值（状态从测量起跳，防首拍误差尖峰）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 3 · 序号 11）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_MracAdaptiveCtrl
VAR_INPUT
    fRefCmd : LREAL := 0.0;  // 参考指令 [工程单位] / the reference command [engineering unit]
    fYMeas  : LREAL := 0.0;  // 被控量测量 [工程单位] / the plant measurement [engineering unit]
    fDtSec  : LREAL := 0.01; // 离散步长 [秒]，域 (0, 0.1] / the discrete step [second]
    fTmSec  : LREAL := 0.5;  // 参考模型时间常数 [秒]，域 > eps / the model time constant [second]
    fGamma  : LREAL := 0.5;  // 自适应增益 [1/(单位·秒)] / the adaptive gain
    fSigma  : LREAL := 0.01; // σ 修正系数 [1/秒]，防漂移 / the sigma modification, anti drift
    fKmin   : LREAL := -10.0; // 增益下钳位 [无量纲] / the gain clamp floor
    fKmax   : LREAL := 10.0;  // 增益上钳位 [无量纲] / the gain clamp ceiling
    bEnable : BOOL := FALSE;  // 使能，失能状态冻结输出零 [-] / the enable, disabling freezes and zeroes
    bReset  : BOOL := FALSE;  // 复位上升沿清状态 [-] / the reset rising edge clears the states
END_VAR
VAR_OUTPUT
    fU      : LREAL := 0.0; // 控制输出 [工程单位] / the control outlet [engineering unit]
    fModelY : LREAL := 0.0; // 参考模型输出 [工程单位] / the model outlet [engineering unit]
    fETrack : LREAL := 0.0; // 跟踪误差（Model − YMeas）[工程单位] / the tracking error [engineering unit]
    fKp     : LREAL := 0.0; // 可调增益实时值 [无量纲] / the adaptive gain live value
    bBad    : BOOL := FALSE; // 非有限/组态闸实时标志 [-] / the non finite or config gate flag
    bValid  : BOOL := FALSE; // 输出可用标志 [-] / the output usable flag
END_VAR
VAR CONSTANT
    DL_MRA_EPS   : LREAL := 1.0E-9;  // 时间常数下阈值 [秒] / the time constant threshold
    DL_MRA_DTMAX : LREAL := 0.1;     // 步长上界 [秒] / the step ceiling
    DL_MRA_EMAX  : LREAL := 1.0E6;   // 跟踪误差钳位（数值防溢出）[工程单位] / the tracking error clamp, numeric
    DL_MRA_KMAXABS : LREAL := 1.0E6; // 自适应增益上界绝对值（R59 补：防 +Inf 穿闸）[—] / the absolute bound on the adaptive gain
END_VAR
VAR
    _fModel : LREAL := 0.0; // 参考模型状态 [工程单位] / the reference model state
    _fKp    : LREAL := 0.0; // 可调增益状态 [无量纲] / the adaptive gain state
    _fE     : LREAL;        // 跟踪误差工作量（含钳位）[工程单位] / the tracking error work value, clamped
    _bFin   : BOOL;         // 入参有限工作量 [-] / the input finiteness work flag
    _bCfg   : BOOL;         // 组态域工作量 [-] / the config domain work flag
    _bInit  : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：模型起跳测量值）/ the first scan flag, real use
    rtReset : R_TRIG;        // 复位沿，段 0 无条件刷新 / the reset edge
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜复位沿作用域：全状态清（解除路径 = bReset 沿，R188）/ segment 1, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _fModel := 0.0; // 模型状态清 / clear the model state
    _fKp := 0.0; // 增益状态清 / clear the gain state
    fModelY := 0.0; // 模型输出清 / clear the model outlet
    fKp := 0.0; // 增益出口清 / clear the gain outlet
    fU := 0.0; // 控制输出清（安全侧）/ clear the control, the safe side
    bValid := FALSE; // 有效降假 / drop the valid
END_IF

// 段 2｜首拍初始化（R310 真实使用路径）：模型起跳当前测量值 / segment 2, the first scan init, the model jump to the measurement
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the flag
    _fModel := fYMeas; // 模型从测量起跳（防首拍误差尖峰）/ the model starts at the measurement
END_IF

// 段 3｜非有限与组态闸（边界一，实时标志非锁存）/ segment 3, the non finite and the config gate
_bFin := (fRefCmd = fRefCmd) AND ((fRefCmd - fRefCmd) = (fRefCmd - fRefCmd)) // 指令有限 / the command finite
    AND (fYMeas = fYMeas) AND ((fYMeas - fYMeas) = (fYMeas - fYMeas)) // 测量有限 / the measurement finite
    AND (fGamma = fGamma) AND ((fGamma - fGamma) = (fGamma - fGamma)) // 自适应增益有限 / the gain finite
    AND (fSigma = fSigma) AND ((fSigma - fSigma) = (fSigma - fSigma)) // σ 系数有限 / the sigma finite
    AND (fDtSec = fDtSec) AND ((fDtSec - fDtSec) = (fDtSec - fDtSec)) // 步长有限（R59 补）/ the step finite
    AND (fTmSec = fTmSec) AND ((fTmSec - fTmSec) = (fTmSec - fTmSec)) // 时间常数有限（R59 补）/ the time constant finite
    AND (fKmin = fKmin) AND (fKmax = fKmax) // 增益上下界有限（R59 补，防 +Inf 穿闸）/ the gain bounds finite
    AND (fKmin - fKmin = 0.0) AND (fKmax - fKmax = 0.0); // 界非无穷（R59 补）/ the bounds not infinite
_bCfg := (fDtSec > 0.0) AND (fDtSec <= DL_MRA_DTMAX) AND (fTmSec > DL_MRA_EPS) // 步长与时间常数域 / the step and the time constant domain
    AND (fKmin < fKmax) // 钳位序合理 / the clamp order sane
    AND (fKmax <= DL_MRA_KMAXABS); // 增益上界绝对值闸（R59 补）/ the absolute gain ceiling
bBad := (NOT _bFin) OR (NOT _bCfg); // 闸实时标志（R191 名实双出口）/ the gate flag

// 段 4｜自适应核心（使能且闸通过才推进；失能或闸拦状态冻结，边界一二）/ segment 4, the adaptive core
IF bEnable AND (NOT bBad) THEN // 有效推进窗 / the valid advance window
    _fModel := _fModel + (fDtSec * (fRefCmd - _fModel) / fTmSec); // 参考模型欧拉一步（除子 Tm 已闸）/ the model Euler step, divided by the gated Tm
    fModelY := _fModel; // 模型出口 / the model outlet
    _fE := _fModel - fYMeas; // 跟踪误差 / the tracking error
    IF _fE > DL_MRA_EMAX THEN // 误差上钳（数值防溢出）/ clamp the error up
        _fE := DL_MRA_EMAX; // 夹到上界 / clamp to the ceiling
    ELSIF _fE < -DL_MRA_EMAX THEN // 误差下钳 / clamp the error down
        _fE := -DL_MRA_EMAX; // 夹到下界 / clamp to the floor
    END_IF
    fETrack := _fE; // 误差出口（钳后口径）/ the error outlet, the clamped value
    _fKp := _fKp + (fDtSec * ((fGamma * _fE * fRefCmd) - (fSigma * _fKp))); // σ 修正增益更新 / the sigma modified gain update
    IF _fKp > fKmax THEN // 增益上钳（单点回夹）/ clamp the gain up
        _fKp := fKmax; // 夹到上界 / clamp to the ceiling
    ELSIF _fKp < fKmin THEN // 增益下钳 / clamp the gain down
        _fKp := fKmin; // 夹到下界 / clamp to the floor
    END_IF
    fKp := _fKp; // 增益出口 / the gain outlet
    fU := _fKp * fRefCmd; // 控制输出 / the control outlet
    bValid := TRUE; // 输出可用 / the output usable
ELSE // 失能或闸拦：输出安全侧零，状态冻结（边界一）/ disabled or gated, the safe zero and the frozen states
    fU := 0.0; // 控制输出安全零 / the safe zero
    fModelY := _fModel; // 模型出口保持冻结值 / the frozen model outlet
    fKp := _fKp; // 增益出口保持冻结值 / the frozen gain outlet
    fETrack := _fModel - fYMeas; // 误差出口保持观测（不推进）/ the observed error, not advanced
    IF NOT ((fETrack = fETrack) AND ((fETrack - fETrack) = (fETrack - fETrack))) THEN // 冻结出口非有限防护（R59 补）/ the frozen outlet finite guard
        fETrack := 0.0; // 非有限落安全零，不静默穿透 / non finite to the safe zero
    END_IF
    bValid := FALSE; // 可用降假 / drop the valid
END_IF
END_FUNCTION_BLOCK
