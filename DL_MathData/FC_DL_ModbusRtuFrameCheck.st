(*
    FC_DL_ModbusRtuFrameCheck —— Modbus RTU 帧一致性校验
    ------------------------------------------------------------------
    分类      : DL_MathData / Protocol
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : Modbus 应用协议规范的公开条款（RTU 帧结构、功能码、异常应答长度、
                广播语义）；本库 T1-3 只借「协议帧解析与校验独立成族」的分类事实；
                判定表组织、错误分级、枚举范围与码位 100% 自有；CRC 校验另有
                FC_DL_Crc16Modbus，本件不重算 CRC；clean-room 重写，未复制任何
                闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 对已收到的 RTU 帧做结构一致性校验，把「解析异常帧」补成「先验帧再解帧」。
                四路互校：① 总长与功能码声明长度是否匹配；② 字节数域与调用方声明的
                数量 uQty 是否自洽；③ 异常帧（功能码 bit7 = 1）长度必须恰为 5；
                ④ 广播地址 0 配读类功能码属站号组态错（只提示不阻断）。
                核心防御：① 长度闸先于任何数组索引，绝不越界读 auFrame；
                ② 异常帧直接走定长分支，不做字节数互校（异常帧无字节数域）；
                ③ 未纳入长度表的功能码只做长度域检查并置信息码，不猜、不阻断上层；
                ④ CASE 含 ELSE 兜底，平台越界写入的非法枚举值同样按未识别功能码处理。
                职责边界：CRC 归 FC_DL_Crc16Modbus，异常码语义归 FC_DL_ModbusExceptionParse。
    错误码    : 16#0001_040A 功能码未纳入长度校验表（eFcUnknown / 非法枚举），只做长度域检查——信息级，正常防御
                16#0001_040B 广播地址配读类功能码（疑似站号组态错，已放行）——信息级，正常防御
                16#0001_032D 帧长非法（< 4 或 > 256 字节），不索引缓冲区——故障级，返回 FALSE
                16#0001_032E 字节数域 / 帧长与声明的数量 uQty 不自洽——故障级，返回 FALSE
                16#0001_032F 异常帧（bit7 置位）长度不等于 5——故障级，返回 FALSE
    码位总账  : 16#0001_040A 用 / 16#0001_040B 用 ｜ 16#0001_032D 用 / 16#0001_032E 用 / 16#0001_032F 用
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
                （本件内部的 CASE 是功能码分派，不是顺序状态机，且含 ELSE 兜底）
    采样约定  : 本件无定时器、无沿检测；一帧一到即校验，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_ModbusFc —— Modbus 功能码（本文件为全库唯一属主）
    说明 : 只覆盖本件能判定长度的 8 个功能码（01/02/03/04/05/06/0F/10）；
           08 诊断、0B 等一律 eFcUnknown 交上层处理，本件不猜。
*)
TYPE E_DL_ModbusFc :
(
    eFcUnknown := 0,                          // 未纳入长度校验表的功能码 / function code outside the length table
    eFc01      := 1,                          // 读线圈（位读取）/ read coils, bit read
    eFc02      := 2,                          // 读离散输入（位读取）/ read discrete inputs, bit read
    eFc03      := 3,                          // 读保持寄存器（字读取）/ read holding registers, word read
    eFc04      := 4,                          // 读输入寄存器（字读取）/ read input registers, word read
    eFc05      := 5,                          // 写单个线圈（定长 8 字节）/ write single coil, fixed 8 bytes
    eFc06      := 6,                          // 写单个寄存器（定长 8 字节）/ write single register, fixed 8 bytes
    eFc0F      := 15,                         // 写多个线圈（请求含字节数域）/ write multiple coils, request carries a byte count field
    eFc10      := 16                          // 写多个寄存器（请求含字节数域）/ write multiple registers, request carries a byte count field
);
END_TYPE

FUNCTION FC_DL_ModbusRtuFrameCheck : BOOL
VAR_INPUT
    auFrame         : ARRAY[0..255] OF BYTE;  // 帧缓冲区，定长 256 字节 / frame buffer, fixed 256 bytes
    uLen            : UINT := 0;              // 实际收到长度 [字节]，范围 0~256 / received length [byte], range 0~256
    eFc             : E_DL_ModbusFc := eFcUnknown; // 调用方读到的功能码（低 7 位语义）/ function code read by the caller, low seven bits
    uQty            : UINT := 0;              // 调用方声明的寄存器数或线圈数 [个]，范围 0~125 / declared register or coil quantity [count], range 0~125
END_VAR
VAR_OUTPUT
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 校验结论是否可信（故障态 FALSE）/ conclusion trustworthy flag, FALSE on fault
    uByteCount      : UINT;                   // 帧内解析出的字节数域 [字节]，无该域的功能码回 0 / byte count field parsed from the frame [byte], zero when absent
    bIsException    : BOOL;                   // 该帧是异常应答帧 / the frame is an exception response
    bBroadcast      : BOOL;                   // 地址域为 0（广播）/ address field is zero, broadcast
END_VAR
VAR CONSTANT
    DL_RTU_MIN_LEN   : UINT := 4;             // 最短帧长度（地址 + 功能码 + CRC×2）[字节] / shortest frame, address plus function code plus two CRC bytes [byte]
    DL_RTU_MAX_LEN   : UINT := 256;           // 协议与缓冲区上限 [字节] / protocol and buffer upper bound [byte]
    DL_RTU_EXC_LEN   : UINT := 5;             // 异常应答帧定长 [字节] / fixed exception response length [byte]
    DL_RTU_FIX_LEN   : UINT := 8;             // 05/06 定长帧 [字节] / fixed frame length for 05 and 06 [byte]
    DL_RTU_QTY_FIX   : UINT := 1;             // 05/06 允许的数量值（恒为 1）[个] / allowed quantity for 05 and 06, always one [count]
    DL_RTU_WR_BASE   : UINT := 9;             // 0F/10 请求帧最小长度（含 1 字节字节数域）[字节] / minimum request length for 0F and 10 [byte]
    DL_RTU_LEN_BASE  : UINT := 5;             // 读类应答帧固定开销（地址 + 功能码 + 字节数 + CRC×2）[字节] / fixed read response overhead [byte]
    DL_RTU_FC_EXC_BIT : BYTE := 16#80;        // 异常帧标志位（功能码 bit7）/ exception flag bit in the function code [bit]
    DL_RTU_BYTE_ZERO : BYTE := 16#00;         // 字节零常量，避免裸字面量 / byte zero constant, avoids a bare literal
    DL_RTU_ADDR_BROADCAST : BYTE := 16#00;    // 广播地址值 / broadcast address value
    DL_RTU_IDX_ADDR  : UINT := 0;             // 地址域下标 [索引] / address field index [index]
    DL_RTU_IDX_FC    : UINT := 1;             // 功能码域下标 [索引] / function code field index [index]
    DL_RTU_IDX_CNT   : UINT := 2;             // 读类应答的字节数域下标 [索引] / byte count index of a read response [index]
    DL_RTU_IDX_WRCNT : UINT := 6;             // 写多请求的字节数域下标 [索引] / byte count index of a multiple write request [index]
    DL_RTU_BITS_PER_BYTE : UINT := 8;         // 每字节位数，位数量换算用 [bit/字节] / bits per byte, used by the bit quantity conversion [bit/byte]
    DL_RTU_WORD_BYTES : UINT := 2;            // 每寄存器字节数 [字节/个] / bytes per register [byte/count]
    DL_RTU_BIT_ROUND : UINT := 7;             // 位数量上取整加数 [无量纲] / rounding addend for the bit quantity [dimensionless]
    DL_RTU_ZERO      : UINT := 0;             // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_RTU_ONE       : UINT := 1;             // 一值常量，下界判定用 [无量纲] / one constant used by the lower bound test [dimensionless]
END_VAR
VAR
    uExpectLen      : UINT;                   // 期望帧长中间量 [字节] / expected frame length intermediate [byte]
    uExpectCnt      : UINT;                   // 期望字节数域中间量 [字节] / expected byte count intermediate [byte]
    bWriteFc        : BOOL;                   // 是否为写类功能码（05/06/0F/10）/ write class function code flag
    bReadFc         : BOOL;                   // 是否为读类功能码（01/02/03/04）/ read class function code flag
    bFrameOk        : BOOL;                   // 帧结构自洽结论中间量 / frame self-consistency conclusion intermediate
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_ModbusRtuFrameCheck := FALSE;           // 缺省判定不自洽 / default conclusion is not self-consistent
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置结论不可信，通过闸门后置位 / preset untrustworthy, set TRUE after the gates
uByteCount := DL_RTU_ZERO;                    // 字节数域先清零 / clear the byte count field
bIsException := FALSE;                        // 预置非异常帧 / preset not an exception frame
bBroadcast := FALSE;                          // 预置非广播 / preset not a broadcast
bFrameOk := FALSE;                            // 结论中间量清零 / clear the conclusion intermediate
bWriteFc := FALSE;                            // 写类标志清零 / clear the write class flag
bReadFc := FALSE;                             // 读类标志清零 / clear the read class flag

// 段 2｜长度闸（先判长度再索引数组，绝不越界）/ segment 2, length gate before any indexing
IF (uLen < DL_RTU_MIN_LEN) OR (uLen > DL_RTU_MAX_LEN) THEN
    eErr := 16#0001_032D;                     // 帧长非法故障码 / illegal frame length fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 结论不可信 / conclusion untrustworthy
    RETURN;                                   // 故障级提前返回，不索引缓冲区 / early return, the buffer is never indexed
END_IF

// 段 3｜地址域判定（长度已保证下标 0 合法）/ segment 3, address field evaluation
bBroadcast := auFrame[DL_RTU_IDX_ADDR] = DL_RTU_ADDR_BROADCAST; // 地址 0 即广播 / address zero means broadcast

// 段 4｜异常帧分支：长度必须恰为 5，且不再做字节数互校 / segment 4, exception branch
IF (auFrame[DL_RTU_IDX_FC] AND DL_RTU_FC_EXC_BIT) <> DL_RTU_BYTE_ZERO THEN
    bIsException := TRUE;                     // 标记异常应答帧 / flag the exception response
    IF uLen = DL_RTU_EXC_LEN THEN
        bValid := TRUE;                       // 异常帧定长合法，结论可信 / fixed length is legal, the conclusion is trustworthy
        FC_DL_ModbusRtuFrameCheck := TRUE;    // 帧结构自洽 / the frame is self-consistent
    ELSE
        eErr := 16#0001_032F;                 // 异常帧长度非法故障码 / illegal exception frame length fault id
        bError := TRUE;                       // 置故障标志 / raise the error flag
        bValid := FALSE;                      // 结论不可信 / conclusion untrustworthy
        FC_DL_ModbusRtuFrameCheck := FALSE;   // 明确判定不自洽 / conclude not self-consistent
    END_IF
    RETURN;                                   // 异常帧分支出口，无字节数域可校 / exception frames carry no byte count field
END_IF

// 段 5｜功能码分派（含 ELSE 兜底，非法枚举按未识别处理）/ segment 5, function code dispatch with ELSE fallback
CASE eFc OF
    eFc01, eFc02:
        bReadFc := TRUE;                      // 位读取类 / bit read class
        IF uQty < DL_RTU_ONE THEN
            eErr := 16#0001_032E;             // 数量为 0 与功能码语义矛盾 / a zero quantity contradicts the function code
            bError := TRUE;                   // 置故障标志 / raise the error flag
        ELSE
            uByteCount := auFrame[DL_RTU_IDX_CNT]; // 解析字节数域 / parse the byte count field
            uExpectCnt := (uQty + DL_RTU_BIT_ROUND) / DL_RTU_BITS_PER_BYTE; // 位数量上取整为字节数，整数式禁浮点 / round the bit quantity up to bytes with integer arithmetic
            uExpectLen := DL_RTU_LEN_BASE + uExpectCnt; // 应答帧期望长度 / expected response length
            IF (uByteCount = uExpectCnt) AND (uLen = uExpectLen) THEN
                bFrameOk := TRUE;             // 字节数域与帧长双向自洽 / both the byte count and the length agree
            ELSE
                eErr := 16#0001_032E;         // 字节数域或帧长不自洽 / byte count or length mismatch
                bError := TRUE;               // 置故障标志 / raise the error flag
            END_IF
        END_IF

    eFc03, eFc04:
        bReadFc := TRUE;                      // 字读取类 / word read class
        IF uQty < DL_RTU_ONE THEN
            eErr := 16#0001_032E;             // 数量为 0 与功能码语义矛盾 / a zero quantity contradicts the function code
            bError := TRUE;                   // 置故障标志 / raise the error flag
        ELSE
            uByteCount := auFrame[DL_RTU_IDX_CNT]; // 解析字节数域 / parse the byte count field
            uExpectCnt := uQty * DL_RTU_WORD_BYTES; // 每寄存器 2 字节 / two bytes per register
            uExpectLen := DL_RTU_LEN_BASE + uExpectCnt; // 应答帧期望长度 / expected response length
            IF (uByteCount = uExpectCnt) AND (uLen = uExpectLen) THEN
                bFrameOk := TRUE;             // 字节数域与帧长双向自洽 / both the byte count and the length agree
            ELSE
                eErr := 16#0001_032E;         // 字节数域或帧长不自洽 / byte count or length mismatch
                bError := TRUE;               // 置故障标志 / raise the error flag
            END_IF
        END_IF

    eFc05, eFc06:
        bWriteFc := TRUE;                     // 写单点类 / single write class
        IF (uQty = DL_RTU_QTY_FIX) AND (uLen = DL_RTU_FIX_LEN) THEN
            bFrameOk := TRUE;                 // 定长帧且数量为 1 / fixed length frame with a quantity of one
        ELSE
            eErr := 16#0001_032E;             // 定长或数量不合法 / fixed length or quantity violated
            bError := TRUE;                   // 置故障标志 / raise the error flag
        END_IF

    eFc0F:
        bWriteFc := TRUE;                     // 写多点线圈类 / multiple coil write class
        IF (uQty >= DL_RTU_ONE) AND (uLen >= DL_RTU_WR_BASE) THEN
            uByteCount := auFrame[DL_RTU_IDX_WRCNT]; // 长度闸在前，下标 6 安全 / the length gate ran first, index six is safe
            uExpectCnt := (uQty + DL_RTU_BIT_ROUND) / DL_RTU_BITS_PER_BYTE; // 线圈数量换算字节数 / coil quantity converted to bytes
            IF uByteCount = uExpectCnt THEN
                bFrameOk := TRUE;             // 字节数域与声明数量自洽 / byte count agrees with the declared quantity
            ELSE
                eErr := 16#0001_032E;         // 字节数域不自洽 / byte count mismatch
                bError := TRUE;               // 置故障标志 / raise the error flag
            END_IF
        ELSE
            eErr := 16#0001_032E;             // 帧长或数量不足以承载请求 / length or quantity cannot carry the request
            bError := TRUE;                   // 置故障标志 / raise the error flag
        END_IF

    eFc10:
        bWriteFc := TRUE;                     // 写多点寄存器类 / multiple register write class
        IF (uQty >= DL_RTU_ONE) AND (uLen >= DL_RTU_WR_BASE) THEN
            uByteCount := auFrame[DL_RTU_IDX_WRCNT]; // 长度闸在前，下标 6 安全 / the length gate ran first, index six is safe
            uExpectCnt := uQty * DL_RTU_WORD_BYTES; // 每寄存器 2 字节 / two bytes per register
            IF uByteCount = uExpectCnt THEN
                bFrameOk := TRUE;             // 字节数域与声明数量自洽 / byte count agrees with the declared quantity
            ELSE
                eErr := 16#0001_032E;         // 字节数域不自洽 / byte count mismatch
                bError := TRUE;               // 置故障标志 / raise the error flag
            END_IF
        ELSE
            eErr := 16#0001_032E;             // 帧长或数量不足以承载请求 / length or quantity cannot carry the request
            bError := TRUE;                   // 置故障标志 / raise the error flag
        END_IF

    eFcUnknown:
        bFrameOk := TRUE;                     // 未纳入长度表：只做长度域检查后放行 / outside the table, released after the length check
        eErr := 16#0001_040A;                 // 信息级：功能码未纳入校验表 / info level, function code outside the length table

ELSE
    bFrameOk := TRUE;                         // 非法枚举值同样放行，不阻断上层解析 / illegal enum values are released too, never block the caller
    eErr := 16#0001_040A;                     // 信息级：未识别功能码，与 eFcUnknown 同一语义 / info level, unidentified function code, same semantics as eFcUnknown
END_CASE

// 段 6｜广播读类提示（协议上无意义，几乎必是站号配错；只提示不阻断）/ segment 6, broadcast read hint
IF (NOT bError) AND bBroadcast AND bReadFc THEN
    eErr := 16#0001_040B;                     // 信息级：广播配读类，已放行 / info level, broadcast with a read class, released
END_IF

// 段 7｜发布结论（故障级优先，信息码永不置 bError）/ segment 7, publish the conclusion
IF bError THEN
    FC_DL_ModbusRtuFrameCheck := FALSE;       // 故障态判定不自洽 / a fault means the frame is not self-consistent
    bValid := FALSE;                          // 结论不可信 / conclusion untrustworthy
ELSE
    FC_DL_ModbusRtuFrameCheck := bFrameOk;    // 无故障时输出结构自洽结论 / publish the self-consistency conclusion when no fault is present
    bValid := TRUE;                           // 结论可信 / conclusion trustworthy
END_IF
END_FUNCTION
