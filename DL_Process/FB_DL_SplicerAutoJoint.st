//==============================================================================
// 功能块：FB_DL_SplicerAutoJoint ｜ 中文名称：自动接膜零停机顺控
// 所属子库：DL_Process ｜ 版本：v1.1.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：卷材设备自动接膜（零停机换卷）顺控：旧卷余量预警 → 新卷预加速 → 速度同步
//           确认（容差 + 保持时长双条件）→ 裁切压合 → 尾料处理 → 回到监测相。
//           安全铁律：未同步绝不裁切——速度差超容差或保持时长不足时裁切一律挂起，宁可
//           等，不裁切（拉断料带的代价远高于停一拍）。余量按面积（卷径平方）比例折算，
//           按直径线性折算会把余量算大一倍以上（量纲教训：卷材体积随直径平方变化）。
//           本件只发预加速/裁切指令与状态，不驱动伺服、不控气阀（执行器归设备层）。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现（原创，参考 公开工程惯例 分类与参数域）
// 单位表：卷径/芯径/满卷直径[mm] / 线速度[米每分] / 余量与预警门限[百分数] /
//         同步容差[百分数] / 时间窗[ms] / 扫描间隔[ms] / 接膜次数[次]
// 错误码表：16#0005_040A 信息级（余量预警触发，上升沿一次，不置 bError）/
//           16#0005_040B 信息级（同步窗未达，裁切挂起，不置 bError）/ 16#0005_0351
//           故障级（预加速超时中止且不裁切；兼「卷径组态非法（满卷直径 ≤ 芯径）」组态
//           分支，映射见本行反证句）/ 16#0005_0352 故障级（胶带未就绪或刀未归零，禁止
//           接膜，置 bError + 撤全部指令）/ 16#0005_0353 故障级（输入非有限，以及状态机
//           ELSE 非法状态兜底）。0351 共用反证句：组态非法、预加速超时与同步相超时
//           （v1.1.0 新增）在现有输出组合下不可观测出差异（均为 bError + bPreAccelCmd 撤
//           + bCutCmd 撤 + bSyncOk 撤 + bValid 撤），同步超时另由 bSyncTimeout 单拍事件可区分观测；
//           §4.17 亦明示组态分支映射入 0351，故共用不越段。0353 共用反证句：非有限
//           输入与非法状态在输出上同为全撤 + bError + eFault，不可观测出差异，故共用。
// 状态机：E_DL_SplicerState（eIdle=0 待机 / eMonitor=10 余量监测 / ePreAccel=20 新卷
//           预加速 / eSyncWait=30 同步确认 / eJointing=40 裁切压合 / eFault=99 故障兜底），
//           CASE 含 ELSE 兜底，ELSE 置 0353 且撤全部指令、许可撤。
// 边界行为：① 余量按面积比例 ((D^2 − core^2)/(full^2 − core^2)) x 100，D 低于芯径钳 0、
//           高于满卷钳 100；② fFullDiaMm <= fCoreDiaMm → 故障 0351 组态分支（分母为零
//           会产出伪余量，先判后算）；③ 预加速超 tPreAccelMax → 故障 0351 + 中止且绝不
//           裁切（停机保料优于拉断）；④ 同步未达（速度差 > 容差，或保持不足 tSyncHold）
//           → 裁切挂起 + 信息 040B（安全侧：宁可等，不裁切）；⑤ bTapeOk 或 bKnifeHome
//           为 FALSE → 禁止接膜 + 故障 0352；⑥ bStop → 中止并回 eIdle（同③不裁切）；
//           ⑦ 余量预警上升沿 → 信息 040A（用沿检测，防每拍刷屏）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.17）
//           v1.0.1 2026-11-17 终审补 eSyncWait 的「进相前置消失」第二退出条件（对外引脚契约零变更）：
//           bNewRollReady 撤销时退回 ePreAccel 相，由 tPreAccelMax 超时闸兜住，避免 bPreAccelCmd
//           长期拉住空卷（R98 家族）。两相 bCutCmd 均为 FALSE，「未同步绝不裁切」铁律不受影响。
//           v1.1.0 2026-11-17 R27 欠账收口（MINOR 升级，引脚契约只增不改、既有码位零变更）：
//           eSyncWait 相新增引脚 tSyncMax（同步等待超时，默认 T#5S）与自有计时器 fbTonSyncMax
//           （每周期无条件调用，仅 IN 条件化）；速度差持续超容差达 tSyncMax 即复用故障级 0351
//           （同段共用，反证句见错误码表 0351 行）并中止，bCutCmd 全程保持 FALSE；新增输出
//           bSyncTimeout（超时单拍事件，供审计计数）。
//           原挂账 R112 三要素收口：复现条件 = bNewRollReady 保持 TRUE 而速度差持续超容差（旧版将
//           无限期停在同步相）；禁用范围 = 无人值守连续线未配该超时者不得无人看管运行；修法取
//           ①新增 tSyncMax 引脚（默认 5 s 从紧口径）。
//           验收向量（VERSION 修订记录同步登记）：新卷就绪后速度差恒定 5%、容差 2% →
//           tSyncMax 之后置 0351、bSyncTimeout 单拍 TRUE、bCutCmd 全程 FALSE。
//           v1.1.1 2026-11-17 R27 终审修复（对外引脚与码位零变更）：fbTonSyncMax 的 IN 由
//           「eSyncWait AND NOT bSpeedWithin」改为「eSyncWait」按相驻留计时。原实现的看门狗
//           只在速度差超出容差时累积：速度差在容差边界抖动（模拟量噪声常态）时，同步超时
//           计时器与同步保持计时器交替复位，两者永不完成 → 相内无限滞留、段 8B 永不触发，
//           bPreAccelCmd 长期拉住空卷，恰是 v1.1.0 要收口的故障模式在抖动输入下的复现。
//           改为按相驻留计时后，相内总等待时长有上界，抖动亦能收口；正常同步（远早于
//           tSyncMax 完成）行为不变。验收向量：速度差在 2% 容差上下逐拍抖动 → tSyncMax 后 0351。
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_SplicerState（归属 DL_Process，与 FB_DL_SplicerAutoJoint 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SplicerState :
(
    eIdle     := 0,   // 待机：指令全撤 / Idle, every command dropped
    eMonitor  := 10,  // 余量监测：算余量、报预警 / Monitoring the remaining roll
    ePreAccel := 20,  // 预加速：新卷升速，等就绪与同步 / Pre-accelerating the new roll
    eSyncWait := 30,  // 同步确认：速度差在容差内且保持达时 / Confirming the speed match
    eJointing := 40,  // 裁切压合：出裁切指令并在接膜窗内完成 / Cutting and joining
    eFault    := 99   // 故障兜底：超时/胶带刀具不就绪/非有限/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SplicerAutoJoint
 * 调用约定: 每个扫描周期无条件调用一次；uDeltaTimeMs 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SplicerAutoJoint
VAR_INPUT
    fUnwindDiaMm    : LREAL;                       // 旧卷当前卷径 [mm] / Current unwinding roll diameter [mm]
    fCoreDiaMm      : LREAL;                       // 芯径 [mm]，须 > 0 / Core diameter [mm], must be > 0
    fFullDiaMm      : LREAL;                       // 满卷直径 [mm]，须 > 芯径 / Full roll diameter [mm], must exceed the core
    fWebSpeedMpm    : LREAL;                       // 旧卷线速度 [米每分] / Current web speed [m per min]
    fNewRollSpeedMpm : LREAL;                      // 新卷表面线速度 [米每分] / New roll surface speed [m per min]
    fRemainWarnPct  : LREAL := 15.0;               // 余量预警门限 [百分数] / Remaining-roll warning threshold [percent]
    fSyncTolPct     : LREAL := 2.0;                // 速度同步容差 [百分数] / Speed match tolerance [percent]
    tSyncHold       : TIME := T#500MS;             // 同步保持确认时长 [ms] / Speed match hold time [ms]
    tPreAccelMax    : TIME := T#20S;               // 预加速超时 [ms] / Pre-acceleration timeout [ms]
    tJointMax       : TIME := T#5S;                // 接膜（裁切压合）窗 [ms] / Joint window [ms]
    tSyncMax        : TIME := T#5S;                // 同步等待超时 [ms]，默认 5 s（eSyncWait 自有看门狗，小于 1 s 钳 1 s）/ Sync wait timeout [ms]
    bNewRollReady   : BOOL;                        // 新卷就绪（装卷到位、气路正常）/ New roll ready
    bKnifeHome      : BOOL;                        // 切刀在零位 / Knife at home position
    bTapeOk         : BOOL;                        // 胶带就绪 / Tape ready
    bStart          : BOOL;                        // 启动（取上升沿）/ Start, rising edge
    bStop           : BOOL;                        // 停止（中止并回待机，绝不裁切）/ Stop, aborts without cutting
    bReset          : BOOL;                        // 复位，上升沿回待机并清故障 / Reset, rising edge returns to idle
    uDeltaTimeMs    : UDINT;                       // 扫描间隔 [ms]，调用方注入，禁系统时间函数 / Scan interval [ms], caller-injected
END_VAR
VAR_OUTPUT
    bWarnLowRoll    : BOOL;                        // 余量预警（电平）/ Low-roll warning, level
    bPreAccelCmd    : BOOL;                        // 新卷预加速指令 / Pre-acceleration command
    bSyncOk         : BOOL;                        // 速度同步确认（容差 + 保持时长双条件）/ Speed match confirmed
    bSyncTimeout    : BOOL;                        // 同步超时事件（单拍脉冲，v1.1.0 新增）/ Sync-timeout event, single-scan pulse
    bCutCmd         : BOOL;                        // 裁切指令（未同步绝不为 TRUE）/ Cut command, never TRUE unless matched
    bJointDone      : BOOL;                        // 接膜完成（单拍脉冲）/ Joint completed, single-scan pulse
    fRemainPct      : LREAL;                       // 旧卷余量 [百分数]，按面积比例 / Remaining roll [percent], by area ratio
    uJointCount     : UDINT;                       // 接膜次数 [次]，饱和 / Joint count [pcs], saturating
    eErr            : UDINT;                       // 错误码，0 = 无错，码位 16#0005_040A 起信息级、16#0005_0351 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError          : BOOL;                        // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                        // 状态输出可用标志，失能/故障闸显式 FALSE / Status usable flag, explicit FALSE on disable/fault gates
    eState          : E_DL_SplicerState;           // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset         : R_TRIG;                      // 复位上升沿检测实例 / Reset rising edge detector
    fbStart         : R_TRIG;                      // 启动上升沿检测实例 / Start rising edge detector
    fbWarn          : R_TRIG;                      // 余量预警上升沿检测实例 / Low-roll warning rising edge detector
    fbTonPreAccel   : TON;                         // 预加速超时定时器实例 / Pre-acceleration timeout timer
    fbTonSyncHold   : TON;                         // 同步保持定时器实例 / Speed match hold timer
    fbTonJoint      : TON;                         // 接膜窗定时器实例 / Joint window timer
    fbTonSyncMax    : TON;                         // 同步相自有超时定时器实例（每周期无条件调用）/ Sync-phase watchdog timer instance
    tSyncMaxUse     : TIME;                        // 生效同步超时（下限钳 1 s 防误配置）/ Effective sync timeout, floored at 1 s
    fCoreSqMm2      : LREAL;                       // 芯径平方 [平方毫米] / Core diameter squared [mm2]
    fFullSqMm2      : LREAL;                       // 满卷直径平方 [平方毫米] / Full diameter squared [mm2]
    fDenomMm2       : LREAL;                       // 面积分母（满卷平方 − 芯径平方）[平方毫米] / Area denominator [mm2]
    fRemainNumMm2   : LREAL;                       // 面积分子（当前平方 − 芯径平方）[平方毫米] / Area numerator [mm2]
    fSpeedDiffPct   : LREAL;                       // 新旧卷速度差 [百分数] / Speed difference [percent]
    fTolEffPct      : LREAL;                       // 生效同步容差 [百分数] / Effective sync tolerance [percent]
    fWarnEffPct     : LREAL;                       // 生效预警门限 [百分数] / Effective warning threshold [percent]
    bNonFin         : BOOL;                        // 非有限判定中间标志 / Non-finite detection intermediate flag
    bSpeedWithin    : BOOL;                        // 速度差在容差内（瞬时）/ Speed difference within tolerance, instantaneous
    bJointOk        : BOOL;                        // 胶带与刀具均就绪 / Tape and knife both ready
    bFirstScan      : BOOL := TRUE;                // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_SPJ_CODE_INFO_1 : UDINT := 16#0005_040A;    // 信息级槽 1（余量预警触发） / info slot 1
    DL_SPJ_CODE_INFO_2 : UDINT := 16#0005_040B;    // 信息级槽 2（同步窗未达，裁切挂起） / info slot 2
    DL_SPJ_CODE_FLT_1  : UDINT := 16#0005_0351;    // 故障级槽 1（预加速超时/卷径组态非法） / fault slot 1
    DL_SPJ_CODE_FLT_2  : UDINT := 16#0005_0352;    // 故障级槽 2（胶带未就绪/刀未归零） / fault slot 2
    DL_SPJ_CODE_FLT_3  : UDINT := 16#0005_0353;    // 故障级槽 3（非有限/非法状态兜底） / fault slot 3
    DL_SPJ_CNT_MAX     : UDINT := 16#FFFF_FFFE;    // 接膜计数饱和值 [次] / Joint counter saturation
    DL_SPJ_PCT         : LREAL := 100.0;           // 百分数系数 [百分数] / Percent factor
    DL_SPJ_ZERO        : LREAL := 0.0;             // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_SPJ_TOL         : LREAL := 1.0E-6;          // 浮点比较容差 [—] / Float comparison tolerance
    DL_SPJ_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：三条沿检测与三个定时器在任意分支之外周期调用；
 *       定时器 IN 取上拍状态（单拍滞后对秒级时间窗无影响），计时链永不断流
 *----------------------------------------------------------------------------*)
bJointDone := FALSE;                               // 接膜完成为单拍脉冲，逐拍先清 / single-scan pulse cleared first
bSyncTimeout := FALSE;                             // 同步超时为单拍事件，逐拍先清 / sync-timeout event cleared first
tSyncMaxUse := tSyncMax;                           // 生效超时取引脚值 / effective timeout from the pin
IF tSyncMaxUse < T#1S THEN
    tSyncMaxUse := T#1S;                           // 超时下限钳 1 s（防 0 配置入相同拍误报）/ floored at 1 s
END_IF
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbStart(CLK := bStart);                            // 启动沿检测无条件刷新 / start edge refreshed unconditionally
fbTonPreAccel(IN := (eState = E_DL_SplicerState.ePreAccel), PT := tPreAccelMax);   // 预加速超时计时 / pre-acceleration timeout
fbTonSyncHold(IN := (eState = E_DL_SplicerState.eSyncWait) AND bSpeedWithin, PT := tSyncHold);   // 同步保持计时 / speed match hold
fbTonJoint(IN := (eState = E_DL_SplicerState.eJointing), PT := tJointMax);         // 接膜窗计时 / joint window
fbTonSyncMax(IN := (eState = E_DL_SplicerState.eSyncWait), PT := tSyncMaxUse);   // v1.1.1 改为按相驻留计时（见修订史 R27-3）/ sync watchdog on phase residency
fbWarn(CLK := bWarnLowRoll);                       // 预警上升沿检测无条件刷新 / warning edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_SplicerState.eIdle;
    eErr   := 0;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    bPreAccelCmd := FALSE;                         // 预加速指令撤 / pre-acceleration dropped
    bCutCmd := FALSE;                              // 裁切指令撤 / cut command dropped
    bSyncOk := FALSE;                              // 同步确认撤 / sync confirmation dropped
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸：映射入 0353（与非法状态共用，反证句见错误码表）
 *       安全侧：撤全部指令，绝不裁切
 *----------------------------------------------------------------------------*)
bNonFin := (fUnwindDiaMm <> fUnwindDiaMm) OR (ABS(fUnwindDiaMm) >= DL_SPJ_INF)
        OR (fCoreDiaMm <> fCoreDiaMm) OR (ABS(fCoreDiaMm) >= DL_SPJ_INF)
        OR (fFullDiaMm <> fFullDiaMm) OR (ABS(fFullDiaMm) >= DL_SPJ_INF)
        OR (fWebSpeedMpm <> fWebSpeedMpm) OR (ABS(fWebSpeedMpm) >= DL_SPJ_INF)
        OR (fNewRollSpeedMpm <> fNewRollSpeedMpm) OR (ABS(fNewRollSpeedMpm) >= DL_SPJ_INF)
        OR (fRemainWarnPct <> fRemainWarnPct) OR (ABS(fRemainWarnPct) >= DL_SPJ_INF)
        OR (fSyncTolPct <> fSyncTolPct) OR (ABS(fSyncTolPct) >= DL_SPJ_INF);   // 引脚非有限汇总 / pins non-finite
IF bNonFin THEN
    eState := E_DL_SplicerState.eFault;            // 进故障相 / enter fault state
    eErr   := DL_SPJ_CODE_FLT_3;                   // 故障级：输入非有限 / fault: non-finite input
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 状态不可用 / status unusable
    bPreAccelCmd := FALSE;                         // 预加速指令撤 / pre-acceleration dropped
    bCutCmd := FALSE;                              // 裁切指令撤（安全侧：绝不裁切）/ cut dropped, never cut
    bSyncOk := FALSE;                              // 同步确认撤 / sync confirmation dropped
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜卷径组态闸：满卷直径必须严格大于芯径（否则面积分母为零，余量必假）
 *       §4.17 明示本组态分支映射入 0351
 *----------------------------------------------------------------------------*)
IF (fCoreDiaMm <= DL_SPJ_TOL) OR (fFullDiaMm <= fCoreDiaMm + DL_SPJ_TOL) THEN
    eState := E_DL_SplicerState.eFault;            // 进故障相 / enter fault state
    eErr   := DL_SPJ_CODE_FLT_1;                   // 故障级：卷径组态非法（映射入 0351）/ fault: roll diameter configuration invalid
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 状态不可用 / status unusable
    bPreAccelCmd := FALSE;                         // 预加速指令撤 / pre-acceleration dropped
    bCutCmd := FALSE;                              // 裁切指令撤安全侧 / cut dropped, safe side
    bSyncOk := FALSE;                              // 同步确认撤 / sync confirmation dropped
    fRemainPct := DL_SPJ_ZERO;                     // 余量不可算，输出 0 而不是伪值 / remaining reported as 0, not a fake value
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜余量面积比例折算：((D^2 − core^2) / (full^2 − core^2)) x 100
 *       按直径线性折算会把余量算大一倍以上（面积随直径平方变化，R12 同族量纲教训）
 *----------------------------------------------------------------------------*)
fCoreSqMm2 := fCoreDiaMm * fCoreDiaMm;             // 芯径平方 [平方毫米] / core squared [mm2]
fFullSqMm2 := fFullDiaMm * fFullDiaMm;             // 满卷直径平方 [平方毫米] / full squared [mm2]
fDenomMm2 := fFullSqMm2 - fCoreSqMm2;              // 面积分母（段 4 已保证为正）[平方毫米] / area denominator, proven positive
fRemainNumMm2 := (fUnwindDiaMm * fUnwindDiaMm) - fCoreSqMm2;   // 面积分子 [平方毫米] / area numerator [mm2]
IF fRemainNumMm2 < DL_SPJ_ZERO THEN
    fRemainNumMm2 := DL_SPJ_ZERO;                  // 卷径低于芯径：分子钳零（欠卷异常不产出负余量）/ numerator floored at zero
END_IF
fRemainPct := fRemainNumMm2 / fDenomMm2 * DL_SPJ_PCT;   // 余量 [百分数] / remaining [percent]
IF fRemainPct > DL_SPJ_PCT THEN
    fRemainPct := DL_SPJ_PCT;                      // 卷径超满卷：钳 100 / clamped to 100
END_IF
IF fRemainPct < DL_SPJ_ZERO THEN
    fRemainPct := DL_SPJ_ZERO;                     // 下限防护 / floor guard
END_IF
fWarnEffPct := fRemainWarnPct;                     // 预警门限工作副本 [百分数] / warning threshold working copy
IF fWarnEffPct < DL_SPJ_ZERO THEN
    fWarnEffPct := DL_SPJ_ZERO;                    // 门限下限钳位 / threshold floored
END_IF
IF fWarnEffPct > DL_SPJ_PCT THEN
    fWarnEffPct := DL_SPJ_PCT;                     // 门限上限钳位 / threshold clamped to 100
END_IF
bWarnLowRoll := (fRemainPct <= fWarnEffPct);       // 余量预警（电平）/ low-roll warning, level

(*------------------------------------------------------------------------------
 * 段 6｜速度同步判据：|旧卷 − 新卷| / 旧卷 x 100 <= 容差（除子先判零，低速记不同步）
 *----------------------------------------------------------------------------*)
fTolEffPct := fSyncTolPct;                         // 容差工作副本 [百分数] / tolerance working copy
IF fTolEffPct < DL_SPJ_ZERO THEN
    fTolEffPct := DL_SPJ_ZERO;                     // 负容差钳零（等价于要求完全相等）/ negative tolerance floored
END_IF
IF fWebSpeedMpm > DL_SPJ_TOL THEN
    fSpeedDiffPct := ABS(fWebSpeedMpm - fNewRollSpeedMpm) / fWebSpeedMpm * DL_SPJ_PCT;   // 速度差 [百分数] / speed difference [percent]
    bSpeedWithin := (fSpeedDiffPct <= fTolEffPct); // 容差内判据 / within-tolerance predicate
ELSE
    fSpeedDiffPct := DL_SPJ_PCT;                   // 旧卷静止：速度差按满刻度记（不可判即不同步）/ web at standstill, treated as not matched
    bSpeedWithin := FALSE;                         // 静止时不允许裁切 / no cut while the web stands still
END_IF
bJointOk := bTapeOk AND bKnifeHome;                // 胶带与刀具就绪判据 / tape and knife ready predicate
bSyncOk := bSpeedWithin AND fbTonSyncHold.Q AND (eState = E_DL_SplicerState.eSyncWait);   // 同步确认＝容差内且保持达时 / match confirmed

(*------------------------------------------------------------------------------
 * 段 7｜禁止接膜闸：胶带未就绪或刀未归零 → 0352 + 撤指令（不裁切）
 *----------------------------------------------------------------------------*)
IF (NOT bJointOk) AND ((eState = E_DL_SplicerState.ePreAccel) OR (eState = E_DL_SplicerState.eSyncWait)
                       OR (eState = E_DL_SplicerState.eJointing)) THEN
    eState := E_DL_SplicerState.eFault;            // 进故障相 / enter fault state
    eErr   := DL_SPJ_CODE_FLT_2;                   // 故障级：胶带未就绪/刀未归零，禁止接膜 / fault: tape or knife not ready
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 状态不可用 / status unusable
    bPreAccelCmd := FALSE;                         // 预加速指令撤 / pre-acceleration dropped
    bCutCmd := FALSE;                              // 裁切指令撤（禁止接膜）/ cut dropped, joining forbidden
    bSyncOk := FALSE;                              // 同步确认撤 / sync confirmation dropped
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜预加速超时闸：0351 + 中止且绝不裁切（停机保料优于拉断）
 *----------------------------------------------------------------------------*)
IF (eState = E_DL_SplicerState.ePreAccel) AND fbTonPreAccel.Q THEN
    eState := E_DL_SplicerState.eFault;            // 进故障相 / enter fault state
    eErr   := DL_SPJ_CODE_FLT_1;                   // 故障级：预加速超时，中止且不裁切 / fault: pre-acceleration timeout, abort without cutting
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 状态不可用 / status unusable
    bPreAccelCmd := FALSE;                         // 预加速指令撤 / pre-acceleration dropped
    bCutCmd := FALSE;                              // 裁切指令撤（绝不裁切）/ cut dropped, never cut
    bSyncOk := FALSE;                              // 同步确认撤 / sync confirmation dropped
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 8B｜同步相超时闸（v1.1.0 欠账收口，R112 家族）：速度差持续超容差达 tSyncMax
 *       → 复用故障级 0351 并中止，bCutCmd 全程 FALSE（安全铁律：未同步绝不裁切）
 *----------------------------------------------------------------------------*)
IF (eState = E_DL_SplicerState.eSyncWait) AND fbTonSyncMax.Q THEN
    eState := E_DL_SplicerState.eFault;            // 进故障相 / enter fault state
    eErr   := DL_SPJ_CODE_FLT_1;                   // 故障级：同步超时（与预加速超时同段共用，反证句见头注）/ fault: sync timeout
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 状态不可用 / status unusable
    bPreAccelCmd := FALSE;                         // 预加速指令撤 / pre-acceleration dropped
    bCutCmd := FALSE;                              // 裁切指令撤（绝不裁切）/ cut dropped, never cut
    bSyncOk := FALSE;                              // 同步确认撤 / sync confirmation dropped
    bSyncTimeout := TRUE;                          // 同步超时单拍事件 / single-scan sync-timeout event
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜状态机：CASE 含 ELSE 兜底（非法状态 → 0353 + 撤全部指令 + 许可撤）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_SplicerState.eIdle:
        bPreAccelCmd := FALSE;                     // 待机预加速撤 / pre-acceleration dropped in idle
        bCutCmd := FALSE;                          // 待机裁切撤 / cut dropped in idle
        bSyncOk := FALSE;                          // 待机同步确认撤 / sync confirmation dropped in idle
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        eErr := 0;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF fbStart.Q THEN
            IF bJointOk THEN
                eState := E_DL_SplicerState.ePreAccel;   // 就绪才允许预加速 / pre-acceleration only when ready
                bFirstScan := FALSE;               // 首拍标志清除 / first-scan flag cleared
            ELSE
                eState := E_DL_SplicerState.eFault;      // 不就绪直接进故障相（0352）/ not ready enters the fault state
                eErr := DL_SPJ_CODE_FLT_2;         // 故障级：胶带未就绪/刀未归零 / fault: tape or knife not ready
                bError := TRUE;                    // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
            END_IF
        ELSE
            eState := E_DL_SplicerState.eMonitor;  // 无启动沿：进常驻余量监测相（监测是被动功能，无需启动）/ passive monitoring needs no start
        END_IF

    E_DL_SplicerState.eMonitor:
        bPreAccelCmd := FALSE;                     // 监测相不预加速 / no pre-acceleration while monitoring
        bCutCmd := FALSE;                          // 监测相不裁切 / no cut while monitoring
        bSyncOk := FALSE;                          // 监测相无同步确认 / no sync confirmation while monitoring
        bValid := TRUE;                            // 余量与预警可用 / remaining and warning usable
        bError := FALSE;                           // 监测相无故障 / no fault while monitoring
        IF fbWarn.Q THEN
            eErr := DL_SPJ_CODE_INFO_1;            // 信息级：余量预警触发（上升沿一次）/ info: low-roll warning, once per rising edge
        ELSE
            eErr := 0;                  // 非预警沿不占码位 / no code without a warning edge
        END_IF
        IF fbStart.Q AND bJointOk THEN
            eState := E_DL_SplicerState.ePreAccel; // 启动且就绪进预加速 / start with readiness enters pre-acceleration
        ELSIF fbStart.Q AND (NOT bJointOk) THEN
            eState := E_DL_SplicerState.eFault;    // 启动但不就绪：禁止接膜 / start without readiness forbids joining
            eErr := DL_SPJ_CODE_FLT_2;             // 故障级：胶带未就绪/刀未归零 / fault: tape or knife not ready
            bError := TRUE;                        // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
            bValid := FALSE;                       // 状态不可用 / status unusable
        END_IF

    E_DL_SplicerState.ePreAccel:
        bPreAccelCmd := TRUE;                      // 新卷预加速指令 / pre-acceleration command
        bCutCmd := FALSE;                          // 预加速相绝不裁切 / never cut while pre-accelerating
        bSyncOk := FALSE;                          // 预加速相尚无同步确认 / not yet confirmed
        bValid := TRUE;                            // 状态可用 / status usable
        bError := FALSE;                           // 本相无故障（超时已由段 8 处置）/ no fault here, timeout handled earlier
        eErr := 0;                      // 预加速相先清码 / clear the code first
        IF bNewRollReady THEN
            eState := E_DL_SplicerState.eSyncWait; // 新卷就绪进同步确认 / new roll ready enters the sync wait
        END_IF

    E_DL_SplicerState.eSyncWait:
        bPreAccelCmd := TRUE;                      // 预加速保持（同步需要维持速度）/ pre-acceleration held to keep the speed
        bCutCmd := FALSE;                          // 未确认绝不出裁切 / no cut before confirmation
        bValid := TRUE;                            // 状态可用 / status usable
        bError := FALSE;                           // 本相无故障 / no fault here
        IF bSyncOk THEN
            eErr := 0;                  // 已同步：无提示 / matched, no hint
            bCutCmd := TRUE;                       // 同步确认后才出裁切指令 / cut only after the match is confirmed
            eState := E_DL_SplicerState.eJointing; // 进裁切压合相 / enter cutting and joining
        ELSIF NOT bNewRollReady THEN
            // v1.0.1 补「进相前置消失」退出条件（R98 家族第二出口）：新卷预加速/就绪条件撤销时，
            // 本相已失去同步对象，继续滞留只会让 bPreAccelCmd 长期拉住空卷。退回 ePreAccel 相，
            // 由该相的 tPreAccelMax 超时闸兜住（仍保持「绝不裁切」——两相 bCutCmd 均为 FALSE）。
            eErr := DL_SPJ_CODE_INFO_2;            // 信息级：仍报同步未达 / info: still not matched
            eState := E_DL_SplicerState.ePreAccel; // 退回预加速相（前置消失退出条件）/ back to pre-acceleration, precondition gone
        ELSE
            eErr := DL_SPJ_CODE_INFO_2;            // 信息级：同步窗未达，裁切挂起（宁可等，不裁切）/ info: cut suspended
        END_IF

    E_DL_SplicerState.eJointing:
        bCutCmd := TRUE;                           // 裁切指令保持（接膜窗内）/ cut command held inside the joint window
        bPreAccelCmd := TRUE;                      // 预加速保持到接膜完成 / pre-acceleration held until the joint completes
        bValid := TRUE;                            // 状态可用 / status usable
        bError := FALSE;                           // 本相无故障 / no fault here
        eErr := 0;                      // 接膜相无错 / no error while joining
        IF fbTonJoint.Q THEN
            bCutCmd := FALSE;                      // 接膜窗到点撤裁切 / cut dropped when the window elapses
            bPreAccelCmd := FALSE;                 // 预加速撤 / pre-acceleration dropped
            bJointDone := TRUE;                    // 接膜完成单拍脉冲 / single-scan joint-done pulse
            IF uJointCount < DL_SPJ_CNT_MAX THEN
                uJointCount := uJointCount + 1;    // 接膜次数饱和自增 [次] / saturating joint increment
            END_IF
            eState := E_DL_SplicerState.eMonitor;  // 回监测相监测新卷余量 / back to monitoring the new roll
        END_IF

    E_DL_SplicerState.eFault:
        bPreAccelCmd := FALSE;                     // 故障闸撤预加速（R72）/ pre-acceleration dropped on the fault gate
        bCutCmd := FALSE;                          // 故障闸撤裁切（绝不裁切）/ cut dropped, never cut
        bSyncOk := FALSE;                          // 同步确认撤 / sync confirmation dropped
        bValid := FALSE;                           // 故障闸显式不可用 / explicit FALSE on the fault gate
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        IF eErr = 0 THEN
            eErr := DL_SPJ_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
        END_IF
        IF fbReset.Q THEN
            eState := E_DL_SplicerState.eIdle;     // 仅复位可退出故障相 / only reset leaves the fault state
        END_IF

    ELSE
        eState := E_DL_SplicerState.eFault;        // 非法状态兜底 / illegal-state fallback
        eErr := DL_SPJ_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 状态不可用 / status unusable
        bPreAccelCmd := FALSE;                     // 预加速指令撤 / pre-acceleration dropped
        bCutCmd := FALSE;                          // 裁切指令撤安全侧（绝不裁切）/ cut dropped, never cut
        bSyncOk := FALSE;                          // 同步确认撤 / sync confirmation dropped

END_CASE

(*------------------------------------------------------------------------------
 * 段 10｜停止闸（电平，最后判，覆盖各相输出）：中止并回待机，绝不裁切。
 *       放在 CASE 之后是为了让「停止」压过任何相内指令（安全侧优先级最高）
 *----------------------------------------------------------------------------*)
IF bStop THEN
    eState := E_DL_SplicerState.eIdle;             // 回待机 / back to idle
    bPreAccelCmd := FALSE;                         // 预加速撤 / pre-acceleration dropped
    bCutCmd := FALSE;                              // 裁切撤（中止不裁切）/ cut dropped, abort without cutting
    bSyncOk := FALSE;                              // 同步确认撤 / sync confirmation dropped
    bValid := FALSE;                               // 停止闸显式不可用（R72）/ explicit FALSE on the stop gate
    bJointDone := FALSE;                           // 停止不产生完成脉冲 / no done pulse on a stop
END_IF
END_FUNCTION_BLOCK
