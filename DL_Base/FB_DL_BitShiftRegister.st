(*
    FB_DL_BitShiftRegister —— 宽度可组态的位串移位寄存器
    ------------------------------------------------------------------
    分类      : DL_Base / BitString
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : T2-1 LGF Bit Logic（只借「位串批量操作归 Bit Logic 组」的分类事实；
                矩阵本行「单点 / 单段 / 批量段」三层已齐备，本件补的是时序层：位串随
                节拍推进）；掩码构造、超宽截断、清空优先序、错误分级与码位 100% 自有；
                T0-7 位串移位闸门纪律（R48）复用：移位量必须结构性小于位宽；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 输送线工件跟踪的经典做法——每个工位到位脉冲把 bShiftIn 从一端移入一位，
                另一端溢出位即「出料口有料」。每次 bShift 上升沿只移一位。
                核心防御：① uWidth 不在 1~32 即故障级 032A 且绝不索引任何位、寄存器清零；
                ② 掩码构造在宽度 32 时走常量 DL_SR_MASK32，禁 SHL(x, 32)（跨平台未定义）；
                ③ 溢出位提取在宽度 32 时走常量 16#8000_0000；
                ④ 每拍移位后 uReg 与掩码相与截断——旧位残留在高位会造成假置位，
                   这是本件最易漏的缺陷；
                ⑤ bClearAll 与 bShift 同拍时清空优先（安全侧：宁可丢一位不可留脏位）；
                ⑥ 移位计数饱和即置 032B，寄存器本体仍正常工作，但统计量不可信；
                ⑦ 溢出位提取跟随移位方向：左移溢出最高有效位（uInMask），右移溢出 bit0——
                   v1.0.0 恒用 uInMask 提取，右移方向报错溢出位（v1.0.1 修正）。
                职责边界：循环旋转（不丢位）归 BitArrayRotate，段搬运归 BitSegmentBlockMove；
                本件只提供「逐拍移位 + 溢出位」语义。
    错误码    : 16#0001_0408 同拍 bClearAll 与 bShift，已按清空优先——信息级，正常防御
                16#0001_0409 预留禁用（信息级，不得挪用）
                16#0001_032A 位宽非法（uWidth 不在 1~32）——故障级，寄存器清零且不索引任何位
                16#0001_032B 移位计数达饱和值，统计量已不可信（寄存器本体仍正常）——故障级，继续移位
                16#0001_032C 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0408 用 / 16#0001_0409 预留 ｜ 16#0001_032A 用 / 16#0001_032B 用 / 16#0001_032C 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
                （bShiftOut 是单周期脉冲量、uReg 是保持量，不存在顺序态）
    采样约定  : fbTrigShift / fbTrigReset 在本体首部无条件刷新，绝不放入 IF 或 CASE；
                bShiftOut 每拍先清后置，故为单周期脉冲；移位节拍由调用方的 bShift 沿决定。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
                2026-11-16 v1.0.1 终审修正：溢出位提取改为跟随移位方向（右移取 bit0），
                v1.0.0 在 bDirLeft=FALSE 时误用最高有效位掩码，bShiftOut 输出错误（R19 终审）
*)
FUNCTION_BLOCK FB_DL_BitShiftRegister
VAR_INPUT
    bEnable     : BOOL;                       // 使能，FALSE 冻结寄存器并清输出脉冲 / enable, FALSE freezes the register and clears the pulse
    bReset      : BOOL;                       // 复位，上升沿把寄存器与计数清零 / reset, rising edge clears the register and the counter
    bShift      : BOOL;                       // 移位请求，上升沿有效，一拍只移一位 / shift request, rising edge valid, one bit per cycle
    bShiftIn    : BOOL := FALSE;              // 移入位，TRUE = 置位 / bit shifted in, TRUE sets it
    uWidth      : UINT := 16;                 // 有效位宽 [bit]，范围 1~32 / effective width [bit], range 1~32
    bClearAll   : BOOL := FALSE;              // 整寄存器清零，优先于 bShift，同拍清空 / clear the whole register, takes priority over bShift
    bDirLeft    : BOOL := TRUE;               // TRUE = 向高位方向移（bit0 → bit(n-1)）/ TRUE shifts towards the higher bits
END_VAR
VAR_OUTPUT
    uReg        : DWORD;                      // 寄存器镜像，bit0 = 最旧位 / register mirror, bit0 is the oldest bit
    bShiftOut   : BOOL;                       // 本拍溢出位，单周期脉冲 / overflow bit of this cycle, single-cycle pulse
    bAnySet     : BOOL;                       // 任一位为 1 / any bit set
    uSetCount   : UINT;                       // 置位总数 [个]，范围 0~32 / number of set bits [count], range 0~32
    uShiftCnt   : UDINT;                      // 累计移位次数，饱和计数 [次] / accumulated shift count, saturating [times]
    eErr        : UDINT;                      // 错误码，0=正常 / error id, 0=ok
    bError      : BOOL;                       // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigShift : R_TRIG;                     // 移位上升沿实例，本体首部无条件刷新 / shift edge instance, refreshed unconditionally
    fbTrigReset : R_TRIG;                     // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    uWidthEff   : UINT;                       // 生效位宽，闸门通过后使用 [bit] / effective width after the gate [bit]
    uMask       : DWORD;                      // 有效宽度掩码 [位图] / mask of the effective width [bitmap]
    uInMask     : DWORD;                      // 移入位置掩码（最高有效位）[位图] / mask of the insertion position, most significant effective bit [bitmap]
    bOutBit     : BOOL;                       // 本拍溢出位中间量 / overflow bit intermediate
    uIdx        : UINT;                       // 位计数游标 [位]，范围 0~31 / bit counting cursor [bit], range 0~31
END_VAR
VAR CONSTANT
    DL_SR_WIDTH_MIN : UINT := 1;              // 位宽下限 [bit] / width lower bound [bit]
    DL_SR_WIDTH_MAX : UINT := 32;             // 位宽上限 [bit] / width upper bound [bit]
    DL_SR_LAST_BIT  : UINT := 31;             // 最高位号 [位] / the highest bit index [bit]
    DL_SR_CNT_MAX   : UDINT := 16#FFFF_FFFE;  // 计数饱和值 [次] / counter saturation value [times]
    DL_SR_MASK32    : DWORD := 16#FFFF_FFFF;  // 全宽掩码，宽度 32 时使用 [位图] / full width mask used at width 32 [bitmap]
    DL_SR_BIT31     : DWORD := 16#8000_0000;  // 最高位掩码，宽度 32 时提取溢出位 [位图] / top bit mask for the overflow extract at width 32 [bitmap]
    DL_SR_BIT0      : DWORD := 16#0001;       // 最低位掩码 [位图] / least significant bit mask [bitmap]
    DL_SR_ZERO      : DWORD := 16#0000;       // 零值常量，避免裸字面量 [位图] / zero constant, avoids a bare literal [bitmap]
    DL_SR_ONE       : DWORD := 16#0001;       // 一值常量，掩码减法用 [位图] / one constant used by the mask subtraction [bitmap]
    DL_SR_SHIFT_ONE : UINT := 1;              // 单步移位量与位宽步长 [bit] / single step shift amount and width step [bit]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigShift(CLK := bShift);
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置：脉冲量每拍先清 / segment 2, preset outputs and error status
bShiftOut := FALSE;                           // 单拍脉冲先清 / clear the single-cycle pulse first
bAnySet := FALSE;                             // 占位清零，段 7 重算 / clear, recomputed in segment 7
uSetCount := 0;                               // 置位计数先清 / clear the set-bit counter
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault

// 段 3｜使能闸：失能冻结寄存器，仅清脉冲 / segment 3, enable gate freezes the register
IF NOT bEnable THEN
    bAnySet := (uReg AND DL_SR_MASK32) <> DL_SR_ZERO; // 冻结态仍如实镜像非零判定 / still mirror the non-zero test while frozen
    RETURN;                                   // 失能即出口 / disabled is the exit
END_IF

// 段 4｜位宽闸：越界即故障级，寄存器清零且绝不索引任何位 / segment 4, width gate
IF (uWidth < DL_SR_WIDTH_MIN) OR (uWidth > DL_SR_WIDTH_MAX) THEN
    eErr := 16#0001_032A;                     // 位宽非法故障码 / illegal width fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    uReg := DL_SR_ZERO;                       // 寄存器清零 / clear the register
    bShiftOut := FALSE;                       // 脉冲撤销 / drop the pulse
    bAnySet := FALSE;                         // 非零判定回 FALSE / non-zero test back to FALSE
    uSetCount := 0;                           // 置位计数回 0 / set-bit counter back to zero
    RETURN;                                   // 故障级提前返回，不触碰任何位 / early return, no bit is touched
END_IF

// 段 5｜掩码与移入位掩码构造（宽度 32 时走常量，禁 SHL(x, 32)）/ segment 5, mask construction
uWidthEff := uWidth;                          // 位宽已由段 4 保证在 1~32 / the width is guaranteed 1~32 by segment 4
IF uWidthEff >= DL_SR_WIDTH_MAX THEN
    uMask := DL_SR_MASK32;                    // 全宽掩码常量路径 / constant path for the full width
    uInMask := DL_SR_BIT31;                   // 最高位掩码常量路径 / constant path for the top bit
ELSE
    uMask := SHL(DL_SR_BIT0, uWidthEff) - DL_SR_ONE; // 2^n − 1，移位量 ≤ 31 结构性安全 / 2 to the n minus one, the shift never exceeds 31
    uInMask := SHL(DL_SR_BIT0, uWidthEff - DL_SR_SHIFT_ONE); // 最高有效位掩码，移位量 ≤ 31 / mask of the most significant effective bit
END_IF

// 段 6｜复位沿优先（清寄存器与计数）/ segment 6, reset edge has priority
IF fbTrigReset.Q THEN
    uReg := DL_SR_ZERO;                       // 寄存器清零 / clear the register
    uShiftCnt := 0;                           // 累计移位次数清零 / clear the accumulated shift count
END_IF

// 段 7｜清空优先于移位：安全侧宁可丢一位不可留脏位 / segment 7, clear has priority over shift
IF bClearAll THEN
    uReg := DL_SR_ZERO;                       // 整寄存器清零 / clear the whole register
    bShiftOut := FALSE;                       // 同拍不产生溢出位 / no overflow bit in the same cycle
    IF fbTrigShift.Q THEN
        eErr := 16#0001_0408;                 // 信息级：同拍清空与移位，已按清空优先 / info level, clearing wins in the same cycle
    END_IF
ELSIF fbTrigShift.Q THEN

    // 段 8｜提取溢出位（先取值再移位，顺序不可颠倒；溢出位跟随移位方向）/ segment 8, extract the overflow bit first, direction aware
    IF bDirLeft THEN
        bOutBit := (uReg AND uInMask) <> DL_SR_ZERO; // 左移：溢出位为最高有效位 / shifting left, the overflow bit is the most significant effective bit
    ELSE
        bOutBit := (uReg AND DL_SR_BIT0) <> DL_SR_ZERO; // 右移：溢出位为 bit0 / shifting right, the overflow bit is bit zero
    END_IF

    // 段 9｜移位并移入（移位量恒为 1，结构性小于位宽）/ segment 9, shift by one and insert
    IF bDirLeft THEN
        uReg := SHL(uReg, DL_SR_SHIFT_ONE);   // 向高位方向移一位，移位量 1 安全 / shift one position towards the higher bits
        IF bShiftIn THEN
            uReg := uReg OR DL_SR_BIT0;       // 低位端移入 / insert at the low end
        END_IF
    ELSE
        uReg := SHR(uReg, DL_SR_SHIFT_ONE);   // 向低位方向移一位 / shift one position towards the lower bits
        IF bShiftIn THEN
            uReg := uReg OR uInMask;          // 高位端移入 / insert at the high end
        END_IF
    END_IF

    // 段 10｜超宽截断：旧位残留在高位会造成假置位 / segment 10, truncate to the effective width
    uReg := uReg AND uMask;                   // 与有效掩码相与 / and with the effective mask
    bShiftOut := bOutBit;                     // 发布本拍溢出位 / publish the overflow bit

    // 段 11｜移位计数饱和（饱和即置码，绝不回绕）/ segment 11, saturating shift counter
    IF uShiftCnt < DL_SR_CNT_MAX THEN
        uShiftCnt := uShiftCnt + 1;           // 饱和加一 / saturating increment
    ELSE
        eErr := 16#0001_032B;                 // 故障级：统计量已不可信 / fault level, the statistics are no longer trustworthy
        bError := TRUE;                       // 置故障标志 / raise the error flag
    END_IF
END_IF

// 段 12｜置位统计（位宽已保证 ≤ 32，移位量 ≤ 31）/ segment 12, set-bit statistics
FOR uIdx := 0 TO uWidthEff - DL_SR_SHIFT_ONE DO
    IF (uReg AND SHL(DL_SR_BIT0, uIdx)) <> DL_SR_ZERO THEN
        uSetCount := uSetCount + 1;           // 逐位累加置位数 / accumulate the set bits one by one
    END_IF
END_FOR
bAnySet := uSetCount > 0;                     // 非零判定由计数导出，避免二次遍历 / derived from the count, no second pass
END_FUNCTION_BLOCK
