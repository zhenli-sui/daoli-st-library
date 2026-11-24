(*
  ==================================================================
  组件名 Component  : FB_DL_HotRunnerZoneBalance
  分类   Category   : DL_Process
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 热流道 8 区温度平衡监视。逐区算实测与设定偏差，输出最大偏差
                      区号、最大偏差与平均偏差；区偏差越限（高 / 低双向独立成因，
                      R190）与掉线（温度低于环境 + 阈值，或变化率异常）三判据带
                      迟滞防抖；传感器非有限判 eSensorBad 并锁存至复位沿。
  来源   Source     : t2-2-lbp
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；多区温度均衡分级为
                      通用热流道工艺语义，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（ARRAY / LREAL 运算，无私有库、无定时器实例）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做平衡判级，不调区功率、不做温控闭环（属主边界）；
                      二 判据方向性（R146）：偏高与偏低为同量纲双向异常，成因独立
                         分派（R190 归因唯一）；
                      三 迟滞口径：进入判据用全带宽 fDevLim，退出判据收窄 fHyst；
                      四 变化率异常判据除子为 fDtS（组态闸证 > 0）；fDtS <= 0 时
                         该判据自动失效并置 eSensorBad（组态域闸承载）；
                      五 传感器非有限锁存解除路径 = bReset 上升沿；偏差类迟滞锁存
                         自愈解除（进入判据反向 + 收窄带）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      nMaxDevZone 为最大绝对偏差区号（1..8，全部无效时为 0）；
                      bBalanced 为迟滞派生输出；eFault 为锁存回放；
                      ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 3 · 序号 14）
  ==================================================================
*)

TYPE E_DL_HzbPhase :
(
    eIdle  := 0,  // 未使能：监视停摆 / disabled, the watch is idle
    eRun   := 10, // 运行：逐拍判级 / running, graded every scan
    eFault := 90  // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_HzbFault :
(
    eNone        := 0, // 无成因 / no cause
    eZoneDevHigh := 1, // 区偏差偏高尚限（故障级，与 bError 配对）/ a zone deviation is high, fault grade paired with bError
    eZoneDevLow  := 2, // 区偏差偏低于限（故障级，与 bError 配对）/ a zone deviation is low, fault grade paired with bError
    eZoneDropout := 3, // 区掉线：温度低于环境阈值或变化率异常（故障级，与 bError 配对）/ a zone dropped out, fault grade paired with bError
    eSensorBad   := 4, // 温度非有限（故障级，与 bError 配对）/ a temperature is non finite, fault grade paired with bError
    ePhaseBad    := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_HotRunnerZoneBalance
VAR_INPUT
    bEnable   : BOOL := TRUE;  // 使能，失能时监视停摆 [-] / enable, the watch stops when disabled
    bReset    : BOOL := FALSE; // 复位上升沿清全部锁存 [-] / reset rising edge clears every latch
    afTemp    : ARRAY[1..8] OF LREAL := [8(0.0)]; // 8 区实测温度 [摄氏度] / the measured temperatures of eight zones [degree celsius]
    afSetp    : ARRAY[1..8] OF LREAL := [8(200.0)]; // 8 区设定温度 [摄氏度] / the setpoints of eight zones [degree celsius]
    fDevLim   : LREAL := 10.0; // 区偏差判据带宽（绝对量）[开尔文] / the zone deviation band [kelvin]
    fHyst     : LREAL := 2.0;  // 迟滞带宽 [开尔文]，域 0..判据带宽 / the hysteresis band [kelvin], inside the band
    fAmbC     : LREAL := 25.0; // 环境温度 [摄氏度] / the ambient temperature [degree celsius]
    fDropMarg : LREAL := 30.0; // 掉线温度阈值（环境 + 裕度）[开尔文] / the dropout threshold above ambient [kelvin]
    fRateMax  : LREAL := 50.0; // 变化率异常阈值 [开尔文每秒] / the rate anomaly threshold [kelvin per second]
    fDtS      : LREAL := 1.0;  // 调用周期 [秒]，域 大于零 / the call period [second], domain above zero
END_VAR
VAR_OUTPUT
    nMaxDevZone: INT := 0;    // 最大偏差区号（1..8，全部无效为 0）[区号] / the maximum deviation zone number [zone]
    fMaxDev    : LREAL := 0.0; // 最大偏差绝对量 [开尔文] / the maximum deviation magnitude [kelvin]
    fMeanDev   : LREAL := 0.0; // 平均偏差（带符号）[开尔文] / the mean deviation, signed [kelvin]
    bBalanced  : BOOL := FALSE; // 平衡（迟滞派生输出）[-] / the balance, a hysteresis derived outlet
    ePhase     : E_DL_HzbPhase := E_DL_HzbPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault     : E_DL_HzbFault := E_DL_HzbFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError     : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset   : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    _ePhase   : E_DL_HzbPhase := E_DL_HzbPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC   : E_DL_HzbFault := E_DL_HzbFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault   : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit    : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgOk   : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bHigh    : BOOL := FALSE; // 偏高迟滞锁存 [-] / the high deviation hysteresis latch
    _bLow     : BOOL := FALSE; // 偏低迟滞锁存 [-] / the low deviation hysteresis latch
    _bDrop    : BOOL := FALSE; // 掉线迟滞锁存 [-] / the dropout hysteresis latch
    _bBad     : BOOL := FALSE; // 传感器非有限锁存 [-] / the sensor bad latch
    _nZoneMax : INT := 0;      // 最大偏差区号工作值 [区号] / the maximum deviation zone working value
    _nI       : INT := 1;      // 区游标 [区] / the zone cursor
    _nGuard   : INT := 0;      // 扫描守护计数 [次] / the scan guard [count]
    _fDev     : LREAL := 0.0;  // 本区偏差工作值 [开尔文] / this zone deviation working value [kelvin]
    _fMax     : LREAL := 0.0;  // 最大偏差绝对量工作值 [开尔文] / the maximum deviation working value [kelvin]
    _fSum     : LREAL := 0.0;  // 偏差和（带符号）[开尔文] / the deviation sum, signed [kelvin]
    _nValid   : INT := 0;      // 有效区计数 [区] / the valid zone count [zone]
    _afTPrev  : ARRAY[1..8] OF LREAL := [8(0.0)]; // 上拍各区温度快照 [摄氏度] / the previous scan temperature snapshots [degree celsius]
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detector
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_HzbPhase.eRun; // 相位从运行起步 / the phase starts in run
    _eFaulC := E_DL_HzbFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nI := 1; // 区游标起步 / start the zone cursor
    WHILE _nI <= 8 DO // 快照取当拍 / the snapshots take this scan
        _afTPrev[_nI] := afTemp[_nI]; // 快照推进 / advance the snapshot
        _nI := _nI + 1; // 游标递增 / increment the cursor
    END_WHILE
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清快照（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_HzbFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _bHigh := FALSE; // 作用域一：清偏高迟滞 / scope one, clear the high latch
    _bLow := FALSE; // 作用域一：清偏低迟滞 / scope one, clear the low latch
    _bDrop := FALSE; // 作用域一：清掉线迟滞 / scope one, clear the dropout latch
    _bBad := FALSE; // 作用域一：清传感器锁存 / scope one, clear the sensor latch
    _ePhase := E_DL_HzbPhase.eRun; // 作用域二：迁回运行相 / scope two, migrate back to run
    _nI := 1; // 作用域三：快照重取 / scope three, retake the snapshots
    WHILE _nI <= 8 DO // 快照取当拍 / the snapshots take this scan
        _afTPrev[_nI] := afTemp[_nI]; // 快照推进 / advance the snapshot
        _nI := _nI + 1; // 游标递增 / increment the cursor
    END_WHILE
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, the configuration domain gate
_bCfgOk := (fDevLim > 0.0) AND (fDevLim = fDevLim) AND (fHyst >= 0.0) AND (fHyst <= fDevLim) AND (fAmbC = fAmbC) AND (fDropMarg >= 0.0) AND (fDropMarg = fDropMarg) AND (fRateMax > 0.0) AND (fRateMax = fRateMax) AND (fDtS > 0.0) AND (fDtS = fDtS); // 组态参数域判定 / the configuration domain verdict

// 段 4｜逐区扫描：偏差统计 + 双向迟滞 + 掉线判据（R146 方向分列）/ segment 4, the per zone scan with the direction split verdicts
_nZoneMax := 0; // 最大偏差区号预置零 / preset the zone number to zero
_fMax := 0.0; // 最大偏差预置零 / preset the maximum to zero
_fSum := 0.0; // 偏差和预置零 / preset the sum to zero
_nValid := 0; // 有效区计数预置零 / preset the valid count to zero
_nI := 1; // 区游标起步 / start the zone cursor
_nGuard := 0; // 守护清零 / clear the guard
WHILE (_nI <= 8) AND (_nGuard < 8) DO // 八区固定扫描，守护为容量 / the fixed eight zone scan with the capacity guard
    _nGuard := _nGuard + 1; // 守护递增 / increment the guard
    IF (afTemp[_nI] = afTemp[_nI]) AND ((afTemp[_nI] - afTemp[_nI]) = (afTemp[_nI] - afTemp[_nI])) AND (_bCfgOk) THEN // 本区温度有限且组态合法 / this zone temperature is finite and the config is legal
        _nValid := _nValid + 1; // 有效区计数递增 / increment the valid count
        _fDev := afTemp[_nI] - afSetp[_nI]; // 本区偏差 / this zone deviation
        _fSum := _fSum + _fDev; // 偏差和累计 / accumulate the sum
        IF ABS(_fDev) > _fMax THEN // 最大偏差刷新 / refresh the maximum
            _fMax := ABS(_fDev); // 更新最大值 / update the maximum
            _nZoneMax := _nI; // 记录区号 / record the zone number
        END_IF
        IF _fDev > fDevLim THEN // 偏高进入判据 / the high entry criterion
            _bHigh := TRUE; // 置偏高迟滞 / raise the high latch
        ELSIF _fDev < fDevLim - fHyst THEN // 偏高退出判据（迟滞收窄）/ the high exit criterion
            _bHigh := FALSE; // 清偏高迟滞 / clear the high latch
        END_IF
        IF _fDev < -fDevLim THEN // 偏低进入判据（方向分列，R146）/ the low entry criterion, the direction split
            _bLow := TRUE; // 置偏低迟滞 / raise the low latch
        ELSIF _fDev > -fDevLim + fHyst THEN // 偏低退出判据（迟滞收窄）/ the low exit criterion
            _bLow := FALSE; // 清偏低迟滞 / clear the low latch
        END_IF
        IF (afTemp[_nI] < fAmbC + fDropMarg) OR (ABS(afTemp[_nI] - _afTPrev[_nI]) > fRateMax * fDtS) THEN // 掉线判据：低于环境阈值或变化率异常（除子无，乘法无除零）/ the dropout criteria, a low reading or a rate anomaly
            _bDrop := TRUE; // 置掉线迟滞 / raise the dropout latch
        ELSIF (afTemp[_nI] > fAmbC + fDropMarg + fHyst) AND (ABS(afTemp[_nI] - _afTPrev[_nI]) <= fRateMax * fDtS) THEN // 掉线退出判据（迟滞收窄）/ the dropout exit criterion with the narrowed band
            _bDrop := FALSE; // 清掉线迟滞 / clear the dropout latch
        END_IF
    ELSE // 本区温度非有限 / this zone temperature is non finite
        _bBad := TRUE; // 置传感器非有限锁存 / raise the sensor bad latch
    END_IF
    _afTPrev[_nI] := afTemp[_nI]; // 快照推进（无论有效与否，防恢复时变化率踢）/ advance the snapshot against a rate kick on recovery
    _nI := _nI + 1; // 游标递增 / increment the cursor
END_WHILE
IF _nValid > 0 THEN // 有有效区才出均值 / the mean needs at least one valid zone
    fMeanDev := _fSum / INT_TO_LREAL(_nValid); // 平均偏差，除子已证大于零 / the mean deviation with a proven divisor
ELSE // 全区无效 / every zone is void
    fMeanDev := 0.0; // 均值记零 / the mean is zeroed
END_IF
fMaxDev := _fMax; // 最大偏差出口 / the maximum deviation outlet
nMaxDevZone := _nZoneMax; // 最大偏差区号出口 / the zone number outlet
bBalanced := (NOT _bHigh) AND (NOT _bLow) AND (NOT _bDrop) AND (NOT _bBad); // 平衡输出（迟滞派生）/ the balance outlet derived from the latches

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_HzbPhase.eIdle: // 未使能相 / the disabled phase
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_HzbPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_HzbPhase.eRun: // 运行相：判级分派（优先级固定：传感器 > 掉线 > 偏高 > 偏低）/ the run phase, the dispatch with a fixed priority
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_HzbPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF _bBad OR _bDrop OR _bHigh OR _bLow THEN // 存在活跃迟滞锁存 / an active latch exists
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        IF _bBad THEN // 传感器非有限优先 / the sensor takes the top priority
            _eFaulC := E_DL_HzbFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        ELSIF _bDrop THEN // 掉线次优先 / the dropout follows
            _eFaulC := E_DL_HzbFault.eZoneDropout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        ELSIF _bHigh THEN // 偏高再次优先（R190 独立成因）/ the high deviation, an independent cause
            _eFaulC := E_DL_HzbFault.eZoneDevHigh; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        ELSE // 偏低（R190 独立成因）/ the low deviation, an independent cause
            _eFaulC := E_DL_HzbFault.eZoneDevLow; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        END_IF
        _ePhase := E_DL_HzbPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSE // 全部在带内，撤销信息级 / everything inside the band, the cause is revoked
        _eFaulC := E_DL_HzbFault.eNone; // 成因清零 / clear the cause
    END_IF

E_DL_HzbPhase.eFault: // 故障相：锁存回放，偏差类锁存自愈解除（迟滞反向）后自动回运行 / the fault phase, the deviation latches self heal and return to run
    IF bEnable AND (NOT _bBad) AND (NOT _bDrop) AND (NOT _bHigh) AND (NOT _bLow) THEN // 全部迟滞已解除 / every latch has cleared
        _bFault := FALSE; // 清故障锁存（自愈解除路径，R152）/ clear the fault latch, the self healing path
        _eFaulC := E_DL_HzbFault.eNone; // 成因清零 / clear the cause
        _ePhase := E_DL_HzbPhase.eRun; // 迁回运行相 / migrate back to run
    ELSIF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_HzbPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_HzbFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_HzbPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜统一出口 / segment 6, the unified outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_HzbFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
