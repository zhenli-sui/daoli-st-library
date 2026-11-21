(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ChamberSeasoningTrack
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 腔体 seasoning 台账与放行判定
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / LEN / LEFT / ABS / MIN / MAX / LIMIT），零厂商方言
 * 接口依赖 (Depends)    : E_DL_Ne107Status —— 唯一属主为 DL_Device 子库的契约件
 *                         I_DL_DeviceHealth（R13 泳道 A1）。本文件只引用成员，不重定义枚举体。
 * 功能描述 (Function)   : seasoning（腔体调机）片数 + 膜厚台账 + 放行判定。每片完成后累计
 *                         片数、累计工艺时长、膜厚均值与趋势；**双判据**（片数达标 **且** 时长
 *                         达标）才放行；连续越窗自动降级 eNotReady；配方名只作标签与校验键。
 * 边界     (Boundary)   : ① **不做配方存储** —— sRecipeName 只作为标签与校验键传入，配方本体
 *                         归 FB_DL_RecipeManager；② **不做膜厚测量** —— 膜厚与均匀性由量测机台
 *                         引脚注入；③ 不做 SPC 判异（只做越窗计数与连续计数）；④ 不做 MES 上报。
 * 分层声明 (Layer)      : 工艺层（DL_Process）。零全局变量表引用、零外部变量声明、零物理 IO。
 * 段序     (Segments)   : 段1 实例无条件刷新 → 段2 复位通道（CASE 前，R39）→ 段3 配方标签闸门
 *                         （R37 显式截断）与参数钳位 → 段4 单片完成受理（R24/R25/R44）→
 *                         段5 状态机 → 段6 码位单一优先级链 → 段7 出口钳位与保持重写。
 * 枚举映射表 (R31)      : eIdle(0)→标签 0｜eTracking(10)→标签 10｜eQualified(20)→标签 20｜
 *                         eNotReady(30)→标签 30｜eFault(99)→标签 99。每个成员有且仅有一个
 *                         显式标签，ELSE 只接脏值（02FB）。
 * 单拍标志清单 (R25)    : bWaferDone —— 预清零点：段1 每拍被实例输出覆盖；置位点：段1
 *                         `_bWaferReq := _fbTrigWafer.Q AND (NOT _bWaferConsumed)`；自清点：
 *                         段4 消费时置 `_bWaferConsumed := TRUE`，bWaferDone 回 FALSE 即解除。
 *                         bReset —— 预清零点：段1 覆盖 _bResetEdge；置位点：段1 实例调用；
 *                         自清点：紧随实例调用的 _bResetEdge 赋值行。
 * 保持位清单 (R27)      : bRelease 逐拍由 _bReleaseLatched 重写；eQualify 逐拍由 _eState 映射；
 *                         nCount / nNgCount / tAccum / fThickAvg / fThickSlope 逐拍由内部
 *                         台账量重写并夹域。复位沿清台账并递增轮次号。
 * 定时器清单 (R40)      : 无 TON/TOF 实例。工艺时长由引脚 tProcessTime 累加（台账语义），
 *                         不存在跨段恒真的定时输入；片数与时长的「达标」判据均为纯比较式。
 * 三元一致表 (R35)      : 片数目标守卫 1~10000 / 封顶 10000 / 判据 `>=`｜
 *                         连续越窗阈守卫 1~10 / 封顶 10 / 判据 `>=`｜
 *                         膜厚容差守卫 0.5~50 % / 封顶 50 / 判据 `>`（越窗）。
 * 镜像量清单 (R38)      : sRecipeName 的长度经 LEN 一次锁存为 _nNameLen，截断判定与登记
 *                         全部读该锁存量，绝不二次取长度；fThickness 与 fUniformity 在段4
 *                         单次锁存后参与全部判据。
 * 开源溯源 (Origin)     : 原创实现（参考 SEMI/半导体厂务公开的 seasoning 台账惯例，以及
 *                         ISA-88 公开的批次/相语义，T2-8 只借「批次台账 + 放行」的组织形态；
 *                         配方名仅作标签、台账只做累计与双判据）。ISA-88 为公开标准条款，
 *                         不声称「符合 ISA-88」；实现、码位、引脚契约 100% 本库独立设计，
 *                         clean-room 编写，未复制任何源码行。许可证说明：无代码借鉴对象，
 *                         本文件为本库原创，随本库许可证发布。
 * 验收向量 (Acceptance) :
 *   V1 25 片、每片 24 min、膜厚 100 ± 2 nm（目标 100、容差 5 %）→ tAccum = 10 h、
 *      eQualified、bRelease = TRUE。
 *   V2（双判据）25 片但每片 10 min（总 4.17 h < 10 h）→ 16#0005_01CD、仍 eTracking、
 *      bRelease = FALSE。
 *   V3（V-A 缺失键）sRecipeName = '' → 16#0005_02F9 锁存、bRelease 强制 FALSE
 *      （安全侧：台账不可信不得放行）。
 *   V4（V-B 串上限，R37）sRecipeName 传 40 字符（超 STRING(32)）→ 入口判 LEN 后置
 *      16#0005_01CE，按截断后的名字登记台账，**不得**依赖赋值隐式截断后静默使用。
 *   V5（V-D 复位首拍）bReset 后 nCount = 0、tAccum = T#0S、nRoundId + 1、bRelease = FALSE；
 *      **不得**保留上一轮 fThickSlope 的首片基准（R41：恢复不重头）。
 * 偏离留档 (Deviation)  :
 *   ① sRecipeName 引脚类型由 STRING(32) 提升为 STRING(80)：若按 STRING(32) 声明，超长截断
 *      会发生在**调用方赋值**那一行，本件永远看不到长度越限，01CE 成为死码 —— 这正是 R37
 *      要消灭的「静默截断」。提升到 STRING(80) 后由本件判 LEN、显式置码、按截断名登记，
 *      登记缓冲仍为 STRING(32)（_sRecipeTag），行为与规格 V4 一致。
 *   ② 工艺时长用 tProcessTime 累加而非墙钟：一台上位机可能同时跟踪多条腔体，墙钟会把
 *      「等待/待机」算进 seasoning 时长；引脚注入的工艺耗时才是台账口径。
 *   ③ 越窗判据取「膜厚相对偏差 > fThickTol 或 均匀性 > fUnifLimit」的**并集**：均匀性越限
 *      同样是「膜质未稳」的证据，只盯膜厚会漏掉「厚度对但均匀性崩」的片子。
 *   ④ 量测值非有限/越域并入 16#0005_02FA：规格故障表只给三个码，量测值不可信属于
 *      「台账数据源坏了」，与计数溢出同属「台账不可继续累加」的语义，故共用该码；
 *      不发生任何累加（本片不入账），也不会放行。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 C · DL_Process 第 25 件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SeasonState（归属 FB_DL_ChamberSeasoningTrack，同文件发布）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SeasonState :
(
    eIdle      := 0,    // 空闲：未使能或参数未就绪 / Idle, disabled or parameters not ready
    eTracking  := 10,   // 台账中：逐片累计，双判据未齐 / Tracking, accumulating wafers
    eQualified := 20,   // 已放行：片数与时长双达标 / Qualified, both criteria met
    eNotReady  := 30,   // 不具备放行条件：连续越窗降级 / Not ready, consecutive out-of-window wafers
    eFault     := 99    // 故障：配方键缺失或计数溢出 / Fault, missing recipe key or counter overflow
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ChamberSeasoningTrack
VAR_INPUT
    bEnable       : BOOL;                   // 使能（Enable），FALSE = 冻结台账与放行；复位通道不受其屏蔽 / Enable, FALSE freezes the ledger
    bReset        : BOOL;                   // 复位（Reset），上升沿清台账并重开新一轮 / Rising edge clears the ledger and opens a new round
    bWaferDone    : BOOL;                   // 单片完成（One-shot wafer done），上升沿受理（R24）/ One-shot wafer done, rising edge only
    fThickness    : REAL;                   // 本片膜厚（Wafer thickness）[nm]，域 0~10000 / Wafer thickness [nm], 0 to 10000
    fUniformity   : REAL;                   // 本片均匀性（Uniformity）[%]，域 0~100 / Uniformity [%], 0 to 100
    sRecipeName   : STRING(80);             // 配方名标签（Recipe tag），域非空，超 32 字符显式截断并置码（偏离留档①）/ Recipe tag, truncated explicitly
    fThickTarget  : REAL;                   // 膜厚目标（Thickness target）[nm]，域 >0 / Thickness target [nm], must be positive
    fThickTol     : REAL := 5.0;            // 膜厚相对容差（Thickness tolerance）[%]，域 0.5~50，默认 5.0 / Thickness tolerance [%]
    fUnifLimit    : REAL := 3.0;            // 均匀性上限（Uniformity limit）[%]，域 0.1~20，默认 3.0 / Uniformity limit [%]
    nCountTarget  : INT := 25;              // 片数目标（Wafer count target）[片]，域 1~10000，默认 25 / Wafer count target [pcs]
    tTimeTarget   : TIME := T#10H;          // 工艺时长目标（Process time target），域 1 min~1000 h，默认 10 h / Process time target
    nConsecNgLimit : INT := 2;              // 连续越窗降级阈值（Consecutive out-of-window limit）[片]，域 1~10，默认 2 / Consecutive limit [pcs]
    tProcessTime  : TIME;                   // 本片工艺耗时（Process time of this wafer），由上层引脚注入 / Process time injected by the caller
END_VAR

VAR_OUTPUT
    nCount        : INT;                    // 已 seasoning 片数（Seasoned wafer count）[片]，逐拍重写 / Seasoned wafer count [pcs]
    nNgCount      : INT;                    // 越窗片数（Out-of-window wafer count）[片]，逐拍重写 / Out-of-window wafer count [pcs]
    tAccum        : TIME;                   // 累计工艺时长（Accumulated process time），逐拍重写 / Accumulated process time
    fThickAvg     : REAL;                   // 膜厚均值（Mean thickness）[nm]，逐拍重写 / Mean thickness [nm]
    fThickSlope   : REAL;                   // 膜厚趋势（Thickness trend）[nm/片]，首末差除以片数差 / Thickness trend [nm/pc]
    bRelease      : BOOL;                   // 放行（Release），保持语义（R27）/ Release, held
    eQualify      : E_DL_SeasonState;       // 判定状态（Qualification state），逐拍重写 / Qualification state
    nRoundId      : UINT;                   // 本轮编号（Round id），复位递增，供 MES 对齐 / Round id, incremented on reset
    eHealth       : E_DL_Ne107Status;       // 健康态（NE107 health），引用属主 A1 的枚举 / NE107 health, owned by A1
    uDiagCode     : UDINT;                  // 诊断码（Diagnostic code），本拍单一优先级链输出 / Diagnostic code, single priority chain
    uErrorId      : UDINT;                  // 故障码（Error code），仅故障级码，0 = 无故障 / Fault-level code, 0 = no fault
    bError        : BOOL;                   // 故障标志（Error），仅故障级码置位 / TRUE only for fault-level codes
END_VAR

VAR
    _eState       : E_DL_SeasonState := E_DL_SeasonState.eIdle;    // 内部状态（Internal state）/ Internal state value
    _bWaferReq    : BOOL;                   // 单片完成单拍请求（Wafer done request）/ Wafer done one-shot request
    _bWaferConsumed : BOOL;                 // 单片完成已消费（Wafer consumed flag）/ Wafer consumed flag
    _bResetEdge   : BOOL;                   // 复位沿单拍标志（Reset one-shot flag）/ Reset one-shot flag
    _uFaultCode   : UDINT;                  // 本拍故障级码（Fault-level code this scan）/ Fault-level code of this scan
    _uFaultLatched : UDINT;                 // 故障码锁存（Latched fault code），仅复位清除 / Latched fault code, reset only
    _uInfoCode    : UDINT;                  // 本拍信息级码（Info-level code this scan）/ Info-level code of this scan
    _bFaultCond   : BOOL;                   // 故障条件（Fault condition）/ Fault condition flag
    _sRecipeTag   : STRING(32);             // 台账登记的配方标签（Registered recipe tag），截断后 32 字符 / Recipe tag after truncation
    _nNameLen     : INT;                    // 配方名长度（Recipe name length）[字符]，一次锁存（R38）/ Recipe name length, latched once
    _bTruncFlag   : BOOL;                   // 截断发生标志（Truncation flag），R37 显式置位 / Truncation flag, set explicitly (R37)
    _bKeyOk       : BOOL;                   // 配方键与目标合法（Key and target valid）/ Key and target valid
    _fThickSnap   : REAL;                   // 膜厚快照（Thickness snapshot）[nm]，单次锁存 / Thickness snapshot [nm]
    _fUnifSnap    : REAL;                   // 均匀性快照（Uniformity snapshot）[%]，单次锁存 / Uniformity snapshot [%]
    _fTolEff      : REAL;                   // 生效膜厚容差（Effective thickness tolerance）[%] / Effective thickness tolerance [%]
    _fUnifLimEff  : REAL;                   // 生效均匀性上限（Effective uniformity limit）[%] / Effective uniformity limit [%]
    _nCountTgtEff : INT;                    // 生效片数目标（Effective count target）[片] / Effective count target [pcs]
    _nConsecEff   : INT;                    // 生效连续越窗阈（Effective consecutive limit）[片] / Effective consecutive limit [pcs]
    _tTimeTgtEff  : TIME;                   // 生效时长目标（Effective time target）/ Effective time target
    _nCountInt    : INT;                    // 内部片数台账（Internal wafer count）[片] / Internal wafer count [pcs]
    _nNgInt       : INT;                    // 内部越窗片数（Internal out-of-window count）[片] / Internal out-of-window count [pcs]
    _nConsecNg    : INT;                    // 当前连续越窗片数（Current consecutive out-of-window count）[片] / Current consecutive count [pcs]
    _tAccumInt    : TIME;                   // 内部累计时长（Internal accumulated time）/ Internal accumulated time
    _fThickSum    : REAL;                   // 膜厚累加（Thickness sum）[nm] / Thickness sum [nm]
    _fThickFirst  : REAL;                   // 首片膜厚（First wafer thickness）[nm]，趋势基准 / First wafer thickness [nm]
    _fThickLast   : REAL;                   // 末片膜厚（Last wafer thickness）[nm] / Last wafer thickness [nm]
    _bFirstSet    : BOOL;                   // 首片基准已装（First sample recorded）/ First sample recorded flag
    _fDevPct      : REAL;                   // 膜厚相对偏差（Relative thickness deviation）[%] / Relative thickness deviation [%]
    _bOutWin      : BOOL;                   // 本片越窗（Out of window this wafer）/ Out of window this wafer
    _bReleaseLatched : BOOL;                // 放行锁存（Release latch），复位清除 / Release latch, reset only
    _nRoundIdInt  : UINT;                   // 内部轮次号（Internal round id），复位递增 / Internal round id, incremented on reset
    _bCountOk     : BOOL;                   // 片数达标（Count criterion met）/ Count criterion met
    _bTimeOk      : BOOL;                   // 时长达标（Time criterion met）/ Time criterion met
    _fbTrigWafer  : R_TRIG;                 // 单片完成上升沿（Wafer done rising edge）/ Wafer done rising edge
    _fbTrigReset  : R_TRIG;                 // 复位上升沿（Reset rising edge）/ Reset rising edge
END_VAR

VAR CONSTANT
    DL_SEA_NAME_MAX   : INT  := 32;          // 配方标签登记宽度（Registered tag width）[字符]，与 STRING(32) 一致 / Registered tag width
    DL_SEA_REAL_MAX   : REAL := 3.4E38;      // 单精度有限值判据幅值（Finite magnitude bound）/ Finite bound for REAL inputs
    DL_SEA_EPS        : REAL := 1.0E-6;      // 浮点防零容差（Divide-guard epsilon）/ Float divide-guard epsilon
    DL_SEA_THICK_MAX  : REAL := 10000.0;     // 膜厚输入域上限（Thickness input bound）[nm] / Thickness input bound [nm]
    DL_SEA_UNIF_MAX   : REAL := 100.0;       // 均匀性输入域上限（Uniformity input bound）[%] / Uniformity input bound [%]
    DL_SEA_TOL_LO     : REAL := 0.5;         // 膜厚容差下限（Tolerance lower clamp）[%] / Tolerance lower clamp [%]
    DL_SEA_TOL_HI     : REAL := 50.0;        // 膜厚容差上限（Tolerance upper clamp）[%] / Tolerance upper clamp [%]
    DL_SEA_UNIFL_LO   : REAL := 0.1;         // 均匀性上限下限（Uniformity limit lower clamp）[%] / Uniformity lower clamp [%]
    DL_SEA_UNIFL_HI   : REAL := 20.0;        // 均匀性上限上限（Uniformity limit upper clamp）[%] / Uniformity upper clamp [%]
    DL_SEA_CNT_LO     : INT  := 1;           // 片数目标下限（Count target lower clamp）[片] / Count target lower clamp [pcs]
    DL_SEA_CNT_HI     : INT  := 10000;       // 片数目标上限（Count target upper clamp）[片] / Count target upper clamp [pcs]
    DL_SEA_CONS_LO    : INT  := 1;           // 连续阈下限（Consecutive limit lower clamp）[片] / Consecutive limit lower clamp [pcs]
    DL_SEA_CONS_HI    : INT  := 10;                 // 连续阈上限（Consecutive limit upper clamp）[片] / Consecutive limit upper clamp [pcs]
    DL_SEA_CNT_OVF    : INT  := 30000;       // 片数台账溢出阈（Count overflow threshold）[片] / Count overflow threshold [pcs]
    DL_SEA_TIME_OVF   : TIME := T#40D;       // 时长台账溢出阈（Time overflow threshold）[ms] / Time overflow threshold
    DL_SEA_TIME_MIN   : TIME := T#1M;        // 时长目标下限（Time target lower clamp）/ Time target lower clamp
    DL_SEA_TIME_MAX   : TIME := T#1000H;     // 时长目标上限（Time target upper clamp）/ Time target upper clamp
    DL_SEA_PCT        : REAL := 100.0;       // 百分比换算（Percent scale）[-] / Percent scale
    DL_SEA_ERR_KEY    : UDINT := 16#0005_02F9; // 0005_02F9 配方名为空或膜厚目标非正【故障级】/ Missing recipe or target, fault level
    DL_SEA_ERR_OVF    : UDINT := 16#0005_02FA; // 0005_02FA 片数或时长台账溢出【故障级】/ Counter overflow, fault level
    DL_SEA_ERR_STATE  : UDINT := 16#0005_02FB; // 0005_02FB 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_SEA_INFO_SINGLE : UDINT := 16#0005_01CB; // 0005_01CB 单片越窗但未连续【信息级】/ Single out-of-window wafer, info level
    DL_SEA_INFO_CONS  : UDINT := 16#0005_01CC; // 0005_01CC 连续越窗达阈值降级【信息级】/ Consecutive limit reached, info level
    DL_SEA_INFO_TIME  : UDINT := 16#0005_01CD; // 0005_01CD 片数达标但时长未达标【信息级】/ Count reached, time pending, info level
    DL_SEA_INFO_TRUNC : UDINT := 16#0005_01CE; // 0005_01CE 配方名超 32 字符已显式截断【信息级】/ Recipe tag truncated explicitly, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of every instance (R7/0.5)
// ============================================================================
_fbTrigWafer(CLK := bWaferDone);                // 单片完成上升沿（Wafer done rising edge）
_bWaferReq := _fbTrigWafer.Q AND (NOT _bWaferConsumed);    // 单拍请求（R25 置位点）
_fbTrigReset(CLK := bReset);                    // 复位上升沿（Reset rising edge）
_bResetEdge := _fbTrigReset.Q;                  // 复位单拍标志紧随实例赋值（R25 自清点）

// 本拍码与条件预置（每拍重算；故障码以上拍锁存续用）
// Per-scan preset of codes and conditions, the fault code is carried from the latch
_uFaultCode := _uFaultLatched;                  // 故障码续用（Carry the latched fault code）
_uInfoCode  := 16#0000_0000;                    // 信息级码预清零（Info code preset to zero）
_bFaultCond := FALSE;                           // 故障条件预清零（Fault condition preset FALSE）
_bKeyOk     := FALSE;                           // 配方键闸门预置未通过（Key gate preset closed）
_bOutWin    := FALSE;                           // 越窗标志预置假（Out-of-window preset FALSE）

// 单片完成消费标志解除：输入回落即允许下一片（R25 生命周期闭环）
// Release the wafer consumption flag once the input falls
IF NOT bWaferDone THEN
    _bWaferConsumed := FALSE;                   // 允许下一次上升沿（Next rising edge accepted）
END_IF

// ============================================================================
// 段 2｜复位通道（R39：置于 CASE 之前，且不被掉使能分支屏蔽）
//      Reset path, before CASE and never masked by the disable branch
// ============================================================================
IF _bResetEdge THEN
    _nCountInt    := 0;                         // 片数台账清零（Wafer count cleared）
    _nNgInt       := 0;                         // 越窗片数清零（Out-of-window count cleared）
    _nConsecNg    := 0;                         // 连续越窗计数清零（Consecutive count cleared）
    _tAccumInt    := T#0S;                      // 累计时长清零（Accumulated time cleared）
    _fThickSum    := 0.0;                       // 膜厚累加清零（Thickness sum cleared）
    _fThickFirst  := 0.0;                       // 首片基准清除（First-sample basis cleared）
    _fThickLast   := 0.0;                       // 末片值清除（Last-sample value cleared）
    _bFirstSet    := FALSE;                     // 首片基准标志清除（First-sample flag cleared，R41）
    _bReleaseLatched := FALSE;                  // 放行锁存清除（Release latch cleared）
    _bTruncFlag   := FALSE;                     // 截断标志清除（Truncation flag cleared）
    _nRoundIdInt  := _nRoundIdInt + UINT#1;     // 轮次递增进位（Round id incremented）
    _uFaultLatched := 16#0000_0000;             // 故障码锁存清除（Latched fault code cleared）
    _uFaultCode   := 16#0000_0000;              // 本拍故障码清空，防止段6 重新锁存旧码（Clear this scan code）
    IF _eState = E_DL_SeasonState.eFault THEN
        _eState := E_DL_SeasonState.eIdle;      // 故障态回空闲（Fault state back to idle）
        _bFaultCond := FALSE;                   // 故障条件清除（Fault condition cleared）
    ELSIF _eState = E_DL_SeasonState.eQualified THEN
        _eState := E_DL_SeasonState.eTracking;  // 已放行轮次复位后重开台账（New round after a qualified round）
    ELSIF _eState = E_DL_SeasonState.eNotReady THEN
        _eState := E_DL_SeasonState.eTracking;  // 降级轮次复位后重开台账（New round after a degraded round）
    END_IF
END_IF

// ============================================================================
// 段 3｜配方标签闸门（R37：先判长度、显式置码、按截断名登记）与参数钳位
//      Recipe tag gate: length first, explicit code, then register the truncated tag
// ============================================================================
_nNameLen := LEN(sRecipeName);                  // 长度一次锁存（R38：此后全部判据读该值）
IF _nNameLen > DL_SEA_NAME_MAX THEN
    _sRecipeTag := LEFT(sRecipeName, DL_SEA_NAME_MAX);   // 按宽度取前缀后写回登记缓冲（预判后写，非回夹）
    _bTruncFlag := TRUE;                        // 截断标志显式置位（R37 核心：不静默）
    _uInfoCode  := DL_SEA_INFO_TRUNC;           // 0005_01CE 配方名超长已截断【信息级】/ Recipe tag truncated
ELSE
    _sRecipeTag := sRecipeName;                 // 未超长按原名登记（Register the tag as-is）
END_IF

IF _nNameLen = 0 THEN
    _bFaultCond := TRUE;                        // 配方键缺失（Missing recipe key）
    _uFaultCode := DL_SEA_ERR_KEY;              // 0005_02F9 配方名为空【故障级】/ Missing recipe, fault level
ELSIF (NOT (fThickTarget >= DL_SEA_EPS)) OR (fThickTarget > DL_SEA_THICK_MAX) THEN
    _bFaultCond := TRUE;                        // 膜厚目标非正或越域（Target not positive or out of domain）
    _uFaultCode := DL_SEA_ERR_KEY;              // 0005_02F9 膜厚目标非法【故障级】/ Illegal target, fault level
ELSE
    _bKeyOk := TRUE;                            // 键与目标合法（Key and target valid）
END_IF

// 参数域钳位（R35：守卫、封顶与判据同向）
// Parameter clamping so that guard, ceiling and comparison stay in step (R35)
_fTolEff      := LIMIT(DL_SEA_TOL_LO, fThickTol, DL_SEA_TOL_HI);            // 膜厚容差 0.5~50 %（Tolerance clamped）
_fUnifLimEff  := LIMIT(DL_SEA_UNIFL_LO, fUnifLimit, DL_SEA_UNIFL_HI);       // 均匀性上限 0.1~20 %（Uniformity limit clamped）
_nCountTgtEff := LIMIT(DL_SEA_CNT_LO, nCountTarget, DL_SEA_CNT_HI);         // 片数目标 1~10000（Count target clamped）
_nConsecEff   := LIMIT(DL_SEA_CONS_LO, nConsecNgLimit, DL_SEA_CONS_HI);     // 连续阈 1~10（Consecutive limit clamped）
_tTimeTgtEff := tTimeTarget;                    // 时长目标取引脚值（Time target taken from the pin）
IF _tTimeTgtEff < DL_SEA_TIME_MIN THEN
    _tTimeTgtEff := DL_SEA_TIME_MIN;            // 时长目标下限钳位（Time target lower clamp）
ELSIF _tTimeTgtEff > DL_SEA_TIME_MAX THEN
    _tTimeTgtEff := DL_SEA_TIME_MAX;            // 时长目标上限钳位（Time target upper clamp）
END_IF

// ============================================================================
// 段 4｜单片完成受理（R24/R25；R44 清码点绑定新片起点）
//      Wafer completion acceptance, info codes cleared at each wafer start (R44)
// ============================================================================
IF _bWaferReq AND (NOT _bWaferConsumed) AND (_eState = E_DL_SeasonState.eTracking) AND _bKeyOk THEN
    _bWaferConsumed := TRUE;                    // 消费单片沿（Wafer edge consumed）
    _uInfoCode      := 16#0000_0000;            // 新片起点清信息码（R44：清码点绑定新片起点）
    _fThickSnap     := fThickness;              // 膜厚快照（Thickness snapshot）
    _fUnifSnap      := fUniformity;             // 均匀性快照（Uniformity snapshot）

    IF (NOT (_fThickSnap >= 0.0 AND _fThickSnap <= DL_SEA_THICK_MAX))
    OR (NOT (_fUnifSnap >= 0.0 AND _fUnifSnap <= DL_SEA_UNIF_MAX)) THEN
        _bFaultCond := TRUE;                    // 量测值非有限或越域（Non-finite or out-of-domain measurement）
        _uFaultCode := DL_SEA_ERR_OVF;          // 0005_02FA 量测值非法并入溢出码【故障级】/ Illegal measurement folded in
    ELSE
        _nCountInt := _nCountInt + 1;           // 片数 +1（Wafer counted）
        _fThickSum := _fThickSum + _fThickSnap; // 膜厚累加（Thickness accumulated）
        _fThickLast := _fThickSnap;             // 末片膜厚（Last wafer thickness）
        IF NOT _bFirstSet THEN
            _fThickFirst := _fThickSnap;        // 首片基准只在首片装一次（First-sample basis once）
            _bFirstSet   := TRUE;               // 基准已装（Basis recorded）
        END_IF
        _tAccumInt := _tAccumInt + tProcessTime;    // 累计工艺时长（Process time accumulated）

        // 越窗判据：膜厚相对偏差 或 均匀性越限（偏离留档③）
        //     Out-of-window when the thickness deviation or the uniformity exceeds its limit
        _fDevPct := ABS(_fThickSnap - fThickTarget) / fThickTarget * DL_SEA_PCT;    // 相对偏差（Relative deviation）
        IF (_fDevPct > _fTolEff) OR (_fUnifSnap > _fUnifLimEff) THEN
            _bOutWin := TRUE;                   // 本片越窗（Out of window）
        END_IF

        IF _bOutWin THEN
            _nNgInt    := _nNgInt + 1;          // 越窗片数 +1（Out-of-window counted）
            _nConsecNg := _nConsecNg + 1;       // 连续越窗 +1（Consecutive count increments）
            IF _nConsecNg >= _nConsecEff THEN
                _uInfoCode := DL_SEA_INFO_CONS; // 0005_01CC 连续越窗达阈值降级【信息级】/ Consecutive limit reached
            ELSE
                _uInfoCode := DL_SEA_INFO_SINGLE;   // 0005_01CB 单片越窗但未连续【信息级】/ Single out-of-window wafer
            END_IF
        ELSE
            _nConsecNg := 0;                    // 未越窗则连续计数清零（Consecutive count resets）
        END_IF

        // 台账溢出守卫（R35：守卫 30000 片 / 40 天，判据 >=）
        //     Ledger overflow guard
        IF (_nCountInt >= DL_SEA_CNT_OVF) OR (_tAccumInt >= DL_SEA_TIME_OVF) THEN
            _bFaultCond := TRUE;                // 台账溢出（Ledger overflow）
            _uFaultCode := DL_SEA_ERR_OVF;      // 0005_02FA 台账溢出【故障级】/ Ledger overflow, fault level
        END_IF
    END_IF
END_IF

// 双判据（片数达标 且 时长达标）：片数达标而时长未达标时只给信息码，不放行
// Dual criteria: the count alone never releases the chamber
_bCountOk := _nCountInt >= _nCountTgtEff;       // 片数判据（Count criterion）
_bTimeOk  := _tAccumInt >= _tTimeTgtEff;        // 时长判据（Time criterion）
IF _bCountOk AND (NOT _bTimeOk) THEN
    _uInfoCode := DL_SEA_INFO_TIME;             // 0005_01CD 片数达标但时长未达标【信息级】/ Count reached, time pending
END_IF

// ============================================================================
// 段 5｜状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      State machine with an explicit ELSE fallback
// ============================================================================
IF _bFaultCond THEN
    _bReleaseLatched := FALSE;                  // 安全侧：台账不可信时强制撤销放行（Safety: release revoked on any fault）
    _eState := E_DL_SeasonState.eFault;         // 故障条件优先于状态机（Fault outranks the machine）
END_IF

// 掉使能冻结分支：显式排除故障态（R39 合法写法①），复位通道仍可从故障态退出
// Disable branch explicitly excludes the fault state so the reset path still works
IF (NOT bEnable) AND (_eState <> E_DL_SeasonState.eFault) THEN
    _eState := E_DL_SeasonState.eIdle;          // 冻结回空闲（Freeze back to idle）
END_IF

CASE _eState OF

    E_DL_SeasonState.eIdle: // 空闲：等键与目标就绪
        IF bEnable AND _bKeyOk AND (NOT _bFaultCond) THEN
            _eState := E_DL_SeasonState.eTracking;  // 门票就绪进台账（Enter tracking）
        END_IF

    E_DL_SeasonState.eTracking: // 台账中：双判据 / 连续越窗降级
        IF _bCountOk AND _bTimeOk THEN
            _bReleaseLatched := TRUE;           // 双判据齐：放行（Releases the chamber）
            _eState := E_DL_SeasonState.eQualified; // 进已放行（Enter qualified）
        ELSIF _nConsecNg >= _nConsecEff THEN
            _bReleaseLatched := FALSE;          // 降级：撤销放行（Degraded, release revoked）
            _eState := E_DL_SeasonState.eNotReady;  // 进不具备放行条件（Enter not ready）
        END_IF

    E_DL_SeasonState.eQualified: // 已放行：结论逐拍在段7 重写（R27），本分支只保留标签
        // 结论保持由段7 逐拍重写承担，此处保留空标签与原因注释（R31）
        // The held verdict is rewritten in segment 7, so this label stays empty (R31)

    E_DL_SeasonState.eNotReady: // 不具备放行条件：等复位重开一轮
        // 复位通道位于 CASE 之前（段2），此处保留空标签与原因注释（R31/R41）
        // Reset happens in segment 2, so this label stays empty (R31/R41)

    E_DL_SeasonState.eFault: // 故障：等复位沿（段2）
        // 复位通道位于 CASE 之前，此分支无需动作（R39）
        // The reset path sits before CASE, so no action is needed here (R39)

    ELSE // 兜底：非法状态
        _uFaultCode := DL_SEA_ERR_STATE;        // 0005_02FB 非法状态兜底【故障级】/ Illegal state fallback
        _bFaultCond := TRUE;                    // 置故障条件（Raise the fault condition）
        _eState     := E_DL_SeasonState.eFault; // 强制回故障态（Force the fault state）
END_CASE

// ============================================================================
// 段 6｜码位单一优先级链（全拍只写一次，信息级不置 bError）
//      Single priority chain for the codes, written once per scan
// ============================================================================
IF _uFaultCode <> 16#0000_0000 THEN
    _uFaultLatched := _uFaultCode;              // 故障码锁存（Latched until reset）
    uErrorId  := _uFaultCode;                   // 故障级码优先（Fault-level code wins）
    uDiagCode := _uFaultCode;                   // 诊断码同源（Diagnostic code mirrors the fault）
    bError    := TRUE;                          // 故障标志置位（Error flag raised）
ELSIF _uInfoCode <> 16#0000_0000 THEN
    uErrorId  := 16#0000_0000;                  // 信息级不占故障码（Info level leaves the fault code empty）
    uDiagCode := _uInfoCode;                    // 诊断码取信息级码（Diagnostic code takes the info code）
    bError    := FALSE;                         // 信息级不置故障位（Info level never raises the error flag）
ELSE
    uErrorId  := 16#0000_0000;                  // 无码（No code）
    uDiagCode := 16#0000_0000;                  // 无码（No code）
    bError    := FALSE;                         // 无故障（No error）
END_IF

// ============================================================================
// 段 7｜出口钳位与保持语义重写（R27/R43；台账量逐拍重写，绝不靠进入那一拍）
//      Output clamping and held-semantics rewrite (R27/R43)
// ============================================================================
nCount    := LIMIT(0, _nCountInt, DL_SEA_CNT_OVF);      // 片数夹进 0~30000（Count clamped）
nNgCount  := LIMIT(0, _nNgInt, DL_SEA_CNT_OVF);         // 越窗片数夹进 0~30000（Out-of-window clamped）
tAccum    := _tAccumInt;                                // 累计时长逐拍重写（Accumulated time rewritten）
IF _nCountInt > 0 THEN
    fThickAvg := _fThickSum / INT_TO_REAL(_nCountInt);  // 膜厚均值（Mean thickness），除零已由计数守卫
ELSE
    fThickAvg := 0.0;                                   // 无片时均值 0（Zero mean without wafers）
END_IF
IF (_nCountInt >= 2) AND _bFirstSet THEN
    fThickSlope := (_fThickLast - _fThickFirst) / INT_TO_REAL(_nCountInt - 1);  // 首末差/片数差（Trend per wafer）
ELSE
    fThickSlope := 0.0;                                 // 单片或未装基准时趋势 0（Zero trend before a basis exists）
END_IF
bRelease  := _bReleaseLatched;                          // 放行逐拍重写（Release rewritten every scan）
eQualify  := _eState;                                   // 判定状态逐拍重写（Qualification state rewritten）
nRoundId  := _nRoundIdInt;                              // 轮次号逐拍重写（Round id rewritten every scan）

// 健康态仲裁（引用属主 A1 的四态语言）
// Health arbitration mapped onto the A1 health language
IF _eState = E_DL_SeasonState.eFault THEN
    eHealth := E_DL_Ne107Status.eFailure;       // 故障：台账不可信（Failure）
ELSIF NOT bEnable THEN
    eHealth := E_DL_Ne107Status.eUnknown;       // 未知：未使能（Unknown）
ELSIF _eState = E_DL_SeasonState.eNotReady THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq;    // 需维护：连续越窗，需重新调机（Maintenance required）
ELSIF _bTruncFlag THEN
    eHealth := E_DL_Ne107Status.eOutOfSpec;     // 越规：配方键被截断，台账对齐风险（Out of spec）
ELSIF _eState = E_DL_SeasonState.eQualified THEN
    eHealth := E_DL_Ne107Status.eOk;            // 正常：已放行（OK, released）
ELSE
    eHealth := E_DL_Ne107Status.eOk;            // 正常：台账进行中（OK, tracking）
END_IF

END_FUNCTION_BLOCK
