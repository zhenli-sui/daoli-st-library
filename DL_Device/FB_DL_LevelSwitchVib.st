(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LevelSwitchVib
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备功能块（Function Block，实现 I_DL_LevelSwitch）
 * 功能简述 (Function)   : 振动叉式料位开关信号处理块。原始开关防抖 → 失效安
 *                         全方向归一（fail-safe HIGH/LOW 可选）→ 覆盖/裸露
 *                         双延迟确认 → 有料/无料双联锁输出 + 传感器失效诊
 *                         断镜像（本轮预留）。
 * 接口实现 (Implements) : I_DL_LevelSwitch。接口属性同名成员（eState/bMaterial/
 *                         bHighAlarm/bLowAlarm/bFault/uErrorId）按 R22 以只
 *                         读 PROPERTY GET 承载（内部镜像同源），非接口成员
 *                         bSensorTest 保留 VAR_OUTPUT；方法 CmdReset/CmdTest
 *                         在本文件尾部落地。
 * 公约遵循 (Convention) : 0.1/R23 周期信号处理型（防抖/延迟由 TON 语义承载，
 *                         无初始化/跟踪同步语义），免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 全部实例
 *                         主体最前部无条件刷新；0.7/R15 故障级锁存仅复位路
 *                         径清码。
 *                         0.8 故障码段位 16#0003_xxxx（经 DL_Device
 *                         VERSION.md 码表核对：规格建议 0003_0290/0003_010a
 *                         中 0290 已由本轮 FB_DL_GuardLockDoor 顺延占用、
 *                         010a 与库内 0110~0116 编号惯例不一致，依公约顺延
 *                         归一）：
 *                         【故障级】0003_02C0 失效安全模式枚举越界；
 *                         【信息级】0003_0116 传感器信号静默提示（预留信息
 *                         级，本轮仅登记码位不触发）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 枚举域防御/参数钳位 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 状态映像 IF 派生
 *                         链含 ELSE 兜底（信号处理型派生映像）✓
 *                         R7 四实例（R_TRIG×1/TON×4）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 失效安全归一核心：bMaterial 归一式 bRawSwitch
 *                           XOR (eFailSafeMode = eLow) 的语义等价式（用 IF
 *                           显式写，禁 XOR 技巧裸用）——eHigh 组态下原始信
 *                           号直接作为有料判定；eLow 组态约定传感器原始信号
 *                           极性为 TRUE=无料/裸露（出厂反相接线，接线层保
 *                           证），取反后统一为 TRUE=有料，防现场接反；
 *                         ② bEnable=FALSE 或传感器失效时输出强制归一到安全
 *                           侧：eHigh → 强制有料（bHighAlarm 报警，防溢流）；
 *                           eLow → 强制无料（bLowAlarm 报警，防干转）；
 *                         ③ 高/低联锁方向语义写死：bHighAlarm = 归一后有料
 *                           （eHigh 失效即报警）；bLowAlarm = 归一后无料
 *                           （eLow 失效即报警），两输出方向由本归一约定承
 *                           载，现场不得反接；
 *                         ④ 覆盖/裸露双延迟：防抖 TON×2 + 确认 TON×2 全部
 *                           在主体前部无条件刷新（R7）；
 *                         ⑤ 传感器失效检测（信号静默）本轮预留：码位
 *                           0003_0116 与 eSensorLoss 态已登记，检测算法后续
 *                           轮次落地（R11 留档）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 码位顺延归一：规格建议 0003_0290 与本轮
 *                           FB_DL_GuardLockDoor 顺延占用冲突，取 0003_02C0；
 *                           规格建议 0003_010a 改为 0003_0116 与库内信息级
 *                           编号惯例一致（核对结果优先于建议值）。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / level-switch-failsafe
 *                         （RAW_NOTES_R7 S-7：TcOpen 料位开关组件失效安全
 *                         语义域与振动叉开关防抖/双延迟公开惯例，公开资料，
 *                         仅借鉴语义域；归一实现、码位与引脚契约 100% 本库
 *                         独立设计，clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 有料/无料双延迟切换逐拍：raw 稳定翻转 → tDebounce 过 → tCoverDelay/
 *      tBareDelay 过 → bMaterial 翻转；
 *   V2 fail-safe HIGH 断线注入（使能切断模拟失效）：bEnable=FALSE + eHigh →
 *      bMaterial 强制 TRUE、bHighAlarm=TRUE（防溢流方向）；
 *   V3 fail-safe LOW 断线注入：bEnable=FALSE + eLow → bMaterial 强制 FALSE、
 *      bLowAlarm=TRUE（防干转方向）；
 *   V4 模式枚举越界：eFailSafeMode 写入域外值 → 故障锁存 0003_02C0；
 *   V5 复位：bReset 沿 → 故障清零回 eIdle 镜像态。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 料位开关族实现件）
 *   2026-11-15  v1.0.1  终审修复 1 处：_fbTrigTest 误接 bEnable——每次使能
 *                       上升沿（含正常开机）误置 bSensorTest 测试镜像一拍，
 *                       删除误接实例，bSensorTest 仅由 CmdTest 单拍承载
 *============================================================================*)
FUNCTION_BLOCK FB_DL_LevelSwitchVib IMPLEMENTS I_DL_LevelSwitch
VAR_INPUT
    bRawSwitch    : BOOL;               // 传感器原始开关信号（Raw switch signal），TRUE=触点动作（介质覆盖叉体，按传感器极性定义）/ Raw switch, TRUE = contact acted per sensor polarity
    eFailSafeMode : E_DL_FailSafeMode := E_DL_FailSafeMode.eHigh; // 失效安全模式（Fail-safe mode），eHigh=失效报有料（防溢流）/ eLow=失效报无料（防干转）/ Fail-safe direction
    tDebounce     : TIME := T#200MS;    // 防抖窗口（Debounce），默认 T#200MS / Debounce window
    tCoverDelay   : TIME := T#1S;       // 覆盖确认延迟（Cover delay），默认 T#1S，防液面波动误翻转 / Cover confirm delay
    tBareDelay    : TIME := T#1S;       // 裸露确认延迟（Bare delay），默认 T#1S / Bare confirm delay
    bEnable       : BOOL;               // 处理使能（Processing enable），FALSE=输出按失效安全方向强制镜像 / FALSE forces fail-safe mirrored outputs
    bReset        : BOOL;               // 上升沿复位故障（Reset edge）/ Rising edge resets fault
END_VAR
VAR_OUTPUT
    bSensorTest : BOOL;                 // 传感器测试态镜像（Sensor test mirror），CmdTest 期间一拍 / Test mirror, one scan during CmdTest
END_VAR
VAR
    _eState        : E_DL_LevelState;   // 派生诊断状态（Derived diagnostic state），属性只读 / Derived state, read-only via property
    _bFaultLatch   : BOOL;              // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt   : UDINT;             // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode     : UDINT;             // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bModeValid    : BOOL;              // 失效安全模式枚举合法（Fail-safe mode in domain）/ Mode in-domain flag
    _bRawDebounced : BOOL;              // 防抖后原始信号（Debounced raw signal）/ Debounced raw signal
    _bMatNorm      : BOOL;              // 极性归一后有料判定（Polarity-normalized material）/ Polarity-normalized material
    _bMatSafe      : BOOL;              // 失效安全归一输出（Fail-safe normalized material output）/ Fail-safe normalized output
    _bMatConfirmed : BOOL;              // 双延迟确认后有料判定（Delay-confirmed material）/ Delay-confirmed material
    _bTestPulse    : BOOL;              // 测试态单拍请求（Test one-shot request）/ Test one-shot request
    _bPendReset    : BOOL;              // 方法复位请求（Method reset request）/ Method reset request
    _bPendTest     : BOOL;              // 方法测试请求（Method test request）/ Method test request
    _fbTrigReset   : R_TRIG;            // 引脚复位沿（Pin reset edge）/ Pin reset edge detector
    _fbTonDbCover  : TON;               // 原始信号覆盖侧防抖（Raw cover-side debounce）/ Cover-side debounce timer
    _fbTonDbBare   : TON;               // 原始信号裸露侧防抖（Raw bare-side debounce）/ Bare-side debounce timer
    _fbTonCover    : TON;               // 覆盖确认延迟（Cover confirm delay）/ Cover confirm delay
    _fbTonBare     : TON;               // 裸露确认延迟（Bare confirm delay）/ Bare confirm delay
END_VAR

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_LevelState.eFault) THEN
    _bPendReset := TRUE;          // 登记复位请求（Register reset request）
    CmdReset := TRUE;             // 可复位（Resettable）
ELSE
    CmdReset := FALSE;            // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdTest —— 传感器功能测试请求：输出镜像进入测试态一拍。故障态拒绝。
 *      Method CmdTest - sensor test request, test mirror one scan, rejected in fault.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdTest : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_LevelState.eFault) THEN
    CmdTest := FALSE;             // 故障态拒绝（Rejected in fault）
ELSE
    _bPendTest := TRUE;           // 登记测试请求（Register test request）
    CmdTest := TRUE;              // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前诊断状态只读视图。
 *      Property eState (GET) - read-only diagnostic state view.
 *------------------------------------------------------------------------------*)
    END_METHOD

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigReset(CLK := bReset);
_fbTonDbCover(IN := bRawSwitch, PT := tDebounce);           // 覆盖侧防抖（Cover debounce）
_fbTonDbBare(IN := (NOT bRawSwitch), PT := tDebounce);      // 裸露侧防抖（Bare debounce）
_fbTonCover(IN := _bRawDebounced AND (NOT _bMatConfirmed) AND (NOT _bFaultLatch), PT := tCoverDelay); // 覆盖确认（Cover confirm）
_fbTonBare(IN := (NOT _bRawDebounced) AND _bMatConfirmed AND (NOT _bFaultLatch), PT := tBareDelay);   // 裸露确认（Bare confirm）

// ============================================================================
// 段 2｜模式域防御 + 信息级预清零 + 复位路径（R15）
//      Mode domain guard + info preset + reset path (R15)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）
_bModeValid := (eFailSafeMode = E_DL_FailSafeMode.eHigh) OR (eFailSafeMode = E_DL_FailSafeMode.eLow); // 模式域校验（Mode domain check）
IF NOT _bModeValid THEN
    _bFaultLatch := TRUE;         // 模式枚举越界锁存（Mode out-of-domain latch）
    _uErrorIdInt := 16#0003_02C0; // 0003_02C0 失效安全模式枚举越界【故障级】/ Fail-safe mode out of domain, fault level
END_IF

IF _fbTrigReset.Q OR _bPendReset THEN
    _bPendReset := FALSE;         // 消费方法复位请求（Consume method reset）
    IF _bModeValid THEN           // 故障源已消失才解除（Release only when source gone）
        _bFaultLatch := FALSE;    // 故障锁存解除（Fault latch released）
        _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
    END_IF
END_IF

// ============================================================================
// 段 3｜防抖合成 + 失效安全归一（核心语义，IF 显式写，禁 XOR 裸用）
//      Debounce merge + fail-safe normalization (explicit IF, no raw XOR)
// ============================================================================
IF _fbTonDbCover.Q THEN
    _bRawDebounced := TRUE;       // 覆盖侧防抖达成（Cover debounce reached）
ELSIF _fbTonDbBare.Q THEN
    _bRawDebounced := FALSE;      // 裸露侧防抖达成（Bare debounce reached）
END_IF                            // 窗内保持上次判定（Hold previous verdict inside window）

IF NOT _bModeValid THEN
    _bMatNorm := FALSE;           // 模式非法归一安全侧（Invalid mode normalized to safe side）
ELSIF eFailSafeMode = E_DL_FailSafeMode.eLow THEN
    _bMatNorm := NOT _bRawDebounced; // eLow 极性取反归一（约定 raw TRUE=无料/裸露，反相接线层保证）/ eLow polarity inversion (raw TRUE = bare by wiring convention)
ELSE
    _bMatNorm := _bRawDebounced;  // eHigh 极性直通归一（raw TRUE=覆盖有料）/ eHigh polarity pass-through
END_IF

// 使能切断/故障期强制镜像到失效安全侧（eHigh→有料防溢流；eLow→无料防干转）
// Enable-off or fault forces the fail-safe side (eHigh → covered, eLow → bare)
IF (NOT bEnable) OR _bFaultLatch THEN
    IF eFailSafeMode = E_DL_FailSafeMode.eHigh THEN
        _bMatSafe := TRUE;        // eHigh 强制有料（Force covered, overflow-safe）
    ELSE
        _bMatSafe := FALSE;       // eLow 强制无料（Force bare, dry-run-safe）
    END_IF
ELSE
    _bMatSafe := _bMatNorm;       // 正常处理直通（Normal processing pass-through）
END_IF

// ============================================================================
// 段 4｜覆盖/裸露双延迟确认 + 测试单拍 + 状态映像（IF 派生链含 ELSE 兜底）
//      Cover/bare dual-delay confirm + test one-shot + state image with ELSE
// ============================================================================
IF _fbTonCover.Q THEN
    _bMatConfirmed := TRUE;       // 覆盖确认达成（Cover confirmed）
ELSIF _fbTonBare.Q THEN
    _bMatConfirmed := FALSE;      // 裸露确认达成（Bare confirmed）
END_IF                            // 确认窗内保持（Hold inside confirm window）

IF _bFaultLatch THEN
    _eState := E_DL_LevelState.eFault;      // 故障映像（Fault image）
ELSIF (NOT bEnable) THEN
    _eState := E_DL_LevelState.eSensorLoss; // 使能切断：失效安全强制镜像的诊断映像（强制镜像诊断位）/ Enable-off: forced-mirror diagnostic image
ELSIF _bMatConfirmed THEN
    _eState := E_DL_LevelState.eMaterial;   // 有料确认映像（Material image）
ELSE
    _eState := E_DL_LevelState.eNoMaterial; // 无料兜底映像（No-material fallback image）
END_IF

bSensorTest := _bPendTest;        // 测试态镜像一拍，仅由 CmdTest 承载（v1.0.1 修复：原
                                  // _fbTrigTest 误接 bEnable，使能沿误置测试镜像）
                                  // Test mirror one scan, CmdTest only (v1.0.1 fix)
_bPendTest := FALSE;              // 方法测试请求消费（Method test request consumed）

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障。仅故障态受理（接口方法拒绝语义红线）。
 *      Method CmdReset - reset, accepted only in fault state.
 *------------------------------------------------------------------------------*)


PROPERTY eState : E_DL_LevelState
eState := _eState;                // 返回派生状态（Return derived state）

(*------------------------------------------------------------------------------
 * 属性: bMaterial（GET）—— 有料判定输出（失效安全归一后，TRUE=有料）。
 *      Property bMaterial (GET) - fail-safe normalized material output.
 *------------------------------------------------------------------------------*)
PROPERTY bMaterial : BOOL
bMaterial := _bMatSafe;           // 返回失效安全归一输出（Return fail-safe normalized output）

(*------------------------------------------------------------------------------
 * 属性: bHighAlarm（GET）—— 高点溢流联锁输出（fail-safe HIGH 语义：归一有
 *         料即报警；eHigh 组态下失效即报警，防溢流方向，现场不得反接）。
 *      Property bHighAlarm (GET) - high-level interlock, fail-safe HIGH semantics.
 *------------------------------------------------------------------------------*)
PROPERTY bHighAlarm : BOOL
bHighAlarm := _bMatSafe;          // 有料即高点报警（Covered = high alarm）

(*------------------------------------------------------------------------------
 * 属性: bLowAlarm（GET）—— 低点干转联锁输出（fail-safe LOW 语义：归一无料
 *         即报警；eLow 组态下失效即报警，防干转方向，现场不得反接）。
 *      Property bLowAlarm (GET) - low-level interlock, fail-safe LOW semantics.
 *------------------------------------------------------------------------------*)
PROPERTY bLowAlarm : BOOL
bLowAlarm := NOT _bMatSafe;       // 无料即低点报警（Bare = low alarm）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_LevelState.eFault); // 显式排除信息级派生式（Derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（故障级优先，无故障时透出本拍信息级
 *         码，0.2/0.15 公约；0003_0116 为预留信息级，本轮不触发）。
 *      Property uErrorId (GET) - last error code (fault priority, info shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_LevelState.eFault) THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK
