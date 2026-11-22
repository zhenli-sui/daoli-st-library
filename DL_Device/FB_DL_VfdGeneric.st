(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VfdGeneric
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / TP），零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，实现 I_DL_VfdDrive）
 * 功能简述 (Function)   : 通用变频器端子型控制功能块。正/反转端子互斥
 *                         （出口断言 + 冲突安全侧停止）、点动优先覆盖运行、
 *                         多段速表/模拟量给定双通道频率设定（越界钳位）、
 *                         频率给定模拟量域线性映射、指令-反馈校验窗、驱动
 *                         故障锁存与复位端子定宽脉冲重试；状态机
 *                         E_DL_VfdState + CASE + ELSE 兜底。
 * 接口实现 (Implements) : I_DL_VfdDrive。接口 OUT 列同名成员（eState/
 *                         fFreqSetpoint/fFreqActual/bRunning/bFault/
 *                         uErrorId）按 R22 以只读 PROPERTY GET 承载（内部
 *                         镜像同源），非接口成员 bRunFwdOut/bRunRevOut/
 *                         bJogOut/bFaultResetOut/fFreqRefPercent/uPresetCode
 *                         保留 VAR_OUTPUT；方法 CmdRun/CmdStop/CmdJog/
 *                         SetFrequency/SelectPresetSpeed/CmdReset 全部在
 *                         本文件尾部落地。
 * 开源溯源 (Origin)     : 来源标签 lbp-basic-process / lbp-device
 *                         （RAW_NOTES_R6 S-1 + S-4：变频器端子标准信号集
 *                         ——正反转互斥、点动优先、多段速 DI 组合、模拟
 *                         量频率给定线性映射、故障复位端子脉冲等行业公知
 *                         工程惯例，公开技术资料，仅借鉴通用信号域语义；
 *                         状态机、钳位与互斥实现、故障码按本库红线独立
 *                         设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防除零/防越界/非有限值
 *                         防御/浮点容差比较 ✓｜R5 全变量中英双语同行注释 ✓
 *                         R6 ENUM+CASE+ELSE ✓｜R7 三个定时器/边缘/脉冲实例
 *                         主体最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1/R23 本块为纯事件型状态机（BOOL 指令/反馈 +
 *                         频率标量直通计算，无积分/滤波类连续量同步语义），
 *                         免首扫，无内部初始化标志。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0250
 *                         驱动故障 / 0003_0251 启动反馈超时 / 0003_0252
 *                         非法状态，R15 锁存仅复位脉冲路径可清；【信息级】
 *                         0003_0106 正反转指令冲突 / 0003_0107 频率设定
 *                         钳位/段速选择越界（瞬时型每拍重算，0.15）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 2 条：
 *                         ① 信息级码：规格原分配 0003_0103/0104，经与子库
 *                           VERSION.md 故障码表核对，R5 已占用 0102~0104
 *                           （AnalogTransmitter），依公约 0.7 冲突顺延为
 *                           0003_0106/0107（0105 经终审裁定空置：重启抑制
 *                           拒绝统一沿用 DolMotor 既有语义码位 0003_0208，
 *                           见 FB_DL_StarDeltaMotor 终审记录）。
 *                         ② 点动频率：规格设计要点"点动频率取 aPresetFreq[1]
 *                           （注释声明）"落为引脚注释声明——本块不因点动切
 *                           换频率通道（端子型变频器点动频率由驱动器内部组
 *                           态承担），段速 1 兼作点动频率域供现场整定选用。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *   2026-11-15  v1.0.1  终审修复【致命】复位端子脉冲触发时序：原实现
 *                       _bResetPulseReq 于主体末尾同拍自清，TP 实例（段 1
 *                       最前部刷新）永远采不到 TRUE 入参，bFaultResetOut
 *                       恒 FALSE，故障复位端子脉冲永不输出（验收向量 V5
 *                       不成立，R13 逐拍推演复现）。修法：自清动作移至
 *                       TP 实例调用之后。另补点动频率引脚注释声明（R11
 *                       偏离②）。引脚契约零变更。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_VfdGeneric IMPLEMENTS I_DL_VfdDrive
VAR_INPUT
    bDriveEnable     : BOOL;            // 驱动使能/上电（Drive enable），FALSE → 未使能态全部输出切断 / Drive enable, FALSE cuts off all outputs
    bCmdRunFwd       : BOOL;            // 正转运行指令（Run forward command），电平生效 / Run forward command, level effective
    bCmdRunRev       : BOOL;            // 反转运行指令（Run reverse command），电平生效；与正转同拍为真 → 冲突安全侧停止 / Run reverse command, conflict with forward stops safely
    bCmdJogFwd       : BOOL;            // 正向点动指令（Jog forward command），电平生效，优先级高于运行指令；点动频率不在本块内切换通道——端子型惯例由驱动器内部点动频率组态承担，亦可现场将 aPresetFreq[1] 整定为点动频率域（段速 1 兼作点动频率） / Jog forward command, level effective, priority over run; jog frequency not switched by this block, use drive-internal jog frequency or tune aPresetFreq[1] as the jog frequency domain
    bFbRunning       : BOOL;            // 运行反馈（Running feedback），TRUE=驱动输出运行中 / Running feedback, TRUE = drive output running
    bFbFault         : BOOL;            // 驱动故障反馈（Drive fault feedback），TRUE=故障 / Drive fault feedback, TRUE = faulty
    bFbAtSpeed       : BOOL;            // 频率到达反馈（At-speed feedback），TRUE=输出频率到达设定容差带 / At-speed feedback, TRUE = output frequency reached setpoint band
    fFreqCmd         : REAL;            // 频率设定（Frequency command）[Hz]，0..fFreqMax，越界钳位信息级 / Frequency command [Hz], clamped with info code
    fFreqActual      : REAL;            // 频率反馈（Frequency feedback）[Hz]，非有限值防御 / Frequency feedback [Hz], non-finite defended
    aPresetFreq      : ARRAY[1..7] OF REAL; // 多段速频率表（Preset speed table）[Hz]，段速值由现场整定注入 / Preset speed table [Hz], field-tuned values injected
    nPresetSel       : USINT;           // 段速选择（Preset speed select），0=模拟量给定、1..7=段速，越界按 0 处理并置码 / Preset select, 0 = analog reference, 1..7 = steps, out-of-range treated as 0 with code
    fFreqMax         : REAL := 50.0;    // 频率上限（Max frequency）[Hz]，默认 50.0 / Maximum frequency [Hz], default 50.0
    tFbWindow        : TIME := T#1S;    // 指令-反馈校验窗口（Feedback check window），T#0S=免校验 / Feedback check window, T#0S disables the check
    tFaultResetPulse : TIME := T#500MS; // 故障复位脉冲宽度（Fault reset pulse）/ Fault reset pulse width
    bReset           : BOOL;            // 故障复位请求（Fault reset request），上升沿生效 / Fault reset request, rising edge effective
END_VAR

VAR_OUTPUT
    bRunFwdOut      : BOOL;             // 正转端子输出（Run forward terminal）/ Run forward terminal output
    bRunRevOut      : BOOL;             // 反转端子输出（Run reverse terminal）/ Run reverse terminal output
    bJogOut         : BOOL;             // 点动端子输出（Jog terminal）/ Jog terminal output
    bFaultResetOut  : BOOL;             // 故障复位端子输出（Fault reset terminal），tFaultResetPulse 定宽单发 / Fault reset terminal, one-shot fixed-width pulse
    fFreqRefPercent : REAL;             // 频率给定模拟量输出（Frequency reference analog out）[%]，0~100 线性映射 fFreqMax / Analog frequency reference [%], linear over fFreqMax
    uPresetCode     : USINT;            // 段速选择码输出（Preset speed code），映射 DI 多段速端子组合 0..7 / Preset speed code mapped to DI terminal group 0..7
END_VAR

VAR
    _eState         : E_DL_VfdState := E_DL_VfdState.eDisabled; // 内部状态机步序（Internal state step），外部经属性只读 / Internal state, read-only via property
    _bFaultLatch    : BOOL;             // 故障锁存标志（Fault latch flag），仅复位脉冲路径清除 / Fault latch flag, cleared only via reset pulse path
    _uErrorIdInt    : UDINT;            // 内部故障码寄存（Internal error register），故障级与信息级共用 / Internal error register, fault and info codes share it
    _uInfoCode      : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算（0.15）/ Transient info code recomputed each cycle
    _bPendRunFwd    : BOOL;             // 方法正转保持锁存（Method run-forward hold latch）/ Method run-forward hold latch
    _bPendRunRev    : BOOL;             // 方法反转保持锁存（Method run-reverse hold latch）/ Method run-reverse hold latch
    _bJogHold       : BOOL;             // 方法点动保持锁存（Method jog hold latch）/ Method jog hold latch
    _bPendReset     : BOOL;             // 方法复位请求（Method reset request）/ Method reset request
    _bResetPulseReq : BOOL;             // 复位脉冲单拍触发请求（Reset pulse trigger request），置位一拍 / One-cycle reset pulse trigger request
    _fFreqMethodVal : REAL;             // 方法频率设定值（Method frequency value）[Hz] / Frequency value set via method
    _bFreqMethodAct : BOOL;             // 方法频率设定激活（Method frequency active），激活后覆盖引脚给定 / Method frequency active, overrides pin reference
    _uPresetMethod  : USINT;            // 方法段速选择值（Method preset select value）/ Preset select value set via method
    _bPresetMethodAct : BOOL;           // 方法段速选择激活（Method preset select active）/ Method preset select active flag
    _fFreqMaxEff    : REAL := 50.0;     // 防御后频率上限（Sanitized max frequency）[Hz] / Sanitized maximum frequency
    _fFreqCmdEff    : REAL := 0.0;      // 防御后模拟量给定（Sanitized analog command）[Hz]，非数回零 / Sanitized analog command, NaN falls back to zero
    _fFreqSetInt    : REAL := 0.0;      // 钳位后生效频率设定（Effective clamped setpoint）[Hz] / Effective clamped frequency setpoint
    _fFreqActHold   : REAL := 0.0;      // 末次有效频率反馈（Last valid frequency feedback）[Hz] / Last valid frequency feedback hold carrier
    _uPresetSelEff  : USINT;            // 钳位后生效段速选择（Effective clamped preset select），0..7 / Effective preset select clamped to 0..7
    _bRunFwd        : BOOL;             // 合成正转指令（Merged run-forward command），引脚 OR 方法锁存 / Merged forward command, pin OR method latch
    _bRunRev        : BOOL;             // 合成反转指令（Merged run-reverse command），引脚 OR 方法锁存 / Merged reverse command, pin OR method latch
    _bJog           : BOOL;             // 合成点动指令（Merged jog command），引脚 OR 方法锁存 / Merged jog command, pin OR method latch
    _bConflict      : BOOL;             // 正反转同拍冲突（Forward/reverse conflict this cycle）/ Forward-reverse conflict flag
    _bFbWinEn       : BOOL;             // 反馈校验窗使能（Feedback window enable），窗口参数大于零有效 / Feedback window enable, active when window above zero
    _bInFbWin       : BOOL;             // 反馈校验窗计时条件（Feedback window timing condition）/ Timing condition of feedback window
    _fbTrigReset    : R_TRIG;           // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTonFbWindow  : TON;              // 启动反馈校验窗定时器（Startup feedback window timer）/ Startup feedback window timer
    _fbTpResetPulse : TP;               // 复位端子定宽脉冲定时器（Reset terminal pulse timer），IEC 标准 TP / Reset terminal pulse timer, IEC standard TP
END_VAR

METHOD CmdRun : BOOL
VAR_INPUT
    bFwd : BOOL; // 方向选择（Direction select），TRUE=正转 / FALSE=反转 / TRUE = forward, FALSE = reverse
END_VAR
IF _bFaultLatch OR (_eState = E_DL_VfdState.eFault) OR (_eState = E_DL_VfdState.eDisabled) THEN
    CmdRun := FALSE;          // 故障/未使能态拒绝（Rejected in fault or disabled state）
ELSE
    IF bFwd THEN
        _bPendRunFwd := TRUE; // 登记正转保持锁存（Register forward hold latch）
        _bPendRunRev := FALSE; // 互斥注销反转锁存（Cancel opposite latch）
    ELSE
        _bPendRunRev := TRUE; // 登记反转保持锁存（Register reverse hold latch）
        _bPendRunFwd := FALSE; // 互斥注销正转锁存（Cancel opposite latch）
    END_IF
    CmdRun := TRUE;           // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 停止指令：撤销运行/点动锁存，无条件受理。
 *      Method CmdStop - revokes run and jog latches, unconditionally accepted.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdStop : BOOL
VAR_INPUT
END_VAR
_bPendRunFwd := FALSE;        // 撤销正转锁存（Release forward latch）
_bPendRunRev := FALSE;        // 撤销反转锁存（Release reverse latch）
_bJogHold    := FALSE;        // 撤销点动保持（Release jog hold）
CmdStop := TRUE;              // 无条件受理（Unconditionally accepted）

(*------------------------------------------------------------------------------
 * 方法: CmdJog —— 点动指令（bFwd=TRUE 登记保持 / FALSE 撤销）。故障态拒绝。
 *      Method CmdJog - jog hold register/release, rejected in fault state.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdJog : BOOL
VAR_INPUT
    bFwd : BOOL; // 点动方向（Jog direction），TRUE=正向登记 / FALSE=撤销保持 / TRUE = register, FALSE = release
END_VAR
IF _bFaultLatch OR (_eState = E_DL_VfdState.eFault) THEN
    CmdJog := FALSE;          // 故障态拒绝（Rejected in fault state）
ELSE
    _bJogHold := bFwd;        // 登记或撤销点动保持（Register or release jog hold）
    CmdJog := TRUE;           // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: SetFrequency —— 频率设定 [Hz]，越界/非有限值拒绝返回 FALSE。
 *      Method SetFrequency - frequency set, out-of-range or NaN returns FALSE.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD SetFrequency : BOOL
VAR_INPUT
    fHz : REAL; // 频率设定值（Frequency value）[Hz]，域 0..fFreqMax / Frequency value [Hz], range 0..fFreqMax
END_VAR
IF (fHz <> fHz) OR (fHz < 0.0) OR (fHz > _fFreqMaxEff) THEN
    SetFrequency := FALSE;    // 非数或越域拒绝（Rejected on NaN or out of range）
ELSE
    _fFreqMethodVal := fHz;   // 登记方法频率设定（Register method frequency value）
    _bFreqMethodAct := TRUE;  // 激活方法给定通道（Activate method reference channel）
    SetFrequency := TRUE;     // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: SelectPresetSpeed —— 多段速选择，0=模拟量给定、1..7=段速，越界拒绝。
 *      Method SelectPresetSpeed - preset select, 0 = analog, 1..7 = steps.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD SelectPresetSpeed : BOOL
VAR_INPUT
    nIdx : USINT; // 段速索引（Preset index），0=模拟量给定 / 1..7=段速 / Preset index, 0 = analog reference, 1..7 = steps
END_VAR
IF nIdx <= 7 THEN
    _uPresetMethod := nIdx;   // 登记方法段速选择（Register method preset value）
    _bPresetMethodAct := TRUE; // 激活方法段速通道（Activate method preset channel）
    SelectPresetSpeed := TRUE; // 受理成功（Accepted）
ELSE
    SelectPresetSpeed := FALSE; // 越界拒绝（Rejected on out-of-range index）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位指令，返回是否受理（存在锁存故障时为 TRUE）。
 *      Method CmdReset - reset command, returns TRUE only when latch exists.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_VfdState.eFault) THEN
    _bPendReset := TRUE;      // 登记复位请求，主体状态机消化（Register reset request, consumed by body）
    CmdReset := TRUE;         // 可复位（Resettable）
ELSE
    CmdReset := FALSE;        // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前状态机状态只读视图。
 *      Property eState (GET) - read-only view of the current state machine state.
 *------------------------------------------------------------------------------*)
    END_METHOD

// ============================================================================
// 段 1｜定时器与边缘检测实例无条件周期刷新（R7：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all timer and edge instances (R7)
// ============================================================================
_fbTrigReset(CLK := bReset);
_bFbWinEn := (tFbWindow > T#0S);      // 窗口为零 = 免校验（Zero window = check disabled）
_bInFbWin := ((_eState = E_DL_VfdState.eRunningFwd) OR (_eState = E_DL_VfdState.eRunningRev))
             AND (NOT bFbRunning) AND _bFbWinEn; // 运行态且反馈未到才计时（Timing only while running and feedback pending）
_fbTonFbWindow(IN := _bInFbWin, PT := tFbWindow);
_fbTpResetPulse(IN := _bResetPulseReq, PT := tFaultResetPulse); // 复位端子定宽脉冲（Fixed-width reset terminal pulse）
_bResetPulseReq := FALSE;             // 单拍触发请求在 TP 采样后立即自清：TP 于本拍见到
                                      // TRUE 并起振，下一拍入参回落 FALSE，定宽由 TP 保持
                                      // （One-cycle trigger cleared right after TP sampling）

// ============================================================================
// 段 2｜参数防御（0.8：非数自比检测，默认值先赋）+ 指令合成与钳位
//      Parameter sanitation (0.8 NaN self-compare) + command merge and clamping
// ============================================================================
_uInfoCode := 0;                      // 本拍信息级码先归零，事件段重算（Info code preset zero, recomputed in event chain）
_fFreqMaxEff := fFreqMax;             // 频率上限镜像（Max frequency mirror）
IF _fFreqMaxEff <> _fFreqMaxEff THEN  // 非数自比检测（NaN self-compare test）
    _fFreqMaxEff := 50.0;             // 回落默认上限（Fallback to default max）
END_IF
IF ABS(_fFreqMaxEff) < 1E-6 THEN
    _fFreqMaxEff := 1E-6;             // 防除零：上限退化时钳最小正值（Divide-by-zero guard, degenerate max clamped to tiny positive）
END_IF

IF _bFreqMethodAct THEN
    _fFreqCmdEff := _fFreqMethodVal;  // 方法设定覆盖引脚给定（Method value overrides pin reference）
ELSE
    _fFreqCmdEff := fFreqCmd;         // 引脚模拟量给定（Pin analog reference）
END_IF
IF _fFreqCmdEff <> _fFreqCmdEff THEN  // 非数自比检测（NaN self-compare test）
    _fFreqCmdEff := 0.0;              // 非数给定回零（NaN reference falls back to zero）
END_IF
IF _fFreqCmdEff < 0.0 THEN
    _fFreqCmdEff := 0.0;              // 负给定下限钳位（Negative reference clamped to zero）
    _uInfoCode := 16#0003_0107;       // 0003_0107 频率设定钳位【信息级】/ Frequency clamped, info level
END_IF
IF _fFreqCmdEff > _fFreqMaxEff THEN
    _fFreqCmdEff := _fFreqMaxEff;     // 超上限钳位（Reference clamped to max）
    _uInfoCode := 16#0003_0107;       // 0003_0107 频率设定钳位【信息级】/ Frequency clamped, info level
END_IF

IF fFreqActual = fFreqActual THEN     // 频率反馈有效性（Frequency feedback validity）
    _fFreqActHold := fFreqActual;     // 更新末次有效反馈（Update last valid feedback）
END_IF                                 // 非有限值保持末次有效值（Non-finite holds last valid）

// 段速选择钳位：越界按 0 处理并置码（Preset select clamped, out-of-range as 0 with code）
IF _bPresetMethodAct THEN
    _uPresetSelEff := _uPresetMethod; // 方法段速选择覆盖引脚（Method preset overrides pin）
ELSIF nPresetSel <= 7 THEN
    _uPresetSelEff := nPresetSel;     // 引脚段速选择合法（Pin preset select valid）
ELSE
    _uPresetSelEff := 0;              // 越界按模拟量给定处理（Out-of-range treated as analog reference）
    _uInfoCode := 16#0003_0107;       // 0003_0107 段速选择越界【信息级】/ Preset select out of range, info level
END_IF

// 生效频率设定：段速优先，模拟量给定兜底（Effective setpoint: preset first, analog fallback）
IF (_uPresetSelEff >= 1) AND (_uPresetSelEff <= 7) THEN
    _fFreqSetInt := aPresetFreq[_uPresetSelEff];       // 取段速表值（Take preset table value, index proven 1..7）
    IF _fFreqSetInt <> _fFreqSetInt THEN
        _fFreqSetInt := 0.0;                           // 段速值非数回零防御（NaN preset falls back to zero）
    END_IF
ELSE
    _fFreqSetInt := _fFreqCmdEff;     // 模拟量给定通道（Analog reference channel）
END_IF

// 指令合成与冲突判定（Command merge and conflict evaluation）
_bRunFwd := bCmdRunFwd OR _bPendRunFwd; // 合成正转（Merged forward）
_bRunRev := bCmdRunRev OR _bPendRunRev; // 合成反转（Merged reverse）
_bJog := bCmdJogFwd OR _bJogHold;       // 合成点动，优先级最高（Merged jog, highest priority）
_bConflict := _bRunFwd AND _bRunRev;    // 同拍正反转冲突（Same-cycle conflict）
IF _bConflict THEN
    _uInfoCode := 16#0003_0106;         // 0003_0106 正反转指令冲突【信息级】/ Forward-reverse conflict, info level
END_IF

// ============================================================================
// 段 3｜驱动故障全局监视（优先级最高）：故障反馈置锁存
//      Drive fault global monitor (highest priority): fault feedback latches
// ============================================================================
IF bFbFault THEN
    _bFaultLatch := TRUE;               // 驱动故障锁存（Drive fault latch）
    _uErrorIdInt := 16#0003_0250;       // 0003_0250 驱动故障【故障级】/ Drive fault, fault level
    _eState      := E_DL_VfdState.eFault; // 强制故障态（Force fault state）
ELSIF (_eState = E_DL_VfdState.eRunningFwd) OR (_eState = E_DL_VfdState.eRunningRev) THEN
    IF _bFbWinEn AND _fbTonFbWindow.Q AND (NOT bFbRunning) THEN
        _bFaultLatch := TRUE;           // 启动反馈超时锁存（Startup feedback timeout latch）
        _uErrorIdInt := 16#0003_0251;   // 0003_0251 启动反馈超时【故障级】/ Startup feedback timeout, fault level
        _eState      := E_DL_VfdState.eFault;
    END_IF
END_IF

// ============================================================================
// 段 4｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
IF _bFaultLatch OR (_eState = E_DL_VfdState.eFault) THEN
    CASE _eState OF
        E_DL_VfdState.eFault: // 故障锁存态：复位端子定宽脉冲重试恢复
            IF _bPendReset OR _fbTrigReset.Q THEN
                _bResetPulseReq := TRUE;        // 触发复位端子脉冲（Trigger reset terminal pulse）
                _bPendReset     := FALSE;       // 消费复位请求（Consume reset request）
                IF NOT bFbFault THEN
                    _bFaultLatch := FALSE;      // 驱动故障已消失，解除锁存（Drive fault cleared, release latch）
                    _uErrorIdInt := 0;          // 故障码清零（Error code cleared）
                    _eState      := E_DL_VfdState.eReady; // 回就绪态（Back to ready）
                END_IF
            END_IF
        ELSE // 锁存标志与状态不一致兜底：强制同步进故障态（Latch/state mismatch fallback）
            _eState := E_DL_VfdState.eFault;
    END_CASE
ELSIF NOT bDriveEnable THEN
    _eState     := E_DL_VfdState.eDisabled; // 未使能态：全部输出切断（Disabled: all outputs cut off）
    _bJogHold   := FALSE;                   // 撤销点动保持（Release jog hold）
    _bPendRunFwd := FALSE;                  // 撤销方法运行锁存（Release method run latches）
    _bPendRunRev := FALSE;
ELSE
    CASE _eState OF

        E_DL_VfdState.eDisabled: // 未使能态：等待使能
            _eState := E_DL_VfdState.eReady; // 使能完成转就绪（Enabled, to ready）

        E_DL_VfdState.eReady: // 就绪态：评估点动/运行指令
            IF _bJog THEN
                _eState := E_DL_VfdState.eJogging; // 点动优先受理（Jog accepted with priority）
            ELSIF _bConflict THEN
                // 正反转同拍冲突：安全侧保持停止（Conflict: hold safe-side stop）
            ELSIF _bRunFwd THEN
                _eState := E_DL_VfdState.eRunningFwd; // 正转受理（Forward accepted）
            ELSIF _bRunRev THEN
                _eState := E_DL_VfdState.eRunningRev; // 反转受理（Reverse accepted）
            END_IF

        E_DL_VfdState.eRunningFwd: // 正转运行态
            IF _bJog THEN
                _eState := E_DL_VfdState.eJogging; // 点动覆盖运行（Jog overrides run）
            ELSIF _bConflict OR (NOT _bRunFwd) THEN
                _eState := E_DL_VfdState.eReady;   // 冲突或指令撤销：安全侧回就绪（Conflict or command dropped: safe-side to ready）
            END_IF

        E_DL_VfdState.eRunningRev: // 反转运行态
            IF _bJog THEN
                _eState := E_DL_VfdState.eJogging; // 点动覆盖运行（Jog overrides run）
            ELSIF _bConflict OR (NOT _bRunRev) THEN
                _eState := E_DL_VfdState.eReady;   // 冲突或指令撤销：安全侧回就绪（Conflict or command dropped: safe-side to ready）
            END_IF

        E_DL_VfdState.eJogging: // 点动态：点动电平维持
            IF NOT _bJog THEN
                IF _bConflict THEN
                    _eState := E_DL_VfdState.eReady;             // 冲突安全侧回就绪（Conflict: safe-side to ready）
                ELSIF _bRunFwd THEN
                    _eState := E_DL_VfdState.eRunningFwd;        // 点动结束回正转（Jog ended, back to forward）
                ELSIF _bRunRev THEN
                    _eState := E_DL_VfdState.eRunningRev;        // 点动结束回反转（Jog ended, back to reverse）
                ELSE
                    _eState := E_DL_VfdState.eReady;             // 点动结束回就绪（Jog ended, back to ready）
                END_IF
            END_IF

        ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
            _bFaultLatch := TRUE;                // 故障锁存（Fault latched）
            _uErrorIdInt := 16#0003_0252;        // 0003_0252 非法状态【故障级】/ Illegal state, fault level
            _eState      := E_DL_VfdState.eFault;
    END_CASE
END_IF

// ============================================================================
// 段 5｜输出推导 + 正/反转端子互斥出口断言（硬约束：两端子恒不可同真）
//      Output derivation + forward/reverse terminal exclusivity exit assertion
// ============================================================================
bRunFwdOut := (_eState = E_DL_VfdState.eRunningFwd); // 正转端子随状态（Forward terminal follows state）
bRunRevOut := (_eState = E_DL_VfdState.eRunningRev); // 反转端子随状态（Reverse terminal follows state）
bJogOut    := (_eState = E_DL_VfdState.eJogging);    // 点动端子随状态（Jog terminal follows state）
IF bRunFwdOut AND bRunRevOut THEN
    bRunFwdOut := FALSE;                  // 断言对调：异常同真时双断保安全（Assertion fallback: cut both on impossible condition）
    bRunRevOut := FALSE;
    _eState    := E_DL_VfdState.eReady;   // 强制回就绪（Force back to ready）
END_IF
IF (_eState = E_DL_VfdState.eDisabled) OR (_eState = E_DL_VfdState.eFault) THEN
    bRunFwdOut := FALSE;                  // 未使能/故障态全端子必断（Assertion: terminals off in disabled/fault）
    bRunRevOut := FALSE;
    bJogOut    := FALSE;
END_IF
bFaultResetOut := _fbTpResetPulse.Q;      // 复位端子定宽脉冲输出（Reset terminal pulse output）
uPresetCode := _uPresetSelEff;            // 段速码输出（Preset code output）
fFreqRefPercent := _fFreqCmdEff * (100.0 / _fFreqMaxEff); // 模拟量域线性映射，除数已证明非零（Linear analog mapping, divisor proven non-zero）

(*------------------------------------------------------------------------------
 * 方法: CmdRun —— 正/反转运行指令（受理为保持锁存）。故障/未使能态拒绝。
 *      Method CmdRun - run command held as latch, rejected in fault/disabled.
 *------------------------------------------------------------------------------*)






PROPERTY eState : E_DL_VfdState
eState := _eState;            // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: fFreqSetpoint（GET）—— 钳位后生效频率设定 [Hz]。
 *      Property fFreqSetpoint (GET) - effective clamped frequency setpoint [Hz].
 *------------------------------------------------------------------------------*)
PROPERTY fFreqSetpoint : REAL
fFreqSetpoint := _fFreqSetInt; // 返回生效设定镜像（Return effective setpoint mirror）

(*------------------------------------------------------------------------------
 * 属性: fFreqActual（GET）—— 频率反馈 [Hz]，非有限值时保持末次有效值。
 *      Property fFreqActual (GET) - frequency feedback [Hz], holds last valid on non-finite.
 *------------------------------------------------------------------------------*)
PROPERTY fFreqActual : REAL
fFreqActual := _fFreqActHold; // 返回末次有效反馈保持值（Return last valid feedback hold value）

(*------------------------------------------------------------------------------
 * 属性: bRunning（GET）—— 运行反馈（正转/反转/点动态且反馈确认）。
 *      Property bRunning (GET) - running feedback (running states AND confirmed).
 *------------------------------------------------------------------------------*)
PROPERTY bRunning : BOOL
bRunning := ((_eState = E_DL_VfdState.eRunningFwd) OR (_eState = E_DL_VfdState.eRunningRev)
          OR (_eState = E_DL_VfdState.eJogging)) AND bFbRunning; // 状态且反馈确认派生式（State AND feedback derived form）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info-level codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_VfdState.eFault); // 显式排除信息级派生式（Explicit derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（0=无故障；无故障级锁存时透出本拍
 *         信息级码，故障级优先，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last error code (fault-level latched code has
 *      priority, transient info code shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_VfdState.eFault) THEN
    uErrorId := _uErrorIdInt; // 故障级码优先透出（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;   // 无故障时透出本拍信息级码（Transient info code when no fault）
END_IF
END_FUNCTION_BLOCK
