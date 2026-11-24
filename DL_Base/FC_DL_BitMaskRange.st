(*==============================================================================
 * 名称 : FC_DL_BitMaskRange —— 连续位区间掩码构造（bitLo..bitHi 置 1 的 DWORD 掩码）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 依入参位号 uLo..uHi 构造 DWORD 掩码，区间内各位置 1、其余为 0。
 *            边界处理：uLo/uHi 越界（<0 或 >31）先钳位到 [0,31] 再构造；
 *            钳位后 uLo>uHi（区间为空）返回 DWORD#0 并置 eErr 故障码。
 *            移位量恒 ≤31（<DWORD 位宽 32），结构性无越界移位。
 * 错误码 : 16#0001_1A01 = 钳位后位区间为空（uLo>uHi），掩码无意义
 *          eErr=0 且 bValid=TRUE 表示掩码有效；bValid=FALSE 时返回值勿用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量≤31 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BitMaskRange : DWORD
VAR_INPUT
    uLo : INT;     // 起始位号 0..31，越界自动钳位 [位] / low bit index, clamped into [0,31]
    uHi : INT;     // 结束位号 0..31，越界自动钳位 [位] / high bit index, clamped into [0,31]
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1A01=区间为空 / error code, 0=ok, 1A01=empty range
    bError : BOOL;     // TRUE=本件发生参数级故障 / TRUE when parameter-level fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _nLo   : INT;      // 钳位后的起始位号 [位] / clamped low bit index
    _nHi   : INT;      // 钳位后的结束位号 [位] / clamped high bit index
    _i     : INT;      // 位扫描游标 [位] / bit scan cursor
    _dwBit : DWORD;    // 当前游标对应的单比特值 [位域] / single-bit walker value
END_VAR

FC_DL_BitMaskRange := DWORD#16#0000_0000;    // 返回值预设全 0 掩码 / preset return to zero mask
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

_nLo := uLo;                                 // 取入参起始位号 / take input low index
_nHi := uHi;                                 // 取入参结束位号 / take input high index
IF _nLo < 0 THEN _nLo := 0; END_IF           // 下界钳位 / clamp lower bound
IF _nLo > 31 THEN _nLo := 31; END_IF         // 上界钳位 / clamp upper bound
IF _nHi < 0 THEN _nHi := 0; END_IF           // 下界钳位 / clamp lower bound
IF _nHi > 31 THEN _nHi := 31; END_IF         // 上界钳位 / clamp upper bound

IF _nLo > _nHi THEN                          // 钳位后区间为空 / empty range after clamping
    eErr   := 16#0001_1A01;                  // 置区间为空故障码 / set empty-range code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return value not usable
    RETURN;                                  // 返回值保持全 0 掩码 / return stays zero mask
END_IF

_dwBit := SHL(DWORD#16#0000_0001, _nLo);     // 单比特走到起始位（_nLo≤31 安全）/ walk bit to start
FOR _i := _nLo TO _nHi DO                    // 逐位置 1 / set bits one by one
    FC_DL_BitMaskRange := FC_DL_BitMaskRange OR _dwBit;    // 并入当前位 / merge current bit
    _dwBit := SHL(_dwBit, 1);                // 单比特左移一位，循环内 _i<_nHi≤31 安全 / shift walker left
END_FOR

END_FUNCTION
