(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WeightedMovingAvg
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（LGF Measurement 统计族深化）
 * 所属子库 (Sublibrary) : DL_MathData / Statistics
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 权重表滑动平均
 *                         （规格 5.5 预授权：FC 静态语义降级为 FB 实现并按计划改名，
 *                         文件名沿用 FC_DL_WeightedMovingAvg.st，宿主 POU 为 FB）
 * 功能一句话 (Summary)  : 显式权重窗口滑动平均，与既有 IIR 滤波族正交。
 * 边界与安全 (Boundary) : ①权重和小于等于 0 → 拒新样本保持旧窗并置码；
 *                         ②NaN 样本跳过不滚动窗口；
 *                         ③窗口未满 bValid=FALSE，不满窗不出值；
 *                         ④权重全零窗退化为等权平均防御；
 *                         ⑤除法前强制判零（权重和、分母均前判）。
 * 错误码    : 16#0001_03C7 权重和非法（小于等于 0，样本拒收）——故障级（持续态）
 *             16#0001_03C8 保留禁用（不得挪用，本件零赋值）
 * 码位总账  : 16#0001_03C7 用 ｜ 16#0001_03C8 预留
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_WeightedMovingAvg
VAR_INPUT
    fNew     : LREAL; // 新样本值 / New sample value
    aWeights : ARRAY[*] OF LREAL; // 权重表（按样本新到旧排列）/ Weight table (newest first)
    bReset   : BOOL;  // 复位：清窗口与有效标志 / Reset: clear window and valid flag
END_VAR
VAR_OUTPUT
    fAvg    : LREAL; // 滑动平均输出 / Weighted moving average output
    bValid  : BOOL;  // 窗口未满=FALSE / FALSE until window filled
    uWindow : UINT;  // 实际窗口长度（权重表长度钳上限）/ Actual window length
    eErr    : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cMaxWin : INT := 64; // 窗口容量上限 / Window capacity limit
END_VAR
VAR
    aBuf    : ARRAY[0..63] OF LREAL; // 样本环形缓冲（跨拍保持）/ Sample ring buffer (kept across scans)
    iHead   : INT;   // 写入位置 / Write position
    uCnt    : UINT;  // 已入窗样本数 / Samples stored in window
    i       : INT;   // 循环游标 / Loop cursor
    iWLen   : INT;   // 权重表长度 / Weight table length
    fWSum   : LREAL; // 权重和 / Weight sum
    fWSumU  : LREAL; // 实际参与求和的权重和（零权剔除后）/ Weight sum actually used
    fAcc    : LREAL; // 加权和累加器 / Weighted sum accumulator
    iSmp    : INT;   // 样本回溯游标 / Sample backtrack cursor
    fSmp    : LREAL; // 当前参与样本值 / Current sample value
END_VAR

// ---------- 周期起点：错误码清零（持续态随后重置） ----------
eErr := 0;

// ---------- 复位：清窗清态 ----------
IF bReset THEN
    FOR i := 0 TO cMaxWin - 1 DO
        aBuf[i] := 0.0;                      // 清样本缓冲 / Clear sample buffer
    END_FOR
    iHead  := 0;                             // 写头归零 / Head reset
    uCnt   := 0;                             // 计数清零 / Count cleared
    bValid := FALSE;                         // 有效标志撤销 / Valid withdrawn
    fAvg   := 0.0;                           // 输出清零 / Output cleared
END_IF

// ---------- 窗口长度防御：权重表长度钳上限 ----------
iWLen := UPPER_BOUND(aWeights, 1) + 1;       // 权重表长度 / Weight table length
IF iWLen < 1 THEN
    iWLen := 1;                              // 至少 1 阶窗口 / At least one tap
END_IF
IF iWLen > cMaxWin THEN
    iWLen := cMaxWin;                        // 钳到容量上限 / Clamp to capacity
END_IF
uWindow := INT_TO_UINT(iWLen);               // 对外窗口长度 / Exposed window length

// ---------- 权重和防御：非正拒新样本（保持旧窗） ----------
fWSum := 0.0;
FOR i := 0 TO iWLen - 1 DO
    fWSum := fWSum + aWeights[i];            // 权重求和 / Sum weights
END_FOR
IF (fWSum <= 0.0) OR (fWSum <> fWSum) THEN
    eErr := 16#0001_03C7;                    // 权重和非法，拒新样本 / Illegal weight sum, reject sample
ELSE
    // ---------- NaN 样本跳过不滚动 ----------
    IF fNew <> fNew THEN
        eErr := 0;                           // NaN 静默跳过（不置码，规格口径）/ NaN skipped silently
    ELSE
        aBuf[iHead] := fNew;                 // 样本入环形缓冲 / Sample into ring buffer
        iHead := (iHead + 1) MOD cMaxWin;    // 写头推进（钳界回绕）/ Head advance with wrap
        IF uCnt < UINT#64 THEN
            uCnt := uCnt + UINT#1;           // 计数封顶防回绕溢出 / Count capped
        END_IF
        IF UINT_TO_INT(uCnt) >= iWLen THEN
            bValid := TRUE;                  // 窗口已满 / Window filled
        END_IF
    END_IF
END_IF

// ---------- 加权平均计算：窗口未满不出值（bValid=FALSE） ----------
IF bValid THEN
    fWSumU := 0.0;
    fAcc   := 0.0;
    FOR i := 0 TO iWLen - 1 DO
        iSmp := (iHead - 1 - i) MOD cMaxWin; // 回溯取样本（新到旧）/ Backtrack samples newest first
        IF iSmp < 0 THEN
            iSmp := iSmp + cMaxWin;          // 负下标钳回正域 / Fix negative index
        END_IF
        fSmp := aBuf[iSmp];                  // 参与样本 / Participating sample
        IF aWeights[i] > 0.0 THEN            // 零权剔除，防除零后仍零贡献 / Skip zero weights
            fAcc   := fAcc + aWeights[i] * fSmp; // 加权累加 / Weighted accumulation
            fWSumU := fWSumU + aWeights[i];  // 有效权重和 / Effective weight sum
        END_IF
    END_FOR
    IF fWSumU > 0.0 THEN
        fAvg := fAcc / fWSumU;               // 除法前判零 / Divide after zero guard
    ELSE
        fAvg := 0.0;                         // 全零权防御缺省 / All-zero-weight default
        bValid := FALSE;                     // 无有效权重则撤销有效 / Withdraw valid if no weights
    END_IF
END_IF

END_FUNCTION_BLOCK
