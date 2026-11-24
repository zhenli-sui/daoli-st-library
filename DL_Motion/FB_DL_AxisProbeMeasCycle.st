(*
  ==================================================================
  组件名 Component  : FB_DL_AxisProbeMeasCycle
  分类   Category   : DL_Motion
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 探针测量循环。相位机 eIdle → eFastApproach → eProbeLatch →
                      eRetract → eSettle → eRecord → eDone / eFault；快进 - 慢探
                      两段速度；探针触发用 R_TRIG 边沿锁存（锁存值用于记录，
                      禁与实时镜像混用）；超行程保护；nRepeat 次重复测量后做
                      离散度判据（max - min 对容差），超差判 eScatterHigh。
  来源   Source     : t2-2-lbp（与 FB_DL_MarkPositionLatch 分工：锁存原子 vs 完整测量循环）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；趋近 - 触发锁存 - 回退 -
                      评价测量循环为通用测量语义，clean-room 自研实现，未复制任何
                      闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / ARRAY / LREAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  同拍多窗说明（R100）：四个窗互斥 —— 每窗 IN 串「本相」闸，任一时刻只有一个窗
                      在计时，无同拍双窗配比约束。
  边界 Boundary     :
                      一 本件只出速度命令与测量结论，不驱动轴本体、不解算几何尺寸
                         （属主边界）；
                      二 锁存纪律：_fMeasPos 只在触发沿那一拍由 fPosAct 写入一次，
                         其后评价一律用锁存值（R33 锁存副本与实时镜像不混用）；
                      三 相级看门狗使能只用相驻留本身（R145）；
                      四 故障锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fVelCmd 为速度命令（快进 / 慢探 / 回退三档）；fMeasPos 为
                      nRepeat 次均值；bMeasValid 为单拍脉冲（R187 两段式）；
                      eFault 为锁存回放；ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 4 · 序号 19）
  ==================================================================
*)

TYPE E_DL_ApcPhase :
(
    eIdle         := 0,  // 空闲：等启动沿 / idle, waiting for the start edge
    eFastApproach := 10, // 快进：高速趋近到慢探起点 / fast approach, high speed to the slow start
    eProbeLatch   := 20, // 慢探：低速探触发并锁存 / probe latch, low speed to the trigger with a latch
    eRetract      := 30, // 回退：退回安全距 / retract, back to the safe distance
    eSettle       := 40, // 稳定：驻留稳定窗 / settle, the dwell window
    eRecord       := 50, // 记录：样本入环并评价 / record, the sample enters the ring and the verdict runs
    eDone         := 60, // 完成：结论驻留 / done, the verdict holds
    eFault        := 90  // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_ApcFault :
(
    eNone       := 0, // 无成因 / no cause
    eNoTrigger  := 1, // 越程内未触发（故障级，与 bError 配对）/ no trigger inside the travel limit, fault grade paired with bError
    eOverTravel := 2, // 超行程保护（故障级，与 bError 配对）/ the overtravel protection, fault grade paired with bError
    eScatterHigh:= 3, // 重复测量离散度超差（故障级，与 bError 配对）/ the scatter of the repeats is over the tolerance, fault grade paired with bError
    eSensorBad  := 4, // 位置非有限或组态非法（故障级，与 bError 配对）/ the position is non finite or the config illegal, fault grade paired with bError
    ePhaseBad   := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisProbeMeasCycle
VAR_INPUT
    bEnable     : BOOL := TRUE;    // 使能，失能时停循环回空闲 [-] / enable, the cycle stops when disabled
    bReset      : BOOL := FALSE;   // 复位上升沿清故障锁存与样本环 [-] / reset rising edge clears the latch and the sample ring
    bStart      : BOOL := FALSE;   // 测量启动脉冲，上升沿受理 [-] / the measurement start pulse, accepted on the rising edge
    bAbort      : BOOL := FALSE;   // 中止（电平），任何中间态回空闲 [-] / the abort level, any middle phase returns to idle
    fPosAct     : LREAL := 0.0;    // 轴实际位置 [位置单位] / the actual axis position [position unit]
    bProbeTrig  : BOOL := FALSE;   // 探针触发信号 [-] / the probe trigger signal
    fTargetPos  : LREAL := 100.0;  // 目标标称位置 [位置单位] / the nominal target position [position unit]
    fSlowStart  : LREAL := 90.0;   // 慢探起点（快进切换位）[位置单位] / the slow probe start [position unit]
    fBackDist   : LREAL := 5.0;    // 回退安全距 [位置单位]，域 大于零 / the retract safe distance [position unit], domain above zero
    fOverTravel : LREAL := 2.0;    // 超行程容限（越程即故障 / 未触发判据）[位置单位]，域 大于零 / the overtravel tolerance [position unit], domain above zero
    fScatterTol : LREAL := 0.01;   // 离散度容差 [位置单位]，域 大于零 / the scatter tolerance [position unit], domain above zero
    nRepeat     : INT := 3;        // 重复测量次数 [次]，域 1..20 / the repeat count [count], domain one to twenty
    fVelFast    : LREAL := 500.0;  // 快进速度 [位置单位每秒] / the fast approach velocity [position unit per second]
    fVelSlow    : LREAL := 20.0;   // 慢探速度 [位置单位每秒]，域 小于快进 / the slow probe velocity, below the fast one
    tFastTo     : TIME := T#10S;   // 快进超时窗 [毫秒] / the fast approach timeout [millisecond]
    tProbeTo    : TIME := T#10S;   // 慢探超时窗 [毫秒] / the probe timeout [millisecond]
    tRetractTo  : TIME := T#5S;    // 回退超时窗 [毫秒] / the retract timeout [millisecond]
    tSettle     : TIME := T#200MS; // 稳定驻留窗 [毫秒] / the settle dwell window [millisecond]
END_VAR
VAR_OUTPUT
    fVelCmd   : LREAL := 0.0;   // 速度命令（快进 / 慢探 / 回退三档）[位置单位每秒] / the velocity command, three gears [position unit per second]
    fMeasPos  : LREAL := 0.0;   // 测量结论（nRepeat 次均值）[位置单位] / the measurement verdict, the mean of the repeats [position unit]
    bMeasValid: BOOL := FALSE;  // 测量有效单拍脉冲 [-] / the measurement valid single shot pulse
    nMeasCnt  : INT := 0;       // 已完成测量次数 [次] / the completed measurement count [count]
    ePhase    : E_DL_ApcPhase := E_DL_ApcPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault    : E_DL_ApcFault := E_DL_ApcFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError    : BOOL := FALSE;  // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStart  : R_TRIG; // 启动沿检测，段 0 无条件刷新 / start edge, refreshed unconditionally in segment zero
    rtProbe  : R_TRIG; // 探针触发沿检测，段 0 无条件刷新 / the probe trigger edge, refreshed unconditionally in segment zero
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonFast  : TON;    // 快进超时窗，段 0 无条件刷新 / the fast timeout window, refreshed unconditionally
    tonProbe : TON;    // 慢探超时窗，段 0 无条件刷新 / the probe timeout window, refreshed unconditionally
    tonRetr  : TON;    // 回退超时窗，段 0 无条件刷新 / the retract timeout window, refreshed unconditionally
    tonSettle: TON;    // 稳定驻留窗，段 0 无条件刷新 / the settle dwell window, refreshed unconditionally
    _ePhase  : E_DL_ApcPhase := E_DL_ApcPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_ApcFault := E_DL_ApcFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bDoneInt: BOOL := FALSE; // 有效脉冲内部位，统一出口映射 / internal valid bit, mapped at the unified outlet
    _bInOk   : BOOL := FALSE; // 位置有限 [-] / the position is finite
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _fLatch  : LREAL := 0.0;  // 触发沿锁存位置（评价唯一来源）[位置单位] / the latched position at the trigger edge, the only evaluation source
    _fMax    : LREAL := 0.0;  // 样本最大值 [位置单位] / the sample maximum [position unit]
    _fMin    : LREAL := 0.0;  // 样本最小值 [位置单位] / the sample minimum [position unit]
    _fSum    : LREAL := 0.0;  // 样本和 [位置单位] / the sample sum [position unit]
    _nRepeat : INT := 3;      // 钳定后的重复次数 [次] / the clamped repeat count [count]
    _nCnt    : INT := 0;      // 已收样本数 [个] / the collected sample count [count]
    _nI      : INT := 1;      // 环窗遍历游标 [槽号] / the ring traversal cursor
    _nGuard  : INT := 0;      // 遍历守护计数 [次] / the traversal guard [count]
    _anMeas  : ARRAY[1..20] OF LREAL := [20(0.0)]; // 样本环（时间序追加，无回绕需求）[位置单位] / the sample ring appended in time order [position unit]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸（FB50-1）/ segment 0, unconditional refresh, no instance call inside a branch
rtStart(CLK := bStart); // 启动沿 / the start edge
rtProbe(CLK := bProbeTrig); // 探针触发沿 / the probe trigger edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonFast(IN := (_ePhase = E_DL_ApcPhase.eFastApproach) AND (NOT _bFault), PT := tFastTo); // 快进超时窗 / the fast timeout window
tonProbe(IN := (_ePhase = E_DL_ApcPhase.eProbeLatch) AND (NOT _bFault), PT := tProbeTo); // 慢探超时窗 / the probe timeout window
tonRetr(IN := (_ePhase = E_DL_ApcPhase.eRetract) AND (NOT _bFault), PT := tRetractTo); // 回退超时窗 / the retract timeout window
tonSettle(IN := (_ePhase = E_DL_ApcPhase.eSettle) AND (NOT _bFault), PT := tSettle); // 稳定驻留窗 / the settle dwell window

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_ApcPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaulC := E_DL_ApcFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nCnt := 0; // 样本数清零 / clear the sample count
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清样本环与计数（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_ApcFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_ApcPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _nCnt := 0; // 作用域三：清样本计数 / scope three, clear the sample count
    fVelCmd := 0.0; // 作用域三：速度命令归零 / scope three, the velocity command zeroes
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖）/ segment 3, the configuration and input domain gates
_bInOk := (fPosAct = fPosAct) AND ((fPosAct - fPosAct) = (fPosAct - fPosAct)); // 位置有限性 / the position finiteness
_bCfgOk := (fBackDist > 0.0) AND (fBackDist = fBackDist) AND (fOverTravel > 0.0) AND (fOverTravel = fOverTravel) AND (fScatterTol > 0.0) AND (fScatterTol = fScatterTol) AND (fVelFast > 0.0) AND (fVelFast = fVelFast) AND (fVelSlow > 0.0) AND (fVelSlow < fVelFast) AND (fVelSlow = fVelSlow) AND (tFastTo > T#0S) AND (tProbeTo > T#0S) AND (tRetractTo > T#0S) AND (tSettle > T#0S); // 组态参数域判定 / the configuration domain verdict
_nRepeat := nRepeat; // 重复次数直通 / the repeat count passes through
IF _nRepeat < 1 THEN // 下越域 / below the floor
    _nRepeat := 1; // 回钳到一 / clamp to one
ELSIF _nRepeat > 20 THEN // 上越域 / above the ceiling
    _nRepeat := 20; // 回钳到二十 / clamp to twenty
END_IF
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 位置非有限或组态非法 / a void position or an illegal configuration
    IF NOT _bFault THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_ApcPhase.eIdle: // 空闲相：等启动沿 / the idle phase, waiting for the start edge
    fVelCmd := 0.0; // 速度命令归零 / the velocity command zeroes
    IF bEnable AND (NOT _bFault) AND (NOT bAbort) AND rtStart.Q THEN // 启动沿受理 / the start edge is accepted
        _nCnt := 0; // 样本数清零（新测量批次）/ clear the sample count for a fresh batch
        _ePhase := E_DL_ApcPhase.eFastApproach; // 迁快进相 / migrate to the fast approach phase
    END_IF

E_DL_ApcPhase.eFastApproach: // 快进相：高速趋近（退出条件 ≥2：到慢探起点 / 超时 / 越程 / 中止 / 失能，R98）/ the fast approach phase with at least two exit conditions
    fVelCmd := fVelFast; // 快进速度命令 / the fast velocity command
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_ApcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF NOT _bInOk THEN // 位置非有限 / the position went void
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF fPosAct > fTargetPos + fOverTravel THEN // 超行程保护（R146 安全侧立即终止）/ the overtravel protection, an immediate safe side stop
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eOverTravel; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF fPosAct >= fSlowStart THEN // 到慢探起点 / the slow start is reached
        _ePhase := E_DL_ApcPhase.eProbeLatch; // 迁慢探相 / migrate to the probe latch phase
    ELSIF tonFast.Q THEN // 快进超时 / the fast approach timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eNoTrigger; // 故障级成因（R45 配对 bError，快进未达判慢探必不触发）/ the fault cause paired with bError
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_ApcPhase.eProbeLatch: // 慢探相：低速探触发并锁存 / the probe latch phase, the low speed trigger with the latch
    fVelCmd := fVelSlow; // 慢探速度命令 / the slow velocity command
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_ApcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF NOT _bInOk THEN // 位置非有限 / the position went void
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF fPosAct > fTargetPos + fOverTravel THEN // 越程未触发（超行程判据复用，R146 方向一致）/ past the limit without a trigger
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eNoTrigger; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF rtProbe.Q THEN // 探针触发沿：锁存位置（锁存纪律：本拍一次写入）/ the trigger edge, the position latches once this scan
        _fLatch := fPosAct; // 锁存副本写入（评价唯一来源）/ the latched copy, the only evaluation source
        _ePhase := E_DL_ApcPhase.eRetract; // 迁回退相 / migrate to the retract phase
    ELSIF tonProbe.Q THEN // 慢探超时 / the probe timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eNoTrigger; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_ApcPhase.eRetract: // 回退相：退回安全距 / the retract phase, back to the safe distance
    fVelCmd := fVelFast; // 回退用快进档（反向由外部换向）/ the retract uses the fast gear, the direction is external
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_ApcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF fPosAct <= (_fLatch - fBackDist) THEN // 已退到安全距 / the safe distance is reached
        _ePhase := E_DL_ApcPhase.eSettle; // 迁稳定相 / migrate to the settle phase
    ELSIF tonRetr.Q THEN // 回退超时 / the retract timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_ApcFault.eNoTrigger; // 故障级成因（回退超时归并触发缺失带，R190 同带子带）/ the fault cause, the retract timeout rides the trigger band
        _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_ApcPhase.eSettle: // 稳定相：速度归零驻留 / the settle phase, the velocity zeroes and dwells
    fVelCmd := 0.0; // 速度命令归零 / the velocity command zeroes
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_ApcPhase.eIdle; // 回空闲相 / back to idle
    ELSIF tonSettle.Q THEN // 稳定驻留窗已过 / the dwell window elapsed
        _ePhase := E_DL_ApcPhase.eRecord; // 迁记录相 / migrate to the record phase
    END_IF

E_DL_ApcPhase.eRecord: // 记录相：锁存样本入环并评价 / the record phase, the latched sample enters the ring and the verdict runs
    IF (NOT bEnable) OR bAbort THEN // 失能或中止 / disabled or aborting
        _ePhase := E_DL_ApcPhase.eIdle; // 回空闲相 / back to idle
    ELSE // 记录与评价 / the recording and the verdict
        IF _nCnt < 20 THEN // 样本环未满（钳定后重复数不超过 20）/ the ring is not full
            _nCnt := _nCnt + 1; // 样本数递增 / increment the sample count
            _anMeas[_nCnt] := _fLatch; // 锁存值入环（非实时镜像）/ the latched value enters the ring, never the live mirror
        END_IF
        IF _nCnt >= _nRepeat THEN // 样本齐 / the samples are complete
            _fMax := _anMeas[1]; // 最大值起步 / start the maximum
            _fMin := _anMeas[1]; // 最小值起步 / start the minimum
            _fSum := 0.0; // 和清零 / clear the sum
            _nI := 1; // 游标起步 / start the cursor
            _nGuard := 0; // 守护清零 / clear the guard
            WHILE (_nI <= _nCnt) AND (_nGuard < 20) DO // 时间序遍历样本环 / traverse the sample ring in time order
                _nGuard := _nGuard + 1; // 守护递增 / increment the guard
                IF _anMeas[_nI] > _fMax THEN // 最大值刷新 / refresh the maximum
                    _fMax := _anMeas[_nI]; // 更新 / update
                END_IF
                IF _anMeas[_nI] < _fMin THEN // 最小值刷新 / refresh the minimum
                    _fMin := _anMeas[_nI]; // 更新 / update
                END_IF
                _fSum := _fSum + _anMeas[_nI]; // 和累计 / accumulate the sum
                _nI := _nI + 1; // 游标递增 / increment the cursor
            END_WHILE
            IF (_fMax - _fMin) > fScatterTol THEN // 离散度超差 / the scatter is over the tolerance
                _bFault := TRUE; // 置故障锁存 / raise the fault latch
                _eFaulC := E_DL_ApcFault.eScatterHigh; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
                _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
            ELSE // 离散度合格，出结论 / the scatter passes, the verdict is raised
                fMeasPos := _fSum / INT_TO_LREAL(_nCnt); // 均值结论，除子已证大于零 / the mean verdict with a proven divisor
                _bDoneInt := TRUE; // 有效脉冲内部位置位（统一出口映射，R187）/ raise the internal valid bit
                _ePhase := E_DL_ApcPhase.eDone; // 迁完成相 / migrate to the done phase
            END_IF
        ELSE // 样本未齐，再来一轮 / the samples are incomplete, another round
            _ePhase := E_DL_ApcPhase.eFastApproach; // 迁快进相 / migrate to the fast approach phase
        END_IF
    END_IF

E_DL_ApcPhase.eDone: // 完成相：结论驻留，速度归零，等复位或新启动 / the done phase, the verdict holds until reset or a new start
    fVelCmd := 0.0; // 速度命令归零 / the velocity command zeroes
    IF (NOT bEnable) OR bAbort OR rtStart.Q THEN // 失能、中止或新启动沿 / disabled, aborting or a new start edge
        _ePhase := E_DL_ApcPhase.eIdle; // 回空闲相 / back to idle
    END_IF

E_DL_ApcPhase.eFault: // 故障相：速度归零，成因锁存，等复位沿 / the fault phase, the velocity zeroes until the reset edge
    fVelCmd := 0.0; // 速度安全侧归零 / the velocity takes the safe side zero
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_ApcPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_ApcFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_ApcPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口 / segment 5, the unified outlet
bMeasValid := _bDoneInt; // 有效脉冲映射本拍值 / map the valid pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping
nMeasCnt := _nCnt; // 已完成测量次数出口 / the completed count outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_ApcFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
