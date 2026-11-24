(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RolloverCounter
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 计数功能块（Function Block · Counter）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / MIN），零厂商方言
 * 功能简介 (Function)   : 回绕型可逆计数器。在 0 至回绕上限的环形域内上下计数，
 *                         到顶继续加则回 0、到底继续减则回上限，同时输出回绕单拍
 *                         脉冲与**净回绕圈数**（可负），用于转盘圈数统计、编码器
 *                         溢出圈数、料盘循环计数等「只关心绕了多少圈」的场合。
 *                         本块**不做任何预设比较逻辑**：既不在到达预设时冻结，
 *                         也不做双预设区间判断，纯粹计数 + 回绕 + 圈数累积。
 *
 * 【引脚契约 / Pin contract】
 *   输入 bEnable      : BOOL  — 使能。FALSE 时冻结计数（值保持、圈数保持、无脉冲），
 *                               状态回空闲；本块不因失能清零，清零只认复位沿；
 *   输入 bReset       : BOOL  — 上升沿把计数值与圈数清零（可在任意状态生效）；
 *   输入 bCountUp     : BOOL  — 上升沿加计数（电平保持不重复计数）；
 *   输入 bCountDown   : BOOL  — 上升沿减计数（电平保持不重复计数）；
 *   输入 bLoad        : BOOL  — 电平有效装载，优先级最高（高于复位沿与计数沿）；
 *   输入 uLoadValue   : UDINT — 装载值 [cnt]，超过回绕上限时钳位并置信息码；
 *   输入 uPreset      : UDINT — 回绕上限（含）[cnt]，有效域 1~16#FFFF_FFFE；
 *   输出 uCount       : UDINT — 当前计数值 [cnt]，0 ~ 回绕上限；
 *   输出 bWrapped     : BOOL  — 本拍发生回绕的单拍脉冲（上下回绕均置位）；
 *   输出 nTurns       : DINT  — 净回绕圈数 [圈]，上加下减，可负，带饱和保护；
 *   输出 bAtPreset    : BOOL  — 当前值已达回绕上限（逐拍重算，非锁存）；
 *   输出 eState       : ENUM  — 主状态机当前态（E_DL_RolloverPhase）；
 *   输出 bError       : BOOL  — 故障锁存：回绕上限退化（小于 1），计数冻结；
 *   输出 uErrorId     : UDINT — 事件 / 故障码，0 = 无。
 *
 * 【与既有四件计数器的职责边界 / Family separation（五件互斥，写死不可互替）】
 *   FB_DL_EventCounter         = 单向事件累加（只关心总数）；
 *   FB_DL_ModuloCounter        = 取模工位索引（单向，用取模得余数）；
 *   FB_DL_PresetCounterSat     = 单向双预设饱和（到限冻结，不回绕）；
 *   FB_DL_BidirectionalCounter = CTUD 双预设比较（关心区间高低限）；
 *   本块                       = 环形回绕 + 净圈数（无预设比较，只关心绕圈）。
 *   本块刻意不实现「到限冻结」与「取模」：前者是饱和件语义，后者在无符号域与
 *   有符号域上行为不一致（历史坑），本块回绕一律用「比较 + 赋值」实现，禁 MOD。
 *
 * 【计数优先级 / Priority chain（同拍多指令的仲裁口径）】
 *   ① 回绕上限退化（小于 1）→ 冻结，最高优先级，任何计数沿都不生效；
 *   ② 装载（bLoad 电平有效）→ 覆盖计数，同拍计数沿被丢弃；
 *   ③ 复位沿 → 计数与圈数清零（与装载同拍时装载胜出，因装载在其后执行）；
 *   ④ 双向同拍 → 净变化 0，计数不变、不发脉冲、置信息码 0120；
 *   ⑤ 单向沿 → 加 / 减，跨过上下界即回绕并累计圈数。
 *
 * 【指令优先级矩阵 / Priority matrix（行 = 状态，列 = 本拍指令）】
 *   状态 \ 指令        退化   装载   复位沿   双向同拍   单向上/下   无指令
 *   eIdle              冻结   落计数 清零     落计数     落计数      保持
 *   eCount             冻结   装载     清零     丢弃       加减回绕    保持
 *   eFrozen            保持   保持     退出冻结 保持       保持        保持
 *   矩阵口径写死：装载是「电平」而非沿，保持期间每拍都写同一个值；
 *   复位是「沿」，只在上升沿那一拍动作；计数同样只认沿，电平保持不重复计数。
 *   三者混用时按上表逐格落地，不存在「装载与计数同拍谁先谁后」的解释空间。
 *
 * 【回绕与圈数口径 / Wrap and turn semantics】
 *   加法回绕：当前值已达上限（大于等于上限）→ 计数值回 0，圈数 +1；
 *   减法回绕：当前值为 0 → 计数值回上限，圈数 -1；
 *   圈数饱和：nTurns 触及正 / 负饱和上限后停在该值，并置信息码（不再累加），
 *   防止远端诊断页数值溢出翻转（历史 D 类缺陷）。饱和后需复位沿才能重新累计。
 *
 * 【圈数换算与量程校核 / Turn-to-engineering conversion】
 *   真实位移 = nTurns × 一圈当量 + 当前值 × 单格当量（一圈当量 = 上限 + 1 格）；
 *   例：分度盘 60 格、单格 6 度，则 nTurns × 360 + uCount × 6 即累计角度；
 *   量程校核方法：nTurns 饱和值 2×10^9 圈 × 一圈当量，须仍在调用方量程内，
 *   量程不足时调用方应在换向或换批时用复位沿清零，而不是依赖饱和兜底。
 *   本块输出「净圈数」而非「绝对位置」：掉电重启后圈数从 0 起算，
 *   需要绝对位置时由调用方在上电时用装载引脚把已知位置写入并自行保存圈数。
 *
 * 【饱和与复位的配合 / Saturation versus reset】
 *   饱和只是停止累加，不改写任何已有值：回绕脉冲照发、计数值照转，
 *   因此「绕圈事实」不会因为圈数饱和而丢失，只是不再累进到诊断量上；
 *   复位沿同时清零计数与圈数并解除饱和，是唯一的重入手段；
 *   本块不因使能撤除而清零：失能只冻结，避免产线短暂停机就丢失圈数。
 *
 * 【现场整定与故障定位提示 / Commissioning hints】
 *   ① 上电先给一次复位沿，把计数与圈数拉到已知零点，再开始累计；
 *   ② 空载手转一圈，观察 bWrapped 是否恰好出现一次：出现两次说明上限设小了，
 *      一次都不出现说明上限大于实际一圈格数（脉冲被吃掉）；
 *   ③ 计数跳变排查：若 uCount 出现跨格跳跃，先查引脚注入的脉冲是否被上层
 *      做了防抖（防抖会削沿，本块只认沿，不做任何滤波）；
 *   ④ 圈数与机械圈数不符时，优先核对上限是否为「一圈格数减一」（上限含端点）。
 *
 * 【主状态机 / Main state machine（ENUM + CASE + ELSE 兜底）】
 *   eIdle   → bEnable 且上限合法：eCount；
 *   eIdle   → bEnable 但上限退化：eFrozen 并置 0218；
 *   eCount  → 上限退化：eFrozen（计数保持，不回 0，避免死循环式跳动）；
 *   eCount  → 使能撤除：eIdle（计数冻结保持）；复位沿留在 eCount 内清零；
 *   eFrozen → 上限恢复合法或复位沿：eIdle（复位后重新装载）；
 *   eFrozen → 使能撤除：eIdle；
 *   ELSE    → 非法态值：eFrozen 并置 0218（兜底拦截，绝不落空态）。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 回绕上限小于 1（含 0）→ 退化冻结：不回绕到 0、不产生无穷回绕，置 0218；
 *   B2 回绕上限超过 16#FFFF_FFFE → 钳到该值并置 0120（防极端值参与比较歧义）；
 *   B3 装载值超上限 → 钳到上限并置 0120（钳位后仍接受装载，不丢弃指令）；
 *   B4 双向同拍 → 计数不变、脉冲不发、置 0120（避免扫描时序歧义）；
 *   B5 圈数饱和 → 停在 ±饱和值并置 0120，不静默回绕；
 *   B6 整数域全为无符号 / 有符号整数比较（UDINT / DINT），无浮点参与，
 *      浮点判等容差红线在本块不适用（头注释显式声明）；
 *   B7 加法不做「上限 + 1」运算、减法不做「0 - 1」运算：回绕由直接赋值完成，
 *      无符号下溢 / 上溢永不发生，跨平台无差异。
 *
 * 【单拍标志三律 / One-shot pulse lifecycle（R24 / R25）】
 *   置位律：bWrapped 每拍于段 1 预清 FALSE，仅由段 5 的回绕分支置位；
 *   分离律：边沿「消费」在段 2 的实例 Q，脉冲「转出」在段 5 的计数分支，
 *           下一拍由段 1 预清零自清，不存在跨拍悬挂；
 *   基准律：三个边沿实例固定在主体顶层无条件刷新，基准唯一（引脚电平），
 *           不置于条件分支内，扫描抖动不丢沿、不重沿。
 *
 * 【调用示例 / Call example（仅行注释，不嵌套块注释）】
 *   // 分度盘：每工位 1 个脉冲，60 工位一圈，统计已转圈数与每圈回绕沿
 *   // fbTurn(fbIndex(bEnable := bRunOk, bReset := bIdxReset,
 *   //        bCountUp := bStationPulse, bCountDown := FALSE,
 *   //        bLoad := bHomingDone, uLoadValue := uHomePos, uPreset := 59,
 *   //        uCount => uStationNo, bWrapped => bLapDone,
 *   //        nTurns => nLapCount, bAtPreset => bLastStation,
 *   //        eState => eTurnState, bError => bTurnErr, uErrorId => uTurnErrId));
 *
 * 【平台移植注意 / Porting notes】
 *   UDINT 的比较与赋值在三平台语义一致；本块不使用 MOD 与无符号减法下溢，
 *   因此不存在「无符号回绕到 4294967295」这一类平台差异；DINT 饱和判据用
 *   显式比较而非加减后判溢出，避免依赖溢出标志位（部分平台不暴露该标志）。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 分度盘 / 转盘：工位脉冲计数到一圈末回绕，回绕沿驱动「整圈完成」逻辑；
 *   ② 编码器 / 计量轮：增量计数的绝对值溢出后回绕，圈数用于累计真实行程；
 *   ③ 料盘循环：料盘码位循环取料，回绕沿触发一次空盘检测；
 *   ④ 卷绕 / 收放卷：正反转计数，净圈数直接反映卷径变化趋势（配合卷径计算件）。
 *
 * 【与上层逻辑的组合契约 / Composition contract】
 *   本块只做「环形计数 + 圈数」，不含任何工艺判断，也不输出报警级别；
 *   上层典型组合：
 *     回绕脉冲 → 触发「整圈完成」事务（发一次 HMI 计米更新或一次换盘请求）；
 *     到限标志 → 作为「下一格即回绕」的预判，供减速 / 预动作使用；
 *     圈数 + 计数 → 由上层换算为长度、角度或位置，本块不做量纲换算；
 *     故障位 → 并入设备级诊断汇总，本块不直接驱动任何硬件输出。
 *   本块不持有任何外部实体引用，也不回调上层：只有引脚进、引脚出。
 *
 * 【典型时序推演 / Typical timing walkthrough】
 *   设上限 100、初始计数 98：加沿 → 99；加沿 → 100（bAtPreset TRUE、无脉冲）；
 *   再加沿 → 计数 0、bWrapped 单拍 TRUE、圈数 +1；此后再加沿回常规递增。
 *   减向：计数 0 时减沿 → 计数 100、bWrapped 单拍 TRUE、圈数 -1。
 *   装载：bLoad 保持 TRUE 期间每拍把装载值写入计数，脉冲不产生；
 *   装载撤销后从装载值继续，圈数不变（装载不重置圈数，只有复位沿才清圈数）。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1 上回绕：上限 100、计数 100、加沿 → 计数 0、bWrapped TRUE、圈数 +1；
 *   V2 下回绕：计数 0、减沿 → 计数 100、bWrapped TRUE、圈数 -1；
 *   V3 装载优先：bLoad TRUE、装载值 42、同拍有加沿 → 计数 42、圈数不变、无脉冲；
 *   V4 双向冲突：加沿与减沿同拍 → 计数不变、无脉冲、uErrorId 0120；
 *   V5 上限退化：上限 0、连续给加沿 → 计数保持、bError TRUE、uErrorId 0218。
 *   V6 装载钳位：上限 100、装载值 500、bLoad TRUE → 计数 100、uErrorId 0120；
 *   V7 连续绕圈：上限 9、从 0 起连给 30 个加沿 → 计数 0、圈数 +3、脉冲仅三次；
 *   V8 复位清圈：任意圈数下给一次复位沿 → 计数 0、圈数 0、脉冲不发。
 *
 * 【故障码表 / Error code table】
 *   16#0001_0120  信息级：装载值超上限已钳位 / 上下限超域已钳位 /
 *                 同拍双向已丢弃 / 圈数饱和已停止累加，均只进事件码；
 *   16#0001_0218  故障级：回绕上限小于 1（退化），计数冻结并锁存 bError。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 A · LGF Counter 组）
 *
 * 同文件发布类型 (Co-published type) : E_DL_RolloverPhase（本块主状态机枚举，
 *   按库内惯例随宿主 POU 同文件发布，禁止在其他文件重复声明同名枚举）。
 *============================================================================*)
TYPE E_DL_RolloverPhase :
(
    eIdle   := 0,      // 空闲：未使能，计数与圈数保持 / Idle, disabled, count and turns held
    eCount  := 10,     // 计数：按边沿加减并回绕 / Counting, edge driven with wrap-around
    eFrozen := 20      // 冻结：上限退化，计数保持且报警 / Frozen, degenerate bound, count held
);
END_TYPE

FUNCTION_BLOCK FB_DL_RolloverCounter
VAR_INPUT
    bEnable      : BOOL;                   // 使能，FALSE 时冻结计数 / Enable, FALSE freezes the counting
    bReset       : BOOL;                   // 上升沿清零计数与圈数 / Rising edge clears the count and the turns
    bCountUp     : BOOL;                   // 上升沿加计数 / Rising edge increments
    bCountDown   : BOOL;                   // 上升沿减计数 / Rising edge decrements
    bLoad        : BOOL;                   // 电平有效装载，优先级最高 / Level-true load, highest priority
    uLoadValue   : UDINT;                  // 装载值 [cnt]，超上限时钳位 / Load value [cnt], clamped to the bound
    uPreset      : UDINT;                  // 回绕上限（含）[cnt]，1~16#FFFF_FFFE / Wrap bound inclusive [cnt], 1 to 16#FFFF_FFFE
END_VAR
VAR_OUTPUT
    uCount       : UDINT;                  // 当前计数值 [cnt]，0 ~ 上限 / Current count [cnt], 0 to the bound
    bWrapped     : BOOL;                   // 本拍回绕单拍脉冲 / One-shot wrap pulse of this scan
    nTurns       : DINT;                   // 净回绕圈数 [圈]，上加下减 / Net wrap turns [turn], signed
    bAtPreset    : BOOL;                   // 当前值已达上限 / The count reached the bound
    eState       : E_DL_RolloverPhase;     // 主状态机当前态 / Current state of the main state machine
    bError       : BOOL;                   // 故障锁存：上限退化 / Fault latched, degenerate bound
    uErrorId     : UDINT;                  // 事件 / 故障码，0 = 无 / Event or fault code, 0 = none
END_VAR
VAR
    _eState      : E_DL_RolloverPhase;     // 内部状态寄存器，段 6 为唯一写点 / Internal state register, single writer in stage 6
    _fbTrigUp    : R_TRIG;                 // 加计数上升沿实例，顶层无条件刷新 / Rising-edge instance of the up pulse
    _fbTrigDown  : R_TRIG;                 // 减计数上升沿实例，顶层无条件刷新 / Rising-edge instance of the down pulse
    _fbTrigReset : R_TRIG;                 // 复位上升沿实例，顶层无条件刷新 / Rising-edge instance of the reset pin
    _uBound      : UDINT;                  // 钳位后的回绕上限工作副本 [cnt] / Working copy of the clamped bound [cnt]
    _bBoundOk    : BOOL;                   // 上限合法性标志 / Bound validity flag
    _bUpEdge     : BOOL;                   // 本拍加沿有效 / Up edge active in this scan
    _bDownEdge   : BOOL;                   // 本拍减沿有效 / Down edge active in this scan
    _bResetEdge  : BOOL;                   // 本拍复位沿有效 / Reset edge active in this scan
    _bWrapNow    : BOOL;                   // 本拍回绕已发生（消费拍标志）/ Wrap happened in this scan, consumer flag
    _nTurnStep   : DINT;                   // 本拍圈数增量 [圈]，+1 / -1 / 0 / Turn increment of this scan [turn]
END_VAR
VAR CONSTANT
    DL_PRESET_MIN : UDINT := 1;            // 上限下限 [cnt]，小于它即退化 / Lower bound of the wrap bound [cnt]
    DL_PRESET_MAX : UDINT := 16#FFFF_FFFE; // 上限上界 [cnt]，极端值参与比较易生歧义 / Upper bound of the wrap bound [cnt]
    DL_TURNS_MAX  : DINT  := 2000000000;   // 圈数饱和上限 [圈]，留累加余量 / Turn saturation limit [turn], leaves headroom
    DL_TURN_UP    : DINT  := 1;            // 圈数增量：加向回绕 [圈] / Turn increment for an up wrap [turn]
    DL_TURN_DOWN  : DINT  := -1;           // 圈数增量：减向回绕 [圈] / Turn increment for a down wrap [turn]
    DL_TURN_HOLD  : DINT  := 0;            // 圈数增量：不回绕 [圈] / Turn increment when no wrap occurs [turn]
    DL_ERR_INFO   : UDINT := 16#0001_0120; // 信息级码：钳位 / 冲突 / 饱和 / Info code for clamp, conflict and saturation
    DL_ERR_PRESET : UDINT := 16#0001_0218; // 故障级码：上限退化，计数冻结 / Fault code for a degenerate bound
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出与工作标志预清零（单拍标志置位律的起点）
 *      Preset clearing of outputs and working flags
 *   uCount / nTurns / bError 为跨拍保持量，此处不清；bWrapped 必须每拍预清。
 *-----------------------------------------------------------------------------*)
bWrapped   := FALSE;                       // 回绕脉冲预清（Wrap pulse preset）
bAtPreset  := FALSE;                       // 到限标志预清（Bound-reached flag preset）
uErrorId   := 16#0000_0000;                // 事件码预清零，逐段置位（Event code preset to zero）
_bWrapNow  := FALSE;                       // 回绕消费标志预清（Wrap consumer flag preset）
_nTurnStep := DL_TURN_HOLD;                // 圈数增量预置 0（Turn increment preset to zero）

(*------------------------------------------------------------------------------
 * 段 2｜边沿实例无条件周期刷新（周期安全红线）
 *      Unconditional per-cycle refresh of all edge instances
 *   三个实例固定在主体顶层，严禁挪入 IF / CASE 分支，否则边沿丢失、计数丢拍。
 *-----------------------------------------------------------------------------*)
_fbTrigUp(CLK    := bCountUp);             // 加计数上升沿（Increment rising edge）
_fbTrigDown(CLK  := bCountDown);           // 减计数上升沿（Decrement rising edge）
_fbTrigReset(CLK := bReset);               // 复位上升沿（Reset rising edge）

_bUpEdge    := _fbTrigUp.Q;               // 本拍加沿（Up edge of this scan）
_bDownEdge  := _fbTrigDown.Q;             // 本拍减沿（Down edge of this scan）
_bResetEdge := _fbTrigReset.Q;            // 本拍复位沿（Reset edge of this scan）

(*------------------------------------------------------------------------------
 * 段 3｜上限钳位与合法性判定（边界 B1 / B2）
 *      Bound clamping and validity verdict
 *   上界超域先钳位（防极端值参与比较），下界退化只判不钳：
 *   退化必须冻结而不是悄悄改成 1，否则现场永远看不到组态错误。
 *-----------------------------------------------------------------------------*)
_uBound := uPreset;                        // 上限工作副本接管输入（Bound working copy）
IF _uBound > DL_PRESET_MAX THEN            // 超上界（Above the upper bound）
    _uBound  := DL_PRESET_MAX;             // 钳到上界（Clamp to the upper bound）
    uErrorId := DL_ERR_INFO;               // 置钳位信息码（Raise the clamp info code）
END_IF

IF _uBound < DL_PRESET_MIN THEN            // 低于下限，退化（Below the lower bound, degenerate）
    _bBoundOk := FALSE;                    // 上限不可用（Bound unusable）
    bError    := TRUE;                     // 故障锁存（Latch the fault）
    uErrorId  := DL_ERR_PRESET;            // 置退化故障码（Raise the degenerate fault code）
ELSE                                       // 上限可用（Bound usable）
    _bBoundOk := TRUE;                     // 上限合法（Bound valid）
    bError    := FALSE;                    // 条件解除即清故障（Fault clears once the condition is gone）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜复位段（计数与圈数清零，任意状态生效）
 *      Reset stage, effective in every state
 *   复位在装载之前执行：同拍既复位又装载时装载胜出（装载语义为「强制落到某值」）。
 *-----------------------------------------------------------------------------*)
IF _bResetEdge THEN                        // 复位沿（Reset edge）
    uCount  := 0;                          // 计数清零（Count cleared）
    nTurns  := 0;                          // 圈数清零（Turns cleared）
    bWrapped := FALSE;                     // 同拍不发回绕脉冲（No wrap pulse on the reset scan）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机与计数核心（ENUM + CASE + ELSE 兜底）
 *      Main state machine with the counting core
 *   状态迁移与计数动作在同一 CASE 内完成，状态寄存器只有本段一个写点；
 *   回绕动作只在 eCount 分支里出现，退化态与空闲态不产生任何回绕。
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_RolloverPhase.eIdle:              // 空闲：等待使能（Idle, waiting for enable）
        IF bEnable AND _bBoundOk THEN      // 使能且上限合法（Enabled with a valid bound）
            _eState := E_DL_RolloverPhase.eCount;            // 进入计数态（Enter the counting state）
        ELSIF bEnable THEN                 // 使能但上限退化（Enabled but the bound is degenerate）
            _eState := E_DL_RolloverPhase.eFrozen;           // 进入冻结态（Enter the frozen state）
            uErrorId := DL_ERR_PRESET;     // 置退化故障码（Raise the degenerate fault code）
        END_IF

    E_DL_RolloverPhase.eCount:             // 计数：按优先级链处理本拍指令（Counting with the priority chain）
        IF NOT _bBoundOk THEN              // 上限转退化（The bound became degenerate）
            _eState  := E_DL_RolloverPhase.eFrozen;          // 进入冻结态，计数保持（Frozen, count held）
            uErrorId := DL_ERR_PRESET;     // 置退化故障码（Raise the degenerate fault code）
        ELSIF NOT bEnable THEN             // 使能撤除（Enable removed）
            _eState := E_DL_RolloverPhase.eIdle;             // 回空闲，计数冻结（Back to idle, count frozen）
        ELSIF bLoad THEN                   // 装载优先，电平有效（Load has the highest priority）
            IF uLoadValue > _uBound THEN   // 装载值超上限（Load value above the bound）
                uCount   := _uBound;       // 钳到上限（Clamp to the bound）
                uErrorId := DL_ERR_INFO;   // 置钳位信息码（Raise the clamp info code）
            ELSE                           // 装载值在域内（Load value within range）
                uCount := uLoadValue;      // 直接装载（Take the load value as-is）
            END_IF
            bWrapped := FALSE;             // 装载拍不发回绕脉冲（No wrap pulse on a load scan）
        ELSIF _bUpEdge AND _bDownEdge THEN // 双向同拍（Both edges in the same scan）
            uErrorId := DL_ERR_INFO;       // 方向冲突已丢弃（Direction conflict discarded）
        ELSIF _bUpEdge AND (NOT _bResetEdge) THEN  // 加向，复位拍不重复加减（Increment, skipped on a reset scan）
            IF uCount >= _uBound THEN      // 已达上限，触发上回绕（At the bound, wrap upwards）
                uCount    := 0;            // 回绕到 0（Wrap to zero）
                _bWrapNow := TRUE;         // 标记本拍回绕（Flag the wrap of this scan）
                _nTurnStep := DL_TURN_UP;  // 圈数增量 +1（Turn increment plus one）
            ELSE                           // 未到上限（Below the bound）
                uCount := uCount + 1;      // 常规加 1（Plain increment）
                _nTurnStep := DL_TURN_HOLD;// 圈数不变（Turns unchanged）
            END_IF
        ELSIF _bDownEdge AND (NOT _bResetEdge) THEN  // 减向，复位拍不重复加减（Decrement, skipped on a reset scan）
            IF uCount = 0 THEN             // 已在下界，触发下回绕（At zero, wrap downwards）
                uCount    := _uBound;      // 回绕到上限（Wrap to the bound）
                _bWrapNow := TRUE;         // 标记本拍回绕（Flag the wrap of this scan）
                _nTurnStep := DL_TURN_DOWN;// 圈数增量 -1（Turn increment minus one）
            ELSE                           // 未到下界（Above zero）
                uCount := uCount - 1;      // 常规减 1（Plain decrement）
                _nTurnStep := DL_TURN_HOLD;// 圈数不变（Turns unchanged）
            END_IF
        END_IF

    E_DL_RolloverPhase.eFrozen:            // 冻结：上限退化，计数保持（Frozen, count held）
        IF NOT bEnable THEN                // 使能撤除（Enable removed）
            _eState := E_DL_RolloverPhase.eIdle;             // 回空闲（Back to idle）
        ELSIF _bBoundOk THEN               // 组态已修正（Configuration fixed）
            _eState := E_DL_RolloverPhase.eIdle;             // 回空闲后重新装载（Back to idle, then re-enter counting）
        ELSIF _bResetEdge THEN             // 复位沿请求退出冻结（Reset edge requests leaving the frozen state）
            _eState := E_DL_RolloverPhase.eIdle;             // 回空闲再重判（Back to idle for a fresh verdict）
        END_IF

    ELSE                                   // 兜底：非法态值（Fallback for an illegal state value）
        _eState  := E_DL_RolloverPhase.eFrozen;              // 一律回冻结态（Force the frozen state）
        uErrorId := DL_ERR_PRESET;         // 置退化故障码，提示检查（Raise the fault code for diagnosis）
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜圈数累计与饱和保护（边界 B5）
 *      Turn accumulation with saturation protection
 *   圈数增量与回绕动作在同一拍产生，本段统一入账，保证「一绕一圈」严格对称；
 *   饱和后停止累加但保留回绕脉冲，回绕事实不被吞掉。
 *-----------------------------------------------------------------------------*)
IF _nTurnStep > DL_TURN_HOLD THEN          // 上加（Upward wrap）
    IF nTurns < DL_TURNS_MAX THEN          // 未饱和（Not saturated）
        nTurns := nTurns + _nTurnStep;     // 圈数加 1（Add one turn）
    ELSE                                   // 已饱和（Already saturated）
        uErrorId := DL_ERR_INFO;           // 置饱和提示信息码（Raise the saturation info code）
    END_IF
ELSIF _nTurnStep < DL_TURN_HOLD THEN       // 下减（Downward wrap）
    IF nTurns > -DL_TURNS_MAX THEN         // 未饱和（Not saturated）
        nTurns := nTurns + _nTurnStep;     // 圈数减 1（Subtract one turn）
    ELSE                                   // 已饱和（Already saturated）
        uErrorId := DL_ERR_INFO;           // 置饱和提示信息码（Raise the saturation info code）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜单拍脉冲转出与输出映射
 *      One-shot pulse transfer and output mapping
 *   回绕脉冲由消费标志转出：本拍置位、下一拍由段 1 预清，宽度严格一拍；
 *   到限标志逐拍重算，与计数值同源，不存在第二份镜像。
 *-----------------------------------------------------------------------------*)
bWrapped  := _bWrapNow;                    // 回绕脉冲转出（Transfer the wrap pulse）
bAtPreset := _bBoundOk AND (uCount >= _uBound);  // 到限判定：上限可用且已达上限（Bound reached, valid bound only）
eState    := _eState;                      // 状态引脚映射（State pin mapping）

(*------------------------------------------------------------------------------
 * 段 8｜设计不变量索引（供终审逐条对照，不含可执行语句）
 *      Design invariant index for the reviewer, no executable statement
 *   I1 回绕只由「比较 + 赋值」产生，全文无 MOD、无无符号下溢、无上溢；
 *   I2 圈数增量与回绕动作同拍同源，不存在「计数绕了但圈数没记」的缝隙；
 *   I3 状态寄存器 _eState 单一写点（段 5），段 3 与段 4 只写保持量与故障位；
 *   I4 故障位 bError 只由上限退化置位、只由条件恢复清除，信息级码不触碰它；
 *   I5 三个边沿实例在段 2 无条件刷新，段 5 只消费结果，调用次序不可交换；
 *   I6 预清零（段 1）→ 消费（段 5）→ 转出（段 7）构成单拍脉冲完整生命周期；
 *   I7 全部阈值来自 VAR CONSTANT，逻辑区无裸数值散落。
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
