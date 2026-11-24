(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisDualFeedbackGuard
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 单轴双反馈交叉校核。把电机侧位置 fPosMotor 与负载侧位置 fPosLoad
 *                         各自乘标定系数换算到同一工程单位后求偏差 fDev，并按幅值与持续时间
 *                         分级：|fDev| 超 fDevWarn → 维护级预警（bWarn）；超 fDevAlarm 且持续
 *                         tDevConfirm → 故障锁存。另做极性装反识别：偏差方向与参考运动方向
 *                         同号、且偏差每拍增量超 fSlopeThr 时归因 ePolarity（区别于打滑——
 *                         打滑时偏差随运动累积但方向与运动一致而增量平稳，装反时增量陡增）。
 * 接口     (Interface)  : 输入 fPosMotor 电机侧位置、fPosLoad 负载侧位置、fScaleMotor / fScaleLoad
 *                         两侧标定系数、fDevWarn 预警阈值、fDevAlarm 故障阈值、tDevConfirm 故障
 *                         确认时间、fSlopeThr 偏差每拍增量阈值、fVelRefMms 参考运动速度（方向
 *                         判据）、bReset 复位；输出 fDev 换算后偏差、bWarn 维护级预警、bGuardOk
 *                         校核通过、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：fScaleMotor / fScaleLoad 的绝对值 <= DL_FLOAT_EPS（防零增益
 *                         静默把偏差算成 0）、fDevWarn <= 0.0、fDevAlarm <= fDevWarn、
 *                         tDevConfirm <= T#0S、fSlopeThr < 0.0 或任一浮点引脚 NaN → 故障锁存；
 *                         ② **本件不定义轴状态枚举、不发运动指令**（轴状态唯一属主 `I_DL_MotionAxis`），
 *                         只读位置与速度参考，只输出校核结论；
 *                         ③ 偏差每拍增量以「每拍工程单位增量」为单位：任务周期固定时它与斜率
 *                         成正比，fSlopeThr 按该口径标定（比值约定见头注释遗留假设）；
 *                         ④ TON 两枚（预警/故障确认）+ R_TRIG 一枚段 0 无条件周期刷新；
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_GantrySyncAxis`（双**轴**同步偏差）分工 —— 本件是**单轴双反馈**
 *                         （电机侧 vs 负载侧），判「同一根轴的两把尺是否一致」；那件判「两根轴的
 *                         位置是否同步」。二者输入维度不同，禁止互相替代。
 * 遗留假设 (Assumption) : 【R95 三句声明】① 代理值 = 偏差每拍增量（未引入任务周期引脚）；
 *                         ② 覆盖范围 = 任务周期 1 ms ~ 20 ms 的常规运动任务；③ 覆盖不到的区间
 *                         （< 1 ms 的高速插补任务）由调用方负责：此时每拍增量被任务周期压缩，
 *                         fSlopeThr 需由调用方按周期比例放大，否则极性识别灵敏度下降。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ |fDev| < fDevWarn（当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：解除式只含当拍偏差比较与组态闸，两枚 TON
 *                         的 IN 由当拍阈值判据派生，偏差回落即 Q 落假，无恒假因子。
 * 码表     (Codes)      : 16#0004_03B4 故障级：双反馈校核故障总码（组态非法 / 偏差超限确认 /
 *                         极性装反 / 非法相位），锁存至 bReset 上升沿，归因由 eCause 承载；
 *                         16#0004_04B4 信息级：维护级预警（|fDev| 超 fDevWarn 但未达故障）。
 *                         加码反证（R90）：预警相 fDev 仍为小值、bError 为假，若只靠 bWarn 布尔
 *                         位则该退化不进报警台账（HMI 只归档带码事件），故立一码。
 *                         码段说明：0004 段故障子带 03xx / 信息子带 04xx，本件取 03B4 / 04B4
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考双反馈交叉校核与极性判别参数域，零代码行复制；
 *                         t1-6-plcopen 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 2 · 序号 10）
 *==============================================================================*)

TYPE E_DL_DfgState :
(
    eIdle  := 0,     // 未取得有效反馈，等待首拍 / Idle, awaiting first valid feedback
    eRun   := 10,    // 校核运行 / Guard running
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_DfgCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eDevLimit   := 2,   // 偏差超故障阈值且确认时间到 / Deviation over alarm limit confirmed
    ePolarity   := 3,   // 极性装反（偏差随运动同号且增量陡增） / Polarity reversed
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisDualFeedbackGuard
VAR_INPUT
    fPosMotor   : REAL := 0.0;          // 电机侧位置（编码器计数或已换算值） [cnt] / Motor-side position in encoder counts [cnt]
    fPosLoad    : REAL := 0.0;          // 负载侧位置（光栅尺或第二编码器） [mm] / Load-side position from scale [mm]
    fScaleMotor : REAL := 0.001;        // 电机侧标定系数，绝对值须 > DL_FLOAT_EPS [mm/cnt] / Motor-side scale, |value| > epsilon [mm/cnt]
    fScaleLoad  : REAL := 1.0;          // 负载侧标定系数，绝对值须 > DL_FLOAT_EPS [mm/mm] / Load-side scale, |value| > epsilon [mm/mm]
    fDevWarn    : REAL := 0.05;         // 维护级预警阈值，域 > 0.0 [mm] / Maintenance warning threshold, domain > 0.0 [mm]
    fDevAlarm   : REAL := 0.20;         // 故障阈值，域 > fDevWarn [mm] / Fault threshold, domain > fDevWarn [mm]
    tDevConfirm : TIME := T#200MS;      // 故障确认时间，域 > T#0S [ms] / Fault confirm time, domain > T#0S [ms]
    fSlopeThr   : REAL := 0.02;         // 偏差每拍增量阈值（极性判据），域 >= 0.0 [mm/拍] / Deviation increment per scan threshold [mm/scan]
    fVelRefMms  : REAL := 0.0;          // 参考运动速度（仅用符号判方向） [mm/s] / Reference velocity, sign used for direction [mm/s]
    bReset      : BOOL := FALSE;        // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    fDev        : REAL;                 // 换算到同一单位后的偏差（电机侧 − 负载侧） [mm] / Deviation after unit conversion [mm]
    bWarn       : BOOL;                 // 维护级预警（未达故障） [-] / Maintenance warning, below fault level
    bGuardOk    : BOOL;                // 校核通过（偏差在预警带内且无故障） [-] / Guard passed
    eState      : E_DL_DfgState;        // 状态出口，段 6 单点映射 / State outlet
    eCause      : E_DL_DfgCause;        // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError      : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId      : UDINT;               // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState     : E_DL_DfgState := E_DL_DfgState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause     : E_DL_DfgCause := E_DL_DfgCause.eNone;    // 故障成因锁存（锁存量） / Latched cause
    tonWarn     : TON;                  // 预警确认计时，段 0 无条件调用 / Warning timer
    tonAlarm    : TON;                  // 故障确认计时，段 0 无条件调用 / Alarm confirm timer
    rtReset     : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _fMotorMm   : REAL;                 // 电机侧换算位置 [mm] / Motor-side position in millimetres
    _fLoadMm    : REAL;                 // 负载侧换算位置 [mm] / Load-side position in millimetres
    _fDevPrev   : REAL;                 // 上拍偏差快照（锁存量） [mm] / Previous-scan deviation snapshot
    _fDevStep   : REAL;                 // 本拍偏差增量 [mm] / Deviation increment this scan
    _fDev       : REAL;                 // 本拍换算偏差中间量（段 0 派生，段 8 映射到输出） [mm] / Deviation intermediate, derived in seg 0, mapped to output in seg 8
    _bPolSame   : BOOL;                 // 偏差符号与运动方向同号当拍量 [-] / Deviation sign matches motion sign
    _bPolSteep  : BOOL;                 // 偏差增量超阈值当拍量 [-] / Deviation increment above threshold
    _bNonFin    : BOOL;                 // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad    : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bFault     : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault     : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo      : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;      // 浮点判零容差（标定系数与判据统一口径） [无量纲] / Float epsilon for zero tests
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新 —— *)
_fMotorMm := fPosMotor * fScaleMotor;                                    // 电机侧换算到 mm / Motor side converted to millimetres
_fLoadMm  := fPosLoad * fScaleLoad;                                      // 负载侧换算到 mm / Load side converted to millimetres
_fDev     := _fMotorMm - _fLoadMm;                                       // 偏差 = 电机侧 − 负载侧 [mm] / Deviation, motor minus load
_fDevStep := _fDev - _fDevPrev;                                          // 本拍偏差增量 [mm/拍] / Deviation increment per scan
_bNonFin  := (fPosMotor <> fPosMotor) OR (fPosLoad <> fPosLoad)          // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
          OR (fScaleMotor <> fScaleMotor) OR (fScaleLoad <> fScaleLoad)  // 标定系数 NaN 判 / Scale NaN tests
          OR (fVelRefMms <> fVelRefMms) OR (fSlopeThr <> fSlopeThr);     // 方向与阈值 NaN 判 / Direction and threshold NaN tests
_bCfgBad  := (ABS(fScaleMotor) <= DL_FLOAT_EPS) OR (ABS(fScaleLoad) <= DL_FLOAT_EPS)   // 零增益闸（R151 覆盖每个参与引脚） / Zero-gain gate
             OR (fDevWarn <= 0.0) OR (fDevAlarm <= fDevWarn)                           // 阈值几何闸 / Threshold geometry gate
             OR (tDevConfirm <= T#0S) OR (fSlopeThr < 0.0);                            // 时间与增量阈值闸 / Time and increment gates
_bPolSame := ((_fDev > 0.0) AND (fVelRefMms > 0.0)) OR ((_fDev < 0.0) AND (fVelRefMms < 0.0));   // 偏差与运动同号 / Deviation sign equals motion sign
_bPolSteep := ABS(_fDevStep) > fSlopeThr;                                                      // 增量陡增判据 / Steep increment criterion
rtReset(CLK := bReset);                                                                        // 复位沿，每拍必调（R228A） / Reset edge
tonWarn(IN := ABS(_fDev) > fDevWarn, PT := tDevConfirm);                                       // 预警确认计时（IN 由判据派生） / Warning timer
tonAlarm(IN := ABS(_fDev) > fDevAlarm, PT := tDevConfirm);                                     // 故障确认计时 / Alarm confirm timer

(* —— 段 1：单拍量预清零（锁存量与快照量不入清单，R107） —— *)
_uInfo    := 16#0000_0000;         // 信息码每拍重算 / Info recomputed every scan
bWarn     := FALSE;                // 预警位每拍预清 / Warning preset
bGuardOk  := FALSE;                // 通过位每拍预清 / Pass flag preset
nErrId    := 16#0000_0000;         // 事件码缺省无事件 / Event code default none
bError    := FALSE;                // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 非有限闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_DfgCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_DfgState.eFault THEN
        _eState := E_DL_DfgState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0004_03B4;                                             // 故障级：双反馈校核故障总码 / Fault-level: guard fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_DfgCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                       // 输入非有限 / Non-finite input
    _uFault := 16#0004_03B4;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_DfgCause.eDevLimit;                                  // 归因：偏差不可信（非有限并入超限） / Cause: deviation untrustworthy, folded into limit
END_IF

(* —— 段 3：极性装反识别（先于幅值分级判，避免装反被误归因为打滑） —— *)
IF (NOT _bFault) AND _bPolSame AND _bPolSteep AND (ABS(_fDev) > fDevWarn) THEN
    _uFault := 16#0004_03B4;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_DfgCause.ePolarity;                                  // 归因：极性装反 / Cause: polarity reversed
END_IF

(* —— 段 4：幅值分级（预警=维护级信息；故障=确认窗到） —— *)
IF (NOT _bFault) THEN
    IF tonAlarm.Q THEN                                                   // 超故障阈值且确认窗到 / Over alarm limit confirmed
        _uFault := 16#0004_03B4;
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_DfgCause.eDevLimit;                              // 归因：偏差超限 / Cause: deviation over limit
    ELSIF ABS(_fDev) > fDevWarn THEN                                     // 预警带（维护级，不锁故障） / Warning band, maintenance level
        bWarn := TRUE;                                                   // 预警位 / Warning flag
        _uInfo := 16#0004_04B4;                                          // 信息级：维护级预警 / Info: maintenance warning
    ELSE
        bGuardOk := TRUE;                                                // 预警带内：校核通过 / Inside band, guard passed
    END_IF
END_IF

(* —— 段 5：偏差快照更新（主体末行，跨拍纪律） —— *)
_fDevPrev := _fDev;                                                      // 偏差快照（本拍末更新） / Deviation snapshot at body end

(* —— 段 6：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (ABS(_fDev) < fDevWarn) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_DfgCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 6A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_DfgState.eFault) THEN
    _eState := E_DL_DfgState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_DfgState.eIdle:
    IF (NOT _bNonFin) AND (NOT _bCfgBad) AND (rtReset.Q OR bGuardOk OR bWarn) THEN   // 出口 1：偏差可算且已判定（复位后首拍或已出结论） / Deviation computable and judged
        _eState := E_DL_DfgState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_DfgState.eFault;
    END_IF

E_DL_DfgState.eRun:
    IF rtReset.Q AND (NOT _bFault) THEN                                  // 出口 1：运行相收到复位沿 → 回观测相重采样一次 / Reset re-arms the guard
        _eState := E_DL_DfgState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_DfgState.eFault;
    END_IF

E_DL_DfgState.eFault:
    ;                                                                     // 故障相：仅段 6 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0004_03B4;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_DfgCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_DfgState.eFault;

END_CASE

(* —— 段 8：出口单点映射（名实同源；锁存码回放；故障相安全侧） —— *)
IF _bFault THEN
    bWarn    := FALSE;                                                   // 故障相不再宣称「仅预警」 / No warning claim in fault
    bGuardOk := FALSE;                                                   // 故障相校核不通过 / Guard failed in fault
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
fDev    := _fDev;                                                               // 偏差输出每拍赋值（名实同源） / Deviation output assigned every scan
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
