(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PackMlCmdDecoder
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· PackML 命令解码器 · Level 2 机台层
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（TON / R_TRIG /
 *                         SHR），零厂商方言
 * 功能描述 (Function)   : PackML 标准命令解码器：十个离散命令源（HMI/MES/
 *                         联锁均可接）与可选命令字入口（bit0..bit9 一一对应）
 *                         双通道收口，统一仲裁、防抖与单发化后输出 eCmd
 *                         （持续一拍）供 FB_DL_PackMlStateMachine 消费。
 * 设计要点 (Key notes)  : ① 同拍多命令 → 冲突位 + 全部丢弃（信息级 0005_0102，
 *                           安全侧选择「不猜」）；优先级仅用于显示仲裁
 *                           （Abort 显示最上），不用于执行——执行侧拒绝是
 *                           状态机的职责，解码器不做跃迁判断（职责单一）；
 *                         ② 离散源任一为 TRUE 时命令字被忽略（离散源优先，
 *                           现场按钮永远压过 MES 报文）；
 *                         ③ 单发化经 TON(tMinPulse) 展宽 + R_TRIG 取沿：
 *                           命令电平须持续 tMinPulse 才发单拍脉冲，防抖动
 *                           误触发；同一次按下只发一拍；
 *                         ④ uLastCmd 记录末次已受理命令，冲突拍不更新
 *                           （保持末次有效值）。
 * 枚举依赖 (Enum note)  : E_DL_PackMlCmd 定义随 FB_DL_PackMlStateMachine.st
 *                         同文件发布（规格书第 6 节交付约定），导入该文件后
 *                         全局可见，本块直接引用，不在本文件重复声明。
 * 规格偏离留档 (R11)    : 规格引脚表未列 uErrorId，但信息级 0005_0102 必须有
 *                         可观察出口，故补充 uErrorId : UDINT 输出引脚。
 * 开源溯源 (Origin)     : packml。来源为 OMAC PackML / ISA-TR88.00.02 公开
 *                         规范的 11 命令集合（S-1 提取点②）；解码、防抖与
 *                         仲裁实现 100% 自有 clean-room，不参考任何厂商源码。
 * 验收向量 (Acceptance) :
 *   V1 单命令链：bCmdStart 按住 ≥ tMinPulse → eCmd=eStart 单拍输出，
 *      长按不重复发（R_TRIG 取沿）；
 *   V2 命令字通道：uCmdWord=16#0004（bit2=Stop）→ eCmd=eStop 单拍；
 *   V3 冲突丢弃：bCmdStart+bCmdStop 同拍 → bCmdConflict=TRUE、eCmd 不出、
 *      信息级 0005_0102、uLastCmd 不变；
 *   V4 离散源优先：bCmdReset=TRUE 且 uCmdWord=16#0002 → 受理 Reset，
 *      命令字被忽略；
 *   V5 防抖：bCmdStart 毛刺 < tMinPulse → 无输出。
 * 故障码表 (Error codes):
 *   16#0005_0102【信息级】同拍多命令冲突全部丢弃（安全侧不猜）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 05 · DL_Process 立项）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbDec(bCmdStart := bHmiStart, bCmdStop := bHmiStop,   // 周期调用
 *         uCmdWord := wMesCmdWord, tMinPulse := T#100MS);
 *   fbPml.eCmd := fbDec.eCmd;                             // 状态机同拍消费
 *   命令字位域：bit0=Reset bit1=Start bit2=Stop bit3=Hold bit4=Unhold
 *   bit5=Suspend bit6=Unsuspend bit7=Abort bit8=Clear bit9=Complete；
 *   bit10..bit15 保留，置位不影响解码（掩码 16#03FF 截取）。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 离散源与命令字是"或不可"关系而非"或"关系：任一离散源为 TRUE 的
 *     拍，命令字整字失效；MES 联调时发现命令字不生效，先查有没有按钮
 *     卡住或联锁位常 TRUE。
 *   2 tMinPulse 展宽的是"电平持续时间"：状态机每拍都在消费 eCmd，若把
 *     脉宽调得过小而扫描周期偏大，可能出现命令电平跨拍不足被吞——
 *     现场默认 T#100MS 在 10ms 任务下有 10 拍裕量，够用。
 *   3 冲突位是瞬态的：只在与多命令同拍的扫描周期为 TRUE，HMI 若要
 *     弹窗提示需自行锁存，本块刻意不做锁存以免故障码污染。
 *   4 uLastCmd 是"末次受理"不是"当前请求"：冲突与空拍都不改写，屏上
 *     以此回显最近一次真正打进状态机的命令。
 *   5 Abort 的显示优先级（最高）只影响冲突拍的画面归因排序，多命令
 *     冲突拍任何命令都不会被发出——执行层不猜，安全侧全弃。
 *   6 本块输出 eCmd 与状态机输入 eCmd 直连时注意同拍时序：解码器先于
 *     状态机调用即可保证命令当拍到达，不产生额外拍延迟。
 *----------------------------------------------------------------------------*)
FUNCTION_BLOCK FB_DL_PackMlCmdDecoder
VAR_INPUT
    bCmdReset     : BOOL := FALSE;      // 复位命令源（Reset command source），电平生效
    bCmdStart     : BOOL := FALSE;      // 启动命令源（Start command source），电平生效
    bCmdStop      : BOOL := FALSE;      // 停止命令源（Stop command source），电平生效
    bCmdHold      : BOOL := FALSE;      // 保持命令源（Hold command source），电平生效
    bCmdUnhold    : BOOL := FALSE;      // 解除保持命令源（Unhold command source），电平生效
    bCmdSuspend   : BOOL := FALSE;      // 挂起命令源（Suspend command source），电平生效
    bCmdUnsuspend : BOOL := FALSE;      // 解除挂起命令源（Unsuspend command source），电平生效
    bCmdAbort     : BOOL := FALSE;      // 急停命令源（Abort command source），电平生效
    bCmdClear     : BOOL := FALSE;      // 清除命令源（Clear command source），电平生效
    bCmdComplete  : BOOL := FALSE;      // 完工命令源（Complete command source），电平生效
    uCmdWord      : WORD := 16#0000;    // 可选命令字入口（Optional command word），bit0..bit9 对应十命令；离散源任一为 TRUE 时被忽略
    tMinPulse     : TIME := T#100MS;    // 最小命令脉宽（Min command pulse），防抖动误触发
END_VAR
VAR_OUTPUT
    eCmd          : E_DL_PackMlCmd := E_DL_PackMlCmd.eUndefined;  // 单发化命令输出（One-shot command），持续一拍
    bCmdConflict  : BOOL := FALSE;      // 命令冲突指示（Command conflict），同拍多命令
    uLastCmd      : E_DL_PackMlCmd := E_DL_PackMlCmd.eUndefined;  // 末次有效命令（Last accepted command），冲突拍不更新
    uErrorId      : UDINT := 0;         // 末次信息级事件码（Last info code），规格外补充引脚（见头注 R11 留档）
END_VAR
VAR
    uDiscreteWord : WORD := 16#0000;    // 离散源合成命令字（Discrete sources word）
    uWordEff      : WORD := 16#0000;    // 有效命令字（Effective command word），已按优先通道截取
    uTmp          : WORD := 16#0000;    // 位扫描工作副本（Bit scan working copy）
    i             : INT := 0;           // 位扫描循环索引（Bit scan loop index），固定 0..9 无死循环风险
    uBitCount     : INT := 0;           // 有效命令位数（Effective command bit count）
    uBitIdx       : INT := 0;           // 末位命中索引（Last hit bit index），唯一命中时即命令位
    eCmdLvl       : E_DL_PackMlCmd := E_DL_PackMlCmd.eUndefined;  // 受理命令电平（Accepted command level）
    bCmdLevel     : BOOL := FALSE;      // 受理命令电平标志（Accepted command level flag）
    tonMinPulse   : TON;                // 最小脉宽展宽定时器（Min pulse stretch timer）
    rtrigEmit     : R_TRIG;             // 命令发放沿检测（Command emit edge trigger）
END_VAR
VAR CONSTANT
    DL_PML_WORD_MASK : WORD := 16#03FF; // 命令字有效位掩码（Command word mask），bit10..15 保留截断
END_VAR

// 段 1｜离散源合成命令字：bit0=Reset … bit9=Complete（位域逐位对应）
uDiscreteWord := 16#0000;
IF bCmdReset THEN
    uDiscreteWord := uDiscreteWord OR 16#0001;        // bit0：复位（Reset）
END_IF
IF bCmdStart THEN
    uDiscreteWord := uDiscreteWord OR 16#0002;        // bit1：启动（Start）
END_IF
IF bCmdStop THEN
    uDiscreteWord := uDiscreteWord OR 16#0004;        // bit2：停止（Stop）
END_IF
IF bCmdHold THEN
    uDiscreteWord := uDiscreteWord OR 16#0008;        // bit3：保持（Hold）
END_IF
IF bCmdUnhold THEN
    uDiscreteWord := uDiscreteWord OR 16#0010;        // bit4：解除保持（Unhold）
END_IF
IF bCmdSuspend THEN
    uDiscreteWord := uDiscreteWord OR 16#0020;        // bit5：挂起（Suspend）
END_IF
IF bCmdUnsuspend THEN
    uDiscreteWord := uDiscreteWord OR 16#0040;        // bit6：解除挂起（Unsuspend）
END_IF
IF bCmdAbort THEN
    uDiscreteWord := uDiscreteWord OR 16#0080;        // bit7：急停（Abort）
END_IF
IF bCmdClear THEN
    uDiscreteWord := uDiscreteWord OR 16#0100;        // bit8：清除（Clear）
END_IF
IF bCmdComplete THEN
    uDiscreteWord := uDiscreteWord OR 16#0200;        // bit9：完工（Complete）
END_IF

// 段 2｜双通道仲裁：离散源任一为 TRUE 时命令字被忽略（现场按钮压过 MES 报文）
IF uDiscreteWord <> 16#0000 THEN
    uWordEff := uDiscreteWord;
ELSE
    uWordEff := uCmdWord AND DL_PML_WORD_MASK;        // 命令字通道，保留位截断
END_IF

// 段 3｜位扫描计数：固定 0..9 十次迭代，无死循环风险；唯一命中位即命令位
uBitCount := 0;
uBitIdx := 0;
uTmp := uWordEff;
FOR i := 0 TO 9 DO
    IF (uTmp AND 16#0001) <> 16#0000 THEN
        uBitCount := uBitCount + 1;
        uBitIdx := i;                   // 多命中时取最低位，仅用于显示仲裁参考
    END_IF
    uTmp := SHR(uTmp, 1);
END_FOR

// 段 4｜仲裁裁决：多命令全部丢弃（安全侧不猜），单命令映射枚举
IF uBitCount > 1 THEN
    bCmdConflict := TRUE;               // 同拍多命令 → 冲突位
    uErrorId := 16#0005_0102;           // 信息级：全部丢弃，优先级仅用于显示
    bCmdLevel := FALSE;
    eCmdLvl := E_DL_PackMlCmd.eUndefined;
ELSIF uBitCount = 1 THEN
    bCmdConflict := FALSE;
    CASE uBitIdx OF                     // 命令位 → 命令枚举映射（唯一命中）
        0: eCmdLvl := E_DL_PackMlCmd.eReset;        // bit0：复位（Reset）
        1: eCmdLvl := E_DL_PackMlCmd.eStart;        // bit1：启动（Start）
        2: eCmdLvl := E_DL_PackMlCmd.eStop;         // bit2：停止（Stop）
        3: eCmdLvl := E_DL_PackMlCmd.eHold;         // bit3：保持（Hold）
        4: eCmdLvl := E_DL_PackMlCmd.eUnhold;       // bit4：解除保持（Unhold）
        5: eCmdLvl := E_DL_PackMlCmd.eSuspend;      // bit5：挂起（Suspend）
        6: eCmdLvl := E_DL_PackMlCmd.eUnsuspend;    // bit6：解除挂起（Unsuspend）
        7: eCmdLvl := E_DL_PackMlCmd.eAbort;        // bit7：急停（Abort）
        8: eCmdLvl := E_DL_PackMlCmd.eClear;        // bit8：清除（Clear）
        9: eCmdLvl := E_DL_PackMlCmd.eComplete;     // bit9：完工（Complete）
    ELSE
        eCmdLvl := E_DL_PackMlCmd.eUndefined;       // 非法位兜底
    END_CASE
    bCmdLevel := TRUE;
ELSE
    bCmdConflict := FALSE;              // 无命令
    bCmdLevel := FALSE;
    eCmdLvl := E_DL_PackMlCmd.eUndefined;
END_IF

// 段 5｜单发化：TON 展宽 tMinPulse 防抖 + R_TRIG 取沿，同一次按下只发一拍
tonMinPulse(CLK := bCmdLevel, PT := tMinPulse);       // 无条件周期刷新（R7 红线）
rtrigEmit(CLK := tonMinPulse.Q);                       // 无条件周期刷新（R7 红线）

eCmd := E_DL_PackMlCmd.eUndefined;                     // 输出默认回零（单拍脉冲语义）
IF rtrigEmit.Q THEN
    eCmd := eCmdLvl;                    // 发放一拍
    uLastCmd := eCmdLvl;                // 受理命令记录；冲突拍不更新（保持末次有效值）
END_IF
END_FUNCTION_BLOCK
