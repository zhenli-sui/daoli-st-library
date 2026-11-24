(*
  ==================================================================
  组件名 Component  : FB_DL_VacIonizerBalance
  分类   Category   : DL_Device
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 离子风机正负离子平衡监视。平衡偏差 = (iP - iN)/( |iP| + |iN| )
                      × 100；正偏 / 负偏双判据独立成因（R190）带迟滞防抖；衰减
                      时间估计：检测到步进突变（|iP| 突变 > fStepThresh）起计时，
                      偏差回带内锁存历时（由采样周期累加），时限 tDecayMax 由
                      TON 判 eDecaySlow；传感器非有限或双低电流判 eSensorBad。
  来源   Source     : t2-2-lbp（ESD 设备族）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；离子平衡度与衰减时间
                      为 ESD 公开评价语义（IEC 61340 概念域），clean-room 自研实现，
                      未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / LREAL 运算，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做平衡判级与衰减估计，不调风机风量、不做高压控制
                         （属主边界）；
                      二 判据方向性（R146）：正偏与负偏为同量纲双向异常，成因独立；
                      三 fDecayS 由采样周期累加估计（秒）；eDecaySlow 由 TON
                         （PT = tDecayMax）判定，两口径职责分离并在头注释声明；
                      四 成因锁存解除路径 = bReset 上升沿（唯一路径，头注释声明，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fBalDevPct 为平衡偏差百分比；bBalanced 迟滞输出；
                      eFault 为锁存回放；ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 3 · 序号 11）
  ==================================================================
*)

TYPE E_DL_VibPhase :
(
    eIdle  := 0,  // 未使能：监视停摆 / disabled, the watch is idle
    eRun   := 10, // 运行：逐拍判级 / running, graded every scan
    eDecay := 20, // 衰减测试：步进突变后计时中 / decay test, timing after a step
    eFault := 90  // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_VibFault :
(
    eNone      := 0, // 无成因 / no cause
    ePosSkew   := 1, // 正偏超限（故障级，与 bError 配对）/ the positive skew is over the limit, fault grade paired with bError
    eNegSkew   := 2, // 负偏超限（故障级，与 bError 配对）/ the negative skew is over the limit, fault grade paired with bError
    eDecaySlow := 3, // 衰减超时（故障级，与 bError 配对）/ the decay outlasted the window, fault grade paired with bError
    eSensorBad := 4, // 传感器非有限或双低电流（故障级，与 bError 配对）/ a sensor is non finite or both currents are void, fault grade paired with bError
    ePhaseBad  := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_VacIonizerBalance
VAR_INPUT
    bEnable     : BOOL := TRUE;    // 使能，失能时监视停摆 [-] / enable, the watch stops when disabled
    bReset      : BOOL := FALSE;   // 复位上升沿清全部成因锁存 [-] / reset rising edge clears every cause latch
    iP          : LREAL := 10.0;   // 正离子电流采样 [微安] / the positive ion current sample [microampere]
    iN          : LREAL := 10.0;   // 负离子电流采样 [微安] / the negative ion current sample [microampere]
    fBalLim     : LREAL := 10.0;   // 平衡限（偏差百分比带宽）[百分比]，域 大于零 / the balance limit band [percent], domain above zero
    fHystPct    : LREAL := 2.0;    // 迟滞带宽 [百分比]，域 0..平衡限 / the hysteresis band [percent], inside the limit
    fStepThresh : LREAL := 5.0;    // 衰减测试步进突变阈值 [微安] / the decay test step threshold [microampere]
    tDecayMax   : TIME := T#10S;   // 衰减时限 [毫秒]，域 大于零 / the decay time limit [millisecond], domain above zero
    fDtS        : LREAL := 0.1;    // 调用周期 [秒]，域 大于零 / the call period [second], domain above zero
END_VAR
VAR_OUTPUT
    fBalDevPct : LREAL := 0.0;  // 平衡偏差百分比 [百分比] / the balance deviation [percent]
    bBalanced  : BOOL := FALSE; // 平衡在带内（迟滞输出）[-] / the balance is inside the band, a hysteresis outlet
    fDecayS    : LREAL := 0.0;  // 最近一次衰减历时估计 [秒] / the last decay duration estimate [second]
    ePhase     : E_DL_VibPhase := E_DL_VibPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault     : E_DL_VibFault := E_DL_VibFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError     : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonDecay : TON;    // 衰减时限计时，段 0 无条件刷新 / decay limit timer, refreshed unconditionally in segment zero
    _ePhase  : E_DL_VibPhase := E_DL_VibPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_VibFault := E_DL_VibFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bInOk   : BOOL := FALSE; // 两电流输入均有限 [-] / both current inputs are finite
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bBad    : BOOL := FALSE; // 传感器无效锁存 [-] / the sensor bad latch
    _fDen    : LREAL := 0.0;  // 电流幅值和（除子）[微安] / the sum of current magnitudes, the divisor
    _fDev    : LREAL := 0.0;  // 平衡偏差工作值 [百分比] / the balance deviation working value [percent]
    _fIPrev  : LREAL := 0.0;  // 上拍正离子电流快照 [微安] / previous scan positive current snapshot [microampere]
    _fElapS  : LREAL := 0.0;  // 衰减历时累加 [秒] / the decay duration accumulator [second]
    _bPosL   : BOOL := FALSE; // 正偏迟滞锁存 [-] / the positive skew hysteresis latch
    _bNegL   : BOOL := FALSE; // 负偏迟滞锁存 [-] / the negative skew hysteresis latch
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸 / segment 0, unconditional refresh with the phase and fault gates on IN only
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonDecay(IN := (_ePhase = E_DL_VibPhase.eDecay) AND (NOT _bFault), PT := tDecayMax); // 衰减时限，IN 串衰减相闸与故障闸 / the decay limit with the phase and fault gates on IN

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_VibPhase.eRun; // 相位从运行起步 / the phase starts in run
    _eFaulC := E_DL_VibFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fIPrev := iP; // 快照取当拍 / the snapshot takes this scan
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清迟滞与历时（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_VibFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _bPosL := FALSE; // 作用域一：清正偏迟滞 / scope one, clear the positive latch
    _bNegL := FALSE; // 作用域一：清负偏迟滞 / scope one, clear the negative latch
    _bBad := FALSE; // 作用域一：清传感器无效锁存 / scope one, clear the sensor bad latch
    _ePhase := E_DL_VibPhase.eRun; // 作用域二：迁回运行相 / scope two, migrate back to run
    _fElapS := 0.0; // 作用域三：清衰减历时 / scope three, clear the decay duration
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖）/ segment 3, the configuration and input domain gates
_bInOk := (iP = iP) AND ((iP - iP) = (iP - iP)) AND (iN = iN) AND ((iN - iN) = (iN - iN)); // 两电流有限性 / finiteness of both currents
_bCfgOk := (fBalLim > 0.0) AND (fBalLim = fBalLim) AND (fHystPct >= 0.0) AND (fHystPct <= fBalLim) AND (fStepThresh > 0.0) AND (fStepThresh = fStepThresh) AND (tDecayMax > T#0S) AND (fDtS > 0.0) AND (fDtS = fDtS); // 组态参数域判定 / the configuration domain verdict
IF (NOT _bInOk) OR (NOT _bCfgOk) OR ((ABS(iP) < 1.0E-6) AND (ABS(iN) < 1.0E-6)) THEN // 非有限、组态非法或双低电流（未出风）/ non finite, illegal config or both currents void
    IF NOT _bBad THEN // 未锁存才置 / set only while unlatched
        _bBad := TRUE; // 置传感器无效锁存 / raise the sensor bad latch
    END_IF
END_IF

// 段 4｜本拍平衡偏差计算（组合量）/ segment 4, the per scan balance deviation
_fDen := ABS(iP) + ABS(iN); // 电流幅值和 / the sum of magnitudes
IF _fDen > 1.0E-6 THEN // 幅值和可用 / the sum is usable
    _fDev := (iP - iN) / _fDen * 100.0; // 平衡偏差百分比，除子已证超阈 / the balance deviation with a proven divisor
ELSE // 幅值和不可用 / the sum is not usable
    _fDev := 0.0; // 偏差记零 / the deviation is zeroed
END_IF
fBalDevPct := _fDev; // 偏差出口 / the deviation outlet

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_VibPhase.eIdle: // 未使能相 / the disabled phase
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_VibPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_VibPhase.eRun: // 运行相：逐拍判级 + 步进突变检测 / the run phase, grading and the step detection
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_VibPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF _bBad THEN // 传感器无效锁存优先 / the sensor bad latch takes priority
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_VibFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_VibPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSE // 正常判级 / the normal grading
        IF ABS(iP - _fIPrev) > fStepThresh THEN // 步进突变，起衰减测试 / a step change starts the decay test
            _fElapS := 0.0; // 历时清零 / clear the duration
            _ePhase := E_DL_VibPhase.eDecay; // 迁衰减相 / migrate to the decay phase
        END_IF
        IF _fDev > fBalLim THEN // 正偏进入判据 / the positive skew entry criterion
            _bPosL := TRUE; // 置正偏迟滞 / raise the positive latch
        ELSIF _fDev < fBalLim - fHystPct THEN // 正偏退出判据（迟滞收窄）/ the positive exit criterion
            _bPosL := FALSE; // 清正偏迟滞 / clear the positive latch
        END_IF
        IF _fDev < -fBalLim THEN // 负偏进入判据 / the negative skew entry criterion
            _bNegL := TRUE; // 置负偏迟滞 / raise the negative latch
        ELSIF _fDev > -fBalLim + fHystPct THEN // 负偏退出判据（迟滞收窄）/ the negative exit criterion
            _bNegL := FALSE; // 清负偏迟滞 / clear the negative latch
        END_IF
        bBalanced := (NOT _bPosL) AND (NOT _bNegL); // 平衡输出（迟滞派生）/ the balance outlet derived from the latches
        IF _bPosL THEN // 正偏故障（R190 独立成因）/ the positive skew fault, an independent cause
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_VibFault.ePosSkew; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_VibPhase.eFault; // 迁故障相 / migrate to the fault phase
        ELSIF _bNegL THEN // 负偏故障（R190 独立成因）/ the negative skew fault, an independent cause
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_VibFault.eNegSkew; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_VibPhase.eFault; // 迁故障相 / migrate to the fault phase
        END_IF
        _fIPrev := iP; // 快照推进 / advance the snapshot
    END_IF

E_DL_VibPhase.eDecay: // 衰减测试相：计时等待回带（退出条件 ≥2：回带 / 超时 / 失能，R98）/ the decay phase with at least two exit conditions
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_VibPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF _bBad THEN // 传感器无效 / the sensor went bad
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_VibFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_VibPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSE // 计时中 / timing
        _fElapS := _fElapS + fDtS; // 历时累加 / accumulate the duration
        IF ABS(_fDev) <= fBalLim - fHystPct THEN // 偏差回带内（收窄带口径）/ the deviation is back inside the narrowed band
            fDecayS := _fElapS; // 衰减历时锁存 / latch the decay duration
            _ePhase := E_DL_VibPhase.eRun; // 迁回运行相 / migrate back to run
        ELSIF tonDecay.Q THEN // 衰减超时 / the decay timed out
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_VibFault.eDecaySlow; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_VibPhase.eFault; // 迁故障相 / migrate to the fault phase
        END_IF
        _fIPrev := iP; // 快照推进 / advance the snapshot
    END_IF

E_DL_VibPhase.eFault: // 故障相：成因锁存，等待复位沿 / the fault phase, the cause is latched until the reset edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_VibPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_VibFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_VibPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜统一出口 / segment 6, the unified outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_VibFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
