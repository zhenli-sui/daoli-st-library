(*==============================================================================
 * 名称 : FC_DL_BitRunLength —— WORD 最长连续 1 游程长度与起始位号
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 单趟扫描 WORD 的 16 个位，返回最长连续 1 的游程长度（0..16），
 *            并给出该游程的起始位号 nStart（0..15）。多条等长游程取最低起始位。
 *            边界处理：无任何 1 位时返回 0 且 nStart=-1（合法结果，非故障，
 *            bValid 保持 TRUE）；游程到字尾截断同样按已计长度参与比较。
 * 错误码 : 无故障路径（全值域合法的纯统计），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A04 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量≤15 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BitRunLength : INT
VAR_INPUT
    wWord : WORD;      // 待扫描的输入字 [位域] / input word to be scanned
END_VAR
VAR_OUTPUT
    nStart : INT;      // 最长游程起始位号，无 1 时为 -1 [位] / start bit of longest run, -1 if none
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=返回值可用，恒 TRUE / TRUE when return value is usable
END_VAR
VAR
    _i        : INT;       // 位扫描游标 [位] / bit scan cursor
    _nCur     : INT;       // 当前游程长度 [位] / current run length
    _nCurSt   : INT;       // 当前游程起始位号 [位] / current run start bit
    _nBest    : INT;       // 已发现的最长游程长度 [位] / best run length so far
    _nBestSt  : INT;       // 已发现的最长游程起始位号 [位] / best run start bit so far
    _wBit     : WORD;      // 当前位单比特掩码 [位域] / single-bit mask of current position
    _xBit     : BOOL;      // 当前位电平 / level of current bit
END_VAR

FC_DL_BitRunLength := 0;                     // 返回值预设 0 / preset return to zero
nStart := -1;                                // 起始位预设 -1（无 1 语义）/ preset start to -1
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

_nBest  := 0;                                // 最长游程清零 / clear best length
_nBestSt := -1;                              // 最长游程起始清零 / clear best start
_nCur   := 0;                                // 当前游程清零 / clear current length
_nCurSt := 0;                                // 当前游程起始清零 / clear current start

FOR _i := 0 TO 15 DO                         // 单趟从低位到高位扫描 / single low-to-high pass
    _wBit := SHL(WORD#16#0001, _i);          // 当前位单比特掩码（_i≤15 安全）/ single-bit mask
    _xBit := (wWord AND _wBit) <> WORD#16#0000;    // 取当前位电平 / sample current bit
    IF _xBit THEN                            // 位为 1：游程延续或新开 / bit set: extend or open run
        IF _nCur = 0 THEN
            _nCurSt := _i;                   // 新游程序幕，记起始位 / new run starts here
        END_IF
        _nCur := _nCur + 1;                  // 游程长度加一 / extend run length
        IF _nCur > _nBest THEN               // 严格大于保证等长取最低起始位 / strict gt keeps lowest start on ties
            _nBest   := _nCur;               // 刷新最长游程 / refresh best length
            _nBestSt := _nCurSt;             // 刷新最长游程起始位 / refresh best start bit
        END_IF
    ELSE                                     // 位为 0：当前游程终结 / bit clear: current run ends
        _nCur := 0;                          // 游程长度归零 / reset current length
    END_IF
END_FOR

FC_DL_BitRunLength := _nBest;                // 回写最长游程长度 / write back best length
nStart := _nBestSt;                          // 回写起始位号（无 1 时保持 -1）/ write back start bit

END_FUNCTION
