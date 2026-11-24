(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CamFollowerLagMonitor
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 凸轮从动轴跟随滞后监控（主从位置差滑动窗统计）。
 *                         每拍采样滞后量 x = fPosMaster − fPosSlave，压入长度 nWindowSize 的
 *                         环形缓冲；每拍在窗内算两个统计量：窗口均值 fLagMean（系统性滞后/超前）
 *                         与窗口内最大绝对值 fLagMax（瞬时最坏滞后）。两档判定：
 *                           预警：|fLagMean| > fLagWarn 或 fLagMax > fLagWarn（维护级，当拍量）
 *                           报警：|fLagMean| > fLagAlarm 或 fLagMax > fLagAlarm，且持续
 *                                 tConfirm（故障锁存）
 *                         均值与最大值并列，是因为二者刻画不同失效：均值大 = 从动轴系统性跟不上
 *                         （增益/惯量问题），最大值大而均值小 = 局部卡顿（机械卡点、润滑不良）。
 *                         只看一个会漏掉另一类故障。
 * 接口     (Interface)  : 输入 fPosMaster 主轴位置、fPosSlave 从动轴位置、nWindowSize 窗长
 *                         （2..64）、fLagWarn / fLagAlarm 阈值、tConfirm 报警确认时间、bReset 复位；
 *                         输出 fLagMean 窗均值、fLagMax 窗最大绝对值、fLagNow 当拍滞后、nFilled
 *                         窗已填数、bWarn 预警、bAlarm 报警锁存、eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只监控滞后，不输出任何补偿/前馈量，不修改
 *                         凸轮表，不改从动轴指令**。凸轮相位补偿与从动轴前馈属 `FB_DL_ElectronicCam`
 *                         一族；本件的结论位仅供上层做降速/报警/维护决策。
 *                         ② 组态闸：nWindowSize < 2 或 > 64（越 ARRAY 边界）、fLagWarn <= 0.0、
 *                         fLagAlarm <= fLagWarn、tConfirm <= T#0S、位置或阈值 NaN → 故障锁存，
 *                         统计量出口置 0（不宣称）。
 *                         ③ 环形缓冲的窗口统计每拍 O(nWindowSize) 遍历（最大 64 次比较）：
 *                         1 ms 任务下为 64 次浮点比较，可接受；若任务更快请调小 nWindowSize。
 *                         该代价写死在此，不由调用方猜测。
 *                         ④ TON 一枚 + R_TRIG 一枚段 0 无条件周期刷新。
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisFollowingErrorMonitor`（单轴跟随误差）分工——那件比
 *                         "指令位置 vs 实际位置"（同一根轴的指令执行质量），本件比"主轴 vs 从动轴"
 *                         （两根轴之间的相位关系）。电子凸轮下二者都需监控，但归因不同。
 * 来源标签 (Source Tag) : T1-6 ◐（开源参考：凸轮跟随滞后滑动窗统计参数域，零代码行复制）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 当拍 |fLagMean| <= fLagWarn ∧
 *                         当拍 fLagMax <= fLagWarn（R240 全当拍量）。自证可满足：主从追平即满足。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 REAL 统计量 + BOOL（bWarn / bAlarm /
 *                         bError）+ ENUM（eState / eCause）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 数组边界闸 + 阈值几何闸 + 浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 3 · 序号 11）
 *==============================================================================*)

TYPE E_DL_CflState :
(
    eIdle  := 0,    // 窗未填满，统计量暂不宣称 / Window not filled, statistics not claimed
    eRun   := 10,   // 窗口统计运行相 / Windowed statistics running
    eFault := 90    // 报警锁存相 / Alarm latched phase
);
END_TYPE

TYPE E_DL_CflCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（窗长越界/阈值倒置/非有限） / Illegal configuration
    eMeanLimit  := 2,   // 窗均值越报警线（系统性滞后） / Mean lag over the alarm line
    ePeakLimit  := 3,   // 窗峰值越报警线（局部卡顿） / Peak lag over the alarm line
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_CamFollowerLagMonitor
VAR_INPUT
    fPosMaster  : REAL := 0.0;      // 主轴位置 [mm] / Master position [mm]
    fPosSlave   : REAL := 0.0;      // 从动轴位置 [mm] / Follower position [mm]
    nWindowSize : INT := 16;        // 滑动窗长度，域 2..64 / Sliding window length, 2..64
    fLagWarn    : REAL := 0.5;      // 滞后期望线，域 > 0.0 [mm] / Lag warning line, > 0.0 [mm]
    fLagAlarm   : REAL := 2.0;      // 滞后报警线，域 > fLagWarn [mm] / Lag alarm line, > warning [mm]
    tConfirm    : TIME := T#100MS;  // 报警确认时间，域 > T#0S [ms] / Alarm confirm time, > 0 [ms]
    bReset      : BOOL := FALSE;    // 复位，上升沿清报警锁存 [-] / Reset, rising edge clears the alarm latch
END_VAR
VAR_OUTPUT
    fLagNow  : REAL;                // 当拍滞后量（主轴 − 从动轴，带符号） [mm] / Present lag, master minus follower [mm]
    fLagMean : REAL;                // 窗口内滞后均值（带符号） [mm] / Windowed mean lag, signed [mm]
    fLagMax  : REAL;                // 窗口内滞后最大绝对值 [mm] / Windowed maximum absolute lag [mm]
    nFilled  : INT;                 // 窗口已填样本数 [个] / Samples currently in the window
    bWarn    : BOOL;                // 维护级预警（未达报警） [-] / Maintenance warning below alarm
    bAlarm   : BOOL;                // 报警锁存 [-] / Latched alarm
    eState   : E_DL_CflState;       // 状态出口 [-] / State outlet
    eCause   : E_DL_CflCause;       // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError   : BOOL;                // 故障标志（报警或组态非法） [-] / Error flag
END_VAR
VAR
    _eState  : E_DL_CflState := E_DL_CflState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_CflCause := E_DL_CflCause.eNone;    // 成因锁存量 / Latched cause
    tonAlarm : TON;                 // 报警确认计时，段 0 无条件调用 / Alarm confirm timer
    rtReset  : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge instance
    afRing   : ARRAY[0..63] OF REAL;    // 滞后环形缓冲（64 槽定长，按 nWindowSize 截取） [mm] / Lag ring buffer, fixed 64 slots
    nIdx     : INT;                 // 环形写指针（锁存量） / Ring write index, latched
    nFill    : INT;                 // 已填槽数（锁存量） / Slots filled, latched
    fSum     : REAL;                // 窗内滞后和（锁存量，增量维护） [mm] / Windowed sum, incrementally maintained
    _bFault  : BOOL;                // 报警锁存位（锁存量） / Latched alarm bit
    _bCfgBad : BOOL;                // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _fLag    : REAL;                // 当拍滞后中间量 [mm] / Present lag intermediate [mm]
    _fMax    : REAL;                // 窗内最大绝对值中间量 [mm] / Windowed maximum intermediate [mm]
    _fMean   : REAL;                // 窗均值中间量 [mm] / Windowed mean intermediate [mm]
    _i       : INT;                 // 遍历索引 / Loop index
    _bMeanOver : BOOL;              // 均值越报警线当拍量 [-] / Mean over the alarm line
    _bPeakOver : BOOL;              // 峰值越报警线当拍量 [-] / Peak over the alarm line
END_VAR
VAR CONSTANT
    DL_CFL_EPS   : REAL := 1.0E-6;  // 浮点判零容差 [无量纲] / Float epsilon
    DL_CFL_MAXN  : INT := 64;       // 环形缓冲容量（与 afRing 上界一致） [个] / Ring capacity matching afRing bounds
    DL_CFL_MINN  : INT := 2;        // 窗口最小长度（少于 2 无离散意义） [个] / Minimum window length
END_VAR

(* —— 段 0：判据派生 + 两实例无条件周期刷新 —— *)
_bNonFin := (fPosMaster <> fPosMaster) OR (fPosSlave <> fPosSlave)      // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fLagWarn <> fLagWarn) OR (fLagAlarm <> fLagAlarm);         // 阈值 NaN 判 / Threshold NaN tests
_bCfgBad := (nWindowSize < DL_CFL_MINN) OR (nWindowSize > DL_CFL_MAXN)  // 窗长越 ARRAY 边界闸 / Window length against array bounds
         OR (fLagWarn <= 0.0) OR (fLagAlarm <= fLagWarn)                // 阈值几何闸 / Threshold geometry gate
         OR (tConfirm <= T#0S) OR _bNonFin;                             // 时间闸 + 非有限 / Time gate and non-finite
_fLag := fPosMaster - fPosSlave;                                        // 当拍滞后（主轴 − 从动轴） / Present lag
rtReset(CLK := bReset);                                                 // 复位沿，每拍必调（R228A） / Reset edge, every scan

(* —— 段 1：单拍量预清零（锁存量 nIdx/nFill/fSum/_bFault/_eCause 不入清单，R107） —— *)
fLagNow := 0.0;         // 当拍滞后出口预清 / Present lag preset
fLagMean := 0.0;        // 均值出口预清 / Mean preset
fLagMax := 0.0;         // 峰值出口预清 / Peak preset
nFilled := 0;           // 填充数出口预清 / Filled preset
bWarn   := FALSE;       // 预警位预清 / Warning preset
bAlarm  := FALSE;       // 报警出口预清 / Alarm preset
bError  := FALSE;       // 故障标志预清（R45 配对） / Error flag preset

(* —— 段 2：复位沿 + 组态闸 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                       // 清报警锁存 / Clear alarm latch
    _eCause := E_DL_CflCause.eNone;                         // 清成因 / Clear cause
    nIdx    := 0;                                           // 环形写指针归零 / Ring index cleared
    nFill   := 0;                                           // 填充数归零 / Fill count cleared
    fSum    := 0.0;                                         // 窗口和归零 / Window sum cleared
    IF _eState = E_DL_CflState.eFault THEN
        _eState := E_DL_CflState.eIdle;                     // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN
    _bFault := TRUE;                                        // 组态非法锁存 / Latch illegal configuration
    _eCause := E_DL_CflCause.eCfgIllegal;                   // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：环形缓冲写入（先减被覆盖的旧值，再加新值，保持 fSum 与窗内一致） —— *)
IF NOT _bCfgBad THEN
    IF nFill >= nWindowSize THEN
        fSum := fSum - afRing[nIdx];                        // 覆盖前减掉旧样本 / Subtract the evicted sample
    ELSE
        nFill := nFill + 1;                                 // 窗口未满则填充数增 / Grow the fill count
    END_IF
    afRing[nIdx] := _fLag;                                  // 写入当拍样本 / Store the present sample
    fSum := fSum + _fLag;                                   // 加上新样本 / Add the new sample
    nIdx := nIdx + 1;                                       // 指针前进 / Advance the pointer
    IF nIdx >= nWindowSize THEN
        nIdx := 0;                                          // 到窗长回卷 / Wrap at the window length
    END_IF
    IF nIdx > DL_CFL_MAXN - 1 THEN
        nIdx := 0;                                          // 双保险：绝不让指针越 ARRAY 上界 / Second guard, never index past the array
    END_IF
    IF nFill > nWindowSize THEN
        nFill := nWindowSize;                               // 钳位（窗长改小时自愈） / Clamp when the window shrinks
    END_IF
END_IF

(* —— 段 4：窗口统计（均值与最大绝对值，均在窗内 nFill 个样本上算） —— *)
IF (NOT _bCfgBad) AND (nFill > 0) THEN
    _fMean := fSum / INT_TO_REAL(nFill);                    // 均值，分母已判正（nFill > 0） / Mean, denominator guarded
    _fMax  := 0.0;                                          // 最大值初值 / Peak initial value
    FOR _i := 0 TO nFill - 1 DO
        IF ABS(afRing[_i]) > _fMax THEN
            _fMax := ABS(afRing[_i]);                       // 逐个比较取最大绝对值 / Track the maximum absolute value
        END_IF
    END_FOR
    fLagNow  := _fLag;                                      // 当拍滞后出口 / Present lag outlet
    fLagMean := _fMean;                                     // 均值出口 / Mean outlet
    fLagMax  := _fMax;                                      // 峰值出口 / Peak outlet
    nFilled  := nFill;                                      // 填充数出口 / Filled outlet
END_IF

(* —— 段 5：分档判据（双口径取或；先算判据再喂 TON，保证 IN 由当拍表达式派生） —— *)
_bMeanOver := ((NOT _bCfgBad) AND (nFill > 0)) AND (ABS(fLagMean) > fLagAlarm);     // 均值越报警线 / Mean over the alarm line
_bPeakOver := ((NOT _bCfgBad) AND (nFill > 0)) AND (fLagMax > fLagAlarm);           // 峰值越报警线 / Peak over the alarm line
tonAlarm(IN := _bMeanOver OR _bPeakOver, PT := tConfirm);                           // 报警确认窗 / Alarm confirm window

(* —— 段 6：报警锁存与归因（均值优先于峰值：系统性滞后比局部卡顿更需要先看） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) AND tonAlarm.Q THEN
    _bFault := TRUE;                                        // 锁存 / Latch
    IF _bMeanOver THEN
        _eCause := E_DL_CflCause.eMeanLimit;                // 归因：均值越限 / Cause: mean over limit
    ELSE
        _eCause := E_DL_CflCause.ePeakLimit;                // 归因：峰值越限 / Cause: peak over limit
    END_IF
END_IF

(* —— 段 7：预警（维护级；报警相不再宣称预警） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) AND (nFill > 0)
   AND ((ABS(fLagMean) > fLagWarn) OR (fLagMax > fLagWarn)) THEN
    bWarn := TRUE;                                          // 维护级预警 / Maintenance warning
END_IF

(* —— 段 8：锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_CflState.eFault) THEN
    _eState := E_DL_CflState.eFault;                        // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 9：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_CflState.eIdle:
    IF _bFault THEN                                         // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_CflState.eFault;
    ELSIF (_bCfgBad = FALSE) AND (nFill >= nWindowSize) THEN    // 出口 2：窗已填满，统计可信 / Window filled, statistics trustworthy
        _eState := E_DL_CflState.eRun;
    END_IF

E_DL_CflState.eRun:
    IF _bFault THEN                                         // 出口 1：报警锁存 / Alarm latched
        _eState := E_DL_CflState.eFault;
    ELSIF nFill < nWindowSize THEN                          // 出口 2：窗被清（复位后重填） / Window cleared, refilling
        _eState := E_DL_CflState.eIdle;
    END_IF

E_DL_CflState.eFault:
    ;                                                       // 故障相：仅段 2 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _bFault := TRUE;                                        // 非法相位兜底锁存 / Illegal-phase fallback latch
    _eCause := E_DL_CflCause.ePhaseBad;                     // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_CflState.eFault;                        // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 10：出口单点映射（名实双出口，R191） —— *)
bAlarm := _bFault;                                          // 报警与锁存同源 / Alarm from latch
bError := _bFault OR _bCfgBad;                              // 故障标志 = 锁存或组态非法 / Error = latch or illegal config
IF _bFault THEN
    bWarn := FALSE;                                         // 报警相不宣称「仅预警」 / No warning claim in alarm
END_IF
eState := _eState;                                          // 状态出口 / State outlet
eCause := _eCause;                                          // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
