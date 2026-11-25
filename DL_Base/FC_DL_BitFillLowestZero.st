(*==============================================================================
 * 名称 : FC_DL_BitFillLowestZero —— 最低 0 位置 1（DWORD），输出该位位号
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 把输入 DWORD 中最低的 0 位置 1 后返回（即 dwIn OR 单比特隔离值），
 *            并给出该位位号 nPos。常用于资源位图分配（找空位并占用）。
 *            边界处理：输入全 1 时无 0 位可填，原值返回、nPos=-1、bValid=FALSE
 *            并置 eErr（返回值虽为原值，但语义上未发生分配）。
 * 错误码 : 16#0001_1A08 = 输入全 1，无 0 位可填
 *          eErr=0 且 bValid=TRUE 表示已完成填位且 nPos 有效
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量≤31 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BitFillLowestZero : DWORD
VAR_INPUT
    dwIn : DWORD;      // 输入位图 [位域] / input bitmap dword
END_VAR
VAR_OUTPUT
    nPos   : INT;      // 被填 1 的最低 0 位位号，全 1 时为 -1 [位] / bit index filled, -1 if none
    eErr   : UDINT;    // 故障码，0=正常，1A08=全 1 无空位 / error code, 0=ok, 1A08=all-ones input
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=填位成功且 nPos 有效 / TRUE when fill succeeded and nPos valid
END_VAR
VAR
    _dwNot  : DWORD;   // 输入按位取反（0 位变 1 位）/ inverted input (zeros become ones)
    _dwIso  : DWORD;   // 最低 0 位的单比特隔离值 [位域] / isolated lowest zero bit
    _i      : INT;     // 位扫描游标 [位] / bit scan cursor
    _dwW    : DWORD;   // 单比特游走值 [位域] / single-bit walker
    _xHit   : BOOL;    // 命中标志 / found flag
END_VAR

nPos := -1;                                  // 位号预设 -1（未命中语义）/ preset position to -1
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

_dwNot := NOT dwIn;                          // 取反后 0 位变 1 位 / invert so zeros become ones
IF _dwNot = DWORD#16#0000_0000 THEN          // 全 1：无 0 位可填 / all ones: nothing to fill
    eErr   := 16#0001_1A08;                  // 置全 1 故障码 / set all-ones code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // nPos 不可用 / position not usable
    FC_DL_BitFillLowestZero := dwIn;         // 原值返回 / return input unchanged
    RETURN;                                  // 提前收口 / early exit
END_IF

_dwIso := _dwNot AND (NOT (_dwNot - DWORD#16#0000_0001));    // 隔离最低 0 位（同最低 1 位法）/ isolate lowest zero bit
_xHit  := FALSE;                             // 命中标志清零 / clear found flag
FOR _i := 0 TO 31 DO                         // 从低位找第一个命中 / scan low to high for first hit
    _dwW := SHL(DWORD#16#0000_0001, _i);     // 当前位单比特掩码（_i≤31 安全）/ single-bit mask
    IF (NOT _xHit) AND ((_dwIso AND _dwW) <> DWORD#16#0000_0000) THEN    // 首个命中即停扫 / stop at first hit
        nPos  := _i;                         // 回写位号 / write back bit index
        _xHit := TRUE;                       // 置命中标志 / set found flag
    END_IF
END_FOR

FC_DL_BitFillLowestZero := dwIn OR _dwIso;   // 填 1 后返回 / return with the bit filled

END_FUNCTION
