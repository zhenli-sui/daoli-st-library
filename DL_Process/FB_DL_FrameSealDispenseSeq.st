(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FrameSealDispenseSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 装框打胶顺控：eIdle → eHome（打胶头回参考）→ ePurge（预挤胶，废胶接料）
 *                         → eDispense（分段打胶，按 nSegCount 段推进，每段校核胶量）→ ePress
 *                         （压合到位）→ eCure（固化窗计时）→ eDone。断胶检测：eDispense 中
 *                         bGlueFlow 连续 tFlowGapMax 无信号 → 判断胶故障并**立即停止打胶并锁存**
 *                         （安全侧：断胶继续走会做出废件且可能把胶漏到设备上）。
 * 取舍声明 (Trade-off)  : **单段胶量超差不中断打胶**：某段胶量偏差超 fDoseTolPct 时该段计 NG，
 *                         但**继续打完剩余段**——半截停止会让整框报废，而打完剩下段至少能拿到
 *                         完整胶道供返修与工艺分析；NG 结论在循环结束时以 nNgSegCount 与 eCause
 *                         = eDoseNg 一并给出。这一取舍与「断胶立即停」并不矛盾：胶量超差是
 *                         **质量降级**，断胶是**工艺不可继续**，前者可回收后者不可。
 * 接口     (Interface)  : 输入 bStart 启动电平、bHomeDone 回参到位、bPurgeDone、bSegDone 段完成沿、
 *                         bPressDone 压合到位、bGlueFlow 胶流在位、fGlueDoseG 段实测胶量、
 *                         fDoseTgtG 段目标胶量、fDoseTolPct 胶量容差百分比、nSegCount 段数、
 *                         六个时间量（回参/预挤/断胶/压合/固化及其超时）、bReset 复位；
 *                         输出 eState、eCause、bGlueOn 打胶阀命令、bPressCmd 压合命令、bPurgeCmd、
 *                         bHomeCmd、nSegDone 已完成段数、nNgSegCount NG 段累计（锁存量，复位不清零）、
 *                         bBatchNg 本批次 NG 结论、bCycleDone、bError、nErrId。
 * 边界     (Boundary)   : ① 组态闸：fDoseTolPct <= 0.0、fDoseTgtG <= 0.0、nSegCount = 0、任一时长
 *                         <= T#0S、时长配比越界（超时 <= 工艺时长）或任一浮点引脚 NaN → 故障锁存；
 *                         ② TON 五枚 + R_TRIG 三枚段 0 无条件刷新，IN 均由相位派生（R228A）；
 *                         ③ **NG 计数为锁存量，复位不清零**（批次台账语义）；窗内极值类当拍量才清；
 *                         ④ 断胶判据只在 eDispense 相内使能，离开该相自动复位（R228B）；
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / 无物理地址）。
 * 定时器清单 (Timers)   : 本件 5 枚 TON + 3 枚 R_TRIG（较派单 4+2 各多一枚，理由：tonFlow 的 IN
 *                         必须随 bGlueFlow 在相内独立复位，不能与相计时合并；段完成沿 bSegDone
 *                         必须独立成沿实例，不能与启动沿或复位沿合并），全部段 0 无条件调用。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 无断胶（bGlueFlow 当拍为真，R240 范式）。
 *                         自证可满足（终审两式 1）：五枚 TON 的 IN 挂相位，故障相内恒假 → Q 恒假；
 *                         恢复供胶后 bGlueFlow 为真即达，无恒假因子。
 * 码表     (Codes)      : 16#0005_03A7 故障级：装框打胶顺控故障总码（组态非法 / 回参超时 / 预挤超时 /
 *                         断胶 / 压合超时 / 固化超时 / 非法相位），锁存至 bReset 上升沿，归因由
 *                         eCause 承载（R190 单件单总码）；16#0005_04CF 信息级：批次正常完成。
 *                         归因说明：eCause 亦承载**非故障**的批次质量归因 eDoseNg（胶量超差但循环
 *                         走完），此时 bError 恒为 FALSE——HMI 必须用 bError 判故障、用 eCause 判
 *                         质量归因，不得以 eCause 非零视为故障（R191 名实双出口）。
 *                         加码反证（R90）：批次完成时 bCycleDone 由相位派生，「完成态驻留」与之同值；
 *                         且 NG 结论 bBatchNg 也会在完成态保持，出口组合无法区分「刚完成一次」
 *                         与「长期驻留完成态」，故立一码记录每次完成沿。
 *                         码段说明：0005 段故障子带 03xx / 信息子带 04xx，本件取 03A7 / 04CF
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考光伏组件装框打胶工艺与公开参数域，
 *                         零代码行复制；自研行业池）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 4 · 序号 19）
 *==============================================================================*)

TYPE E_DL_FsdState :
(
    eIdle     := 0,     // 待启动 / Idle, awaiting start
    eHome     := 10,    // 打胶头回参考 / Dispenser homing
    ePurge    := 20,    // 预挤胶（废胶接料） / Purging to the waste cup
    eDispense := 30,    // 分段打胶 / Segmented dispensing
    ePress    := 40,    // 压合 / Pressing
    eCure     := 50,    // 固化窗计时 / Curing window
    eDone     := 60,    // 批次完成 / Batch done
    eFault    := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_FsdCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eHomeTmo    := 2,   // 回参超时 / Homing timeout
    ePurgeTmo   := 3,   // 预挤超时 / Purge timeout
    eNoGlue     := 4,   // 断胶（流量信号消失超时） / Glue flow lost
    ePressTmo   := 5,   // 压合超时 / Press timeout
    eCureTmo    := 6,   // 固化超时 / Cure timeout
    eDoseNg     := 7,   // 胶量超差（非故障，批次质量归因） / Dose out of tolerance, quality attribution only
    ePhaseBad   := 8    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_FrameSealDispenseSeq
VAR_INPUT
    bStart        : BOOL := FALSE;        // 启动电平（落沿等于撤启动） [-] / Start level, falling edge means abort
    bHomeDone     : BOOL := FALSE;        // 打胶头回参考到位 [-] / Dispenser homed
    bPurgeDone    : BOOL := FALSE;        // 预挤完成 [-] / Purge finished
    bSegDone      : BOOL := FALSE;        // 当前段完成，上升沿受理一段 [-] / Segment done, rising edge accepts one segment
    bPressDone    : BOOL := FALSE;        // 压合到位 [-] / Pressed in position
    bGlueFlow     : BOOL := FALSE;        // 胶流在位（断胶判据） [-] / Glue flow present
    fGlueDoseG    : REAL := 0.0;          // 当前段累计胶量 [g] / Accumulated dose of the current segment [g]
    fDoseTgtG     : REAL := 5.0;          // 段目标胶量，域 > 0.0 [g] / Segment target dose, domain > 0.0 [g]
    fDoseTolPct   : REAL := 5.0;          // 段胶量容差百分比，域 > 0.0 [%] / Segment dose tolerance, domain > 0.0 [%]
    nSegCount     : INT := 8;             // 段数（正整数），域 > 0 [段] / Segment count, domain > 0 [seg]
    tHomeMax      : TIME := T#20S;        // 回参超时，域 > T#0S [ms] / Homing timeout [ms]
    tPurge        : TIME := T#3S;         // 预挤工艺时长，域 > T#0S [ms] / Purge process time [ms]
    tPurgeMax     : TIME := T#8S;         // 预挤超时，域 > tPurge [ms] / Purge timeout [ms]
    tFlowGapMax   : TIME := T#300MS;      // 断胶判定时长（无胶流超时），域 > T#0S [ms] / Glue-flow gap limit [ms]
    tPressMax     : TIME := T#15S;        // 压合超时，域 > T#0S [ms] / Press timeout [ms]
    tCure         : TIME := T#30S;        // 固化工艺时长，域 > T#0S [ms] / Cure process time [ms]
    tCureMax      : TIME := T#60S;        // 固化超时，域 > tCure [ms] / Cure timeout [ms]
    bReset        : BOOL := FALSE;        // 复位命令，上升沿清故障（不清 NG 台账） [-] / Reset clears fault, not the NG ledger
END_VAR
VAR_OUTPUT
    eState        : E_DL_FsdState;        // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_FsdCause;        // 成因出口（故障归因或批次质量归因） / Cause outlet, fault or quality attribution
    bGlueOn       : BOOL;                 // 打胶阀命令（仅 eDispense 相） [-] / Glue valve command, dispense phase only
    bPressCmd     : BOOL;                 // 压合命令（仅 ePress 相） [-] / Press command, press phase only
    bPurgeCmd     : BOOL;                 // 预挤命令（仅 ePurge 相） [-] / Purge command, purge phase only
    bHomeCmd      : BOOL;                 // 回参命令（仅 eHome 相） [-] / Homing command, home phase only
    nSegDone      : INT;                  // 已完成段数 [段] / Segments completed [seg]
    nNgSegCount   : INT;                  // NG 段累计（锁存量，复位不清零） [段] / NG segment total, latched, kept across resets
    bBatchNg      : BOOL;                 // 本批次 NG 结论（NG 段 > 0） [-] / Batch NG verdict
    bCycleDone    : BOOL;                 // 批次完成标志 [-] / Batch done flag
    bError        : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_FsdState := E_DL_FsdState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_FsdCause := E_DL_FsdCause.eNone;   // 成因锁存（锁存量） / Latched cause
    tonHome       : TON;                  // 回参计时（PT = 超时），段 0 无条件调用 / Homing timer
    tonPurge      : TON;                  // 预挤计时（PT = 超时），段 0 无条件调用 / Purge timer
    tonFlow       : TON;                  // 断胶计时（IN 随胶流独立复位），段 0 无条件调用 / Glue-gap timer
    tonPress      : TON;                  // 压合计时（PT = 超时），段 0 无条件调用 / Press timer
    tonCure       : TON;                  // 固化计时（PT = 超时），段 0 无条件调用 / Cure timer
    rtSeg         : R_TRIG;               // 段完成沿实例，段 0 无条件调用 / Segment-done edge
    rtStart       : R_TRIG;               // 启动沿实例，段 0 无条件调用 / Start edge
    rtReset       : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _nSegDone     : INT;                  // 已完成段计数（锁存量） [段] / Completed segment counter, latched
    _nNgSeg       : INT;                  // NG 段计数（锁存量，复位不清零） [段] / NG segment counter, kept across resets
    _fDoseDevPct  : REAL;                 // 段胶量相对偏差当拍量 [%] / Segment relative dose deviation [%]
    _bNonFin      : BOOL;                 // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad      : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bFault       : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;        // 浮点判零容差（除子统一口径） [无量纲] / Float epsilon for zero tests
    DL_PCT_SCALE : REAL := 100.0;         // 百分比换算常数 [%] / Percentage scaling constant [%]
END_VAR

(* —— 段 0：当拍判据派生 + 5 枚 TON 与 3 枚 R_TRIG 无条件周期刷新 —— *)
_bNonFin := (fGlueDoseG <> fGlueDoseG) OR (fDoseTgtG <> fDoseTgtG) OR (fDoseTolPct <> fDoseTolPct);   // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
IF fDoseTgtG > DL_FLOAT_EPS THEN                                                                       // 除零前置判 / Divide-by-zero guard
    _fDoseDevPct := (ABS(fGlueDoseG - fDoseTgtG) / fDoseTgtG) * DL_PCT_SCALE;                          // 段胶量相对偏差 / Segment relative dose deviation
ELSE
    _fDoseDevPct := DL_PCT_SCALE;                                                                       // 目标退化按最差偏差处理（组态闸已拦） / Degenerate target treated as worst deviation
END_IF
_bCfgBad := (fDoseTolPct <= 0.0) OR (fDoseTgtG <= 0.0) OR (nSegCount <= 0)                              // 容差与段数组态闸（R151） / Tolerance and segment-count gates
            OR (tHomeMax <= T#0S) OR (tPurge <= T#0S) OR (tPurgeMax <= tPurge)                          // 回参与预挤时间闸 / Homing and purge gates
            OR (tFlowGapMax <= T#0S) OR (tPressMax <= T#0S)                                             // 断胶与压合时间闸 / Glue-gap and press gates
            OR (tCure <= T#0S) OR (tCureMax <= tCure);                                                  // 固化时间配比闸 / Cure time gates
rtSeg(CLK := bSegDone);                                                                                 // 段完成沿，每拍必调（R228A） / Segment edge
rtStart(CLK := bStart);                                                                                 // 启动沿，每拍必调 / Start edge
rtReset(CLK := bReset);                                                                                 // 复位沿，每拍必调 / Reset edge
tonHome(IN := (_eState = E_DL_FsdState.eHome), PT := tHomeMax);                                          // 回参计时（IN 绑相位） / Homing timer
tonPurge(IN := (_eState = E_DL_FsdState.ePurge), PT := tPurgeMax);                                       // 预挤计时（IN 绑相位） / Purge timer
tonFlow(IN := (_eState = E_DL_FsdState.eDispense) AND (NOT bGlueFlow), PT := tFlowGapMax);                // 断胶计时（相内随胶流复位） / Glue-gap timer
tonPress(IN := (_eState = E_DL_FsdState.ePress), PT := tPressMax);                                       // 压合计时（IN 绑相位） / Press timer
tonCure(IN := (_eState = E_DL_FsdState.eCure), PT := tCureMax);                                          // 固化计时（IN 绑相位） / Cure timer

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo     := 16#0000_0000;        // 信息码每拍重算 / Info recomputed every scan
nSegDone   := _nSegDone;           // 完成段数镜像（锁存量回放） / Segment-done mirror
nNgSegCount := _nNgSeg;            // NG 台账镜像（锁存量回放，复位不清零） / NG ledger mirror
bBatchNg   := (_nNgSeg > 0);       // 批次 NG 结论由台账派生（名实同源） / Batch verdict derived from the ledger
nErrId     := 16#0000_0000;        // 事件码缺省无事件 / Event code default none
bError     := FALSE;               // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 非有限闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_FsdCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_FsdState.eFault THEN
        _eState := E_DL_FsdState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0005_03A7;                                             // 故障级：装框打胶顺控故障总码 / Fault-level: dispensing sequence fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_FsdCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                       // 输入非有限 / Non-finite input
    _uFault := 16#0005_03A7;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsdCause.eCfgIllegal;                                // 归因：组态非法（含非有限输入） / Cause: illegal configuration with non-finite input
END_IF
IF (NOT _bFault) AND tonFlow.Q THEN                                      // 断胶：立即停止打胶并锁存（安全侧） / Glue lost, stop immediately and latch
    _uFault := 16#0005_03A7;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsdCause.eNoGlue;                                    // 归因：断胶 / Cause: glue flow lost
END_IF

(* —— 段 3：相超时判据（各成因独立赋值点，R190） —— *)
IF (NOT _bFault) AND tonHome.Q THEN
    _uFault := 16#0005_03A7;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsdCause.eHomeTmo;                                   // 归因：回参超时 / Cause: homing timeout
END_IF
IF (NOT _bFault) AND tonPurge.Q THEN
    _uFault := 16#0005_03A7;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsdCause.ePurgeTmo;                                  // 归因：预挤超时 / Cause: purge timeout
END_IF
IF (NOT _bFault) AND tonPress.Q THEN
    _uFault := 16#0005_03A7;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsdCause.ePressTmo;                                  // 归因：压合超时 / Cause: press timeout
END_IF
IF (NOT _bFault) AND tonCure.Q THEN
    _uFault := 16#0005_03A7;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsdCause.eCureTmo;                                   // 归因：固化超时 / Cause: cure timeout
END_IF

(* —— 段 4：段级胶量校核（NG 只记台账不中断，头注释取舍声明） —— *)
IF (NOT _bFault) AND (_eState = E_DL_FsdState.eDispense) AND rtSeg.Q THEN
    IF _nSegDone < nSegCount THEN                                        // 段数未满才受理 / Accept only while segments remain
        _nSegDone := _nSegDone + 1;                                      // 累计完成段 / Count the segment
        IF _fDoseDevPct > fDoseTolPct THEN                               // 胶量超差：记 NG 但继续打（不中断） / Over tolerance, record NG and continue
            IF _nNgSeg < 32767 THEN
                _nNgSeg := _nNgSeg + 1;                                  // NG 台账递增（锁存量） / NG ledger increment, latched
            END_IF
            _eCause := E_DL_FsdCause.eDoseNg;                            // 质量归因（非故障，bError 保持 FALSE） / Quality attribution, not a fault
        END_IF
    END_IF
END_IF

(* —— 段 5：故障解除式（R240 全当拍量；NG 台账不受复位影响） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND bGlueFlow THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_FsdCause.eNone;                                      // 清成因（锁存量，NG 台账仍保留） / Clear cause, NG ledger preserved
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_FsdState.eFault) THEN
    _eState := E_DL_FsdState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_FsdState.eIdle:
    IF rtStart.Q AND (NOT _bFault) THEN                                  // 出口 1：启动沿 / Start edge
        _nSegDone := 0;                                                  // 新批次清完成段（台账 nNgSeg 不清） / Reset segment progress, NG ledger kept
        _eState := E_DL_FsdState.eHome;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_FsdState.eFault;
    END_IF

E_DL_FsdState.eHome:
    IF bHomeDone THEN                                                    // 出口 1：回参到位 / Homed
        _eState := E_DL_FsdState.ePurge;
    ELSIF NOT bStart THEN                                                // 出口 2：撤启动（前置消失，R98） / Start released
        _eState := E_DL_FsdState.eIdle;
    END_IF

E_DL_FsdState.ePurge:
    IF (bPurgeDone OR (tonPurge.ET >= tPurge)) THEN                      // 出口 1：预挤完成或工艺时长届满 / Purge done or process time reached
        _eState := E_DL_FsdState.eDispense;
    ELSIF NOT bStart THEN                                                // 出口 2：撤启动 / Start released
        _eState := E_DL_FsdState.eIdle;
    END_IF

E_DL_FsdState.eDispense:
    IF _nSegDone >= nSegCount THEN                                       // 出口 1：全部段完成 / All segments done
        _eState := E_DL_FsdState.ePress;
    ELSIF NOT bStart THEN                                                // 出口 2：撤启动 / Start released
        _eState := E_DL_FsdState.eIdle;
    END_IF

E_DL_FsdState.ePress:
    IF bPressDone THEN                                                   // 出口 1：压合到位 / Pressed in position
        _eState := E_DL_FsdState.eCure;
    ELSIF NOT bStart THEN                                                // 出口 2：撤启动 / Start released
        _eState := E_DL_FsdState.eIdle;
    END_IF

E_DL_FsdState.eCure:
    IF tonCure.ET >= tCure THEN                                          // 出口 1：固化时长届满 / Cure time reached
        _uInfo := 16#0005_04CF;                                          // 信息级：批次正常完成 / Info: batch completed
        _eState := E_DL_FsdState.eDone;
    ELSIF NOT bStart THEN                                                // 出口 2：撤启动 / Start released
        _eState := E_DL_FsdState.eIdle;
    END_IF

E_DL_FsdState.eDone:
    bCycleDone := TRUE;                                                  // 完成相保持完成标志 / Hold done flag in done phase
    IF NOT bStart THEN                                                   // 出口 1：撤启动回空闲 / Start released returns idle
        _eState := E_DL_FsdState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_FsdState.eFault;
    END_IF

E_DL_FsdState.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0005_03A7;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsdCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_FsdState.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放；故障相命令全落） —— *)
IF _bFault THEN
    bGlueOn    := FALSE;                                                 // 故障相：打胶阀关（断胶/超时均不得继续打胶） / Glue valve closed in fault
    bPressCmd  := FALSE;                                                 // 故障相：压合命令撤 / Press command released in fault
    bPurgeCmd  := FALSE;                                                 // 故障相：预挤命令撤 / Purge command released in fault
    bHomeCmd   := FALSE;                                                 // 故障相：回参命令撤 / Home command released in fault
    bCycleDone := FALSE;                                                 // 故障相不宣称完成 / No completion claim in fault
ELSE
    bGlueOn    := (_eState = E_DL_FsdState.eDispense);                   // 打胶阀仅打胶相开 / Glue valve only while dispensing
    bPressCmd  := (_eState = E_DL_FsdState.ePress);                      // 压合仅压合相 / Press only in press phase
    bPurgeCmd  := (_eState = E_DL_FsdState.ePurge);                      // 预挤仅预挤相 / Purge only in purge phase
    bHomeCmd   := (_eState = E_DL_FsdState.eHome);                       // 回参仅回参相 / Home only in home phase
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
