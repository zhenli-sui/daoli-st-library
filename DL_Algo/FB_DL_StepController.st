(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StepController
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / LIMIT / TON / R_TRIG /
 *                         TIME_TO_REAL / UINT_TO_REAL / REAL_TO_UINT），零厂商方言
 * 分类     (Category)   : 算法功能块（Function Block，分级步进控制族）
 * 功能描述 (Function)   : 分级步进控制器。把连续偏差映射为离散级数（0 至级数
 *                         上限），供多级加热器组、多台泵 / 压缩机、多组冷却塔
 *                         等"阶梯式执行器阵列"使用。内置级间双向死区（上升与
 *                         下降迟滞，防边界抖动频繁投切）、最小驻留时间（防
 *                         短周期反复投切损伤设备）、可选均衡轮换（多台同型
 *                         设备轮流投切，均摊磨损）；输出拓扑二选一：累积型
 *                         （多级依次投入，前缀为真）或单级型（仅一台投入）。
 * 职责边界 (Scope)     : 本块只做"偏差 → 级数 → 阵列电平"的纯逻辑编排，不含
 *                         任何 PID 运算、不含任何阀门/泵的启停时序与反馈校验；
 *                         启停时序由被控设备自身的驱动块承担。
 * 无状态机声明 (No FSM) : 本块为连续运算型（逐拍数值裁定），无顺序状态步序，
 *                         故不设状态枚举、无 CASE 分支；与库内连续运算型先例
 *                         FB_DL_LowPassFilter 同类（红线 R6 的 ENUM + CASE +
 *                         ELSE 仅约束"存在顺序状态"的 POU）。泳道 D 契约明确
 *                         规定"无新增枚举"，故本文件不引入任何 DUT。
 *                         bCumulative 属输出接线拓扑选择，不构成算法变体，本块
 *                         禁止再叠加任何模式参数（避免巨无霸参数块）。
 * 开源溯源 (Origin)     : 原创实现（参考 LBP CtrlStp 语义）。来源标签
 *                         lbp-step-controller / lgf-technology（RAW_NOTES_R8 条目
 *                         S-9：LBP 库 CtrlStp 类"偏差分级 + 级间迟滞 + 最小
 *                         驻留"的公开功能描述与参数域），仅借鉴功能分类、参数域
 *                         与状态语义；分级公式、双向迟滞判据、轮换取模、防死锁
 *                         循环与全部故障码体系按本库红线 clean-room 独立编写，
 *                         未复制任何源码行。许可证说明：LBP 为闭源免费库，其
 *                         公开描述仅作功能分类与参数域参考，本文件为独立实现，
 *                         无代码复制、无许可证传染。
 * 故障码 (Codes)        : 段位 16#0002_xxxx（已核对 DL_Algo 台账：01xx 至 18xx
 *                         为既有族段，1Axx 为本轮新建"分级步进族"，无冲突）。
 *                         【信息级】0002_1A01 最小驻留未到换级被拒、
 *                         0002_1A02 级数越界已钳位、0002_1A03 级带宽非法回默认、
 *                         0002_1A04 死区过大已钳至半级带、
 *                         0002_1A05 设定或实际非有限级数保持；
 *                         【故障级】0002_1A06 级带宽退化无法运算（锁存，仅复位可
 *                         清）。信息级码只进 uErrorId，不置 bError。
 * 公约遵循 (Convention) : 0.2 全部信息级码不进报警链，bError 为显式排除信息级
 *                         码的派生式（仅 16#0002_1A06 故障级码置位）。0.6 换级
 *                         当拍强制给驻留定时器断输入一拍，保证计时从零重启（避免
 *                         "改周期后计时不清零"的幽灵故障）。0.7 锁存型故障码与
 *                         瞬时型信息码分寄存器存放。0.14 WHILE 循环带防死锁
 *                         计数器、除法前置判零、浮点容差比较。0.16 级数上限、
 *                         默认带宽、默认死区、浮点容差全部常量化。
 * 规格偏离 (R11 Dev.)   : D1 级输出数组上界以字面量 7 声明（等价于常量
 *                         DL_STEP_MAX_STAGES 减一），规避同块内常量在声明区
 *                         前向引用导致的编译告警；语义与规格一致。D2 轮换偏移
 *                         采用"规格要求的条件减法 + 防死锁计数器"实现，轮换
 *                         步长先按级数取模归约，保证条件减法循环最多执行一次。
 *                         D3 16#0002_1A06 的触发条件落地为"钳位后级带宽仍不大于
 *                         浮点容差"的终止分支（级数钳位已保证不小于 1，故只在
 *                         极端参数下可达），语义与规格"钳位后仍无法运算"一致。
 *                         D4 累积型 + 轮换同开时，规格步骤 6 的映射式
 *                         （abStage[i] := i < nOut）会使投入台数由 nActiveStage
 *                         变为 nOut（偏移非零时多投一台），与"多级依次投入"
 *                         语义冲突；本实现改为"以轮换偏移为起点的循环前缀"判据，
 *                         台数恒等于 nActiveStage，单级型仍沿用规格公式，输出
 *                         位移语义不变。
 * 验收向量 (Acceptance) :
 *   V1  fSetpoint=50、fActual=50 → nActiveStage=0；偏差 25、4 级、带宽 100、
 *       死区 0 → nActiveStage=1（死区非零时加级门槛为"单级带宽 + 死区"，
 *       属有意迟滞，见 V3）
 *   V2  偏差由 25 逐步增大（45 至 70 至 95）→ 每拍最多加 1 级，不跨级跳变
 *   V3  fDeadband=5：偏差落在级界正负 5 以内 → 不换级（双向迟滞生效）
 *   V4  tMinDwell=T#10S 内在驻留期连续请求换级 → nActiveStage 不变、
 *       uErrorId=16#0002_1A01（每拍重算）
 *   V5  bCumulative=FALSE 且 nActiveStage=2 → 仅 abStage[1] 为 TRUE，其余 FALSE
 *   V6  bRotate=TRUE、nRotateStep=1：两次投切后 nRotateOffset 递增，物理级输出
 *       相对逻辑级位移 1 位（第二次投切后输出起点后移）
 *   V7  fBandSpan=0 → 带宽回默认 100.0 并置 uErrorId=16#0002_1A03（不产生除零）
 *   V8  fDeadband=30、带宽 100、4 级 → 死区钳至半级带 12.5 并置
 *       uErrorId=16#0002_1A04
 * 已知限制 (Limits)     : 1 换级速率为每拍最多一级，级数多而带宽窄时上升沿存在
 *                         多拍延迟，属防跳变的有意设计。2 tMinDwell 小于 2 倍
 *                         扫描周期时驻留保护失效（不可知，本块不校验）；T#0S
 *                         等价无驻留，存在高频投切风险，仅建议调试期使用。
 *                         3 累积型输出为"前缀为真"，相邻级同时为真属正常语义；
 *                         "相邻级不得同时为真"只对单级型成立。
 *                         4 本块不做投切次数均衡的长期统计（nSwitchCount 为总量
 *                         计数），按台数均摊的寿命管理需上层另建统计。
 * 红线自检 (Redline)    : 零全局变量表访问 ✓｜零外部变量声明 ✓｜零物理地址直写 ✓
 *                         纯 IEC 61131-3 ✓｜防除零 + 防越界 + 浮点容差 + 循环上限 ✓
 *                         全变量中英双语同行注释 ✓｜TON / R_TRIG 主体最前部无条件 ✓
 *                         FUNCTION_BLOCK 与 END_FUNCTION_BLOCK 成对 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · 泳道 D · DL_Algo 分级步进族 1Axx）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_StepController
VAR_INPUT
    bEnable      : BOOL := FALSE;                  // 使能（Enable），FALSE=全部级复位为 0 / Enable, FALSE resets every stage to 0
    bReset       : BOOL := FALSE;                  // 复位（Reset），上升沿把级数与轮换偏移清零 / Reset stage count and rotation offset on rising edge
    fSetpoint    : REAL := 0.0;                    // 设定值（Setpoint）[工程单位]，与 fActual 同量纲 / Setpoint [EU], same unit as fActual
    fActual      : REAL := 0.0;                    // 实际值（Actual value）[工程单位] / Actual value [EU]
    nStages      : UINT := 4;                      // 级数（Stage count）[-]，域 1 至 8，越界钳位 / Stage count, clamped into 1 to 8
    fBandSpan    : REAL := 100.0;                  // 级带宽（Band span）[工程单位]，偏差绝对值满量程对应全部级投入 / Band span [EU], full deflection engages all stages
    fDeadband    : REAL := 2.0;                    // 级间死区（Stage deadband）[工程单位]，迟滞半宽，负值取绝对值 / Deadband [EU], hysteresis half width, negative uses ABS
    tMinDwell    : TIME := T#10S;                  // 最小驻留（Min dwell time），换级后须停留此时间才允许再切 / Minimum dwell after a stage change
    bCumulative  : BOOL := TRUE;                   // 累积拓扑（Cumulative topology），TRUE=多级依次投入，FALSE=单级互斥 / TRUE cumulative, FALSE single-stage
    bRotate      : BOOL := FALSE;                  // 均衡轮换（Rotation），TRUE=每次投切换物理设备偏移 / Rotation across identical devices
    nRotateStep  : UINT := 1;                      // 轮换步长（Rotation step）[-]，按级数取模归约 / Rotation step, reduced modulo the stage count
END_VAR

VAR_OUTPUT
    nActiveStage  : UINT := 0;                     // 当前投入级数（Active stage）[-]，域 0 至 nStages / Active stage count, 0 to nStages
    abStage       : ARRAY[0..7] OF BOOL;           // 各级输出（Stage outputs），索引 0=第 1 级 / Stage outputs, index 0 is the first stage
    nRotateOffset : UINT := 0;                     // 轮换偏移（Rotation offset）[-]，域 0 至 nStages-1 / Rotation offset, 0 to nStages-1
    nSwitchCount  : UDINT := 0;                    // 投切次数（Switch counter），级数每变化一次加一 / Switch counter, one per stage change
    bAtMaxStage   : BOOL;                          // 已达最大级（At max stage），满出力警示 / At max stage, full output warning
    bAtMinStage   : BOOL;                          // 已回零级（At min stage）/ At min stage
    bError        : BOOL;                          // 故障标志（Fault flag），仅故障级码置位 / Fault flag, fault-level codes only
    uErrorId      : UDINT := 0;                    // 错误码（Error code），0=无错误，段位 16#0002_1Axx / Error code, 0 = none, family 16#0002_1Axx
END_VAR

VAR
    _nStageEff    : UINT := 1;                     // 生效级数（Effective stage count）[-] / Effective stage count
    _fBandEff     : REAL := 100.0;                 // 生效带宽（Effective band span）[工程单位] / Effective band span [EU]
    _fStepBand    : REAL := 25.0;                  // 单级带宽（Band per stage）[工程单位] = 带宽 / 级数 / Band per stage [EU]
    _fDeadEff     : REAL := 2.0;                   // 生效死区（Effective deadband）[工程单位] / Effective deadband [EU]
    _tDwellEff    : TIME := T#10S;                 // 生效驻留时间（Effective dwell time）/ Effective dwell time
    _fErr         : REAL;                          // 偏差（Error）[工程单位]，正偏差=需投入更多级 / Error [EU], positive means more stages needed
    _fRatio       : REAL;                          // 归一化偏差（Normalized error）[-]，域 0 至级数 / Normalized error, 0 to stage count
    _nReq         : UINT;                          // 比例需求级数（Requested stage count）[-] / Requested stage count
    _nOut         : UINT;                          // 映射后的物理级数（Mapped physical stage count）[-] / Mapped physical stage count
    _nTmpRot      : UINT;                          // 轮换偏移中间值（Rotation offset scratch）[-] / Rotation offset scratch value
    _nRotStepEff  : UINT;                          // 归约后轮换步长（Reduced rotation step）[-] / Reduced rotation step
    _uIdx         : UINT;                          // 数组索引（Array index），域 0 至 7 / Array index, 0 to 7
    _nGuard       : UINT;                          // 防死锁循环计数（Loop guard counter），上限为级数上限 / Loop guard counter bounded by the max stage count
    _bInputValid  : BOOL;                          // 输入有效性（Input validity），非有限值为 FALSE / Input validity, FALSE for non-finite values
    _bWantUp      : BOOL;                          // 请求加级（Request up），迟滞判据通过为 TRUE / Request up passes the hysteresis test
    _bWantDown    : BOOL;                          // 请求减级（Request down），迟滞判据通过为 TRUE / Request down passes the hysteresis test
    _bDwellOk     : BOOL;                          // 驻留满足（Dwell satisfied），允许换级 / Dwell satisfied, changing allowed
    _bDwellSat    : BOOL := TRUE;                  // 驻留满足锁存（Dwell satisfied latch），初值 TRUE / Dwell satisfied latch, initial TRUE
    _bDwellFeed   : BOOL;                          // 驻留定时器输入（Dwell timer input）/ Dwell timer input
    _bDwellBreak  : BOOL;                          // 断输入一拍脉冲（One-scan input break pulse）/ One-scan input break pulse
    _bStageChanged: BOOL;                          // 驻留计时进行中（Dwell timing running）/ Dwell timing running flag
    _bRotAdvance  : BOOL;                          // 本拍换级需推进轮换（Advance rotation this scan），单拍标志每拍预清零 / One-scan flag pre-cleared each scan
    _uInfoCode    : UDINT;                         // 本拍信息级码（Info code this scan），每拍重算 / Info code this scan, recomputed each scan
    _uErrFault    : UDINT;                         // 故障级码寄存（Fault-level code register），仅复位清除 / Fault-level code register, cleared by reset only
    _fbTrigReset  : R_TRIG;                        // 复位信号上升沿（Reset rising edge）/ Reset rising edge detector
    _fbTonDwell   : TON;                           // 最小驻留定时器（Minimum dwell timer）/ Minimum dwell timer
END_VAR
VAR CONSTANT
    DL_STEP_MAX_STAGES   : UINT := 8;              // 级数上限（Max stage count）[-]，同时为输出数组长度 / Max stage count, also the array length
    DL_STEP_BAND_DEFAULT : REAL := 100.0;          // 带宽非法时的回默认值（Default band span）[工程单位] / Default band span [EU]
    DL_STEP_FLOAT_EPS    : REAL := 1.0E-6;         // 浮点容差（Float epsilon），替代判等与防除零 / Float epsilon for comparisons and divide guards
    DL_STEP_INF_MAX      : REAL := 1.0E30;         // 有限值判定幅值上限（Finite-value magnitude bound）[工程单位] / Finite-value magnitude bound [EU]
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（公约 0.5）+ 驻留定时器断输入一拍（公约 0.6）
//      Unconditional refresh, plus a one-scan input break for the dwell timer
// ============================================================================
_bDwellFeed := _bStageChanged AND (NOT _bDwellBreak); // 断输入拍定时器输入强制为假（Force FALSE during the break scan）
_fbTrigReset(CLK := bReset);
_fbTonDwell(IN := _bDwellFeed, PT := _tDwellEff);
_bDwellBreak := FALSE;                                // 断输入脉冲自清，位于实例调用之后（R24）/ Break pulse self-cleared after the call

IF _fbTonDwell.Q THEN
    _bStageChanged := FALSE;                          // 驻留期满自清，定时器下拍复位重计（R24）/ Dwell elapsed, timer restarts next scan
    _bDwellSat     := TRUE;                           // 驻留满足锁存（Dwell satisfied latch set）
END_IF

// ============================================================================
// 段 2｜信息级码预清零（瞬时型每拍重算，公约 0.7）
//      Transient info code pre-cleared every scan
// ============================================================================
_uInfoCode := 0;
_bRotAdvance := FALSE;                               // 轮换推进单拍标志预清零（R25 第一律）/ Rotation advance flag pre-cleared each scan

// ============================================================================
// 段 3｜复位路径：级数、轮换偏移、投切计数清零，故障级码解除（R15）
//      Reset path clearing stages, offset, switch counter and the fault code
// ============================================================================
IF _fbTrigReset.Q THEN
    nActiveStage   := 0;                              // 级数清零（Stage count cleared）
    nRotateOffset  := 0;                              // 轮换偏移清零（Rotation offset cleared）
    nSwitchCount   := 0;                              // 投切计数清零（Switch counter cleared）
    _bStageChanged := FALSE;                          // 驻留计时停止（Dwell timing stopped）
    _bDwellSat     := TRUE;                           // 驻留视为满足，允许重新投切（Dwell treated as satisfied）
    _uErrFault     := 0;                              // 故障级码清零（Fault-level code cleared）
END_IF

// ============================================================================
// 段 4｜使能闸门：FALSE 时全部级复位为 0，投切状态不保留
//      Enable gate: all stages cleared while disabled
// ============================================================================
IF NOT bEnable THEN
    nActiveStage := 0;                                // 级数归零（Stage count zeroed）
    FOR _uIdx := 0 TO 7 DO
        abStage[_uIdx] := FALSE;                      // 逐索引清输出（Clear every array element）
    END_FOR
    bAtMaxStage := FALSE;                             // 非满级（Not at max stage）
    bAtMinStage := TRUE;                              // 零级（At min stage）
    bError      := (_uErrFault <> 0);                 // 仅故障级派生（Fault-level derivation only）
    IF _uErrFault <> 0 THEN
        uErrorId := _uErrFault;                       // 故障级码优先（Fault-level code priority）
    ELSE
        uErrorId := _uInfoCode;                       // 否则信息级码（Otherwise the info code）
    END_IF
    RETURN;                                           // 提前退出（Early exit）
END_IF

// ============================================================================
// 段 5｜参数域裁决（级数钳位、带宽回默认、死区取绝对值与半级带钳位）
//      Parameter arbitration: stage clamp, band default, deadband clamp
// ============================================================================
_nStageEff := nStages;                                // 先取原值（Take the raw value first）
IF nStages < 1 THEN
    _nStageEff := 1;                                  // 下限钳位（Lower clamp）
    _uInfoCode := 16#0002_1A02;                       // 0002_1A02 级数越界已钳位【信息级】/ Stage count clamped, info level
ELSIF nStages > DL_STEP_MAX_STAGES THEN
    _nStageEff := DL_STEP_MAX_STAGES;                 // 上限钳位（Upper clamp）
    _uInfoCode := 16#0002_1A02;                       // 0002_1A02 级数越界已钳位【信息级】/ Stage count clamped, info level
END_IF

IF (fBandSpan <> fBandSpan) OR (ABS(fBandSpan) > DL_STEP_INF_MAX) OR (fBandSpan <= DL_STEP_FLOAT_EPS) THEN
    _fBandEff  := DL_STEP_BAND_DEFAULT;               // 非法带宽回默认，防除零（Illegal band falls back, prevents division by zero）
    _uInfoCode := 16#0002_1A03;                       // 0002_1A03 带宽非法回默认【信息级】/ Illegal band span defaults, info level
ELSE
    _fBandEff := fBandSpan;                           // 合法带宽直通（Valid band passes through）
END_IF

IF (fDeadband <> fDeadband) OR (ABS(fDeadband) > DL_STEP_INF_MAX) THEN
    _fDeadEff := 0.0;                                 // 非法死区按零处理（Illegal deadband treated as zero）
ELSE
    _fDeadEff := ABS(fDeadband);                      // 负值取绝对值（Negative value uses ABS）
END_IF

_tDwellEff  := tMinDwell;                             // 驻留时间直通，T#0S 等价无驻留（Dwell passes through, T#0S means none）
_fStepBand  := _fBandEff / UINT_TO_REAL(_nStageEff);  // 单级带宽，级数不小于 1 故无除零（Band per stage, divisor is at least 1）

IF _fStepBand <= DL_STEP_FLOAT_EPS THEN
    _uErrFault := 16#0002_1A06;                       // 0002_1A06 级带宽退化无法运算【故障级】/ Degenerated band, fault level
    _fStepBand := DL_STEP_BAND_DEFAULT;               // 兜底带宽，避免后续除零（Fallback band prevents later division by zero）
ELSIF _fDeadEff >= (_fStepBand * 0.5) THEN
    _fDeadEff  := _fStepBand * 0.5;                   // 死区吃掉整级带宽时钳至半级带（Clamp to half a band）
    _uInfoCode := 16#0002_1A04;                       // 0002_1A04 死区过大已钳至半级带【信息级】/ Deadband clamped to half band, info level
END_IF

// ============================================================================
// 段 6｜输入有效性 + 需求级数计算（非法输入保持上次级数，不跳级防误投切）
//      Input validity and requested stage, illegal input holds the last stage
// ============================================================================
_bInputValid := NOT (((fSetpoint <> fSetpoint) OR (ABS(fSetpoint) > DL_STEP_INF_MAX)) OR
                     ((fActual <> fActual) OR (ABS(fActual) > DL_STEP_INF_MAX)));
IF NOT _bInputValid THEN
    _uInfoCode := 16#0002_1A05;                       // 0002_1A05 设定或实际非有限，级数保持【信息级】/ Non-finite setpoint or actual, stage held
END_IF

IF (_uErrFault = 0) AND _bInputValid THEN
    _fErr   := fSetpoint - fActual;                   // 偏差，正偏差=需加热/加压/加速（Error, positive means more stages）
    _fRatio := LIMIT(0.0, (ABS(_fErr) / _fBandEff) * UINT_TO_REAL(_nStageEff),
                     UINT_TO_REAL(_nStageEff));       // 归一化偏差，先除后乘并双侧限幅（Normalized error, divide then multiply, bounded）
    _nReq   := REAL_TO_UINT(_fRatio);                 // 比例需求级数（Requested stage count）

    // ------------------------------------------------------------------
    // 双向迟滞：加级需越过"下一级边界 + 死区"，减级需回落到"本级边界 - 死区"
    // Two-sided hysteresis on the stage boundaries
    // ------------------------------------------------------------------
    _bWantUp   := FALSE;                              // 加级请求预清零（Up request pre-cleared）
    _bWantDown := FALSE;                              // 减级请求预清零（Down request pre-cleared）
    IF _nReq > nActiveStage THEN
        IF ABS(_fErr) >= ((UINT_TO_REAL(nActiveStage) + 1.0) * _fStepBand) + _fDeadEff THEN
            _bWantUp := TRUE;                         // 越过下一级边界加死区，允许加一级（Above the next boundary plus deadband）
        END_IF
    ELSIF _nReq < nActiveStage THEN
        IF (nActiveStage > 0) AND (ABS(_fErr) <= (UINT_TO_REAL(nActiveStage) * _fStepBand) - _fDeadEff) THEN
            _bWantDown := TRUE;                       // 回落到本级边界减死区，允许减一级（Below the current boundary minus deadband）
        END_IF
    END_IF

    // ------------------------------------------------------------------
    // 最小驻留闸门：驻留未满拒绝换级，信息码每拍重算
    // Minimum dwell gate, the info code is recomputed every scan
    // ------------------------------------------------------------------
    _bDwellOk := _bDwellSat;                          // 驻留满足锁存即允许（Gate follows the dwell latch）
    IF _bWantUp OR _bWantDown THEN
        IF NOT _bDwellOk THEN
            _uInfoCode := 16#0002_1A01;               // 0002_1A01 最小驻留未到，换级被拒【信息级】/ Dwell not elapsed, change rejected
        ELSE
            IF _bWantUp THEN
                nActiveStage := nActiveStage + 1;     // 每拍最多加一级，不跨级跳变（At most one stage up per scan）
            ELSE
                nActiveStage := nActiveStage - 1;     // 每拍最多减一级（At most one stage down per scan）
            END_IF
            _bStageChanged := TRUE;                   // 开启驻留计时（Start the dwell timer）
            _bDwellSat     := FALSE;                  // 驻留锁存复位（Clear the dwell latch）
            _bDwellBreak   := TRUE;                   // 换级当拍断输入一拍，保证计时从零重启（Force a one-scan input break）
            _bRotAdvance   := TRUE;                   // 换级当拍推进轮换偏移（Advance the rotation offset this scan）
            nSwitchCount   := nSwitchCount + 1;       // 投切次数累加（Switch counter increments）
        END_IF
    END_IF
END_IF

// ============================================================================
// 段 7｜均衡轮换偏移（条件减法取模 + 防死锁计数，禁负数取余）
//      Rotation offset by conditional subtraction with a loop guard
// ============================================================================
IF bRotate THEN
    _nRotStepEff := nRotateStep MOD _nStageEff;        // 步长先按级数归约（Reduce the step modulo the stage count）
    _nTmpRot     := nRotateOffset;                     // 取当前偏移（Take the current offset）
    IF _bRotAdvance THEN
        _nTmpRot := _nTmpRot + _nRotStepEff;           // 换级当拍推进一个步长（Advance one step on the change scan）
    END_IF
    _nGuard      := 0;                                 // 防死锁计数清零（Clear the loop guard）
    WHILE (_nTmpRot >= _nStageEff) AND (_nGuard < DL_STEP_MAX_STAGES) DO
        _nTmpRot := _nTmpRot - _nStageEff;             // 条件减法归约（Conditional subtraction）
        _nGuard  := _nGuard + 1;                       // 计数累加（Guard increments）
    END_WHILE
    IF _nTmpRot >= _nStageEff THEN
        _nTmpRot := 0;                                 // 计数耗尽兜底归零（Guard exhausted, fallback to zero）
    END_IF
    nRotateOffset := _nTmpRot;                         // 回写归约后的偏移（Write back the reduced offset）
ELSE
    nRotateOffset := 0;                                // 关闭轮换即偏移归零（Offset cleared when rotation is off）
END_IF
IF nRotateOffset >= _nStageEff THEN
    nRotateOffset := 0;                                // 级数缩小后偏移越界归零（Offset wraps when the stage count shrinks）
END_IF

// ============================================================================
// 段 8｜输出映射：逻辑级 → 物理级（含轮换位移），先统一清零再按拓扑置位
//      Output mapping from logical stage to physical stage, cleared then set
// ============================================================================
IF nActiveStage = 0 THEN
    _nOut := 0;                                        // 零级无输出（No output at zero stage）
ELSE
    _nOut := ((nActiveStage - 1 + nRotateOffset) MOD _nStageEff) + 1; // 逻辑级位移后映射到物理级（Logical stage shifted to physical）
END_IF

FOR _uIdx := 0 TO 7 DO
    abStage[_uIdx] := FALSE;                           // 统一清零，避免残留（Clear all to avoid stale levels）
END_FOR

IF _nOut > 0 THEN
    IF bCumulative THEN
        FOR _uIdx := 0 TO 7 DO
            IF (_uIdx < _nStageEff) AND
               ((((_uIdx + _nStageEff) - nRotateOffset) MOD _nStageEff) < nActiveStage) THEN
                abStage[_uIdx] := TRUE;                // 累积型：以轮换偏移为起点的循环前缀为真（Cyclic prefix starting at the offset）
            END_IF
        END_FOR
    ELSE
        FOR _uIdx := 0 TO 7 DO
            IF _uIdx = (_nOut - 1) THEN
                abStage[_uIdx] := TRUE;                // 单级型：仅一台投入，相邻级互斥（Single stage, only one device on）
            END_IF
        END_FOR
    END_IF
END_IF

// ============================================================================
// 段 9｜出口派生量与错误码映射（bError 为显式排除信息级码的派生式）
//      Derived outputs and error mapping, fault flag excludes info codes
// ============================================================================
bAtMaxStage := (nActiveStage >= _nStageEff);           // 已达最大级（At max stage）
bAtMinStage := (nActiveStage = 0);                     // 已回零级（At min stage）
bError      := (_uErrFault <> 0);                      // 仅故障级码置位（Fault-level codes only）
IF _uErrFault <> 0 THEN
    uErrorId := _uErrFault;                            // 故障级码优先（Fault-level code priority）
ELSE
    uErrorId := _uInfoCode;                            // 否则上报本拍信息码（Otherwise the transient info code）
END_IF
END_FUNCTION_BLOCK
