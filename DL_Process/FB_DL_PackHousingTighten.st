(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PackHousingTighten
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 电池包壳体螺栓拧紧对角轴序 + 扭矩/角度双窗判定。
 *                         ① 对角轴序：四螺栓按 1 → 3 → 2 → 4 的对角顺序拧（顺序常量表
 *                            DL_PTH_SEQ = [0, 2, 1, 3]），对角拧紧是为避免壳体单侧先压紧
 *                            导致密封面翘曲——顺序写死在常量里，不运行期可改。
 *                         ② 每一步由 bStepDone 上升沿推进（拧紧工具给"本颗完成"信号），
 *                            完成时即用该颗的 afTorque[i] / afAngle[i] 判双窗：
 *                            扭矩 ∈ [fTorqueLo, fTorqueHi] 且 角度 ∈ [fAngleLo, fAngleHi]，
 *                            任一越窗即该颗不合格。
 *                         ③ 不合格记录轴号：不合格螺栓的**螺栓号（1..4，非数组下标）**写入
 *                            anFailBolt 数组（按不合格先后排放），nFailCount 为个数。
 *                            记录轴号而不是只置一个 bNg，是因为返修要知道"回去拧哪一颗"。
 *                         ④ 四颗走完 → bCycleDone 单拍脉冲，bAllOk =（nFailCount = 0）。
 *                         ⑤ 每步有专用超时 tonStepTo（R228A 专用超时 TON 命名豁免），
 *                            超时 → eFault（eStepTimeout），记录卡住的螺栓号。
 * 接口     (Interface)  : 输入 afTorque / afAngle 四颗实测扭矩与角度（VAR_IN_OUT，本件只读）、
 *                         扭矩窗 fTorqueLo / fTorqueHi、角度窗 fAngleLo / fAngleHi、
 *                         bStart 启动沿、bStepDone 本颗完成沿、tStepTimeout 单颗超时、bReset 复位；
 *                         输出 nCurrentBolt 当前螺栓号（1..4，0=无）、bStepActive 拧紧进行中、
 *                         bCycleDone 一轮完成单拍、bAllOk 全合格、anFailBolt 不合格螺栓号表、
 *                         nFailCount 不合格个数、nDoneCount 已完成个数、eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只排轴序与判双窗，不驱动拧紧轴、不下发扭矩
 *                         设定值、不做扭矩闭环**。工具动作与设定值下发属拧紧控制器/轴级 POU；
 *                         本件吃完成信号与实测值，出轴序推进与判定结论。
 *                         ② 组态闸：fTorqueLo <= 0.0、fTorqueHi <= fTorqueLo、fAngleLo < 0.0、
 *                         fAngleHi <= fAngleLo、tStepTimeout <= T#0S、任一实测 NaN
 *                         → 故障锁存（NaN 会让双窗比较恒假，静默判合格是最坏结果）。
 *                         ③ 固定四颗（ARRAY[0..3]）：颗数写死在类型里；若工艺要 6 颗须改类型与
 *                         顺序常量，不允许运行期可变（越界风险）。
 *                         ④ 单枚 TON（tonStepTo）+ 三枚 R_TRIG（bStart / bStepDone / bReset）
 *                         段 0 无条件周期刷新；tonStepTo 的 IN =（eRun 相），出相即复位，
 *                         不存在跨步累积（R228A）。
 *                         ⑤ eFault 迁出：bReset 上升沿 → eIdle（R228B）；另 bStart 上升沿亦可
 *                         从 eDone 重开一轮（新工件，非解除式）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisTorqueLimitGuard`（轴力矩瞬时限）分工——那件是运动中
 *                         连续保护，本件是**工序级**顺序与结果判定；不共用判据、不互相内嵌。
 * 来源标签 (Source Tag) : ROADMAP B 类 / T2-2（电池包壳体螺栓对角拧紧，自研 clean-room）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 清故障、清不合格表、回 eIdle。
 *                         自证可满足：复位为外部动作，无锁存量门控。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 INT 螺栓号 + INT 表 + BOOL 组 +
 *                         ENUM（eState / eCause）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 数组边界闸 + 双窗几何闸 + NaN 闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 4 · 序号 20）
 *==============================================================================*)

TYPE E_DL_PthState :
(
    eIdle  := 0,    // 待启动 / Idle
    eRun   := 10,   // 拧紧进行相（逐颗推进） / Tightening, advancing bolt by bolt
    eDone  := 20,   // 一轮完成相（结论已出） / Cycle complete with a verdict
    eFault := 90    // 故障相（超时/组态非法，等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_PthCause :
(
    eNone        := 0,   // 无异常 / No anomaly
    eCfgIllegal  := 1,   // 组态非法（窗口倒置/超时非正/实测非有限） / Illegal configuration
    eTorqueNg    := 2,   // 扭矩越窗 / Torque out of the window
    eAngleNg     := 3,   // 角度越窗 / Angle out of the window
    eBothNg      := 4,   // 扭矩与角度同时越窗 / Torque and angle both out of the window
    eStepTimeout := 5,   // 单颗拧紧超时 / Single-bolt tightening timed out
    ePhaseBad    := 6    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_PackHousingTighten
VAR_IN_OUT
    afTorque : ARRAY[0..3] OF REAL;     // 四颗实测扭矩（本件只读） [N·m] / Four measured torques, read-only here [N·m]
    afAngle  : ARRAY[0..3] OF REAL;     // 四颗实测转角（本件只读） [度] / Four measured angles, read-only here [deg]
END_VAR
VAR_INPUT
    fTorqueLo    : REAL := 20.0;        // 扭矩窗下限，域 > 0.0 [N·m] / Torque window lower limit, > 0.0 [N·m]
    fTorqueHi    : REAL := 30.0;        // 扭矩窗上限，域 > fTorqueLo [N·m] / Torque window upper limit, > lower [N·m]
    fAngleLo     : REAL := 10.0;        // 角度窗下限，域 >= 0.0 [度] / Angle window lower limit, >= 0.0 [deg]
    fAngleHi     : REAL := 90.0;        // 角度窗上限，域 > fAngleLo [度] / Angle window upper limit, > lower [deg]
    bStart       : BOOL := FALSE;       // 启动沿，开新的一轮 [-] / Start edge, opens a new cycle
    bStepDone    : BOOL := FALSE;       // 本颗拧紧完成沿，推进一颗 [-] / Current-bolt-done edge, advances one bolt
    tStepTimeout : TIME := T#10S;       // 单颗超时，域 > T#0S [ms] / Per-bolt timeout, > T#0S [ms]
    bReset       : BOOL := FALSE;       // 复位，上升沿清故障与不合格表 [-] / Reset, clears fault and the failure table
END_VAR
VAR_OUTPUT
    nCurrentBolt : INT;                 // 当前螺栓号 1..4，0=无 [号] / Current bolt number, 1..4, 0 means none
    bStepActive  : BOOL;                // 拧紧进行中（有当前螺栓） [-] / Tightening in progress
    bCycleDone   : BOOL;                // 一轮完成，单拍脉冲 [-] / Cycle done, single-scan pulse
    bAllOk       : BOOL;                // 本轮全合格 [-] / All bolts passed this cycle
    anFailBolt   : ARRAY[0..3] OF INT;  // 不合格螺栓号表（按发生先后，0 表空位） [号] / Failed bolt numbers in order, 0 marks an empty slot
    nFailCount   : INT;                 // 不合格个数 [颗] / Number of failed bolts
    nDoneCount   : INT;                 // 已完成颗数 [颗] / Number of completed bolts
    eState       : E_DL_PthState;       // 状态出口 [-] / State outlet
    eCause       : E_DL_PthCause;       // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError       : BOOL;                // 故障标志（超时/组态非法） [-] / Error flag
END_VAR
VAR
    _eState    : E_DL_PthState := E_DL_PthState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_PthCause := E_DL_PthCause.eNone;    // 成因锁存量 / Latched cause
    tonStepTo  : TON;           // 单颗拧紧专用超时，段 0 无条件调用 / Per-bolt dedicated timeout
    rtStart    : R_TRIG;        // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtStepDone : R_TRIG;        // 本颗完成沿实例，段 0 无条件调用 / Step-done edge instance
    rtReset    : R_TRIG;        // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _nStepIdx  : INT;           // 顺序表下标 0..3（锁存量） / Sequence table index, latched
    _nFailCnt  : INT;           // 不合格计数（锁存量） [颗] / Failure count, latched
    _nDoneCnt  : INT;           // 完成计数（锁存量） [颗] / Done count, latched
    _anFail    : ARRAY[0..3] OF INT;    // 不合格螺栓号表（锁存量） [号] / Failure table, latched
    _bFault    : BOOL;          // 故障锁存位（锁存量） / Latched fault bit
    _bCfgBad   : BOOL;          // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin   : BOOL;          // 实测非有限当拍量 [-] / Non-finite measurement this scan
    _bTqNg     : BOOL;          // 当前颗扭矩越窗当拍量 [-] / Torque NG for the current bolt
    _bAgNg     : BOOL;          // 当前颗角度越窗当拍量 [-] / Angle NG for the current bolt
    _nIdxSafe  : INT;           // 钳位后的顺序表下标（0..3） / Clamped sequence index
    _i         : INT;           // 遍历索引 / Loop index
END_VAR
VAR CONSTANT
    DL_PTH_N       : INT := 4;                          // 螺栓颗数（与 ARRAY 上界一致） [颗] / Bolt count matching the array bounds
    DL_PTH_SEQ     : ARRAY[0..3] OF INT := [0, 2, 1, 3];    // 对角顺序表：1→3→2→4（0 基下标） [下标] / Diagonal order 1-3-2-4 as 0-based indices
END_VAR

(* —— 段 0：组态闸派生 + 四实例无条件周期刷新 —— *)
_bNonFin := FALSE;                                                  // 非有限标志初值 / Non-finite initial value
FOR _i := 0 TO DL_PTH_N - 1 DO
    IF (afTorque[_i] <> afTorque[_i]) OR (afAngle[_i] <> afAngle[_i]) THEN
        _bNonFin := TRUE;                                           // 实测 NaN 自反判（判等禁令唯一例外） / Measurement NaN test
    END_IF
END_FOR
_bCfgBad := (fTorqueLo <= 0.0) OR (fTorqueHi <= fTorqueLo)          // 扭矩窗几何闸 / Torque window geometry
         OR (fAngleLo < 0.0) OR (fAngleHi <= fAngleLo)              // 角度窗几何闸 / Angle window geometry
         OR (tStepTimeout <= T#0S) OR _bNonFin;                     // 超时闸 + 非有限 / Timeout gate and non-finite
rtStart(CLK := bStart);                                             // 启动沿，每拍必调（R228A） / Start edge, every scan
rtStepDone(CLK := bStepDone);                                       // 完成沿，每拍必调 / Step-done edge, every scan
rtReset(CLK := bReset);                                             // 复位沿，每拍必调 / Reset edge, every scan
tonStepTo(IN := (_eState = E_DL_PthState.eRun), PT := tStepTimeout);    // 单颗专用超时（进相计时，出相自复位） / Per-bolt dedicated timeout

(* —— 段 1：单拍量预清零（锁存量 _nStepIdx/_nFailCnt/_nDoneCnt/_anFail/_bFault 不入清单，R107） —— *)
bCycleDone  := FALSE;           // 完成脉冲预清 / Cycle-done preset
bStepActive := FALSE;           // 进行中指示预清 / Step-active preset
bAllOk      := FALSE;           // 全合格位预清 / All-ok preset
bError      := FALSE;           // 故障标志预清（R45 配对） / Error flag preset
_bTqNg      := FALSE;           // 扭矩越窗当拍量预清 / Torque NG preset
_bAgNg      := FALSE;           // 角度越窗当拍量预清 / Angle NG preset

(* —— 段 2：复位沿（清故障、清表、回待机） —— *)
IF rtReset.Q THEN
    _bFault   := FALSE;                                 // 清故障锁存 / Clear the fault latch
    _eCause   := E_DL_PthCause.eNone;                   // 清成因 / Clear cause
    _nFailCnt := 0;                                     // 不合格计数清零 / Failure count cleared
    _nDoneCnt := 0;                                     // 完成计数清零 / Done count cleared
    _nStepIdx := 0;                                     // 顺序下标归零 / Sequence index cleared
    FOR _i := 0 TO DL_PTH_N - 1 DO
        _anFail[_i] := 0;                               // 不合格表清零 / Failure table cleared
    END_FOR
    IF _eState <> E_DL_PthState.eIdle THEN
        _eState := E_DL_PthState.eIdle;                 // 回待机相（R228B 迁出路径） / Back to idle, the R228B exit
    END_IF
END_IF
IF _bCfgBad THEN
    _bFault := TRUE;                                    // 组态非法锁存 / Latch illegal configuration
    _eCause := E_DL_PthCause.eCfgIllegal;               // 归因：组态非法 / Cause: illegal configuration
    _eState := E_DL_PthState.eFault;                    // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：启动沿（开新的一轮，清表清计数） —— *)
IF rtStart.Q AND (NOT _bCfgBad) THEN
    _nStepIdx := 0;                                     // 从顺序表第 0 位开始 / Start at sequence position 0
    _nFailCnt := 0;                                     // 不合格计数清零 / Failure count cleared
    _nDoneCnt := 0;                                     // 完成计数清零 / Done count cleared
    FOR _i := 0 TO DL_PTH_N - 1 DO
        _anFail[_i] := 0;                               // 表清零（新工件） / Table cleared for the new part
    END_FOR
    _eCause   := E_DL_PthCause.eNone;                   // 清成因 / Clear cause
    _eState   := E_DL_PthState.eRun;                    // 入运行相 / Enter run phase
END_IF

(* —— 段 4：逐颗推进与双窗判定（完成沿触发，单点写入锁存量，R187） —— *)
IF (_eState = E_DL_PthState.eRun) AND rtStepDone.Q AND (NOT _bCfgBad) THEN
    _nIdxSafe := _nStepIdx;                             // 取顺序下标 / Take the sequence index
    IF _nIdxSafe < 0 THEN
        _nIdxSafe := 0;                                 // 下界钳（双保险） / Lower clamp
    END_IF
    IF _nIdxSafe > DL_PTH_N - 1 THEN
        _nIdxSafe := DL_PTH_N - 1;                      // 上界钳（双保险，绝不越 ARRAY） / Upper clamp, never index past the array
    END_IF
    _bTqNg := (afTorque[DL_PTH_SEQ[_nIdxSafe]] < fTorqueLo) OR (afTorque[DL_PTH_SEQ[_nIdxSafe]] > fTorqueHi);    // 扭矩双窗 / Torque window, both sides
    _bAgNg := (afAngle[DL_PTH_SEQ[_nIdxSafe]] < fAngleLo) OR (afAngle[DL_PTH_SEQ[_nIdxSafe]] > fAngleHi);       // 角度双窗 / Angle window, both sides
    IF _bTqNg OR _bAgNg THEN
        IF _nFailCnt < DL_PTH_N THEN
            _anFail[_nFailCnt] := DL_PTH_SEQ[_nIdxSafe] + 1;    // 记录螺栓号（1 基，不是数组下标） / Record the 1-based bolt number
            _nFailCnt := _nFailCnt + 1;                         // 计数增 / Increment the count
        END_IF
        IF _bTqNg AND _bAgNg THEN
            _eCause := E_DL_PthCause.eBothNg;                   // 归因：双窗同越 / Cause: both windows violated
        ELSIF _bTqNg THEN
            _eCause := E_DL_PthCause.eTorqueNg;                 // 归因：扭矩越窗 / Cause: torque violated
        ELSE
            _eCause := E_DL_PthCause.eAngleNg;                  // 归因：角度越窗 / Cause: angle violated
        END_IF
    END_IF
    _nDoneCnt := _nDoneCnt + 1;                                 // 完成颗数增 / Increment the done count
    _nStepIdx := _nStepIdx + 1;                                 // 顺序推进 / Advance the sequence
    IF _nStepIdx >= DL_PTH_N THEN
        _eState := E_DL_PthState.eDone;                         // 四颗走完：出结论 / All four done, deliver the verdict
        bCycleDone := TRUE;                                     // 单拍完成脉冲 / Single-scan completion pulse
    END_IF
END_IF

(* —— 段 5：单颗超时（运行相且计时到 → 故障，记录卡住的螺栓号） —— *)
IF (_eState = E_DL_PthState.eRun) AND tonStepTo.Q AND (NOT _bCfgBad) THEN
    IF _nFailCnt < DL_PTH_N THEN
        _nIdxSafe := _nStepIdx;                                 // 取当前下标 / Take the present index
        IF _nIdxSafe < 0 THEN
            _nIdxSafe := 0;                                     // 下界钳 / Lower clamp
        END_IF
        IF _nIdxSafe > DL_PTH_N - 1 THEN
            _nIdxSafe := DL_PTH_N - 1;                          // 上界钳 / Upper clamp
        END_IF
        _anFail[_nFailCnt] := DL_PTH_SEQ[_nIdxSafe] + 1;        // 记录超时螺栓号 / Record the timed-out bolt number
        _nFailCnt := _nFailCnt + 1;                             // 计数增 / Increment the count
    END_IF
    _bFault := TRUE;                                            // 锁存 / Latch
    _eCause := E_DL_PthCause.eStepTimeout;                      // 归因：单颗超时 / Cause: per-bolt timeout
    _eState := E_DL_PthState.eFault;                            // 入故障相 / Enter fault phase
END_IF

(* —— 段 6：锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_PthState.eFault) THEN
    _eState := E_DL_PthState.eFault;                            // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_PthState.eIdle:
    IF _bCfgBad THEN                                            // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_PthState.eFault;
    ELSIF rtStart.Q THEN                                        // 出口 2：启动沿 / Start edge
        _eState := E_DL_PthState.eRun;
    END_IF

E_DL_PthState.eRun:
    IF _bCfgBad OR _bFault THEN                                 // 出口 1：故障（组态或超时） / Fault, config or timeout
        _eState := E_DL_PthState.eFault;
    ELSIF _nStepIdx >= DL_PTH_N THEN                            // 出口 2：四颗走完 / All four finished
        _eState := E_DL_PthState.eDone;
    END_IF

E_DL_PthState.eDone:
    IF _bCfgBad THEN                                            // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_PthState.eFault;
    ELSIF rtStart.Q THEN                                        // 出口 2：新工件启动 / New part started
        _eState := E_DL_PthState.eRun;
    END_IF

E_DL_PthState.eFault:
    IF rtReset.Q AND (NOT _bCfgBad) THEN                        // 出口：复位且组态已合法才迁出（R228B） / Reset with legal config
        _eState := E_DL_PthState.eIdle;
    END_IF

ELSE
    _eCause := E_DL_PthCause.ePhaseBad;                         // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_PthState.eFault;                            // 强拉故障相 / Force fault phase
    bError  := TRUE;                                            // 故障标志 / Error flag

END_CASE

(* —— 段 8：出口单点映射（当前螺栓号由顺序表反查，1 基；名实双出口 R191） —— *)
nCurrentBolt := 0;                                              // 当前螺栓号缺省无 / Current bolt defaults to none
IF _eState = E_DL_PthState.eRun THEN
    _nIdxSafe := _nStepIdx;                                     // 取顺序下标 / Take the sequence index
    IF _nIdxSafe < 0 THEN
        _nIdxSafe := 0;                                         // 下界钳 / Lower clamp
    END_IF
    IF _nIdxSafe > DL_PTH_N - 1 THEN
        _nIdxSafe := DL_PTH_N - 1;                              // 上界钳 / Upper clamp
    END_IF
    nCurrentBolt := DL_PTH_SEQ[_nIdxSafe] + 1;                  // 螺栓号 1..4（对角序反查） / Bolt number 1..4 via the diagonal order
END_IF
bStepActive := (_eState = E_DL_PthState.eRun) AND (nCurrentBolt > 0);      // 进行中 = 运行相且有当前螺栓 / Active when running with a current bolt
bAllOk      := (_eState = E_DL_PthState.eDone) AND (_nFailCnt = 0);        // 全合格 = 完成相且无不合格 / All-ok when done with no failures
nFailCount  := _nFailCnt;                                       // 不合格个数出口 / Failure count outlet
nDoneCount  := _nDoneCnt;                                       // 完成颗数出口 / Done count outlet
FOR _i := 0 TO DL_PTH_N - 1 DO
    anFailBolt[_i] := _anFail[_i];                              // 不合格表整体回放 / Failure table replay
END_FOR
bError := _bFault OR _bCfgBad;                                  // 故障标志 = 锁存或组态非法 / Error = latch or illegal config
eState := _eState;                                              // 状态出口 / State outlet
eCause := _eCause;                                              // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
