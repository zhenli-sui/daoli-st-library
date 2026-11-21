(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SignalTower
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG）与本库
 *                         I_DL_TowerLight 接口契约，零厂商方言
 * 分类     (Category)   : 状态指示功能块（Function Block，实现 I_DL_TowerLight）
 * 功能描述 (Function)   : 塔灯集中驱动程序。以一组设备状态位为输入，按唯一
 *                         优先级出口仲裁出五色模式与蜂鸣输出；未确认告警慢闪、
 *                         已确认常亮；慢闪与快闪的时基全部由引脚给定（禁读任何
 *                         内部时钟源）；蜂鸣支持允许 / 消音 / 消音超时自动恢复；
 *                         红绿互斥安全侧断言（异常同真时保红灭绿并锁存故障码）；
 *                         多色同亮合法（蓝 + 黄叠加、绿 + 蓝快闪叠加）。
 * 接口实现 (Implements) : I_DL_TowerLight —— 语义为"状态位集合 → 灯色仲裁 →
 *                         通道输出"的三层解耦契约。10 个接口属性全部以只读
 *                         PROPERTY GET 在文件尾部落地（eState / eRed / eAmber /
 *                         eGreen / eBlue / eWhite / bBuzzer / bSilenced / bError /
 *                         uErrorId），3 个接口方法 SetColor / SilenceBuzzer /
 *                         Reset 以置请求标志、主体状态机消费的两段式实现，
 *                         方法内不含跨周期阻塞动作。规格 OUT 列与接口属性同名
 *                         的 4 项（eState / bBuzzer / bSilenced / uErrorId）按
 *                         公约 R22 以属性承载、不再重复声明为输出引脚；不同的
 *                         6 项（bRed / bAmber / bGreen / bBlue / bWhite / bFault）
 *                         保留为输出引脚，双通道并存不冲突。
 * 仲裁优先序 (Priority) : 1 安全事件 > 2 故障未确认 > 3 故障已确认 > 4 预警
 *                         未确认 > 5 预警已确认 > 6 手动 > 7 自动运行 > 8 求助 >
 *                         9 待机。级 1 至 3 为主级且互斥（其余灯全灭）；级 4 至 5
 *                         主色为黄，允许蓝（手动）叠加；级 6 至 8 为辅级可叠加。
 *                         红与绿永不共存（出口断言兜底）。
 * 开源溯源 (Origin)     : 原创实现（参考 TcOpen 组件范式）。来源标签
 *                         tcopen-component / stack-light（RAW_NOTES_R8 条目 S-13：
 *                         公开文档呈现的「状态位集合 → 灯色仲裁 → 通道输出」
 *                         分层惯例与消音/确认语义），仅借鉴功能分类、参数域与
 *                         状态语义；仲裁表、故障码、消音状态机、闪烁时基生成
 *                         按本库红线 clean-room 独立编写，未复制任何源码行。
 *                         许可证说明：TcOpen 采用 MIT 许可，公开语义描述借鉴
 *                         合规；本文件不含其代码片段。
 * 故障码 (Codes)        : 段位 16#0003_xxxx（已核对 DL_Device 台账：信息级用到
 *                         0122、故障级用到 02C0，本轮新建 012x/02Dx 状态指示族，
 *                         无冲突）。【信息级】0003_0123 闪频参数为零已退化常亮、
 *                         0003_0124 消音到期自动恢复蜂鸣、0003_0125 消音时长为
 *                         零即永续、0003_0126 手动与自动同真（手动优先）；
 *                         【故障级】0003_02D0 红绿同亮断言冲突（锁存，保红灭绿）、
 *                         0003_02D1 非法显示状态兜底（锁存）。信息级码只进
 *                         uErrorId，不置 bFault / bError。
 * 公约遵循 (Convention) : 0.1 本块为纯事件型指示器，无积分/滤波类首扫跟踪需求，
 *                         标注「免首扫」：无 bInit 标志、无 bTrack 引脚，状态
 *                         每拍由输入位与内部锁存完整推导，上电首拍即得正确灯效。
 *                         0.2 bFault / bError 为显式排除信息级码的派生式，信息级
 *                         码只进 uErrorId 寄存器。0.7 锁存型故障码与瞬时型信息码
 *                         分寄存器存放，不得混写。
 *                         0.13 本块属指示与诊断镜像层，不构成 ISO 13849 /
 *                         IEC 62061 认证安全功能，安全回路由认证安全控制器承载；
 *                         bSafetyEvent 仅作状态镜像，不得作为安全输出使用。
 * 规格偏离 (R11 Dev.)   : D1（已授权）规格 OUT 列 4 个与接口属性同名成员按 R22
 *                         改为只读属性承载，引脚可读性不变（调用方仍可
 *                         实例名.bBuzzer 读取）。D2 接口枚举 eRotate 在单灯通道
 *                         硬件上无法产生真实环灯轮转，实现退化为慢闪并在已知
 *                         限制中披露（不新增模式参数，避免算法变体化）。D3 红绿
 *                         互斥出口断言保留为防御性分支：正常仲裁下表内组合天然
 *                         互斥，外部引脚无法构造同真，验收向量 V7 的验证方式为
 *                         调试期强制写入内部模式镜像；保留该分支用于后续实现
 *                         替换与人工覆盖扩展时的兜底，不影响仲裁正确性。
 * 验收向量 (Acceptance) :
 *   V1  bSafetyEvent=TRUE（即使先按消音）→ eRed=eFlashFast、eState=eSafety、
 *       bBuzzer=TRUE（安全事件强制鸣，不受消音约束）
 *   V2  bFaultActive=TRUE、bFaultAck=FALSE → eRed=eFlashSlow、bBuzzer=TRUE、
 *       eState=eFaultUnack
 *   V3  同 V2 后置 bFaultAck=TRUE → eRed=eSteady、bBuzzer=FALSE、eState=eFaultAck
 *   V4  bWarnActive=TRUE、bWarnAck=FALSE → eAmber=eFlashSlow；置 bWarnAck=TRUE →
 *       eAmber=eSteady、eState=eWarning
 *   V5  bManualMode=TRUE 且 bWarnActive=TRUE → eAmber=eSteady 且 eBlue=eSteady
 *       （叠加合法，eState=eWarning，黄色主级不被蓝色覆盖）
 *   V6  tSilenceTime=T#60S 下按消音 → bSilenced=TRUE、bBuzzer=FALSE；保持期满后
 *       bSilenced=FALSE、bBuzzer 恢复 TRUE 且当拍 uErrorId=16#0003_0124
 *   V7  出口断言（防御性分支）：调试期强制构造 eRed 与 eGreen 同时为真的组合 →
 *       bGreen 被强制灭、bFault=TRUE、uErrorId=16#0003_02D0（外部引脚无法构
 *       造该组合，理由见规格偏离 D3）
 *   V8  bEnable=FALSE → 五色全灭、bBuzzer=FALSE、eState=eNormal、模式属性回 eOff
 * 已知限制 (Limits)     : 1 eRotate 在单色通道退化为慢闪（真实多色环灯轮转需
 *                         上层替换实现块，接口语义不变）。2 慢闪/快闪半周期必须
 *                         不小于 5 倍任务扫描周期，否则闪频失真，本块不校验。
 *                         3 消音只作用于"主级 1 至 2 的蜂鸣"，安全事件强制鸣。
 *                         4 本块不做消音次数限制与消音权限校验，属上层 HMI 职责。
 *                         5 红绿互斥断言属防御性不可达分支（正常仲裁天然互斥），
 *                         仅在后续实现替换或人工覆盖扩展时可能命中。
 * 红线自检 (Redline)    : 零全局变量表访问 ✓｜零外部变量声明 ✓｜零物理地址直写 ✓
 *                         纯 IEC 61131-3 ✓｜浮点容差与防除零 ✓（本块无浮点运算）
 *                         全变量中英双语同行注释 ✓｜ENUM + CASE + ELSE 兜底 ✓
 *                         6 个实例（3 个 TON + 3 个 R_TRIG）主体最前部无条件刷新 ✓
 *                         FUNCTION_BLOCK 与 END_FUNCTION_BLOCK 成对 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · 泳道 C · DL_Device 状态指示族）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SignalTower IMPLEMENTS I_DL_TowerLight
VAR_INPUT
    bEnable          : BOOL := FALSE;                          // 使能（Enable），FALSE=全灯灭且蜂鸣停 / Enable, FALSE clears all lamp and buzzer outputs
    bSafetyEvent     : BOOL := FALSE;                          // 安全事件镜像（Safety event mirror，急停/安全门/光幕），最高优先 / Safety event mirror, highest priority
    bFaultActive     : BOOL := FALSE;                          // 故障存在（Fault active），TRUE=有未复位故障 / Fault active, TRUE while a fault persists
    bFaultAck        : BOOL := FALSE;                          // 故障已确认（Fault acknowledged），TRUE=红常亮不鸣 / Fault acknowledged, TRUE gives steady red without buzzer
    bWarnActive      : BOOL := FALSE;                          // 预警存在（Warning active），TRUE=黄灯参与显示 / Warning active, TRUE engages the amber channel
    bWarnAck         : BOOL := FALSE;                          // 预警已确认（Warning acknowledged），TRUE=黄常亮 / Warning acknowledged, TRUE gives steady amber
    bManualMode      : BOOL := FALSE;                          // 手动模式（Manual mode），TRUE=蓝常亮 / Manual mode, TRUE gives steady blue
    bAutoRunning     : BOOL := FALSE;                          // 自动运行中（Auto running），TRUE=绿常亮 / Auto running, TRUE gives steady green
    bOperatorCall    : BOOL := FALSE;                          // 操作员求助（Operator call），TRUE=蓝快闪 / Operator call, TRUE gives fast-flashing blue
    bStandbyIndicate : BOOL := FALSE;                          // 待机指示（Standby indication），TRUE=白常亮（可选通道）/ Standby indication, TRUE gives steady white
    bBuzzerEnable    : BOOL := TRUE;                           // 蜂鸣允许（Buzzer enable），FALSE=永不鸣 / Buzzer enable, FALSE mutes the buzzer permanently
    bSilenceCmd      : BOOL := FALSE;                          // 消音指令（Silence command），上升沿受理 / Silence command, accepted on rising edge
    tSilenceTime     : TIME := T#60S;                          // 消音保持时长（Silence hold time），T#0S=消音永续 / Silence hold time, T#0S means silence forever
    tFlashSlow       : TIME := T#500MS;                        // 慢闪半周期（Slow flash half period），T#0S=退化常亮 / Slow flash half period, T#0S degrades to steady
    tFlashFast       : TIME := T#250MS;                        // 快闪半周期（Fast flash half period），T#0S=退化常亮 / Fast flash half period, T#0S degrades to steady
    bReset           : BOOL := FALSE;                          // 故障复位（Fault reset），上升沿生效 / Fault reset, effective on rising edge
END_VAR

VAR_OUTPUT
    bRed             : BOOL;                                   // 红灯电平输出（Red lamp output），TRUE=亮 / Red lamp output, TRUE = lit
    bAmber           : BOOL;                                   // 黄灯电平输出（Amber lamp output），TRUE=亮 / Amber lamp output, TRUE = lit
    bGreen           : BOOL;                                   // 绿灯电平输出（Green lamp output），TRUE=亮 / Green lamp output, TRUE = lit
    bBlue            : BOOL;                                   // 蓝灯电平输出（Blue lamp output），TRUE=亮 / Blue lamp output, TRUE = lit
    bWhite           : BOOL;                                   // 白灯电平输出（White lamp output），TRUE=亮 / White lamp output, TRUE = lit
    bFault           : BOOL;                                   // 故障锁存指示（Fault latched），仅故障级码置位 / Fault latched, fault-level codes only
END_VAR

VAR
    _eDispState      : E_DL_TowerState := E_DL_TowerState.eNormal; // 显示状态（Displayed state），仲裁唯一出口 / Displayed state, single arbitration outlet
    _eRedPat         : E_DL_TowerPattern := E_DL_TowerPattern.eOff; // 红色模式（Red pattern），每拍先清零再裁决 / Red pattern, cleared then arbitrated each scan
    _eAmberPat       : E_DL_TowerPattern := E_DL_TowerPattern.eOff; // 黄色模式（Amber pattern），每拍先清零再裁决 / Amber pattern, cleared then arbitrated each scan
    _eGreenPat       : E_DL_TowerPattern := E_DL_TowerPattern.eOff; // 绿色模式（Green pattern），每拍先清零再裁决 / Green pattern, cleared then arbitrated each scan
    _eBluePat        : E_DL_TowerPattern := E_DL_TowerPattern.eOff; // 蓝色模式（Blue pattern），每拍先清零再裁决 / Blue pattern, cleared then arbitrated each scan
    _eWhitePat       : E_DL_TowerPattern := E_DL_TowerPattern.eOff; // 白色模式（White pattern），每拍先清零再裁决 / White pattern, cleared then arbitrated each scan
    _bBuzzerInt      : BOOL;                                   // 蜂鸣器内部输出（Internal buzzer output），经消音与使能合成 / Internal buzzer output, composed with silence and enable
    _bBuzzerReq      : BOOL;                                   // 蜂鸣请求（Buzzer request），主级 1 至 2 有效 / Buzzer request, active for main level 1 and 2
    _bSilenceActive  : BOOL;                                   // 消音保持中（Silence hold active），窗口内为 TRUE / Silence hold active during the hold window
    _bFaultLatch     : BOOL;                                   // 故障锁存（Fault latch），仅复位路径清除 / Fault latch, cleared only by the reset path
    _uErrFault       : UDINT;                                  // 故障级码寄存（Fault-level code register），锁存写入 / Fault-level code register, written on latch
    _uInfoCode       : UDINT;                                  // 本拍信息级码（Info code this scan），瞬时型每拍重算 / Info code this scan, transient and recomputed
    _bSlowPhase      : BOOL;                                   // 慢闪相位（Slow flash phase），半周期翻转 / Slow flash phase, toggled every half period
    _bFastPhase      : BOOL;                                   // 快闪相位（Fast flash phase），半周期翻转 / Fast flash phase, toggled every half period
    _bSlowDeg        : BOOL;                                   // 慢闪退化标志（Slow flash degenerated），参数为零时 TRUE / Slow flash degenerated flag, TRUE when the period is zero
    _bFastDeg        : BOOL;                                   // 快闪退化标志（Fast flash degenerated），参数为零时 TRUE / Fast flash degenerated flag, TRUE when the period is zero
    _bSilenceForever : BOOL;                                   // 消音永续标志（Silence forever），时长参数为零时 TRUE / Silence forever flag, TRUE when the hold time is zero
    _tFlashSlowEff   : TIME := T#500MS;                        // 生效慢闪半周期（Effective slow half period）/ Effective slow flash half period
    _tFlashFastEff   : TIME := T#250MS;                        // 生效快闪半周期（Effective fast half period）/ Effective fast flash half period
    _tSilenceEff     : TIME := T#60S;                          // 生效消音时长（Effective silence hold time）/ Effective silence hold time
    _bSlowOn         : BOOL;                                   // 慢闪当拍电平（Slow flash level this scan）/ Slow flash level this scan
    _bFastOn         : BOOL;                                   // 快闪当拍电平（Fast flash level this scan）/ Fast flash level this scan
    _bRedOut         : BOOL;                                   // 红灯中间电平（Red intermediate level），断言前 / Red intermediate level before assertion
    _bAmberOut       : BOOL;                                   // 黄灯中间电平（Amber intermediate level），断言前 / Amber intermediate level before assertion
    _bGreenOut       : BOOL;                                   // 绿灯中间电平（Green intermediate level），断言前 / Green intermediate level before assertion
    _bBlueOut        : BOOL;                                   // 蓝灯中间电平（Blue intermediate level），断言前 / Blue intermediate level before assertion
    _bWhiteOut       : BOOL;                                   // 白灯中间电平（White intermediate level），断言前 / White intermediate level before assertion
    _bMainLevel      : BOOL;                                   // 主级占用标志（Main level occupied），级 1 至 5 为 TRUE / Main level occupied flag, TRUE for levels 1 to 5
    _bOvActive       : BOOL;                                   // 人工覆盖有效（Override active），由 SetColor 置位 / Override active, armed by SetColor
    _eOvColor        : E_DL_TowerColor := E_DL_TowerColor.eNone; // 人工覆盖灯色（Override color），eNone=无覆盖 / Override color, eNone means no override
    _eOvPattern      : E_DL_TowerPattern := E_DL_TowerPattern.eOff; // 人工覆盖模式（Override pattern），eOff=灭 / Override pattern, eOff means off
    _bPendSilence    : BOOL;                                   // 方法消音请求（Method silence request），主体消费 / Method silence request consumed by the body
    _bPendReset      : BOOL;                                   // 方法复位请求（Method reset request），主体消费 / Method reset request consumed by the body
    _fbTrigSilence   : R_TRIG;                                 // 消音指令上升沿（Silence command edge）/ Silence command rising edge
    _fbTrigReset     : R_TRIG;                                 // 复位指令上升沿（Reset command edge）/ Reset command rising edge
    _fbTrigSilenceEnd: R_TRIG;                                 // 消音到期上升沿（Silence expiry edge），信息码 0124 用 / Silence expiry edge for info code 0124
    _fbTonSlow       : TON;                                    // 慢闪半周期定时器（Slow half-period timer）/ Slow flash half-period timer
    _fbTonFast       : TON;                                    // 快闪半周期定时器（Fast half-period timer）/ Fast flash half-period timer
    _fbTonSilence    : TON;                                    // 消音保持定时器（Silence hold timer）/ Silence hold timer
END_VAR
VAR CONSTANT
    DL_TOWER_FLASH_MIN   : TIME := T#10MS;  // 闪频退化时的内部替代半周期（Replacement half period when flash is degenerated）/ Replacement half period used when flash periods are zero
    DL_TOWER_SILENCE_MAX : TIME := T#24H;   // 消音时长为零时的替代保持时长（Substitute hold time when the silence time is zero），等效永续 / Substitute hold time when silence time is zero, effectively forever
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（公约 0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of all timer and edge instances
// ============================================================================
_fbTrigSilence(CLK := bSilenceCmd);
_fbTrigReset(CLK := bReset);
_fbTonSlow(IN := NOT _bSlowPhase, PT := _tFlashSlowEff);
_fbTonFast(IN := NOT _bFastPhase, PT := _tFlashFastEff);
_fbTonSilence(IN := _bSilenceActive, PT := _tSilenceEff);
_fbTrigSilenceEnd(CLK := _fbTonSilence.Q);

// 半周期到达即翻转相位：入参下一拍回落，TON 自动清零重新计时（时基由引脚给定）
// Toggle the phase when a half period elapses; TON resets itself next scan
IF _fbTonSlow.Q THEN
    _bSlowPhase := NOT _bSlowPhase;   // 慢闪相位翻转（Slow phase toggled）
END_IF
IF _fbTonFast.Q THEN
    _bFastPhase := NOT _bFastPhase;   // 快闪相位翻转（Fast phase toggled）
END_IF
IF _fbTonSilence.Q THEN
    _bSilenceActive := FALSE;         // 消音保持期满自动解除（Silence hold released on expiry）
END_IF

// ============================================================================
// 段 2｜参数域裁决 + 信息级码（瞬时型每拍重算，公约 0.2 / 0.7）
//      Parameter domain arbitration + transient info codes recomputed each scan
// ============================================================================
_uInfoCode := 0;                                        // 信息级码每拍预清零（Info code pre-cleared each scan）
_bSlowDeg  := (tFlashSlow <= T#0S);                     // 慢闪参数为零 → 退化常亮（Zero slow period degrades to steady）
_bFastDeg  := (tFlashFast <= T#0S);                     // 快闪参数为零 → 退化常亮（Zero fast period degrades to steady）
_bSilenceForever := (tSilenceTime <= T#0S);             // 消音时长为零 → 消音永续（Zero silence time means forever）

IF _bSlowDeg THEN
    _tFlashSlowEff := DL_TOWER_FLASH_MIN;               // 替代半周期，避免零值定时器空转（Substitute period avoids idle zero timer）
ELSE
    _tFlashSlowEff := tFlashSlow;                       // 合法参数直通（Valid parameter passes through）
END_IF
IF _bFastDeg THEN
    _tFlashFastEff := DL_TOWER_FLASH_MIN;               // 替代半周期（Substitute half period）
ELSE
    _tFlashFastEff := tFlashFast;                       // 合法参数直通（Valid parameter passes through）
END_IF
IF _bSilenceForever THEN
    _tSilenceEff := DL_TOWER_SILENCE_MAX;               // 替代保持时长，等效永续（Substitute hold time, effectively forever）
ELSE
    _tSilenceEff := tSilenceTime;                       // 合法参数直通（Valid parameter passes through）
END_IF

IF _bSlowDeg OR _bFastDeg THEN
    _uInfoCode := 16#0003_0123;                         // 0003_0123 闪频参数为零已退化常亮【信息级】/ Flash period zero, degraded to steady, info level
END_IF
IF _bSilenceForever THEN
    _uInfoCode := 16#0003_0125;                         // 0003_0125 消音时长为零即永续【信息级】/ Silence time zero means forever, info level
END_IF
IF bManualMode AND bAutoRunning THEN
    _uInfoCode := 16#0003_0126;                         // 0003_0126 手动与自动同真，手动优先【信息级】/ Manual and auto both true, manual wins, info level
END_IF
IF _fbTrigSilenceEnd.Q THEN
    _uInfoCode := 16#0003_0124;                         // 0003_0124 消音到期自动恢复蜂鸣【信息级】/ Silence expired, buzzer restored, info level
END_IF

// ============================================================================
// 段 3｜故障锁存复位路径（R15：锁存码只在解除路径清除）
//      Fault latch release path (latched codes cleared only on release)
// ============================================================================
IF _fbTrigReset.Q OR _bPendReset THEN
    _bPendReset  := FALSE;                              // 消费方法复位请求（Consume method reset request）
    _bFaultLatch := FALSE;                              // 解除故障锁存（Release fault latch）
    _uErrFault   := 0;                                  // 故障级码清零（Fault-level code cleared）
END_IF

// ============================================================================
// 段 4｜使能闸门：关闭时五色全灭、蜂鸣停、模式属性回 eOff、状态回 eNormal
//      Enable gate: all lamps off, buzzer muted, patterns off, state normal
// ============================================================================
IF NOT bEnable THEN
    _eDispState := E_DL_TowerState.eNormal;             // 状态回正常（State forced to normal）
    _eRedPat    := E_DL_TowerPattern.eOff;              // 红模式清零（Red pattern cleared）
    _eAmberPat  := E_DL_TowerPattern.eOff;              // 黄模式清零（Amber pattern cleared）
    _eGreenPat  := E_DL_TowerPattern.eOff;              // 绿模式清零（Green pattern cleared）
    _eBluePat   := E_DL_TowerPattern.eOff;              // 蓝模式清零（Blue pattern cleared）
    _eWhitePat  := E_DL_TowerPattern.eOff;              // 白模式清零（White pattern cleared）
    _bBuzzerInt := FALSE;                               // 蜂鸣停（Buzzer muted）
    _bSilenceActive := FALSE;                           // 消音窗关闭（Silence window closed）
    _bOvActive  := FALSE;                               // 人工覆盖撤销（Override revoked）
    _bPendSilence := FALSE;                             // 方法请求清空（Method requests cleared）
    bRed   := FALSE;                                    // 红灯灭（Red off）
    bAmber := FALSE;                                    // 黄灯灭（Amber off）
    bGreen := FALSE;                                    // 绿灯灭（Green off）
    bBlue  := FALSE;                                    // 蓝灯灭（Blue off）
    bWhite := FALSE;                                    // 白灯灭（White off）
    bFault := _bFaultLatch;                             // 故障锁存仍如实上报（Fault latch still reported）
    RETURN;                                             // 提前退出，保持输出确定（Early exit keeps outputs deterministic）
END_IF

// ============================================================================
// 段 5｜唯一优先级出口仲裁（单一出口 IF/ELSIF，不得写成并列覆盖）
//      Single-outlet priority arbitration with one IF/ELSIF chain
// ============================================================================
IF bSafetyEvent THEN
    _eDispState := E_DL_TowerState.eSafety;             // 级 1 安全事件（Level 1 safety event）
ELSIF bFaultActive AND (NOT bFaultAck) THEN
    _eDispState := E_DL_TowerState.eFaultUnack;         // 级 2 故障未确认（Level 2 unacknowledged fault）
ELSIF bFaultActive THEN
    _eDispState := E_DL_TowerState.eFaultAck;           // 级 3 故障已确认（Level 3 acknowledged fault）
ELSIF bWarnActive THEN
    _eDispState := E_DL_TowerState.eWarning;            // 级 4 至 5 预警（Levels 4 and 5 warning）
ELSIF bManualMode THEN
    _eDispState := E_DL_TowerState.eManual;             // 级 6 手动（Level 6 manual mode）
ELSIF bOperatorCall AND (NOT bAutoRunning) THEN
    _eDispState := E_DL_TowerState.eCall;               // 级 8 求助（Level 8 operator call）
ELSE
    _eDispState := E_DL_TowerState.eNormal;             // 级 7 与级 9：运行或待机（Levels 7 and 9: running or standby）
END_IF

_bMainLevel := (_eDispState = E_DL_TowerState.eSafety) OR
               (_eDispState = E_DL_TowerState.eFaultUnack) OR
               (_eDispState = E_DL_TowerState.eFaultAck) OR
               (_eDispState = E_DL_TowerState.eWarning); // 主级占用（Main level occupied）

// ============================================================================
// 段 6｜显示状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Display state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
_eRedPat   := E_DL_TowerPattern.eOff;                   // 每拍先清零（Pre-clear all patterns each scan）
_eAmberPat := E_DL_TowerPattern.eOff;
_eGreenPat := E_DL_TowerPattern.eOff;
_eBluePat  := E_DL_TowerPattern.eOff;
_eWhitePat := E_DL_TowerPattern.eOff;

CASE _eDispState OF

    E_DL_TowerState.eSafety: // 级 1：红快闪 + 强制鸣，其余主级灯全灭（安全优先）
        _eRedPat := E_DL_TowerPattern.eFlashFast;       // 红快闪（Red fast flash）

    E_DL_TowerState.eFaultUnack: // 级 2：红慢闪 + 鸣
        _eRedPat := E_DL_TowerPattern.eFlashSlow;       // 红慢闪（Red slow flash）

    E_DL_TowerState.eFaultAck: // 级 3：红常亮不鸣
        _eRedPat := E_DL_TowerPattern.eSteady;          // 红常亮（Red steady）

    E_DL_TowerState.eWarning: // 级 4 至 5：黄主色；蓝（手动）允许叠加，绿强制熄灭
        IF bWarnAck THEN
            _eAmberPat := E_DL_TowerPattern.eSteady;    // 已确认黄常亮（Acknowledged warning steady）
        ELSE
            _eAmberPat := E_DL_TowerPattern.eFlashSlow; // 未确认黄慢闪（Unacknowledged warning slow flash）
        END_IF
        IF bManualMode THEN
            _eBluePat := E_DL_TowerPattern.eSteady;     // 手动蓝叠加（Manual blue overlays）
        END_IF

    E_DL_TowerState.eManual: // 级 6：蓝常亮
        _eBluePat := E_DL_TowerPattern.eSteady;         // 蓝常亮（Blue steady）

    E_DL_TowerState.eCall: // 级 8：蓝快闪
        _eBluePat := E_DL_TowerPattern.eFlashFast;      // 蓝快闪（Blue fast flash）

    E_DL_TowerState.eNormal: // 级 7 与级 9：绿运行、蓝求助、白待机可叠加
        IF bAutoRunning THEN
            _eGreenPat := E_DL_TowerPattern.eSteady;    // 自动运行绿常亮（Auto running steady green）
        END_IF
        IF bOperatorCall THEN
            _eBluePat := E_DL_TowerPattern.eFlashFast;  // 运行中求助蓝快闪（Call during run fast flash）
        END_IF
        IF bStandbyIndicate AND (NOT bAutoRunning) AND (NOT bOperatorCall) THEN
            _eWhitePat := E_DL_TowerPattern.eSteady;    // 纯待机白常亮（Pure standby steady white）
        END_IF

    ELSE // 非法状态兜底：任何越界枚举值一律清灯并锁存专用码
        _bFaultLatch := TRUE;                           // 故障锁存（Fault latched）
        _uErrFault   := 16#0003_02D1;                   // 0003_02D1 非法显示状态【故障级】/ Illegal display state, fault level
        _bOvActive   := FALSE;                          // 非法态撤销人工覆盖（Revoke override on illegal state）
        _eRedPat   := E_DL_TowerPattern.eOff;           // 红灯灭（Red off）
        _eAmberPat := E_DL_TowerPattern.eOff;           // 黄灯灭（Amber off）
        _eGreenPat := E_DL_TowerPattern.eOff;           // 绿灯灭（Green off）
        _eBluePat  := E_DL_TowerPattern.eOff;           // 蓝灯灭（Blue off）
        _eWhitePat := E_DL_TowerPattern.eOff;           // 白灯灭（White off）

END_CASE

// ============================================================================
// 段 7｜人工覆盖注入（SetColor）：仅无主级占用时生效，主级出现即撤销
//      Manual override injection, only when no main level is active
// ============================================================================
IF _bMainLevel THEN
    _bOvActive := FALSE;                                // 主级占用即撤销覆盖（Main level revokes the override）
ELSIF _bOvActive THEN
    IF _eOvColor = E_DL_TowerColor.eRed THEN
        _eRedPat := _eOvPattern;                        // 覆盖红色通道（Override red channel）
    ELSIF _eOvColor = E_DL_TowerColor.eAmber THEN
        _eAmberPat := _eOvPattern;                      // 覆盖黄色通道（Override amber channel）
    ELSIF _eOvColor = E_DL_TowerColor.eGreen THEN
        _eGreenPat := _eOvPattern;                      // 覆盖绿色通道（Override green channel）
    ELSIF _eOvColor = E_DL_TowerColor.eBlue THEN
        _eBluePat := _eOvPattern;                       // 覆盖蓝色通道（Override blue channel）
    ELSIF _eOvColor = E_DL_TowerColor.eWhite THEN
        _eWhitePat := _eOvPattern;                      // 覆盖白色通道（Override white channel）
    ELSE
        _bOvActive := FALSE;                            // 无色请求即撤销（No color revokes the override）
    END_IF
END_IF

// ============================================================================
// 段 8｜蜂鸣与消音（消音指令上升沿或方法请求受理；到期由段 1 自动解除）
//      Buzzer and silence handling, expiry released in section 1
// ============================================================================
IF _fbTrigSilence.Q OR _bPendSilence THEN
    _bPendSilence   := FALSE;                           // 消费方法消音请求（Consume method silence request）
    _bSilenceActive := TRUE;                            // 开启消音保持窗（Open the silence hold window）
END_IF

_bBuzzerReq := (_eDispState = E_DL_TowerState.eSafety) OR
               (_eDispState = E_DL_TowerState.eFaultUnack); // 蜂鸣请求：仅级 1 与级 2（Buzzer request for levels 1 and 2）
IF NOT _bBuzzerReq THEN
    _bSilenceActive := FALSE;                           // 非蜂鸣期不保留消音窗，防陈旧消音（No stale silence outside buzzer phase）
END_IF
_bBuzzerInt := _bBuzzerReq AND bBuzzerEnable AND
               ((NOT _bSilenceActive) OR (_eDispState = E_DL_TowerState.eSafety)); // 安全事件不受消音约束（Safety bypasses silence）

// ============================================================================
// 段 9｜模式到电平映射（闪烁相位在段 1 生成；退化参数按常亮处理）
//      Pattern to level mapping, degenerated periods behave as steady
// ============================================================================
_bSlowOn := _bSlowDeg OR _bSlowPhase;                   // 慢闪当拍电平（Slow flash level）
_bFastOn := _bFastDeg OR _bFastPhase;                   // 快闪当拍电平（Fast flash level）

_bRedOut := (_eRedPat = E_DL_TowerPattern.eSteady) OR
            ((_eRedPat = E_DL_TowerPattern.eFlashSlow) AND _bSlowOn) OR
            ((_eRedPat = E_DL_TowerPattern.eFlashFast) AND _bFastOn) OR
            ((_eRedPat = E_DL_TowerPattern.eRotate) AND _bSlowOn); // 红通道电平（Red channel level）
_bAmberOut := (_eAmberPat = E_DL_TowerPattern.eSteady) OR
              ((_eAmberPat = E_DL_TowerPattern.eFlashSlow) AND _bSlowOn) OR
              ((_eAmberPat = E_DL_TowerPattern.eFlashFast) AND _bFastOn) OR
              ((_eAmberPat = E_DL_TowerPattern.eRotate) AND _bSlowOn); // 黄通道电平（Amber channel level）
_bGreenOut := (_eGreenPat = E_DL_TowerPattern.eSteady) OR
              ((_eGreenPat = E_DL_TowerPattern.eFlashSlow) AND _bSlowOn) OR
              ((_eGreenPat = E_DL_TowerPattern.eFlashFast) AND _bFastOn) OR
              ((_eGreenPat = E_DL_TowerPattern.eRotate) AND _bSlowOn); // 绿通道电平（Green channel level）
_bBlueOut := (_eBluePat = E_DL_TowerPattern.eSteady) OR
             ((_eBluePat = E_DL_TowerPattern.eFlashSlow) AND _bSlowOn) OR
             ((_eBluePat = E_DL_TowerPattern.eFlashFast) AND _bFastOn) OR
             ((_eBluePat = E_DL_TowerPattern.eRotate) AND _bSlowOn); // 蓝通道电平（Blue channel level）
_bWhiteOut := (_eWhitePat = E_DL_TowerPattern.eSteady) OR
              ((_eWhitePat = E_DL_TowerPattern.eFlashSlow) AND _bSlowOn) OR
              ((_eWhitePat = E_DL_TowerPattern.eFlashFast) AND _bFastOn) OR
              ((_eWhitePat = E_DL_TowerPattern.eRotate) AND _bSlowOn); // 白通道电平（White channel level）

// ============================================================================
// 段 10｜出口断言：红绿同亮为逻辑错误，安全侧保红灭绿并锁存专用码
//      Exit assertion: red and green never coexist, red wins and code latched
// ============================================================================
IF _bRedOut AND _bGreenOut THEN
    _bGreenOut := FALSE;                                // 保红灭绿（Keep red, force green off）
    _eGreenPat := E_DL_TowerPattern.eOff;               // 绿模式同步清零（Green pattern cleared for consistency）
    _bFaultLatch := TRUE;                               // 故障锁存（Fault latched）
    _uErrFault   := 16#0003_02D0;                       // 0003_02D0 红绿同亮断言冲突【故障级】/ Red-green conflict assertion, fault level
END_IF

// ============================================================================
// 段 11｜输出映射（bFault 为仅故障级派生式；其余同名成员由属性承载）
//      Output mapping, fault flag derives from fault-level codes only
// ============================================================================
bRed   := _bRedOut;                                     // 红输出（Red output）
bAmber := _bAmberOut;                                   // 黄输出（Amber output）
bGreen := _bGreenOut;                                   // 绿输出（Green output）
bBlue  := _bBlueOut;                                    // 蓝输出（Blue output）
bWhite := _bWhiteOut;                                   // 白输出（White output）
bFault := _bFaultLatch;                                 // 故障锁存映射（Fault latch mapping）

(*------------------------------------------------------------------------------
 * 方法: SetColor —— 请求置某色某模式。主级占用 / 故障锁存 / 未使能一律拒绝。
 *      Method SetColor - request a color and pattern, rejected on main level,
 *      fault latch or disabled state. Body consumer: section 7.
 *------------------------------------------------------------------------------*)
METHOD SetColor : BOOL
VAR_INPUT
    eColor   : E_DL_TowerColor;    // 目标灯色（Target color），eNone=撤销人工覆盖 / Target color, eNone revokes the override
    ePattern : E_DL_TowerPattern;  // 目标模式（Target pattern），eOff=该色熄灭 / Target pattern, eOff turns the channel off
END_VAR
IF (NOT bEnable) OR _bFaultLatch THEN
    SetColor := FALSE;                                  // 未使能或故障锁存拒绝（Rejected when disabled or latched）
ELSIF _bMainLevel THEN
    SetColor := FALSE;                                  // 主级占用拒绝，覆盖不抢占仲裁（Rejected while a main level owns the tower）
ELSE
    _eOvColor   := eColor;                              // 登记覆盖灯色（Register override color）
    _eOvPattern := ePattern;                            // 登记覆盖模式（Register override pattern）
    _bOvActive  := (eColor <> E_DL_TowerColor.eNone);   // 无色即撤销覆盖（No color revokes the override）
    SetColor    := TRUE;                                // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: SilenceBuzzer —— 一次性消音。非蜂鸣期、蜂鸣禁能或安全事件期返回 FALSE。
 *      Method SilenceBuzzer - one-shot silence, rejected outside the buzzer phase,
 *      when the buzzer is disabled, or during a safety event.
 *------------------------------------------------------------------------------*)
METHOD SilenceBuzzer : BOOL
VAR_INPUT
END_VAR
IF (NOT bEnable) OR (NOT bBuzzerEnable) OR (NOT _bBuzzerReq) THEN
    SilenceBuzzer := FALSE;                             // 非蜂鸣期无消音对象（Nothing to silence outside the buzzer phase）
ELSIF _eDispState = E_DL_TowerState.eSafety THEN
    SilenceBuzzer := FALSE;                             // 安全事件不受消音约束（Safety event cannot be silenced）
ELSE
    _bPendSilence := TRUE;                              // 登记消音请求，段 8 消费（Register silence request, consumed in section 8）
    SilenceBuzzer := TRUE;                              // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: Reset —— 复位故障锁存。仅存在锁存故障时返回 TRUE。
 *      Method Reset - release the fault latch, TRUE only when a latch exists.
 *------------------------------------------------------------------------------*)
METHOD Reset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch THEN
    _bPendReset := TRUE;                                // 登记复位请求，段 3 消费（Register reset request, consumed in section 3）
    Reset       := TRUE;                                // 可复位（Resettable）
ELSE
    Reset       := FALSE;                               // 无锁存可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 显示状态只读视图（仲裁结果的语义分类）。
 *      Property eState (GET) - read-only displayed state.
 *------------------------------------------------------------------------------*)
PROPERTY eState : E_DL_TowerState
eState := _eDispState;                                  // 返回显示状态（Return displayed state）

(*------------------------------------------------------------------------------
 * 属性: eRed（GET）—— 红色通道模式只读视图。
 *      Property eRed (GET) - read-only red channel pattern.
 *------------------------------------------------------------------------------*)
PROPERTY eRed : E_DL_TowerPattern
eRed := _eRedPat;                                       // 返回红模式（Return red pattern）

(*------------------------------------------------------------------------------
 * 属性: eAmber（GET）—— 黄色通道模式只读视图。
 *      Property eAmber (GET) - read-only amber channel pattern.
 *------------------------------------------------------------------------------*)
PROPERTY eAmber : E_DL_TowerPattern
eAmber := _eAmberPat;                                   // 返回黄模式（Return amber pattern）

(*------------------------------------------------------------------------------
 * 属性: eGreen（GET）—— 绿色通道模式只读视图。
 *      Property eGreen (GET) - read-only green channel pattern.
 *------------------------------------------------------------------------------*)
PROPERTY eGreen : E_DL_TowerPattern
eGreen := _eGreenPat;                                   // 返回绿模式（Return green pattern）

(*------------------------------------------------------------------------------
 * 属性: eBlue（GET）—— 蓝色通道模式只读视图。
 *      Property eBlue (GET) - read-only blue channel pattern.
 *------------------------------------------------------------------------------*)
PROPERTY eBlue : E_DL_TowerPattern
eBlue := _eBluePat;                                     // 返回蓝模式（Return blue pattern）

(*------------------------------------------------------------------------------
 * 属性: eWhite（GET）—— 白色通道模式只读视图。
 *      Property eWhite (GET) - read-only white channel pattern.
 *------------------------------------------------------------------------------*)
PROPERTY eWhite : E_DL_TowerPattern
eWhite := _eWhitePat;                                   // 返回白模式（Return white pattern）

(*------------------------------------------------------------------------------
 * 属性: bBuzzer（GET）—— 蜂鸣器当前输出（已合成使能与消音）。
 *      Property bBuzzer (GET) - composed buzzer output.
 *------------------------------------------------------------------------------*)
PROPERTY bBuzzer : BOOL
bBuzzer := _bBuzzerInt;                                 // 返回蜂鸣合成输出（Return composed buzzer output）

(*------------------------------------------------------------------------------
 * 属性: bSilenced（GET）—— 消音保持窗内为 TRUE。
 *      Property bSilenced (GET) - TRUE inside the silence hold window.
 *------------------------------------------------------------------------------*)
PROPERTY bSilenced : BOOL
bSilenced := _bSilenceActive;                           // 返回消音保持状态（Return silence hold state）

(*------------------------------------------------------------------------------
 * 属性: bError（GET）—— 故障锁存指示（信息级码不置本位，公约 0.2）。
 *      Property bError (GET) - fault latch only, info codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bError : BOOL
bError := _bFaultLatch;                                 // 仅故障级派生（Fault-level derivation only）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 故障级码优先，否则本拍信息级码（0=无错误）。
 *      Property uErrorId (GET) - fault-level code first, else the info code.
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF _uErrFault <> 0 THEN
    uErrorId := _uErrFault;                             // 故障级码优先（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;                             // 否则上报本拍信息级码（Otherwise report the info code）
END_IF
END_FUNCTION_BLOCK
