(*
  ==================================================================
  组件名 Component  : FC_DL_AsciiFrameParse
  分类   Category   : DL_MathData
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : ASCII 仪表帧解析。STX(16#02)/ETX(16#03) 定界 + 长度闸
                      + 可选校验。载荷校验模式：载荷末两字符为十六进制校验
                      和（前部载荷字符 hex 值之和模 256），bChkEn = TRUE 时
                      逐字符 hex 解码比对。OSCAT Network ASCII 帧族语义
                      clean-room，与 FC_DL_ModbusRtuFrameCheck 二进制帧分工。
  来源   Source     : T1-3-oscat-network（ASCII 帧族公开语义）
  溯源   Origin     : STX/ETX 定界与 LRC 校验为公开工业语义，clean-room 自研
                      实现，未复制 OSCAT 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: LEN / MID / LEFT /
                      RIGHT / FIND，'$02' '$03' 为 IEC 标准 $ 转义）
  分工声明 Split     : 与 FC_DL_ModbusRtuFrameCheck 分工——后者做二进制 RTU
                      帧校验，本件做 ASCII 可打印帧解析。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 结构闸：长度 ∈ [5..255]（STX + 载荷 ≥1 + 校验 2 +
                         ETX）、首字符 = STX、末字符 = ETX、ETX 唯一（FIND
                         定位 = 末位），任一不满足置 bError；
                      二 校验闸（bChkEn）：载荷含非 hex 字符或和模 256 ≠ 校
                         和 → bBadChk（信息级），bValid 随之降假；
                      三 非有限无涉（纯整数与串操作，无除零/浮点风险）；
                      四 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 2 · 序号 7）
  ==================================================================
*)

FUNCTION FC_DL_AsciiFrameParse : BOOL
VAR_INPUT
    sFrame : STRING(255) := ''; // 原始帧串（含 STX/ETX）[-] / the raw frame string with the delimiters
    bChkEn : BOOL := FALSE;     // 载荷校验使能（末两字符 hex 校验和）[-] / the payload checksum enable
END_VAR
VAR_OUTPUT
    sPayload : STRING(255) := ''; // 载荷输出（不含 STX/ETX/校验段，校验使能时）/ the payload outlet, without the delimiters and the checksum when enabled
    nPayLen  : DINT  := 0;  // 载荷长度 [字符] / the payload length
    bValid   : BOOL := FALSE; // 解析受理且校验通过（校验未使能时仅结构）[-] / the parsed and verified flag
    bBadChk  : BOOL := FALSE; // 校验不匹配或载荷非 hex（信息级，仅校验使能时判定）[-] / the checksum mismatch, informational
    bError   : BOOL := FALSE; // 结构故障标志（定界/长度闸）[-] / the structure fault flag
END_VAR
VAR CONSTANT
    DL_AFP_STX    : STRING(1) := '$02'; // 帧头 STX（IEC $ 转义）/ the STX delimiter
    DL_AFP_ETX    : STRING(1) := '$03'; // 帧尾 ETX（IEC $ 转义）/ the ETX delimiter
    DL_AFP_HEXTAB : STRING(16) := '0123456789ABCDEF'; // hex 字符表（FIND 解码）/ the hex table for the FIND decoding
    DL_AFP_LENMIN : DINT := 5;  // 最小帧长（STX+1+2+ETX）[字符] / the min frame length
    DL_AFP_LENMAX : DINT := 255; // 最大帧长（库串上限）[字符] / the max frame length
END_VAR
VAR
    nLen   : DINT; // 帧长 [字符] / the frame length
    nEtx   : DINT; // ETX 定位（FIND 结果）[位] / the ETX position by the FIND
    sCh    : STRING(1); // 单字符工作量 [-] / the one char work value
    nPos   : DINT;  // hex 表命中位（0 = 非法）[位] / the hex table hit, zero means illegal
    nSum   : DINT;  // 载荷 hex 值累加和 [无量纲] / the payload hex value sum
    nChk   : DINT;  // 末两字符校验和值 [无量纲] / the trailing checksum value
    nI     : DINT;  // 载荷遍历索引 [字符] / the payload loop index
    nDataLen: DINT; // 数据段长度（载荷减校验两字符）[字符] / the data length, the payload minus two
    sHead  : STRING(1); // 首字符工作量 [-] / the first char work value
    sTail  : STRING(1); // 末字符工作量 [-] / the last char work value
    sChk   : STRING(2); // 校验段工作量 [-] / the checksum slice work value
END_VAR

// 段 1｜返回值与输出预置（四段式第一段，R45）/ segment 1, preset the return and the outputs
FC_DL_AsciiFrameParse := FALSE; // 受理预置假 / preset the accepted false
sPayload := ''; // 载荷预置空 / preset the payload empty
nPayLen := 0; // 载荷长预置零 / preset the payload length zero
bValid := FALSE; // 有效预置假 / preset the valid false
bBadChk := FALSE; // 校验不匹配预置假 / preset the checksum flag false
bError := FALSE; // 故障预置假 / preset the fault false

// 段 2｜结构闸（定界 + 长度 + ETX 唯一性，边界一）/ segment 2, the structure gates
nLen := LEN(sFrame); // 取帧长 / take the frame length
IF (nLen < DL_AFP_LENMIN) OR (nLen > DL_AFP_LENMAX) THEN // 长度闸 / the length gate
    bError := TRUE; // 置故障 / raise the fault
    RETURN; // 早退 / return early
END_IF
sHead := LEFT(sFrame, 1); // 取首字符 / take the first char
sTail := RIGHT(sFrame, 1); // 取末字符 / take the last char
IF (sHead <> DL_AFP_STX) OR (sTail <> DL_AFP_ETX) THEN // 定界闸 / the delimiter gate
    bError := TRUE; // 置故障 / raise the fault
    RETURN; // 早退 / return early
END_IF
nEtx := FIND(sFrame, DL_AFP_ETX); // ETX 定位 / locate the ETX
IF nEtx <> nLen THEN // ETX 非末位（帧内混入 ETX）/ the ETX not at the tail
    bError := TRUE; // 置故障 / raise the fault
    RETURN; // 早退 / return early
END_IF

// 段 3｜载荷提取与校验判定（校验使能时载荷末两字符为 hex 校验和，边界二）/ segment 3, the payload extraction and the checksum
IF bChkEn THEN // 校验使能模式 / the checksum enabled mode
    nDataLen := nLen - 5; // 数据段长 = 帧长 - STX - ETX - 校验 2 字符 / the data length
    sPayload := MID(sFrame, nDataLen, 2); // 取数据段（跳过 STX 与校验两字符）/ take the data slice
    sChk := MID(sFrame, 2, nDataLen + 1); // 取校验两字符 / take the two checksum chars
    nSum := 0; // 和清零 / clear the sum
    FOR nI := 1 TO nDataLen DO // 逐数据字符 hex 累加 / per data char hex sum
        sCh := MID(sPayload, 1, nI); // 取单字符 / take one char
        nPos := FIND(DL_AFP_HEXTAB, sCh); // hex 表命中 / the hex table hit
        IF nPos = 0 THEN // 非 hex 字符 / a non hex char
            bBadChk := TRUE; // 置校验不匹配（信息级）/ raise the mismatch, informational
        ELSE // 合法 hex / a legal hex
            nSum := nSum + (nPos - 1); // 累加 hex 值 / accumulate the value
        END_IF
    END_FOR
    nPos := FIND(DL_AFP_HEXTAB, MID(sChk, 1, 1)); // 校验高位解码 / decode the high nibble
    IF nPos = 0 THEN // 非法 / illegal
        bBadChk := TRUE; // 置不匹配 / raise the mismatch
    ELSE // 合法 / legal
        nChk := (nPos - 1) * 16; // 高位 ×16 / the high times sixteen
        nPos := FIND(DL_AFP_HEXTAB, MID(sChk, 1, 2)); // 校验低位解码 / decode the low nibble
        IF nPos = 0 THEN // 非法 / illegal
            bBadChk := TRUE; // 置不匹配 / raise the mismatch
        ELSE // 合法 / legal
            nChk := nChk + (nPos - 1); // 低位并入 / add the low
            IF (nSum MOD 256) <> nChk THEN // 和模 256 比对 / the modulo compare
                bBadChk := TRUE; // 校验不匹配 / the mismatch
            END_IF
        END_IF
    END_IF
    nPayLen := nDataLen; // 载荷长出口（数据段口径）/ the payload length outlet
ELSE // 校验未使能：整段载荷直通 / the checksum disabled, the whole payload
    sPayload := MID(sFrame, nLen - 2, 2); // 取 STX 与 ETX 之间 / take between the delimiters
    nPayLen := nLen - 2; // 载荷长出口 / the payload length outlet
    IF nPayLen < 1 THEN // 零载荷防御（长度闸已保下限 5，纵深）/ the empty payload defense in depth
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
END_IF

// 段 4｜统一出口（校验使能时 bValid = 结构通过 AND 校验通过）/ segment 4, the unified outlet
bValid := (NOT bError) AND (NOT bBadChk); // 受理判据 / the accept verdict
FC_DL_AsciiFrameParse := bValid; // 受理标志 / the accepted flag
END_FUNCTION
