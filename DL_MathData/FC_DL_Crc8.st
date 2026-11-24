(*==============================================================================
 * 组件名称 (Component)  : FC_DL_Crc8
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 参数化 8 位 CRC 校验
 *                         lgf-datahandling / oscat-network / crc8
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 SHL / XOR / AND
 *                         与显式枚举比较，不含查表常量数组，无实例依赖
 * 功能一句话 (Summary)  : 参数化 MSB-first 的 CRC-8 逐位算法，覆盖 ATM、SAE-J1850、
 *                         HITAG 三个变体，补齐本库 CRC 族的 8 位宽度。
 * 功能描述 (Function)   : 逐位算法，无查表、无状态、内存占用恒定。每个字节先与 CRC
 *                         寄存器异或，再做 8 次「看最高位、左移一位、条件异或多项式」，
 *                         全部字节处理完后与终值异或。三个变体只差多项式、初值、终值
 *                         三个参数，算法主体完全共用。典型现场用途：SMBus 与多数
 *                         传感器帧的 8 位校验、汽车与部分变频器状态帧的 SAE-J1850
 *                         校验、HITAG 类标签读写的同族变体、以及自定义短帧协议里
 *                         「厂家只给多项式、不给算法」时的快速对齐。
 * 与既有件边界 (Boundary): FC_DL_Crc16Modbus 做 16 位反射型、FC_DL_Crc32Ethernet 做
 *                         32 位、FC_DL_LrcChecksum 做纵向加和。本件只做 8 位且只做
 *                         MSB-first。反射型 8 位变体（多项式 16#31 的 MAXIM-DOW 一族）
 *                         位序相反，是另一套算法族，强行并入同一枚举会让「变体」概念
 *                         失真，故本件明确不立，留作后续独立件。
 * 三个变体参数表        :
 *   eCrc8Atm       多项式 16#07 初值 16#00 终值 16#00  典型 SMBus 与传感器帧
 *   eCrc8SaeJ1850  多项式 16#1D 初值 16#FF 终值 16#FF  典型汽车与变频器状态帧
 *   eCrc8Hitag     多项式 16#1D 初值 16#FF 终值 16#00  同族不同终值约定
 * 枚举映射表 (R31)      : eCrc8Atm 对应第 1 分支 ｜ eCrc8SaeJ1850 对应第 2 分支 ｜
 *                         eCrc8Hitag 对应第 3 分支 ｜ 其余脏值走兜底分支并回退 ATM。
 *                         三个合理值各有且仅有一个分支，兜底分支只接脏值。
 * 设计要点 (Key notes)  : ① 截断必须显式：入参长度超上限时先把截断标志置真，再把
 *                           实际参与长度改成上限，绝不静默按上限算却报「完整」；
 *                         ② 变体非法时回退到 ATM 而不是返回零：算一个可复算的值
 *                           便于现场与厂家的校验工具对表；
 *                         ③ 长度非法（小于 1）时直接返回零并置故障码，不进入循环；
 *                         ④ 纯函数：无内部状态、无跨周期残留，同入参同结果。
 *
 * 【验收向量 / Acceptance vectors（已按公开目录实算复核）】
 *   V1  ATM 标准串 9 字节（字符 1 到 9）→ 16#F4
 *   V2  SAE-J1850 同一串 → 16#4B
 *   V3  HITAG 同一串 → 16#B4
 *   V4  V-B 上限截断（R37 主向量）：nLen=200 → nProcessed=128、bTruncated=真、
 *       码 0141；不得静默按 128 算却报完整
 *   V5  V-A 域外：nLen=0 → 返回 16#00、码 0221、nProcessed=0、bTruncated=假
 *   V6  变体填 9（非法）→ 按 ATM 参数计算并置 0142，结果与 V1 相同
 *
 * 开源溯源 (Origin)     : 来源标签 lgf-datahandling 与 oscat-network。前者为免费闭源
 *                         发布的公开函数库手册，本件仅借鉴其数据处理组「校验按位宽
 *                         独立成族、CRC 家族参数化」的粒度事实；后者为 EPL-2.0 公开
 *                         库，本件仅借鉴「校验与诊断独立成族」的分类方式，未读取其
 *                         函数体。三个变体的多项式、初值、终值取自公开 CRC 参数目录
 *                         与各协议的公开规范，属公开常数。本件零代码行、零注释、
 *                         零数据结构引用，clean-room 独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 信息 16#0001_0141 长度已截断 ｜ 16#0001_0142 变体已回退
 *                         故障 16#0001_0221 长度非法。取号见本轮规格 §3.2。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 SHL / XOR / AND。
 * 镜像量清单 (R38)      : 本件无锁存副本，循环上界 nCount 由入口 nLen 一次导出后不再
 *                         读取入参，不存在锁存量与实时量混用面。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址直写
 *                         纯 IEC 61131-3 ｜ 无除法故无除零面 ｜ 循环上界全常量化
 *                         全变量与枚举项双语同行注释 ｜ 状态机 N/A（纯函数）
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 B CRC8 子族开族）
 *============================================================================*)

(*==============================================================================
 * 逐位算法推演 (Bitwise algorithm walk-through)：
 *   设寄存器初值 16#00、多项式 16#07，输入单字节 16#00
 *   第 1 步 寄存器异或字节后仍为 16#00
 *   第 2 步 连续 8 次「最高位为 0 则仅左移」，寄存器始终为 16#00
 *   终值与 16#00 异或后返回 16#00
 *   若输入为 16#80：异或后寄存器为 16#80，最高位为 1
 *   第 1 次移位得 16#00 再异或 16#07 得 16#07，其后 7 次移位按最高位判断继续推进
 *   可见「先判最高位、再移位、最后条件异或」的顺序不可颠倒，写反会得到另一族的
 *   校验值，且现象是「校验总是差一位固定值」，极难在总线上查出
 *============================================================================*)

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   uCrc := FC_DL_Crc8(
 *              aData      := aFrame,
 *              nLen       := nLen,
 *              eVar       := E_DL_Crc8Variant.eCrc8Atm,
 *              nProcessed => nUsed,
 *              bTruncated => bCut,
 *              uErrorId   => uCode);
 *   提示：bCut 为真时说明帧长超出本件上限，校验值只覆盖前 128 字节，
 *         此时不得把它当作整帧校验结果使用。
 *============================================================================*)

TYPE E_DL_Crc8Variant :
(
    eCrc8Atm      := 0,  // SMBus 与多数传感器帧，多项式 16#07 初值 16#00 终值 16#00 / SMBus and most sensor frames
    eCrc8SaeJ1850 := 1,  // 汽车与部分变频器状态帧，多项式 16#1D 初值 16#FF 终值 16#FF / SAE J1850 flavour
    eCrc8Hitag    := 2   // 同族的另一终值约定，多项式 16#1D 初值 16#FF 终值 16#00 / HITAG flavour
);
END_TYPE

FUNCTION FC_DL_Crc8 : BYTE
VAR_INPUT
    aData : ARRAY[1..128] OF BYTE;                              // 数据缓冲区 [字节]，定长 128，未用位置填 0 / Data buffer, fixed 128 bytes, unused slots zeroed
    nLen  : INT;                                               // 有效字节数 [个]，域 1 到 128，超上限按截断规则处理 / Valid byte count, 1 to 128, truncated above the limit
    eVar  : E_DL_Crc8Variant := E_DL_Crc8Variant.eCrc8Atm;     // 变体选择 [枚举]，默认 ATM / Variant selector, ATM by default
END_VAR
VAR_OUTPUT
    nProcessed : INT;                                          // 实际参与计算的字节数 [个]，域 0 到 128 / Bytes actually processed, 0 to 128
    bTruncated : BOOL;                                         // 入参超上限被截断，截断发生时必须显式置真 / Set true explicitly whenever truncation happened
    uErrorId   : UDINT;                                        // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    uCrc    : BYTE;      // CRC 寄存器，逐位推进的运行值 [字节] / CRC register, the running value
    uPoly   : BYTE;      // 本次生效的多项式 [字节] / Effective polynomial
    uInit   : BYTE;      // 本次生效的初值 [字节] / Effective initial value
    uXorOut : BYTE;      // 本次生效的终值异或量 [字节] / Effective final xor value
    uByte   : BYTE;      // 当前处理字节快照 [字节] / Snapshot of the byte under processing
    nCount  : INT;       // 钳位后实际参与计算的字节数 [个] / Clamped byte count to process
    nI      : INT;       // 字节循环下标 [索引]，域 1 到 128 / Byte loop index, 1 to 128
    nBit    : INT;       // 位循环下标 [索引]，固定 1 到 8 / Bit loop index, fixed 1 to 8
    bMsb    : BOOL;      // 移位前最高位状态 [布尔] / Most significant bit state before the shift
    uCode   : UDINT;     // 码位暂存，出口单点写入 [码] / Code staging, written once at the exit
END_VAR
VAR CONSTANT
    DL_CRC8_MAXLEN : INT := 128;            // 定长上限 [字节]，与形参维度一致，避免大数组进栈 / Fixed upper bound matching the dimension
    DL_CRC8_BITS   : INT := 8;              // 每字节位循环次数 [次] / Bit iterations per byte
    DL_CRC8_MSB    : BYTE := 16#80;         // 最高位掩码 [位串] / Most significant bit mask
    DL_CRC8_MASK8  : BYTE := 16#FF;         // 八位满掩码，移位后裁掉溢出位 [位串] / Eight bit mask to drop the shifted out bit
    DL_CRC8_POLY_ATM : BYTE := 16#07;       // ATM 多项式 [字节] / ATM polynomial
    DL_CRC8_POLY_J1850 : BYTE := 16#1D;     // SAE-J1850 与 HITAG 多项式 [字节] / SAE J1850 and HITAG polynomial
    DL_CRC8_INIT_ATM : BYTE := 16#00;       // ATM 初值 [字节] / ATM initial value
    DL_CRC8_INIT_J1850 : BYTE := 16#FF;     // SAE-J1850 与 HITAG 初值 [字节] / SAE J1850 and HITAG initial value
    DL_CRC8_XOR_J1850 : BYTE := 16#FF;      // SAE-J1850 终值 [字节] / SAE J1850 final xor
    DL_CRC8_XOR_NONE : BYTE := 16#00;       // 无终值异或 [字节] / No final xor
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值落零，截断标志落假，码位落零
 *      Safe preset: zero return, truncation flag false, code cleared
 *      截断标志的初值必须是假，否则「恒真」与「从不置真」两种错误无法区分
 *      The flag starts false so that a stuck true and a never set true are distinguishable
 *-----------------------------------------------------------------------------*)
FC_DL_Crc8  := 16#00;
nProcessed  := 0;
bTruncated  := FALSE;
uErrorId    := 16#0000_0000;
uCode       := 16#0000_0000;
uCrc        := 16#00;
nCount      := 0;

(*------------------------------------------------------------------------------
 * 段 2｜长度闸门（边界 B1/B2）：小于 1 早退，大于上限先置截断标志再钳位
 *      Length gate: below one exits early, above the limit flags first then clamps
 *      顺序硬约束：先置标志、后改长度。反过来的写法会出现「已经按 128 算完、
 *      却因为标志被后面的赋值覆盖而报完整」的静默失真
 *      Order matters: flag first, then clamp, the reverse silently loses the evidence
 *-----------------------------------------------------------------------------*)
IF nLen < 1 THEN
    uErrorId := 16#0001_0221;   // 故障级：长度非法，返回零且不进入循环
    RETURN;
ELSIF nLen > DL_CRC8_MAXLEN THEN
    bTruncated := TRUE;         // 截断发生，先置标志
    nCount     := DL_CRC8_MAXLEN;
    uCode      := 16#0001_0141; // 信息级：已截断，实际只算前 128 字节
ELSE
    nCount := nLen;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜变体参数装载（边界 B3）：三个合法值逐一比较，脏值回退 ATM
 *      Variant parameter load: three legal values compared one by one, dirty falls back to ATM
 *      用等值列举而非区间判断：枚举底层是整数，区间判断会放过将来新增的成员
 *      Equality enumeration instead of a range test, a range would accept future members
 *-----------------------------------------------------------------------------*)
IF eVar = E_DL_Crc8Variant.eCrc8Atm THEN
    uPoly   := DL_CRC8_POLY_ATM;
    uInit   := DL_CRC8_INIT_ATM;
    uXorOut := DL_CRC8_XOR_NONE;
ELSIF eVar = E_DL_Crc8Variant.eCrc8SaeJ1850 THEN
    uPoly   := DL_CRC8_POLY_J1850;
    uInit   := DL_CRC8_INIT_J1850;
    uXorOut := DL_CRC8_XOR_J1850;
ELSIF eVar = E_DL_Crc8Variant.eCrc8Hitag THEN
    uPoly   := DL_CRC8_POLY_J1850;
    uInit   := DL_CRC8_INIT_J1850;
    uXorOut := DL_CRC8_XOR_NONE;
ELSE
    (* 兜底分支只接脏值：回退 ATM 参数并报信息级码，仍给出可复算的校验值 *)
    (* The fallback branch only sees dirty values, it falls back to ATM and reports *)
    uPoly   := DL_CRC8_POLY_ATM;
    uInit   := DL_CRC8_INIT_ATM;
    uXorOut := DL_CRC8_XOR_NONE;
    IF uCode = 16#0000_0000 THEN
        uCode := 16#0001_0142;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜逐字节、逐位计算（边界 B4/B5/B6）
 *      Byte-wise and bit-wise computation
 *      外层：nCount 已在段 2 保证 1 到 128，循环必执行且下标不越界
 *      内层：固定 8 次，顺序为「先取最高位、再左移、最后条件异或」
 *      移位后与满掩码相与，显式丢弃移出位，不依赖平台对 BYTE 移位的截断行为
 *-----------------------------------------------------------------------------*)
uCrc := uInit;

FOR nI := 1 TO nCount DO

    (* 写前下标双检，与形参维度 1 到 128 对齐 / Index double check against the declared dimension *)
    IF (nI >= 1) AND (nI <= DL_CRC8_MAXLEN) THEN

        uByte := aData[nI];
        uCrc  := uCrc XOR uByte;

        FOR nBit := 1 TO DL_CRC8_BITS DO
            bMsb := (uCrc AND DL_CRC8_MSB) <> 16#00;   // 步骤 1 移位前先捕获最高位
            uCrc := SHL(uCrc, 1) AND DL_CRC8_MASK8;    // 步骤 2 左移一位并裁掉溢出位
            IF bMsb THEN
                uCrc := uCrc XOR uPoly;               // 步骤 3 最高位为 1 时异或多项式
            END_IF
        END_FOR;

    END_IF

END_FOR;

(*------------------------------------------------------------------------------
 * 段 5｜终值异或与出口收口（边界 B7）
 *      Final xor and close out
 *-----------------------------------------------------------------------------*)
uCrc         := uCrc XOR uXorOut;
FC_DL_Crc8   := uCrc;
nProcessed   := nCount;
uErrorId     := uCode;      // 码位单点写入，全拍只写一次 / Single write point for the code
END_FUNCTION
