(*==============================================================================
 * 名称 : FC_DL_BitLowestSet —— 最低置位位号与单比特隔离值（DWORD）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回输入 DWORD 中最低置位位的位号（0..31），并输出单比特隔离值
 *            dwIsolate = dwIn AND (NOT (dwIn - 1))（无符号回绕语义，等价于
 *            二进制补码的 x AND (-x)，仅保留最低的 1 位）。
 *            边界处理：dwIn 全 0 时无置位位，返回 -1、dwIsolate=0、bValid=FALSE
 *            并置 eErr（隔离值无效，调用方不得使用）。
 * 错误码 : 16#0001_1A05 = 输入全 0，无置位位可隔离
 *          eErr=0 且 bValid=TRUE 表示返回位号与隔离值均有效
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量≤31 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BitLowestSet : INT
VAR_INPUT
    dwIn : DWORD;      // 待扫描的输入双字 [位域] / input dword to be scanned
END_VAR
VAR_OUTPUT
    dwIsolate : DWORD;    // 最低置位位的单比特隔离值 [位域] / isolated lowest set bit
    eErr      : UDINT;    // 故障码，0=正常，1A05=输入全 0 / error code, 0=ok, 1A05=all-zero input
    bError    : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid    : BOOL;     // TRUE=返回位号与隔离值可用 / TRUE when outputs are usable
END_VAR
VAR
    _i    : INT;       // 位扫描游标 [位] / bit scan cursor
    _dwW  : DWORD;     // 单比特游走值 [位域] / single-bit walker
    _xHit : BOOL;      // 是否已找到最低置位位 / found flag for lowest set bit
END_VAR

FC_DL_BitLowestSet := -1;                    // 返回值预设 -1（未命中语义）/ preset return to -1
dwIsolate := DWORD#16#0000_0000;             // 隔离值预设全 0 / preset isolate to zero
eErr      := 16#0000_0000;                   // 故障码清零 / clear error code
bError    := FALSE;                          // 故障标志清零 / clear error flag
bValid    := TRUE;                           // 预设输出可用 / preset valid flag

IF dwIn = DWORD#16#0000_0000 THEN            // 输入全 0：无置位位 / all-zero input: no set bit
    eErr   := 16#0001_1A05;                  // 置全 0 故障码 / set all-zero code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 位号与隔离值均不可用 / outputs not usable
    RETURN;                                  // 返回 -1、隔离值 0 / return -1 with zero isolate
END_IF

dwIsolate := dwIn AND (NOT (dwIn - DWORD#16#0000_0001));    // 经典隔离式，仅留最低 1 位 / classic isolate of lowest set bit
_xHit := FALSE;                              // 命中标志清零 / clear found flag
FOR _i := 0 TO 31 DO                         // 从低位向高位找第一个 1 / scan low to high for first one
    _dwW := SHL(DWORD#16#0000_0001, _i);     // 当前位单比特掩码（_i≤31 安全）/ single-bit mask
    IF (NOT _xHit) AND ((dwIsolate AND _dwW) <> DWORD#16#0000_0000) THEN    // 首个命中即停扫 / stop at first hit
        FC_DL_BitLowestSet := _i;            // 回写最低置位位号 / write back lowest bit index
        _xHit := TRUE;                       // 置命中标志 / set found flag
    END_IF
END_FOR

END_FUNCTION
