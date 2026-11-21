(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PresetCounterSat
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 分类     (Category)   : 计数功能块（Function Block · Counter）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 功能简介 (Function)   : 带饱和预设计数器：上/下双向计数（上升沿生效），
 *                         到达上限（nPreset）或下限（nLowLimit）饱和不回绕
 *                         ——上计数在 nCount >= nPreset 时拒绝递增并保持
 *                         bSatHigh，下计数在 nCount <= nLowLimit 时拒绝递减
 *                         并保持 bSatLow。到达上限输出保持型完成标志 bDone
 *                         与单拍阈值事件 bThreshold（首次到达一拍脉冲，遵循
 *                         R25 单拍标志生命周期三律）。装载 bLoad 优先级最高，
 *                         复位 bReset 次之，同拍双计数互相抵消不偏置任何方向。
 *                         与已入库 FB_DL_EventCounter（回绕 + 比较输出通用
 *                         事件计数）、FB_DL_ModuloCounter（取模工位索引）
 *                         职责分离——本块是饱和计数（批次计数 / 托盘满载
 *                         场景），越界语义固定为钳位停走。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 库 Counter 计数器分类的功能域
 *                         与参数域，来源标签 lgf-counter），饱和计数语义为
 *                         公开计数器行为域，仅借分类/参数域/命名，clean-room
 *                         实现，未复制任何厂商私有库源码，不构成衍生作品。
 * 日期     (Date)       : 2026-11-15 ｜ 作者 (Author): Daoli Library
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 *
 *------------------------------------------------------------------------------
 * 【引脚契约 / Pin contract】
 *   输入 bCountUp   : BOOL — 上计数脉冲输入，上升沿 +1；
 *   输入 bCountDown : BOOL — 下计数脉冲输入，上升沿 -1；
 *   输入 bLoad      : BOOL — 装载预设值，上升沿生效（优先级最高）；
 *   输入 nPreset    : DINT — 上限预设值 [个]，>= nLowLimit，默认 100；
 *   输入 nLowLimit  : DINT — 下限预设值 [个]，<= nPreset，默认 0；
 *   输入 bReset     : BOOL — 复位到下限，上升沿生效（次优先级，兼故障解除）；
 *   输出 nCount     : DINT — 当前计数值 [个]，饱和域 [nLowLimit, nPreset]；
 *   输出 bSatHigh   : BOOL — 已达上限饱和（保持型，逐拍重算）；
 *   输出 bSatLow    : BOOL — 已达下限饱和（保持型，逐拍重算）；
 *   输出 bDone      : BOOL — 计数到达上限（保持型，逐拍重算）；
 *   输出 bThreshold : BOOL — 首次到达上限单拍脉冲（R25 三律）；
 *   输出 uErrorId   : UDINT — 故障码，0 = 无故障。
 *
 * 【优先级序 / Priority order（写死防歧义）】
 *   参数故障锁存 > 装载（bLoad 沿）> 复位（bReset 沿）> 同拍双计数抵消
 *   （计数值不变，不偏置任何方向）> 单向上计数 > 单向下计数 > 保持。
 *   同拍装载与计数脉冲：装载覆盖计数（计数脉冲被吞，不补发不记账）。
 *   同拍装载与复位：装载优先（覆盖复位到下限的行为）。
 *
 * 【饱和语义 / Saturation semantics（写死防误解）】
 *   上饱和：nCount = nPreset 时再收上计数沿 → 计数值保持 nPreset 不回绕、
 *           不取模，bSatHigh 保持 TRUE，脉冲被吞不置任何事件码（饱和本身
 *           是正常工况语义而非故障，上层以 bSatHigh/bDone 感知）；
 *   下饱和：nCount = nLowLimit 时再收下计数沿 → 保持 nLowLimit，bSatLow
 *           保持 TRUE，脉冲同样被吞；
 *   与 FB_DL_EventCounter 的 bWrap = FALSE 饱和模式语义一致但本块无回绕
 *   选项——批次/满载场景回绕是危险行为，设计上直接删除该自由度。
 *
 * 【bThreshold 单拍 R25 三律落地 / One-shot pulse lifecycle】
 *   置位律：仅「本拍到达上限 AND 上拍未在限」的扫描拍置 TRUE
 *           （bReached 为边沿基准，单一来源，仅由计数出口单点推导）；
 *   自清律：bThreshold 每拍预清 FALSE，无到达沿自动回落，不锁存；
 *   基准律：bReached 每拍在计数出口后单点刷新为 (nCount >= nPreset)，
 *           无第二份镜像状态；故障拍强制 bReached := FALSE，故障解除后
 *           再次到达会重新给出一拍脉冲（诊断链可见）。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 nPreset < nLowLimit → 参数非法故障锁存 16#0001_0212：计数值强制钳到
 *      nLowLimit，计数/装载全部冻结，仅 bReset 上升沿解除（R15：故障级
 *      锁存仅解除路径清码）；解除后首次满足条件重新计数；
 *   B2 先判界后加减：上计数前判 nCount >= nPreset、下计数前判
 *      nCount <= nLowLimit，杜绝 DINT 极值 +1/-1 回绕穿透判据；
 *   B3 同拍 bCountUp/bCountDown 同时有效 → 计数不变（不偏置任何方向）；
 *   B4 装载值即 nPreset 引脚现值（装载拍实时采样，非缓存旧值）；
 *   B5 bReset 上升沿把计数值直接置 nLowLimit 并同时清除故障锁存。
 *
 * 【调用示例 / Call example】
 *   「托盘满载计数：装满 100 件给满托信号，人工换托后复位」
 *   fbPalletCnt(bCountUp := bPartInFeed, bCountDown := bPartRejectOut,
 *               bLoad := FALSE, nPreset := 100, nLowLimit := 0,
 *               bReset := bPalletChanged, nCount => nPalletCount,
 *               bSatHigh => , bSatLow => , bDone => bPalletFull,
 *               bThreshold => bPalletFullPulse, uErrorId => uCntErr);
 *
 * 【平台移植注意 / Porting notes】
 *   全部运算为 DINT 整数比较与加减，先判界后运算的次序保证永不触发
 *   DINT 极值回绕，无浮点、无除法、无定时依赖，各平台行为一致。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 托盘满载计数：产线件流逐件 +1，装满 nPreset 件给满托信号（bDone/
 *      bThreshold），人工换托后 bReset 清零重新计件；
 *   ② 批次计数器：批次目标 nPreset 件，剔除品经 bCountDown 回退，计数
 *      上下饱和防止误键导致的负数或超量程静默错值；
 *   ③ 收线长度/圈数计量：到达设定圈数停机收卷（饱和停走保证计数器停在
 *      满值可读，回绕式计数会让操作工无法读出实际完成量）；
 *   ④ 重复触发防护：bThreshold 单拍脉冲驱动一次性动作（满托打印/批次
 *      结束报文），保持型 bDone 驱动持续状态（满托指示灯）。
 *
 * 【保持型与单拍输出关系表 / Held vs one-shot output relation】
 *   输出          类型     置位条件                     复位条件
 *   bSatHigh     保持型   nCount >= nPreset            nCount 降回限内
 *   bSatLow      保持型   nCount <= nLowLimit          nCount 升回限内
 *   bDone        保持型   nCount >= nPreset            nCount 降回限内/故障
 *   bThreshold   单拍     首次到达拍（含装载到达）      下一拍自动回落
 *   bSatHigh 与 bDone 判据相同但语义分层：bSatHigh 描述"在限停走状态"，
 *   bDone 描述"任务完成状态"，分开输出便于上层对停走与完成做不同联锁。
 *
 * 【典型时序推演 / Typical timing walkthrough】
 *   设 nPreset = 3，nLowLimit = 0，上电 nCount = 0：
 *     拍 1 上沿 → 1；拍 2 上沿 → 2；拍 3 上沿 → 3，bDone TRUE，
 *       bThreshold 单拍 TRUE，bSatHigh TRUE；
 *     拍 4 上沿 → 保持 3（上饱和），bThreshold FALSE（无新到达沿）；
 *     拍 5 下沿 → 2，bSatHigh/bDone 回落，bThreshold 无脉冲（2 不是到达）；
 *     拍 6 上沿 → 3，bThreshold 单拍 TRUE（bReached 已回落，重新到达）；
 *     拍 7 bReset 沿 → 0，bSatLow TRUE，无脉冲；
 *   结论：bThreshold 严格对应"从限外进入上限"的每一次跃迁，同限保持
 *   与复位不触发，装载到达触发（口径与验收推演 C1~C7 一致）。
 *
 * 【参数退化域 / Degenerate parameter domains】
 *   nPreset = nLowLimit：计数域退化为单点，装载到该点后双向均饱和停走
 *   （验收推演 C7）；上电 nCount = 0 若低于下限（如 nLowLimit = 5），
 *   bSatLow 立即为 TRUE，首个下计数沿被吞直至装载/复位对齐下限——
 *   上层应在上电后先装载或复位一次，保证计数值落在合法饱和域内。
 *
 * 【同族职责分离 / Family separation】
 *   FB_DL_EventCounter：通用事件计数（回绕/饱和双模式 + 阈值比较输出）；
 *   FB_DL_ModuloCounter：取模工位索引（循环工位场景）；本块：固定饱和
 *   计数（批次满载），三者语义正交、零互相调用。
 *
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓ ｜ R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 标准运算 ✓ ｜ R4 先判界后运算/
 *                           故障锁存仅解除路径清码/参数钳位 ✓
 *                         R5 全变量中英双语同行注释 ✓ ｜ R6 N/A（无主状态机，
 *                           优先级 IF-ELSIF 链即状态裁决，规格豁免 ENUM）✓
 *                         R7 四个 R_TRIG 主体最前部无条件刷新 ✓ ｜ R8 界限/
 *                           码值全常量化，无魔法数 ✓
 * 验收推演 (Acceptance) :
 *   C1 单发递增链：nPreset=3, nLowLimit=0，连发 3 个上沿 → 1/2/3，第 3 拍
 *      bDone TRUE 且 bThreshold 单拍 TRUE；第 4 个上沿 → 保持 3，bSatHigh
 *      TRUE，bThreshold 无脉冲；
 *   C2 下饱和：nCount=0 时发下沿 → 保持 0，bSatLow TRUE，无事件码；
 *   C3 同拍双计数：nCount=1 时同拍上/下沿 → 保持 1，无偏置；
 *   C4 装载优先：nCount=0 时同拍 bLoad 沿 + 上沿 → nCount := nPreset，
 *      bThreshold 单拍 TRUE（首次到达），上沿被覆盖不记账；
 *   C5 复位：bCount=5 时 bReset 沿 → nCount := nLowLimit，bDone/bSatHigh
 *      回落，bThreshold 无脉冲（复位不算"到达"）；
 *   C6 参数非法：nPreset=2 < nLowLimit=5 → 故障锁存 0212，nCount 强制 5，
 *      计数冻结；bReset 沿 → 当拍解除锁存并把计数压到下限，但同一拍段 3
 *      复检参数仍非法即刻**重新锁存**（参数不修正则计数不恢复）；须先把
 *      nPreset 改为 >= nLowLimit，再给 bReset 沿才彻底解除并可重新计数
 *      （v1.0.1 终审勘误：原文"bReset 沿 → 解除，可重新计数"未写明参数前置，
 *      与"锁存置位每拍检测"的实现不符）；
 *   C7 下限装载边界：nPreset = nLowLimit = 7 → 上电 nCount=0，bSatLow TRUE；
 *      bLoad 沿 → nCount := 7，bThreshold 单拍 TRUE，此后双向均饱和停走。
 *
 * 【故障码表 / Error code table】
 *   16#0001_0212  参数非法：上限预设 nPreset < 下限预设 nLowLimit，故障级
 *                 锁存，计数冻结在 nLowLimit，仅 bReset 上升沿解除（0212
 *                 空闲，0210/0211 已被 EventCounter/ModuloCounter 登记）。
 *
 * 【设计要点 / Key notes】
 *   ① 计数值单点出口：段 4 优先级链只写 nWork，段 4 末 nCount := nWork
 *      单点回写，故障段强制钳位也只改出口，任何路径不出现第二份计数镜像，
 *      杜绝多出口读改写竞态（沿用库内 EventCounter 修复后的单点出口范式）；
 *   ② 先判界后运算：加/减算全部在边界预判之后执行，DINT 极值 +1/-1 回绕
 *      在数学上不可达（R25 家族通用防穿透写法）；
 *   ③ 故障锁存生命周期：置位（段 3 每拍检测）→ 冻结（段 4 闸门）→ 解除
 *      （仅段 2 复位沿），三段各一入口，无第三条改动路径（R15）；
 *   ④ 饱和吞脉冲不置码：饱和属正常工况语义，置码会造成诊断链噪音，
 *      上层以 bSatHigh/bSatLow 感知（与 EventCounter 溢出一拍脉冲口径
 *      不同，两块语义分层，注释在两侧各自写死）；
 *   ⑤ 事件型组件免首扫：计数由脉冲沿驱动，无连续量同步语义，按 R23
 *      不设 bInit 跟踪逻辑，上电即处于下限饱和观测态。
 *
 * 【实现选择 / Implementation choice】
 *   无主状态机（规格豁免 ENUM）：饱和计数的行为本质是「边沿事件 + 优先级
 *   裁决 + 单点出口」，用 IF-ELSIF 优先级链表达比 ENUM+CASE 更短且无空态；
 *   计数值单点出口（nCount := _nWork 后全段共享），bSatHigh/bSatLow/bDone
 *   全部由出口值逐拍重算派生，无第二份计数镜像，杜绝读改写竞态；
 *   本块为事件型计数组件，无连续量同步语义，按 R23 免首扫，不设 bInit。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · LGF Counter 组）
 *   2026-11-15  v1.0.1  终审勘误：验收推演 C6 补写"参数未修正时 bReset 沿当拍
 *                       重新锁存"的前置条件（原文易误读为复位即可恢复计数）；
 *                       代码行为未改动，故障码 0001_0212 复核无冲突
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PresetCounterSat
VAR_INPUT
    bCountUp   : BOOL;                     // 上计数脉冲输入，上升沿 +1 / Count-up pulse input, rising edge increments
    bCountDown : BOOL;                     // 下计数脉冲输入，上升沿 -1 / Count-down pulse input, rising edge decrements
    bLoad      : BOOL;                     // 装载预设值，上升沿生效（优先级最高）/ Load preset, rising edge, top priority
    nPreset    : DINT := 100;              // 上限预设值 [个]，>= nLowLimit / Upper preset [pieces], at least nLowLimit
    nLowLimit  : DINT := 0;                // 下限预设值 [个]，<= nPreset / Lower preset [pieces], at most nPreset
    bReset     : BOOL;                     // 复位到下限，上升沿生效（兼故障解除）/ Reset to lower limit, rising edge, also releases the fault latch
END_VAR
VAR_OUTPUT
    nCount     : DINT := 0;                // 当前计数值 [个]，饱和域 [nLowLimit, nPreset] / Current count [pieces], saturated within [nLowLimit, nPreset]
    bSatHigh   : BOOL;                     // 已达上限饱和（保持型）/ Saturated at upper limit (held)
    bSatLow    : BOOL;                     // 已达下限饱和（保持型）/ Saturated at lower limit (held)
    bDone      : BOOL;                     // 计数到达上限（保持型）/ Count reached upper limit (held)
    bThreshold : BOOL;                     // 首次到达上限单拍脉冲（R25 三律）/ First-arrival one-shot pulse (R25 three rules)
    uErrorId   : UDINT;                    // 故障码，0 = 无故障 / Error code, 0 = none
END_VAR
VAR
    fbTrigUp   : R_TRIG;                   // 上计数边沿 / Count-up edge detector
    fbTrigDn   : R_TRIG;                   // 下计数边沿 / Count-down edge detector
    fbTrigLoad : R_TRIG;                   // 装载边沿 / Load edge detector
    fbTrigRst  : R_TRIG;                   // 复位边沿 / Reset edge detector
    bReached   : BOOL := FALSE;            // 内部到达标志（阈值事件边沿基准，单一来源）/ Internal reached flag (threshold edge baseline, single source)
    bFaultLatch: BOOL;                     // 参数非法故障锁存（仅复位沿解除）/ Invalid-parameter fault latch (released only by reset edge)
    nWork      : DINT;                     // 计数运算工作副本（单点出口）/ Working copy for count arithmetic (single outlet)
    bUpEdge    : BOOL;                     // 本拍上计数沿有效 / Up edge active this scan
    bDnEdge    : BOOL;                     // 本拍下计数沿有效 / Down edge active this scan
    bLoadEdge  : BOOL;                     // 本拍装载沿有效 / Load edge active this scan
    bRstEdge   : BOOL;                     // 本拍复位沿有效 / Reset edge active this scan
END_VAR
VAR CONSTANT
    DL_CNT_ERR_PARAM : UDINT := 16#0001_0212; // 参数非法故障码（上限 < 下限）/ Error code for invalid parameters (preset below lower limit)
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜边沿实例无条件周期刷新（R7 红线：严禁置于 IF/CASE 分支内）
 *      Unconditional per-cycle refresh of all edge instances (R7 redline)
 *      四个 R_TRIG 全部在主体最前部刷新，与任何条件无关
 *      All four R_TRIG instances refreshed at the very top of the body
 *-----------------------------------------------------------------------------*)
fbTrigUp(CLK   := bCountUp);               // 上计数沿（Up edge）
fbTrigDn(CLK   := bCountDown);             // 下计数沿（Down edge）
fbTrigLoad(CLK := bLoad);                  // 装载沿（Load edge）
fbTrigRst(CLK  := bReset);                 // 复位沿（Reset edge）
bUpEdge   := fbTrigUp.Q;                   // 本拍上计数沿（Up edge this scan）
bDnEdge   := fbTrigDn.Q;                   // 本拍下计数沿（Down edge this scan）
bLoadEdge := fbTrigLoad.Q;                 // 本拍装载沿（Load edge this scan）
bRstEdge  := fbTrigRst.Q;                  // 本拍复位沿（Reset edge this scan）

(*------------------------------------------------------------------------------
 * 段 2｜输出预清零（R25 自清律）+ 复位/故障解除路径
 *      Output preset clearing (R25 self-clear rule) + reset/release paths
 *      bThreshold 每拍预清 FALSE：无到达沿自动回落，不锁存
 *      bThreshold preset FALSE each scan: falls back without an arrival edge
 *-----------------------------------------------------------------------------*)
bThreshold := FALSE;                       // 单拍脉冲预清（One-shot preset cleared）
uErrorId   := 16#0000_0000;                // 故障码出口预清，段 6 按锁存态重写 / Error outlet preset, rewritten by stage 6 per latch state

IF bRstEdge THEN                           // 复位沿：计数回下限并解除故障锁存 / Reset edge: count back to lower limit and release the latch
    bFaultLatch := FALSE;                  // 故障锁存解除（R15 解除路径唯一）/ Latch released (unique release path per R15)
    nWork       := nLowLimit;              // 计数值回下限（Count back to lower limit）
    nCount      := nWork;                  // 计数单点出口（Single outlet）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数防御（边界 B1）：nPreset < nLowLimit → 故障锁存，计数冻结
 *      Parameter guard (B1): preset below lower limit latches a fault
 *   锁存期间计数值强制钳到 nLowLimit、全部计数/装载动作冻结，仅复位沿解除
 *   While latched, count is forced to nLowLimit and all actions frozen
 *   锁存生命周期三段：置位（本段检测）→ 冻结（段 4 闸门跳过）→ 解除（段 2
 *   复位沿），每段单入口，无第三条改动路径（R15 故障级公约）
 *   Latch lifecycle: raise here, freeze in stage 4, release only in stage 2
 *-----------------------------------------------------------------------------*)
IF nPreset < nLowLimit THEN
    bFaultLatch := TRUE;                    // 参数非法故障锁存（Invalid-parameter latch）
END_IF

IF NOT bFaultLatch THEN

    (*--------------------------------------------------------------------------
     * 段 4｜计数主逻辑（优先级序写死）：装载 > 复位 > 双计数抵消 > 单向
     *      Counting main logic (fixed priority): load > reset > cancel > single
     *   注意复位沿已在段 2 处理计数值回下限，此处 ELSIF 链只在非复位拍进入；
     *   同拍装载与复位冲突时装载胜出（覆盖段 2 的回下限值）
     *   A load edge on the same scan as reset wins over the reset value
     *-------------------------------------------------------------------------*)
    IF bLoadEdge THEN
        nWork := nPreset;                   // 装载优先级最高：写入引脚现值（Load top priority: live pin value）
    ELSIF bRstEdge THEN
        nWork := nLowLimit;                 // 复位次之：回到下限（Reset next: back to lower limit）
    ELSIF bUpEdge AND bDnEdge THEN
        nWork := nCount;                    // 同拍双计数抵消：计数不变不偏置（Dual edges cancel: no bias）
        (* 口径注释：双沿抵消不置事件码——抵消属输入侧拍点重叠的正常现象，
           置码会造成诊断噪音；与 EventCounter 的信息级 0101 抵消码口径
           不同（该块有显式抵消码），本块按规格只保证"不偏置任何方向" *)
    ELSIF bUpEdge THEN
        IF nCount >= nPreset THEN
            nWork := nPreset;               // 上饱和：钳位停走不回绕（Upper saturation: clamp and hold, no wrap）
        ELSE
            nWork := nCount + 1;            // 先判界后加算，无极值回绕（Boundary pre-checked increment）
        END_IF
    ELSIF bDnEdge THEN
        IF nCount <= nLowLimit THEN
            nWork := nLowLimit;             // 下饱和：钳位停走不回绕（Lower saturation: clamp and hold, no wrap）
        ELSE
            nWork := nCount - 1;            // 先判界后减算，无极值回绕（Boundary pre-checked decrement）
        END_IF
    ELSE
        nWork := nCount;                    // 无事件保持（No event, hold）
    END_IF
    nCount := nWork;                        // 计数单点出口（Single outlet for the count）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜保持型输出派生：全部由计数出口逐拍重算，无第二份镜像
 *      Held outputs derived from the count outlet each scan, no mirror state
 *   派生式而非锁存式：三路保持型输出每拍从计数出口现值重算，即使计数
 *   被装载/复位/故障强行搬移，输出也在同拍对齐，无跨拍错位窗口；
 *   bSatHigh 与 bDone 判据相同但语义分层（停走态 vs 完成态），见头注释
 *   关系表，上层可分别做联锁与指示。
 *-----------------------------------------------------------------------------*)
IF bFaultLatch THEN
    nCount   := nLowLimit;                  // 故障期计数值强制钳到下限（Forced clamp while latched）
    bSatHigh := FALSE;                      // 故障期上限饱和态清空（Upper saturation cleared while latched）
    bSatLow  := TRUE;                       // 故障期钳在下限 → 下饱和态成立（Clamped at lower limit, so lower saturation holds）
    bDone    := FALSE;                      // 故障期完成标志清空（Done cleared while latched）
ELSE
    bSatHigh := (nCount >= nPreset);        // 上饱和派生（Upper saturation derived）
    bSatLow  := (nCount <= nLowLimit);      // 下饱和派生（Lower saturation derived）
    bDone    := (nCount >= nPreset);        // 完成标志派生（Done derived）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜bThreshold 单拍脉冲（R25 三律：置位/自清/基准单一来源）
 *      bThreshold one-shot pulse (R25: set / self-clear / single-source baseline)
 *   置位：本拍在限 AND 上拍未在限（bReached 边沿基准）；
 *   自清：段 2 每拍预清，无沿自动回落；
 *   基准：bReached 本拍末单点刷新，故障拍强制 FALSE（解除后可再触发）。
 *   装载/计数任一路径到达上限均视为"到达"（口径写死）；
 *   复位路径回下限不算到达，不给脉冲（验收推演 C5）。
 *   跃迁真值表（上拍 bReached → 本拍在限 → bThreshold）：
 *     FALSE → TRUE  ：单拍 TRUE（首次到达或离开后重新到达）
 *     TRUE  → TRUE  ：FALSE（同限保持不触发）
 *     任意  → FALSE ：FALSE（离开上限不触发，下限侧无阈值事件）
 *-----------------------------------------------------------------------------*)
IF (NOT bFaultLatch) AND (nCount >= nPreset) AND (NOT bReached) THEN
    bThreshold := TRUE;                     // 首次到达单拍脉冲（First-arrival one-shot）
END_IF

IF bFaultLatch THEN
    bReached := FALSE;                      // 故障拍强制清基准，解除后可再触发 / Baseline force-cleared while latched, re-armable after release
ELSE
    bReached := (nCount >= nPreset);        // 边沿基准单点刷新（Baseline refreshed at a single point）
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜uErrorId 出口（R15：故障级锁存优先透出）
 *      uErrorId outlet (R15: latched fault code has priority)
 *-----------------------------------------------------------------------------*)
IF bFaultLatch THEN
    uErrorId := DL_CNT_ERR_PARAM;           // 参数非法锁存码（Latched parameter code）
ELSE
    uErrorId := 16#0000_0000;               // 无故障透出零码（Zero when healthy）
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜验收推演索引 / Acceptance walkthrough index
 *   C1 递增链 1/2/3 → 第 3 拍 bDone+单拍；第 4 拍饱和停走无脉冲
 *   C2 下饱和保持 0；C3 双沿抵消不偏置；C4 装载覆盖计数并给单拍
 *   C5 复位回下限无脉冲；C6 参数非法锁存 0212 仅复位沿解除
 *   C7 nPreset = nLowLimit 退化域：装载拍单拍触发后双向饱和
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
