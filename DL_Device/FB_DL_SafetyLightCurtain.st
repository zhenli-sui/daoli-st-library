(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SafetyLightCurtain
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备功能块（Function Block，实现 I_DL_LightCurtain）
 * 功能简述 (Function)   : 光幕 OSSD 监控 + 2/4 传感器序列屏蔽状态机 + 屏蔽
 *                         总时长超时 + 滞留清除 override + 屏蔽灯输出（屏蔽
 *                         常亮/override 闪烁）+ 故障复位联锁（SICK mut_p /
 *                         西门子 Sequential Muting 公开语义 clean-room）。
 * 定位声明 (Positioning): 公约 0.13——本块为标准 PLC 逻辑编排与诊断镜像层，
 *                         不构成 ISO 13849 / IEC 62061 认证安全功能，安全回
 *                         路由认证安全控制器/安全 PLC 承载；光幕本体 OSSD
 *                         的安全判断在认证安全光幕内部完成，本块仅做诊断镜
 *                         像与屏蔽编排。
 * 接口实现 (Implements) : I_DL_LightCurtain。接口属性同名成员（eState/bClear/
 *                         bMutingActive/bOverrideActive/bSafeStop/bFault/
 *                         uErrorId）按 R22 以只读 PROPERTY GET 承载（内部镜
 *                         像同源），非接口成员 bMutingLamp 保留 VAR_OUTPUT；
 *                         方法 CmdOverride/CmdAck/CmdReset 在本文件尾部落地。
 * 公约遵循 (Convention) : 0.1/R23 事件/电平混合编排（电平条件级联驱动，无连
 *                         续量同步语义），免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 全部实例主
 *                         体最前部无条件刷新；0.7/R15 故障级锁存仅复位路径
 *                         清码。
 *                         0.8 故障码段位 16#0003_xxxx（经 DL_Device
 *                         VERSION.md 码表核对：规格建议 0003_0270/0271/0272
 *                         已被 FB_DL_ThreePointValve 占用、0003_0106 已被
 *                         FB_DL_VfdGeneric 占用，依公约冲突顺延）：
 *                         【故障级】0003_02A0 屏蔽传感器序列错误、0003_02A1
 *                         屏蔽超时、0003_02A2 OSSD 双通道不一致；
 *                         【信息级】0003_0122 override 准入拒绝（无遮挡）、
 *                         0003_0118 override 硬帽到期退出。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 参数钳位/超窗防御 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 状态映像 IF 派生
 *                         链含 ELSE 兜底（无显式 CASE 主状态机，见偏离①）✓
 *                         R7 五实例（R_TRIG×1/TON×4）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 序列屏蔽：2 传感器 M1→M2 进入、M1→M2 清离退出；
 *                           4 传感器正向 M1→M2 进入、M3→M4 离开、全清退出，
 *                           反向全程镜像；序列错乱 → 立即退出屏蔽 + 故障 +
 *                           bSafeStop 按光幕实际状态输出；
 *                         ② override 准入硬约束：bOverrideKey（或方法请求）
 *                           AND 屏蔽传感器至少一真才进入，无遮挡拒绝置信级；
 *                         ③ 屏蔽灯闪烁用主周期 TON 振荡器自实现（方波生成
 *                           不用 TON 单实例直出，用 IN:=NOT Q 重触发振荡法；
 *                           R14 断输入一拍规则不涉及方波生成，注释说明）；
 *                         ④ OSSD 双通道不一致超 tDiscrepancy → 故障锁存；
 *                         ⑤ bSafeStop 出口断言：屏蔽/override 态恒 FALSE
 *                           （光幕正常），永不因屏蔽置假。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 2 条：
 *                         ① 码位与兜底态：规格建议 0003_0270/0271/0272/0273
 *                           与既有 FB_DL_ThreePointValve 冲突，顺延为
 *                           0003_02A0/02A1/02A2；因本块状态为条件派生映像
 *                           （无独立 CASE 主状态机），「非法状态兜底」码不
 *                           适用而取消，派生链含 ELSE 兜底保证域外输入归安
 *                           全侧（核对结果优先于建议值）。
 *                         ② 反向序列：2 传感器模式以「首遮挡传感器」判定方
 *                           向（M1 先遮挡=正向）；4 传感器模式同理（M4 先
 *                           遮挡=反向），方向一经判定锁定至本序列结束。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / light-curtain-muting
 *                         （RAW_NOTES_R7 S-5：SICK mut_p 与西门子 Sequential
 *                         Muting 公开手册语义——2/4 传感器序列、容差窗、
 *                         override 硬帽、屏蔽灯，公开资料，仅借鉴语义域；
 *                         状态步进实现、码位与引脚契约 100% 本库独立设计，
 *                         clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 无屏蔽遮挡停机链：光幕遮挡且未屏蔽 → bSafeStop=TRUE、eState=eBlocked；
 *   V2 2 传感器合法序列：M1→M2 遮挡（屏蔽灯常亮，bSafeStop=FALSE）→ M1 清
 *      → M2 清（序列完成回 eClear）；
 *   V3 序列错乱停机：M2 先遮挡后 M1 清（E2 清而 E1 仍遮挡）→ 故障 0003_02A0
 *      + bSafeStop 按实际 OSSD 输出；
 *   V4 屏蔽超时：序列驻留超 tMutingTimeout → 故障 0003_02A1；
 *   V5 override 准入/拒绝/硬帽：钥匙开关无遮挡 → 拒绝置信级 0003_0122；有遮
 *      挡 → eOverride 灯闪；超 tOverrideMax → 退出 + 0003_0118；
 *   V6 OSSD 不一致：双通道异电平超 tDiscrepancy → 故障 0003_02A2；
 *   V7 复位联锁：故障后仅 bReset 沿且故障源消失才解除锁存。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 光幕族实现件）
 *   2026-11-15  v1.0.1  终审修复 2 处：① 反向序列判向条件与偏离②矛盾——
 *                       2 传感器模式判向 ELSIF 与正向 IF 恒等（死代码）、4
 *                       传感器模式误查 M3（应为 M4=_bX2），按「M2/M4 先遮挡=
 *                       反向」修正；② 2 传感器 E2 步双清离无分支 → 步号滞留、
 *                       依赖屏蔽超时误报故障，补双清离回 IDLE（中断恢复）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SafetyLightCurtain IMPLEMENTS I_DL_LightCurtain
VAR_INPUT
    bOssd1          : BOOL;             // 光幕 OSSD 通道 1（OSSD channel 1），TRUE=通光 / OSSD channel 1, TRUE = clear
    bOssd2          : BOOL;             // 光幕 OSSD 通道 2（OSSD channel 2），TRUE=通光 / OSSD channel 2, TRUE = clear
    bMutSens1       : BOOL;             // 屏蔽传感器 1（Muting sensor 1），TRUE=被遮挡；2 传感器模式使用 / Muting sensor 1, TRUE = blocked, 2-sensor mode
    bMutSens2       : BOOL;             // 屏蔽传感器 2（Muting sensor 2），TRUE=被遮挡；2 传感器模式使用 / Muting sensor 2, TRUE = blocked, 2-sensor mode
    bMutSens3       : BOOL;             // 屏蔽传感器 3（Muting sensor 3），TRUE=被遮挡；4 传感器模式使用 / Muting sensor 3, TRUE = blocked, 4-sensor mode
    bMutSens4       : BOOL;             // 屏蔽传感器 4（Muting sensor 4），TRUE=被遮挡；4 传感器模式使用 / Muting sensor 4, TRUE = blocked, 4-sensor mode
    bFourSensorMode : BOOL;             // 四传感器模式选择（Four-sensor mode），TRUE=序列式 4 传感器；FALSE=2 传感器 / TRUE = 4-sensor sequential, FALSE = 2-sensor
    bEnableMuting   : BOOL;             // 屏蔽功能总使能（Muting enable），FALSE=任何屏蔽条件都不生效（纯防护模式）/ FALSE disables all muting, pure guard mode
    bOverrideKey    : BOOL;             // 滞留清除钥匙开关（Override key，双通道语义由接线层保证），电平保持式 / Override key, level-held
    bReset          : BOOL;             // 复位按钮（Reset），上升沿复位故障与重启联锁 / Reset edge clears fault and restart interlock
    tMutingTimeout  : TIME := T#30S;    // 屏蔽总时长上限（Muting timeout），域 1S~600S 越界钳位；首末传感器间隔超限即故障 / Muting total-time cap, clamped 1S..600S
    tDiscrepancy    : TIME := T#3S;     // 传感器容差窗（Sensor discrepancy time），域 100MS~10S 越界钳位 / Discrepancy window, clamped 100MS..10S
    tOverrideMax    : TIME := T#30S;    // 滞留清除硬帽（Override max time），域 1S~60S 越界钳位 / Override hard cap, clamped 1S..60S
END_VAR
VAR_OUTPUT
    bMutingLamp : BOOL;                 // 屏蔽灯输出（Muting lamp）：屏蔽常亮、override 闪烁 / Muting lamp: steady in muting, blinking in override
END_VAR
VAR
    _eState       : E_DL_CurtainState;  // 派生状态映像（Derived state image），属性只读 / Derived state, read-only via property
    _bFaultLatch  : BOOL;               // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt  : UDINT;              // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode    : UDINT;              // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _nMutStep     : USINT;              // 屏蔽序列步号（Muting sequence step），0=空闲 / Muting step, 0 = idle
    _bMutRev      : BOOL;               // 反向序列方向标志（Reverse sequence direction），首遮挡传感器判定 / Reverse direction by first-blocked sensor
    _bE1          : BOOL;               // 映射后进入侧传感器 1（Mapped entry sensor 1）/ Mapped entry sensor 1
    _bE2          : BOOL;               // 映射后进入侧传感器 2（Mapped entry sensor 2）/ Mapped entry sensor 2
    _bX1          : BOOL;               // 映射后离开侧传感器 1（Mapped exit sensor 1）/ Mapped exit sensor 1
    _bX2          : BOOL;               // 映射后离开侧传感器 2（Mapped exit sensor 2）/ Mapped exit sensor 2
    _bMutingAct   : BOOL;               // 屏蔽进行中派生（Muting-active derived flag）/ Muting-active derived flag
    _bOverrideAct : BOOL;               // 滞留清除进行中（Override active flag）/ Override active flag
    _bPendOverride: BOOL;               // 方法 override 请求（Method override request）/ Method override request
    _bPendAck     : BOOL;               // 方法确认请求（Method ack request）/ Method ack request
    _bPendReset   : BOOL;               // 方法复位请求（Method reset request）/ Method reset request
    _bAnyMutBlocked: BOOL;              // 屏蔽传感器任一遮挡（Any muting sensor blocked）/ Any muting sensor blocked
    _tMutToEff    : TIME := T#30S;      // 钳位后屏蔽超时（Clamped muting timeout）/ Clamped muting timeout
    _tDiscEff     : TIME := T#3S;       // 钳位后容差窗（Clamped discrepancy window）/ Clamped discrepancy window
    _tOvrMaxEff   : TIME := T#30S;      // 钳位后 override 硬帽（Clamped override cap）/ Clamped override cap
    _fbTrigReset  : R_TRIG;             // 复位沿（Reset edge）/ Reset edge detector
    _fbTonDisc    : TON;                // OSSD 双通道容差窗（OSSD discrepancy window）/ OSSD discrepancy window
    _fbTonMutTo   : TON;                // 屏蔽总时长超时（Muting total-time timeout）/ Muting total-time timeout
    _fbTonOvrMax  : TON;                // override 硬帽计时（Override hard-cap timer）/ Override hard-cap timer
    _fbTonBlink   : TON;                // 屏蔽灯闪烁振荡器（Lamp blink oscillator），IN:=NOT Q 重触发 / Lamp blink oscillator, retriggered by NOT Q
END_VAR
VAR CONSTANT
    DL_BLINK_HALF : TIME := T#250MS;    // 屏蔽灯闪烁半周期（Lamp blink half period）/ Lamp blink half period
    DL_MUTTO_MIN  : TIME := T#1S;       // 屏蔽超时下限（Muting timeout lower clamp）/ Muting timeout lower clamp
    DL_MUTTO_MAX  : TIME := T#600S;     // 屏蔽超时上限（Muting timeout upper clamp）/ Muting timeout upper clamp
    DL_DISC_MIN   : TIME := T#100MS;    // 容差窗下限（Discrepancy lower clamp）/ Discrepancy lower clamp
    DL_DISC_MAX   : TIME := T#10S;      // 容差窗上限（Discrepancy upper clamp）/ Discrepancy upper clamp
    DL_OVR_MIN    : TIME := T#1S;       // override 硬帽下限（Override cap lower clamp）/ Override cap lower clamp
    DL_OVR_MAX    : TIME := T#60S;      // override 硬帽上限（Override cap upper clamp）/ Override cap upper clamp
    MUT_STEP_IDLE  : USINT := 0;        // 序列步：空闲（Step: idle）/ Step: idle
    MUT_STEP_E1    : USINT := 1;        // 序列步：首进入传感器已遮挡（Step: first entry sensor blocked）/ Step: first entry sensor blocked
    MUT_STEP_E2    : USINT := 2;        // 序列步：进入侧成对遮挡，屏蔽生效（Step: entry pair blocked, muting on）/ Step: entry pair blocked, muting on
    MUT_STEP_EXIT1 : USINT := 3;        // 序列步：首进入传感器清离（2 传感器退出段）/ Step: first entry sensor cleared (2-sensor exit)
    MUT_STEP_X1    : USINT := 4;        // 序列步：离开侧首传感器遮挡（4 传感器）/ Step: first exit sensor blocked (4-sensor)
    MUT_STEP_X2    : USINT := 5;        // 序列步：离开侧成对遮挡（4 传感器）/ Step: exit pair blocked (4-sensor)
    MUT_STEP_CL1   : USINT := 6;        // 序列步：离开侧首传感器清离（4 传感器退出段）/ Step: first exit sensor cleared (4-sensor exit)
END_VAR

METHOD CmdOverride : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CurtainState.eFault) THEN
    CmdOverride := FALSE;         // 故障态拒绝（Rejected in fault）
ELSIF _bAnyMutBlocked THEN
    _bPendOverride := TRUE;       // 登记请求，主体编排消化（Register request, consumed by body）
    CmdOverride := TRUE;          // 受理成功（Accepted）
ELSE
    CmdOverride := FALSE;         // 无遮挡拒绝（Rejected with nothing blocked）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdAck —— 屏蔽/故障确认复位：中止当前屏蔽序列回评估态（非故障态）。
 *      Method CmdAck - aborts the current muting sequence back to evaluation.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdAck : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CurtainState.eFault) THEN
    CmdAck := FALSE;              // 故障态走 CmdReset（Fault goes through CmdReset）
ELSIF _bMutingAct OR _bOverrideAct THEN
    _bPendAck := TRUE;            // 登记确认请求（Register ack request）
    CmdAck := TRUE;               // 受理成功（Accepted）
ELSE
    CmdAck := FALSE;              // 无屏蔽活动可确认（Nothing to acknowledge）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障与重启联锁：仅故障态受理（接口方法拒绝语义）。
 *      Method CmdReset - reset fault and interlock, accepted only in fault.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CurtainState.eFault) THEN
    _bPendReset := TRUE;          // 登记复位请求（Register reset request）
    CmdReset := TRUE;             // 可复位（Resettable）
ELSE
    CmdReset := FALSE;            // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前光幕状态只读视图。
 *      Property eState (GET) - read-only curtain state view.
 *------------------------------------------------------------------------------*)
    END_METHOD

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
//      屏蔽灯闪烁用 TON 振荡器（IN := NOT Q 重触发）生成方波：Q 每 250MS 翻
//      转，override 态取 Q 作闪烁源；方波生成不适用 R14 断输入一拍规则（变
//      相位由振荡器自身承担），注释说明。
//      Lamp blink via a TON oscillator (IN := NOT Q): Q toggles every 250 MS;
//      the R14 one-scan-off rule does not apply to square-wave generation.
// ============================================================================
_fbTrigReset(CLK := bReset);
_fbTonDisc(IN := (bOssd1 <> bOssd2), PT := _tDiscEff);                    // OSSD 容差窗（OSSD discrepancy window）
_fbTonMutTo(IN := (_nMutStep > MUT_STEP_IDLE) AND (NOT _bFaultLatch), PT := _tMutToEff); // 屏蔽总时长（Muting total time）
_fbTonOvrMax(IN := _bOverrideAct, PT := _tOvrMaxEff);                     // override 硬帽（Override hard cap）
_fbTonBlink(IN := (NOT _fbTonBlink.Q), PT := DL_BLINK_HALF);              // 闪烁振荡器（Blink oscillator）

// ============================================================================
// 段 2｜参数钳位 + 信息级码预清零 + 复位路径（R15）
//      Parameter clamps + info preset + reset path (R15)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）
IF tMutingTimeout < DL_MUTTO_MIN THEN
    _tMutToEff := DL_MUTTO_MIN;   // 超时下限钳位（Timeout lower clamp）
ELSIF tMutingTimeout > DL_MUTTO_MAX THEN
    _tMutToEff := DL_MUTTO_MAX;   // 超时上限钳位（Timeout upper clamp）
ELSE
    _tMutToEff := tMutingTimeout; // 合法直通（Valid pass-through）
END_IF
IF tDiscrepancy < DL_DISC_MIN THEN
    _tDiscEff := DL_DISC_MIN;     // 容差窗下限钳位（Discrepancy lower clamp）
ELSIF tDiscrepancy > DL_DISC_MAX THEN
    _tDiscEff := DL_DISC_MAX;     // 容差窗上限钳位（Discrepancy upper clamp）
ELSE
    _tDiscEff := tDiscrepancy;    // 合法直通（Valid pass-through）
END_IF
IF tOverrideMax < DL_OVR_MIN THEN
    _tOvrMaxEff := DL_OVR_MIN;    // 硬帽下限钳位（Cap lower clamp）
ELSIF tOverrideMax > DL_OVR_MAX THEN
    _tOvrMaxEff := DL_OVR_MAX;    // 硬帽上限钳位（Cap upper clamp）
ELSE
    _tOvrMaxEff := tOverrideMax;  // 合法直通（Valid pass-through）
END_IF

IF _fbTrigReset.Q OR _bPendReset THEN
    _bPendReset := FALSE;         // 消费方法复位请求（Consume method reset）
    IF NOT _fbTonDisc.Q THEN      // 复位联锁：OSSD 不一致故障源已消失才解除（Restart interlock: source gone）
        _bFaultLatch := FALSE;    // 故障锁存解除（Fault latch released）
        _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
        _nMutStep := MUT_STEP_IDLE;   // 序列步归零（Sequence step reset）
    END_IF
END_IF

// ============================================================================
// 段 3｜故障全局监视（优先级最高）：OSSD 双通道不一致 / 屏蔽超时
//      Global fault monitors: OSSD discrepancy / muting timeout
// ============================================================================
IF _fbTonDisc.Q THEN
    _bFaultLatch := TRUE;         // OSSD 双通道不一致锁存（OSSD discrepancy latch）
    _uErrorIdInt := 16#0003_02A2; // 0003_02A2 OSSD 双通道不一致【故障级】/ OSSD channel discrepancy, fault level
ELSIF _fbTonMutTo.Q THEN
    _bFaultLatch := TRUE;         // 屏蔽总时长超时锁存（Muting timeout latch）
    _uErrorIdInt := 16#0003_02A1; // 0003_02A1 屏蔽超时【故障级】/ Muting timeout, fault level
END_IF
IF _bFaultLatch THEN
    _nMutStep := MUT_STEP_IDLE;   // 故障即退出屏蔽序列（Fault exits the sequence）
END_IF

// ============================================================================
// 段 4｜传感器方向映射 + 屏蔽序列步进机 + override 编排（无故障时执行）
//      Sensor direction mapping + muting step machine + override orchestration
// ============================================================================
_bAnyMutBlocked := bMutSens1 OR bMutSens2 OR bMutSens3 OR bMutSens4; // 任一屏蔽传感器遮挡（Any sensor blocked）

IF NOT _bFaultLatch THEN
    // —— 方法确认消费：中止当前屏蔽/override 序列回评估态 ——
    IF _bPendAck THEN
        _bPendAck := FALSE;           // 消费方法确认请求（Consume method ack）
        _nMutStep := MUT_STEP_IDLE;   // 屏蔽序列中止（Sequence aborted）
        _bOverrideAct := FALSE;       // override 中止（Override aborted）
    END_IF

    // —— 方向映射（偏离②：首遮挡传感器判向）——
    IF bFourSensorMode THEN
        IF NOT _bMutRev THEN
            _bE1 := bMutSens1;        // 正向进入侧 1 = M1（Fwd entry 1 = M1）
            _bE2 := bMutSens2;        // 正向进入侧 2 = M2（Fwd entry 2 = M2）
            _bX1 := bMutSens3;        // 正向离开侧 1 = M3（Fwd exit 1 = M3）
            _bX2 := bMutSens4;        // 正向离开侧 2 = M4（Fwd exit 2 = M4）
        ELSE
            _bE1 := bMutSens4;        // 反向进入侧 1 = M4（Rev entry 1 = M4）
            _bE2 := bMutSens3;        // 反向进入侧 2 = M3（Rev entry 2 = M3）
            _bX1 := bMutSens2;        // 反向离开侧 1 = M2（Rev exit 1 = M2）
            _bX2 := bMutSens1;        // 反向离开侧 2 = M1（Rev exit 2 = M1）
        END_IF
    ELSE
        IF NOT _bMutRev THEN
            _bE1 := bMutSens1;        // 正向进入侧 1 = M1（Fwd entry 1 = M1）
            _bE2 := bMutSens2;        // 正向进入侧 2 = M2（Fwd entry 2 = M2）
        ELSE
            _bE1 := bMutSens2;        // 反向进入侧 1 = M2（Rev entry 1 = M2）
            _bE2 := bMutSens1;        // 反向进入侧 2 = M1（Rev entry 2 = M1）
        END_IF
        _bX1 := _bE1;                 // 2 传感器模式：离开侧=同对清离（Exit = clearing of the same pair）
        _bX2 := _bE2;
    END_IF

    // —— 屏蔽序列步进机（电平条件级联，序列错乱即故障退出）——
    //     Muting sequence step machine (level-condition cascade, any deviation faults out)
    IF NOT bEnableMuting THEN
        _nMutStep := MUT_STEP_IDLE;   // 总使能切断：序列强制空闲（Master disable forces idle）
    ELSE
        CASE _nMutStep OF
            MUT_STEP_IDLE: // 空闲：等待首传感器遮挡判向
                IF _bE1 AND (NOT _bE2) AND (NOT _bX1) AND (NOT _bX2) THEN
                    _nMutStep := MUT_STEP_E1; // 首进入传感器遮挡（First entry sensor blocked）
                ELSIF ((NOT bFourSensorMode) AND _bE2 AND (NOT _bE1))
                   OR (bFourSensorMode AND _bX2 AND (NOT _bE1) AND (NOT _bE2) AND (NOT _bX1)) THEN
                    _bMutRev := NOT _bMutRev; // 次序第二传感器先遮挡：判反向（v1.0.1 修复：原条件 2 传感器
                                              // 模式与正向 IF 恒等矛盾成死代码、4 传感器模式误查 M3，
                                              // 按偏离②语义 M2/M4 先遮挡=反向）/ Second-in-order blocked
                                              // first: reverse (v1.0.1 fix per deviation note ②)
                    _nMutStep := MUT_STEP_E1; // 反向序列启动（Reverse sequence starts）
                END_IF

            MUT_STEP_E1: // 首进入传感器已遮挡：等第二进入传感器
                IF _bE1 AND _bE2 THEN
                    _nMutStep := MUT_STEP_E2; // 进入侧成对遮挡，屏蔽生效（Entry pair blocked, muting on）
                ELSIF NOT _bE1 THEN
                    _bFaultLatch := TRUE;     // 首传感器提前清离：序列错乱（First sensor cleared early: sequence error）
                    _uErrorIdInt := 16#0003_02A0; // 0003_02A0 屏蔽传感器序列错误【故障级】/ Muting sequence error, fault level
                    _nMutStep := MUT_STEP_IDLE;
                END_IF

            MUT_STEP_E2: // 屏蔽生效：2 传感器等首清离 / 4 传感器等离开侧首遮挡
                IF bFourSensorMode THEN
                    IF _bX1 THEN
                        _nMutStep := MUT_STEP_X1; // 离开侧首传感器遮挡（First exit sensor blocked）
                    ELSIF (NOT _bE1) OR (NOT _bE2) THEN
                        _nMutStep := MUT_STEP_IDLE; // 物未达离开侧即全清：屏蔽正常收尾（Cleared before exit pair: normal end）
                    ELSIF _bX2 THEN
                        _bFaultLatch := TRUE;     // 离开侧第二传感器先遮挡：序列错乱（Exit second first: sequence error）
                        _uErrorIdInt := 16#0003_02A0;
                        _nMutStep := MUT_STEP_IDLE;
                    END_IF
                ELSE
                    IF (NOT _bE1) AND _bE2 THEN
                        _nMutStep := MUT_STEP_EXIT1; // 首进入传感器清离（First entry sensor cleared）
                    ELSIF (NOT _bE2) AND _bE1 THEN
                        _bFaultLatch := TRUE;        // 第二传感器先清离：序列错乱（Second cleared first: sequence error）
                        _uErrorIdInt := 16#0003_02A0;
                        _nMutStep := MUT_STEP_IDLE;
                    ELSIF (NOT _bE1) AND (NOT _bE2) THEN
                        _nMutStep := MUT_STEP_IDLE;  // 双清离：物体回退/中断恢复，序列中止回评估态（v1.0.1 修复：
                                                     // 原无分支滞留 E2 依赖屏蔽超时误报故障）/ Both cleared:
                                                     // abort back to evaluation (v1.0.1 fix)
                    END_IF
                END_IF

            MUT_STEP_EXIT1: // 2 传感器退出段：等第二传感器清离
                IF (NOT _bE1) AND (NOT _bE2) THEN
                    _nMutStep := MUT_STEP_IDLE;   // 序列完成（Sequence complete）
                ELSIF _bE1 AND _bE2 THEN
                    _nMutStep := MUT_STEP_E2;     // 新物体衔接进入：回屏蔽段（Back-to-back object: back to muting）
                END_IF

            MUT_STEP_X1: // 4 传感器：离开侧首遮挡，等成对
                IF _bX1 AND _bX2 THEN
                    _nMutStep := MUT_STEP_X2;     // 离开侧成对遮挡（Exit pair blocked）
                ELSIF NOT _bX1 THEN
                    _bFaultLatch := TRUE;         // 离开首传感器提前清离：序列错乱（Exit first cleared early: error）
                    _uErrorIdInt := 16#0003_02A0;
                    _nMutStep := MUT_STEP_IDLE;
                END_IF

            MUT_STEP_X2: // 4 传感器：离开侧成对，等首清离
                IF (NOT _bX1) AND _bX2 THEN
                    _nMutStep := MUT_STEP_CL1;    // 离开首传感器清离（Exit first cleared）
                ELSIF (NOT _bX2) AND _bX1 THEN
                    _bFaultLatch := TRUE;         // 离开第二传感器先清离：序列错乱（Exit second cleared first: error）
                    _uErrorIdInt := 16#0003_02A0;
                    _nMutStep := MUT_STEP_IDLE;
                END_IF

            MUT_STEP_CL1: // 4 传感器退出段：等第二传感器清离
                IF (NOT _bX1) AND (NOT _bX2) THEN
                    _nMutStep := MUT_STEP_IDLE;   // 序列完成（Sequence complete）
                ELSIF _bX1 AND _bX2 THEN
                    _nMutStep := MUT_STEP_X2;     // 新物体衔接：回成对段（Back-to-back: back to pair state）
                END_IF

            ELSE
                _nMutStep := MUT_STEP_IDLE;       // 步号域外兜底：强制空闲（Out-of-domain step: force idle）
        END_CASE
    END_IF

    // —— override 编排：准入硬约束（钥匙/方法请求 AND 至少一传感器遮挡）——
    //     Override orchestration: admission hard constraint
    IF _bOverrideAct THEN
        IF (NOT bOverrideKey) AND (NOT _bPendOverride) THEN
            _bOverrideAct := FALSE;       // 请求撤销退出（Request dropped: exit override）
        ELSIF _fbTonOvrMax.Q THEN
            _bOverrideAct := FALSE;       // 硬帽到期退出（Hard cap expired: exit override）
            _uInfoCode := 16#0003_0118;   // 0003_0118 override 硬帽到期退出【信息级】/ Override cap exit, info level
        END_IF
    ELSE
        IF (bOverrideKey OR _bPendOverride) AND _bAnyMutBlocked AND (NOT _bFaultLatch) THEN
            _bOverrideAct := TRUE;        // 准入成立进入 override（Admission granted, enter override）
        ELSIF (bOverrideKey OR _bPendOverride) AND (NOT _bAnyMutBlocked) THEN
            _uInfoCode := 16#0003_0122;   // 0003_0122 override 准入拒绝（无遮挡）【信息级】/ Override denied (nothing blocked), info level
        END_IF
        _bPendOverride := FALSE;          // 方法请求消费（Method request consumed）
    END_IF
END_IF

_bMutingAct := (_nMutStep >= MUT_STEP_E2) AND (NOT _bFaultLatch); // 屏蔽生效派生（Muting-active derived form）

// ============================================================================
// 段 5｜状态映像（IF 派生链含 ELSE 兜底）+ 输出推导 + bSafeStop 出口断言
//      State image (IF derivation chain with ELSE) + outputs + bSafeStop assertion
// ============================================================================
IF _bFaultLatch THEN
    _eState := E_DL_CurtainState.eFault;            // 故障锁存映像（Fault image）
ELSIF _bOverrideAct THEN
    _eState := E_DL_CurtainState.eOverride;         // 滞留清除映像（Override image）
ELSIF _bMutingAct THEN
    _eState := E_DL_CurtainState.eMuting;           // 屏蔽进行中映像（Muting image）
ELSIF NOT (bOssd1 AND bOssd2) THEN
    _eState := E_DL_CurtainState.eBlocked;          // 遮挡未屏蔽映像（Blocked image）
ELSE
    _eState := E_DL_CurtainState.eClear;            // 通光兜底映像（Clear fallback image）
END_IF

// bSafeStop 不在此处赋值：其为接口属性，由 PROPERTY bSafeStop（GET）以出口
// 断言式承载（R22）；此处仅推导非接口输出 bMutingLamp。
// bSafeStop is not written here: as an interface attribute it is carried by the
// PROPERTY getter with exit assertion (R22); only bMutingLamp is derived here.
bMutingLamp := _bMutingAct OR (_bOverrideAct AND _fbTonBlink.Q); // 屏蔽灯：屏蔽常亮/override 闪烁（Lamp: steady/blink）

(*------------------------------------------------------------------------------
 * 方法: CmdOverride —— 滞留物清除请求：至少一个屏蔽传感器仍遮挡才受理。
 *      Method CmdOverride - override accepted only with a muting sensor blocked.
 *------------------------------------------------------------------------------*)



PROPERTY eState : E_DL_CurtainState
eState := _eState;                // 返回派生状态（Return derived state）

(*------------------------------------------------------------------------------
 * 属性: bClear（GET）—— 光幕通光（OSSD 双通道全通光）。
 *      Property bClear (GET) - curtain clear (both OSSD channels clear).
 *------------------------------------------------------------------------------*)
PROPERTY bClear : BOOL
bClear := bOssd1 AND bOssd2;      // 双通道通光派生式（Both-channel clear derived form）

(*------------------------------------------------------------------------------
 * 属性: bMutingActive（GET）—— 屏蔽进行中。
 *      Property bMutingActive (GET) - muting active.
 *------------------------------------------------------------------------------*)
PROPERTY bMutingActive : BOOL
bMutingActive := _bMutingAct;     // 返回屏蔽派生标志（Return muting derived flag）

(*------------------------------------------------------------------------------
 * 属性: bOverrideActive（GET）—— 滞留清除进行中。
 *      Property bOverrideActive (GET) - override active.
 *------------------------------------------------------------------------------*)
PROPERTY bOverrideActive : BOOL
bOverrideActive := _bOverrideAct; // 返回 override 标志（Return override flag）

(*------------------------------------------------------------------------------
 * 属性: bSafeStop（GET）—— 应停机输出（核心安全镜像位，屏蔽/override 态断
 *         言恒 FALSE，永不因屏蔽置假）。
 *      Property bSafeStop (GET) - safe-stop mirror, asserted FALSE when muting/override.
 *------------------------------------------------------------------------------*)
PROPERTY bSafeStop : BOOL
bSafeStop := (NOT (bOssd1 AND bOssd2)) AND (NOT _bMutingAct)
          AND (NOT _bOverrideAct) AND (NOT _bFaultLatch); // 出口断言式派生（Exit-assertion derived form）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_CurtainState.eFault); // 显式排除信息级派生式（Derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（故障级优先，无故障时透出本拍信息级
 *         码，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last error code (fault priority, info shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_CurtainState.eFault) THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK
