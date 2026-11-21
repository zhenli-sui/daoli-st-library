(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PortDiagBoard
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备诊断 · 多组端口看板与首出仲裁
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 功能描述 (Function)   : 把最多 4 个端口诊断聚合组（每组最多 8 端口）汇总为一张看板：
 *                         屏蔽超界位后的各组掩码、全局故障端口总数、全局首出端口
 *                         （组号加端口号加诊断码），以及按「组号优先、端口号次之」稳定
 *                         排序的前 3 个待修端口。回答现场两个问题：现在还剩几个端口坏、
 *                         先修哪一个。
 * 分层声明 (Layering)   : ① 本件是「汇总层」，只消费端口级聚合结果（掩码加组内首出
 *                         码），不实例化上游聚合块、不重算端口明细——聚合器实例由调用方
 *                         按组各自持有，重复实例化会造成同一批端口被算两遍；
 *                         ② 不读模块级状态字（模块级归本地总线诊断锁存件，端口级归聚合
 *                         器，参数对象级归参数回读调度件，三层数据源分账已在 R11 收口）；
 *                         ③ 不绑定任何总线驱动，全部数据经引脚注入。
 * 职责边界 (Scope)      : 不做端口去抖（聚合器职责）、不做报警确认与搁置、不做历史趋势
 *                         归档、不做跨机架分组切换（组数运行期变化按钳位处理）。
 * 组数语义 (Grouping)   : 组是「同一块远程 IO 卡或同一台交换机的 8 个端口」的物理分组，
 *                         组号小者更靠近主站，故首出仲裁取组号最小、再取端口号最小，
 *                         这与现场排故的因果顺序一致。
 * 开源溯源 (Origin)     : 来源标签 plcnext-diag 加 roadmap-p0。原创实现（参考 T1-7
 *                         PLCnext 端口诊断四元组的分类与参数域，以及 ROADMAP §15.3 P0
 *                         条目的「看板加首出」需求定义）。仅借分类层次、参数域与验收
 *                         口径，掩码位序、首出三律、Top 排序编码、枚举、状态机与全部
 *                         码位 100% 本库独立设计，clean-room 实现，零代码行复制。
 *                         PLCnext 帮助文档为厂商公开资料，此处按最严口径「只借结构与
 *                         参数域」处置，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 故障码表 (Error codes):
 *   16#0003_0149【信息级】组数超上限已钳位到 4（只影响显示范围，不置故障位）
 *   16#0003_014A【信息级】某组端口数超上限已钳位到 8（组态常见，非错误）
 *   16#0003_014B【信息级】掩码超界位已屏蔽（绝不把不存在的端口计入故障数）
 *   16#0003_014C【信息级】组内声明首出端口与掩码推导值不一致（数据源未同步）
 *   16#0003_030B【故障段趋势码】单拍掩码变化位数超阈值，判为组态刷新；按规格
 *                         第 3.13 节「仅提示不锁存」处置：只透出一拍，不置故障位
 *   16#0003_0309【故障级】组数小于 1，无诊断源（锁存，置故障位）
 *   16#0003_030A【故障级】某组端口数小于 1，该组掩码含义不可信（锁存，置故障位）
 *   16#0003_030C【故障级】非法状态兜底（锁存，置故障位，终端安全态）
 * 码位占用 (Slot)       : 信息级 0149 / 014A / 014B / 014C；故障级 0309 / 030A / 030B / 030C。
 *                         全部落在 R12 本件分配块内，无跨块借用、无段外哨兵值。
 * 拍序纪律 (Cycle order) :
 *   ① ePhase      ：段 4 状态机（唯一位移点），段 6 复位分支是唯一回退点
 *   ② 首出锁存    ：段 4 的 eScanning 分支（仅未锁存时仲裁）→ 段 5 换出 → 段 6 复位清除
 *   ③ 输出码      ：段 7 单一优先级链，全拍只写一次 uErrorId，杜绝多分支互相覆盖
 *   ④ 掩码基准    ：段 4 的 eScanning 分支末尾装载，与风暴判定同段且判在读后写前
 * 首出三律 (First-out)  : ① 仅在无锁存时仲裁；② 同拍多端口故障取组号最小、再取端口号
 *                         最小；③ 复位在仲裁之后执行，故复位当拍首出为空、下一拍重新
 *                         仲裁（与 R11 端口聚合器同口径）。
 * 验收向量 (Acceptance) :
 *   V1 单组超界位：组数 1、端口数 8、掩码 16#0101 → 位 8 对应端口 9 超界被屏蔽，
 *      掩码出 16#0001、总故障 1、首出 1 组 1 号、码 014B
 *   V2 双组排序：两组端口数 8，掩码 16#0004 与 16#0003 → 总数 3、首出 1 组 3 号、
 *      待修序 13、21、22（编码为组号乘 10 加端口号）
 *   V3 复位时序：与 V2 同参，复位上升沿当拍首出为空，下一拍重新仲裁回 1 组 3 号
 *   V4 无诊断源：组数 0 → 钳为 1、故障位置位、码 0309
 *   V5 空组：第 1 组端口数 0 → 钳为 1、故障位置位、码 030A
 * 偏离留档 (Deviation)  :
 *   ① 规格第 3.13 节算法要点对「端口数超上限」写 014A、对「端口数越界」的边界说明
 *      又写 030A。本件按语义拆分：大于 8 属组态多填，按信息级 014A 只钳位；小于 1
 *      属无有效端口（掩码含义不可信），按故障级 030A 锁存——与验收向量 V5 完全一致。
 *   ② 规格未给 anGroupFirstPort 的用途。本件把它用作「声明值与掩码推导值」的一致性
 *      校验（为 0 视为未填、不校验），不一致只置信息级 014C，避免该引脚悬空无意义。
 *   ③ 030B 落在故障段但不置故障位，理由见上方故障码表，属规格原文要求的「仅提示不
 *      锁存」，不是定级笔误。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（R12 · 泳道 C · 端口诊断看板 P0 件）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_BoardPhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block and published in the same file
 *-----------------------------------------------------------------------------*)
TYPE E_DL_BoardPhase :
(
    eIdle     := 0,   // 待机：钳位参数后即转扫描，或未使能时清掩码保首出 / Idle, clamps parameters then moves on to scanning
    eScanning := 10,  // 扫描：一趟完成屏蔽、计数、首出仲裁与待修排序，本拍结束回待机 / Scanning, the whole sweep completes in one pass
    eFault    := 99   // 故障：无诊断源、空组或非法状态，需复位退出 / Fault, needs a reset to leave
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_BoardState（跨周期状态，由调用方持有）
 *         Persistent state structure, owned by the caller
 *         说明：首出锁存是「诊断证据」，掉使能不清、只有复位沿才清；
 *               anLastMask 用于掩码跳变风暴的差分基准
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_BoardState :
STRUCT
    nLatchedGroup : INT;                     // 首出锁存组号 [1..4]，0 表示无 / Latched first-out group, zero means none
    nLatchedPort  : INT;                     // 首出锁存端口号 [1..8]，0 表示无 / Latched first-out port, zero means none
    uLatchedCode  : UDINT;                   // 首出锁存诊断码 [代码]，0 表示未填 / Latched first-out diagnostic code, zero means not filled
    bLatchValid   : BOOL;                    // 首出锁存有效，仅复位沿可清 / First-out latch valid, cleared by the reset edge only
    anLastMask    : ARRAY[1..4] OF WORD;     // 上次各组掩码快照，用于跳变风暴差分 [位串] / Previous per-group mask for burst differencing
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_PortDiagBoard
VAR_INPUT
    bEnable          : BOOL;                              // 看板使能，FALSE 时掩码清零而首出保持 [-] / Enable, masks are cleared while the first-out latch is kept
    bReset           : BOOL;                              // 复位首出锁存，上升沿有效 [-] / Rising edge clears the first-out latch
    nGroupCount      : INT := 1;                          // 聚合组数 [组]，有效域 1 到 4 / Group count, valid range one to four
    anGroupFaultMask : ARRAY[1..4] OF WORD;               // 各组端口故障掩码，位 n 减一 对应端口 n [位串] / Per-group fault mask, bit n minus one is port n
    anGroupPortCount : ARRAY[1..4] OF INT;                // 各组实际端口数 [个]，有效域 1 到 8 / Ports per group, valid range one to eight
    anGroupFirstPort : ARRAY[1..4] OF INT;                // 各组声明首出端口号，0 表示未填不校验 [端口号] / Declared first-out port, zero skips the cross check
    auGroupFirstCode : ARRAY[1..4] OF UDINT;              // 各组组内首出诊断码 [代码]，0 表示未填 / Per-group first-out diagnostic code, zero means not filled
END_VAR
VAR_OUTPUT
    nTotalFaultPort  : INT;                               // 全局故障端口总数 [个] / Total faulted ports across the enabled groups
    nFirstGroup      : INT;                               // 全局首出组号 [1..4]，0 表示无 / Global first-out group, zero means none
    nFirstPort       : INT;                               // 全局首出端口号 [1..8]，0 表示无 / Global first-out port, zero means none
    uFirstCode       : UDINT;                             // 全局首出诊断码 [代码]，0 表示未填 / Global first-out diagnostic code
    anGroupMaskOut   : ARRAY[1..4] OF WORD;               // 屏蔽超界位后的各组掩码 [位串] / Sanitised per-group masks
    anTopPortNo      : ARRAY[1..3] OF INT;                // 待修端口编码，组号乘 10 加端口号，0 表示空位 [编码] / Top repair ports encoded as group times ten plus port
    auTopPortCode    : ARRAY[1..3] OF UDINT;              // 待修端口对应诊断码 [代码] / Diagnostic code of each top repair port
    bAnyFault        : BOOL;                              // 总故障数大于 0 [-] / Any faulted port present
    bError           : BOOL;                              // 故障级锁存，仅 0309 030A 030C 置位 [-] / Latched fault, only fault level codes set it
    uErrorId         : UDINT;                             // 事件码，0 表示无事件 [代码] / Event code, zero means none
    eState           : E_DL_BoardPhase;                   // 主状态机当前相位 [-] / Current phase of the main state machine
END_VAR
VAR_IN_OUT
    stBoard          : ST_DL_BoardState;                  // 跨周期：首出锁存与掩码差分基准 [-] / Persistent first-out latch and mask baseline
END_VAR
VAR
    fbTrigReset      : R_TRIG;                            // 复位沿检测，主周期无条件刷新 [-] / Reset edge detector, refreshed unconditionally
    ePhase           : E_DL_BoardPhase := E_DL_BoardPhase.eIdle; // 内部相位，对外经 eState 输出 [-] / Internal phase exported as eState
    bInit            : BOOL := FALSE;                     // 首扫标志，初值 FALSE，判据取非 [-] / First-scan flag initialised FALSE
    bMaskBase        : BOOL := FALSE;                     // 掩码差分基准已装载 [-] / Mask baseline loaded flag
    bFaultLatch      : BOOL;                              // 故障锁存，仅复位分支清除 [-] / Fault latch, cleared by the reset path only
    uErrInt          : UDINT;                             // 故障级码寄存，锁存型 [代码] / Latched fault level code register
    uInfoCode        : UDINT;                             // 本拍信息级码，每拍重算 [代码] / Info level code recomputed every scan
    nGroupUse        : INT;                               // 生效组数，钳位后 [组] / Effective group count after clamping
    auPortCntUse     : ARRAY[1..4] OF INT;                // 生效端口数，钳位后 [个] / Effective port count per group after clamping
    uBuildMask       : WORD;                              // 掩码装配中间量 [位串] / Mask under assembly
    uDiff            : WORD;                              // 掩码差分中间量 [位串] / Mask difference under evaluation
    nTotal           : INT;                               // 故障端口累加计数 [个] / Faulted port counter
    nMinPort         : INT;                               // 组内最小故障端口号 [1..8]，0 表示无 / Lowest faulted port inside a group
    nBitScan         : INT;                               // 掩码跳变位计数 [位] / Changed bit counter for the burst check
    nScanGroup       : INT;                               // 仲裁扫描组号 [1..4] / Arbitration group index
    nScanPort        : INT;                               // 仲裁扫描端口号 [1..8] / Arbitration port index
    bFound           : BOOL;                              // 仲裁命中标志 [-] / Arbitration hit flag
    nTopCount        : INT;                               // 已填待修位个数 [个] / Filled top repair slots
    nGuard           : DINT;                              // 循环守卫计数 [次]，上限常量化 / Loop guard counter with a constant bound
    bMaskClamped     : BOOL;                              // 本拍存在掩码超界位被屏蔽 [-] / Mask bits were suppressed this scan
    bPortClamped     : BOOL;                              // 本拍存在端口数超上限被钳位 [-] / A port count was clamped this scan
    bGroupClamped    : BOOL;                              // 本拍组数超上限被钳位 [-] / The group count was clamped this scan
    bPortShort       : BOOL;                              // 本拍存在某组端口数小于 1 [-] / A group has no usable port this scan
    bGroupShort      : BOOL;                              // 本拍组数小于 1 [-] / The group count is below one this scan
    bPortDeclMismatch: BOOL;                              // 声明首出端口与推导值不一致 [-] / Declared first-out port differs from the derived one
    bMaskJump        : BOOL;                              // 单拍掩码跳变位超阈值 [-] / Mask changed in more bits than the threshold
    g                : INT;                               // 组循环索引 [1..4] / Group loop index
    p                : INT;                               // 端口循环索引 [1..8] / Port loop index
END_VAR
VAR CONSTANT
    DL_GROUP_MAX     : INT := 4;                          // 聚合组数上限 [组] / Maximum group count
    DL_PORT_MAX      : INT := 8;                          // 组内端口数上限 [个] / Maximum ports per group
    DL_TOP_N         : INT := 3;                          // 待修输出位个数 [个] / Number of top repair slots
    DL_GROUP_STRIDE  : INT := 10;                         // 端口编码步长，组号乘该值加端口号 / Encoding stride of the top repair code
    DL_JUMP_MAX      : INT := 8;                          // 单拍掩码跳变位阈值 [位] / Changed bit threshold per scan
    DL_GUARD_MAX     : DINT := 96;                        // 循环守卫上限 [次] / Loop guard bound
    DL_WORD_BITS     : INT := 16;                         // 掩码字宽，超界位屏蔽的遍历上限 [位] / Mask word width
    DL_MASK_ONE      : WORD := 16#0001;                   // 单端口基准位 [位串] / Single port base bit
    DL_MASK_NONE     : WORD := 16#0000;                   // 全零掩码基准 [位串] / All zero mask reference
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出确定性默认值（公约：出口先赋；单拍标志每拍预清零，R25 第一律）
 *      Deterministic defaults first, one-scan flags pre-cleared every scan
 *-----------------------------------------------------------------------------*)
bAnyFault         := FALSE;                     // 看板派生量预清零（Dashboard flag pre-cleared）
uInfoCode         := 16#0000_0000;              // 信息级码每拍重算（Info code recomputed every scan）
bMaskClamped      := FALSE;                     // 掩码屏蔽标记预清零（Mask suppression flag pre-cleared）
bPortClamped      := FALSE;                     // 端口数钳位标记预清零（Port clamp flag pre-cleared）
bGroupClamped     := FALSE;                     // 组数钳位标记预清零（Group clamp flag pre-cleared）
bPortShort        := FALSE;                     // 空组标记预清零（Empty group flag pre-cleared）
bGroupShort       := FALSE;                     // 无组标记预清零（No group flag pre-cleared）
bPortDeclMismatch := FALSE;                     // 声明一致性标记预清零（Declared mismatch flag pre-cleared）
bMaskJump         := FALSE;                     // 掩码跳变标记预清零（Mask jump flag pre-cleared）
nGuard            := 0;                         // 循环守卫清零（Loop guard cleared）

(*------------------------------------------------------------------------------
 * 段 2｜沿检测无条件刷新（红线：实例在 CASE 之外每拍必刷）
 *      Edge detection refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据取非）
 *      First-scan initialisation following the single legal pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    FOR g := 1 TO DL_GROUP_MAX DO
        stBoard.anLastMask[g] := DL_MASK_NONE;  // 掩码差分基准清零，避免首拍假风暴（Baseline cleared to suppress a false burst）
        anGroupMaskOut[g]     := DL_MASK_NONE;  // 掩码出口清零，HMI 初值确定（Mask outlet cleared for a deterministic HMI start value）
    END_FOR
    FOR p := 1 TO DL_TOP_N DO
        anTopPortNo[p]   := 0;                  // 待修端口空位（Top repair slot empty）
        auTopPortCode[p] := 0;                  // 待修诊断码清零（Top repair code cleared）
    END_FOR
    stBoard.nLatchedGroup := 0;                 // 首出组号：0 表示无（No first-out group）
    stBoard.nLatchedPort  := 0;                 // 首出端口号：0 表示无（No first-out port）
    stBoard.uLatchedCode  := 0;                 // 首出码：0 表示未填（No first-out code）
    stBoard.bLatchValid   := FALSE;             // 首出锁存无效（First-out latch invalid）
    nTotalFaultPort       := 0;                 // 故障总数清零（Fault total cleared）
    nFirstGroup           := 0;                 // 首出组号出口清零（First-out group outlet cleared）
    nFirstPort            := 0;                 // 首出端口出口清零（First-out port outlet cleared）
    uFirstCode            := 0;                 // 首出码出口清零（First-out code outlet cleared）
    bFaultLatch           := FALSE;             // 故障锁存清零（Fault latch cleared）
    uErrInt               := 16#0000_0000;      // 故障码清零（Fault code cleared）
    bMaskBase             := FALSE;             // 差分基准待本拍装载（Baseline to be loaded this scan）
    ePhase                := E_DL_BoardPhase.eIdle; // 相位复位为待机（Phase reset to idle）
    bInit                 := TRUE;              // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜主状态机（枚举每个成员均有标签，末尾 ELSE 兜底到终端安全态）
 *      Main state machine, one label per member plus a trailing ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE ePhase OF

    E_DL_BoardPhase.eIdle: // 待机：未使能则清掩码保首出，使能则钳位参数后转扫描
        IF NOT bEnable THEN
            FOR g := 1 TO DL_GROUP_MAX DO
                anGroupMaskOut[g] := DL_MASK_NONE;  // 掉使能掩码清零，防止下游误联锁（Masks cleared while disabled）
            END_FOR
            nTotalFaultPort := 0;               // 故障总数清零（Fault total cleared）
            bAnyFault       := FALSE;           // 无故障派生量（No fault derived）
            ePhase          := E_DL_BoardPhase.eIdle; // 保持在待机（Stay idle）
        ELSE
            IF nGroupCount < 1 THEN
                nGroupUse    := 1;              // 无组：先给 1 供后续诊断（Fall back to one group）
                bGroupShort  := TRUE;           // 标记待置 0309（Flag for code 0309）
            ELSIF nGroupCount > DL_GROUP_MAX THEN
                nGroupUse    := DL_GROUP_MAX;   // 超上限钳位（Clamp to the upper bound）
                bGroupClamped := TRUE;          // 标记待置 0149（Flag for code 0149）
            ELSE
                nGroupUse := nGroupCount;       // 合法组数直通（Valid group count passed through）
            END_IF
            FOR g := 1 TO DL_GROUP_MAX DO
                nGuard := nGuard + 1;           // 守卫递增（Guard incremented）
                IF nGuard > DL_GUARD_MAX THEN
                    EXIT;                       // 守卫到顶即退出，防死循环（Bail out at the guard bound）
                END_IF
                IF g <= nGroupUse THEN
                    IF anGroupPortCount[g] < 1 THEN
                        auPortCntUse[g] := 1;   // 空组：先给 1 供后续诊断（Empty group falls back to one port）
                        bPortShort      := TRUE; // 标记待置 030A（Flag for code 030A）
                    ELSIF anGroupPortCount[g] > DL_PORT_MAX THEN
                        auPortCntUse[g] := DL_PORT_MAX; // 超上限钳位（Clamp to the upper bound）
                        bPortClamped    := TRUE;        // 标记待置 014A（Flag for code 014A）
                    ELSE
                        auPortCntUse[g] := anGroupPortCount[g]; // 合法端口数直通（Valid port count passed through）
                    END_IF
                ELSE
                    auPortCntUse[g] := 0;       // 未启用组记 0，不参与扫描（Unused group marked zero）
                END_IF
            END_FOR
            IF bGroupShort THEN
                bFaultLatch := TRUE;                        // 无诊断源：锁故障（No diagnostic source, latch a fault）
                uErrInt     := 16#0003_0309;                // 0309 组数小于 1（Group count below one）
                ePhase      := E_DL_BoardPhase.eFault;      // 进故障态（Enter the fault state）
            ELSIF bPortShort THEN
                bFaultLatch := TRUE;                        // 空组：锁故障（Empty group latches a fault）
                uErrInt     := 16#0003_030A;                // 030A 端口数小于 1（Port count below one）
                ePhase      := E_DL_BoardPhase.eFault;      // 进故障态（Enter the fault state）
            ELSE
                ePhase := E_DL_BoardPhase.eScanning;        // 参数可用，进入扫描（Parameters usable, start scanning）
            END_IF
        END_IF

    E_DL_BoardPhase.eScanning: // 扫描：屏蔽、计数、首出仲裁、待修排序、跳变差分，一趟完成
        nTotal    := 0;                         // 故障计数清零（Fault counter cleared）
        nBitScan  := 0;                         // 跳变位计数清零（Changed bit counter cleared）
        (* ① 屏蔽超界位并统计故障数，同时取组内最小故障端口号 *)
        nGuard := 0;                            // 子段守卫清零（Guard reset for this pass）
        FOR g := 1 TO DL_GROUP_MAX DO
            nGuard := nGuard + 1;               // 守卫递增（Guard incremented）
            IF nGuard > DL_GUARD_MAX THEN
                EXIT;                           // 守卫到顶即退出（Bail out at the guard bound）
            END_IF
            IF g <= nGroupUse THEN
                uBuildMask := anGroupFaultMask[g];      // 取原始掩码（Take the raw mask）
                nMinPort   := 0;                        // 组内最小端口号预清零（Lowest port pre-cleared）
                FOR p := 1 TO DL_WORD_BITS DO
                    nGuard := nGuard + 1;               // 守卫递增（Guard incremented）
                    IF nGuard > DL_GUARD_MAX THEN
                        EXIT;                           // 守卫到顶即退出（Bail out at the guard bound）
                    END_IF
                    IF p > auPortCntUse[g] THEN
                        IF (uBuildMask AND SHL(DL_MASK_ONE, p - 1)) <> DL_MASK_NONE THEN
                            bMaskClamped := TRUE;       // 超界位有值：标记待置 014B（Out-of-range bit held a value）
                        END_IF
                        uBuildMask := uBuildMask AND (NOT SHL(DL_MASK_ONE, p - 1)); // 超界位清零（Clear the out-of-range bit）
                    ELSE
                        IF (uBuildMask AND SHL(DL_MASK_ONE, p - 1)) <> DL_MASK_NONE THEN
                            nTotal := nTotal + 1;       // 在界内且为故障：计数（In range and faulted, count it）
                            IF nMinPort = 0 THEN
                                nMinPort := p;          // 首次命中即组内最小号（First hit is the lowest port）
                            END_IF
                        END_IF
                    END_IF
                END_FOR
                anGroupMaskOut[g] := uBuildMask;        // 屏蔽后掩码出口（Sanitised mask outlet）
                IF (anGroupFirstPort[g] > 0) AND (anGroupFirstPort[g] <> nMinPort) THEN
                    bPortDeclMismatch := TRUE;          // 声明值与推导值不一致：标记 014C（Declared value differs, flag 014C）
                END_IF
            ELSE
                anGroupMaskOut[g] := DL_MASK_NONE;      // 未启用组掩码清零（Unused group mask cleared）
            END_IF
        END_FOR
        nTotalFaultPort := nTotal;              // 故障总数出口（Fault total outlet）
        bAnyFault       := (nTotal > 0);        // 存在故障（Any fault present）
        (* ② 首出仲裁：仅未锁存时执行，组号优先、端口号次之，取字典序最小 *)
        nGuard := 0;                            // 子段守卫清零（Guard reset for this pass）
        IF (NOT stBoard.bLatchValid) AND (nTotal > 0) THEN
            bFound      := FALSE;               // 命中标志预清零（Hit flag pre-cleared）
            nScanGroup  := 0;                   // 仲裁组号预清零（Arbitration group pre-cleared）
            nScanPort   := 0;                   // 仲裁端口号预清零（Arbitration port pre-cleared）
            FOR g := 1 TO nGroupUse DO
                nGuard := nGuard + 1;           // 守卫递增（Guard incremented）
                IF nGuard > DL_GUARD_MAX THEN
                    EXIT;                       // 守卫到顶即退出（Bail out at the guard bound）
                END_IF
                FOR p := 1 TO auPortCntUse[g] DO
                    nGuard := nGuard + 1;       // 守卫递增（Guard incremented）
                    IF nGuard > DL_GUARD_MAX THEN
                        EXIT;                   // 守卫到顶即退出（Bail out at the guard bound）
                    END_IF
                    IF (NOT bFound) AND ((anGroupMaskOut[g] AND SHL(DL_MASK_ONE, p - 1)) <> DL_MASK_NONE) THEN
                        bFound      := TRUE;    // 命中即锁存（Latch on the first hit）
                        nScanGroup  := g;       // 记录组号（Record the group）
                        nScanPort   := p;       // 记录端口号（Record the port）
                    END_IF
                END_FOR
            END_FOR
            IF bFound THEN
                stBoard.nLatchedGroup := nScanGroup;                  // 锁存组号（Latch the group）
                stBoard.nLatchedPort  := nScanPort;                   // 锁存端口号（Latch the port）
                stBoard.uLatchedCode  := auGroupFirstCode[nScanGroup]; // 组内首出码代表该组（The group first-out code represents the group）
                stBoard.bLatchValid   := TRUE;                        // 置锁存有效（Mark the latch valid）
            END_IF
        END_IF
        (* ③ 待修排序：与仲裁同一字典序，取前三位，空位填 0 *)
        nGuard := 0;                            // 子段守卫清零（Guard reset for this pass）
        nTopCount := 0;                         // 已填位个数清零（Filled slot count cleared）
        FOR g := 1 TO nGroupUse DO
            nGuard := nGuard + 1;               // 守卫递增（Guard incremented）
            IF nGuard > DL_GUARD_MAX THEN
                EXIT;                           // 守卫到顶即退出（Bail out at the guard bound）
            END_IF
            FOR p := 1 TO auPortCntUse[g] DO
                nGuard := nGuard + 1;           // 守卫递增（Guard incremented）
                IF nGuard > DL_GUARD_MAX THEN
                    EXIT;                       // 守卫到顶即退出（Bail out at the guard bound）
                END_IF
                IF (nTopCount < DL_TOP_N) AND ((anGroupMaskOut[g] AND SHL(DL_MASK_ONE, p - 1)) <> DL_MASK_NONE) THEN
                    nTopCount := nTopCount + 1;                        // 占一个待修位（Occupy one slot）
                    anTopPortNo[nTopCount]   := g * DL_GROUP_STRIDE + p; // 编码：组号乘十加端口号（Encode as group times ten plus port）
                    auTopPortCode[nTopCount] := auGroupFirstCode[g];    // 诊断码取组内首出码（Code taken from the group first-out code）
                END_IF
            END_FOR
        END_FOR
        FOR p := 1 TO DL_TOP_N DO
            IF p > nTopCount THEN
                anTopPortNo[p]   := 0;          // 不足三位填空位（Empty slot marked zero）
                auTopPortCode[p] := 0;          // 空位码清零（Empty slot code cleared）
            END_IF
        END_FOR
        (* ④ 掩码跳变风暴：单拍变化位数超阈值只作趋势提示，不锁存、不置故障位 *)
        nGuard := 0;                            // 子段守卫清零（Guard reset for this pass）
        IF bMaskBase THEN
            FOR g := 1 TO DL_GROUP_MAX DO
                uDiff := anGroupMaskOut[g] XOR stBoard.anLastMask[g]; // 掩码差分（Mask difference）
                FOR p := 1 TO DL_PORT_MAX DO
                    IF (uDiff AND SHL(DL_MASK_ONE, p - 1)) <> DL_MASK_NONE THEN
                        nBitScan := nBitScan + 1;   // 变化位计数（Changed bit counted）
                    END_IF
                END_FOR
            END_FOR
            IF nBitScan > DL_JUMP_MAX THEN
                bMaskJump := TRUE;              // 超阈值：标记趋势码 030B（Above the threshold, flag trend code 030B）
            END_IF
        END_IF
        FOR g := 1 TO DL_GROUP_MAX DO
            stBoard.anLastMask[g] := anGroupMaskOut[g]; // 判读完再装载新基准（Load the baseline after the comparison）
        END_FOR
        bMaskBase := TRUE;                      // 基准已就绪（Baseline ready）
        ePhase    := E_DL_BoardPhase.eIdle;     // 本拍结束回待机，无长驻态（Back to idle, never resident）

    E_DL_BoardPhase.eFault: // 故障：输出保持，等复位沿（Fault, outputs held until the reset edge）
        bAnyFault := (nTotalFaultPort > 0);     // 故障位保持期间派生量仍可读（Derived flag stays readable）

    ELSE
        bFaultLatch := TRUE;                    // 非法状态兜底锁存（Illegal state latched）
        uErrInt     := 16#0003_030C;            // 030C 非法状态兜底（Illegal state fallback code）
        ePhase      := E_DL_BoardPhase.eFault;  // 进终端安全态（Enter the terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 5｜首出换出（锁存值转出到引脚，复位分支在本段之后执行）
 *      First-out outlet mapping, the reset block runs after this section
 *-----------------------------------------------------------------------------*)
nFirstGroup := stBoard.nLatchedGroup;           // 首出组号出口（First-out group outlet）
nFirstPort  := stBoard.nLatchedPort;            // 首出端口号出口（First-out port outlet）
uFirstCode  := stBoard.uLatchedCode;            // 首出码出口（First-out code outlet）

(*------------------------------------------------------------------------------
 * 段 6｜复位（置于仲裁与换出之后，保证复位当拍首出即为空，下一拍重新仲裁）
 *      Reset runs after arbitration and outlet mapping, so the first-out is empty
 *      on the reset cycle and re-arbitrated on the next one
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    stBoard.nLatchedGroup := 0;                 // 清锁存组号（Clear the latched group）
    stBoard.nLatchedPort  := 0;                 // 清锁存端口号（Clear the latched port）
    stBoard.uLatchedCode  := 0;                 // 清锁存码（Clear the latched code）
    stBoard.bLatchValid   := FALSE;             // 清锁存有效位（Clear the latch valid flag）
    nFirstGroup           := 0;                 // 复位当拍首出为空（First-out empty on the reset cycle）
    nFirstPort            := 0;                 // 复位当拍首出为空（First-out empty on the reset cycle）
    uFirstCode            := 0;                 // 复位当拍首出码为空（First-out code empty on the reset cycle）
    bFaultLatch           := FALSE;             // 清故障锁存（Clear the fault latch）
    uErrInt               := 16#0000_0000;      // 清故障码（Clear the fault code）
    IF ePhase = E_DL_BoardPhase.eFault THEN
        ePhase := E_DL_BoardPhase.eIdle;        // 故障态复位回待机（Fault returns to idle）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜码位定级（单一优先级链，全拍只写一次 uErrorId）
 *      Single priority chain, the event code is written once per scan
 *-----------------------------------------------------------------------------*)
IF bMaskJump THEN
    uInfoCode := 16#0003_030B;                  // 优先级一：掩码跳变风暴，仅趋势提示（Mask burst, trend only）
ELSIF bMaskClamped THEN
    uInfoCode := 16#0003_014B;                  // 优先级二：超界位被屏蔽（Out-of-range bits suppressed）
ELSIF bPortDeclMismatch THEN
    uInfoCode := 16#0003_014C;                  // 优先级三：声明首出端口不一致（Declared first-out port mismatch）
ELSIF bGroupClamped THEN
    uInfoCode := 16#0003_0149;                  // 优先级四：组数超上限已钳位（Group count clamped）
ELSIF bPortClamped THEN
    uInfoCode := 16#0003_014A;                  // 优先级五：端口数超上限已钳位（Port count clamped）
ELSIF bGroupShort THEN
    uInfoCode := 16#0003_0309;                  // 优先级六：组数小于 1（Group count below one）
ELSIF bPortShort THEN
    uInfoCode := 16#0003_030A;                  // 优先级七：端口数小于 1（Port count below one）
ELSE
    uInfoCode := 16#0000_0000;                  // 无事件（No event）
END_IF

eState := ePhase;                               // 相位出口（Phase outlet）
bError := bFaultLatch;                          // 故障位只反映故障级锁存（Fault bit reflects the latch only）
IF bFaultLatch THEN
    uErrorId := uErrInt;                        // 故障级码优先透出（Fault level code has priority）
ELSE
    uErrorId := uInfoCode;                      // 无故障透出本拍信息级码（Info code exposed otherwise）
END_IF
END_FUNCTION_BLOCK
