(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EventCounter
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 分类     (Category)   : 信号处理功能块（Function Block · 通用事件计数）
 * 功能简述 (Function)   : 双向事件计数器（DINT 域）。递增/递减脉冲沿独立
 *                         计数、预置装载、高/低阈值比较输出（每拍重算非锁
 *                         存）、回绕/饱和两种越界模式可选；双脉冲同拍抵消
 *                         置信息级、装载覆盖计数置信息级；参数非法故障锁存。
 *                         与 FC_DL_BitCount（位统计）、FB_DL_RuntimeMeter
 *                         （时间累计）职责分离，本块为通用事件计数。
 * 公约遵循 (Convention) : 0.1/R23 事件型，免首扫——计数由脉冲沿驱动，无
 *                         初始化/跟踪同步语义，不设 bInit。
 *                         0.2/R21 bFault 为显式排除信息级码的派生式；故障
 *                         码表逐条标注级别；信息级只进 uErrorId 不进报警链。
 *                         0.7/R15 故障级锁存仅解除路径（bReset 上升沿）清
 *                         码；信息级瞬时型每拍重算。
 *                         0.8 故障码段位 16#0001_xxxx（经 DL_Base VERSION.md
 *                         码表核对，0001_0101~0104 / 0001_0210 均未占用）：
 *                         【故障级】0001_0210 计数下限 ≥ 上限；
 *                         【信息级】0001_0101 双脉冲同拍抵消、0001_0102 装
 *                         载覆盖计数（bLoad 优先级最高，同拍覆盖计数脉冲）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 越界钳位/回绕双模式 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R7 三个边沿实例主体
 *                         最前部无条件刷新 ✓｜R8 越界常量化无魔法数 ✓
 * 设计要点 (Key notes)  : ① 双脉冲同拍到达：净变化 0，置信息级 0001_0101，
 *                           不计数（避免扫描时序歧义）；
 *                         ② 回绕语义：计数值越过 nMax → 回 nMin 继续（bWrap
 *                           =TRUE）；饱和语义：钳位在 nMax/nMin 并置溢出标志
 *                           一拍（bWrap=FALSE）；
 *                         ③ bLoad 上升沿优先级最高：同拍覆盖计数脉冲，置信
 *                           息级 0001_0102；
 *                         ④ bCompHigh = nCount >= nCompHigh、bCompLow =
 *                           nCount <= nCompLow，每拍重算非锁存（判据语义在
 *                           注释写死，防现场误解）；
 *                         ⑤ bOverflow/bUnderflow 为事件一拍脉冲，不锁存。
 * 开源溯源 (Origin)     : 来源标签 lgf-counter（RAW_NOTES_R7 S-1：LGF 库
 *                         CTU/CTUD 计数器族的功能语义域——双向计数、预置
 *                         装载、比较输出、回绕，公开文档，仅借鉴功能域语
 *                         义；实现、故障码与引脚契约 100% 本库独立设计，
 *                         clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 增/减/抵消逐拍推演：单发 +1 → 1；再单发 -1 → 0；同拍双发 → 0 且
 *      信息级 0001_0101；
 *   V2 回绕跨上下限：nMin=0/nMax=9/bWrap=TRUE，nCount=9 时 +1 → 0 且
 *      bOverflow 一拍；nCount=0 时 -1 → 9 且 bUnderflow 一拍；
 *   V3 饱和钳位：bWrap=FALSE，nCount=9 时 +1 → 9（钳位）且 bOverflow 一拍；
 *   V4 预置装载：bLoad 沿 → nCount := nPreset=5；同拍 +1 脉冲被覆盖且信息
 *      级 0001_0102；
 *   V5 参数非法：nMin=10 > nMax=5 → 故障锁存 0001_0210，bFault=TRUE；
 *   V6 复位清零：bReset 沿 → 计数值=0、故障与信息码清零。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Base LGF Counter 组开组）
 *   2026-11-15  v1.0.1  终审修复 2 处：① DINT 极值 +1/-1 回绕穿透饱和/回绕
 *                       判据（加算/减算改先判界后运算）；② 复位与计数脉冲
 *                       同拍时计数覆盖复位（复位拍最高优先，段 4 前置分支）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_EventCounter
VAR_INPUT
    bCntUp     : BOOL;              // 递增计数脉冲（Count-up pulse），R_TRIG 上升沿 +1 / Count-up pulse, rising edge +1
    bCntDown   : BOOL;              // 递减计数脉冲（Count-down pulse），R_TRIG 上升沿 -1 / Count-down pulse, rising edge -1
    bLoad      : BOOL;              // 预置装载指令（Preset load），R_TRIG 上升沿把 nPreset 写入计数值 / Preset load edge writes nPreset into the count
    nPreset    : DINT;              // 预置值（Preset value）[-]，任意 DINT 域 / Preset value, any DINT value
    bWrap      : BOOL;              // 回绕模式使能（Wrap-around enable），TRUE=上溢回 nMin/nMax 循环；FALSE=饱和钳位 / TRUE = wrap to opposite limit, FALSE = saturate
    nMin       : DINT := -2147483648; // 计数下限（Count lower limit）[-]，默认 DINT 域下界（与 DL_CNT_DINT_MIN 一致）/ Lower limit, DINT minimum by default
    nMax       : DINT := 2147483647;  // 计数上限（Count upper limit）[-]，默认 DINT 域上界（与 DL_CNT_DINT_MAX 一致）/ Upper limit, DINT maximum by default
    nCompHigh  : DINT;              // 高阈值比较（High compare）[-]，bCompHigh 判据 nCount >= nCompHigh / High threshold for bCompHigh (greater-or-equal)
    nCompLow   : DINT;              // 低阈值比较（Low compare）[-]，bCompLow 判据 nCount <= nCompLow / Low threshold for bCompLow (less-or-equal)
    bReset     : BOOL;              // 上升沿复位故障与清零计数值（Reset edge clears fault and count）/ Rising edge resets fault and clears count
END_VAR
VAR_OUTPUT
    nCount      : DINT;             // 当前计数值（Current count）[-] / Current count value
    bCompHigh   : BOOL;             // 高阈值比较结果（High compare output），每拍重算 nCount >= nCompHigh 非锁存 / High compare, recomputed every scan, not latched
    bCompLow    : BOOL;             // 低阈值比较结果（Low compare output），每拍重算 nCount <= nCompLow 非锁存 / Low compare, recomputed every scan, not latched
    bOverflow   : BOOL;             // 上溢事件标志（Overflow event），本拍发生上溢置位一拍 / Overflow event, TRUE for one scan on overflow
    bUnderflow  : BOOL;             // 下溢事件标志（Underflow event），本拍发生下溢置位一拍 / Underflow event, TRUE for one scan on underflow
    bFault      : BOOL;             // 故障标志（Fault flag），显式排除信息级码（R21）/ Fault flag, info codes explicitly excluded
    uErrorId    : UDINT;            // 故障码（Error code），16#0001_xxxx 段，0=无故障 / Error code, family 16#0001_xxxx, 0 = none
END_VAR
VAR
    _fbTrigUp    : R_TRIG;          // 递增脉冲上升沿（Up pulse rising edge）/ Up pulse edge detector
    _fbTrigDown  : R_TRIG;          // 递减脉冲上升沿（Down pulse rising edge）/ Down pulse edge detector
    _fbTrigLoad  : R_TRIG;          // 装载指令上升沿（Load command rising edge）/ Load command edge detector
    _fbTrigReset : R_TRIG;          // 复位上升沿（Reset rising edge）/ Reset edge detector
    _bFaultLatch : BOOL;            // 故障锁存标志（Fault latch flag），仅 bReset 上升沿清除 / Fault latch, cleared only by reset edge
    _uErrorIdInt : UDINT;           // 内部故障级码寄存（Internal fault-level code register）/ Internal fault-level code register
    _uInfoCode   : UDINT;           // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bUpEdge     : BOOL;            // 本拍递增沿有效（Up edge active this scan）/ Up edge active this scan
    _bDownEdge   : BOOL;            // 本拍递减沿有效（Down edge active this scan）/ Down edge active this scan
    _bLoadEdge   : BOOL;            // 本拍装载沿有效（Load edge active this scan）/ Load edge active this scan
    _nWork       : DINT;            // 计数运算工作副本（Working copy of count）[-] / Working copy for arithmetic
END_VAR
VAR CONSTANT
    DL_CNT_DINT_MIN : DINT := -2147483648; // DINT 域下界（DINT lower bound）/ DINT lower bound
    DL_CNT_DINT_MAX : DINT := 2147483647;  // DINT 域上界（DINT upper bound）/ DINT upper bound
END_VAR

// ============================================================================
// 段 1｜边沿实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all edge instances (R7/0.5)
// ============================================================================
_fbTrigUp(CLK    := bCntUp);
_fbTrigDown(CLK  := bCntDown);
_fbTrigLoad(CLK  := bLoad);
_fbTrigReset(CLK := bReset);
_bUpEdge   := _fbTrigUp.Q;        // 本拍递增沿（Up edge this scan）
_bDownEdge := _fbTrigDown.Q;      // 本拍递减沿（Down edge this scan）
_bLoadEdge := _fbTrigLoad.Q;      // 本拍装载沿（Load edge this scan）

// ============================================================================
// 段 2｜信息级码预清零 + 复位路径（R15：锁存型故障只在解除路径清码）
//      Info code preset zero + reset path (R15: latched fault cleared in release path only)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）
bOverflow  := FALSE;              // 事件标志每拍预清零，由段 4 事件置位一拍（Event flags preset FALSE, set one scan by stage 4）
bUnderflow := FALSE;              // 事件标志每拍预清零（Event flag preset FALSE）

IF _fbTrigReset.Q THEN
    _nWork      := 0;             // 计数值清零（Count cleared）
    _bFaultLatch := FALSE;        // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
END_IF

// ============================================================================
// 段 3｜参数防御：nMin >= nMax → 故障锁存（故障级，锁存期间计数值冻结）
//      Parameter guard: nMin >= nMax latches a fault-level error, count frozen
// ============================================================================
IF nMin >= nMax THEN
    _bFaultLatch := TRUE;                 // 参数非法故障锁存（Invalid limit latch）
    _uErrorIdInt := 16#0001_0210;         // 0001_0210 计数下限 ≥ 上限【故障级】/ Lower limit >= upper limit, fault level
ELSE

    // ========================================================================
    // 段 4｜计数主逻辑：装载优先 → 双脉冲抵消 → 单向计数与越界处理
    //      Counting main logic: load first, dual-pulse cancellation, then counting
    // ========================================================================
    IF _fbTrigReset.Q THEN
        _nWork := 0;                    // 复位拍最高优先：同拍计数/装载脉冲被复位覆盖（复位-计数同拍冲突修复）/ Reset scan top priority, pulses overridden
    ELSIF _bLoadEdge THEN
        _nWork := nPreset;                // 装载优先级最高：预置值直接写入（Load has top priority）
        IF _bUpEdge OR _bDownEdge THEN
            _uInfoCode := 16#0001_0102;   // 0001_0102 装载覆盖计数【信息级】/ Load overrides counting pulses, info level
        END_IF
    ELSIF _bUpEdge AND _bDownEdge THEN
        _uInfoCode := 16#0001_0101;     // 0001_0101 双脉冲同拍抵消【信息级】，净变化 0 / Dual pulses cancel, net zero, info level
    ELSIF _bUpEdge THEN
        // 先判界再加算：nCount 已达 nMax 直接走越界语义，杜绝 DINT 极值 +1
        // 回绕穿透（nCount=DINT_MAX 时 +1 回绕为负、>nMax 判据失效）
        // Boundary pre-check before increment: DINT-max +1 wrap cannot bypass the verdict
        IF nCount >= nMax THEN
            IF bWrap THEN
                _nWork := nMin;         // 回绕语义：越过上限回下限（Wrap: above max falls back to min）
            ELSE
                _nWork := nMax;         // 饱和语义：钳位在上限（Saturate at max）
            END_IF
            bOverflow := TRUE;          // 上溢事件一拍脉冲（Overflow event, one scan）
        ELSE
            _nWork := nCount + 1;       // 递增一步（Increment one step, pre-guarded no-overflow）
        END_IF
    ELSIF _bDownEdge THEN
        // 先判界再减算：对称防御 DINT 极值 −1 回绕穿透（Mirror of the increment guard）
        IF nCount <= nMin THEN
            IF bWrap THEN
                _nWork := nMax;         // 回绕语义：越过下限回上限（Wrap: below min jumps to max）
            ELSE
                _nWork := nMin;         // 饱和语义：钳位在下限（Saturate at min）
            END_IF
            bUnderflow := TRUE;         // 下溢事件一拍脉冲（Underflow event, one scan）
        ELSE
            _nWork := nCount - 1;       // 递减一步（Decrement one step, pre-guarded no-overflow）
        END_IF
    ELSE
        _nWork := nCount;               // 无事件保持计数值（No event, hold count）
    END_IF
    nCount := _nWork;                   // 计数值单点出口（Single outlet for the count）
END_IF

// ============================================================================
// 段 5｜输出推导：比较输出每拍重算、溢出标志由段 4 置位本拍后自然回落
//      Output derivation: compare outputs recomputed each scan, event flags one-shot
// ============================================================================
bCompHigh := (nCount >= nCompHigh);   // 高阈值判据（High compare: greater-or-equal）
bCompLow  := (nCount <= nCompLow);    // 低阈值判据（Low compare: less-or-equal）

IF _fbTrigReset.Q THEN
    bOverflow  := FALSE;              // 复位拍清事件标志（Event flags cleared on reset scan）
    bUnderflow := FALSE;
END_IF

IF _bFaultLatch THEN
    nCount := 0;                      // 故障期计数值输出安全零（Safe zero while latched）
END_IF

// ============================================================================
// 段 6｜bFault/uErrorId 出口（R21：bFault 显式排除信息级；无故障级锁存时
//       uErrorId 透出本拍信息级码）
//      Outlets: bFault excludes info codes (R21); uErrorId shows info code when no fault
// ============================================================================
bFault := _bFaultLatch;               // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;         // 故障级码优先透出（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;           // 无故障时透出本拍信息级码（Transient info code when no fault）
END_IF
END_FUNCTION_BLOCK
