(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitArrayReverse
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 位数组段镜像反转
 *                         iec-std-wrapper / bitstring / bit-array
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；零库函数依赖，纯标准布尔交换
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : 位数组指定段的镜像反转（首尾对调向中推进），段域
 *                         双闸（起始下标、段长），空段或单元素恒等返回。
 *
 * 功能描述 (Function)   : 先过段域双闸：起始下标在 0..127 且段长非负且
 *                         起始加段长不越 128 上界，域外拒绝且不触碰数组；
 *                         合法路径用 VAR_IN_OUT 就地交换，双指针向中推进，
 *                         段长小于等于 1 时恒等返回并告知。
 * 与既有件边界 (Boundary): BitArray 族 Extract/Insert/Rotate/SegCopy 覆盖
 *                         取段、插段、循环移位与段复制；本件补镜像反转原子，
 *                         服务 LSB/MSB 序数组整体换序与测试向量构造。
 * 码位说明 (Codes)      : 信息 16#0002_3054 段长小于等于 1，恒等返回
 *                         故障 16#0002_3055 起始下标域外（小于 0 或越上界）
 *                         故障 16#0002_3056 段长域外（负值或越出数组上界）
 *                         段 16#02_3_54~57 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；零库函数依赖。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         循环上界由已闸段参数给定，无越局面
 *                         全变量双语同行注释 ｜ 无定时器实例 ｜ 无状态机
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 3）
 *============================================================================*)

FUNCTION FC_DL_BitArrayReverse : BOOL
VAR_INPUT
    iStart : INT;                       // 段起始下标 [索引]，域 0 到 127 / Segment start index, 0 to 127
    iLen   : INT;                       // 段长 [位]，域 0 到 128 减起始 / Segment length in bits
END_VAR
VAR_IN_OUT
    aBits  : ARRAY[0..127] OF BOOL;     // 位数组 [位]，就地反转不复制 / Bit array reversed in place
END_VAR
VAR_OUTPUT
    nSwapped : INT;                     // 交换对数 [对]，段长一半向下取整 / Swap pairs, half the length
    uErrorId : UDINT;                   // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    bTmp  : BOOL;   // 交换暂存位 [位] / Swap staging bit
    nLo   : INT;    // 左指针 [索引] / Left pointer
    nHi   : INT;    // 右指针 [索引] / Right pointer
    uCode : UDINT;  // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_BAR_SIZE : INT := 128;           // 数组位容量 [位]，与声明一致 / Array capacity, matches the declaration
END_VAR

(* 段 1｜输出预置 / Pre-set *)
FC_DL_BitArrayReverse := FALSE;
nSwapped := 0;
uErrorId := 16#0000_0000;
uCode    := 16#0000_0000;

(* 段 2｜起始下标闸：域外拒绝且不触碰数组 / Start index gate: refuse without touching the array *)
IF (iStart < 0) OR (iStart >= DL_BAR_SIZE) THEN
    uErrorId := 16#0002_3055;    // 故障级：起始下标域外 / Fault: start index out of domain
    RETURN;
END_IF

(* 段 3｜段长闸：非负且段尾不越数组上界 / Length gate: non-negative and the tail inside bounds *)
IF (iLen < 0) OR ((iStart + iLen) > DL_BAR_SIZE) THEN
    uErrorId := 16#0002_3056;    // 故障级：段长域外 / Fault: length out of domain
    RETURN;
END_IF

(* 段 4｜恒等早退：空段或单元素无需交换 / Identity exit: nothing to swap *)
IF iLen <= 1 THEN
    uErrorId := 16#0002_3054;    // 信息级：恒等返回 / Info: identity return
    FC_DL_BitArrayReverse := TRUE;
    RETURN;
END_IF

(* 段 5｜双指针镜像交换：向中推进，交会即停 / Two-pointer mirror swap, stop at the meeting point *)
nLo := iStart;                   // 左指针从段首 / Left pointer at the head
nHi := iStart + iLen - 1;        // 右指针从段尾 / Right pointer at the tail
WHILE nLo < nHi DO
    bTmp        := aBits[nLo];   // 暂存左位 / Stage the left bit
    aBits[nLo]  := aBits[nHi];   // 左位取右位 / Left takes the right
    aBits[nHi]  := bTmp;         // 右位取暂存 / Right takes the staged
    nLo := nLo + 1;              // 左推进 / Advance left
    nHi := nHi - 1;              // 右回退 / Retreat right
    nSwapped := nSwapped + 1;    // 交换对计数 / Count the pair
END_WHILE

(* 段 6｜出口：码位单点写入 / Exit: single write point *)
uErrorId := uCode;               // 无事件，保持零 / No event, stays zero
FC_DL_BitArrayReverse := TRUE;
END_FUNCTION
