(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ModbusRtuFrameBuild
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（SHR / SHL 位运算），零厂商私有库
 * 功能描述 (Function)   : Modbus RTU 帧构造（从站地址 + 功能码 + 数据域 + 可选 CRC16）：
 *                         ① 域闸：从站地址 1..247、功能码 1..127、数据长度 ≤ 32，
 *                            任一项越界即拒建帧并返回 FALSE（绝不输出可疑半帧）；
 *                         ② 帧缓冲先整体清零（aFrame[1..64] := 16#00），保证未使用尾部
 *                            可复现，接收侧做帧比对不会因残留字节误判；
 *                         ③ 装配：aFrame[1] = 从站地址，aFrame[2] = 功能码，
 *                            aFrame[3..] = 数据域（数据域长度为 0 时直接接 CRC）；
 *                         ④ **CRC16 逐位实现**（多项式 16#A001 反射式、初值 16#FFFF、
 *                            低字节先发），内联循环、不调用任何外部件，跨平台零差异；
 *                         ⑤ bAppendCrc = FALSE 时只出 PDU 头 + 数据域，uiCrc 仍照算
 *                            （便于上层做接收侧预校验，信息级披露）。
 * 接口     (Interface)  : 输入 uiSlaveAddr / uiFuncCode / aData[1..32] / uiDataLen /
 *                         bAppendCrc；输出 aFrame[1..64] / uiFrameLen / uiCrc（WORD）/
 *                         bOk / uErrorId；返回值 BOOL = 建帧成功标志（与 bOk 同源）。
 * 边界     (Boundary)   : ① 最长帧 = 2 + 32 + 2 = 36 字节 ≤ 64，缓冲结构性不溢出；
 *                         ② 数据域长度 0 合法（如读请求以外的自定义功能码），
 *                            此时帧长 = 3（含 CRC 时 +2）；
 *                         ③ CRC 逐位循环恒 8 次，移位量恒为 1 与 8，绝不等于 16 位宽，
 *                            结构性规避「移位量等于位宽」的跨平台未定义行为；
 *                         ④ 本件只做**发送方向**建帧，不解析接收帧、不做字节间超时判定；
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q / %M）。
 * 码表     (Codes)      : 本件占用 16#0004_1030 ~ 16#0004_103F 区间，实际使用 5 个：
 *                         1030 故障级 从站地址越界；1031 故障级 功能码越界；
 *                         1032 故障级 数据域长度越界；1033 信息级 已按要求不追加 CRC；
 *                         1034 故障级 帧长自检异常（内部一致性兜底）。
 * 分工声明 (Scope)      : 与 FC_DL_Crc16Generic 分工：那件为通用参数化 CRC（可配反射 /
 *                         异或终值），本件内联 Modbus 固定参数 CRC 以保证零依赖、
 *                         单次建帧不引入 FB 实例；两者结果对 Modbus 参数必然一致。
 * 开源溯源 (Origin)     : 开源溯源：原创实现（无外部代码引入）。Modbus 应用协议规约
 *                         常数为公开规范值（CRC 多项式 16#A001、初值 16#FFFF、地址域
 *                         1..247、功能码 1..127），按 clean-room 口径只取规范常数，
 *                         未复制任何第三方实现代码。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 全域闸 + 长度钳位 + 缓冲结构性不溢出
 *                         R5 ✓ 声明逐行同行双语注释 ｜ R6 N/A（纯函数无状态机）
 *                         R7 N/A（无定时器/边沿实例）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版
 * 验收向量 (Acceptance) :
 *   V1 uiSlaveAddr=1、uiFuncCode=3、数据域 {00 00 00 01}、bAppendCrc=TRUE →
 *      aFrame[1..8] = 01 03 00 00 00 01 84 0A，uiFrameLen=8、uiCrc=16#0A84、
 *      bOk=TRUE、返回值 TRUE、uErrorId=0。
 *   V2 同 V1 但数据域 {00 00 00 0A} → uiCrc=16#CDC5，帧尾两字节依次 C5 CD
 *      （低字节先发），uiFrameLen=8。
 *   V3 uiSlaveAddr=17、uiFuncCode=3、uiDataLen=0、bAppendCrc=TRUE →
 *      uiCrc=16#E14D，aFrame[1..4] = 11 03 4D E1，uiFrameLen=4、bOk=TRUE。
 *   V4 uiSlaveAddr=248（越界）→ 返回值 FALSE、bOk=FALSE、uiFrameLen=0、
 *      uErrorId=16#0004_1030，且 aFrame 全 0（不输出可疑半帧）。
 *   V5 uiDataLen=40（> 32）→ 返回值 FALSE、uErrorId=16#0004_1032、uiFrameLen=0。
 *   V6 同 V1 但 bAppendCrc=FALSE → uiFrameLen=6、uiCrc 仍为 16#0A84、
 *      uErrorId=16#0004_1033（信息级，bOk 仍 TRUE）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   本件为 FUNCTION，无实例状态，可在任意 FB / PRG 内直接调用：
 *     xSend := FC_DL_ModbusRtuFrameBuild(uiSlaveAddr := 1, uiFuncCode := 3,
 *                                        aData := astReq.aBytes, uiDataLen := 4,
 *                                        bAppendCrc := TRUE,
 *                                        aFrame => astTx.aBytes, uiFrameLen => nTxLen);
 *   注：aData 元素不足 uiDataLen 时上层必须自行保证数据已填；本件对 aData 只读。
 *   发送前请核对 uiFrameLen 与串口驱动的写入长度一致，避免少发 CRC。
 *----------------------------------------------------------------------------*)

(*==============================================================================
 * 函数: FC_DL_ModbusRtuFrameBuild
 * 返回: BOOL，TRUE = 建帧成功（aFrame / uiFrameLen / uiCrc 可用）
 * 纯函数性: 除 VAR_OUTPUT 外不保留任何跨调用状态，同参数必得同结果。
 *============================================================================*)
FUNCTION FC_DL_ModbusRtuFrameBuild : BOOL
VAR_INPUT
    uiSlaveAddr : UINT;                       // Modbus 从站地址，合法域 1..247 [-] / Modbus slave address, legal domain 1..247
    uiFuncCode  : UINT;                       // Modbus 功能码，合法域 1..127 [-] / Modbus function code, legal domain 1..127
    aData       : ARRAY[1..32] OF BYTE;       // 数据域源字节数组（定长 32，只用前 uiDataLen 个）[字节] / Source data bytes, fixed 32, only the first uiDataLen used [byte]
    uiDataLen   : UINT;                       // 数据域实际长度，0..32 [字节] / Actual data field length, 0..32 [byte]
    bAppendCrc  : BOOL;                       // 是否追加 CRC16 两字节（FALSE 只出 PDU）[BOOL] / Append the two CRC bytes, FALSE emits the PDU only
END_VAR
VAR_OUTPUT
    aFrame      : ARRAY[1..64] OF BYTE;       // 组帧输出缓冲，未使用尾部恒为 16#00 [字节] / Frame output buffer, unused tail always 16#00 [byte]
    uiFrameLen  : UINT;                       // 实际帧长（含 CRC 时 = 2 + 数据长 + 2）[字节] / Actual frame length, including CRC when appended [byte]
    uiCrc        : WORD;                      // 计算所得的 CRC16 值（低字节先发，不随 bAppendCrc 变化）[-] / Computed CRC16, low byte first, independent of bAppendCrc
    bOk         : BOOL;                       // 建帧成功标志，与返回值同源 / Frame build success flag, same source as the return value
    uErrorId    : UDINT;                      // 错误码，0 = 无码（信息级码不置失败）[码] / Error code, 0 = no code, info codes never fail the call
END_VAR
VAR
    iIdx        : INT;                        // 通用循环下标（1 基）[-] / Generic loop index, one based
    iBit        : INT;                        // CRC 位循环下标 1..8 [位] / CRC bit loop index 1..8 [bit]
    nDataLen    : INT;                        // 数据域长度整数化 [字节] / Data field length as an integer [byte]
    nContent    : INT;                        // CRC 覆盖的字节数（地址域 + 功能码 + 数据域）[字节] / Bytes covered by the CRC [byte]
    wCrcReg     : WORD;                       // CRC 移位寄存器 [位图] / CRC shift register [bitmap]
    wBitVal     : WORD;                       // 本位移出的最低位值 [位图] / Lowest bit value shifted out this round [bitmap]
    wByteExt    : WORD;                       // 当前字节零扩展值 [位图] / Zero-extended current byte [bitmap]
    wCrcHi      : WORD;                       // CRC 高字节（右移 8 位取得）[位图] / High byte of the CRC, obtained by shifting right eight bits [bitmap]
    wCrcLo      : WORD;                       // CRC 低字节（掩码取得）[位图] / Low byte of the CRC, obtained by masking [bitmap]
END_VAR
VAR CONSTANT
    DL_MB_OK        : UDINT := 16#0000_0000;  // 无码哨兵 / No-code sentinel
    DL_MB_ADDR_MIN  : UINT := 1;              // 从站地址下限（0 为广播，不作为本件输入）[-] / Slave address lower bound, zero is broadcast and not accepted here
    DL_MB_ADDR_MAX  : UINT := 247;            // 从站地址上限 [-] / Slave address upper bound
    DL_MB_FUNC_MIN  : UINT := 1;              // 功能码下限 [-] / Function code lower bound
    DL_MB_FUNC_MAX  : UINT := 127;            // 功能码上限（公开功能码最大 127）[-] / Function code upper bound, public range ends at 127
    DL_MB_DATA_MAX  : UINT := 32;             // 数据域长度上限 [字节] / Data field length upper bound [byte]
    DL_MB_FRAME_MAX : INT := 64;              // 帧缓冲上界（数组上界，清缓冲用）[字节] / Frame buffer bound used to clear the array [byte]
    DL_MB_HDR_LEN   : INT := 2;               // 帧头长度（地址 + 功能码）[字节] / Header length, address plus function code [byte]
    DL_MB_CRC_LEN   : INT := 2;               // CRC 字段长度 [字节] / CRC field length [byte]
    DL_MB_BIT_LAST  : INT := 8;               // 每字节处理位数（恒 8，不等于 16 位宽）[位] / Bits processed per byte, always 8 and never the 16 bit width [bit]
    DL_MB_SHIFT_HI  : INT := 8;               // 取高字节的右移量（恒 8，不等于 16 位宽）[位] / Shift amount for the high byte, always 8 [bit]
    DL_MB_BYTE_0    : BYTE := 16#00;          // 字节零哨兵，清缓冲用 [字节] / Byte zero sentinel used to clear the buffer [byte]
    DL_MB_W0        : WORD := 16#0000;        // 字零哨兵，避免裸字面量比较 / Word zero sentinel avoiding bare literal comparison
    DL_MB_CRC_INIT  : WORD := 16#FFFF;        // CRC16 初值（Modbus 规范常数）[位图] / CRC16 initial value, Modbus standard constant [bitmap]
    DL_MB_CRC_POLY  : WORD := 16#A001;        // CRC16 反射多项式（Modbus 规范常数）[位图] / CRC16 reflected polynomial, Modbus standard constant [bitmap]
    DL_MB_LSB_MASK  : WORD := 16#0001;        // 最低位掩码 [位图] / Least significant bit mask [bitmap]
    DL_MB_BYTE_MASK : WORD := 16#00FF;        // 低字节掩码 [位图] / Low byte mask [bitmap]
END_VAR

(* —— 段 0：出口预置安全值（四段式第一段：预置） —— *)
FC_DL_ModbusRtuFrameBuild := FALSE;                       // 返回值预置失败 / Return preset to failure
bOk        := FALSE;                                      // 成功标志预置失败 / Success flag preset to failure
uiFrameLen := 0;                                          // 帧长预置 0 / Frame length preset to zero
uiCrc      := DL_MB_CRC_INIT;                             // CRC 预置初值（未计算口径） / CRC preset to the initial value
uErrorId   := DL_MB_OK;                                   // 无码预置 / Preset no code

(* 缓冲整体清零：未使用尾部恒 0，接收侧比帧不会因残留字节误判 *)
(* Clear the whole buffer: the unused tail is always zero so frame comparison is reproducible *)
FOR iIdx := 1 TO DL_MB_FRAME_MAX DO
    aFrame[iIdx] := DL_MB_BYTE_0;                         // 逐字节清 0 / Clear byte by byte
END_FOR

(* —— 段 1：从站地址域闸（1..247，0 为广播不属本件职责） —— *)
IF (uiSlaveAddr < DL_MB_ADDR_MIN) OR (uiSlaveAddr > DL_MB_ADDR_MAX) THEN
    uErrorId := 16#0004_1030;                             // 故障级：从站地址越界 / Fault: slave address out of range
    RETURN;                                               // 早退，保持 aFrame 全 0 / Early exit keeping the buffer cleared
END_IF

(* —— 段 2：功能码域闸（1..127） —— *)
IF (uiFuncCode < DL_MB_FUNC_MIN) OR (uiFuncCode > DL_MB_FUNC_MAX) THEN
    uErrorId := 16#0004_1031;                             // 故障级：功能码越界 / Fault: function code out of range
    RETURN;                                               // 早退 / Early exit
END_IF

(* —— 段 3：数据域长度域闸（0..32），整数化后才允许参与下标运算 —— *)
IF uiDataLen > DL_MB_DATA_MAX THEN
    uErrorId := 16#0004_1032;                             // 故障级：数据域长度越界 / Fault: data length out of range
    RETURN;                                               // 早退 / Early exit
END_IF
nDataLen := UINT_TO_INT(uiDataLen);                       // 长度整数化（标准转换，禁构造式） / Integer conversion through the standard function

(* —— 段 4：帧装配（地址 + 功能码 + 数据域） —— *)
aFrame[1] := UINT_TO_BYTE(uiSlaveAddr);                   // 地址域占 b1 / Address field at byte one
aFrame[2] := UINT_TO_BYTE(uiFuncCode);                    // 功能码域占 b2 / Function code at byte two
IF nDataLen > 0 THEN
    FOR iIdx := 1 TO nDataLen DO
        aFrame[DL_MB_HDR_LEN + iIdx] := aData[iIdx];      // 数据域搬移到 b3 起 / Move the data field starting at byte three
    END_FOR
END_IF
nContent := DL_MB_HDR_LEN + nDataLen;                     // CRC 覆盖长度（2 + 数据长）/ CRC coverage length

(* —— 段 5：CRC16 逐位实现（初值 16#FFFF、反射多项式 16#A001、低字节先发） —— *)
(* Bitwise CRC16: initial value 16#FFFF, reflected polynomial 16#A001, low byte sent first *)
wCrcReg := DL_MB_CRC_INIT;                                // 寄存器装载规范初值 / Load the standard initial value
FOR iIdx := 1 TO nContent DO
    wByteExt := BYTE_TO_WORD(aFrame[iIdx]);               // 当前字节零扩展为字 / Zero-extend the current byte
    wCrcReg  := wCrcReg XOR wByteExt;                     // 字节异或进寄存器低 8 位 / XOR the byte into the low half
    FOR iBit := 1 TO DL_MB_BIT_LAST DO
        wBitVal := wCrcReg AND DL_MB_LSB_MASK;            // 取最低位（移位前快照）/ Snapshot the lowest bit before shifting
        wCrcReg := SHR(wCrcReg, 1);                       // 右移一位（移位量恒 1，不等于 16 位宽）/ Shift right by one
        IF wBitVal <> DL_MB_W0 THEN
            wCrcReg := wCrcReg XOR DL_MB_CRC_POLY;        // 最低位为 1：异或反射多项式 / Bit set, XOR the reflected polynomial
        END_IF
    END_FOR
END_FOR
uiCrc := wCrcReg;                                         // CRC 结果出口（不追加也照算）/ CRC outlet, computed even without appending

(* —— 段 6：CRC 追加（低字节先发）与帧长确认 —— *)
IF bAppendCrc THEN
    wCrcLo := wCrcReg AND DL_MB_BYTE_MASK;                // 低字节掩码取得 / Low byte by masking
    wCrcHi := SHR(wCrcReg, DL_MB_SHIFT_HI);               // 右移 8 位得高字节（移位量恒 8）/ High byte by shifting right eight bits
    aFrame[nContent + 1] := WORD_TO_BYTE(wCrcLo);         // 低字节先发 / Low byte first
    aFrame[nContent + 2] := WORD_TO_BYTE(wCrcHi);         // 高字节随后 / High byte afterwards
    uiFrameLen := INT_TO_UINT(nContent + DL_MB_CRC_LEN);  // 帧长含 CRC / Frame length including the CRC
ELSE
    uiFrameLen := INT_TO_UINT(nContent);                  // 帧长不含 CRC / Frame length without the CRC
    uErrorId   := 16#0004_1033;                           // 信息级：按要求未追加 CRC / Info: CRC intentionally not appended
END_IF

(* —— 段 7：帧长自检兜底（四段式第四段：复检） —— *)
IF (uiFrameLen < 3) OR (uiFrameLen > 36) THEN
    uiFrameLen := 0;                                      // 自检异常：不给可疑帧长 / Self-check failed, never emit a suspicious length
    bOk        := FALSE;                                  // 成功标志清除 / Success flag cleared
    uErrorId   := 16#0004_1034;                           // 故障级：帧长自检异常 / Fault: internal frame length self-check failed
    FC_DL_ModbusRtuFrameBuild := FALSE;                   // 返回值失败 / Return failure
    RETURN;                                               // 早退 / Early exit
END_IF

(* —— 段 8：成功出口（信息级码不改变成功性） —— *)
bOk := TRUE;                                              // 建帧成功 / Frame built successfully
FC_DL_ModbusRtuFrameBuild := TRUE;                        // 返回值成功 / Return success
END_FUNCTION
