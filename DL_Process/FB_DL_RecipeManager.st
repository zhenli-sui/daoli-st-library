(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RecipeManager
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 分类     (Category)   : 工艺段功能块（Function Block · 通用配方管理器）
 * 功能简述 (Function)   : 以「参数清单 + 值集 + 校验和」承载多品种配方：选择、
 *                         校验、应用（写入运行参数）、写回（采集当前参数为
 *                         新配方）、切换防呆（仅机台稳态允许）、变更审计（次
 *                         数 + 注入时间戳）。零文件 I/O、零全局耦合——配方库
 *                         与运行参数均为引脚注入的数组，持久化由调用方自行完
 *                         成；校验和为自包含 32 位滚动异或累加，本块不伪造校
 *                         验和（写回时清零，由调用方重新生成）。
 * 首扫说明 (Init note)  : 纯事件型组件，免首扫（R23/公约 0.1），无 bInit；
 *                         所有状态由指令沿驱动。
 * 公约遵循 (Convention) : 0.2/R21 bError 为显式排除信息级码的派生式；0.4 双语
 *                         同行注释；0.5/R7 实例主体最前部无条件刷新；0.7/R15
 *                         故障锁存仅复位路径清码、信息级瞬时型；0.8 码位段
 *                         16#0005_xxxx（经 DL_Process VERSION.md 复核，本块
 *                         0140~0143 / 0240~0246 无冲突）；0.14 数组存取先判
 *                         域再索引、除法前判零（进度类运算无除法）；0.16 无
 *                         魔法数；0.17 终结符成对 ✓；0.18 ST_DL_RecipeEntry
 *                         与 E_DL_RecipeState 随本块同文件发布；0.19 码位同
 *                         行【级别】注释；0.20 验收向量入头注释；R25 bDone
 *                         单拍生命周期三律。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 越界/非有限值/校验和防御 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 五实例（R_TRIG×4）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓｜R25 单拍标志生命周期三律 ✓
 * 设计要点 (Key notes)  : ① 校验链（eValidating）：配方号域内 → 配方启用 →
 *                           参数个数一致 → 逐参数非有限值 → 逐参数上下限 →
 *                           校验和比对，任一失败锁存对应故障级码；
 *                         ② 应用（eApplying）单拍全量写入 afParamActual，防
 *                           半套参数生效；复核（eVerifying）回读重算校验和比
 *                           对，失败判写入异常 0245；
 *                         ③ 写回（Save）：运行参数拷入配方、个数同步、校验和
 *                           清零（本块不伪造校验和，调用方持久化前须重算）；
 *                         ④ 切换防呆：bMachineStopped=FALSE 时加载拒绝（信
 *                           息码 0141，不置故障，属正常联锁）；Load/Save 同
 *                           拍双丢弃（信息码 0142，"不猜"原则）；
 *                         ⑤ bParamOutOfRange 为瞬时型每拍重算（对当前选中配
 *                           方值集逐参数复核上下限），nOutOfRangeIndex 指向
 *                           首个越界参数；
 *                         ⑥ 数组维度字面量 16（等同 DL_RECIPE_MAX_PARAM）/32
 *                           （等同 DL_RECIPE_MAX_COUNT）与常量同步维护（跨
 *                           平台数组维度须编译期字面量，运行期域检查用常量）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 校验和算法二选一裁定：规格允许复用 DL_Base 既有
 *                           CRC 函数或自包含算法；本块选自包含 32 位滚动异或
 *                           累加（uSum := (uSum XOR SHL(uSum,5)) +
 *                           REAL_TO_UDINT(v×1000.0 + 1.0E9)，正偏置保证折叠
 *                           项非负、避免负值参数取整的平台回绕歧义；取整语义
 *                           依平台四舍五入）。理由：保持本文件零跨子库依赖，
 *                           可单独导入；影响：与上层持久化校验格式必须一致
 *                           （调用方生成校验和时用同一含偏置算法），头注释已
 *                           声明。
 * 开源溯源 (Origin)     : 来源标签 codesys-forge / recipe-management
 *                         （RAW_NOTES_R8 S-6，T1-4 CODESYS Forge 首次开组：
 *                         公开配方管理示例——配方名/启用/参数值集/校验和的组
 *                         织分类与「校验→应用→复核」相语义，公开开源示例，
 *                         仅借鉴分类与参数域；结构体字段、状态机、码位、引脚
 *                         契约 100% 本库独立设计，clean-room 未复制源码。
 *                         许可证说明：借鉴对象为公开社区示例，本文件为本库原
 *                         创实现，随本库许可证发布）。
 * 验收向量 (Acceptance) :
 *   V1 正常 Load（3 参数，域内）→ bLoaded/eDone、uActiveChecksum 正确、
 *      uChangeCount +1、tLastChange 等于注入 tNow；
 *   V2 参数越界 → 故障 0243 + nOutOfRangeIndex 指向首个越界项；
 *   V3 校验和不匹配 → 0244（配方损坏）；
 *   V4 bMachineStopped=FALSE 加载 → 拒绝 + 信息码 0141（不置故障）；
 *   V5 Save 后 uChangeCount +1、配方值集与个数同步、uChecksum 清零；
 *   V6 Load+Save 同拍 → 双丢弃 + 信息码 0142；
 *   V7 配方参数含非有限值 → 0242；
 *   V8 配方号越界/未启用 → 0240。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Process 配方管理件）
 *   2026-11-15  v1.0.1  R8 总监终审修复：终端态分支内的孤立空语句 `;`（非 IEC 61131-3 文法，statement_list 允许零条语句但不容纳孤立分号）改为纯注释占位分支，行为等价、跨平台可移植性合规。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_RecipeEntry（归属 FB_DL_RecipeManager，与其同文件发布）
 *         值集维度字面量 16 等同 DL_RECIPE_MAX_PARAM，须与常量同步维护。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_RecipeEntry :
STRUCT
    sName        : STRING[32];                    // 配方名（Recipe name）/ Recipe name
    bEnabled     : BOOL;                          // 配方启用（Enabled），FALSE 时选中即判故障 / Recipe enabled flag
    nParamCount  : UINT;                          // 有效参数个数（Active param count）[-]，域 0..16 / Active parameter count
    afValue      : ARRAY[0..15] OF REAL;          // 参数值集（Parameter values），维度 16 等同 DL_RECIPE_MAX_PARAM / Parameter values, dim 16
    uChecksum    : UDINT;                         // 校验和（Checksum），0=未启用校验；由调用方生成、本块只比对 / Checksum, 0 = verification off, caller generates
END_STRUCT
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RecipeState（归属 FB_DL_RecipeManager，与其同文件发布）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RecipeState :
(
    eIdle       := 0,   // 空闲：等操作沿 / Idle, awaiting operation edge
    eValidating := 10,  // 校验中：选择域/启用/个数/数值域/校验和逐项过链 / Validating selection, enable, count, ranges and checksum
    eApplying   := 20,  // 应用中：加载全量写入运行参数 / 写回采集参数入配方 / Applying, load writes parameters or save collects them
    eVerifying  := 30,  // 复核中：回读运行参数重算校验和比对 / Verifying, read-back checksum comparison
    eDone       := 40,  // 完成：结果保持，等下一操作沿 / Done, results held awaiting next operation
    eFault      := 99   // 故障锁存：仅复位沿退出 / Fault latched, only reset edge exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_RecipeManager
VAR_INPUT
    bEnable             : BOOL;             // 使能（Enable），FALSE=中止操作并保持当前运行参数不变 / Enable, FALSE aborts and keeps live parameters
    bLoad               : BOOL;             // 加载所选配方到运行参数（Load），上升沿受理 / Load edge applies selected recipe
    bSave               : BOOL;             // 把当前运行参数写回所选配方（Save/Teach），上升沿受理 / Save edge teaches live parameters into recipe
    bValidate           : BOOL;             // 仅校验不应用（Validate），上升沿受理，结果出 bValid / Validate edge, result in bValid
    bMachineStopped     : BOOL := TRUE;     // 机台稳态确认（Machine stopped），FALSE 时拒绝加载（切换防呆）/ Machine stopped interlock, FALSE rejects load
    bReset              : BOOL;             // 复位故障（Fault reset），上升沿受理 / Rising edge resets fault
    nSelectRecipe       : UINT;             // 选中配方号（Selected recipe index）[-]，域 0..DL_RECIPE_MAX_COUNT-1 / Selected recipe index
    nParamCount         : UINT := 1;        // 本机参数个数（Param count）[-]，域 1..DL_RECIPE_MAX_PARAM，越界钳位 / Machine parameter count, clamped
    afParamMin          : ARRAY[0..15] OF REAL; // 参数下限（Param lower limits），逐项与配方值比较；min ≥ max 视为该参数未启用校验 / Param lower limits, min ≥ max disables that check
    afParamMax          : ARRAY[0..15] OF REAL; // 参数上限（Param upper limits），与下限配对使用 / Param upper limits paired with lower
    tNow                : TIME := T#0S;     // 时间戳注入（Timestamp injection）[ms]，禁读 CPU 钟，用于审计记录 / Injected timestamp for audit, CPU clock never read
END_VAR
VAR_OUTPUT
    bLoaded             : BOOL;             // 加载完成（Loaded），完成态且操作为 Load 时为 TRUE / TRUE while done with load operation
    bSaved              : BOOL;             // 写回完成（Saved），完成态且操作为 Save 时为 TRUE / TRUE while done with save operation
    bValid              : BOOL;             // 校验通过（Valid），校验型操作结果，保持到下次操作 / Validation verdict held until next operation
    bParamOutOfRange    : BOOL;             // 存在越界参数（Out of range），瞬时型每拍重算 / Transient out-of-range flag, recomputed each scan
    nOutOfRangeIndex    : UINT;             // 首个越界参数索引（First bad index）[-]，越界标志有效时成立 / First out-of-range parameter index
    nActiveRecipe       : UINT;             // 当前生效配方号（Active recipe）[-] / Currently applied recipe index
    uActiveChecksum     : UDINT;            // 当前运行参数校验和（Active checksum），每拍重算供上层比对 / Live parameter checksum recomputed each scan
    uChangeCount        : UDINT;            // 配方变更次数（Change counter），每次成功 Load/Save +1 / Successful load/save counter
    tLastChange         : TIME := T#0S;     // 末次变更时间戳（Last change time），取注入 tNow / Last change timestamp from injected tNow
    bBusy               : BOOL;             // 执行中（Busy），校验/应用/复核态为 TRUE / TRUE while validating/applying/verifying
    bDone               : BOOL;             // 操作完成单拍脉冲（Done pulse），单拍生命周期三律 / One-scan operation done pulse
    bError              : BOOL;             // 故障锁存（Error），仅故障级码置位 / Latched error, fault codes only
    uErrorId            : UDINT;            // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, fault-level priority
END_VAR
VAR_IN_OUT
    astRecipe           : ARRAY[0..31] OF ST_DL_RecipeEntry; // 配方库（Recipe library），维度 32 等同 DL_RECIPE_MAX_COUNT，调用方持有与持久化 / Recipe library owned and persisted by caller
    afParamActual       : ARRAY[0..15] OF REAL; // 当前运行参数（Live parameters），维度 16，Save 被读 / Load 被写 / Live parameters, read on save, written on load
END_VAR
VAR
    _eState             : E_DL_RecipeState := E_DL_RecipeState.eIdle; // 内部状态机（Internal state）/ Internal state
    _nOp                : USINT;            // 当前操作类型（Operation type）[-]，1=Load 2=Save 3=Validate，0=无 / Operation type register
    _bFaultLatch        : BOOL;             // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt        : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode          : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code
    _nParamEff          : UINT;             // 生效参数个数（Effective param count），钳位后值 / Clamped effective parameter count
    _nSelEff            : UINT;             // 生效配方号（Effective recipe index），域校验后值 / Validated recipe index
    _fV                 : REAL;             // 循环内当前参数值（Loop value scratch）/ Loop parameter value scratch
    _bFinite            : BOOL;             // 非有限值检测结果（Finite check verdict）/ Finite-value check verdict
    _uSum               : UDINT;            // 校验和累加器（Checksum accumulator）/ Checksum accumulator
    _uTargetCk          : UDINT;            // 目标配方校验和（Target recipe checksum）/ Target recipe checksum
    _nIdx               : UINT;             // 循环索引（Loop index）[-] / Loop index
    _bBadIdxFound       : BOOL;             // 越界首索引已记录（First bad index found）/ First bad index recorded flag
    _bValOk             : BOOL;             // 校验链通过（Validation chain passed）/ Validation chain verdict
    _fbTrigLoad         : R_TRIG;           // 加载沿（Load edge detector）/ Load edge detector
    _fbTrigSave         : R_TRIG;           // 写回沿（Save edge detector）/ Save edge detector
    _fbTrigValidate     : R_TRIG;           // 校验沿（Validate edge detector）/ Validate edge detector
    _fbTrigReset        : R_TRIG;           // 复位沿（Reset edge detector）/ Reset edge detector
END_VAR
VAR CONSTANT
    DL_RECIPE_MAX_PARAM : UINT := 16;       // 单配方参数上限（Max params per recipe）[-]，与数组维度字面量 16 同步 / Max params, sync with literal dim 16
    DL_RECIPE_MAX_COUNT : UINT := 32;       // 配方库容量上限（Max recipe count）[-]，与数组维度字面量 32 同步 / Max recipes, sync with literal dim 32
    DL_RECIPE_REAL_MAX  : REAL := 3.4E38;   // 单精度有限值判据幅值（Finite magnitude bound），超出或非数均拒绝 / Finite magnitude bound for REAL inputs
    DL_RECIPE_EPS       : REAL := 1.0E-6;   // 浮点通用容差（General float epsilon）/ General float epsilon
    DL_RECIPE_VERIFY_EPS: REAL := 1.0E-3;   // 复核逐参数容差（Verify per-param epsilon），千分之一工程单位 / Verify tolerance per parameter
    DL_RECIPE_SCALE     : REAL := 1000.0;   // 校验和定标系数（Checksum scale）[-]，值×此系数取整入校验和 / Checksum scale factor for fixed-point fold
    DL_RECIPE_BIAS      : REAL := 1.0E9;    // 校验和正偏置（Checksum positive bias），保证折叠项非负、跨平台回绕确定 / Positive bias keeps fold term non-negative, portable
    DL_RECIPE_CHK_ROL   : DINT := 5;        // 校验和滚动移位量（Checksum shift amount）[-] / Checksum rolling shift amount
    DL_RECIPE_OP_LOAD   : USINT := 1;       // 操作码：加载（Op code: load）/ Op code load
    DL_RECIPE_OP_SAVE   : USINT := 2;       // 操作码：写回（Op code: save）/ Op code save
    DL_RECIPE_OP_VALID  : USINT := 3;       // 操作码：仅校验（Op code: validate only）/ Op code validate-only
    DL_RECIPE_ERR_SEL   : UDINT := 16#0005_0240; // 0005_0240 配方号越界/未启用【故障级】/ Bad recipe index or disabled, fault level
    DL_RECIPE_ERR_CNT   : UDINT := 16#0005_0241; // 0005_0241 参数个数与配方定义不一致【故障级】/ Param count mismatch, fault level
    DL_RECIPE_ERR_NAN   : UDINT := 16#0005_0242; // 0005_0242 配方参数含非有限值【故障级】/ Non-finite recipe parameter, fault level
    DL_RECIPE_ERR_RANGE : UDINT := 16#0005_0243; // 0005_0243 参数越界【故障级】/ Parameter out of range, fault level
    DL_RECIPE_ERR_CKSUM : UDINT := 16#0005_0244; // 0005_0244 校验和不匹配（配方损坏）【故障级】/ Checksum mismatch, recipe corrupted, fault level
    DL_RECIPE_ERR_VERIFY: UDINT := 16#0005_0245; // 0005_0245 应用后复核失败【故障级】/ Post-apply verify failed, fault level
    DL_RECIPE_ERR_STATE : UDINT := 16#0005_0246; // 0005_0246 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_RECIPE_INFO_NOCK : UDINT := 16#0005_0140; // 0005_0140 配方未启用校验和（uChecksum=0）【信息级】/ Checksum disabled (zero), info level
    DL_RECIPE_INFO_LOCK : UDINT := 16#0005_0141; // 0005_0141 机台非稳态，加载被拒【信息级】/ Load rejected, machine not stopped, info level
    DL_RECIPE_INFO_CONF : UDINT := 16#0005_0142; // 0005_0142 Load/Save 同拍冲突，双丢弃【信息级】/ Load/save edge conflict, both dropped, info level
    DL_RECIPE_INFO_CLAMP: UDINT := 16#0005_0143; // 0005_0143 参数个数越界钳位【信息级】/ Param count clamped, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigLoad(CLK := bLoad);              // 加载沿（Load edge）
_fbTrigSave(CLK := bSave);              // 写回沿（Save edge）
_fbTrigValidate(CLK := bValidate);      // 校验沿（Validate edge）
_fbTrigReset(CLK := bReset);            // 复位沿（Reset edge）

// ============================================================================
// 段 2｜信息级预清零 + 单拍标志预清零 + 参数防御（R25/R15）
//      Info preset + one-shot preset + parameter defense (R25/R15)
// ============================================================================
_uInfoCode := 0;                        // 信息级瞬时型每拍重算（Transient info recomputed each scan）
bDone := FALSE;                         // 完成单拍先清零（R25：置位-消费-复位同周期闭环）/ Done pulse preset FALSE (R25 lifecycle)

// 参数个数钳位（Param count clamp，域 1..16）
IF nParamCount < UINT#1 THEN
    _nParamEff := UINT#1;               // 下限钳位（Lower clamp）
    _uInfoCode := DL_RECIPE_INFO_CLAMP; // 0005_0143 参数个数越界钳位【信息级】/ Count clamped, info level
ELSIF nParamCount > DL_RECIPE_MAX_PARAM THEN
    _nParamEff := DL_RECIPE_MAX_PARAM;  // 上限钳位（Upper clamp）
    _uInfoCode := DL_RECIPE_INFO_CLAMP; // 0005_0143 参数个数越界钳位【信息级】/ Count clamped, info level
ELSE
    _nParamEff := nParamCount;          // 引脚原值（Pin value as-is）
END_IF

// 复位路径：仅此路径可清故障锁存（R15）
IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;              // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000;       // 故障码清零（Fault code cleared）
    IF _eState = E_DL_RecipeState.eFault THEN
        _eState := E_DL_RecipeState.eIdle; // 故障态回空闲（Fault state back to idle）
    END_IF
END_IF

// ============================================================================
// 段 3｜每拍瞬态复核：运行参数校验和 + 越界扫描（对当前选中配方）
//      Per-scan transient: live checksum + out-of-range scan on selected recipe
// ============================================================================
uActiveChecksum := 16#0000_0000;        // 校验和累加器清零（Checksum accumulator reset）
FOR _nIdx := UINT#0 TO _nParamEff - UINT#1 DO
    _fV := afParamActual[_nIdx];        // 索引域已由 _nParamEff 钳位保证（Index bounded by clamped count）
    uActiveChecksum := (uActiveChecksum XOR SHL(uActiveChecksum, DL_RECIPE_CHK_ROL))
                  + REAL_TO_UDINT(_fV * DL_RECIPE_SCALE + DL_RECIPE_BIAS);   // 滚动异或累加 + 正偏置保证非负折叠（偏离留档①算法）/ Rolling XOR fold with positive bias (deviation 1)
END_FOR

bParamOutOfRange := FALSE;              // 越界标志瞬态预清零（Transient flag preset）
nOutOfRangeIndex := UINT#0;             // 首个越界索引预清零（First bad index preset）
IF nSelectRecipe < DL_RECIPE_MAX_COUNT THEN
    IF (astRecipe[nSelectRecipe].nParamCount >= UINT#1)
      AND (astRecipe[nSelectRecipe].nParamCount <= DL_RECIPE_MAX_PARAM) THEN
        FOR _nIdx := UINT#0 TO astRecipe[nSelectRecipe].nParamCount - UINT#1 DO
            _fV := astRecipe[nSelectRecipe].afValue[_nIdx];      // 配方值（Recipe value）
            IF (afParamMin[_nIdx] < afParamMax[_nIdx])
              AND ((_fV < afParamMin[_nIdx]) OR (_fV > afParamMax[_nIdx]))
              AND (NOT bParamOutOfRange) THEN
                bParamOutOfRange := TRUE;            // 越界成立（Out of range found）
                nOutOfRangeIndex := _nIdx;           // 首个越界索引（First bad index）
            END_IF
        END_FOR
    END_IF
END_IF

// ============================================================================
// 段 4｜操作受理（仅在空闲/完成态受理指令沿；同拍冲突双丢弃）
//      Operation acceptance at idle/done; same-cycle conflict drops both
// ============================================================================
IF bEnable AND (( _eState = E_DL_RecipeState.eIdle)
             OR (_eState = E_DL_RecipeState.eDone)) THEN
    IF _fbTrigLoad.Q AND _fbTrigSave.Q THEN
        _uInfoCode := DL_RECIPE_INFO_CONF;  // 0005_0142 Load/Save 同拍冲突双丢弃【信息级】/ Edge conflict, both dropped
    ELSIF _fbTrigLoad.Q THEN
        IF bMachineStopped THEN
            _nOp := DL_RECIPE_OP_LOAD;      // 登记加载操作（Register load operation）
            _eState := E_DL_RecipeState.eValidating;
        ELSE
            _uInfoCode := DL_RECIPE_INFO_LOCK; // 0005_0141 机台非稳态加载被拒【信息级】/ Load rejected, machine running
        END_IF
    ELSIF _fbTrigSave.Q THEN
        _nOp := DL_RECIPE_OP_SAVE;          // 登记写回操作（Register save operation）
        _eState := E_DL_RecipeState.eValidating;
    ELSIF _fbTrigValidate.Q THEN
        _nOp := DL_RECIPE_OP_VALID;         // 登记校验操作（Register validate operation）
        _eState := E_DL_RecipeState.eValidating;
    END_IF
END_IF

// ============================================================================
// 段 5｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
CASE _eState OF

    E_DL_RecipeState.eIdle: // 空闲：等操作沿（受理逻辑在段 4）
        // 无动作（No action）

    E_DL_RecipeState.eValidating: // 校验链：域 → 启用 → 个数 → 非有限值 → 上下限 → 校验和
        _bValOk := TRUE;                    // 校验链初始通过（Chain starts valid）
        // ① 配方号域内（Index in domain）
        IF nSelectRecipe >= DL_RECIPE_MAX_COUNT THEN
            _bValOk := FALSE;
            _bFaultLatch := TRUE;
            _uErrorIdInt := DL_RECIPE_ERR_SEL;   // 0005_0240 配方号越界【故障级】/ Bad recipe index, fault level
        ELSE
            _nSelEff := nSelectRecipe;           // 生效配方号登记（Register effective index）
            // ② 配方启用（Recipe enabled）
            IF NOT astRecipe[_nSelEff].bEnabled THEN
                _bValOk := FALSE;
                _bFaultLatch := TRUE;
                _uErrorIdInt := DL_RECIPE_ERR_SEL; // 0005_0240 配方未启用【故障级】/ Recipe disabled, fault level
            END_IF
        END_IF

        IF _bValOk THEN
            // ③ 参数个数一致（Load/Validate 要求；Save 允许覆盖定义）
            IF (_nOp <> DL_RECIPE_OP_SAVE)
              AND (astRecipe[_nSelEff].nParamCount <> _nParamEff) THEN
                _bValOk := FALSE;
                _bFaultLatch := TRUE;
                _uErrorIdInt := DL_RECIPE_ERR_CNT;   // 0005_0241 个数与配方定义不一致【故障级】/ Count mismatch, fault level
            END_IF
        END_IF

        IF _bValOk AND (_nOp <> DL_RECIPE_OP_SAVE) THEN
            _uTargetCk := 16#0000_0000;          // 目标校验和累加器（Target checksum accumulator）
            FOR _nIdx := UINT#0 TO _nParamEff - UINT#1 DO
                _fV := astRecipe[_nSelEff].afValue[_nIdx];    // 配方值（Recipe value）
                _bFinite := (_fV >= (-DL_RECIPE_REAL_MAX)) AND (_fV <= DL_RECIPE_REAL_MAX); // 非有限值自比等价式（Finite check）
                IF NOT _bFinite THEN
                    _bValOk := FALSE;
                    _bFaultLatch := TRUE;
                    _uErrorIdInt := DL_RECIPE_ERR_NAN;        // 0005_0242 参数含非有限值【故障级】/ Non-finite parameter, fault level
                ELSIF (afParamMin[_nIdx] < afParamMax[_nIdx])
                  AND ((_fV < afParamMin[_nIdx]) OR (_fV > afParamMax[_nIdx])) THEN
                    _bValOk := FALSE;
                    _bFaultLatch := TRUE;
                    _uErrorIdInt := DL_RECIPE_ERR_RANGE;      // 0005_0243 参数越界【故障级】/ Parameter out of range, fault level
                    nOutOfRangeIndex := _nIdx;                // 首个越界索引（First bad index）
                END_IF
                _uTargetCk := (_uTargetCk XOR SHL(_uTargetCk, DL_RECIPE_CHK_ROL))
                         + REAL_TO_UDINT(_fV * DL_RECIPE_SCALE + DL_RECIPE_BIAS);   // 同算法重算目标校验和（Target checksum recomputed, same algorithm）
            END_FOR
            // ⑤ 校验和比对（=0 视为未启用校验）
            IF _bValOk THEN
                IF astRecipe[_nSelEff].uChecksum = 16#0000_0000 THEN
                    _uInfoCode := DL_RECIPE_INFO_NOCK;    // 0005_0140 未启用校验和【信息级】/ Checksum disabled, info level
                ELSIF astRecipe[_nSelEff].uChecksum <> _uTargetCk THEN
                    _bValOk := FALSE;
                    _bFaultLatch := TRUE;
                    _uErrorIdInt := DL_RECIPE_ERR_CKSUM;  // 0005_0244 校验和不匹配（配方损坏）【故障级】/ Checksum mismatch, fault level
                END_IF
            END_IF
        END_IF

        // 校验链出口分派（Chain exit dispatch）
        IF _bValOk THEN
            IF _nOp = DL_RECIPE_OP_LOAD THEN
                _eState := E_DL_RecipeState.eApplying;    // 进入应用（Proceed to apply）
            ELSIF _nOp = DL_RECIPE_OP_SAVE THEN
                _eState := E_DL_RecipeState.eApplying;    // 写回也走应用相（Save proceeds to apply phase）
            ELSE
                bValid := TRUE;                           // 仅校验：结果通过（Validate-only passed）
                bDone := TRUE;                            // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
                _eState := E_DL_RecipeState.eDone;
            END_IF
        ELSE
            _eState := E_DL_RecipeState.eFault;           // 校验失败进故障锁存（Validation failed, latch fault）
        END_IF

    E_DL_RecipeState.eApplying: // 应用：Load 单拍全量写入 / Save 单拍全量采集
        IF _nOp = DL_RECIPE_OP_LOAD THEN
            FOR _nIdx := UINT#0 TO _nParamEff - UINT#1 DO
                _fV := astRecipe[_nSelEff].afValue[_nIdx];    // 源：配方值（Source: recipe value）
                _bFinite := (_fV >= (-DL_RECIPE_REAL_MAX)) AND (_fV <= DL_RECIPE_REAL_MAX);
                IF _bFinite THEN
                    afParamActual[_nIdx] := _fV;              // 单拍全量写入（Single-scan bulk write, no half-set applied）
                END_IF
            END_FOR
            _eState := E_DL_RecipeState.eVerifying;           // 进入复核（Proceed to verify）
        ELSE
            FOR _nIdx := UINT#0 TO _nParamEff - UINT#1 DO
                astRecipe[_nSelEff].afValue[_nIdx] := afParamActual[_nIdx]; // 单拍全量采集（Single-scan bulk collect）
            END_FOR
            astRecipe[_nSelEff].nParamCount := _nParamEff;    // 个数同步（Count synchronized）
            astRecipe[_nSelEff].uChecksum := 16#0000_0000;    // 校验和清零：本块不伪造，调用方须重算（Checksum zeroed, caller regenerates）
            uChangeCount := uChangeCount + UINT#1;            // 审计计数（Audit counter）
            tLastChange := tNow;                              // 审计时间戳取注入值（Audit timestamp from injected pin）
            nActiveRecipe := _nSelEff;                        // 生效配方号登记（Active recipe registered）
            bSaved := TRUE;                                   // 写回完成保持（Saved held）
            bDone := TRUE;                                    // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
            _eState := E_DL_RecipeState.eDone;
        END_IF

    E_DL_RecipeState.eVerifying: // 复核：回读运行参数与目标比对（防写入异常）
        IF astRecipe[_nSelEff].uChecksum <> 16#0000_0000 THEN
            IF uActiveChecksum <> astRecipe[_nSelEff].uChecksum THEN
                _bFaultLatch := TRUE;
                _uErrorIdInt := DL_RECIPE_ERR_VERIFY;         // 0005_0245 复核失败（写入异常）【故障级】/ Verify failed, fault level
                _eState := E_DL_RecipeState.eFault;
            ELSE
                nActiveRecipe := _nSelEff;                    // 生效配方号登记（Active recipe registered）
                uChangeCount := uChangeCount + UINT#1;        // 审计计数（Audit counter）
                tLastChange := tNow;                          // 审计时间戳（Audit timestamp）
                bLoaded := TRUE;                              // 加载完成保持（Loaded held）
                bDone := TRUE;                                // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
                _eState := E_DL_RecipeState.eDone;
            END_IF
        ELSE
            // 目标未启用校验和：逐参数容差比对兜底（Checksum off: element-wise tolerance fallback）
            FOR _nIdx := UINT#0 TO _nParamEff - UINT#1 DO
                IF ABS(afParamActual[_nIdx] - astRecipe[_nSelEff].afValue[_nIdx]) > DL_RECIPE_VERIFY_EPS THEN
                    _bFaultLatch := TRUE;
                    _uErrorIdInt := DL_RECIPE_ERR_VERIFY;     // 0005_0245 复核失败【故障级】/ Verify failed, fault level
                    _eState := E_DL_RecipeState.eFault;
                END_IF
            END_FOR
            IF NOT _bFaultLatch THEN
                nActiveRecipe := _nSelEff;
                uChangeCount := uChangeCount + UINT#1;
                tLastChange := tNow;
                bLoaded := TRUE;                              // 加载完成保持（Loaded held）
                bDone := TRUE;                                // 完成单拍（R25）/ Done pulse (R25)
                _eState := E_DL_RecipeState.eDone;
            END_IF
        END_IF

    E_DL_RecipeState.eDone: // 完成：结果保持，下一操作沿回空闲（受理逻辑在段 4，下一拍起效）
        IF _fbTrigLoad.Q OR _fbTrigSave.Q OR _fbTrigValidate.Q THEN
            _eState := E_DL_RecipeState.eIdle;                // 让位新操作（Yield to new operation）
            bLoaded := FALSE;                                 // 结果锁存随让位清零（Result holds released）
            bSaved := FALSE;
            bValid := FALSE;
        END_IF

    E_DL_RecipeState.eFault: // 故障锁存：等复位（复位路径在段 2）
        // 等复位（Awaiting reset）

    ELSE // 非法状态兜底（本块专用码位）
        _bFaultLatch := TRUE;
        _uErrorIdInt := DL_RECIPE_ERR_STATE;                  // 0005_0246 非法状态兜底【故障级】/ Illegal state fallback, fault level
        _eState := E_DL_RecipeState.eFault;
END_CASE

// ============================================================================
// 段 6｜使能撤销与出口派生（R21）
//      Enable teardown and outlet derivation (R21)
// ============================================================================
IF NOT bEnable THEN
    // 撤销进行中操作，运行参数保持不变（Abort in-flight ops, live parameters untouched）
    IF (_eState = E_DL_RecipeState.eValidating)
     OR (_eState = E_DL_RecipeState.eApplying)
     OR (_eState = E_DL_RecipeState.eVerifying) THEN
        _eState := E_DL_RecipeState.eIdle;   // 中途回空闲（Back to idle mid-flight）
    END_IF
END_IF

bBusy := (_eState = E_DL_RecipeState.eValidating)
      OR (_eState = E_DL_RecipeState.eApplying)
      OR (_eState = E_DL_RecipeState.eVerifying);            // 执行中派生（Busy derived）

bError := _bFaultLatch;                      // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;                // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;                  // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK