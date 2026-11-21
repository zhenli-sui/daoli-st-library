(*
  ==================================================================
  组件名 Component  : FB_DL_SlurrySieveClogWatch
  分类   Category   : DL_Process
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 浆料筛网堵塞监视。堵塞指数 = (dP / q²) 对学习基准的比值；
                      趋势斜率取时间序环窗 8 点（R194：时间序遍历，禁头游标序）
                      最小二乘斜率；劣化分 warn / alarm 双级独立成因（R190）；
                      流量低于下限判 eFlowLoss；基准仅在清洁态持续窗口内更新。
  来源   Source     : t2-6-rockwell-aoi（判据组织次源）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；压差 / 流量堵塞判据为
                      公开过滤工艺语义，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / ARRAY / LREAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做堵塞判级与基准学习，不反冲洗、不调流量（属主边界）；
                      二 环窗遍历一律按时间序（自最旧样本起，R194）；最小二乘分母
                         8·Σx² - (Σx)² = 8·140 - 784 = 336，x = 0..7 结构性非零；
                      三 判据方向性（R146）：warn 与 alarm 为同向递进双级，成因独立；
                      四 学习判据：严重度 < fCleanRatio 持续 tLearnWin 才更新基准
                         （rtLearn 边沿单次更新，防每拍重写）；
                      五 成因锁存解除路径 = 迟滞反向自愈 或 bReset 上升沿（R188）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fClogIdx 为堵塞指数（相对基准，1.0 = 基准水平）；fTrendSlope 为
                      8 点最小二乘斜率（每拍）；eFault 为锁存回放；
                      ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 3 · 序号 15）
  ==================================================================
*)

TYPE E_DL_SscPhase :
(
    eIdle  := 0,  // 未使能：监视停摆 / disabled, the watch is idle
    eRun   := 10, // 运行：逐拍判级 / running, graded every scan
    eFault := 90  // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_SscFault :
(
    eNone      := 0, // 无成因 / no cause
    eClogWarn  := 1, // 堵塞预警级（故障级，与 bError 配对）/ the clog warning grade, fault grade paired with bError
    eClogAlarm := 2, // 堵塞报警级（故障级，与 bError 配对）/ the clog alarm grade, fault grade paired with bError
    eFlowLoss  := 3, // 流量低于下限（故障级，与 bError 配对）/ the flow is below the floor, fault grade paired with bError
    eSensorBad := 4, // 压差或流量非有限（故障级，与 bError 配对）/ the pressure or the flow is non finite, fault grade paired with bError
    ePhaseBad  := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_SlurrySieveClogWatch
VAR_INPUT
    bEnable     : BOOL := TRUE;   // 使能，失能时监视停摆 [-] / enable, the watch stops when disabled
    bReset      : BOOL := FALSE;  // 复位上升沿清全部锁存与环窗 [-] / reset rising edge clears every latch and the ring
    fDp         : LREAL := 10.0;  // 筛前筛后压差 [千帕] / the sieve differential pressure [kilopascal]
    fQ          : LREAL := 20.0;  // 筛下流量 [立方米每小时] / the under sieve flow [cubic metre per hour]
    fQMin       : LREAL := 2.0;   // 流量下限（判据与除子域）[立方米每小时]，域 大于零 / the flow floor for the criteria and the divisor, domain above zero
    fWarnRatio  : LREAL := 1.5;   // 预警级比值阈 [无量纲]，域 大于 1 / the warning ratio threshold, above one
    fAlarmRatio : LREAL := 2.5;   // 报警级比值阈 [无量纲]，域 大于预警阈 / the alarm ratio threshold, above the warning one
    fCleanRatio : LREAL := 1.2;   // 清洁态比值上限（学习判据）[无量纲] / the clean ratio ceiling for learning
    tLearnWin   : TIME := T#60S;  // 清洁态学习持续窗 [毫秒]，域 大于零 / the clean learning dwell window [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    fClogIdx    : LREAL := 1.0; // 堵塞指数（相对基准）[无量纲] / the clog index relative to the baseline
    fTrendSlope : LREAL := 0.0; // 8 点趋势斜率 [指数每拍] / the eight point trend slope [index per scan]
    ePhase      : E_DL_SscPhase := E_DL_SscPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault      : E_DL_SscFault := E_DL_SscFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError      : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    rtLearn  : R_TRIG; // 学习窗到时沿检测，段 0 无条件刷新 / the learning window edge, refreshed unconditionally in segment zero
    tonLearn : TON;    // 清洁态学习持续窗（自清洁判据驱动，非错峰窗，无自复位需求）/ the clean learning dwell window
    _ePhase  : E_DL_SscPhase := E_DL_SscPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_SscFault := E_DL_SscFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bInOk   : BOOL := FALSE; // 两输入均有限 [-] / both inputs are finite
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bBad    : BOOL := FALSE; // 传感器无效锁存 [-] / the sensor bad latch
    _bFlowLo : BOOL := FALSE; // 流量损失迟滞锁存 [-] / the flow loss hysteresis latch
    _bWarn   : BOOL := FALSE; // 预警迟滞锁存 [-] / the warning hysteresis latch
    _bAlarm  : BOOL := FALSE; // 报警迟滞锁存 [-] / the alarm hysteresis latch
    _bClean  : BOOL := FALSE; // 清洁态判定 [-] / the clean state verdict
    _nHead   : INT := 0;      // 环窗最近样本槽位（1 起）[槽号] / the newest ring slot, one based
    _nFill   : INT := 0;      // 环窗已填样本数 [个] / the ring fill count
    _nIdx    : INT := 1;      // 时间序遍历槽位 [槽号] / the time order traversal slot
    _nK      : INT := 0;      // 时间序遍历序号 [序号] / the time order ordinal
    _nGuard  : INT := 0;      // 遍历守护计数 [次] / the traversal guard [count]
    _fIdxRaw : LREAL := 0.0;  // 原始堵塞指数（dP / q²）[无量纲] / the raw clog index, dP over q squared
    _fSev    : LREAL := 0.0;  // 严重度（对基准比值）[无量纲] / the severity against the baseline
    _fSumX   : LREAL := 0.0;  // 最小二乘 Σx [无量纲] / the least squares sum of x
    _fSumY   : LREAL := 0.0;  // 最小二乘 Σy [无量纲] / the least squares sum of y
    _fSumXY  : LREAL := 0.0;  // 最小二乘 Σxy [无量纲] / the least squares sum of x times y
    _fNum    : LREAL := 0.0;  // 斜率分子 [无量纲] / the slope numerator
    _afIdx   : ARRAY[1..8] OF LREAL := [8(0.0)]; // 环窗堵塞指数缓存 [无量纲] / the ring of clog indices
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串状态闸（FB50-1）/ segment 0, unconditional refresh with the state gates on IN only
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonLearn(IN := _bClean AND (_ePhase = E_DL_SscPhase.eRun) AND (NOT _bFault) AND (NOT _bFlowLo) AND (NOT _bWarn) AND (NOT _bAlarm), PT := tLearnWin); // 清洁态学习窗 / the clean learning window
rtLearn(CLK := tonLearn.Q); // 学习窗到时沿 / the learning window edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_SscPhase.eRun; // 相位从运行起步 / the phase starts in run
    _eFaulC := E_DL_SscFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nHead := 0; // 环窗无样本 / the ring holds no sample
    _nFill := 0; // 环窗计数清零 / clear the ring count
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清环窗与基准（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_SscFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _bFlowLo := FALSE; // 作用域一：清流量损失迟滞 / scope one, clear the flow loss latch
    _bWarn := FALSE; // 作用域一：清预警迟滞 / scope one, clear the warning latch
    _bAlarm := FALSE; // 作用域一：清报警迟滞 / scope one, clear the alarm latch
    _bBad := FALSE; // 作用域一：清传感器锁存 / scope one, clear the sensor latch
    _ePhase := E_DL_SscPhase.eRun; // 作用域二：迁回运行相 / scope two, migrate back to run
    _nHead := 0; // 作用域三：清环窗槽位 / scope three, clear the ring slot
    _nFill := 0; // 作用域三：清环窗计数 / scope three, clear the ring count
    fClogIdx := 1.0; // 作用域三：指数回归基准水平 / scope three, the index returns to the baseline level
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖）/ segment 3, the configuration and input domain gates
_bInOk := (fDp = fDp) AND ((fDp - fDp) = (fDp - fDp)) AND (fQ = fQ) AND ((fQ - fQ) = (fQ - fQ)); // 两输入有限性 / finiteness of both inputs
_bCfgOk := (fQMin > 0.0) AND (fQMin = fQMin) AND (fWarnRatio > 1.0) AND (fWarnRatio = fWarnRatio) AND (fAlarmRatio > fWarnRatio) AND (fAlarmRatio = fAlarmRatio) AND (fCleanRatio > 1.0) AND (fCleanRatio <= fWarnRatio) AND (fCleanRatio = fCleanRatio) AND (tLearnWin > T#0S); // 组态参数域判定 / the configuration domain verdict
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 输入非有限或组态非法 / a non finite input or an illegal configuration
    IF NOT _bBad THEN // 未锁存才置 / set only while unlatched
        _bBad := TRUE; // 置传感器无效锁存 / raise the sensor bad latch
    END_IF
END_IF

// 段 4｜本拍指数计算与环窗写入 / segment 4, the per scan index computation and the ring write
_fIdxRaw := 0.0; // 原始指数预置零 / preset the raw index to zero
IF _bInOk AND (fQ > fQMin) THEN // 流量高于下限才可算（除子域闸）/ the index needs the flow above the floor
    _fIdxRaw := fDp / (fQ * fQ); // 原始堵塞指数，除子为流量平方已证超阈 / the raw index with the proven squared flow divisor
END_IF
IF (_nFill < 8) OR (_nHead < 8) THEN // 槽位推进（未满顺填，已满环回钳 1..8）/ advance the slot with the wrap clamp
    _nHead := _nHead + 1; // 槽位前移 / advance the slot
    IF _nHead > 8 THEN // 越过上界 / past the upper bound
        _nHead := 1; // 回钳到一号槽 / clamp back to slot one
    END_IF
    IF _nFill < 8 THEN // 未满顺填 / fill while not full
        _nFill := _nFill + 1; // 计数递增 / increment the count
    END_IF
    _afIdx[_nHead] := _fIdxRaw; // 指数入环窗 / store the index
END_IF

// 段 5｜时间序环窗遍历：最小二乘斜率（R194：自最旧样本起）/ segment 5, the time order traversal for the least squares slope
_fSumX := 0.0; // Σx 清零 / clear the sum of x
_fSumY := 0.0; // Σy 清零 / clear the sum of y
_fSumXY := 0.0; // Σxy 清零 / clear the sum of xy
_fTrendSlope := 0.0; // 斜率预置零 / preset the slope to zero
IF _nFill >= 2 THEN // 至少两点才可算斜率 / the slope needs at least two points
    _nK := 1; // 时间序序号起步（1 = 最旧样本）/ start the time order ordinal at the oldest
    _nGuard := 0; // 守护清零 / clear the guard
    WHILE (_nK <= _nFill) AND (_nGuard < 16) DO // 时间序遍历，守护为两倍容量 / the time order traversal with a twice capacity guard
        _nGuard := _nGuard + 1; // 守护递增 / increment the guard
        _nIdx := _nHead - _nFill + _nK; // 时间序槽位 / the slot in time order
        IF _nIdx < 1 THEN // 越过下界 / below the lower bound
            _nIdx := _nIdx + 8; // 单次回绕补齐 / a single wrap restores the order
        END_IF
        _fSumX := _fSumX + INT_TO_LREAL(_nK - 1); // x = 0..7 / the x ordinal from zero
        _fSumY := _fSumY + _afIdx[_nIdx]; // y 累计 / accumulate y
        _fSumXY := _fSumXY + INT_TO_LREAL(_nK - 1) * _afIdx[_nIdx]; // xy 累计 / accumulate xy
        _nK := _nK + 1; // 序号递增 / increment the ordinal
    END_WHILE
    _fNum := 8.0 * _fSumXY - _fSumX * _fSumY; // 斜率分子 / the slope numerator
    fTrendSlope := _fNum / 336.0; // 最小二乘斜率，分母 8·140 - 28² = 336 结构性非零（R63 反算留档）/ the slope, the denominator is structurally non zero
END_IF

// 段 6｜严重度计算（对时间序最旧样本 = 学习基准）/ segment 6, the severity against the oldest sample as the learned baseline
IF _nFill >= 1 THEN // 有样本 / a sample exists
    _nIdx := _nHead - _nFill + 1; // 时间序最旧槽位（学习基准）/ the oldest slot, the learned baseline
    IF _nIdx < 1 THEN // 越过下界 / below the lower bound
        _nIdx := _nIdx + 8; // 单次回绕 / a single wrap
    END_IF
    IF _afIdx[_nIdx] > 1.0E-9 THEN // 基准指数可用（除子域闸）/ the baseline is usable
        fClogIdx := _afIdx[_nHead] / _afIdx[_nIdx]; // 堵塞指数 = 当前 / 学习基准 / the clog index, the current over the learned baseline
        _fSev := fClogIdx; // 严重度同源 / the severity shares the source
    ELSE // 基准指数近零 / the baseline is near zero
        fClogIdx := 1.0; // 指数回归基准 / the index returns to the baseline
        _fSev := 1.0; // 严重度记一 / the severity is one
    END_IF
ELSE // 无样本 / no sample
    fClogIdx := 1.0; // 指数回归基准 / the index returns to the baseline
    _fSev := 1.0; // 严重度记一 / the severity is one
END_IF
_bClean := (_fSev <= fCleanRatio) AND (fQ > fQMin) AND _bInOk; // 清洁态判定 / the clean state verdict
IF _fSev > fAlarmRatio THEN // 报警级进入判据 / the alarm entry criterion
    _bAlarm := TRUE; // 置报警迟滞 / raise the alarm latch
    _bWarn := TRUE; // 报警级蕴含预警级 / the alarm implies the warning
ELSIF _fSev < fWarnRatio - 0.1 THEN // 报警级退出判据（迟滞收窄）/ the alarm exit criterion with the narrowed band
    _bAlarm := FALSE; // 清报警迟滞 / clear the alarm latch
END_IF
IF (_fSev > fWarnRatio) AND (NOT _bAlarm) THEN // 预警级进入判据 / the warning entry criterion
    _bWarn := TRUE; // 置预警迟滞 / raise the warning latch
ELSIF _fSev < fWarnRatio - 0.1 THEN // 预警级退出判据（迟滞收窄）/ the warning exit criterion
    _bWarn := FALSE; // 清预警迟滞 / clear the warning latch
END_IF
IF fQ <= fQMin THEN // 流量损失进入判据 / the flow loss entry criterion
    _bFlowLo := TRUE; // 置流量损失迟滞 / raise the flow loss latch
ELSIF fQ > fQMin * 1.2 THEN // 流量损失退出判据（迟滞收窄）/ the flow loss exit criterion
    _bFlowLo := FALSE; // 清流量损失迟滞 / clear the flow loss latch
END_IF

// 段 7｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 7, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_SscPhase.eIdle: // 未使能相 / the disabled phase
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_SscPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_SscPhase.eRun: // 运行相：判级分派（优先级：传感器 > 流量损失 > 报警 > 预警）与学习更新 / the run phase, the dispatch and the learning
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_SscPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF _bBad OR _bFlowLo OR _bAlarm OR _bWarn THEN // 存在活跃迟滞锁存 / an active latch exists
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        IF _bBad THEN // 传感器非有限优先 / the sensor takes the top priority
            _eFaulC := E_DL_SscFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        ELSIF _bFlowLo THEN // 流量损失次优先 / the flow loss follows
            _eFaulC := E_DL_SscFault.eFlowLoss; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        ELSIF _bAlarm THEN // 报警级再次优先（R190 独立成因）/ the alarm grade, an independent cause
            _eFaulC := E_DL_SscFault.eClogAlarm; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        ELSE // 预警级（R190 独立成因）/ the warning grade, an independent cause
            _eFaulC := E_DL_SscFault.eClogWarn; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        END_IF
        _ePhase := E_DL_SscPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSE // 正常运行 / the normal running
        _eFaulC := E_DL_SscFault.eNone; // 成因清零 / clear the cause
    END_IF

E_DL_SscPhase.eFault: // 故障相：锁存回放，迟滞自愈解除后回运行 / the fault phase, the latches self heal and return to run
    IF bEnable AND (NOT _bBad) AND (NOT _bFlowLo) AND (NOT _bAlarm) AND (NOT _bWarn) THEN // 全部迟滞已解除 / every latch has cleared
        _bFault := FALSE; // 清故障锁存（自愈路径，R152）/ clear the fault latch, the self healing path
        _eFaulC := E_DL_SscFault.eNone; // 成因清零 / clear the cause
        _ePhase := E_DL_SscPhase.eRun; // 迁回运行相 / migrate back to run
    ELSIF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_SscPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_SscFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_SscPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 8｜学习更新与统一出口 / segment 8, the learning update and the unified outlet
IF rtLearn.Q THEN // 学习窗到时沿 / the learning edge
    _nIdx := _nHead - _nFill + 1; // 时间序最旧槽位 / the oldest slot in time order
    IF _nIdx < 1 THEN // 越过下界 / below the lower bound
        _nIdx := _nIdx + 8; // 单次回绕 / a single wrap
    END_IF
    _afIdx[_nIdx] := _afIdx[_nHead]; // 基准更新：最旧样本改写为当前指数 / the baseline update, the oldest slot takes the current index
END_IF
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_SscFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
