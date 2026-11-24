(*
  ==================================================================
  组件名 Component  : FB_DL_UltrasonicWeldCtrl
  分类   Category   : DL_Device
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 超声波焊接顺控。相位机 eIdle → eDown → eHold → eSonicOn →
                      eCool → eUp → eDone / eFault；能量积分用梯形法（E += (P +
                      Pprev)/2·dt）；超能量 / 欠能量双判据独立成因（R190）+ 超时
                      看门狗；输出 bSonicActive / bWeldDone / fEnergy。
  来源   Source     : t2-2-lbp
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；超声焊接能量 / 振幅 /
                      时间三模终点为通用工艺语义，clean-room 自研实现，未复制任何
                      闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / LREAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  同拍多窗说明（R100）：五个窗互斥 —— 每窗 IN 串「本相」闸，任一时刻只有一个窗
                      在计时；配比约束 tSonicTo > tWeld 在组态域闸内判故障
                      （看门狗窗必须覆盖目标窗）。
  边界 Boundary     :
                      一 本件只出焊接命令与能量结算，不驱动换能器电源、不控气缸
                         （属主边界）；
                      二 相级看门狗使能只用相驻留本身（R145）；
                      三 能量梯形积分仅在 eSonicOn 相执行；进入该相时能量清零
                         （单点入口赋值，防跨批残留）；
                      四 故障锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fAmplitudeCmd 恒在 [0, fAmpMax]；fEnergy 为最近一次焊接结算
                      能量 [焦]；bWeldDone 为单拍脉冲（R187 两段式）；
                      eFault 为锁存回放；ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 4 · 序号 18）
  ==================================================================
*)

TYPE E_DL_UwcPhase :
(
    eIdle    := 0,  // 空闲：等启动沿 / idle, waiting for the start edge
    eDown    := 10, // 下压：等到位反馈 / down, waiting for the position feedback
    eHold    := 20, // 保压：保压计时 / holding, the hold timing
    eSonicOn := 30, // 超声：能量积分与双判据 / sonic on, the energy integral with the twin verdicts
    eCool    := 40, // 冷却：冷却计时 / cooling, the cool timing
    eUp      := 50, // 回升：等原位反馈 / up, waiting for the home feedback
    eDone    := 60, // 完成：结算驻留 / done, the settlement holds
    eFault   := 90  // 故障：成因锁存，超声撤 / fault, the cause is latched with the sonic off
);
END_TYPE

TYPE E_DL_UwcFault :
(
    eNone         := 0, // 无成因 / no cause
    eEnergyHigh   := 1, // 能量超上限（故障级，与 bError 配对）/ the energy is over the ceiling, fault grade paired with bError
    eEnergyLow    := 2, // 焊接窗耗尽能量仍低于下限（故障级，与 bError 配对）/ the window expired with the energy below the floor, fault grade paired with bError
    eSonicTimeout := 3, // 超声相看门狗超时（故障级，与 bError 配对）/ the sonic phase watchdog timed out, fault grade paired with bError
    eDownTimeout  := 4, // 下压相超时（故障级，与 bError 配对）/ the down phase timed out, fault grade paired with bError
    eUpTimeout    := 5, // 回升相超时（故障级，与 bError 配对）/ the up phase timed out, fault grade paired with bError
    eSensorBad    := 6, // 功率非有限或组态非法（故障级，与 bError 配对）/ the power is non finite or the config illegal, fault grade paired with bError
    ePhaseBad     := 7  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_UltrasonicWeldCtrl
VAR_INPUT
    bEnable     : BOOL := TRUE;    // 使能，失能时停顺控回空闲 [-] / enable, the sequence stops when disabled
    bReset      : BOOL := FALSE;   // 复位上升沿清故障锁存 [-] / reset rising edge clears the fault latch
    bStart      : BOOL := FALSE;   // 焊接启动脉冲，上升沿受理 [-] / the weld start pulse, accepted on the rising edge
    bAbort      : BOOL := FALSE;   // 中止（电平），任何中间态撤超声回空闲 [-] / the abort level, any middle phase withdraws the sonic
    bPosDownFb  : BOOL := FALSE;   // 焊接位置到位反馈 [-] / the weld position feedback
    bPosUpFb    : BOOL := TRUE;    // 原位反馈 [-] / the home position feedback
    fPowerW     : LREAL := 0.0;    // 超声功率实测 [瓦] / the measured sonic power [watt]
    fAmpSet     : LREAL := 60.0;   // 振幅设定 [百分比]，域 0..100 / the amplitude setpoint [percent], domain zero to one hundred
    fAmpMax     : LREAL := 100.0;  // 振幅上限 [百分比] / the amplitude ceiling [percent]
    fEnergyMinJ : LREAL := 50.0;   // 能量下限 [焦] / the energy floor [joule]
    fEnergyTgtJ : LREAL := 200.0;  // 能量目标 [焦]，域 大于下限 / the energy target [joule], above the floor
    fEnergyMaxJ : LREAL := 300.0;  // 能量上限 [焦]，域 大于目标 / the energy ceiling [joule], above the target
    tHold       : TIME := T#500MS; // 保压时长 [毫秒] / the hold duration [millisecond]
    tWeld       : TIME := T#3S;    // 焊接目标窗 [毫秒] / the weld target window [millisecond]
    tSonicTo    : TIME := T#5S;    // 超声相看门狗窗 [毫秒]，域 大于 tWeld / the sonic watchdog window, above the weld window
    tCool       : TIME := T#1S;    // 冷却时长 [毫秒] / the cool duration [millisecond]
    tDownTo     : TIME := T#5S;    // 下压超时窗 [毫秒] / the down timeout window [millisecond]
    tUpTo       : TIME := T#5S;    // 回升超时窗 [毫秒] / the up timeout window [millisecond]
    fDtS        : LREAL := 0.01;   // 调用周期 [秒]，域 大于零 / the call period [second], domain above zero
END_VAR
VAR_OUTPUT
    bSonicActive  : BOOL := FALSE; // 超声激活命令（相位派生电平）[-] / the sonic active command, a phase derived level
    fAmplitudeCmd : LREAL := 0.0;  // 振幅命令输出 [百分比] / the amplitude command outlet [percent]
    bWeldDone     : BOOL := FALSE; // 焊接完成单拍脉冲 [-] / the weld done single shot pulse
    fEnergy       : LREAL := 0.0;  // 最近一次焊接结算能量 [焦] / the settled energy of the last weld [joule]
    ePhase        : E_DL_UwcPhase := E_DL_UwcPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault        : E_DL_UwcFault := E_DL_UwcFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError        : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStart  : R_TRIG; // 启动沿检测，段 0 无条件刷新 / start edge, refreshed unconditionally in segment zero
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonDown  : TON;    // 下压超时窗，段 0 无条件刷新 / the down timeout window, refreshed unconditionally
    tonHold  : TON;    // 保压计时窗，段 0 无条件刷新 / the hold timing window, refreshed unconditionally
    tonWeld  : TON;    // 焊接目标窗，段 0 无条件刷新 / the weld target window, refreshed unconditionally
    tonSonic : TON;    // 超声看门狗窗，段 0 无条件刷新 / the sonic watchdog window, refreshed unconditionally
    tonCool  : TON;    // 冷却计时窗，段 0 无条件刷新 / the cool timing window, refreshed unconditionally
    tonUp    : TON;    // 回升超时窗，段 0 无条件刷新 / the up timeout window, refreshed unconditionally
    _ePhase  : E_DL_UwcPhase := E_DL_UwcPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_UwcFault := E_DL_UwcFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bDoneInt: BOOL := FALSE; // 完成脉冲内部位，统一出口映射 / internal done bit, mapped at the unified outlet
    _bInOk   : BOOL := FALSE; // 功率有限 [-] / the power is finite
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _fPwPrev : LREAL := 0.0;  // 上拍功率快照 [瓦] / previous scan power snapshot [watt]
    _fEnergyW: LREAL := 0.0;  // 能量积分工作值 [焦] / the energy integral working value [joule]
    _fAmpUse : LREAL := 60.0;  // 钳定后的振幅 [百分比] / the clamped amplitude [percent]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸（FB50-1）/ segment 0, unconditional refresh, no instance call inside a branch
rtStart(CLK := bStart); // 启动沿 / the start edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonDown(IN := (_ePhase = E_DL_UwcPhase.eDown) AND (NOT _bFault), PT := tDownTo); // 下压超时窗 / the down timeout window
tonHold(IN := (_ePhase = E_DL_UwcPhase.eHold) AND (NOT _bFault), PT := tHold); // 保压计时窗 / the hold timing window
tonWeld(IN := (_ePhase = E_DL_UwcPhase.eSonicOn) AND (NOT _bFault), PT := tWeld); // 焊接目标窗 / the weld target window
tonSonic(IN := (_ePhase = E_DL_UwcPhase.eSonicOn) AND (NOT _bFault), PT := tSonicTo); // 超声看门狗窗 / the sonic watchdog window
tonCool(IN := (_ePhase = E_DL_UwcPhase.eCool) AND (NOT _bFault), PT := tCool); // 冷却计时窗 / the cool timing window
tonUp(IN := (_ePhase = E_DL_UwcPhase.eUp) AND (NOT _bFault), PT := tUpTo); // 回升超时窗 / the up timeout window

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_UwcPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaulC := E_DL_UwcFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fPwPrev := fPowerW; // 快照取当拍 / the snapshot takes this scan
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清能量工作值（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_UwcFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_UwcPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _fEnergyW := 0.0; // 作用域三：清能量工作值（结算出口 fEnergy 保持）/ scope three, the integral clears while the settlement holds
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖，含 R100 配比）/ segment 3, the configuration gate with the window pairing
_bInOk := (fPowerW = fPowerW) AND ((fPowerW - fPowerW) = (fPowerW - fPowerW)) AND (fPowerW >= 0.0); // 功率有限且非负 / the power is finite and non negative
_bCfgOk := (fAmpSet >= 0.0) AND (fAmpSet = fAmpSet) AND (fAmpMax > 0.0) AND (fAmpMax = fAmpMax) AND (fEnergyMinJ > 0.0) AND (fEnergyMinJ = fEnergyMinJ) AND (fEnergyTgtJ > fEnergyMinJ) AND (fEnergyTgtJ = fEnergyTgtJ) AND (fEnergyMaxJ > fEnergyTgtJ) AND (fEnergyMaxJ = fEnergyMaxJ) AND (tHold > T#0S) AND (tWeld > T#0S) AND (tSonicTo > tWeld) AND (tCool > T#0S) AND (tDownTo > T#0S) AND (tUpTo > T#0S) AND (fDtS > 0.0) AND (fDtS = fDtS); // 组态参数域判定（含 tSonicTo > tWeld 配比，R100）/ the configuration verdict with the pairing
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 功率无效或组态非法 / a void power or an illegal configuration
    IF NOT _bFault THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_UwcFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_UwcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF
END_IF
_fAmpUse := fAmpSet; // 振幅直通 / the amplitude passes through
IF _fAmpUse > fAmpMax THEN // 振幅上钳（R117 两级回退）/ clamp the amplitude high
    _fAmpUse := fAmpMax; // 钳到上限 / clamp to the ceiling
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_UwcPhase.eIdle: // 空闲相：等启动沿 / the idle phase, waiting for the start edge
    IF bEnable AND (NOT _bFault) AND (NOT bAbort) AND rtStart.Q THEN // 启动沿受理 / the start edge is accepted
        _fEnergyW := 0.0; // 能量工作值清零 / clear the energy integral
        _fPwPrev := 0.0; // 功率快照清零 / clear the power snapshot
        _ePhase := E_DL_UwcPhase.eDown; // 迁下压相 / migrate to the down phase
    END_IF

E_DL_UwcPhase.eDown: // 下压相：等到位反馈（退出条件 ≥2：到位 / 超时 / 中止 / 失能，R98）/ the down phase with at least two exit conditions
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_UwcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF bPosDownFb THEN // 到位 / the position is reached
        _ePhase := E_DL_UwcPhase.eHold; // 迁保压相 / migrate to the hold phase
    ELSIF tonDown.Q THEN // 下压超时 / the down phase timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_UwcFault.eDownTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_UwcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_UwcPhase.eHold: // 保压相：保压计时 / the hold phase, the hold timing
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_UwcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF tonHold.Q THEN // 保压时长已到 / the hold duration elapsed
        _fEnergyW := 0.0; // 能量积分入口清零（单点入口赋值，防跨批残留）/ the entry zeroing of the energy integral
        _fPwPrev := 0.0; // 功率快照入口清零 / the entry zeroing of the power snapshot
        _ePhase := E_DL_UwcPhase.eSonicOn; // 迁超声相 / migrate to the sonic phase
    END_IF

E_DL_UwcPhase.eSonicOn: // 超声相：梯形能量积分 + 双判据 + 看门狗 / the sonic phase, the trapezoid integral with the twin verdicts and the watchdog
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_UwcPhase.eIdle; // 回空闲相 / back to idle
    ELSE // 焊接中 / welding
        IF _bInOk THEN // 功率有限 / the power is finite
            _fEnergyW := _fEnergyW + (fPowerW + _fPwPrev) / 2.0 * fDtS; // 梯形法能量积分，除子无（乘法口径）/ the trapezoid energy integral
            _fPwPrev := fPowerW; // 功率快照推进 / advance the power snapshot
        END_IF
        fEnergy := _fEnergyW; // 能量出口实时跟随 / the energy outlet follows live
        IF _fEnergyW > fEnergyMaxJ THEN // 超能量判据（R190 独立成因）/ the over energy criterion, an independent cause
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_UwcFault.eEnergyHigh; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_UwcPhase.eFault; // 迁故障相 / migrate to the fault phase
        ELSIF tonSonic.Q THEN // 看门狗超时（覆盖目标窗的兜底，R100）/ the watchdog expired, the fallback over the target window
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_UwcFault.eSonicTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_UwcPhase.eFault; // 迁故障相 / migrate to the fault phase
        ELSIF tonWeld.Q THEN // 焊接目标窗耗尽 / the weld target window expired
            IF _fEnergyW < fEnergyMinJ THEN // 欠能量判据（R190 独立成因）/ the under energy criterion, an independent cause
                _bFault := TRUE; // 置故障锁存 / raise the fault latch
                _eFaulC := E_DL_UwcFault.eEnergyLow; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
                _ePhase := E_DL_UwcPhase.eFault; // 迁故障相 / migrate to the fault phase
            ELSE // 能量在窗内，按时间终点收焊 / the energy is inside the window, the time based close
                _ePhase := E_DL_UwcPhase.eCool; // 迁冷却相 / migrate to the cool phase
            END_IF
        ELSIF _fEnergyW >= fEnergyTgtJ THEN // 能量达标（优先终点）/ the energy target is reached, the primary end
            _ePhase := E_DL_UwcPhase.eCool; // 迁冷却相 / migrate to the cool phase
        END_IF
    END_IF

E_DL_UwcPhase.eCool: // 冷却相：冷却计时 / the cool phase, the cool timing
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_UwcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF tonCool.Q THEN // 冷却时长已到 / the cool duration elapsed
        _ePhase := E_DL_UwcPhase.eUp; // 迁回升相 / migrate to the up phase
    END_IF

E_DL_UwcPhase.eUp: // 回升相：等原位反馈（退出条件 ≥2：原位 / 超时 / 中止 / 失能，R98）/ the up phase with at least two exit conditions
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_UwcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF bPosUpFb THEN // 原位 / the home position is reached
        _bDoneInt := TRUE; // 完成脉冲内部位置位（统一出口映射，R187）/ raise the internal done bit
        _ePhase := E_DL_UwcPhase.eDone; // 迁完成相 / migrate to the done phase
    ELSIF tonUp.Q THEN // 回升超时 / the up phase timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_UwcFault.eUpTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_UwcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_UwcPhase.eDone: // 完成相：结算驻留，等复位或新启动 / the done phase, the settlement holds until reset or a new start
    IF (NOT bEnable) OR rtStart.Q THEN // 失能或新启动沿 / disabled or a new start edge
        _ePhase := E_DL_UwcPhase.eIdle; // 回空闲相 / back to idle
    END_IF

E_DL_UwcPhase.eFault: // 故障相：超声撤，成因锁存，等复位沿 / the fault phase, the sonic off until the reset edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_UwcPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_UwcFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_UwcPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜命令出口派生（互斥的结构性承载）/ segment 6, the command outlets, the structural carrier
bSonicActive := (_ePhase = E_DL_UwcPhase.eSonicOn) AND (NOT _bFault) AND bEnable AND (NOT bAbort); // 超声激活命令：仅超声相派生 / the sonic command, derived in the sonic phase only
IF bSonicActive THEN // 超声激活拍 / the sonic active scan
    fAmplitudeCmd := _fAmpUse; // 振幅命令出口 / the amplitude command outlet
ELSE // 非激活拍 / the inactive scan
    fAmplitudeCmd := 0.0; // 振幅归零（安全侧）/ the amplitude zeroes, the safe side
END_IF

// 段 7｜统一出口 / segment 7, the unified outlet
bWeldDone := _bDoneInt; // 完成脉冲映射本拍值 / map the done pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_UwcFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
