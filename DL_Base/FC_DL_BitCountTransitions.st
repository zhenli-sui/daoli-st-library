(*==============================================================================
 * 名称 : FC_DL_BitCountTransitions —— WORD 相邻位跳变统计（总跳变 / 上升 / 下降）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 单趟扫描 WORD 的 15 对相邻位（bit i-1 → bit i，i=1..15），统计
 *            跳变总次数并分解为上升（0→1）与下降（1→0）计数；恒有
 *            nRise + nFall = 返回值（调用方可据此自证）。
 *            边界处理：全 0 / 全 1 输入无跳变，三项全 0，属合法结果。
 * 错误码 : 无故障路径（全值域合法的纯统计），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A07 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量≤15 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BitCountTransitions : INT
VAR_INPUT
    wWord : WORD;      // 待统计的输入字 [位域] / input word to be analyzed
END_VAR
VAR_OUTPUT
    nRise : INT;       // 0→1 上升跳变次数 [次] / number of rising transitions
    nFall : INT;       // 1→0 下降跳变次数 [次] / number of falling transitions
    eErr  : UDINT;     // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError: BOOL;      // 故障标志，恒 FALSE / error flag, always FALSE
    bValid: BOOL;      // TRUE=三项计数可用，恒 TRUE / TRUE when counts are usable
END_VAR
VAR
    _i     : INT;      // 位对扫描游标（取 bit i 与 bit i-1）[位] / pair scan cursor
    _wBit  : WORD;     // 当前位单比特掩码 [位域] / single-bit mask of current bit
    _wPrev : WORD;     // 前一位单比特掩码 [位域] / single-bit mask of previous bit
    _xCur  : BOOL;     // 当前位电平 / level of current bit
    _xPrev : BOOL;     // 前一位电平 / level of previous bit
END_VAR

FC_DL_BitCountTransitions := 0;              // 返回值（总跳变）预设 0 / preset total to zero
nRise := 0;                                  // 上升计数清零 / clear rise count
nFall := 0;                                  // 下降计数清零 / clear fall count
eErr  := 16#0000_0000;                       // 故障码清零 / clear error code
bError:= FALSE;                              // 故障标志清零 / clear error flag
bValid:= TRUE;                               // 本件全值域合法，恒可用 / always valid

FOR _i := 1 TO 15 DO                         // 扫描 15 对相邻位 / scan the 15 adjacent pairs
    _wBit  := SHL(WORD#16#0001, _i);         // 当前位掩码（_i≤15 安全）/ mask of current bit
    _wPrev := SHL(WORD#16#0001, _i - 1);     // 前一位掩码（i-1≥0 安全）/ mask of previous bit
    _xCur  := (wWord AND _wBit)  <> WORD#16#0000;    // 取当前位电平 / sample current bit
    _xPrev := (wWord AND _wPrev) <> WORD#16#0000;    // 取前一位电平 / sample previous bit
    IF _xCur AND (NOT _xPrev) THEN           // 0→1 上升沿 / rising transition
        nRise := nRise + 1;                  // 上升计数加一 / bump rise count
    END_IF
    IF (NOT _xCur) AND _xPrev THEN           // 1→0 下降沿 / falling transition
        nFall := nFall + 1;                  // 下降计数加一 / bump fall count
    END_IF
END_FOR

FC_DL_BitCountTransitions := nRise + nFall;  // 恒等式：总跳变 = 上升 + 下降 / invariant: total = rise + fall

END_FUNCTION
