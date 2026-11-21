(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ArraySearchFirst
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : lgf-datahandling（T2-1 LGF Data Handling 组回补）
 * 作者/日期             : Daoli Library / 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），数组经 VAR_IN_OUT 注入
 * 功能简介 (Function)   : 在注入数组前 nCount 个元素中线性搜索首个命中目标值的索引；
 *                         可选全量计数模式（bSearchAll）继续扫描统计命中总数。
 *                         不要求有序，O(n) 单遍扫描。
 *                         与 FC_DL_BinarySearchLReal 职责分离：
 *                         本块 = 无序数组通用查找（O(n)）；二分块 = 升序数组快速查找（O(log n)）。
 *                         典型现场用途：批号 / 配方号在注册表中的定位、
 *                         传感器标定表按名义值反查槽位、物料序列首个异常值定位。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 公开手册 Data Handling 分类中
 *                         数组查找族的功能分类与参数域），只借分类/参数域/命名，
 *                         clean-room 实现，未复制任何源码。来源标签：lgf-datahandling。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 *
 * 【接口契约 / Interface contract】
 *   输入  ：bExecute 上升沿触发一次扫描（内部 R_TRIG，调用方无需自备边沿块）；
 *           fTarget 目标值；nCount 搜索范围（前 nCount 个元素）；
 *           bSearchAll 全量计数模式开关。
 *   输出  ：bDone 搜索完成单拍脉冲；bFound 至少命中一个；
 *           nIndex 首个命中索引（未命中恒 -1）；uHitCount 命中总数；
 *           uErrorId 故障码。
 *   注入  ：afData 搜索体由调用方声明并经 VAR_IN_OUT 注入，
 *           容量上限 DL_SRH_MAX = 1024 元素，本块不持有数组内存。
 *   纪律  ：同一实例在同一扫描周期内只能被调用一次（R_TRIG 边沿语义约束）。
 *
 * 【使用示例 / Usage example】
 *   VAR
 *       afRecipeTab : ARRAY[0..1023] OF LREAL;  // 调用方持有搜索体
 *       fbFindBatch : FB_DL_ArraySearchFirst;   // 搜索实例
 *   END_VAR
 *   fbFindBatch(bExecute := bLookup, fTarget := fBatchNo,
 *               nCount := nLoadedRows, bSearchAll := FALSE,
 *               afData := afRecipeTab);
 *   IF fbFindBatch.bDone AND fbFindBatch.bFound THEN
 *       nSelRow := fbFindBatch.nIndex;          // 命中行索引
 *   END_IF
 *   // 全量计数模式示例（同批号出现次数盘点）：
 *   // fbCountBatch(bExecute := bAudit, fTarget := fBatchNo,
 *   //              nCount := nLoadedRows, bSearchAll := TRUE,
 *   //              afData := afRecipeTab);
 *   // nDup := fbCountBatch.uHitCount;   // 触发拍内取走
 *
 * 【选型对照 / Selection guide】
 *   本块（ArraySearchFirst） ：无序 / 有序皆可，O(n) 单遍，支持全量计数，
 *                             nCount 可小于数组实际长度（前缀搜索）。
 *   FC_DL_BinarySearchLReal ：要求升序，O(log n)，1024 元素最多 11 次比较，
 *                             但不支持全量计数、不校验有序性。
 *   高频轮询查找（每周期都查）选二分块；低频事件查找 / 无序数据选本块。
 *
 * 【扫描周期行为 / Scan behavior】
 *   触发拍执行：缺省值清零 → 范围钳位 → 单遍扫描（含守护双保险）→ 结果落位。
 *   bDone 仅触发拍为 TRUE，下一拍自清（R25 三律）；
 *   结果族（bFound / nIndex / uHitCount）每拍先清后写，无残留。
 *
 * 【单拍脉冲逐拍推演 / Single-pulse walk-through（R25 三律）】
 *   拍 n：bExecute 上升沿 → bDone=TRUE，扫描完成结果落位；
 *   拍 n+1：bExecute 仍为 TRUE（无新上升沿）→ 段 2 自清 bDone=FALSE，
 *   结果族同拍复位为"未命中"缺省。调用方必须在触发拍内取结果。
 *
 * 【性能与实时性披露 / Performance disclosure】
 *   最坏情形（bSearchAll = TRUE 且全命中）：1024 次容差比较，
 *   LREAL 比较约百纳秒级，单拍总耗时远低于 0.1ms（通用工控 CPU 口径），
 *   不构成实时性风险；触发制设计保证未触发拍零开销。
 *   单命中模式开销与首个命中位置线性相关，平均约为最坏情形之半；
 *   容差比较为两次减法一次 ABS 一次小于，无除法无超越函数。
 *   实例净占用约 0.03KB（边沿实例 + 计数器），数组内存归调用方。
 *   建议同数据的查找点集中到单一实例，便于触发链路与诊断归口。
 *
 * 故障码表 (Error codes):
 *   16#0001_010E  nCount 越界，已钳位到 0..DL_SRH_MAX（信息级）
 *   16#0001_0205  扫描守护计数超限，提前跳出（故障级，理论不可达，
 *                 为跨平台 FOR 语义差异兜底）
 *   【码位终审】原拟 0002_0101 / 0002_0201 经全库复核冲突：0002_01xx 段已由
 *   DL_Algo PID 族登记（FB_DL_PidController 0002_0101 输出饱和、
 *   FB_DL_CascadePid 0002_0201 副设定钳位），且 DL_MathData 依公约 0.7 归
 *   16#0001_xxxx 段。已顺延至 0001_010E / 0001_0205（无冲突）。
 * 红线自检 (Redline)    : R1 ✓ 零全局存储 / 零外部变量引用 ｜ R2 ✓ 零物理地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ nCount 钳位 + 浮点容差判等 + 下标先判界 + 守护计数
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机，边沿触发扫完即停）
 *                         R7 ✓ R_TRIG 主体最前部无条件刷新
 * 边界契约 (Boundaries):
 *   B1 搜索体 afData 由调用方持有并注入，容量上限 DL_SRH_MAX = 1024 元素。
 *   B2 命中判据为 ABS(afData[i] - fTarget) < DL_FLOAT_EPS，严禁浮点直接判等
 *      （红线 R4），标称相等但低位噪声的采样值按相等处理。
 *   B3 未命中时 nIndex 固定 -1、bFound FALSE，不残留上拍结果：结果族每拍先清。
 *   B4 bDone 单拍脉冲遵循 R25 三律：仅触发拍置位，下拍自清。
 *   B5 bSearchAll = FALSE 时 uHitCount 只可能是 0 或 1（首个命中即退出）；
 *      = TRUE 时为全量命中总数。nIndex 恒为首个命中索引，与计数模式无关。
 *   B6 nCount = 0 合法：返回未命中（bDone 一拍），不置故障——空表是合法工况。
 * 【验收推演表 / Acceptance walk-through】
 *   数据体 afData = {8.1, 3.3, 5.5, 3.3, 7.7}（无序，含重复值 3.3）
 *   A1 fTarget=5.5, nCount=5, 单命中模式 → nIndex=2、bFound=TRUE、
 *      uHitCount=1、bDone 一拍、uErrorId=0
 *   A2 fTarget=3.3, nCount=5, 单命中模式 → nIndex=1（首个命中即退出，
 *      不继续数第二个 3.3）、uHitCount=1
 *   A3 fTarget=3.3, nCount=5, 全量模式   → nIndex=1、uHitCount=2（B5 语义）
 *   A4 fTarget=9.9, nCount=5             → nIndex=-1、bFound=FALSE、
 *      uHitCount=0（未命中不残留上拍结果，B3）
 *   A5 fTarget=7.7, nCount=0             → 未命中返回，bDone 一拍，
 *      不置故障（B6 空表合法）
 *   A6 nCount=2000（超上限）             → 钳位 1024 + uErrorId=0001_010E，
 *      前 1024 个元素照常搜索
 *   A7 nCount=-5（负范围）               → 视作空表，未命中返回，
 *      uErrorId=0001_010E（信息级）
 *
 * 【结果生命周期 / Result lifetime】
 *   触发拍：结果族写入扫描结论；非触发拍：结果族复位为未命中缺省。
 *   调用方必须在 bDone 拍内取走 nIndex / uHitCount——这是触发制组件
 *   的标准纪律，与每拍自动刷新型组件（如 RingBuffer 窥视）用法不同。
 *   需要保持型结论时，调用方在 bDone 拍自行锁存到自己的保持变量。
 *
 * 【与二分块参数域对照 / Parameter domain comparison with the binary block】
 *   维度          ｜ 本块                  ｜ FC_DL_BinarySearchLReal
 *   有序要求      ｜ 无                    ｜ 升序（契约责任在调用方）
 *   复杂度        ｜ O(n)，1024 上限        ｜ O(log n)，最多 11 次比较
 *   全量计数      ｜ 支持（bSearchAll）     ｜ 不支持
 *   前缀搜索      ｜ 支持（nCount < 长度）  ｜ 支持（nCount 即前缀）
 *   命中判据      ｜ ABS 容差              ｜ ABS 容差（同一口径）
 *   调用形态      ｜ FB 实例（R_TRIG 边沿）｜ FC 纯函数（无状态）
 *   重复值语义    ｜ 返回首个命中索引      ｜ 返回其中任一命中索引（不保证首）
 *
 * 【组态建议 / Configuration notes】
 *   nCount 建议传"实际装载行数"而非数组全长：前缀搜索可线性缩减扫描
 *   时间，且未装载区是残留旧数据，纳入搜索反而会误命中。
 *   bSearchAll 只在需要重复值统计（如同批号计数）时开启，
 *   单命中定位场景保持 FALSE 以获得最快退出路径。
 *   fTarget 与数据体必须是同一工程单位与同一量纲口径，本块不做单位换算。
 *
 * 【引脚速查表 / Pin quick reference】
 *   方向 ｜ 名称        ｜ 类型 ｜ 语义摘要
 *   输入 ｜ bExecute    ｜ BOOL ｜ 执行沿，上升沿触发一次扫描
 *   输入 ｜ fTarget     ｜ LREAL｜ 目标值，与数据体同工程单位
 *   输入 ｜ nCount      ｜ DINT ｜ 搜索前缀长度 [元素]，0..1024 钳位
 *   输入 ｜ bSearchAll  ｜ BOOL ｜ 全量计数模式开关
 *   输出 ｜ bDone       ｜ BOOL ｜ 完成单拍（仅触发拍）
 *   输出 ｜ bFound      ｜ BOOL ｜ 至少命中一个
 *   输出 ｜ nIndex      ｜ DINT ｜ 首个命中下标，未命中 -1
 *   输出 ｜ uHitCount   ｜ UINT ｜ 命中总数，单命中模式为 0/1
 *   输出 ｜ uErrorId    ｜ UDINT｜ 故障码（见故障码表）
 *   注入 ｜ afData      ｜ 数组 ｜ 搜索体，调用方持有
 *
 * 【触发丢失防护 / Trigger-loss protection】
 *   bExecute 保持 TRUE 不会连续扫描（R_TRIG 只认上升沿）；
 *   需要重复查找时先回 FALSE 至少一拍再置位。反向风险同样存在：
 *   若调用方把常 TRUE 信号接到 bExecute，只有第一拍生效，
 *   之后数据体变化不会触发重扫——动态数据应按事件接线，不按电平接线。
 *
 * 【与排序块组合范式 / Composition with the sort block】
 *   已入库 FC_DL_QuickSortLReal（排序）+ 本块（查找）构成"先整序后检索"
 *   组合：装载完成后排序一次，之后的高频查找可切换到二分块
 *   （FC_DL_BinarySearchLReal）获得 O(log n)；数据体会被运行时追加打乱
 *   的场合保持本块线性查找，避免为维护有序性付出额外搬移成本。
 *   两块职责正交，本块不依赖排序块（泳道零互相依赖红线）。
 *
 * 【组态错误清单 / Misuse checklist】
 *   M1 bExecute 常 TRUE 接线 → 只首拍生效，动态数据漏扫（见触发丢失防护）；
 *   M2 nCount 传全长而未装满 → 残留旧数据误命中，传实际装载行数；
 *   M3 目标值单位与数据体量纲不一致 → 永不命中或全命中，组态期核对量纲；
 *   M4 把 nIndex 直接当数组下标写而不查 bFound → 未命中 -1 越界风险；
 *   M5 在多个任务调用同一实例 → R_TRIG 边沿语义被破坏，结果不可信；
 *   M6 数据体边扫边改（同周期外部写）→ 竞态，先复制快照再搜；
 *   M7 容差常量被调用方按需调整（只读常量无法改，此处指另建
 *   变体组件时改常量）→ 与二分块互校口径断裂，须库级统一升版；
 *   M8 nCount 填了数组全长且数据体为部分重载 → 未装载区残留旧值
 *   误命中（同 M2 根因的高频变体，单列提醒）。
 *
 * 【诊断与可观测性 / Diagnostics and observability】
 *   uErrorId 信息级（0001_010E）表示范围被钳位：频现说明调用方
 *   范围计算有系统偏差，应修上游而非吞码；故障级（0001_0205）
 *   理论不可达，一旦出现说明运行平台 FOR 循环语义异常，
 *   应停用该实例并上报平台层。bDone 与 bFound 组合即完整结论：
 *   （TRUE,TRUE）命中（TRUE,FALSE）未命中（FALSE,任意）本拍无操作。
 *
 * 【扫描开销披露 / Scan-cost disclosure】
 *   未触发拍：一次 R_TRIG 刷新 + 五个赋值，开销可忽略；
 *   触发拍最坏（全量模式 1024 元素全命中）：1024 次容差比较 +
 *   1024 次计数递增，通用工控 CPU 口径低于 0.1ms；
 *   单命中模式首个命中即退出，实际开销与首个命中位置成正比。
 *
 * 【术语与口径表 / Glossary and semantics】
 *   命中（Hit）：ABS(元素 - 目标) < 容差，即工程意义上的"相等"；
 *   首个命中：下标最小的命中元素，本块恒返回首个（与二分块互补）；
 *   前缀搜索：只扫前 nCount 个元素，nCount 可小于数组全长；
 *   全量计数：bSearchAll = TRUE 时扫完整个前缀统计命中总数；
 *   触发制：仅上升沿拍扫描，未触发拍零扫描开销。
 *
 * 【逐段结构说明 / Section map】
 *   段 1 边沿无条件刷新（红线 R7）｜ 段 2 本拍缺省值与结果族清零
 *   段 3 触发沿门控 ｜ 段 4 范围钳位 ｜ 段 5 单遍扫描主体（双守护）
 *   段序即执行序，全部为直线结构，无跨段跳转，审阅按序阅读即可。
 *   段 3 门控包住段 4 / 段 5：钳位与扫描都只在触发拍发生，
 *   非触发拍连钳位都不执行，确保"未触发拍零开销"口径成立。
 *
 * 【合规范式声明 / Paradigm compliance】
 *   R25 单拍三律：bDone 置位点唯一（段 3 门控首句）、自清点唯一
 *   （段 2 缺省值）、边沿基准唯一（R_TRIG 实例）；
 *   R26 无孤立分号：全文件无空语句；
 *   R19 首扫范式：本块无首扫需求（无跨拍状态记忆），未使用首扫标志；
 *   禁记号口径：全文零全局存储声明、零外部变量声明、零绝对地址记号，
 *   机检口径按全文命中为 0 执行。
 *
 * 【所有权与生命周期边界 / Ownership and lifetime】
 *   afData 所有权归调用方：本块只在触发拍内读，绝不写、绝不缓存
 *   数组引用（VAR_IN_OUT 语义，调用结束即释放）；
 *   调用方在扫描中途改写数组属竞态工况：本块不防御同一周期内的
 *   外部改写，需要一致快照时由调用方先复制再搜索。
 *
 * 【部署位置建议 / Deployment placement】
 *   建议布置在数据装载 / 变更的事件链上（装载完成沿、人工查询按钮沿、
 *   上位机请求沿），而非固定周期链——触发制组件挂周期链会让 R_TRIG
 *   永不翻转，白白占用实例；确有周期性重查需求时，由调用方用
 *   边沿比较（本拍值 <> 上拍值）生成请求沿再接入。
 *   多查询点共享同一数据体时各建实例互不干扰（本块对数组只读）。
 *
 * 【验证流程对接 / Verification hooks】
 *   验收推演表 A1~A7 供终审逐组代回实现验算：A1~A3 验正常路径与
 *   重复值语义，A4~A5 验未命中与空表（拒绝路径），A6~A7 验钳位路径；
 *   机检口径：全文禁记号命中为 0、END_FUNCTION_BLOCK 成对终结、
 *   无孤立分号。组件无浮点判等、无除法、无 WHILE 循环，
 *   除零 / 死循环两类风险在本块结构性不存在。
 *
 * 【版本与变更边界 / Version and change boundary】
 *   输出族语义（触发拍写入 / 非触发拍复位）与容差常量 1E-9 属库级
 *   公开契约：修订若改变任一项必须升版登记；容差调整将影响与
 *   二分块的结果互校口径，禁止单独改本块常量。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · Level 0 原子族回补）
 *   2026-11-15  v1.0.1  终审修复：故障码 0002_0101 / 0002_0201 与 DL_Algo
 *                       PID 族冲突且越段位，顺延为 0001_010E / 0001_0205，
 *                       行为语义零改动
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ArraySearchFirst
VAR_INPUT
    bExecute    : BOOL;                 // 执行搜索，上升沿触发（Execute search, rising edge）
    fTarget     : LREAL := 0.0;         // 目标值 [工程单位随应用] / Target value [EU by application]
    nCount      : DINT := 0;            // 搜索范围 [元素数]，0..DL_SRH_MAX，越界钳位 / Search range [elements], clamped
    bSearchAll  : BOOL := FALSE;        // TRUE = 继续全量扫描统计命中总数 / TRUE = scan all and count total hits
END_VAR
VAR_OUTPUT
    bDone       : BOOL;                 // 搜索完成，单拍脉冲（仅触发拍置位）/ Search done, single pulse
    bFound      : BOOL;                 // 至少命中一个 / At least one hit found
    nIndex      : DINT := -1;           // 首个命中索引 [元素下标]，未命中 = -1 / First hit index, -1 when not found
    uHitCount   : UINT := 0;            // 命中总数 [个]，bSearchAll = FALSE 时为 0 或 1 / Total hits [items]
    uErrorId    : UDINT;                // 故障码，0 = 无故障（见头注释故障码表）/ Error code, 0 = no error
END_VAR
VAR_IN_OUT
    afData      : ARRAY[0..DL_SRH_MAX-1] OF LREAL;  // 搜索数据体，调用方持有并注入 / Search array, owned and injected by the caller
END_VAR
VAR
    fbTrigExec  : R_TRIG;               // 执行边沿检测实例 / Execute edge detector instance
    nGuard      : DINT;                 // 循环防死锁守护计数器 [次] / Loop guard counter [iterations]
    nCountEff   : DINT;                 // 钳位后的有效搜索范围 [元素数] / Effective clamped search range [elements]
    bHit        : BOOL;                 // 单元素命中暂存 / Per-element hit latch
END_VAR
VAR CONSTANT
    DL_SRH_MAX  : DINT := 1024;         // 数组容量上限 [元素]，必须与数组维度一致 / Array capacity limit, must match the dimension
    DL_FLOAT_EPS: LREAL := 1.0E-9;      // LREAL 判等容差，禁浮点直接判等 / LREAL equality tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：边沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: edge instance at the very top
 *      嵌入条件分支会漏拍，触发沿被吞掉后本次请求永久丢失
 *-----------------------------------------------------------------------------*)
fbTrigExec(CLK := bExecute);

(*------------------------------------------------------------------------------
 * 段 2｜本拍缺省值：结果族每拍先清（边界 B3），单拍脉冲自清（R25）
 *      Per-scan defaults: result family cleared first, single-pulse self-clear
 *      保持型输出不存在：本块全部输出均为"触发拍语义"
 *-----------------------------------------------------------------------------*)
uErrorId  := 16#0000_0000;
bDone     := FALSE;
bFound    := FALSE;
nIndex    := -1;
uHitCount := UINT#0;

(*------------------------------------------------------------------------------
 * 段 3｜触发沿处理：仅边沿拍执行扫描（触发制，未触发拍零开销）
 *      Edge-triggered scan body: scan runs on the rising edge only
 *      常电平接线只首拍生效（见触发丢失防护），动态数据按事件接线
 *-----------------------------------------------------------------------------*)
    IF fbTrigExec.Q THEN
        bDone := TRUE;              // R25：仅操作拍置位，下拍段 2 自清
        (* 置位唯一写点：后续任何提前退出路径不再触碰 bDone *)

    (*--------------------------------------------------------------------------
     * 段 4｜范围钳位（边界 B1）：nCount 钳位到 0..DL_SRH_MAX
     *      负数视作 0（空表合法工况，不置故障以外的动作）；超上限截断
     *      Range clamp: negative treated as zero, overflow truncated
     *-------------------------------------------------------------------------*)
    IF (nCount < 0) OR (nCount > DL_SRH_MAX) THEN
        IF nCount < 0 THEN
            nCountEff := 0;     // 负范围 → 空表 / Negative range to empty table
        ELSE
            nCountEff := DL_SRH_MAX;    // 超上限截断 / Overflow truncated
        END_IF
        uErrorId := 16#0001_010E;   // 信息级：范围越界已钳位 / Info: range clamped
        (* 钳位后照常扫描：范围修正不应吞掉本次查找请求 *)
    ELSE
        nCountEff := nCount;        // 合法范围直通 / Legal range passes through
    END_IF

    (*--------------------------------------------------------------------------
     * 段 5｜线性单遍扫描（边界 B2/B6）：循环上限 = DL_SRH_MAX 兼作防死锁上限，
     *      另设守护计数器双保险，超限置故障级码提前跳出
     *      Linear single-pass scan with a double-guard against dead loops
     *-------------------------------------------------------------------------*)
    IF nCountEff > 0 THEN
        FOR nGuard := 0 TO DL_SRH_MAX - 1 DO
            (* nGuard 身兼二职：循环变量 + 守护计数器，上限即容量上限 *)
            (* 守护退出 1：已达有效范围，正常收尾（空表已被段 5 外层拦截） *)
            IF nGuard >= nCountEff THEN
                EXIT;
            END_IF

            (* 下标先判界再访问（红线 R4）：循环界已保证，仍显式兜底 *)
            IF (nGuard >= 0) AND (nGuard < DL_SRH_MAX) THEN
                bHit := ABS(afData[nGuard] - fTarget) < DL_FLOAT_EPS;   // 容差判等（B2）
                (* 判等口径与二分块一致：1E-9，跨组件结果可互校 *)
            ELSE
                bHit := FALSE;  // 理论不可达分支，保守判未命中 / Unreachable, conservative miss
            END_IF

            IF bHit THEN
                uHitCount := uHitCount + UINT#1;    // 命中计数累加 / Increment hit counter
                (* 计数累加先于首个命中锁定：全量模式下计数值与索引独立 *)
                IF nIndex < 0 THEN
                    nIndex := nGuard;   // 首个命中索引只写一次（B5）
                    bFound := TRUE;
                    (* 全量模式下此处不退出，继续累计后续命中 *)
                END_IF
            (* 全量模式继续计数；单命中模式立即退出（O(n) 最快路径） *)
                IF NOT bSearchAll THEN
                    EXIT;
                END_IF
                (* 全量模式在此继续下一轮：命中不退出，直至扫完前缀 *)
            END_IF
        END_FOR

        (* 守护退出 2：循环耗尽守护上限仍未见有效范围收尾 → 故障级兜底。
           触发条件要求 nCountEff > DL_SRH_MAX，钳位后理论不可达，
           仅为跨平台 FOR 循环语义差异（如步进异常）兜底 *)
        IF (nGuard >= DL_SRH_MAX) AND (nCountEff > DL_SRH_MAX) THEN
            uErrorId := 16#0001_0205;   // 故障级：守护超限（理论不可达）/ Fault: guard exceeded
            (* 结果族保持本拍已累计值，调用方以故障级码识别本轮不可信 *)
        END_IF
    END_IF
END_IF
END_FUNCTION_BLOCK
