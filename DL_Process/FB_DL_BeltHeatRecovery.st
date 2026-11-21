(*
  ==================================================================
  组件名 Component  : FB_DL_BeltHeatRecovery
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 转轮热回收与输送联锁。按「转轮先启、输送后行、停输后吹扫」
                      的时序编排输送允许信号：转轮运行命令与反馈、过滤网状态、
                      火警联锁、防霜限温四条判据共同决定输送允许；停输后转轮
                      继续运行 tStopDelay 完成吹扫再停。同时按进排风温差算热回收
                      效率并给出效率达标标志。
  溯源   Origin     : 转轮热回收联锁为通用暖通时序语义；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-hvac），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / REAL 运算，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  同拍双窗配比约束（R100）：tStopDelay 必须大于等于 tStartDelay，保证吹扫窗
                      不短于启动窗；两窗职责分离：启动窗等转轮反馈，吹扫窗保
                      转轮续转，任一窗不得兼作另一窗用途。
  边界 Boundary     :
                      一 本件只出输送允许与转轮命令，不直接驱动风机变频器（属主边界）；
                      二 火警联锁优先级最高：撤转轮命令 + 撤输送允许 + 锁存至复位沿；
                      三 防霜判据成立时撤输送允许但保留转轮运行（防冻需转轮换热）；
                      四 过滤网异常撤输送允许但保留转轮运行（降级运行并置成因）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      bConvPermit 仅在运行相且转轮反馈到位、无火警、过滤网正常、
                      未触发防霜时为真（挂状态量，非单拍标志）；
                      fEffPct 在进排风温差不足 fMinDeltaTC 时保持上拍值并置 bEffOk 为假；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 3 · 序号 14）
  ==================================================================
*)

TYPE E_DL_BhrState :
(
    eIdle      := 0,    // 空闲：转轮停、输送禁行 / idle, the wheel is stopped and the conveyor is inhibited
    eStartWait := 10,   // 启动等反馈：等转轮运行反馈与启动延时 / waiting for the wheel feedback and the start delay
    eRun       := 20,   // 运行：输送允许 / running, the conveyor is permitted
    ePurge     := 30,   // 吹扫：停输后转轮续转 / purge, the wheel keeps running after the conveyor stops
    eFault     := 90    // 故障：火警或组态非法锁存 / fault, fire alarm or illegal configuration latched
);
END_TYPE

TYPE E_DL_BhrCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：时间窗配比反置或阈值越域（故障级，与 bError 配对）/ illegal config, window ratio inverted or a threshold out of domain
    eFireAlarm  := 2,   // 火警联锁动作（故障级，与 bError 配对，锁存至复位沿）/ fire alarm interlock tripped, a fault latched until the reset edge
    eFrost      := 3,   // 防霜动作，撤输送允许（信息级）/ frost protection tripped and the conveyor was inhibited, informational
    eFilterBad  := 4,   // 过滤网异常，撤输送允许（信息级）/ filter fault inhibited the conveyor, informational
    eNoWheelFb  := 5,   // 转轮反馈缺失，输送不放开（信息级）/ the wheel feedback is missing so the conveyor stays inhibited, informational
    eEffInvalid := 6    // 进排风温差不足，效率不更新（信息级）/ the temperature difference is too small and the efficiency holds, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_BeltHeatRecovery
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时全部命令撤除 [-] / enable, all commands are withdrawn when disabled
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存（火警须已消失）/ reset rising edge clears the fault latch, the fire alarm must be cleared first
    bConvRunCmd  : BOOL := FALSE;            // 输送运行请求（电平）[-] / conveyor run request, a level
    bWheelRunFb  : BOOL := FALSE;            // 转轮运行反馈 [-] / wheel running feedback
    bFilterOk    : BOOL := FALSE;            // 过滤网正常 [-] / filter healthy
    bFireAlarm   : BOOL := FALSE;            // 火警联锁源 [-] / fire alarm interlock source
    fExhaustC    : REAL := 20.0;             // 排风温度 [摄氏度] / exhaust air temperature [degree Celsius]
    fSupplyC     : REAL := 20.0;             // 送风温度（转轮后）[摄氏度] / supply air temperature after the wheel [degree Celsius]
    fFreshC      : REAL := 10.0;             // 新风温度（转轮前）[摄氏度] / fresh air temperature before the wheel [degree Celsius]
    fFrostLimitC : REAL := -5.0;             // 防霜限温 [摄氏度]，域 -60..10 / frost protection limit [degree Celsius], domain minus sixty to ten
    fMinDeltaTC  : REAL := 5.0;              // 效率计算的进排风最小温差 [开尔文]，域 大于零 / minimum exhaust to fresh difference for the efficiency calculation [Kelvin], domain above zero
    fEffMinPct   : REAL := 50.0;             // 效率达标阈 [百分比]，域 0..100 / efficiency pass threshold [percent], domain 0 to 100
    tStartDelay  : TIME := T#5S;             // 启动延时（转轮先启）[毫秒] / start delay so the wheel leads [millisecond]
    tStopDelay   : TIME := T#30S;            // 吹扫延时（输送后停）[毫秒]，须不短于启动延时 / purge delay so the wheel lags [millisecond], not shorter than the start delay
END_VAR
VAR_OUTPUT
    bConvPermit  : BOOL := FALSE;            // 输送允许 [-] / conveyor permit
    bWheelRunCmd : BOOL := FALSE;            // 转轮运行命令 [-] / wheel run command
    bFrostProtect: BOOL := FALSE;            // 防霜动作中 [-] / frost protection active
    bWheelFbOk   : BOOL := FALSE;            // 转轮反馈到位 [-] / wheel feedback present
    fEffPct      : REAL := 0.0;              // 热回收效率（锁存值）[百分比] / heat recovery efficiency, latched [percent]
    bEffOk       : BOOL := FALSE;            // 效率达标且本拍有效 [-] / efficiency passes and this scan is valid
    eState       : E_DL_BhrState := E_DL_BhrState.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eCause       : E_DL_BhrCause := E_DL_BhrCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonStart     : TON;                      // 启动延时，段 0 无条件刷新 / start delay, refreshed unconditionally in segment zero
    tonStop      : TON;                      // 吹扫延时，段 0 无条件刷新 / purge delay, refreshed unconditionally in segment zero
    _eState      : E_DL_BhrState := E_DL_BhrState.eIdle;  // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause      : E_DL_BhrCause := E_DL_BhrCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause : E_DL_BhrCause := E_DL_BhrCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bTempOk     : BOOL := FALSE;            // 三项温度均有限 [-] / all three temperatures finite
    _bEffBaseOk  : BOOL := FALSE;            // 效率分母可用 [-] / the efficiency denominator is usable
    _bFrost      : BOOL := FALSE;            // 防霜动作判定 [-] / frost protection verdict
    _bWheelFbOk  : BOOL := FALSE;            // 转轮反馈到位判定 [-] / wheel feedback verdict
    _bConvPermit : BOOL := FALSE;            // 输送允许判定 [-] / conveyor permit verdict
    _fEff         : REAL := 0.0;             // 效率工作值 [百分比] / efficiency working value [percent]
    _fEffHold     : REAL := 0.0;             // 效率保持块 [百分比] / efficiency holder [percent]
    _fDeltaT      : REAL := 0.0;             // 进排风温差（分母）[开尔文] / exhaust to fresh difference, the denominator [Kelvin]
    _fNum         : REAL := 0.0;             // 效率分子（送风减新风）[开尔文] / numerator, supply minus fresh [Kelvin]
END_VAR
VAR CONSTANT
    DL_BHR_EFF_MIN   : REAL := -100.0;       // 效率下限（负效率可能：转轮反向传热）[百分比] / efficiency floor, a negative value is possible [percent]
    DL_BHR_EFF_MAX   : REAL := 150.0;        // 效率上限 [百分比] / efficiency ceiling [percent]
    DL_BHR_FROST_MIN : REAL := -60.0;        // 防霜限温下限 [摄氏度] / frost limit floor [degree Celsius]
    DL_BHR_FROST_MAX : REAL := 10.0;         // 防霜限温上限 [摄氏度] / frost limit ceiling [degree Celsius]
    DL_BHR_DELTA_MAX : REAL := 200.0;        // 最小温差上限 [开尔文] / minimum difference ceiling [Kelvin]
    DL_BHR_TEMP_MAX  : REAL := 200.0;        // 温度量级上限（绝对值）[摄氏度] / temperature magnitude ceiling as an absolute value [degree Celsius]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串状态闸与业务闸 / segment 0, unconditional refresh with state and process gates on IN only
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonStart(IN := (_eState = E_DL_BhrState.eStartWait) AND (NOT _bFault), PT := tStartDelay); // 启动延时，仅在等反馈相计时 / start delay timing only in the waiting phase
tonStop(IN := (_eState = E_DL_BhrState.ePurge) AND (NOT _bFault), PT := tStopDelay); // 吹扫延时，仅在吹扫相计时 / purge delay timing only in the purge phase

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eState := E_DL_BhrState.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eCause := E_DL_BhrCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_BhrCause.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fEffHold := 0.0; // 效率保持块清零 / clear the efficiency holder
END_IF

// 段 2｜复位沿作用域：清故障锁存（火警必须已消失才允许解除，R152 可达性）/ segment 2, reset edge scope with a reachable release condition
IF rtReset.Q AND (NOT bFireAlarm) THEN // 复位沿且火警已消失 / reset edge with the fire alarm cleared
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_BhrCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _eState := E_DL_BhrState.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
END_IF

// 段 3｜组态域闸（R151 全覆盖）：双窗配比（R100）+ 阈值域 / segment 3, configuration domain gate including the window ratio
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF tStopDelay < tStartDelay THEN // 吹扫窗短于启动窗，违反配比约束 / the purge window is shorter than the start window
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (tStartDelay < T#0S) OR (tStopDelay < T#0S) THEN // 时间窗为负 / a negative time window
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fFrostLimitC < DL_BHR_FROST_MIN) OR (fFrostLimitC > DL_BHR_FROST_MAX) OR (fFrostLimitC <> fFrostLimitC) THEN // 防霜限温越域 / frost limit out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fMinDeltaTC <= 0.0) OR (fMinDeltaTC > DL_BHR_DELTA_MAX) OR (fMinDeltaTC <> fMinDeltaTC) THEN // 最小温差越域 / minimum difference out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fEffMinPct < 0.0) OR (fEffMinPct > 100.0) OR (fEffMinPct <> fEffMinPct) THEN // 效率达标阈越域 / efficiency threshold out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_BhrCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _eState := E_DL_BhrState.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 4｜火警联锁：最高优先级，撤命令 + 撤允许 + 锁存 / segment 4, fire alarm interlock with the highest priority
IF bFireAlarm THEN // 火警成立 / the fire alarm is active
    IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_BhrCause.eFireAlarm; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    END_IF
END_IF

// 段 5｜温度闸与防霜判据：温度非有限即不判防霜（不穿透出口）/ segment 5, temperature gate and frost criterion
_bTempOk := (fExhaustC = fExhaustC) AND ((fExhaustC - fExhaustC) = (fExhaustC - fExhaustC)) AND (fSupplyC = fSupplyC) AND ((fSupplyC - fSupplyC) = (fSupplyC - fSupplyC)) AND (fFreshC = fFreshC) AND ((fFreshC - fFreshC) = (fFreshC - fFreshC)) AND (ABS(fExhaustC) <= DL_BHR_TEMP_MAX) AND (ABS(fFreshC) <= DL_BHR_TEMP_MAX); // 三项温度有限性闸 / finiteness gate on all three temperatures
_bFrost := _bTempOk AND (fFreshC <= fFrostLimitC); // 防霜判据：新风温度低于限温 / frost criterion on the fresh air temperature
_bWheelFbOk := bWheelRunFb AND (NOT bFireAlarm); // 反馈到位判据：反馈有且无火警 / feedback verdict

// 段 6｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 6, phase machine with an ELSE fallback for illegal phases
_bConvPermit := FALSE; // 每拍先撤输送允许，只有运行相才能重新置位（防相外残留）/ the permit is withdrawn every scan and only the run phase may raise it again
CASE _eState OF
E_DL_BhrState.eIdle: // 空闲相：有请求且有反馈才进启动等反馈相 / idle, a request plus feedback moves into the start wait
    IF _bFault THEN // 故障锁存 / the fault is latched
        _eState := E_DL_BhrState.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF bConvRunCmd AND bEnable THEN // 有输送请求且使能 / a conveyor request while enabled
        _eState := E_DL_BhrState.eStartWait; // 迁启动等反馈相 / migrate to the start wait phase
    END_IF

E_DL_BhrState.eStartWait: // 启动等反馈相：转轮先启，反馈与延时双满足才放开输送 / start wait, the wheel leads and both feedback and delay must hold
    _bWheelFbOk := bWheelRunFb AND (NOT bFireAlarm) AND _bTempOk; // 本相内反馈判据再收紧（含温度闸）/ the feedback verdict is tightened inside this phase to include the temperature gate
    IF _bFault THEN // 故障锁存 / the fault is latched
        _eState := E_DL_BhrState.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF (NOT bConvRunCmd) THEN // 请求撤销 / the request was withdrawn
        _eState := E_DL_BhrState.eIdle; // 回空闲相 / return to idle
    ELSIF _bWheelFbOk AND tonStart.Q THEN // 反馈到位且启动延时到 / feedback present and the start delay elapsed
        _eState := E_DL_BhrState.eRun; // 迁运行相 / migrate to the run phase
    END_IF

E_DL_BhrState.eRun: // 运行相：输送允许，请求撤销即进吹扫相 / run phase, a withdrawn request moves into purge
    _bConvPermit := bEnable AND bFilterOk AND _bWheelFbOk AND (NOT _bFrost) AND (NOT bFireAlarm); // 输送允许判据，四条判据逐项与 / the conveyor permit is the conjunction of four criteria
    IF _bFault THEN // 故障锁存 / the fault is latched
        _eState := E_DL_BhrState.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF NOT bConvRunCmd THEN // 请求撤销 / the request was withdrawn
        _eState := E_DL_BhrState.ePurge; // 迁吹扫相 / migrate to the purge phase
    END_IF

E_DL_BhrState.ePurge: // 吹扫相：转轮续转，延时到回空闲 / purge phase, the wheel keeps running until the delay elapses
    IF _bFault THEN // 故障锁存 / the fault is latched
        _eState := E_DL_BhrState.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF tonStop.Q THEN // 吹扫延时到 / the purge delay elapsed
        _eState := E_DL_BhrState.eIdle; // 回空闲相 / return to idle
    ELSIF bConvRunCmd THEN // 请求重新给出 / the request is issued again
        _eState := E_DL_BhrState.eStartWait; // 重走启动等反馈相 / restart from the start wait phase
    END_IF

E_DL_BhrState.eFault: // 故障相：全撤命令，等复位沿 / fault phase, all commands withdrawn until the reset edge
    _bConvPermit := FALSE; // 撤输送允许 / the conveyor permit is withdrawn
    _bWheelFbOk := FALSE; // 撤反馈判据 / the feedback verdict is withdrawn

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_BhrCause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
    _eState := E_DL_BhrState.eFault; // 迁故障相 / migrate to the fault phase
    _bConvPermit := FALSE; // 撤输送允许 / the conveyor permit is withdrawn
END_CASE

// 段 7｜转轮命令：启动等反馈 / 运行 / 吹扫三相为真，故障与失能一律撤除 / segment 7, wheel command truth table
bWheelRunCmd := ((_eState = E_DL_BhrState.eStartWait) OR (_eState = E_DL_BhrState.eRun) OR (_eState = E_DL_BhrState.ePurge)) AND bEnable AND (NOT bFireAlarm) AND (NOT _bFault); // 转轮命令，四条件合取 / the wheel command as a conjunction of four conditions
IF _eState = E_DL_BhrState.eFault THEN // 故障相 / the fault phase
    bWheelRunCmd := FALSE; // 撤转轮命令 / withdraw the wheel command
END_IF

// 段 8｜热回收效率：温差不足不更新，出口保持上拍值 / segment 8, heat recovery efficiency with a guarded denominator
IF _bTempOk THEN // 温度可用 / temperatures usable
    _fDeltaT := fExhaustC - fFreshC; // 进排风温差 / the exhaust to fresh difference
    _bEffBaseOk := _fDeltaT >= fMinDeltaTC; // 分母可用判据（含正负方向：仅排风高于新风才有效）/ denominator verdict requiring the exhaust to be warmer than the fresh air
    IF _bEffBaseOk THEN // 分母可用 / the denominator is usable
        _fNum := fSupplyC - fFreshC; // 分子：转轮后温升 / numerator, the temperature rise across the wheel
        _fEff := _fNum / _fDeltaT * 100.0; // 效率，除子已证不小于 fMinDeltaTC / efficiency, divisor proven not below the minimum difference
        IF _fEff < DL_BHR_EFF_MIN THEN // 效率下越界 / efficiency below the floor
            _fEff := DL_BHR_EFF_MIN; // 下钳 / clamp downward
        ELSIF _fEff > DL_BHR_EFF_MAX THEN // 效率上越界 / efficiency above the ceiling
            _fEff := DL_BHR_EFF_MAX; // 上钳 / clamp upward
        END_IF
        IF (_fEff = _fEff) AND ((_fEff - _fEff) = (_fEff - _fEff)) THEN // 结果有限性闸 / result finiteness gate
            _fEffHold := _fEff; // 有效拍更新保持块 / the holder updates on a valid scan
        END_IF
    END_IF
END_IF

// 段 9｜成因分派（固定优先级：故障 > 火警外的降级原因 > 无成因）/ segment 9, cause dispatch with a fixed priority
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSIF _bFrost THEN // 防霜动作 / frost protection tripped
    eCause := E_DL_BhrCause.eFrost; // 信息级成因 / informational cause
ELSIF (NOT bFilterOk) THEN // 过滤网异常 / the filter is unhealthy
    eCause := E_DL_BhrCause.eFilterBad; // 信息级成因 / informational cause
ELSIF (NOT bWheelRunFb) AND (_eState = E_DL_BhrState.eStartWait) THEN // 等反馈相缺反馈 / feedback missing while waiting
    eCause := E_DL_BhrCause.eNoWheelFb; // 信息级成因 / informational cause
ELSIF (NOT _bEffBaseOk) AND _bTempOk THEN // 温差不足 / the temperature difference is too small
    eCause := E_DL_BhrCause.eEffInvalid; // 信息级成因 / informational cause
ELSE
    eCause := E_DL_BhrCause.eNone; // 无成因 / no cause
END_IF

// 段 10｜统一出口 / segment 10, unified outlet
bConvPermit := _bConvPermit AND (_eState = E_DL_BhrState.eRun) AND (NOT _bFault); // 输送允许受运行相与故障锁存双重否决 / the permit is vetoed by the run phase and the fault latch
bFrostProtect := _bFrost; // 防霜动作出口 / frost protection outlet
bWheelFbOk := _bWheelFbOk AND (NOT _bFault); // 反馈到位出口受故障锁存否决 / the feedback outlet is vetoed by the fault latch
fEffPct := _fEffHold; // 效率出口取保持块 / efficiency outlet from the holder
bEffOk := _bEffBaseOk AND (_fEffHold >= fEffMinPct) AND (NOT _bFault); // 效率达标且本拍有效（挂状态量）/ efficiency pass with this scan valid
eState := _eState; // 相位出口单点映射 / single-point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
