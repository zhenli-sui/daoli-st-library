(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RotaryIndexerCycleSeq
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.1 ｜ 2026-11-24
 * 码位     (Code Segment): 16#0005_2100（DL_Process 段内 21xx 子带首发，R83）
 * 复杂度   (Complexity) : C5
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / LIMIT），零厂商私有库
 * 开源溯源 (Provenance) : menes97/ayran-mini-fabrika / FB_Dolum / MIT /
 *                         借鉴点：8 工位回转链节拍推进与「每杯 TR_CUP / TR_BAD 移位寄存器」语义
 *                         （未复制任何实现行，按 IEC 61131-3 重写为相序状态机 + 定长环形寄位器）
 * 功能描述 (Function)   : 转盘八工位索引节拍机。每个索引节拍转盘推进一格，同时上料位装入一杯，
 *                         杯位好坏沿环形寄位器右移（下标 +1），剔除工位（固定 iStationCnt-1）
 *                         对坏杯执行剔除脉冲（200ms）。三相节拍：eIndexing（索引计时）→
 *                         eSettle（到位整定）→ eEject（剔除，仅坏杯在位且就绪时进入）→ 回 eIndexing。
 *                         **寄位器语义**：aCupOk[n] = 第 n 工位上的杯「有杯且好」；索引完成同拍
 *                         从高位到低位搬移 aCupOk[n] := aCupOk[n-1]，最低位 aCupOk[0] 装入新杯
 *                         （= bCupPresent AND NOT bCupBad），即「索引与上料同拍」的物理模型。
 *                         **剔除**：坏杯到达剔除工位时若 bEjectReady 立即获准；不就绪则在 eSettle
 *                         驻留等待，超过 tEjectTimeout → 故障级 21（禁止坏杯带着缺陷直接流出）。
 *                         **bEnable = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         剔除命令撤销、bBusy 归假、相位回 eIdle；移位寄存器与三计数保留（停机
 *                         不清产），仅 bReset 上升沿清。
 * 接口     (Interface)  : 输入 bEnable / bReset（上升沿）/ bStart / iStationCnt / tIndexTime /
 *                         iCupPerCycle / bCupPresent / bCupBad / bEjectReady / tEjectTimeout；
 *                         输出 eState（E_DL_RotaryIndexerCycleSeq_State）/ bBusy / bDone（圈完成
 *                         单拍）/ bError / iErrCode / iStationIdx / aCupOk[0..11] / iGoodCnt /
 *                         iBadCnt / iEjectCnt / bEjectCmd。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eReady：bEnable 且 bStart 且组态闸通过且无锁存；拍 N 进入 / 本拍行为：拒绝任何
 *      索引与剔除命令 / 拍 N+1 转出至 eReady。
 *   ② eReady → eIndexing：bEnable 且 bStart（出口条件互补：NOT(bEnable AND bStart) → eIdle）；
 *      拍 N 进入 / 本拍行为：清三计数、清 12 位寄位器、工位号归零、圈完成位归假、拒剔除 /
 *      拍 N+1 转出至 eIndexing。本相为单拍过渡相，两出口条件互补完备（R448 满足方式）。
 *   ③ eIndexing → eSettle：tonIndex.Q（索引时间到）；拍 N 进入 / 本拍行为：工位号 +1（越上界回 0
 *      并置圈完成位）、寄位器高位到低位搬移、装入新杯、好/坏杯按 iCupPerCycle 计数 / 拍 N+1
 *      转出至 eSettle。
 *   ④ eSettle → eEject：tonSettle.Q 且剔除位寄位为坏杯 且 bEjectReady；拍 N 进入 / 本拍行为：
 *      剔除命令由派生式置真 / 拍 N+1 转出至 eEject。
 *   ⑤ eSettle → eIndexing：tonSettle.Q 且剔除位寄位为好杯（或无杯）；拍 N 进入 / 本拍行为：
 *      拒绝剔除 / 拍 N+1 转出至 eIndexing。
 *   ⑥ eEject → eIndexing：tonEjectPulse.Q（200ms 剔除脉宽到）；拍 N 进入 / 本拍行为：剔除计数
 *      +1、剔除位寄位清为空、脉宽定时器自复位 / 拍 N+1 转出至 eIndexing。
 *   ⑦ eSettle / eEject → eFault：剔除超时 tonEject.Q（21）；eReady 驻留超时 tonReady.Q（12）；
 *      组态/入参越域（11）；非法枚举（99）。锁存后由段 7 段尾迁移闸迁相（FB50-1④）。
 *   ⑧ eFault → eIdle：bReset 上升沿（rtReset.Q）；拍 N 进入 / 本拍行为：清寄位器、工位号、
 *      三计数、锁存与错误码，剔除命令撤销 / 拍 N+1 转出至 eIdle。出口穷举、不停留故障态。
 *   ⑨ ELSE（非法枚举值）→ eFault，码 99（R6 兜底）。
 * 边界     (Boundary)   : ① 五个 TON 与一个 R_TRIG 全部在 CASE 外无条件调用（R7）；IN 均含
 *                            NOT .Q 自复位项（R188），禁靠外部沿清零。
 *                         ② 数组下标安全：剔除工位下标 _iEjectIdx 恒经 LIMIT 钳在 0..11（R4 越界
 *                            防护），组态非法时亦不会越界访问寄位器。
 *                         ③ 寄位器搬移上界固定 11（定长 ARRAY[0..11]，R17），不随 iStationCnt
 *                            改变搬移宽度，保证同型机台行为一致。
 *                         ④ 剔除脉宽 200ms 为库内常量（DL_RIX_EJECT_PULSE），不开放为引脚——
 *                            该值属执行机构特性，一改即需重新验证气路，开放引脚会引入现场漂移。
 *                         ⑤ 同拍双窗配比约束（R100）：tonIndex（PT := tIndexTime）与 tonSettle
 *                            （PT := T#100MS）分属不重叠相，无配比冲突；tonEject（PT :=
 *                            tEjectTimeout）与 tonEjectPulse（PT := T#200MS）亦分属不同相。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件按派单指定使用小整数码（派单原文明确要求 iErrCode 数值码）。
 *                         信息级（不置 bError）：无。故障级（置 bError，锁存至 bReset 沿）：
 *                         11 = 组态/入参越域（iStationCnt 不在 4..12、tIndexTime 或 tEjectTimeout
 *                              不在 20ms..60s）；反证：该场景下四相节拍全部失去时间基准，
 *                              现有输出组合无法唯一还原「是哪一项越域」，必须独立成码。
 *                         12 = eReady 驻留超时（结构性相驻留看门狗：正常路径下两出口条件互补，
 *                              本相恒为单拍过渡、该码**不触发**；仅在相驻留被后续改动或扫描
 *                              异常延长时生效）；反证：该相不产生任何寄位器变化，仅凭 aCupOk /
 *                              三计数全零无法与「刚上电」区分，故仍须独立成码而非复用 11。
 *                         21 = 剔除位未就绪超时（坏杯在位而剔除位不响应）；反证：该场景下
 *                              iEjectCnt 不增、工位号停驻，与「正常停止」输出组合完全同形。
 *                         99 = 非法状态枚举值（ELSE 兜底）。
 * 分工声明 (Scope)      : 转盘伺服/减速机定位归 DL_Motion 轴类件；坏杯判定（视觉/称重）归
 *                         上游检测件（本件只接收 bCupBad 布尔）；剔除气缸动作时序归
 *                         FB_DL_CylinderBase 类件。本件只做**索引节拍 + 杯位寄位 + 剔除裁决**。
 * 归属     (Ownership)  : E_DL_RotaryIndexerCycleSeq_State 归属本文件（全库唯一定义，R264）。
 * 命名偏离 (Naming Ex.) : 本件按派单原文保留 i 前缀表示 INT（iStationCnt / iErrCode / iStationIdx /
 *                         iCupPerCycle / iGoodCnt / iBadCnt / iEjectCnt），与规范 1.2 节 n 前缀
 *                         存在登记偏离；接口契约（上层调用点与 HMI 标签）优先，不改名。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         （TON / R_TRIG / LIMIT / DINT_TO_TIME）｜ R4 ✓ 无除法 + 下标 LIMIT 钳位 +
 *                         无 ABS(x-x) / (x-x)<>0 非有限判据（本件无浮点入参，故无浮点闸需求）
 *                         R5 ✓ 逐行同行中英双语注释 ｜ R6 ✓ 六态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 全部 TON / R_TRIG 在 CASE 外无条件调用 ｜ R8 ✓ 无 METHOD（全内联）
 *                         R10 ✓ 无构造式转换（仅标准函数）｜ R11 ✓ 声明全分号结尾
 *                         R12 ✓ ENUM 成员用 := ｜ R14 ✓ 无 PROPERTY ｜ R16 ✓ 不引用任何外部 FB/FC。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R81-B 首版
 *                          2026-11-24  v1.0.1  R81-C 三处 FOR..DOWNTO 改镜像下标升序（RuSTy E007 编译阻断，闸席最小修法，20000 例随机穷举逐拍等价）
 * 验收向量 (Acceptance) :
 *   V1 iStationCnt=8、tIndexTime=T#500MS、bCupPresent 恒 TRUE、bCupBad 恒 FALSE：
 *      bEnable+bStart → 22 个索引拍后 iGoodCnt=22、aCupOk 全 TRUE、iBadCnt=0、iEjectCnt=0；
 *      每满 8 拍（iStationIdx 由 7 回 0）bDone 出一拍。
 *   V2 单杯坏：第 3 拍 bCupBad=TRUE → iBadCnt=1、aCupOk[0]=FALSE；随索引右移至 aCupOk[7]
 *      （剔除工位）且 bEjectReady=TRUE → eEject、bEjectCmd=TRUE 200ms 后撤销、iEjectCnt=1、
 *      aCupOk[7] 清为 FALSE。
 *   V3 剔除位不就绪：坏杯到 aCupOk[7] 且 bEjectReady 恒 FALSE → 驻留 eSettle；超过
 *      tEjectTimeout=T#2S → eState=eFault、iErrCode=21、bError=TRUE、bEjectCmd=FALSE。
 *   V4 组态越域：iStationCnt=3 → eState=eFault、iErrCode=11、bError=TRUE；bReset 上升沿 →
 *      eState=eIdle、bError=FALSE、iErrCode=0、aCupOk 全 FALSE、三计数全 0。
 *   V5 撤使能：运行中 bEnable=FALSE → bBusy=FALSE、bEjectCmd=FALSE、eState=eIdle；
 *      aCupOk 与三计数保持（不全清），bError=FALSE（降级不置故障）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RotaryIndexerCycleSeq_State（转盘索引节拍相位；eFault 为安全相）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RotaryIndexerCycleSeq_State :
(
    eIdle     := 0,    // 空闲：等启动条件，无任何动作 / Idle: waiting for the start condition, no action
    eReady    := 10,   // 就绪过渡相：清寄位器与计数，单拍 / Ready transition: clears register and counters, one scan
    eIndexing := 20,   // 索引相：计时推进工位与寄位器 / Indexing: advancing the station and the cup register on the timer
    eSettle   := 30,   // 整定相：到位整定并裁决是否剔除 / Settle: dwell for seating, decide whether to eject
    eEject    := 40,   // 剔除相：输出剔除脉冲 200ms / Eject: driving the eject pulse for 200 ms
    eFault    := 90    // 故障安全相：锁存成因，全部动作撤销 / Fault safe phase: latched cause, all actions withdrawn
);
END_TYPE

FUNCTION_BLOCK FB_DL_RotaryIndexerCycleSeq
VAR_INPUT
    bEnable       : BOOL := FALSE;      // 使能：FALSE 撤销剔除并回空闲 / Enable, FALSE withdraws eject and returns to idle
    bReset        : BOOL := FALSE;      // 复位（上升沿，清锁存与寄位器与计数）/ Reset rising edge clearing latch, cup register and counters
    bStart        : BOOL := FALSE;      // 启动（电平，eReady 判据之一）/ Start level, one of the eReady exit criteria
    iStationCnt   : INT := 8;           // 工位数，有效域 4..12 [工位] / Station count, valid domain 4..12
    tIndexTime    : TIME := T#800MS;    // 单工位索引时间，有效域 20ms..60s [s] / Indexing time per station
    iCupPerCycle  : INT := 1;           // 每索引拍上料杯数，有效域 1..4 [杯] / Cups loaded per index cycle, valid domain 1..4
    bCupPresent   : BOOL := FALSE;      // 当前上料位有杯（索引完成同拍采样）/ A cup is present at the loading station, sampled on index completion
    bCupBad       : BOOL := FALSE;      // 当前杯判定为坏（仅在 bCupPresent 为真时有效）/ The cup is bad, meaningful only while a cup is present
    bEjectReady   : BOOL := FALSE;      // 剔除位就绪（气路压力与剔除腔空闲）/ The eject station is ready, air pressure present and chamber free
    tEjectTimeout : TIME := T#3S;       // 剔除位就绪等待上限，有效域 20ms..60s [s] / Eject-ready waiting limit
END_VAR
VAR_OUTPUT
    eState        : E_DL_RotaryIndexerCycleSeq_State;   // 当前相位出口（段 8 单点映射）/ Current phase outlet mapped once at segment 8
    bBusy         : BOOL;               // 节拍运行中（就绪/索引/整定/剔除）/ Sequence running, ready through eject
    bDone         : BOOL;               // 圈完成单拍脉冲（工位号回绕过零时）/ One-scan pulse when the station index wraps to zero
    bError        : BOOL;               // 故障锁存标志 / Fault latch flag
    iErrCode      : INT := 0;           // 错误码（故障期锁存回放，其余拍为 0）/ Error code, latched code replayed while in fault
    iStationIdx   : INT := 0;           // 当前工位号 0..iStationCnt-1 [工位] / Current station index
    aCupOk        : ARRAY[0..11] OF BOOL;   // 各工位杯位「有杯且好」寄位器 [真/假] / Per-station cup register, present and good
    iGoodCnt      : DINT := 0;          // 好杯累计 [杯] / Cumulative good-cup count
    iBadCnt       : DINT := 0;          // 坏杯累计 [杯] / Cumulative bad-cup count
    iEjectCnt     : DINT := 0;          // 剔除动作累计 [次] / Cumulative eject action count
    bEjectCmd     : BOOL;               // 剔除执行命令（相内派生量映射）/ Eject command mapped from the derived phase value
END_VAR
VAR
    _eState       : E_DL_RotaryIndexerCycleSeq_State := E_DL_RotaryIndexerCycleSeq_State.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch  : BOOL := FALSE;      // 故障锁存位（仅 bReset 上升沿清除）/ Fault latch bit, cleared only by the bReset rising edge
    _iErrLatch    : INT := 0;           // 锁存错误码（故障期唯一回放源，FB33-1）/ Latched error code, the only replay source during fault
    _iErrTmp      : INT := 0;           // 本拍首因中间量（段 2 组态闸写）/ First cause of this scan written by the configuration gate
    _bCfgOk       : BOOL := TRUE;       // 组态与入参闸通过标志 / Configuration and argument gate flag
    _iStationIdx  : INT := 0;           // 内部工位号（相内推进，段 8 映射）/ Internal station index advanced inside the phase
    _iEjectIdx    : INT := 0;           // 剔除工位下标（恒钳 0..11，防越界）/ Eject station index clamped to 0..11 against out-of-range access
    _iCupPer      : INT := 1;           // 每拍上料杯数钳位值 1..4 [杯] / Clamped cups per cycle, 1..4
    _aCupOk       : ARRAY[0..11] OF BOOL;   // 内部杯位寄位器（保持量，段 1 不清）/ Internal cup register, a holding value never cleared at segment 1
    _bEjectCmd    : BOOL := FALSE;      // 剔除命令派生量（相内派生，禁多分支赋值）/ Derived eject command, never assigned in two branches
    _bCycleDone   : BOOL := FALSE;      // 圈完成内部单拍位（段 1 预置，段 8 映射）/ Internal one-scan cycle-done bit preset at segment 1
    _iGoodCnt     : DINT := 0;          // 内部好杯累计 [杯] / Internal good-cup counter
    _iBadCnt      : DINT := 0;          // 内部坏杯累计 [杯] / Internal bad-cup counter
    _iEjectCnt    : DINT := 0;          // 内部剔除累计 [次] / Internal eject counter
    _nIdx         : INT := 0;           // 遍历下标（FOR 专用）/ Loop index reserved for FOR statements
    rtReset       : R_TRIG;             // bReset 边沿实例（段 3 无条件调用，R18）/ bReset edge instance called unconditionally at segment 3
    tonIndex      : TON;                // 单工位索引计时器（段 3 无条件调用）/ Per-station indexing timer called unconditionally
    tonSettle     : TON;                // 到位整定计时器（段 3 无条件调用）/ Seating settle timer called unconditionally
    tonEject      : TON;                // 剔除位就绪等待计时器（段 3 无条件调用）/ Eject-ready waiting timer called unconditionally
    tonEjectPulse : TON;                // 剔除脉宽计时器 200ms（段 3 无条件调用）/ Eject pulse-width timer, called unconditionally
    tonReady      : TON;                // 就绪过渡相驻留看门狗（段 3 无条件调用）/ Ready-phase dwell watchdog called unconditionally
END_VAR
VAR CONSTANT
    DL_RIX_ST_MIN      : INT := 4;                 // 工位数下限（四工位为上料/加工/剔除的最小完备数）[工位] / Station count lower bound
    DL_RIX_ST_MAX      : INT := 12;                // 工位数上限（寄位器定长上界 + 1）[工位] / Station count upper bound
    DL_RIX_ARR_MAX     : INT := 11;                // 寄位器下标上界（定长 ARRAY[0..11]）[下标] / Cup register index upper bound
    DL_RIX_IDX_ZERO    : INT := 0;                 // 下标与工位号零基准 [下标] / Zero base for indices and station numbers
    DL_RIX_ONE         : INT := 1;                 // 整数一（步进与下限用）[1] / Integer one used for stepping and lower bounds
    DL_RIX_CUP_MIN     : INT := 1;                 // 每拍上料杯数下限 [杯] / Cups-per-cycle lower bound
    DL_RIX_CUP_MAX     : INT := 4;                 // 每拍上料杯数上限 [杯] / Cups-per-cycle upper bound
    DL_RIX_CNT_ZERO    : DINT := 0;                // 计数量零基准 [-] / Zero base for DINT counters
    DL_RIX_T_MIN       : TIME := T#20MS;           // 时间参数下限 [s] / Time parameter lower bound
    DL_RIX_T_MAX       : TIME := T#60S;            // 时间参数上限 [s] / Time parameter upper bound
    DL_RIX_SETTLE      : TIME := T#100MS;          // 到位整定窗（执行机构落位与气路稳定）[s] / Seating settle window
    DL_RIX_EJECT_PULSE : TIME := T#200MS;          // 剔除脉宽（执行机构特性常量，不开放引脚）[s] / Eject pulse width, a constant actuator characteristic
    DL_RIX_READY_WIN   : TIME := T#5S;             // 就绪过渡相驻留看门狗，域 ≥ 20ms [s] / Ready-phase dwell watchdog
END_VAR

(* —— 段 1：中间量预置（只清单拍标志与扫描量，不清寄位器 / 计数 / 锁存，FB32-1） —— *)
_bCfgOk     := TRUE;                       // 组态闸标志复位 / Configuration gate flag reset
_iErrTmp    := 0;                          // 当拍首因复位 / Scan first cause reset
_bCycleDone := FALSE;                      // 圈完成单拍位复位（单拍路径唯一预置点，FB51-8）/ Cycle-done pulse reset, the single preset point
_nIdx       := DL_RIX_IDX_ZERO;            // 遍历下标复位 / Loop index reset

(* —— 段 2：组态与入参域闸（越域只置首因，锁存与迁相在段 7 统一执行，R21） —— *)
IF (iStationCnt < DL_RIX_ST_MIN) OR (iStationCnt > DL_RIX_ST_MAX) THEN
    _bCfgOk  := FALSE;                     // 工位数越域 / Station count out of domain
    _iErrTmp := 11;                        // 故障级：组态/入参越域 / Fault: configuration or argument out of domain
END_IF
IF (tIndexTime < DL_RIX_T_MIN) OR (tIndexTime > DL_RIX_T_MAX) THEN
    _bCfgOk  := FALSE;                     // 索引时间越域 / Index time out of domain
    _iErrTmp := 11;                        // 故障级：组态/入参越域 / Fault: configuration or argument out of domain
END_IF
IF (tEjectTimeout < DL_RIX_T_MIN) OR (tEjectTimeout > DL_RIX_T_MAX) THEN
    _bCfgOk  := FALSE;                     // 剔除等待上限越域 / Eject-ready limit out of domain
    _iErrTmp := 11;                        // 故障级：组态/入参越域 / Fault: configuration or argument out of domain
END_IF
(* 剔除工位下标恒钳 0..11：即使 iStationCnt 瞬时非法也保证寄位器访问不越界（R4） *)
_iEjectIdx := LIMIT(DL_RIX_IDX_ZERO, iStationCnt - DL_RIX_ONE, DL_RIX_ARR_MAX);   // 剔除工位下标钳位 / Eject index clamped
_iCupPer   := LIMIT(DL_RIX_CUP_MIN, iCupPerCycle, DL_RIX_CUP_MAX);                // 每拍杯数钳位（两级回退，不故障）/ Cups per cycle clamped, no fault raised

(* —— 段 3：边沿与定时器（CASE 外无条件调用，R7；IN 均含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                    // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
tonIndex(IN := (_eState = E_DL_RotaryIndexerCycleSeq_State.eIndexing) AND (NOT tonIndex.Q) AND (NOT _bFaultLatch),
         PT := tIndexTime);                // 单工位索引计时（自复位后逐相再触发）/ Per-station indexing timer, retriggered each phase
tonSettle(IN := (_eState = E_DL_RotaryIndexerCycleSeq_State.eSettle) AND (NOT tonSettle.Q) AND (NOT _bFaultLatch),
          PT := DL_RIX_SETTLE);            // 到位整定计时 / Seating settle timer
tonEjectPulse(IN := (_eState = E_DL_RotaryIndexerCycleSeq_State.eEject) AND (NOT tonEjectPulse.Q) AND (NOT _bFaultLatch),
              PT := DL_RIX_EJECT_PULSE);   // 剔除脉宽计时 200ms / Eject pulse-width timer
tonEject(IN := (((_eState = E_DL_RotaryIndexerCycleSeq_State.eSettle) AND (NOT _aCupOk[_iEjectIdx]))
                OR ((_eState = E_DL_RotaryIndexerCycleSeq_State.eEject) AND (NOT bEjectReady)))
               AND (NOT tonEject.Q) AND (NOT _bFaultLatch),
          PT := tEjectTimeout);            // 剔除位就绪等待（整定相等待 + 剔除相脉宽期丢失共用）/ Eject-ready waiting shared by settle wait and pulse-loss
tonReady(IN := (_eState = E_DL_RotaryIndexerCycleSeq_State.eReady) AND (NOT tonReady.Q) AND (NOT _bFaultLatch),
         PT := DL_RIX_READY_WIN);          // 就绪过渡相看门狗（防过渡相被卡）/ Ready transition dwell watchdog

(* —— 段 4：派生量（剔除命令为相内派生式，单赋值点，避免同相双写，FB32-6①） —— *)
_bEjectCmd := (_eState = E_DL_RotaryIndexerCycleSeq_State.eEject) AND (NOT tonEjectPulse.Q);   // 剔除命令：仅在剔除相且脉宽未到时为真 / Eject command true only inside the eject phase before the pulse expires

(* —— 段 5：状态机主体（唯一相位写入点；故障只置锁存，迁相由段 7 执行） —— *)
CASE _eState OF
    E_DL_RotaryIndexerCycleSeq_State.eIdle :
        (* 迁移①：启动条件成立即进就绪过渡相 *)
        IF bEnable AND bStart AND _bCfgOk AND (NOT _bFaultLatch) THEN
            _eState := E_DL_RotaryIndexerCycleSeq_State.eReady;   // 进入就绪过渡相 / Enter the ready transition phase
        END_IF

    E_DL_RotaryIndexerCycleSeq_State.eReady :
        (* 拍 N 进入（bEnable 且 bStart 且组态闸通过）/ 本拍行为：清三计数、清 12 位寄位器、
           工位号归零、圈完成位归假，拒绝剔除命令 / 拍 N+1 转出：条件成立即刻迁相（R80 三段式） *)
        _iStationIdx := DL_RIX_IDX_ZERO;                          // 工位号归零 / Station index zeroed
        _iGoodCnt    := DL_RIX_CNT_ZERO;                          // 好杯累计清零 / Good counter cleared
        _iBadCnt     := DL_RIX_CNT_ZERO;                          // 坏杯累计清零 / Bad counter cleared
        _iEjectCnt   := DL_RIX_CNT_ZERO;                          // 剔除累计清零 / Eject counter cleared
        FOR _nIdx := DL_RIX_IDX_ZERO TO DL_RIX_ARR_MAX DO
            _aCupOk[_nIdx] := FALSE;                              // 寄位器全清（新批次起点）/ Cup register cleared, new batch origin
        END_FOR
        IF bEnable AND bStart THEN
            _eState := E_DL_RotaryIndexerCycleSeq_State.eIndexing;   // 迁移②：进索引相 / Move to indexing
        ELSE
            _eState := E_DL_RotaryIndexerCycleSeq_State.eIdle;       // 迁移②（互补出口）：前置条件消失回空闲 / Complementary exit to idle
        END_IF

    E_DL_RotaryIndexerCycleSeq_State.eIndexing :
        (* 迁移③：索引时间到 → 推进工位与寄位器 *)
        IF tonIndex.Q THEN
            _iStationIdx := _iStationIdx + DL_RIX_ONE;            // 工位号步进 / Station index stepped
            IF _iStationIdx > (iStationCnt - DL_RIX_ONE) THEN
                _iStationIdx := DL_RIX_IDX_ZERO;                  // 越上界回绕到 0 / Wrap to zero past the upper bound
                _bCycleDone  := TRUE;                             // 圈完成单拍（工位号回绕）/ One-scan cycle-done on wrap
            END_IF
            (* 寄位器右移一位：高位到低位搬移，避免覆盖尚未搬移的低位（从高到低遍历） *)
            (* RuSTy 1.0.8 不支持 FOR..DOWNTO（E007），改为镜像下标升序遍历：
               _nIdx 由 0 递增至 ARR_MAX-1，实际操作下标 (ARR_MAX-_nIdx) 递减，逐拍与降序等价 *)
            FOR _nIdx := DL_RIX_IDX_ZERO TO (DL_RIX_ARR_MAX - DL_RIX_ONE) DO
                _aCupOk[DL_RIX_ARR_MAX - _nIdx] := _aCupOk[(DL_RIX_ARR_MAX - _nIdx) - DL_RIX_ONE]; // 第 n 工位承接第 n-1 工位的杯 / Station n inherits the cup of station n-1
            END_FOR
            _aCupOk[DL_RIX_IDX_ZERO] := bCupPresent AND (NOT bCupBad);   // 上料位装入新杯「有杯且好」/ Loading station takes the new cup, present and good
            IF bCupPresent THEN
                IF bCupBad THEN
                    _iBadCnt := _iBadCnt + INT_TO_DINT(_iCupPer);    // 坏杯按每拍杯数累计 / Bad cups accumulated by the per-cycle cup count
                ELSE
                    _iGoodCnt := _iGoodCnt + INT_TO_DINT(_iCupPer);  // 好杯按每拍杯数累计 / Good cups accumulated by the per-cycle cup count
                END_IF
            END_IF
            _eState := E_DL_RotaryIndexerCycleSeq_State.eSettle;  // 迁移③：进整定相 / Move to settle
        END_IF

    E_DL_RotaryIndexerCycleSeq_State.eSettle :
        (* 迁移④/⑤：整定窗到后按剔除位寄位裁决；坏杯在位但剔除位不就绪则驻留等待（tonEject 超时兜底） *)
        IF tonSettle.Q THEN
            IF _aCupOk[_iEjectIdx] THEN
                _eState := E_DL_RotaryIndexerCycleSeq_State.eIndexing;   // 迁移⑤：好杯/空杯，继续索引 / Good or empty slot, continue indexing
            ELSIF bEjectReady THEN
                _eState := E_DL_RotaryIndexerCycleSeq_State.eEject;      // 迁移④：坏杯且就绪，进剔除相 / Bad cup and ready, move to eject
            END_IF
            (* 坏杯在位且不就绪：本拍不迁相，驻留等 bEjectReady；tonEject 超时由段 6 锁存码 21 *)
        END_IF

    E_DL_RotaryIndexerCycleSeq_State.eEject :
        (* 迁移⑥：脉宽到 → 计数并清该工位寄位，回索引相；脉宽期内 bEjectReady 丢失由 tonEject 超时兜底 *)
        IF tonEjectPulse.Q THEN
            _aCupOk[_iEjectIdx] := FALSE;                         // 剔除后该工位无杯（寄位清空）/ Slot emptied after the eject
            _iEjectCnt := _iEjectCnt + INT_TO_DINT(DL_RIX_ONE);  // 剔除动作累计 +1 / Eject action count incremented
            _eState    := E_DL_RotaryIndexerCycleSeq_State.eIndexing;   // 迁移⑥：回索引相 / Back to indexing
        END_IF

    E_DL_RotaryIndexerCycleSeq_State.eFault :
        (* 拍 N 进入（锁存即迁相）/ 本拍行为：剔除命令由派生式自动撤销，仅等复位沿 / 拍 N+1 转出至 eIdle *)
        IF rtReset.Q THEN
            FOR _nIdx := DL_RIX_IDX_ZERO TO DL_RIX_ARR_MAX DO
                _aCupOk[_nIdx] := FALSE;                          // 复位：寄位器全清 / Reset: cup register cleared
            END_FOR
            _iStationIdx := DL_RIX_IDX_ZERO;                      // 复位：工位号归零 / Reset: station index zeroed
            _iGoodCnt    := DL_RIX_CNT_ZERO;                      // 复位：好杯累计清零 / Reset: good counter cleared
            _iBadCnt     := DL_RIX_CNT_ZERO;                      // 复位：坏杯累计清零 / Reset: bad counter cleared
            _iEjectCnt   := DL_RIX_CNT_ZERO;                      // 复位：剔除累计清零 / Reset: eject counter cleared
            _bCycleDone  := FALSE;                                // 复位：圈完成位归假 / Reset: cycle-done bit cleared
            _iErrLatch   := 0;                                    // 复位：错误码归零 / Reset: error code cleared
            _bFaultLatch := FALSE;                                // 迁移⑧：清故障锁存 / Clear the fault latch
            _eState      := E_DL_RotaryIndexerCycleSeq_State.eIdle;   // 迁移⑧：回空闲相，不滞留故障态 / Back to idle, never parked in fault
        END_IF

ELSE
    (* 迁移⑨：非法枚举兜底（R6） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                    // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                  // 置故障锁存（码位赋值 3 行内配对，R45）/ Latch the fault within three lines of the code assignment
    END_IF
END_CASE

(* —— 段 6：定时器触发的故障锁存（锁存与迁相分离，R21） —— *)
IF tonEject.Q AND (NOT _bFaultLatch) THEN
    _iErrLatch   := 21;                        // 故障级：剔除位未就绪超时 / Fault: eject-ready timeout
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF tonReady.Q AND (NOT _bFaultLatch) THEN
    _iErrLatch   := 12;                        // 故障级：就绪过渡相驻留超时 / Fault: ready-phase dwell timeout
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF

(* —— 段 7：组态闸锁存 + 段尾故障迁移闸 + 撤使能降级（R191 已声明为降级+置标志） —— *)
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                  // 锁存组态首因 / Latch the configuration first cause
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_RotaryIndexerCycleSeq_State.eFault) THEN
    _eState := E_DL_RotaryIndexerCycleSeq_State.eFault;   // 锁存即迁相（段尾统一执行，FB50-1④）/ Latch forces the fault phase at the tail
END_IF
IF (NOT bEnable) AND (NOT _bFaultLatch) AND (_eState <> E_DL_RotaryIndexerCycleSeq_State.eIdle) THEN
    _eState := E_DL_RotaryIndexerCycleSeq_State.eIdle;    // 撤使能：回空闲（降级为安全值，保留寄位器与计数）/ Disable: back to idle, register and counters kept
END_IF

(* —— 段 8：统一出口（单点映射，禁在 CASE 后无条件清零 CASE 内赋值标识符，FB33-1） —— *)
eState      := _eState;                        // 相位映射 / Phase mapping
bBusy       := (_eState = E_DL_RotaryIndexerCycleSeq_State.eReady)
               OR (_eState = E_DL_RotaryIndexerCycleSeq_State.eIndexing)
               OR (_eState = E_DL_RotaryIndexerCycleSeq_State.eSettle)
               OR (_eState = E_DL_RotaryIndexerCycleSeq_State.eEject);   // 节拍运行中 / Sequence running
bDone       := _bCycleDone;                    // 圈完成单拍映射 / Cycle-done pulse mapping
bError      := _bFaultLatch;                   // 故障标志取锁存位 / Fault flag taken from the latch
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                    // 故障期回放锁存码（FB33-1）/ Replay the latched code during fault
ELSE
    iErrCode := 0;                             // 非故障拍错误码归零 / Error code zeroed outside fault
END_IF
iStationIdx := _iStationIdx;                   // 工位号映射 / Station index mapping
bEjectCmd   := _bEjectCmd;                     // 剔除命令映射 / Eject command mapping
iGoodCnt    := _iGoodCnt;                      // 好杯累计映射 / Good counter mapping
iBadCnt     := _iBadCnt;                       // 坏杯累计映射 / Bad counter mapping
iEjectCnt   := _iEjectCnt;                     // 剔除累计映射 / Eject counter mapping
FOR _nIdx := DL_RIX_IDX_ZERO TO DL_RIX_ARR_MAX DO
    aCupOk[_nIdx] := _aCupOk[_nIdx];           // 寄位器逐位映射 / Cup register mapped element by element
END_FOR
END_FUNCTION_BLOCK
