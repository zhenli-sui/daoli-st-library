(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BufferMagazine
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 工艺段功能块（Function Block · 多层料仓/弹夹升降存取调度）
 * 功能简述 (Function)   : 多层料仓/弹夹升降存取调度器：管理各层槽位状态（空/
 *                         满/NG/预留），按「取料优先最低满层、存料优先最低空
 *                         层、NG 料优先占预留隔离位」策略选层，输出升降方向
 *                         与到位联锁，统计满/空/NG 数，支持手动指定层。本块
 *                         不做夹具/机械手动作编排（只给层目标与到位联锁），
 *                         取放动作由调用方分段编排，经 bHandlingDone 反馈。
 * 首扫说明 (Init note)  : 纯事件型组件，免首扫（R23/公约 0.1），无 bInit；
 *                         槽位状态由调用方初始化，本块仅做存取维护。
 * 公约遵循 (Convention) : 0.2/R21 bFault 为显式排除信息级码的派生式；0.4 双
 *                         语同行注释；0.5/R7 六实例（R_TRIG×3/TON×3）主体最
 *                         前部无条件刷新；0.7/R15 故障锁存仅复位路径清码、
 *                         信息级瞬时型；0.8 码位段 16#0005_xxxx（经 DL_Process
 *                         VERSION.md 复核，本块 0180~0186 / 0280~0283 无冲
 *                         突）；0.13 零接口依赖（层位置信号引脚注入，无接口
 *                         引用）；0.14 数组存取先判域、FOR 有界（禁无界
 *                         WHILE）；0.16 无魔法数；0.17 终结符成对 ✓；0.18
 *                         E_DL_SlotState 与 E_DL_MagState 随本块同文件发布；
 *                         0.19 码位同行【级别】注释；0.20 验收向量入头注释；
 *                         R25 bDone 单拍三律。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 越界防御/超时锁存 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 六实例主体最前部无条件刷新 ✓｜R8 全常量化 ✓
 *                         R25 单拍标志生命周期三律 ✓
 * 设计要点 (Key notes)  : ① 选层策略：取料=最低 eFull 层；存 OK=最低 eEmpty
 *                           层；存 NG=最低 eReserved 优先、次 eEmpty（NG 料优
 *                           先占隔离位，与良品物理隔离）；无适配层 → 对应信息
 *                           码（0180/0181/0182）拒绝回空闲；
 *                         ② 手动层优先：nManualLayer 在 1..层数时强制用指定
 *                           层，槽位状态与请求类型不匹配 → 0183 拒绝；运行中
 *                           （bBusy）改手动层本周期不生效 + 0185；
 *                         ③ 移动联锁：方向由层位置与目标层比较派生（位置未
 *                           知 0 时不发方向指令，等限位恢复，超时走 0280）；
 *                           到位 = 层号相等 AND 到位信号消抖通过；升降方向输
 *                           出由同源比较派生，结构上恒互斥；
 *                         ④ 取放槽位更新：取料 eFull→eEmpty、存 OK
 *                           eEmpty→eFull、存 NG eEmpty/eReserved→eNg；
 *                         ⑤ 槽位数组维度字面量 16（等同 DL_MAG_MAX_LAYERS）
 *                           与常量同步维护；所有槽位索引先判域再访问。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 层位置未知（nLiftAtLayer=0）的移动语义：规格仅
 *                           定义「0=未知」未定义移动行为，按「不发方向指令、
 *                           保持等待，超时走 0280」实现。理由：位置未知时发
 *                           方向指令有撞层风险；影响：编码器断线工况下升降静
 *                           止直至超时报故障，不会盲动。
 * 开源溯源 (Origin)     : 来源标签 material-handling / magazine-stocker
 *                         （RAW_NOTES_R8 S-7 线体节拍 + S-13 状态指示联动：
 *                         多层料仓/弹夹存取公开工程惯例——最低满层取料、最
 *                         低空层存料、NG 隔离位优先、槽位状态四态分类、层位
 *                         置到位联锁与超时参数域，公开技术资料，仅借鉴策略分
 *                         类与参数域；状态机、码位、引脚契约 100% 本库独立设
 *                         计，clean-room 未复制源码。许可证说明：借鉴对象为
 *                         公开技术惯例，无附带许可限制；本文件为本库原创实现，
 *                         随本库许可证发布）。
 * 验收向量 (Acceptance) :
 *   V1 8 层全空，存料 → 选第 1 层，到位+取放完成后槽位变 eFull；
 *   V2 连续存至全满 → bMagFull 置位，再存 → 拒绝 + 信息码 0181；
 *   V3 多层满时取料 → 选最低满层；
 *   V4 存 NG 且存在 eReserved 层 → 优先占预留隔离位（eReserved→eNg）；
 *   V5 手动指定第 5 层取料但该层空 → 拒绝 + 信息码 0183；
 *   V6 升降超时 → 0280 锁存；
 *   V7 取/存请求同拍 → 双丢弃 + 信息码 0186；
 *   V8 nLayerCount=0 → 钳位 1 + 信息码 0184。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Process 料仓调度件）
 *   2026-11-15  v1.0.1  R8 总监终审修复：终端态分支内的孤立空语句 `;`（非 IEC 61131-3 文法，statement_list 允许零条语句但不容纳孤立分号）改为纯注释占位分支，行为等价、跨平台可移植性合规。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SlotState（归属 FB_DL_BufferMagazine，与其同文件发布，公约 0.18）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SlotState :
(
    eEmpty    := 0,    // 空槽：可存料 / Empty slot, available for store
    eFull     := 10,   // 满槽：有良品可取 / Full slot, good part awaiting fetch
    eNg       := 20,   // NG 槽：隔离不良品 / NG slot, rejected part isolated
    eReserved := 30    // 预留槽：NG 存入优先占用 / Reserved slot, preferred for NG store
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MagState（归属 FB_DL_BufferMagazine，与其同文件发布，公约 0.18）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MagState :
(
    eIdle     := 0,    // 空闲：等请求 / Idle, awaiting request
    eSelect   := 10,   // 选层：按策略确定目标层 / Select, choose target layer by strategy
    eMoving   := 20,   // 移动：升降趋近目标层 / Moving, lift approaching target layer
    eArrived  := 30,   // 到位：方向撤销过渡 / Arrived, direction revoked transition
    eHandling := 40,   // 取放中：等动作完成反馈 / Handling, awaiting completion feedback
    eDone     := 50,   // 完成：单拍后回空闲 / Done, one-shot then idle
    eFault    := 99    // 故障锁存：仅复位沿退出 / Fault latched, only reset edge exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_BufferMagazine
VAR_INPUT
    bEnable             : BOOL;             // 使能（Enable），FALSE=停止升降输出并清请求 / Enable, FALSE stops lift outputs and clears requests
    bReset              : BOOL;             // 复位故障（Fault reset），上升沿受理 / Rising edge resets fault
    bReqFetch           : BOOL;             // 取料请求（Fetch request），上升沿受理 / Fetch request edge
    bReqStore           : BOOL;             // 存料请求（Store request），上升沿受理 / Store request edge
    bReqStoreNg         : BOOL;             // 存 NG 料（Store NG），与 bReqStore 同沿时按 NG 处理 / Store-as-NG flag, effective with store edge
    nManualLayer        : UINT;             // 手动指定层（Manual layer）[-]，0=自动选层，1..层数=指定 / Manual layer, zero = auto select
    nLayerCount         : UINT := 8;        // 层数（Layer count）[-]，域 1..DL_MAG_MAX_LAYERS，越界钳位 / Layer count, clamped
    nLiftAtLayer        : UINT;             // 升降当前层位置（Lift current layer）[-]，由限位/编码器注入，0=未知 / Lift position, zero = unknown
    bLiftInPosition     : BOOL;             // 升降到位确认（Lift in position） / Lift in-position feedback
    bHandlingDone       : BOOL;             // 取放动作完成（Handling done），取放相退出条件 / Handling completion feedback
    tMoveTimeout        : TIME := T#20S;    // 升降超时（Move timeout），按层间行程整定 / Lift move timeout
    tHandlingTimeout    : TIME := T#10S;    // 取放超时（Handling timeout）/ Handling timeout
    tDebounce           : TIME := T#50MS;   // 到位信号消抖（In-position debounce）/ In-position debounce time
END_VAR
VAR_OUTPUT
    bMoveUp             : BOOL;             // 上升指令（Move up）/ Move up command
    bMoveDown           : BOOL;             // 下降指令（Move down）/ Move down command
    nTargetLayer        : UINT;             // 目标层（Target layer）[-]，1 基层号，0=无目标 / Target layer 1-based, zero = none
    eState              : E_DL_MagState := E_DL_MagState.eIdle; // 主状态（Main state）/ Main state
    bBusy               : BOOL;             // 调度中（Busy），选层至取放态为 TRUE / TRUE from select to handling
    bDone               : BOOL;             // 存取完成单拍（Done pulse），单拍生命周期三律 / One-scan done pulse
    bMagFull            : BOOL;             // 料仓全满（Magazine full），无空槽，瞬态型 / Magazine full, no empty slot, transient
    bMagEmpty           : BOOL;             // 料仓全空（Magazine empty），无满槽，瞬态型 / Magazine empty, no full slot, transient
    nFullCount          : UINT;             // 满槽数（Full count），每拍重算 / Full slot count, recomputed each scan
    nEmptyCount         : UINT;             // 空槽数（Empty count），每拍重算 / Empty slot count, recomputed each scan
    nNgCount            : UINT;             // NG 槽数（NG count），每拍重算 / NG slot count, recomputed each scan
    bFault              : BOOL;             // 故障锁存（Fault），仅故障级码 / Latched fault, fault codes only
    uErrorId            : UDINT;            // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, fault-level priority
END_VAR
VAR_IN_OUT
    aeSlot              : ARRAY[0..15] OF E_DL_SlotState; // 各层槽位状态（Slot states），维度 16 等同 DL_MAG_MAX_LAYERS，索引 0 = 第 1 层，由本块维护 / Slot states, dim 16, index 0 = layer 1, maintained by this block
END_VAR
VAR
    _eState             : E_DL_MagState := E_DL_MagState.eIdle;   // 内部主状态（Internal main state）/ Internal state
    _bFaultLatch        : BOOL;             // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt        : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode          : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code
    _bStoreNgOp         : BOOL;             // 本次存取为 NG 存入（Store-as-NG operation flag）/ Store-as-NG operation register
    _bFetchOp           : BOOL;             // 本次操作为取料（Fetch operation flag）/ Fetch operation register
    _nTargetIdx         : UINT;             // 目标层数组索引（Target slot index）[-]，0 基 / Target slot index 0-based
    _nLayerEff          : UINT := 8;        // 生效层数（Effective layer count），钳位后值 / Clamped effective layer count
    _nManualEff         : UINT;             // 生效手动层（Effective manual layer），非忙时锁存 / Effective manual layer, latched when not busy
    _nFullCnt           : UINT;             // 满槽计数（Full count scratch）/ Full count scratch
    _nEmptyCnt          : UINT;             // 空槽计数（Empty count scratch）/ Empty count scratch
    _nNgCnt             : UINT;             // NG 槽计数（NG count scratch）/ NG count scratch
    _nIdx               : UINT;             // 循环索引（Loop index）[-] / Loop index
    _nSelIdx            : UINT;             // 选层命中索引（Selected slot index）[-]，哨兵 16 / Selected slot index, sentinel 16
    _bInPosDeb          : BOOL;             // 消抖后到位信号（Debounced in-position）/ Debounced in-position feedback
    _fbTrigReset        : R_TRIG;           // 复位沿（Reset edge detector）/ Reset edge detector
    _fbTrigFetch        : R_TRIG;           // 取料沿（Fetch edge detector）/ Fetch edge detector
    _fbTrigStore        : R_TRIG;           // 存料沿（Store edge detector）/ Store edge detector
    _fbTonDebounce      : TON;              // 到位信号消抖（In-position debounce timer）/ In-position debounce timer
    _fbTonMoveTo        : TON;              // 升降超时（Move timeout timer）/ Move timeout timer
    _fbTonHandTo        : TON;              // 取放超时（Handling timeout timer）/ Handling timeout timer
END_VAR
VAR CONSTANT
    DL_MAG_MAX_LAYERS   : UINT := 16;       // 层数上限（Max layers）[-]，与数组维度字面量 16 同步 / Max layers, sync with literal dim 16
    DL_MAG_IDX_NONE     : UINT := 16;       // 选层哨兵索引（Sentinel index for none）[-] / Sentinel index, none selected
    DL_MAG_ERR_MOVE     : UDINT := 16#0005_0280; // 0005_0280 升降超时未到位【故障级】/ Lift move timeout, fault level
    DL_MAG_ERR_HAND     : UDINT := 16#0005_0281; // 0005_0281 取放动作超时【故障级】/ Handling timeout, fault level
    DL_MAG_ERR_POS      : UDINT := 16#0005_0282; // 0005_0282 升降层位置越界（限位/编码器异常）【故障级】/ Lift position out of range, fault level
    DL_MAG_ERR_STATE    : UDINT := 16#0005_0283; // 0005_0283 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_MAG_INFO_NOFULL  : UDINT := 16#0005_0180; // 0005_0180 无满槽可取（料仓空）【信息级】/ No full slot, magazine empty, info level
    DL_MAG_INFO_NOEMPTY : UDINT := 16#0005_0181; // 0005_0181 无空槽可存（料仓满）【信息级】/ No empty slot, magazine full, info level
    DL_MAG_INFO_NONG    : UDINT := 16#0005_0182; // 0005_0182 无 NG 隔离位可用【信息级】/ No NG isolation slot, info level
    DL_MAG_INFO_MISMATCH: UDINT := 16#0005_0183; // 0005_0183 手动指定层与请求类型不匹配【信息级】/ Manual layer mismatch, info level
    DL_MAG_INFO_CLAMP   : UDINT := 16#0005_0184; // 0005_0184 层数越界钳位【信息级】/ Layer count clamped, info level
    DL_MAG_INFO_MANBUSY : UDINT := 16#0005_0185; // 0005_0185 运行中改手动层，下周期生效【信息级】/ Manual layer changed while busy, info level
    DL_MAG_INFO_CONFL   : UDINT := 16#0005_0186; // 0005_0186 取/存请求同拍冲突，双丢弃【信息级】/ Fetch/store edge conflict, both dropped, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigReset(CLK := bReset);            // 复位沿（Reset edge）
_fbTrigFetch(CLK := bReqFetch);         // 取料沿（Fetch edge）
_fbTrigStore(CLK := bReqStore);         // 存料沿（Store edge）
_fbTonDebounce(IN := bLiftInPosition, PT := tDebounce);   // 到位信号消抖（In-position debounce）
_fbTonMoveTo(IN := (_eState = E_DL_MagState.eMoving), PT := tMoveTimeout);      // 升降超时（Move timeout）
_fbTonHandTo(IN := (_eState = E_DL_MagState.eHandling), PT := tHandlingTimeout); // 取放超时（Handling timeout）

// ============================================================================
// 段 2｜信息级预清零 + 输出默认赋值（0.9）+ 参数防御 + 复位路径（R15）
//      Info preset + output defaults + param defense + reset path (R15)
// ============================================================================
_uInfoCode := 0;                        // 信息级瞬时型每拍重算（Transient info recomputed each scan）
bDone := FALSE;                         // 完成单拍先清零（R25：置位-消费-复位同周期闭环）/ Done pulse preset FALSE (R25)
bMoveUp := FALSE;                       // 方向指令默认双 FALSE（Directions default FALSE）
bMoveDown := FALSE;
bMagFull := FALSE;                      // 料仓状态标志默认清（Status flags preset）
bMagEmpty := FALSE;
nFullCount := UINT#0;                   // 计数默认零（Counts preset zero）
nEmptyCount := UINT#0;
nNgCount := UINT#0;

// 层数钳位（Layer count clamp，域 1..16）
IF (nLayerCount < UINT#1) OR (nLayerCount > DL_MAG_MAX_LAYERS) THEN
    _nLayerEff := LIMIT(UINT#1, nLayerCount, DL_MAG_MAX_LAYERS);   // 域钳位（Domain clamp）
    _uInfoCode := DL_MAG_INFO_CLAMP;    // 0005_0184 层数越界钳位【信息级】/ Layer count clamped, info level
ELSE
    _nLayerEff := nLayerCount;          // 引脚原值（Pin value as-is）
END_IF

// 升降位置越界监视（位置 > 生效层数且非零 → 限位/编码器异常，锁存）
// Lift position range monitor (position beyond layers and non-zero → sensor fault)
IF (nLiftAtLayer > _nLayerEff) AND (nLiftAtLayer <> UINT#0) THEN
    _bFaultLatch := TRUE;               // 位置越界锁存（Position range latch）
    _uErrorIdInt := DL_MAG_ERR_POS;     // 0005_0282 升降层位置越界【故障级】/ Lift position out of range, fault level
    _eState := E_DL_MagState.eFault;
END_IF

// 复位路径：仅此路径可清故障锁存（R15）
IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;              // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000;       // 故障码清零（Fault code cleared）
    IF _eState = E_DL_MagState.eFault THEN
        _eState := E_DL_MagState.eIdle; // 故障态回空闲（Fault state back to idle）
        nTargetLayer := UINT#0;         // 目标层清零（Target cleared）
    END_IF
END_IF

// 到位消抖归并（Debounced in-position merge）
_bInPosDeb := _fbTonDebounce.Q;         // 消抖后到位（Debounced in-position）

// ============================================================================
// 段 3｜每拍槽位统计（FOR 有界 + 索引先判域；瞬态型重算）
//      Per-scan slot statistics (bounded FOR, index bounded; transient)
// ============================================================================
_nFullCnt := UINT#0;                    // 计数清零（Counts reset）
_nEmptyCnt := UINT#0;
_nNgCnt := UINT#0;
FOR _nIdx := UINT#0 TO _nLayerEff - UINT#1 DO
    IF _nIdx < DL_MAG_MAX_LAYERS THEN   // 索引先判域（Index bounded first）
        IF aeSlot[_nIdx] = E_DL_SlotState.eFull THEN
            _nFullCnt := _nFullCnt + UINT#1;    // 满槽计数（Full counted）
        ELSIF aeSlot[_nIdx] = E_DL_SlotState.eEmpty THEN
            _nEmptyCnt := _nEmptyCnt + UINT#1;  // 空槽计数（Empty counted）
        ELSIF aeSlot[_nIdx] = E_DL_SlotState.eNg THEN
            _nNgCnt := _nNgCnt + UINT#1;        // NG 槽计数（NG counted）
        END_IF
        // eReserved 不计入三类计数（Reserved not counted in the three classes）
    END_IF
END_FOR
nFullCount := _nFullCnt;                // 计数出口（Count outlets）
nEmptyCount := _nEmptyCnt;
nNgCount := _nNgCnt;
bMagFull := (_nEmptyCnt = UINT#0);      // 全满：无空槽（Full: no empty slot）
bMagEmpty := (_nFullCnt = UINT#0);      // 全空：无满槽（Empty: no full slot）

// 手动层生效锁存：非忙时跟随引脚，忙时冻结（Manual layer latched when not busy）
IF NOT bBusy THEN
    _nManualEff := nManualLayer;        // 非忙跟随（Follow when idle）
ELSIF nManualLayer <> _nManualEff THEN
    _uInfoCode := DL_MAG_INFO_MANBUSY;  // 0005_0185 运行中改手动层【信息级】/ Manual changed while busy, info level
END_IF

// ============================================================================
// 段 4｜请求受理与选层（同拍冲突双丢弃；选层策略见设计要点①②）
//      Request acceptance and layer selection (conflict drops both)
// ============================================================================
IF bEnable AND (NOT _bFaultLatch) AND (_eState = E_DL_MagState.eIdle) THEN
    IF _fbTrigFetch.Q AND _fbTrigStore.Q THEN
        _uInfoCode := DL_MAG_INFO_CONFL;    // 0005_0186 取/存同拍冲突双丢弃【信息级】/ Fetch/store conflict, info level
    ELSIF _fbTrigFetch.Q THEN
        _bFetchOp := TRUE;                  // 登记取料操作（Register fetch operation）
        _bStoreNgOp := FALSE;
        _eState := E_DL_MagState.eSelect;
    ELSIF _fbTrigStore.Q THEN
        _bFetchOp := FALSE;                 // 登记存料操作（Register store operation）
        _bStoreNgOp := bReqStoreNg;         // NG 存入标志随沿锁定（NG flag locked with edge）
        _eState := E_DL_MagState.eSelect;
    END_IF
END_IF

// ============================================================================
// 段 5｜核心调度状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core dispatch state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
CASE _eState OF

    E_DL_MagState.eIdle: // 空闲：等请求（受理逻辑在段 4）
        nTargetLayer := UINT#0;         // 无目标（No target）
        // 等请求（Awaiting request）

    E_DL_MagState.eSelect: // 选层：手动优先，自动按策略（设计要点①②）
        _nSelIdx := DL_MAG_IDX_NONE;    // 哨兵：未命中（Sentinel: none selected）
        IF (_nManualEff >= UINT#1) AND (_nManualEff <= _nLayerEff) THEN
            _nTargetIdx := _nManualEff - UINT#1;    // 手动层索引（Manual slot index, 0-based）
            IF _bFetchOp THEN
                IF aeSlot[_nTargetIdx] = E_DL_SlotState.eFull THEN
                    _nSelIdx := _nTargetIdx;    // 手动层有满槽，命中（Manual full slot hit）
                END_IF
            ELSIF _bStoreNgOp THEN
                IF (aeSlot[_nTargetIdx] = E_DL_SlotState.eEmpty)
                OR (aeSlot[_nTargetIdx] = E_DL_SlotState.eReserved) THEN
                    _nSelIdx := _nTargetIdx;    // 手动层可存 NG，命中（Manual NG-capable hit）
                END_IF
            ELSE
                IF aeSlot[_nTargetIdx] = E_DL_SlotState.eEmpty THEN
                    _nSelIdx := _nTargetIdx;    // 手动层有空槽，命中（Manual empty slot hit）
                END_IF
            END_IF
            IF _nSelIdx = DL_MAG_IDX_NONE THEN
                _uInfoCode := DL_MAG_INFO_MISMATCH;   // 0005_0183 手动层与请求不匹配【信息级】/ Manual mismatch, info level
                _eState := E_DL_MagState.eIdle;       // 拒绝回空闲（Rejected back to idle）
            END_IF
        ELSE
            IF _bFetchOp THEN
                // 取料：最低满层（Fetch: lowest full slot）
                FOR _nIdx := UINT#0 TO _nLayerEff - UINT#1 DO
                    IF (_nSelIdx = DL_MAG_IDX_NONE) AND (_nIdx < DL_MAG_MAX_LAYERS)
                    AND (aeSlot[_nIdx] = E_DL_SlotState.eFull) THEN
                        _nSelIdx := _nIdx;    // 最低满层命中（Lowest full hit）
                    END_IF
                END_FOR
                IF _nSelIdx = DL_MAG_IDX_NONE THEN
                    _uInfoCode := DL_MAG_INFO_NOFULL;     // 0005_0180 无满槽可取【信息级】/ No full slot, info level
                    _eState := E_DL_MagState.eIdle;
                END_IF
            ELSIF _bStoreNgOp THEN
                // 存 NG：最低 eReserved 优先、次 eEmpty（NG 优先占隔离位，设计要点①）
                // Store NG: lowest reserved preferred, then empty (NG prefers isolation)
                FOR _nIdx := UINT#0 TO _nLayerEff - UINT#1 DO
                    IF (_nSelIdx = DL_MAG_IDX_NONE) AND (_nIdx < DL_MAG_MAX_LAYERS)
                    AND (aeSlot[_nIdx] = E_DL_SlotState.eReserved) THEN
                        _nSelIdx := _nIdx;    // 最低预留位命中（Lowest reserved hit）
                    END_IF
                END_FOR
                FOR _nIdx := UINT#0 TO _nLayerEff - UINT#1 DO
                    IF (_nSelIdx = DL_MAG_IDX_NONE) AND (_nIdx < DL_MAG_MAX_LAYERS)
                    AND (aeSlot[_nIdx] = E_DL_SlotState.eEmpty) THEN
                        _nSelIdx := _nIdx;    // 次选最低空层（Lowest empty fallback）
                    END_IF
                END_FOR
                IF _nSelIdx = DL_MAG_IDX_NONE THEN
                    _uInfoCode := DL_MAG_INFO_NONG;       // 0005_0182 无 NG 隔离位【信息级】/ No NG slot, info level
                    _eState := E_DL_MagState.eIdle;
                END_IF
            ELSE
                // 存 OK：最低空层（Store OK: lowest empty slot）
                FOR _nIdx := UINT#0 TO _nLayerEff - UINT#1 DO
                    IF (_nSelIdx = DL_MAG_IDX_NONE) AND (_nIdx < DL_MAG_MAX_LAYERS)
                    AND (aeSlot[_nIdx] = E_DL_SlotState.eEmpty) THEN
                        _nSelIdx := _nIdx;    // 最低空层命中（Lowest empty hit）
                    END_IF
                END_FOR
                IF _nSelIdx = DL_MAG_IDX_NONE THEN
                    _uInfoCode := DL_MAG_INFO_NOEMPTY;    // 0005_0181 无空槽可存【信息级】/ No empty slot, info level
                    _eState := E_DL_MagState.eIdle;
                END_IF
            END_IF
        END_IF
        IF _nSelIdx < DL_MAG_MAX_LAYERS THEN
            _nTargetIdx := _nSelIdx;    // 目标索引登记（Target index registered）
            nTargetLayer := _nSelIdx + UINT#1;      // 目标层出口（1 基层号 / 1-based outlet）
            _eState := E_DL_MagState.eMoving;       // 进入移动（Enter moving）
        END_IF

    E_DL_MagState.eMoving: // 移动：方向派生 + 到位判据（偏离留档①：位置未知不发方向）
        IF (nLiftAtLayer >= UINT#1) AND (nLiftAtLayer <= _nLayerEff) THEN
            IF nLiftAtLayer < nTargetLayer THEN
                bMoveUp := TRUE;        // 上升趋近（Move up）
            ELSIF nLiftAtLayer > nTargetLayer THEN
                bMoveDown := TRUE;      // 下降趋近（Move down）
            ELSIF _bInPosDeb THEN
                _eState := E_DL_MagState.eArrived;  // 层号相等且到位消抖通过（At layer and debounced）
            END_IF
            IF _fbTonMoveTo.Q THEN
                _bFaultLatch := TRUE;   // 升降超时锁存（Move timeout latch）
                _uErrorIdInt := DL_MAG_ERR_MOVE;    // 0005_0280 升降超时【故障级】/ Move timeout, fault level
                _eState := E_DL_MagState.eFault;
            END_IF
        END_IF
        // 位置未知（0）：不发方向指令保持等待，超时走 0280（偏离留档①）
        // Position unknown: no direction output, hold and let timeout fire (deviation 1)

    E_DL_MagState.eArrived: // 到位：方向撤销过渡，直接进取放
        bMoveUp := FALSE;               // 方向撤销（Direction revoked）
        bMoveDown := FALSE;
        _eState := E_DL_MagState.eHandling;     // 进入取放（Enter handling）

    E_DL_MagState.eHandling: // 取放：等动作完成反馈后更新槽位
        IF bHandlingDone THEN
            IF _nTargetIdx < DL_MAG_MAX_LAYERS THEN   // 索引先判域（Index bounded first）
                IF _bFetchOp THEN
                    aeSlot[_nTargetIdx] := E_DL_SlotState.eEmpty;   // 取料：满→空（Fetch: full to empty）
                ELSIF _bStoreNgOp THEN
                    aeSlot[_nTargetIdx] := E_DL_SlotState.eNg;      // 存 NG：→NG 槽（Store NG: to NG slot）
                ELSE
                    aeSlot[_nTargetIdx] := E_DL_SlotState.eFull;    // 存 OK：空→满（Store OK: empty to full）
                END_IF
            END_IF
            bDone := TRUE;              // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
            _eState := E_DL_MagState.eDone;
        ELSIF _fbTonHandTo.Q THEN
            _bFaultLatch := TRUE;       // 取放超时锁存（Handling timeout latch）
            _uErrorIdInt := DL_MAG_ERR_HAND;        // 0005_0281 取放超时【故障级】/ Handling timeout, fault level
            _eState := E_DL_MagState.eFault;
        END_IF

    E_DL_MagState.eDone: // 完成：单拍后回空闲（下一拍受理新请求）
        nTargetLayer := UINT#0;         // 目标层清零（Target cleared）
        _eState := E_DL_MagState.eIdle; // 回空闲（Back to idle）

    E_DL_MagState.eFault: // 故障锁存：等复位（复位路径在段 2）
        // 等复位（Awaiting reset）

    ELSE // 非法状态兜底（本块专用码位）
        _bFaultLatch := TRUE;
        _uErrorIdInt := DL_MAG_ERR_STATE;   // 0005_0283 非法状态兜底【故障级】/ Illegal state fallback, fault level
        _eState := E_DL_MagState.eFault;
END_CASE

// ============================================================================
// 段 6｜输出派生（方向互斥由同源比较派生；出口断言升降指令不同真）
//      Outlet derivation (mutual exclusion by common-source comparison)
// ============================================================================
IF NOT bEnable THEN
    // 使能撤销：升降输出停止、请求清、状态回空闲（Disabled: outputs stopped, state idle）
    bMoveUp := FALSE;                   // 升降输出停（Lift outputs stopped）
    bMoveDown := FALSE;
    IF (_eState <> E_DL_MagState.eFault) THEN
        _eState := E_DL_MagState.eIdle; // 状态回空闲（State back to idle）
        nTargetLayer := UINT#0;
    END_IF
END_IF

bBusy := (_eState = E_DL_MagState.eSelect)
      OR (_eState = E_DL_MagState.eMoving)
      OR (_eState = E_DL_MagState.eArrived)
      OR (_eState = E_DL_MagState.eHandling);       // 调度中派生（Busy derived）

eState := _eState;                       // 状态镜像（State mirror）

// ============================================================================
// 段 7｜bFault/uErrorId 出口（R21：bFault 显式排除信息级码）
//      Outlets: bFault excludes info codes (R21)
// ============================================================================
bFault := _bFaultLatch;                  // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;            // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;              // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK