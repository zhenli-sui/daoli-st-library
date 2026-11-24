(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BidirectionalCounter
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 双向预设计数器 · CTUD 超集
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library 的 R_TRIG
 * 功能描述 (Function)   : 上 / 下双向计数（CU / CD 双沿入口），带装载（Load）、
 *                         复位（Reset）、上下独立预设（PV_UP / PV_DN）与双向
 *                         到预设输出（QU / QD），支持饱和不回绕与同拍双边沿
 *                         「加优先」仲裁。对应 IEC 61131-3 标准 CTUD 语义的
 *                         超集（标准 CTUD 只有单一 PV，本件上下各一个预设）。
 *                         典型场景：库位进出双向计数、双向行程脉冲累计、
 *                         双向流量累积、批次进出料差额核算。
 * 职责矩阵 (Scope map)  : 本库计数四件套职责互斥，不可互相替代：
 *                         FB_DL_EventCounter      通用事件累加（单向、无预设）
 *                         FB_DL_ModuloCounter     取模回绕工位索引（单向、循环）
 *                         FB_DL_PresetCounterSat  单向上下限双预设饱和
 *                         本件                    双向 CU 加 CD，双向独立预设，
 *                                                 双向饱和，加优先仲裁
 * 设计要点 (Key notes)  : ① 执行次序写死：预清零 → 取沿 → 预设校验 → 复位 →
 *                           装载 → 计数 → 饱和 → 比较输出，次序颠倒会出现
 *                           「装载拍还多计一个」这类现场最难查的缺陷；
 *                         ② 装载优先于计数：装载边沿拍内计数分支被完全跳过，
 *                           保证「装载值」不会被同拍计数污染；
 *                         ③ 同拍双边沿按「加优先」处理（净加 1），与 IEC
 *                           CTUD 惯例一致，已在注释中写死，不做方向仲裁参数；
 *                         ④ 预设倒置（PV_UP 小于等于 PV_DN）只锁故障不冻结
 *                           计数，与 FB_DL_PresetCounterSat 的「倒置即冻结」
 *                           策略相反，差异在此显式声明（现场止损优先）；
 *                         ⑤ QU / QD 为保持型（R27）：每拍按当前 CV 重算，
 *                           不允许只在「跨越预设那一拍」置位，否则 HMI 会
 *                           看到输出闪断。
 * 开源溯源 (Origin)     : lgf-counter。参考 LGF（Libre Graphical Framework）
 *                         公开函数库「Counter」分类中双向计数类函数的功能
 *                         分类与参数域（CU / CD / LOAD / PV 四组入口形态），
 *                         只借分类、参数域与命名习惯，算法与实现 100% 自有
 *                         clean-room，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 R_TRIG
 * 故障码表 (Error codes):
 *   16#0001_0118【信息级】装载值越界被钳位，装载照常完成
 *   16#0001_0215【故障级】预设倒置（PV_UP 小于等于 PV_DN），锁存 bError，
 *                        计数不冻结；只能由 bReset 清除
 *   16#0001_0216【故障级】保留位，本块无 CASE 主状态机，仅作防御式默认码
 *   信息级码只进 uErrorId，不置 bError（R21）。
 * 验收向量 (Acceptance) :
 *   V1 基本双向：PV_UP = 3 / PV_DN = 0，CU 三拍 → CV = 3、QU = TRUE；
 *      CD 一拍 → CV = 2、QU = FALSE、QD = FALSE
 *   V2 同拍双边沿：CU 与 CD 同拍上升 → CV 净加 1，UP 脉冲为 TRUE，DN 为 FALSE
 *   V3 装载优先：bLoad 与 bCountUp 同拍 → CV 等于装载值，装载脉冲为 TRUE，
 *      加计数脉冲为 FALSE
 *   V4 倒置预设：PV_UP = 5 / PV_DN = 10 → bError = TRUE、码 0215，计数继续
 *   V5 饱和：装载 DL_COUNT_MAX 后 CU 一拍 → CV 不变、AtMax = TRUE、无脉冲
 *   V6 保持语义：QU 为 TRUE 后再 CU 两拍，QU 每拍仍为 TRUE（不得回落）
 * 现场提示 (Field notes):
 *   1 bCountUp / bCountDown 取的是上升沿，编码器 A 相脉冲可直接接入，但
 *     高频脉冲（高于任务频率一半）会丢沿，需先由硬件高速计数模块预处理；
 *   2 bReset 为电平有效且优先级高于装载，复位拍不产生装载脉冲，联锁复位
 *     与装载同时给时以复位为准；
 *   3 bEnable 为 FALSE 时冻结计数并清 QU / QD，但 CV 保持，便于检修时保留
 *     当前值；重新使能后从冻结值继续，不做归零；
 *   4 本块不含回绕行为，计到上限即饱和并置 bAtMax，需要回绕请用
 *     FB_DL_ModuloCounter，不要把两个语义混在一个块里。
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 DINT 饱和钳位防溢出
 *                         R5 全变量中英双语同行注释 ｜ R6 无 CASE 主状态机（计数型），
 *                         防御式默认码 0216 保留 ｜ R7 三个 R_TRIG 均在分支外刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · Level 0 计数族回补）
 *============================================================================*)

(*==============================================================================
 * 执行次序总表 (Execution order，写死，不得调整)：
 *   序号 步骤            依赖条件              违反后的典型现场现象
 *   1    单拍脉冲预清零  无                    脉冲跨拍泄漏，上一层多计一次
 *   2    三个沿检测刷新  无                    边沿丢失，计数少一拍
 *   3    首扫初始化      仅首扫一次            初值不确定，首件计数错
 *   4    预设域校验      每拍                  预设改错后无提示，输出恒真
 *   5    复位            电平                  复位不生效或复位拍仍计数
 *   6    装载            装载边沿              装载值被同拍计数污染
 *   7    方向仲裁与计数  使能且非复位非装载    上下同拍时净变化不为 1
 *   8    饱和标志        每拍                  到限位后继续累加，溢出回绕
 *   9    比较输出        每拍                  输出只在跨阈拍有效，HMI 闪断
 *   10   对外镜像        每拍                  输出与内部值不同步
 *============================================================================*)

(*==============================================================================
 * 逐拍推演 (Cycle-by-cycle trace)：
 *   场景 A 基本双向（PV_UP=3，PV_DN=0，CV 初值 0）
 *     拍 1 加计数沿 → 方向仲裁走加分支，CV 由 0 变 1，加脉冲为真，QU 假
 *     拍 2 加计数沿 → CV 由 1 变 2，加脉冲为真，QU 假
 *     拍 3 加计数沿 → CV 由 2 变 3，加脉冲为真，QU 真（3 大于等于 3）
 *     拍 4 无沿     → 输出全部保持，QU 仍真（保持语义，不得回落）
 *     拍 5 减计数沿 → CV 由 3 变 2，减脉冲为真，QU 变假
 *   场景 B 同拍双边沿（PV_UP=100）
 *     拍 1 两路同时上升 → 加优先分支，CV 净加 1，加脉冲真、减脉冲假
 *   场景 C 装载与计数同拍
 *     拍 1 装载沿加计数沿 → 装载先执行，CV 等于装载值，装载脉冲真，
 *          本拍跳过计数分支，加脉冲保持假
 *   场景 D 倒置预设（PV_UP=5，PV_DN=10）
 *     拍 1 校验成立 → 锁故障、码 0215，但计数分支照常执行
 *     拍 2 加计数沿 → CV 由 0 变 1（计数未被冻结）
 *   场景 E 饱和（装载 DL_COUNT_MAX 后加计数一拍）
 *     拍 1 装载 → CV 等于上限
 *     拍 2 加计数沿 → 判 CV 不小于上限，不加、不置脉冲，AtMax 为真
 *============================================================================*)

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   VAR fbSlotCnt : FB_DL_BidirectionalCounter; END_VAR
 *   fbSlotCnt(
 *       bCountUp   := bPartInPulse,      // 进料光电脉冲
 *       bCountDown := bPartOutPulse,     // 出料光电脉冲
 *       bLoad      := bRecipeLoad,       // 配方切换时装载
 *       nLoadValue := nRecipeStartCount, // 配方起始值
 *       bReset     := bShiftReset,       // 班次复位
 *       nPresetUp  := nFullLevel,        // 满仓阈值
 *       nPresetDn  := nEmptyLevel,       // 空仓阈值
 *       bEnable    := bStationEnabled);
 *   bFull  := fbSlotCnt.bQu;
 *   bEmpty := fbSlotCnt.bQd;
 *   IF fbSlotCnt.bError THEN nAlarm := fbSlotCnt.uErrorId; END_IF
 *   注意：本块每拍必须调用一次，跳过调用会使边沿检测失效并冻结计数。
 *============================================================================*)

(*==============================================================================
 * 与标准 CTUD 的差异声明 (Deviation from IEC CTUD)：
 *   1 标准 CTUD 只有单一 PV 与单一 QU；本件有上下两个独立预设与两个输出，
 *     以满足双向工艺（满仓与空仓两个阈值）的实际需要；
 *   2 标准 CTUD 在到达计数类型边界时行为未定义；本件在远离边界的
 *     正负二十一万万处饱和，保证加一与减一永不溢出；
 *   3 标准 CTUD 不定义同拍双边沿的净效果；本件写死为加优先净加一；
 *   4 标准 CTUD 无故障概念；本件在预设倒置时锁故障但不冻结计数。
 *============================================================================*)

(*==============================================================================
 * 输出真值表 (Output truth table)：
 *   状态组合                                      QU    QD    含义
 *   使能 且 CV 大于等于 PV_UP                     真    按 QD 判定   满仓侧到达
 *   使能 且 CV 小于等于 PV_DN                     按 QU   真         空仓侧到达
 *   使能 且 PV_UP 大于 CV 大于 PV_DN              假    假         正常区间
 *   失能 且 CV 任意                               假    假         冻结，CV 保持
 *   复位拍 且 CV 归零                             按新 CV 重算        复位优先
 *   PV_UP 与 PV_DN 倒置                           仍按比较式输出      计数不冻结，另报故障
 *   注：两行「按 QU 判定」表示该列的取值与另一列同时成立时互不影响，
 *       两个输出互相独立，不互斥，也不做优先级仲裁。
 *============================================================================*)

(*==============================================================================
 * 参数域与默认值说明 (Parameter domain)：
 *   bCountUp    布尔，上升沿有效；无默认，必须由现场光电或编码器给出
 *   bCountDown  布尔，上升沿有效；无默认，必须由现场光电或编码器给出
 *   bLoad       布尔，上升沿有效；建议用配方切换脉冲或手动装载按钮
 *   nLoadValue  双整数，默认 0，域正负二十一万万；越界自动钳位并置 0118
 *   bReset      布尔，电平有效；建议接班次复位或工位初始化，不接急停
 *   nPresetUp   双整数，默认 100，域建议放在工艺允许范围内，须大于 PV_DN
 *   nPresetDn   双整数，默认 0，域建议放在工艺允许范围内，须小于 PV_UP
 *   bEnable     布尔，默认真；检修时置假可冻结计数并保留当前值
 *   说明：预设值不做内部钳位，只做倒置校验，因为预设是工艺参数而不是
 *   物理量，钳位会掩盖组态错误；倒置只锁故障不改值，便于工程师看到原始填错
 *   的两个数字再决定怎么改。
 *============================================================================*)

(*==============================================================================
 * 常见误用与现场提示 (Field notes)：
 *   1 把高频编码器脉冲直接接到 bCountUp：本块按任务周期取沿，脉冲频率
 *     高于任务频率一半时会丢沿，表现为「计数偏小且不稳定」；正确做法是
 *     先用硬件高速计数模块预处理，或把本块放在高速任务里；
 *   2 把 bReset 接急停回路：急停应当切断输出侧并由安全层处理，本块的复位
 *     只是计数归零，接急停会导致「拍下急停后计数清零」这种不可追溯的行为；
 *   3 把 QU 与 QD 当作互斥的两个状态：两者可能同时为真（当预设区间被
 *     配置成重叠甚至倒置时），上位必须按「两个独立阈值」处理；
 *   4 用本块做取模回绕（如工位号循环）：本块饱和不回绕，请改用
 *     FB_DL_ModuloCounter，两者语义不同，混用会出现「到顶后卡住」；
 *   5 装载后立刻读 CV：装载在同一扫描周期已经完成，读到的就是装载值，
 *     不需要等下一拍；装载脉冲只在该拍为真，下一拍自动清零。
 *============================================================================*)

(*==============================================================================
 * 选型指引 (Which counter to use)：
 *   现场需求                                     应当选用的组件
 *   只想知道「发生了多少次」，不设阈值            FB_DL_EventCounter
 *   工位号在固定范围内循环（如转盘十六工位）      FB_DL_ModuloCounter
 *   单向计数，上下两个阈值，到顶后冻结            FB_DL_PresetCounterSat
 *   双向计数（进出两个方向），上下两个独立阈值    本件
 *   需要计长、累计流量、累计运行时间的工程量      不属于计数件，请用相应工艺件
 *   选错件的典型后果：用本件做转盘循环会在到顶后卡住；用取模件做满仓判断
 *   会永远等不到「满」这个状态，因为取模件根本不产生阈值输出。
 *============================================================================*)

(*==============================================================================
 * 联调清单 (Commissioning checklist)：
 *   1 先确认两路计数信号在静止时都为假，若有常真信号，上电首拍就会误计一次；
 *   2 手动触发一次进料，观察 bUpPulse 是否只闪一拍，若连续闪多拍说明输入
 *     信号抖动，请在上一层加防抖（FC_DL_SignalDebounce 或 FB_DL_SignalDebounce）；
 *   3 把 PV_UP 临时设成当前值，确认 QU 立刻变真，验证比较链路通畅；
 *   4 把 PV_DN 设成大于 PV_UP 的值，确认 bError 置位且码为 0215，验证倒置
 *     保护；验证完毕后必须改回正确值并给一次复位，否则故障锁存不会自清；
 *   5 装载一次上限值再手动加计数，确认 CV 不动且 AtMax 为真，验证饱和；
 *   6 断使能一拍，确认 CV 保持且 QU 与 QD 都为假，验证冻结语义。
 *============================================================================*)

(*==============================================================================
 * 执行代价 (Cost)：
 *   每拍固定两次边沿检测、最多两次整数加减、四次比较，无条件分支以外的
 *   逻辑量恒定，最坏执行时间可静态界定。本件不含循环、不含定时器、不含
 *   浮点，因此放在高速计数中断所挂的任务里也不会有抖动；唯一的库依赖是
 *   R_TRIG，其内部只保存一个上一拍电平，无任何时间量参与。
 *============================================================================*)

FUNCTION_BLOCK FB_DL_BidirectionalCounter
VAR_INPUT
    bCountUp   : BOOL;               // 加计数输入，上升沿加 1，主周期无条件取沿 [-] / Count-up input, rising edge increments by one
    bCountDown : BOOL;               // 减计数输入，上升沿减 1，与加计数同拍时加优先 [-] / Count-down input, rising edge decrements by one
    bLoad      : BOOL;               // 装载请求，上升沿装载，装载拍跳过计数 [-] / Load request, rising edge loads and skips counting
    nLoadValue : DINT := 0;          // 装载值，域 DL_COUNT_MIN 到 DL_COUNT_MAX [计数值] / Load value, range DL_COUNT_MIN to DL_COUNT_MAX
    bReset     : BOOL;               // 复位请求，电平有效：CV 归 0、清 QU / QD 与锁存 [-] / Reset request, level active: CV to zero, clears flags and latches
    nPresetUp  : DINT := 100;        // 加预设值 PV_UP，CV 大于等于此值时 QU 为 TRUE [计数值] / Preset up, QU is TRUE while CV is greater or equal
    nPresetDn  : DINT := 0;          // 减预设值 PV_DN，CV 小于等于此值时 QD 为 TRUE [计数值] / Preset down, QD is TRUE while CV is less or equal
    bEnable    : BOOL := TRUE;       // 使能，FALSE 时冻结计数并清 QU / QD，CV 保持 [-] / Enable, FALSE freezes counting and clears QU and QD
END_VAR
VAR_OUTPUT
    nCv        : DINT;               // 当前计数值 CV，饱和域内不回绕 [计数值] / Current count value, saturated, no wrap-around
    bQu        : BOOL;               // 加预设到达，保持型，CV 大于等于 PV_UP 期间持续为真 [-] / Up preset reached, holding type
    bQd        : BOOL;               // 减预设到达，保持型，CV 小于等于 PV_DN 期间持续为真 [-] / Down preset reached, holding type
    bAtMax     : BOOL;               // 已达上限饱和，再加 1 被拒 [-] / Upper saturation reached, further increments rejected
    bAtMin     : BOOL;               // 已达下限饱和，再减 1 被拒 [-] / Lower saturation reached, further decrements rejected
    bUpPulse   : BOOL;               // 本次实际加计数成功，单拍脉冲 [-] / Increment actually applied this cycle, single-cycle pulse
    bDnPulse   : BOOL;               // 本次实际减计数成功，单拍脉冲 [-] / Decrement actually applied this cycle, single-cycle pulse
    bLoadDone  : BOOL;               // 装载完成，单拍脉冲 [-] / Load completed, single-cycle pulse
    uErrorId   : UDINT;              // 事件码，0 = 无事件 / Event code, 0 = no event
    bError     : BOOL;               // 故障锁存，仅故障级码置位，复位清除 [-] / Fault latch, set only by fault-level codes
END_VAR
VAR
    fbTrigUp    : R_TRIG;            // 加计数边沿检测实例，分支外无条件刷新 [-] / Rising edge detector for count-up input
    fbTrigDown  : R_TRIG;            // 减计数边沿检测实例，分支外无条件刷新 [-] / Rising edge detector for count-down input
    fbTrigLoad  : R_TRIG;            // 装载边沿检测实例，分支外无条件刷新 [-] / Rising edge detector for load request
    bInit       : BOOL := FALSE;     // 首扫标志，初值 FALSE，判据 NOT bInit（R19 范式）[-] / First-scan flag, initial FALSE, tested with NOT
    nCvInt      : DINT := 0;         // 内部计数值，对外经 nCv 镜像输出 [计数值] / Internal count value, mirrored to nCv
    bPresetBad  : BOOL;              // 预设倒置锁存，PV_UP 小于等于 PV_DN 时为 TRUE [-] / Preset inversion latch
    nLoadClamp  : DINT;              // 装载值钳位中间量 [计数值] / Clamped load value temp
END_VAR
VAR CONSTANT
    DL_COUNT_MAX : DINT := 2147483000;   // 计数上限，留安全裕度防加 1 溢出 [计数值] / Count upper bound with overflow margin
    DL_COUNT_MIN : DINT := -2147483000;  // 计数下限，留安全裕度防减 1 溢出 [计数值] / Count lower bound with underflow margin
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜单拍输出预清零（R25 律①）：三个脉冲输出必须在主体最前部清零
 *      Single-cycle output pre-clear (R25 rule 1): clear the three pulses first
 *      若把清零放在计数之后，上一拍的脉冲会残留到本拍，形成「跨拍泄漏」
 *-----------------------------------------------------------------------------*)
bUpPulse  := FALSE;
bDnPulse  := FALSE;
bLoadDone := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜边沿实例无条件周期刷新（R7 红线）：不得放在 IF 或 CASE 分支内
 *      Edge instances refreshed unconditionally every cycle, never inside a branch
 *-----------------------------------------------------------------------------*)
fbTrigUp(CLK := bCountUp);
fbTrigDown(CLK := bCountDown);
fbTrigLoad(CLK := bLoad);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（R19 唯一合法范式）：初值 FALSE，判据 NOT bInit
 *      First-scan initialisation: initial value FALSE, tested with NOT bInit
 *      首扫只装载初值与清锁存，不做任何输入相关的动作
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    nCvInt     := 0;                 // 计数从 0 起
    bPresetBad := FALSE;             // 清预设倒置锁存
    bError     := FALSE;             // 清故障锁存
    uErrorId   := 16#0000_0000;      // 清事件码
    bAtMax     := FALSE;             // 饱和位复位
    bAtMin     := FALSE;             // 饱和位复位
    bInit      := TRUE;              // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜预设域校验（每拍重算）：倒置即锁故障，但计数继续
 *      Preset domain check every cycle: inversion latches a fault, counting goes on
 *      现场取舍：宁可带着一组错预设继续计数，也不因一次组态失误停线；
 *      与 FB_DL_PresetCounterSat 的「倒置冻结」策略相反，此处显式声明差异
 *-----------------------------------------------------------------------------*)
IF nPresetUp <= nPresetDn THEN
    bPresetBad := TRUE;
    bError     := TRUE;              // 故障级：锁存
    uErrorId   := 16#0001_0215;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜复位（电平有效，优先于装载）：CV 归 0，清全部锁存
 *      Reset is level active and takes precedence over load
 *-----------------------------------------------------------------------------*)
IF bReset THEN
    nCvInt     := 0;
    bPresetBad := FALSE;
    bError     := FALSE;
    uErrorId   := 16#0000_0000;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜装载（边沿有效，优先于计数）：装载拍完全跳过计数分支
 *      Load on rising edge, takes precedence over counting for that cycle
 *      装载值先钳位再落盘，越界只置信息级码，装载动作照常完成
 *-----------------------------------------------------------------------------*)
IF fbTrigLoad.Q AND (NOT bReset) THEN
    nLoadClamp := nLoadValue;
    IF nLoadClamp > DL_COUNT_MAX THEN
        nLoadClamp := DL_COUNT_MAX;
        uErrorId   := 16#0001_0118;  // 装载值越界钳位（信息级）
    ELSIF nLoadClamp < DL_COUNT_MIN THEN
        nLoadClamp := DL_COUNT_MIN;
        uErrorId   := 16#0001_0118;  // 装载值越界钳位（信息级）
    END_IF
    nCvInt    := nLoadClamp;
    bLoadDone := TRUE;               // 装载脉冲，单拍
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜方向仲裁与计数（装载拍与复位拍均不计数）
 *      Direction arbitration and counting, skipped on load and reset cycles
 *      同拍双边沿：加优先，净加 1（IEC CTUD 惯例，语义写死不再开放参数）
 *-----------------------------------------------------------------------------*)
IF bEnable AND (NOT bReset) AND (NOT fbTrigLoad.Q) THEN
    IF fbTrigUp.Q AND (NOT fbTrigDown.Q) THEN
        IF nCvInt < DL_COUNT_MAX THEN
            nCvInt   := nCvInt + 1;
            bUpPulse := TRUE;
        END_IF
    ELSIF fbTrigDown.Q AND (NOT fbTrigUp.Q) THEN
        IF nCvInt > DL_COUNT_MIN THEN
            nCvInt   := nCvInt - 1;
            bDnPulse := TRUE;
        END_IF
    ELSIF fbTrigUp.Q AND fbTrigDown.Q THEN
        IF nCvInt < DL_COUNT_MAX THEN
            nCvInt   := nCvInt + 1;  // 加优先：同拍双边沿净加 1
            bUpPulse := TRUE;
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜饱和标志每拍重算：饱和位不是事件位，而是状态的派生量
 *      Saturation flags recomputed every cycle as derived state
 *-----------------------------------------------------------------------------*)
IF nCvInt >= DL_COUNT_MAX THEN
    bAtMax := TRUE;
ELSE
    bAtMax := FALSE;
END_IF

IF nCvInt <= DL_COUNT_MIN THEN
    bAtMin := TRUE;
ELSE
    bAtMin := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜比较输出每拍重写（R27 保持语义）：禁止只在跨预设那一拍赋值
 *      Comparison outputs rewritten every cycle to keep the holding semantics
 *-----------------------------------------------------------------------------*)
IF bEnable AND (nCvInt >= nPresetUp) THEN
    bQu := TRUE;
ELSE
    bQu := FALSE;
END_IF

IF bEnable AND (nCvInt <= nPresetDn) THEN
    bQd := TRUE;
ELSE
    bQd := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜对外镜像输出：内部值单一来源，外部只读
 *      Mirror the internal count to the output pin, single source of truth
 *-----------------------------------------------------------------------------*)
nCv := nCvInt;

(*------------------------------------------------------------------------------
 * 防御式默认码说明（0216）：本块为计数型，无 CASE 主状态机，故 0216 不参与
 * 正常运行路径，仅作为后续维护者新增分支时的保留码，禁止挪作他用。
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
