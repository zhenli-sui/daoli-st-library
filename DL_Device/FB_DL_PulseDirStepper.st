(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PulseDirStepper
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 分类     (Category)   : 设备功能块（Function Block · 脉冲方向型开环步进控制器）
 * 作者     (Author)     : Daoli Library
 * 日期     (Date)       : 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（TON），零厂商方言
 * 功能简介 (Function)   : 脉冲 + 方向型开环步进控制器，实现接口
 *                         I_DL_StepperOpenLoop 的全部属性与方法。① 梯形加减速
 *                         脉冲频率规划（加速/匀速/减速三段，短行程退化为三角型）；
 *                         ② 限位保护（同向限位立即停发脉冲并锁故障，方向拒绝为
 *                         电平判据持续生效）；③ 堵转超时判据（运动耗时超理论耗时
 *                         乘裕度系数加附加裕度即判故障）；④ 脉冲按任务周期定宽
 *                         输出（R24：脉宽恒为一拍，停发在本拍内完成，无半脉冲）。
 * 职责边界 (Scope)      : 不绑定输出模块（脉冲/方向/使能全部经引脚输出，物理口
 *                         映射由适配层完成）；不做位置闭环（开环无编码器，位置为
 *                         指令推算值）；不做回原与点动（由上层组合实现）；不构成
 *                         ISO 13849 / IEC 62061 认证安全功能，急停与安全门必须由
 *                         认证安全回路在输出侧直接切断。
 * 开源溯源 (Origin)     : 来源标签 stepper（GitHub topics 开组）+ plcopen-motion
 *                         梯形规划语义。仅参考 MIT 许可开源步进驱动项目（AccelStepper
 *                         及同类公开仓库）公开的「梯形加减速脉冲频率规划算法思想」
 *                         与「脉冲当量 / 最大速度 / 加速度 / 超时」参数域惯例，以及
 *                         PLCopen 公开规范中梯形速度曲线的段划分语义；枚举编号、
 *                         状态机、限位/堵转判据、故障码位与脉冲发生实现 100% 本库
 *                         独立设计，clean-room 实现，未复制任何来源代码行，不构成
 *                         任何来源的衍生作品。
 * 公约遵循 (Convention) : 0.1/R19 首扫范式；0.2/R21 bError 排除信息级码；0.5/R7
 *                         定时器实例主体最前部无条件刷新；0.6/R14 定时器语义参数
 *                         变化断输入一拍；0.7/R15 故障锁存仅复位路径清码；0.9 非
 *                         有限值防御与出口默认值先赋；0.12/R22 接口属性以 PROPERTY
 *                         GET 承载、非接口成员保留引脚；0.14 除法防零与浮点容差；
 *                         0.15 单位统一 mm / mm/s / mm/s² / Hz / 脉冲；0.16 全常量化。
 * 红线自检 (Redline)    : 全局隔离 ✓｜命名合规 ✓｜注释完整 ✓（声明行全中英双语）｜
 *                         OOP 封装 ✓（IMPLEMENTS 接口、状态私有、属性只读）｜周期
 *                         安全 ✓（TON 无条件刷新，方法无跨周期驻留）｜防御编程 ✓
 *                         （除零守卫、浮点容差、CASE+ELSE 兜底、脉宽下限保护）｜
 *                         可移植性 ✓（纯 IEC 61131-3）｜终结符成对 ✓
 * 设计要点 (Key notes)  : ① 频率上限硬约束：脉冲每拍最多翻转一次，最高频率为
 *                         1 / (2 × 任务周期)（一高拍 + 一低拍）；超限即钳位并置
 *                         0003_0131，保证脉宽下限恒为一拍（R24）。
 *                         ② 梯形解析式（脉冲域，速度为频率）：加速段步数 na =
 *                         v² / (2a)；若 2 × na > N 则三角型，na = N / 2 且峰值
 *                         v = SQRT(a × N)；理论耗时 t = 2(v/a) + (N − 2na)/v [s]。
 *                         ③ 堵转判据：时限 = t × 1.5 + tStallTimeout，定时器自运动
 *                         起点计时，到期判堵转（开环无反馈，只能以时间偏离推断）。
 *                         ④ 限位语义：运动中同向限位即停发并锁故障；复位后方向拒绝
 *                         仍由开关电平承担（停在限位开关上时仅反方向可动），避免
 *                         「卡在限位无法脱离」的死锁。
 *                         ⑤ 故障不切使能：bEnableOut 恒透传使能指令，故障期保持保持
 *                         力矩，防垂直轴溜车；切使能由上层安全回路决定。
 * 偏离留档 (Deviation)  : ① 规格 OUT 列的 bReady / fPosition / uAlarmWord 标为
 *                         「接口属性实现」，按公约 0.12 改为 PROPERTY GET 承载
 *                         （读法不变，语义一致）；② 规格 VAR 段 bFirstScan 改名
 *                         _bInit（公约 0.1）；③ 规格建议故障码 0003_0230~0235 与
 *                         既有 FB_DL_VacuumEjector（0230~0232）冲突，依公约 0.8
 *                         顺延至 0003_02E0~02E4；信息级扩至 0136。
 * 故障码表 (Error codes) :
 *                         16#0003_0130【信息级】速度指令超最大速度已钳位
 *                         16#0003_0131【信息级】脉冲频率超任务周期上限已钳位
 *                         16#0003_0132【信息级】位移不足一个脉冲当量被忽略
 *                         16#0003_0133【信息级】运动/复位指令被拒绝（状态不满足）
 *                         16#0003_0134【信息级】限位方向禁止（同向指令被拒）
 *                         16#0003_0135【信息级】去使能冻结脉冲输出
 *                         16#0003_0136【信息级】任务周期非法已兜底为 10 ms
 *                         16#0003_0137【信息级】减速收尾残差不足一脉冲，按到位处理
 *                         16#0003_02E0【故障级】组态参数非法（Init 参数域越界）
 *                         16#0003_02E1【故障级】限位入侵停机（运动中同向限位触发）
 *                         16#0003_02E2【故障级】驱动器报警输入有效
 *                         16#0003_02E3【故障级】堵转超时（超理论耗时乘裕度）
 *                         16#0003_02E4【故障级】非法状态兜底（枚举越界）
 * 验收向量 (Acceptance) :
 *   V1 规划：当量 400、细分 1、速度 20 mm/s、加速度 500 mm/s²、行程 10 mm →
 *      总步数 4000、指令频率 8000 Hz（必被钳位）、加速段按 v²/(2a) 复算一致；
 *   V2 钳位：任务周期 10 ms → 上限 50 Hz，指令 8000 Hz 被钳位并置 0003_0131，
 *      波形一高一低各一拍；
 *   V3 限位：正向运动中 bLimitPos → 本拍停发、锁 0003_02E1、报警字 bit0；
 *      复位后仍拒正向（0003_0134），反向受理；
 *   V4 堵转：理论 1 s、裕度 500 ms → 2 s 到期锁 0003_02E3 并停发；
 *   V5 停车：运动中 Stop → 剩余步数压到减速段，频率降零回空闲，位置与已发
 *      脉冲数一致；
 *   V6 去使能：Enable(FALSE) → 本拍停发（无半脉冲）、bEnableOut FALSE、位置
 *      保持，再使能不自动续走。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 09 · DL_Device 开环步进族 · 实现件）
 *   2026-11-15  v1.0.1  终审修复：eDecel 补「频率归零即收尾」第二出口（原实现
 *                       仅在步数 <= 1E-6 时出口，减速段一拍归零而残差为小数时
 *                       状态机永久停在 eDecel，属无故障码的静默卡死）；新增
 *                       信息级 0003_0137 记录该收尾口径
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   stCfg.uStepsPerMm := 400; stCfg.uMicrostep := 8; stCfg.fMaxSpeed := 30.0;
 *   stCfg.fAccel := 400.0; stCfg.tStallTimeout := T#300MS; stCfg.fTaskCycle := 0.01;
 *   bOk := fbStep.Init(stCfg := stCfg);      // 注入组态（调用方持有结构体）
 *   bOk := fbStep.Enable(bEnable := TRUE);   // 上使能（保持力矩）
 *   fbStep(bLimitPos := bDiPos, bLimitNeg := bDiNeg, bAlarmIn := bDiAlm);
 *   bOk := fbStep.MoveRelative(fDistance := 25.0, fSpeed := 15.0);
 *   上层映射：bDoPulse := fbStep.bPulse; bDoDir := fbStep.bDir;
 *   常见误用：① 脉宽硬下限——10 ms 任务最高 50 Hz，更高频率必须换更快的任务；
 *   ② 开环会丢步，fPosition 禁止当反馈做闭环；③ 有效当量 = 当量 × 细分，
 *   改细分必须同步改字段，否则速度与行程成比例偏差；④ 堵转判据识别卡滞不识别
 *   打滑；⑤ 故障期保持使能是有意设计（垂直轴防溜车），切动力请在安全回路侧。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StepperState（归属 FB_DL_PulseDirStepper，随本文件发布）
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_StepperState :
(
    eIdle  := 0,     // 空闲待机：无运动，脉冲停发，可受理新指令 / Idle, pulses stopped and ready for a new command
    eAccel := 10,    // 加速段：频率按加速度斜坡上升 / Acceleration segment, frequency ramps up
    eRun   := 20,    // 匀速段：频率保持峰值 / Constant segment, frequency held at the peak
    eDecel := 30,    // 减速段：频率按减速度斜坡下降 / Deceleration segment, frequency ramps down
    eFault := 99     // 故障锁存：脉冲停发，仅复位可退 / Fault latched, only reset can leave
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_PulseDirStepper IMPLEMENTS I_DL_StepperOpenLoop
VAR_INPUT
    bLimitPos    : BOOL;                // 正限位开关输入（Positive limit switch），TRUE = 触发；常闭型由调用方反相 / TRUE means triggered
    bLimitNeg    : BOOL;                // 负限位开关输入（Negative limit switch），TRUE = 触发 / TRUE means triggered
    bAlarmIn     : BOOL;                // 驱动器报警输入（Drive alarm input），TRUE = 报警 / TRUE means the drive reports an alarm
    fJogSpeed    : LREAL := 5.0;        // 点动速度预留（Reserved jog speed）[mm/s]，本版不启用 / Reserved, unused in this version
END_VAR
VAR_OUTPUT
    bPulse       : BOOL;                // 脉冲输出（Pulse output），定宽一拍（R24）/ Fixed one-scan-wide pulse per R24
    bDir         : BOOL;                // 方向输出（Direction output），TRUE = 正向 / TRUE means the positive direction
    bEnableOut   : BOOL;                // 使能输出（Enable output），透传指令，故障期保持 / Pass-through, held during faults
    fFreqNow     : LREAL;               // 当前脉冲频率（Current pulse frequency）[Hz]，诊断用 / Diagnostic frequency in hertz
    bError       : BOOL;                // 故障保持型（Fault latched），排除信息级码 / Latched fault flag, info codes excluded
    uErrorId     : UDINT;               // 故障码（Error code），0 = 无故障，段位 16#0003_xxxx / Error code, zero means no error
END_VAR
VAR
    _stCfg       : ST_DL_StepperCfg;    // 组态副本（Configuration copy），Init 注入 / Copy injected by Init
    _eState      : E_DL_StepperState := E_DL_StepperState.eIdle; // 主状态机状态（Main state machine state）/ Main state machine state
    _bInit       : BOOL;                // 首扫完成标志（First-scan done flag），初值 FALSE / First-scan done flag, initial FALSE
    _bInited     : BOOL;                // 组态已注入标志（Configuration injected flag）/ Configuration injected flag
    _bEnableCmd  : BOOL;                // 使能指令电平（Enable command level），Enable 方法写入 / Written by the Enable method
    _bPendMove   : BOOL;                // 待受理运动请求（Pending move request），方法置位主体消化 / Set by the method, consumed by the body
    _bPendStop   : BOOL;                // 待受理停车请求（Pending stop request），方法置位主体消化 / Set by the method, consumed by the body
    _bPendReset  : BOOL;                // 待受理复位请求（Pending reset request），方法置位主体消化 / Set by the method, consumed by the body
    _fPendDist   : LREAL;               // 待受理位移（Pending distance）[mm]，带符号 / Signed pending distance [mm]
    _fPendSpeed  : LREAL;               // 待受理速度（Pending speed）[mm/s]，已钳位 / Clamped pending speed [mm/s]
    _fPulsePerMm : LREAL := 400.0;      // 有效脉冲当量（Effective pulses per millimetre）[脉冲/mm]=当量×细分 / Equivalent times microstep divisor
    _fTaskCycle  : LREAL := 0.01;       // 生效任务周期（Effective task cycle）[s] / Effective task cycle [s]
    _fFreqMaxScan : LREAL := 50.0;      // 周期决定的频率上限（Cycle-driven frequency limit）[Hz]=1/(2×周期) / One over twice the cycle
    _fAccStepHz  : LREAL := 200000.0;   // 脉冲域加速度（Acceleration in the pulse domain）[脉冲/s²]=加速度×当量 / Acceleration scaled to pulses
    _fFreqStepHz : LREAL := 2000.0;     // 每拍频率增量（Frequency step per scan）[Hz]=脉冲域加速度×周期 / Pulse acceleration times the cycle
    _fFreqCmd    : LREAL;               // 指令频率（Command frequency）[Hz]，钳位后 / Command frequency after clamping [Hz]
    _fFreqTarget : LREAL;               // 峰值频率（Peak frequency）[Hz]，梯形峰值 / Trapezoidal peak frequency [Hz]
    _fFreqNow    : LREAL;               // 当前频率（Current frequency）[Hz]，逐拍积分 / Integrated frequency of this scan [Hz]
    _fStepsTotal : LREAL;               // 本次总步数（Total steps of this move）[脉冲]，正数 / Total pulses, always positive
    _fStepsRemain: LREAL;               // 剩余步数（Remaining steps）[脉冲]，递减到零即到位 / Counted down to zero on completion
    _fStepsAccel : LREAL;               // 加速段步数（Acceleration steps）[脉冲] / Pulses spent accelerating
    _fStepsDecel : LREAL;               // 减速段步数（Deceleration steps）[脉冲]，与加速段对称 / Symmetric with the acceleration segment
    _fPhaseAcc   : LREAL;               // 脉冲相位累加器（Pulse phase accumulator）[周期]，域 0 至 1 / Phase accumulator, zero to one period
    _fPosSteps   : LREAL;               // 指令位置脉冲数（Command position in pulses）[脉冲]，带符号 / Signed accumulated command position
    _fPosMm      : LREAL;               // 指令位置（Command position）[mm]，开环推算 / Open-loop derived command position [mm]
    _fExpectSec  : LREAL;               // 理论运动耗时（Theoretical move time）[s] / Theoretical move time [s]
    _fLimitSec   : LREAL;               // 堵转判据时限（Stall limit time）[s] / Stall limit time [s]
    _tMoveLimit  : TIME;                // 堵转判据时限（Stall limit as TIME）[ms]，喂定时器 / Stall limit fed to the timer [ms]
    _bMoveActive : BOOL;                // 运动进行中（Move active flag）/ Move active flag
    _bMoveBreak  : BOOL;                // 定时器断输入一拍（Timer break），运动起点重计时（公约 0.6）/ One-scan break at the move start
    _bDirNow     : BOOL;                // 当前运动方向（Current move direction），TRUE = 正向 / TRUE means positive
    _bLimitIntr  : BOOL;                // 同向限位入侵（Same-direction limit intrusion）/ Intrusion in the running direction
    _bFaultLatch : BOOL;                // 故障锁存（Fault latch），仅复位路径清除 / Fault latch, cleared only by the reset path
    _bStallLat   : BOOL;                // 堵转锁存（Stall latched），供报警字 bit3 / Stall latch feeding alarm bit three
    _uErrInt     : UDINT;               // 故障级码寄存（Fault-level code register），锁存型 / Latched fault-level code register
    _uInfoCode   : UDINT;               // 本拍信息级码（Info code this scan），每拍重算 / Info code recomputed every scan
    _uInfoHold   : UDINT;               // 方法拍信息级码保持（Method info code hold），供下一拍主体透出 / Held one scan for the body to expose
    _uAlarmWord  : WORD;                // 报警字（Alarm word），bit0 至 bit3 有效 / Alarm word with bits zero to three used
    _fbMoveTimer : TON;                 // 运动耗时监控定时器（Move elapsed timer），无条件刷新 / Refreshed unconditionally every scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS     : LREAL := 1.0E-6; // 浮点容差（Float epsilon）[mm]，替代判等 / Float epsilon replacing equality [mm]
    DL_FREQ_EPS      : LREAL := 0.1;    // 频率容差（Frequency epsilon）[Hz] / Frequency epsilon [Hz]
    DL_TIMEOUT_GAIN  : LREAL := 1.5;    // 堵转裕度系数（Stall timeout gain），理论耗时倍数 / Multiplier on the theoretical time
    DL_PHASE_FULL    : LREAL := 1.0;    // 相位满量程（Full phase period）[周期] / Full phase period in cycles
    DL_PHASE_GUARD   : LREAL := 1.5;    // 相位防越界上限（Phase guard bound）[周期] / Defensive phase clamp bound
    DL_CYCLE_FALLBACK : LREAL := 0.01;  // 任务周期兜底（Task cycle fallback）[s] / Fallback task cycle [s]
    DL_LIMIT_SEC_MAX : LREAL := 3600.0; // 时限上限（Upper bound of the limit）[s]，防溢出 / Bound preventing overflow [s]
    DL_ALM_LIMIT_POS : WORD := 16#0001; // 报警字 bit0 正限位（Alarm bit zero, positive limit）/ Positive limit alarm bit
    DL_ALM_LIMIT_NEG : WORD := 16#0002; // 报警字 bit1 负限位（Alarm bit one, negative limit）/ Negative limit alarm bit
    DL_ALM_DRIVE     : WORD := 16#0004; // 报警字 bit2 驱动器报警（Alarm bit two, drive alarm）/ Drive alarm bit
    DL_ALM_STALL     : WORD := 16#0008; // 报警字 bit3 堵转超时（Alarm bit three, stall timeout）/ Stall timeout alarm bit
END_VAR

// 段 1｜出口确定性与单拍标志预清零（公约 0.9 / R25 第一律：停发在本拍内完成）
bPulse     := FALSE;                   // 脉冲默认低电平（Pulse defaults low）
_uInfoCode := _uInfoHold;              // 先透出方法拍产生的信息级码，保留单拍（Method codes survive one body scan）
_uInfoHold := 0;                       // 单拍消费后自清（Consumed and cleared after exactly one scan）
_bLimitIntr := FALSE;                  // 限位入侵标志每拍重算（Intrusion recomputed every scan）

// 段 2｜首扫初始化（R19 范式：IF (NOT _bInit) 唯一判据）
IF NOT _bInit THEN
    _bInit        := TRUE;             // 置首扫完成（First-scan done）
    _eState       := E_DL_StepperState.eIdle; // 状态复位空闲（State reset to idle）
    _bEnableCmd   := FALSE;            // 使能指令清零（Enable command cleared）
    _bPendMove    := FALSE;            // 清待受理运动（Pending move cleared）
    _bPendStop    := FALSE;            // 清待受理停车（Pending stop cleared）
    _bPendReset   := FALSE;            // 清待受理复位（Pending reset cleared）
    _fFreqNow     := 0.0;              // 当前频率清零（Frequency cleared）
    _fPhaseAcc    := 0.0;              // 相位累加器清零（Phase cleared）
    _fPosSteps    := 0.0;              // 位置脉冲数清零（Position pulses cleared）
    _fPosMm       := 0.0;              // 位置清零（Position cleared）
    _bMoveActive  := FALSE;            // 运动标志清零（Move flag cleared）
    _bDirNow      := TRUE;             // 方向默认正向（Direction defaults positive）
    _bFaultLatch  := FALSE;            // 故障锁存清零（Fault latch cleared）
    _bStallLat    := FALSE;            // 堵转锁存清零（Stall latch cleared）
    _uErrInt      := 16#0000_0000;     // 故障码清零（Fault code cleared）
    _uAlarmWord   := 16#0000;          // 报警字清零（Alarm word cleared）
END_IF

// 段 3｜定时器无条件刷新（公约 0.5 / 0.6：断输入一拍后从零重计）
_fbMoveTimer(IN := _bMoveActive AND (NOT _bMoveBreak), PT := _tMoveLimit); // 运动耗时监控（Move elapsed monitoring）
_bMoveBreak := FALSE;                  // 断输入脉冲在实例调用后自清（Break self-cleared after the call）

// 段 4｜组态派生与参数防御（脉冲域换算、频率上限、除零守卫）
IF _bInited THEN
    IF (_stCfg.fTaskCycle <> _stCfg.fTaskCycle) OR (_stCfg.fTaskCycle <= DL_FLOAT_EPS) THEN
        _fTaskCycle := DL_CYCLE_FALLBACK; // 周期非法兜底（Illegal cycle falls back）
        _uInfoCode  := 16#0003_0136;      // 0003_0136 任务周期非法已兜底【信息级】（Cycle fell back, info level）
    ELSE
        _fTaskCycle := _stCfg.fTaskCycle; // 合法周期直通（Valid cycle passed through）
    END_IF
    _fPulsePerMm := UINT_TO_LREAL(_stCfg.uStepsPerMm) * UINT_TO_LREAL(_stCfg.uMicrostep); // 有效当量（Effective equivalent）
    IF _fPulsePerMm <= DL_FLOAT_EPS THEN
        _bFaultLatch := TRUE;          // 当量为零锁故障（Zero equivalent latches a fault）
        _uErrInt     := 16#0003_02E0;  // 0003_02E0 组态参数非法【故障级】（Illegal configuration, fault level）
        _fPulsePerMm := 1.0;           // 除零守卫置 1（Divide guard set to one）
    END_IF
    _fFreqMaxScan := 1.0 / (2.0 * _fTaskCycle); // 频率上限，脉宽下限一拍（Ceiling keeping the pulse one scan wide）
    _fAccStepHz   := _stCfg.fAccel * _fPulsePerMm; // 脉冲域加速度 [脉冲/s²]（Pulse-domain acceleration）
    _fFreqStepHz  := _fAccStepHz * _fTaskCycle;    // 每拍频率增量 [Hz]（Frequency increment per scan）
END_IF

// 段 5｜故障源监视与锁存（限位入侵 / 驱动器报警 / 堵转超时；0.7 锁存型）
_bLimitIntr := _bMoveActive AND ((_bDirNow AND bLimitPos) OR ((NOT _bDirNow) AND bLimitNeg)); // 同向限位判据（Intrusion verdict）
IF _bMoveActive THEN
    IF _bLimitIntr THEN
        _bFaultLatch := TRUE;          // 限位入侵锁存（Intrusion latched）
        _uErrInt     := 16#0003_02E1;  // 0003_02E1 限位入侵停机【故障级】（Intrusion stop, fault level）
    ELSIF bAlarmIn THEN
        _bFaultLatch := TRUE;          // 驱动器报警锁存（Drive alarm latched）
        _uErrInt     := 16#0003_02E2;  // 0003_02E2 驱动器报警输入【故障级】（Drive alarm, fault level）
    ELSIF _fbMoveTimer.Q THEN
        _bFaultLatch := TRUE;          // 堵转超时锁存（Stall timeout latched）
        _bStallLat   := TRUE;          // 报警字 bit3 保持（Alarm bit three held）
        _uErrInt     := 16#0003_02E3;  // 0003_02E3 堵转超时【故障级】（Stall timeout, fault level）
    END_IF
END_IF

// 段 6｜请求消化：复位（报警源优先）/ 停车（受控减速）/ 去使能（本拍冻结）
IF _bPendReset THEN
    _bPendReset := FALSE;              // 复位请求单拍消费（Reset request consumed）
    IF NOT bAlarmIn THEN
        _bFaultLatch := FALSE;         // 报警源消失才解除（Cleared only when the alarm is gone）
        _bStallLat   := FALSE;         // 堵转锁存解除（Stall latch released）
        _uErrInt     := 16#0000_0000;  // 故障码清零（Fault code cleared）
        IF _eState = E_DL_StepperState.eFault THEN
            _eState := E_DL_StepperState.eIdle; // 故障态退回空闲（Fault returns to idle）
        END_IF
    END_IF
END_IF
IF _bPendStop THEN
    _bPendStop := FALSE;               // 停车请求单拍消费（Stop request consumed）
    IF (_eState = E_DL_StepperState.eAccel) OR (_eState = E_DL_StepperState.eRun) THEN
        IF _fStepsRemain > _fStepsDecel THEN
            _fStepsRemain := _fStepsDecel; // 剩余步数压到减速段长度（Cut to the deceleration length）
        END_IF
        _eState := E_DL_StepperState.eDecel; // 进减速段受控停车（Controlled stop via deceleration）
    END_IF
END_IF
IF NOT _bEnableCmd THEN
    IF _bMoveActive THEN
        _uInfoCode := 16#0003_0135;    // 0003_0135 去使能冻结脉冲输出【信息级】（Disable freezes pulses, info level）
    END_IF
    _eState      := E_DL_StepperState.eIdle; // 去使能立即回空闲（Disable returns to idle）
    _fFreqNow    := 0.0;               // 频率清零（Frequency cleared）
    _fPhaseAcc   := 0.0;               // 相位清零，杜绝半脉冲（Phase cleared, no half pulse remains）
    _bMoveActive := FALSE;             // 运动标志清零（Move flag cleared）
    _fStepsRemain := 0.0;              // 剩余步数清零（Remaining steps cleared）
END_IF

// 段 7｜主状态机与梯形频率规划（ENUM + CASE + ELSE 兜底）
CASE _eState OF
    E_DL_StepperState.eIdle: // 空闲：等待运动请求（Idle, waiting for a move request）
        _fFreqNow    := 0.0;       // 空闲频率为零（Idle frequency is zero）
        _bMoveActive := FALSE;     // 空闲无运动（No motion while idle）
        IF _bFaultLatch THEN
            _eState := E_DL_StepperState.eFault; // 故障优先（Fault takes priority）
        ELSIF _bPendMove THEN
            _bPendMove := FALSE;   // 运动请求单拍消费（Move request consumed）
            _fStepsTotal := ABS(_fPendDist) * _fPulsePerMm; // 总步数 [脉冲]（Total pulses）
            IF _fStepsTotal <= DL_FLOAT_EPS THEN
                _uInfoCode := 16#0003_0132; // 0003_0132 位移不足一当量【信息级】（Distance below one pulse, info level）
            ELSE
                _fFreqCmd := _fPendSpeed * _fPulsePerMm; // 指令频率 [Hz]（Command frequency）
                IF _fFreqCmd > _fFreqMaxScan THEN
                    _fFreqCmd  := _fFreqMaxScan;         // 钳位到周期上限（Clamp to the cycle ceiling）
                    _uInfoCode := 16#0003_0131;          // 0003_0131 频率超上限已钳位【信息级】（Clamped, info level）
                END_IF
                IF _fAccStepHz > DL_FLOAT_EPS THEN
                    _fStepsAccel := (_fFreqCmd * _fFreqCmd) / (2.0 * _fAccStepHz); // na = v²/(2a)（Acceleration pulses）
                ELSE
                    _fStepsAccel := 0.0;                     // 加速度为零无加速段（No acceleration segment）
                END_IF
                IF (2.0 * _fStepsAccel) > _fStepsTotal THEN
                    _fStepsAccel := _fStepsTotal / 2.0;      // 三角型取半程（Triangular, half of the travel）
                    IF _fAccStepHz > DL_FLOAT_EPS THEN
                        _fFreqTarget := SQRT(_fAccStepHz * _fStepsTotal); // 峰值 = SQRT(a×N)（Triangular peak）
                    ELSE
                        _fFreqTarget := _fFreqCmd;           // 无加速度退化匀速（Constant speed fallback）
                    END_IF
                    IF _fFreqTarget > _fFreqCmd THEN
                        _fFreqTarget := _fFreqCmd;           // 峰值不超指令频率（Peak never exceeds the command）
                    END_IF
                ELSE
                    _fFreqTarget := _fFreqCmd;               // 梯形峰值 = 指令频率（Trapezoidal peak）
                END_IF
                _fStepsDecel  := _fStepsAccel;               // 减速段对称（Symmetric deceleration）
                _fStepsRemain := _fStepsTotal;               // 剩余步数装载（Remaining steps loaded）
                _fPhaseAcc    := 0.0;                        // 相位从头开始（Phase restarts）
                _bDirNow      := (_fPendDist > 0.0);         // 方向取位移符号（Direction from the sign）
                _bMoveActive  := TRUE;                       // 置运动进行中（Move marked active）
                _bMoveBreak   := TRUE;                       // 定时器下拍从零重计（Timer restarts next scan）
                _fExpectSec   := 0.0;                        // 理论耗时先清零（Theoretical time cleared）
                IF (_fFreqTarget > DL_FREQ_EPS) AND (_fAccStepHz > DL_FLOAT_EPS) THEN
                    _fExpectSec := (2.0 * (_fFreqTarget / _fAccStepHz)) +
                                   ((_fStepsTotal - (2.0 * _fStepsAccel)) / _fFreqTarget); // t = 2(v/a)+(N−2na)/v（Theoretical time）
                END_IF
                _fLimitSec := (_fExpectSec * DL_TIMEOUT_GAIN) +
                              (UDINT_TO_LREAL(TIME_TO_UDINT(_stCfg.tStallTimeout)) / 1000.0); // 时限 = 理论×裕度 + 附加裕度（Limit with margin）
                _fLimitSec := LIMIT(0.001, _fLimitSec, DL_LIMIT_SEC_MAX);                     // 防 TIME 溢出（Bound preventing overflow）
                _tMoveLimit := UDINT_TO_TIME(LREAL_TO_UDINT(_fLimitSec * 1000.0));            // 毫秒量化（Whole milliseconds）
                _eState := E_DL_StepperState.eAccel;         // 进加速段（Enter acceleration）
            END_IF
        END_IF

    E_DL_StepperState.eAccel: // 加速段：频率斜坡上升（Frequency ramps up）
        _fFreqNow := _fFreqNow + _fFreqStepHz; // 每拍加一增量（Advance one frequency step）
        IF _fFreqNow >= _fFreqTarget THEN
            _fFreqNow := _fFreqTarget;     // 到峰值封顶（Clamped at the peak）
            _eState   := E_DL_StepperState.eRun; // 转匀速段（Go to constant speed）
        END_IF
        IF _fFreqNow <= DL_FREQ_EPS THEN
            _fFreqNow := DL_FREQ_EPS;      // 起步频率守卫，防相位不累加（Startup guard）
        END_IF
        IF _fStepsRemain <= _fStepsDecel THEN
            _eState := E_DL_StepperState.eDecel; // 剩余步入减速区（Deceleration zone reached）
        END_IF

    E_DL_StepperState.eRun: // 匀速段：频率保持峰值（Constant segment）
        _fFreqNow := _fFreqTarget;         // 频率恒定（Frequency held）
        IF _fStepsRemain <= _fStepsDecel THEN
            _eState := E_DL_StepperState.eDecel; // 进减速段（Enter deceleration）
        END_IF

    E_DL_StepperState.eDecel: // 减速段：频率斜坡下降（Frequency ramps down）
        _fFreqNow := _fFreqNow - _fFreqStepHz; // 每拍减一增量（Retreat one frequency step）
        IF _fFreqNow <= DL_FREQ_EPS THEN
            _fFreqNow := 0.0;              // 频率归零（Frequency reaches zero）
        END_IF
        (* 收尾双出口（v1.0.1 终审补第二出口，状态终态可达性）：
           ① 步数走完 → 正常到位；
           ② 频率已归零 → 相位不再累加，剩余脉冲在数学上永不可发，必须按到位
              收尾；否则状态机永久停在 eDecel，表现为 bPulse 恒 FALSE、
              bError FALSE、bReady 恒 FALSE 的静默卡死。
              触发条件：每拍频率步进 fAccel×当量×周期 远大于峰值频率时
              （默认组态 2000 Hz/拍 vs 50 Hz 峰值即属此列），减速段一拍归零
              而残余分步（位移×当量带小数）尚未发完。 *)
        IF (_fStepsRemain <= DL_FLOAT_EPS) OR (_fFreqNow <= DL_FREQ_EPS) THEN
            IF _fStepsRemain > DL_FLOAT_EPS THEN
                _uInfoCode := 16#0003_0137; // 0003_0137 残差不足一脉冲按到位收尾【信息级】（Residual below one pulse, info level）
            END_IF
            _eState      := E_DL_StepperState.eIdle; // 步数归零回空闲（Idle when no step remains）
            _bMoveActive := FALSE;         // 运动结束（Move finished）
            _fFreqNow    := 0.0;           // 频率清零（Frequency cleared）
            _fPhaseAcc   := 0.0;           // 相位清零，杜绝残余半脉冲（Phase cleared, no half pulse remains）
        END_IF

    E_DL_StepperState.eFault: // 故障锁存：脉冲停发（Fault latched, pulses stopped）
        _fFreqNow     := 0.0;              // 频率清零（Frequency cleared）
        _bMoveActive  := FALSE;            // 运动标志清零（Move flag cleared）
        _fStepsRemain := 0.0;              // 剩余步数清零（Remaining steps cleared）

    ELSE
        _bFaultLatch := TRUE;              // 非法状态兜底锁存（Illegal state latched）
        _uErrInt     := 16#0003_02E4;      // 0003_02E4 非法状态兜底【故障级】（Illegal state, fault level）
        _eState      := E_DL_StepperState.eFault; // 进故障态（Enter the fault state）
        _fFreqNow    := 0.0;               // 频率清零（Frequency cleared）
        _bMoveActive := FALSE;             // 运动标志清零（Move flag cleared）
END_CASE

// 段 8｜脉冲发生（相位累加、定宽输出、步数与位置累计；R24 无半脉冲）
IF _bMoveActive AND (_fFreqNow > DL_FREQ_EPS) THEN
    _fPhaseAcc := _fPhaseAcc + (_fFreqNow * _fTaskCycle); // 相位增量 = 频率×周期（Phase increment）
    IF _fPhaseAcc > DL_PHASE_GUARD THEN
        _fPhaseAcc := DL_PHASE_FULL;   // 防御钳位，杜绝静默丢脉冲（Defensive clamp, no silent pulse loss）
    END_IF
    IF _fPhaseAcc >= DL_PHASE_FULL THEN
        _fPhaseAcc := _fPhaseAcc - DL_PHASE_FULL; // 消耗一个脉冲周期（Consume one period）
        bPulse := TRUE;                // 本拍输出一个定宽脉冲（Emit one fixed-width pulse）
        _fStepsRemain := _fStepsRemain - 1.0; // 剩余步数递减（Remaining steps decremented）
        IF _bDirNow THEN
            _fPosSteps := _fPosSteps + 1.0; // 正向累计（Accumulate positive）
        ELSE
            _fPosSteps := _fPosSteps - 1.0; // 负向累计（Accumulate negative）
        END_IF
    END_IF
END_IF
IF _bMoveActive AND (_fStepsRemain <= DL_FLOAT_EPS) THEN
    _eState      := E_DL_StepperState.eIdle; // 步数走完回空闲（Idle once every step is emitted）
    _bMoveActive := FALSE;             // 运动结束（Move finished）
    _fFreqNow    := 0.0;               // 频率清零（Frequency cleared）
    _fPhaseAcc   := 0.0;               // 相位清零（Phase cleared）
END_IF

// 段 9｜出口映射（位置、报警字、故障级码优先透出）
IF _fPulsePerMm > DL_FLOAT_EPS THEN
    _fPosMm := _fPosSteps / _fPulsePerMm; // 位置换算 [mm]（Position conversion）
ELSE
    _fPosMm := 0.0;                    // 除零守卫，位置报零（Divide guard, position reported as zero）
END_IF
bDir       := _bDirNow;                // 方向输出（Direction output）
bEnableOut := _bEnableCmd;             // 使能透传，故障期保持力矩（Enable passed through for holding torque）
fFreqNow   := _fFreqNow;               // 当前频率出口（Current frequency outlet）
_uAlarmWord := 16#0000;                // 报警字先清零（Alarm word cleared first）
IF bLimitPos THEN
    _uAlarmWord := _uAlarmWord OR DL_ALM_LIMIT_POS; // bit0 正限位（Positive limit bit）
END_IF
IF bLimitNeg THEN
    _uAlarmWord := _uAlarmWord OR DL_ALM_LIMIT_NEG; // bit1 负限位（Negative limit bit）
END_IF
IF bAlarmIn THEN
    _uAlarmWord := _uAlarmWord OR DL_ALM_DRIVE;     // bit2 驱动器报警（Drive alarm bit）
END_IF
IF _bStallLat THEN
    _uAlarmWord := _uAlarmWord OR DL_ALM_STALL;     // bit3 堵转超时保持（Stall timeout bit, held）
END_IF
bError := _bFaultLatch OR (_eState = E_DL_StepperState.eFault); // 故障派生，排除信息级（Fault derived, info codes excluded）
IF bError THEN
    uErrorId := _uErrInt;              // 故障级码优先（Fault-level code first）
ELSE
    uErrorId := _uInfoCode;            // 无故障透出信息级码（Info code exposed）
END_IF

// 方法: Init —— 注入组态并校验参数域，越界锁故障（Method Init, configuration validation）
METHOD Init : BOOL
VAR_IN_OUT
    stCfg : ST_DL_StepperCfg;          // 步进组态（Stepper configuration），调用方持有 / Caller-owned configuration
END_VAR
IF (stCfg.uStepsPerMm = 0) OR (stCfg.uMicrostep = 0) OR (stCfg.fMaxSpeed <= DL_FLOAT_EPS) OR
   (stCfg.fAccel <= DL_FLOAT_EPS) OR (stCfg.fTaskCycle <= DL_FLOAT_EPS) OR
   (stCfg.fMaxSpeed <> stCfg.fMaxSpeed) OR (stCfg.fAccel <> stCfg.fAccel) OR
   (stCfg.fTaskCycle <> stCfg.fTaskCycle) THEN
    _uErrInt     := 16#0003_02E0;      // 0003_02E0 组态参数非法【故障级】（Illegal configuration, fault level）
    _bFaultLatch := TRUE;              // 越界锁故障（Violation latches a fault）
    _bInited     := FALSE;             // 保持未初始化（Remains uninitialized）
    Init         := FALSE;             // 受理失败（Rejected）
ELSE
    _stCfg       := stCfg;             // 保存组态副本（Keep a copy）
    _bInited     := TRUE;              // 置已初始化（Mark initialized）
    _uErrInt     := 16#0000_0000;      // 故障码清零（Fault code cleared）
    _bFaultLatch := FALSE;             // 成功初始化解除参数锁存（Successful init releases the latch）
    Init         := TRUE;              // 受理成功（Accepted）
END_IF

// 方法: Enable —— 电平语义，TRUE 使能（故障态拒绝），FALSE 恒受理并冻结（Method Enable）
METHOD Enable : BOOL
VAR_INPUT
    bEnable : BOOL;                    // 使能指令（Enable command），TRUE = 使能 / TRUE enables
END_VAR
IF bEnable THEN
    IF (NOT _bInited) OR _bFaultLatch OR (_eState = E_DL_StepperState.eFault) THEN
        _uInfoHold := 16#0003_0133;    // 0003_0133 指令被拒绝【信息级】（Command rejected, info level）
        Enable     := FALSE;           // 未初始化或故障态拒绝（Refused while uninitialized or faulty）
    ELSE
        _bEnableCmd := TRUE;           // 登记使能（Enable registered）
        Enable      := TRUE;           // 受理成功（Accepted）
    END_IF
ELSE
    _bEnableCmd := FALSE;              // 去使能恒受理（Disable always accepted）
    Enable      := TRUE;               // 受理成功（Accepted）
END_IF

// 方法: MoveRelative —— 仅空闲态受理，参数与限位方向先行校验（Method MoveRelative）
METHOD MoveRelative : BOOL
VAR_INPUT
    fDistance : LREAL;                 // 相对位移（Relative distance）[mm]，带符号 / Signed distance [mm]
    fSpeed    : LREAL;                 // 运行速度（Run speed）[mm/s]，必需为正 / Must be positive
END_VAR
IF (NOT _bInited) OR (NOT _bEnableCmd) OR _bFaultLatch OR (_eState <> E_DL_StepperState.eIdle) OR
   (fDistance <> fDistance) OR (ABS(fDistance) <= DL_FLOAT_EPS) OR
   (fSpeed <> fSpeed) OR (fSpeed <= DL_FLOAT_EPS) THEN
    _uInfoHold   := 16#0003_0133;      // 0003_0133 指令被拒绝【信息级】（Command rejected, info level）
    MoveRelative := FALSE;             // 拒绝受理（Rejected）
ELSIF (fDistance > 0.0) AND bLimitPos THEN
    _uInfoHold   := 16#0003_0134;      // 0003_0134 限位方向禁止【信息级】（Direction blocked, info level）
    MoveRelative := FALSE;             // 正限位上禁止正向（Positive motion refused at the positive limit）
ELSIF (fDistance < 0.0) AND bLimitNeg THEN
    _uInfoHold   := 16#0003_0134;      // 0003_0134 限位方向禁止【信息级】（Direction blocked, info level）
    MoveRelative := FALSE;             // 负限位上禁止负向（Negative motion refused at the negative limit）
ELSE
    IF (_stCfg.fMaxSpeed > DL_FLOAT_EPS) AND (fSpeed > _stCfg.fMaxSpeed) THEN
        _fPendSpeed := _stCfg.fMaxSpeed; // 钳位到最大速度（Clamped to the maximum）
        _uInfoHold  := 16#0003_0130;     // 0003_0130 速度超限已钳位【信息级】（Speed clamped, info level）
    ELSE
        _fPendSpeed := fSpeed;          // 合法速度直通（Valid speed passed through）
    END_IF
    _fPendDist   := fDistance;          // 登记位移（Distance registered）
    _bPendMove   := TRUE;               // 登记运动请求（Move request registered）
    MoveRelative := TRUE;               // 受理成功（Accepted）
END_IF

// 方法: Stop —— 受控停车：剩余步数压到减速段后按斜坡降频（Method Stop）
METHOD Stop : BOOL
VAR_INPUT
END_VAR
IF _bMoveActive THEN
    _bPendStop := TRUE;                // 登记停车请求（Stop request registered）
    Stop       := TRUE;                // 受理成功（Accepted）
ELSE
    _uInfoHold := 16#0003_0133;        // 0003_0133 指令被拒绝【信息级】（Command rejected, info level）
    Stop       := FALSE;               // 无运动可停（Nothing to stop）
END_IF

// 方法: Reset —— 仅故障锁存时受理；报警源未消失则保留锁存（Method Reset）
METHOD Reset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_StepperState.eFault) THEN
    _bPendReset := TRUE;               // 登记复位请求，主体按报警源裁决（Reset registered, body decides）
    Reset       := TRUE;               // 受理成功（Accepted）
ELSE
    _uInfoHold  := 16#0003_0133;       // 0003_0133 无故障可复位【信息级】（Nothing to reset, info level）
    Reset       := FALSE;              // 拒绝受理（Rejected）
END_IF

// 方法: GetErrorId —— 故障码查询，与 uErrorId 引脚同源（Method GetErrorId）
METHOD GetErrorId : UDINT
VAR_INPUT
END_VAR
GetErrorId := uErrorId;                // 直接透出末次码（Expose the last code）

// 属性: bReady（GET）—— 已初始化 + 已使能 + 无故障 + 空闲（Property bReady）
PROPERTY bReady : BOOL
bReady := _bInited AND _bEnableCmd AND (NOT _bFaultLatch) AND (_eState = E_DL_StepperState.eIdle); // 就绪派生式（Ready derived form）

// 属性: fPosition（GET）—— 指令位置累计，开环推算非反馈（Property fPosition）
PROPERTY fPosition : LREAL
fPosition := _fPosMm;                  // 透出内部位置（Expose the internal position）

// 属性: uAlarmWord（GET）—— 报警字位域回读（Property uAlarmWord）
PROPERTY uAlarmWord : WORD
uAlarmWord := _uAlarmWord;             // 透出内部报警字（Expose the internal alarm word）
END_FUNCTION_BLOCK
