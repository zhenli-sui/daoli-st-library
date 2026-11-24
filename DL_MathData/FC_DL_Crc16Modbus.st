(*==============================================================================
 * 组件名称 (Component)  : FC_DL_Crc16Modbus
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 SHR / XOR / AND，无厂商方言、无查表常量数组
 * 功能描述 (Function)   : 标准 Modbus RTU CRC-16 校验计算。
 *                         参数：反射多项式 0xA001（即 0x8005 的位反转形式）、
 *                         初值 0xFFFF、输入输出反射（LSB first）、结果无异或。
 *                         逐位计算法：每字节先与 CRC 低字节异或，再循环 8 次
 *                         "取最低位 → 右移一位 → 若移出位为 1 则异或多项式"。
 *                         使用 SHR 而非除以 2，规避不同平台整数除法语义差异。
 * 算法     (Algorithm)  : 禁用除法取 LSB（B4），禁用点号位访问方言（B4），
 *                         必须先取最低位再右移（B5，顺序写反是最常见实现错误）。
 *
 * 【验收向量 / Acceptance vectors（已实算复核）】
 *   V1（本轮强制验收向量）
 *      帧  : 01 03 00 00 00 02
 *      CRC 寄存器值 = 16#0BC4，拼帧时按低字节先发：C4 0B
 *   V2  帧 01 03 00 00 00 0A  → 16#CDC5（发 C5 CD）
 *   V3  帧 11 03 00 6B 00 03  → 16#8776（发 76 87）
 *   V4  单字节 0x0C          → 16#45BF（发 BF 45）
 *
 * 【对 ROUND_PLAN §2.14 B7 的一处勘误 / Erratum】
 *   ROUND_PLAN 原文给出的单字节向量"0x0C → 0x911E"无法复现：按 Modbus 参数
 *   （初值 0xFFFF、反射多项式 0xA001）穷举 0..255 全部单字节输入，无任何取值
 *   得到 0x911E，故该值应源自其它多项式或其它初值的变体。本实现采用实算复核过的
 *   V4（0x0C → 0x45BF）替代，避免把错误向量写进单测造成"算法正确但测试失败"。
 *
 * 【返回字节序 / Byte order（B8）】
 *   函数返回的是 CRC 寄存器值（高字节在前语义）。拼帧时必须自行拆分：
 *     uCrc  := FC_DL_Crc16Modbus(abyData := aFrame, uByteCount := nLen);
 *     aFrame[nLen]     := WORD_TO_BYTE(uCrc AND 16#00FF);         「低字节先发」
 *     aFrame[nLen + 1] := WORD_TO_BYTE(SHR(uCrc, 8) AND 16#00FF); 「高字节后发」
 *
 * 【首版范围 / Scope of v1.0.0】
 *   仅实现逐位法，不含 256 项查表法：常量数组的跨平台初始化行为尚未验证，
 *   逐位法只有移位与异或两条语句，行为在三家平台上可预期。查表法列入 ROADMAP。
 * 开源溯源 (Origin)     : 原创实现。CRC-16/MODBUS 参数集见 Modbus over Serial Line
 *                         Specification V1.02 与公开 CRC 目录（Polynomial 0x8005 反射）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无除法取位、无点号位访问、显式 BYTE_TO_WORD）
 *                         R4 ✓ 长度为零/超限钳位 + 循环边界 + 位判断时序 + 下标校验
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *   2026-11-15  v1.0.1  R9 全库审计修复：头注释示例代码内嵌注释定界符改为引号形式，
 *                       消除"注释不可嵌套"平台上的提前闭合风险（算法与接口零变更）
 *============================================================================*)
FUNCTION FC_DL_Crc16Modbus : WORD
VAR_IN_OUT
    abyData : ARRAY[0..255] OF BYTE;   // 报文缓冲区，定长 256 字节，按 uByteCount 取前 N 字节 / Fixed 256-byte frame buffer, first N bytes are used
END_VAR
VAR_INPUT
    uByteCount : UINT := 0;            // 参与校验的字节数，合法域 1..256 / Number of bytes to checksum, valid range 1..256
END_VAR
VAR_OUTPUT
    bValid     : BOOL;                 // 长度合法标志，FALSE 表示已钳位或为零 / Length valid flag, FALSE means clamped or zero
    uErrorId   : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uCrc       : WORD;                 // CRC 寄存器，计算过程值 / CRC register, running value
    uCount     : UINT;                 // 钳位后的参与字节数 / Clamped byte count actually processed
    nIdx       : UINT;                 // 字节循环索引，值域 0..255 / Byte loop index, range 0..255
    nBit       : USINT;                // 位循环索引，固定 0..7 / Bit loop index, fixed 0..7
    bLsbSet    : BOOL;                 // 移位前最低位状态 / LSB state captured before the shift
END_VAR
VAR CONSTANT
    DL_CRC16_POLY   : WORD := 16#A001;   // 反射多项式 0x8005 / Reflected polynomial 0x8005
    DL_CRC16_INIT   : WORD := 16#FFFF;   // Modbus 规定初值 / Modbus mandated initial value
    DL_CRC16_MAXLEN : UINT := 256;       // 最大字节数，必须与数组维度一致 / Max byte count, must match the array dimension
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值先落到初值，异常路径下不得返回 0
 *      Safe preset: return falls back to the initial value, never to 0 on error paths
 *      0 在数学上是一个合法的 CRC 结果，返回它会让上层把"没算"误判成"算对了"
 *-----------------------------------------------------------------------------*)
FC_DL_Crc16Modbus := DL_CRC16_INIT;
bValid            := TRUE;
uErrorId          := 16#0000_0000;
uCrc              := DL_CRC16_INIT;
uCount            := uByteCount;

(*------------------------------------------------------------------------------
 * 段 2｜长度防御（边界 B1/B2）
 *      Length defence (boundaries B1/B2)
 *      零长度：返回初值 + 告警，直接退出（无字节可算）
 *      超限：钳到 256 后继续计算——现场排错时需要拿到一个可比对的值，
 *            中断会让诊断链断在第一步
 *-----------------------------------------------------------------------------*)
IF uByteCount = 0 THEN
    bValid   := FALSE;
    uErrorId := 16#0001_0001;
    RETURN;
ELSIF uByteCount > DL_CRC16_MAXLEN THEN
    uCount   := DL_CRC16_MAXLEN;
    bValid   := FALSE;
    uErrorId := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜逐字节、逐位计算（边界 B3/B4/B5/B6）
 *      Byte-wise and bit-wise computation
 *      外层：uCount ≥ 1 已由段 2 保证，故 uCount - 1 不会下溢
 *      内层：固定 8 次，无动态步长、无 BY -1
 *      顺序硬约束：先取最低位 → 再右移 → 最后按标志异或
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (uCount - 1) DO

    (* 数组下标上下界双检（红线 R4）：uCount ≤ 256 已保证 nIdx ≤ 255 *)
    (* Array index double check: uCount ≤ 256 guarantees nIdx ≤ 255 *)
    IF nIdx < DL_CRC16_MAXLEN THEN

        (* 显式 BYTE_TO_WORD 转换，禁止隐式提升（红线 R3） *)
        (* Explicit BYTE_TO_WORD conversion, implicit promotion is forbidden *)
        uCrc := uCrc XOR BYTE_TO_WORD(abyData[nIdx]);

        FOR nBit := 0 TO 7 DO
            (* 步骤 1：移位前先捕获最低位（边界 B5，顺序反了必然算错） *)
            (* Step 1: capture the LSB before shifting, reversing the order breaks the CRC *)
            bLsbSet := (uCrc AND 16#0001) <> 16#0000;

            (* 步骤 2：逻辑右移一位，禁用 / 2（边界 B4） *)
            (* Step 2: logical shift right by one, division by 2 is forbidden *)
            uCrc := SHR(uCrc, 1);

            (* 步骤 3：若移出位为 1，异或反射多项式 *)
            (* Step 3: if the shifted-out bit was 1, XOR the reflected polynomial *)
            IF bLsbSet THEN
                uCrc := uCrc XOR DL_CRC16_POLY;
            END_IF
        END_FOR;

    END_IF

END_FOR;

(*------------------------------------------------------------------------------
 * 段 4｜结果回写（边界 B8）：返回寄存器值，拆字节由调用方按低字节先发执行
 *      Result write-back: the register value is returned, byte splitting is the caller's job
 *-----------------------------------------------------------------------------*)
FC_DL_Crc16Modbus := uCrc;
END_FUNCTION
