(*==============================================================================
 * 组件名称 (Component)  : FC_DL_Crc32Ethernet
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 SHR / XOR / AND 与显式类型转换，无厂商方言
 * 功能描述 (Function)   : 标准 CRC-32/ISO-HDLC 校验码计算，即以太网 FCS、ZIP、PNG
 *                         使用的同一参数模型：反射多项式 16#EDB88320（即 16#04C11DB7
 *                         的位反射形式）、初值 16#FFFF_FFFF、终值异或 16#FFFF_FFFF。
 *                         逐位（bit-wise）实现：每字节先与 CRC 寄存器低 8 位异或，
 *                         再循环 8 次"取最低位 → 右移一位 → 移出位为 1 则异或多项式"。
 *                         支持分块链式调用：大报文分批计算，中间块 bFinalXor := FALSE，
 *                         把上一次返回值作为下一块的 uCrcSeed，最后一块才置 TRUE。
 *                         用于固件包完整性校验、文件传输校验、EtherCAT/Profinet 诊断
 *                         帧签核、上位机与 PLC 之间的报文校验。
 *
 * 【多项式方向警示 / Polynomial direction warning（边界 B1）】
 *   必须用反射值 16#EDB88320 配右移。若用 16#04C11DB7 配左移，得到的是
 *   CRC-32/BZIP2（"123456789" 算出 16#FC891918），两者不可混搭——
 *   混搭多项式方向是 CRC 实现的第一大错，且错误结果毫无规律可排查。
 *
 * 【链式调用契约 / Chained-call contract】
 *   分块时前 n-1 块传 bFinalXor := FALSE，把返回值直接作为下一块的 uCrcSeed；
 *   最后一块 bFinalXor := TRUE。中间块若误置 TRUE，相当于整体多异或了一次
 *   终值，整包校验必失败且极难定位（边界 B4）。
 *   调用序列文字说明（伪流程，非代码）：
 *     第 1 块：种子 = 默认全 1，末块标志 = FALSE，返回值记为 R1
 *     第 2 块：种子 = R1，末块标志 = FALSE，返回值记为 R2
 *     ……依此接力……
 *     第 n 块（末块）：种子 = R(n-1)，末块标志 = TRUE，返回值即整包 CRC
 *   分块大小可任意切分（含单字节），链式结果与一次性整包计算逐位一致。
 *
 * 【字节序披露 / Byte-order disclosure（边界 B7）】
 *   本函数只算数值。以太网 FCS 上帧时按小端（低字节先发）填入帧尾，
 *   拆字节与摆放顺序由组帧方决定，与本函数无关。
 *
 * 【扫描周期披露 / Cycle-time disclosure（边界 B5）】
 *   256 字节 × 8 位 = 2048 次内层循环，属重计算。应放在慢任务或事件触发
 *   任务中调用，不要放进 1 ms 高速任务拖垮总线周期。
 *
 * 【验收向量 / Acceptance vectors（已实算复核，算法独立交叉验证）】
 *   V1（本轮强制验收向量）
 *      "123456789"（31 32 33 34 35 36 37 38 39）
 *      seed 16#FFFF_FFFF、bFinalXor = TRUE → 16#CBF4_3926
 *   V2  空输入（nLength = 0）+ 默认参数 → 16#0000_0000（正确值，非错误）
 *   V3  单字节 00 → 16#D202_EF8D
 *   V4  分块链式："1234"（bFinalXor = FALSE，返回 16#641C_1F5C 作种子）
 *       + "56789"（bFinalXor = TRUE）→ 16#CBF4_3926（与 V1 一致，验证链式语义）
 *   V5  nLength = 300 → 钳位为 256 继续计算，nBytesUsed = 256，uErrorId = 16#0001_0001
 *
 * 【首版范围 / Scope of v1.0.0（边界 B6）】
 *   仅实现逐位法：零 RAM 开销、行为在三家平台可预期。若现场需要提速，
 *   按扩产规则另立 256 项查表变体，本组件内不加模式开关（禁止巨无霸）。
 * 开源溯源 (Origin)     : 依 IEEE 802.3 与公开 CRC 目录（CRC-32/ISO-HDLC 参数模型）
 *                         独立实现。OSCAT Network 校验函数族仅提供"按协议分族、
 *                         独立成函数"的组织方式参考（EPL-2.0）；其实现采用地址
 *                         指针入参，本库改为数组引脚传参，未复制任何源码。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（显式 BYTE_TO_DWORD，无位访问方言）
 *                         R4 ✓ 长度钳位 + 下标双检 + 空输入兜底（空输入是合法值）
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
FUNCTION FC_DL_Crc32Ethernet : DWORD
VAR_IN_OUT
    aabyData   : ARRAY[0..255] OF BYTE;   // 待校验字节缓冲，定长 256，按 nLength 取前 N 字节 / Fixed 256-byte data buffer, first nLength bytes are used
END_VAR
VAR_INPUT
    nLength    : INT;                     // 本次参与计算的字节数，合法域 0..256，越界自动钳位 / Byte count this call, range 0..256, clamped
    uCrcSeed   : DWORD := 16#FFFF_FFFF;   // 初值或上一分块的返回值（链式调用），首块用默认值 / Initial value or previous chunk result for chaining
    bFinalXor  : BOOL  := TRUE;           // TRUE = 输出前异或 16#FFFF_FFFF，仅最后一块置 TRUE / Final XOR, TRUE on the last chunk only
END_VAR
VAR_OUTPUT
    uErrorId   : UDINT;                   // 故障码，0 = 无故障，16#0001_0001 = 长度越界已钳位 / Error code, 0 = no error, 0001_0001 = length clamped
    nBytesUsed : INT;                     // 实际参与计算的字节数（钳位后），供诊断 / Bytes actually processed after clamping
END_VAR
VAR
    uCrc       : DWORD;                   // CRC 工作寄存器 / CRC working register
    nLenWork   : INT;                     // 钳位后的本地长度副本，不回写输入引脚 / Local clamped copy of the length
    nI         : INT;                     // 字节循环索引，值域 0..255 / Byte loop index, range 0..255
    nBit       : INT;                     // 位循环索引，固定 8 次 / Bit loop index, fixed 8 iterations
    uByte      : DWORD;                   // 当前字节零扩展到 32 位 / Current byte zero-extended to 32 bits
    bLsbSet    : BOOL;                    // 右移前最低位状态 / LSB state captured before the shift
END_VAR
VAR CONSTANT
    DL_CRC32_POLY_REFLECTED : DWORD := 16#EDB8_8320;  // IEEE 802.3 多项式 16#04C11DB7 的位反射形式 / Bit-reflected IEEE 802.3 polynomial
    DL_CRC32_INIT           : DWORD := 16#FFFF_FFFF;  // 参数模型规定初值，全 1 / Mandated all-ones initial value
    DL_CRC32_XOROUT         : DWORD := 16#FFFF_FFFF;  // 终值异或值 / Final XOR value
    DL_CRC32_BUF_MAX        : INT   := 256;           // 缓冲上限，必须与数组维度一致 / Buffer limit, must match the array dimension
    DL_CRC32_BITS_PER_BYTE  : INT   := 8;             // 每字节位循环次数 / Bit iterations per byte
    DL_CRC32_BIT_MASK       : DWORD := 16#0000_0001;  // 最低位提取掩码 / LSB extraction mask
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值先落初值，故障码清零，长度取本地副本
 *      Safe preset: return value falls back to the seed, error code cleared
 *-----------------------------------------------------------------------------*)
FC_DL_Crc32Ethernet := uCrcSeed;
uErrorId            := 16#0000_0000;
nBytesUsed          := 0;
uCrc                := uCrcSeed;
nLenWork            := nLength;

(*------------------------------------------------------------------------------
 * 段 2｜长度防御（边界 B3/B5）：钳位而非拒绝，让诊断链拿到可比对的值
 *      Length defence: clamp instead of reject so diagnostics still get a value
 *      负值 → 0；大于 256 → 256；均置 16#0001_0001（瞬时码）
 *-----------------------------------------------------------------------------*)
IF nLenWork < 0 THEN
    nLenWork := 0;
    uErrorId := 16#0001_0001;
ELSIF nLenWork > DL_CRC32_BUF_MAX THEN
    nLenWork := DL_CRC32_BUF_MAX;
    uErrorId := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜逐字节、逐位计算（边界 B1）
 *      Byte-wise and bit-wise computation
 *      顺序硬约束：先与寄存器低 8 位异或 → 循环 8 次
 *      （先捕获最低位 → 右移 → 移出位为 1 则异或反射多项式）
 *      空输入（nLenWork = 0）跳过循环，返回值为终值异或后的 16#0000_0000，
 *      这是参数模型的正确结果而非错误（边界 B3）
 *-----------------------------------------------------------------------------*)
IF nLenWork > 0 THEN

    FOR nI := 0 TO (nLenWork - 1) DO

        (* 数组下标上下界双检（红线 R4）：nLenWork ≤ 256 已保证 nI ≤ 255 *)
        (* Array index double check: nLenWork ≤ 256 guarantees nI ≤ 255 *)
        IF nI < DL_CRC32_BUF_MAX THEN

            (* 显式 BYTE_TO_DWORD 零扩展，禁止隐式提升（红线 R3） *)
            (* Explicit BYTE_TO_DWORD zero extension, implicit promotion is forbidden *)
            uByte := BYTE_TO_DWORD(aabyData[nI]);
            uCrc  := uCrc XOR uByte;

            FOR nBit := 1 TO DL_CRC32_BITS_PER_BYTE DO
                (* 步骤 1：右移前先捕获最低位，顺序反了必然算错 *)
                (* Step 1: capture the LSB before shifting, reversing breaks the CRC *)
                bLsbSet := (uCrc AND DL_CRC32_BIT_MASK) <> 16#0000_0000;

                (* 步骤 2：逻辑右移一位，禁用除法取位（红线 R3） *)
                (* Step 2: logical shift right by one, division is forbidden *)
                uCrc := SHR(uCrc, 1);

                (* 步骤 3：若移出位为 1，异或反射多项式 *)
                (* Step 3: if the shifted-out bit was 1, XOR the reflected polynomial *)
                IF bLsbSet THEN
                    uCrc := uCrc XOR DL_CRC32_POLY_REFLECTED;
                END_IF
            END_FOR;

        END_IF

    END_FOR;

END_IF

(*------------------------------------------------------------------------------
 * 段 4｜终值与回写：仅最后一块做终值异或（链式契约见头注释）
 *      Final value and write-back: final XOR only on the last chunk
 *-----------------------------------------------------------------------------*)
IF bFinalXor THEN
    uCrc := uCrc XOR DL_CRC32_XOROUT;
END_IF

nBytesUsed          := nLenWork;
FC_DL_Crc32Ethernet := uCrc;

(*------------------------------------------------------------------------------
 * 段 5｜自检断言说明（供单元测试与现场对拍，向量已实算复核）
 *      Self-check assertion notes for unit tests and on-site cross-checks
 *      V1  "123456789"，种子默认、末块标志 TRUE → 16#CBF4_3926
 *      V2  空输入（长度 0），种子默认、末块标志 TRUE → 16#0000_0000
 *      V3  单字节 00，种子默认、末块标志 TRUE → 16#D202_EF8D
 *      V4  "1234"（末块标志 FALSE，返回 16#641C_1F5C 作种子）
 *          + "56789"（末块标志 TRUE）→ 16#CBF4_3926，与 V1 逐位一致
 *      V5  长度传 300 → 钳位为 256 继续计算，本函数输出 16#0001_0001
 *          且 nBytesUsed = 256，返回值为前 256 字节的校验值
 *-----------------------------------------------------------------------------*)
END_FUNCTION
