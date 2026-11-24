(*
    FB_DL_ExternalEncoderScaler —— 外部编码器折算
    ------------------------------------------------------------------
    分类      : DL_Motion / Feedback
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 只借「外部编码器属运动层反馈、可独立成块」的分类事实（公开运动控制示例
                的组织划分）；回绕展开算法、折算链顺序、错误分级与码位 100% 自有；
                本件不自造轴状态、不发运动指令、不消费任何厂商轴接口；
                clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把外部编码器原始计数折算成工程量（mm / 度），含分辨率、传动比、导程三段
                折算与 32 位计数器回绕展开（不展开则多圈坐标每转一圈就跳变）。
                **本件最易错的一行**：回绕判据必须先做 DINT 减法、再升位到 LINT——
                先升位再减会让 32 位回绕变成巨大正数（R68 硬纪律）。
                其余防御：① 分辨率或导程为 0 即故障级（除零唯一出口），输出冻结；
                ② 传动比分子或分母为 0 即故障级 02DF；
                ③ 计数器位宽越域只钳位并置信息码（钳位后回绕判据仍可用，不必停功能）；
                ④ 首拍只装初值、不产生回绕事件；
                ⑤ 折算结果非有限即故障级并保持末次有效位置——掉成 0 会被上层当成真实回零。
                规格补正：fVelocity [mm/s] 需要时间基准，派单未给采样周期引脚，特补
                tSampleTime（否则速度只能伪造），收口报告留档。
                职责边界：卷径/张力等工艺量归各自工艺件，本件只出位置与速度。
    错误码    : 16#0004_01CD 检测到计数回绕已展开 / 位宽参数超域已钳位——信息级，正常防御
                16#0004_01CE 预留禁用（信息级，不得挪用）
                16#0004_02DE 分辨率或导程非法（为 0 / 非有限）——故障级，输出冻结
                16#0004_02DF 传动比分子或分母为 0——故障级，输出冻结
                16#0004_02E0 折算结果非有限——故障级，保持末次有效位置
    码位总账  : 16#0004_01CD 用 / 16#0004_01CE 预留 ｜ 16#0004_02DE 用 / 16#0004_02DF 用 / 16#0004_02E0 用
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
                （首拍由单比特 bInit 承载，非顺序状态机）
    采样约定  : fbTrigReset 在本体首部无条件刷新；速度由相邻拍位置差分除以 tSampleTime 得到，
                采样周期为 0 时速度置 0（不做除零），位置折算与之无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION_BLOCK FB_DL_ExternalEncoderScaler
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 输出冻结 / enable, FALSE freezes the outputs
    bReset          : BOOL;                   // 复位，上升沿清多圈展开与零点 / reset, rising edge clears the multi-turn unfolding and the datum
    diRawCount      : DINT := 0;              // 原始计数（编码器直接读出的 32 位值）[count] / raw count read from the encoder [count]
    uCountsPerRev   : UDINT := 4096;          // 每转计数 [count/rev]，必须 > 0 / counts per revolution [count/rev], must be > 0
    fPitch          : REAL := 5.0;            // 每转行程（丝杠导程 / 辊周长）[mm/rev]，必须 > 0 / travel per revolution [mm/rev], must be > 0
    iGearNum        : INT := 1;               // 传动比分子 [无量纲]，必须 != 0 / gear ratio numerator [dimensionless], must be nonzero
    iGearDen        : INT := 1;               // 传动比分母 [无量纲]，必须 != 0 / gear ratio denominator [dimensionless], must be nonzero
    bInvert         : BOOL := FALSE;          // TRUE = 方向取反 / TRUE inverts the direction
    fOffset         : REAL := 0.0;            // 零点偏置 [mm] / datum offset [mm]
    nMultiTurnBits  : INT := 32;              // 计数器位宽 [bit]，范围 8~32 / counter width [bit], range 8~32
    tSampleTime     : TIME := T#10MS;         // 采样周期（规格补正引脚，速度折算用）[ms]，范围 1~1000 / sample time, a spec correction pin used by the velocity conversion [ms], range 1~1000
END_VAR
VAR_OUTPUT
    fPosition       : REAL;                   // 折算后工程量 [mm] / converted engineering position [mm]
    liTotalCount    : LINT;                   // 展开后的多圈累计计数 [count] / unfolded multi-turn accumulated count [count]
    bWrapped        : BOOL;                   // 本拍检测到回绕（单周期脉冲）/ a wrap was detected in this cycle, single-cycle pulse
    uWrapCount      : UDINT;                  // 累计回绕次数，饱和 [次] / accumulated wrap count, saturating [times]
    fVelocity       : REAL;                   // 相邻拍差分估计速度（仅供监视）[mm/s] / velocity estimated from consecutive cycles, monitoring only [mm/s]
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 输出是否可用 / output valid flag
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    diPrevRaw       : DINT;                   // 上一拍原始计数 [count] / previous raw count [count]
    liAccum         : LINT;                   // 多圈累计计数 [count] / multi-turn accumulated count [count]
    liDelta         : LINT;                   // 单拍计数增量（升位后）[count] / per cycle increment widened to LINT [count]
    liHalfSpan      : LINT;                   // 半量程（2^(位宽-1)）[count] / half span of the counter [count]
    liFullSpan      : LINT;                   // 全量程（2^位宽）[count] / full span of the counter [count]
    nDelta          : DINT;                   // 单拍计数增量（先做 DINT 减法）[count] / per cycle increment computed in DINT first [count]
    nBitsEff        : INT;                    // 钳位后的计数器位宽 [bit] / clamped counter width [bit]
    fRatio          : REAL;                   // 圈数（含小数）[rev] / revolution count including the fraction [rev]
    fGear           : REAL;                   // 传动比（分子/分母）[无量纲] / gear ratio, numerator over denominator [dimensionless]
    fSign           : REAL;                   // 方向符号 [+1 / -1] / direction sign, plus or minus one
    fPos            : REAL;                   // 折算位置中间量 [mm] / converted position intermediate [mm]
    fDtSec          : REAL;                   // 采样周期秒值 [s] / sample time in seconds [s]
    fPrevPos        : REAL;                   // 上一拍位置 [mm] / previous position [mm]
    bInit           : BOOL := FALSE;          // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    nDtMs           : DINT;                   // 采样周期毫秒整数 [ms] / sample time in integer milliseconds [ms]
END_VAR
VAR CONSTANT
    DL_EES_CPR_MIN   : UDINT := 1;            // 每转计数下限 [count/rev] / counts per revolution lower bound [count/rev]
    DL_EES_BITS_MIN  : INT := 8;              // 计数器位宽下限 [bit] / counter width lower bound [bit]
    DL_EES_BITS_MAX  : INT := 32;             // 计数器位宽上限 [bit] / counter width upper bound [bit]
    DL_EES_CNT_MAX   : UDINT := 16#FFFF_FFFE; // 回绕计数饱和值 [次] / wrap counter saturation value [times]
    DL_EES_DT_MIN    : TIME := T#1MS;         // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_EES_DT_MAX    : TIME := T#1S;          // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_EES_INF_GUARD : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_EES_MS_PER_S  : REAL := 1000.0;        // 毫秒到秒换算因子 [ms/s] / milliseconds per second [ms/s]
    DL_EES_TWO       : LINT := 2;             // 整型二值常量，量程倍数用 [无量纲] / integer two used for the span multiples
    DL_EES_ONE       : LINT := 1;             // 整型一值常量，位运算基底 [无量纲] / integer one used as the shift base
    DL_EES_SIGN_POS  : REAL := 1.0;           // 正向符号 [+1] / positive direction sign
    DL_EES_SIGN_NEG  : REAL := -1.0;          // 反向符号 [-1] / negative direction sign
    DL_EES_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_EES_ZERO_L    : LINT := 0;             // LINT 零值常量 [count] / LINT zero constant [count]
    DL_EES_ZERO_U    : UDINT := 0;            // UDINT 零值常量 [无量纲] / UDINT zero constant [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置（fPosition / liTotalCount 为保持量，故障时须保末值）/ segment 2, preset outputs, the held values are kept
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用 / preset invalid
bWrapped := FALSE;                            // 单周期脉冲先清 / clear the single-cycle pulse

// 段 3｜参数闸一：分辨率与导程（除零唯一出口）/ segment 3, resolution and pitch gate
IF (uCountsPerRev < DL_EES_CPR_MIN)
   OR (fPitch <= DL_FLOAT_EPS)
   OR (fPitch <> fPitch) OR (fPitch > DL_EES_INF_GUARD) OR (fPitch < -DL_EES_INF_GUARD) THEN
    eErr := 16#0004_02DE;                     // 分辨率或导程非法故障码 / resolution or pitch fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 输出冻结 / the output stays frozen
    RETURN;                                   // 故障级提前返回，不进入任何除法 / early return before any division
END_IF

// 段 4｜参数闸二：传动比分子分母非零 / segment 4, gear ratio gate
IF (iGearNum = 0) OR (iGearDen = 0) THEN
    eErr := 16#0004_02DF;                     // 传动比为 0 故障码 / zero gear ratio fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 输出冻结 / the output stays frozen
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜位宽钳位（钳位后回绕判据仍可用，不必停功能）/ segment 5, width clamping
nBitsEff := nMultiTurnBits;                   // 取入参副本 / copy the input
IF nBitsEff < DL_EES_BITS_MIN THEN
    nBitsEff := DL_EES_BITS_MIN;              // 位宽下限钳位 / clamp at the lower bound
    eErr := 16#0004_01CD;                     // 信息级：位宽超域已钳位 / info level, the width was clamped
ELSIF nBitsEff > DL_EES_BITS_MAX THEN
    nBitsEff := DL_EES_BITS_MAX;              // 位宽上限钳位 / clamp at the upper bound
    eErr := 16#0004_01CD;                     // 信息级：位宽超域已钳位 / info level, the width was clamped
END_IF

// 段 6｜半量程与全量程（LINT 承载，避开 2^31 在 DINT 域溢出）/ segment 6, half and full span in LINT
liHalfSpan := SHL(DL_EES_ONE, nBitsEff - 1);  // 2^(位宽-1)，移位量 <= 31 结构性安全 / two to the width minus one, the shift never exceeds 31
liFullSpan := liHalfSpan * DL_EES_TWO;        // 2^位宽 / two to the width

// 段 7｜使能闸：失能冻结输出 / segment 7, enable gate freezes the outputs
IF NOT bEnable THEN
    RETURN;                                   // 失能即出口，输出保持 / disabled is the exit, the outputs are held
END_IF

// 段 8｜首扫初始化：只装初值，不产生回绕事件 / segment 8, first-scan initialisation without a wrap event
IF NOT bInit THEN
    liAccum := DL_EES_ZERO_L;                 // 累计计数清零 / clear the accumulated count
    diPrevRaw := diRawCount;                  // 原始计数基准装载 / load the raw count reference
    fPrevPos := fOffset;                      // 位置基准取偏置 / the position reference starts at the offset
    uWrapCount := DL_EES_ZERO_U;              // 回绕计数清零 / clear the wrap counter
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
    fPosition := fOffset;                     // 首拍位置即偏置 / the first position equals the offset
    liTotalCount := liAccum;                  // 首拍累计计数输出 / publish the accumulated count
    bValid := TRUE;                           // 首拍输出可用 / the first scan output is usable
    RETURN;                                   // 首拍不做回绕判定 / no wrap detection on the first scan
END_IF

// 段 9｜复位沿：清多圈展开与零点基准 / segment 9, reset clears the unfolding and the datum
IF fbTrigReset.Q THEN
    liAccum := DL_EES_ZERO_L;                 // 累计计数清零 / clear the accumulated count
    diPrevRaw := diRawCount;                  // 基准重装 / reload the reference
    fPrevPos := fOffset;                      // 位置基准回偏置 / the position reference returns to the offset
    uWrapCount := DL_EES_ZERO_U;              // 回绕计数清零 / clear the wrap counter
END_IF

// 段 10｜回绕展开（R68 硬纪律：先做 DINT 减法，再升位比较）/ segment 10, wrap unfolding, subtract first then widen
nDelta := diRawCount - diPrevRaw;             // 先做 32 位减法：回绕在此自然发生 / the 32-bit subtraction comes first, the wrap happens here naturally
diPrevRaw := diRawCount;                      // 立即更新基准 / update the reference immediately
liDelta := DINT_TO_LINT(nDelta);              // 减法之后才升位，顺序不可颠倒 / widen only after the subtraction
IF liDelta > liHalfSpan THEN
    liDelta := liDelta - liFullSpan;          // 正向回绕展开 / unfold a forward wrap
    bWrapped := TRUE;                         // 标记回绕事件 / flag the wrap event
ELSIF liDelta < -liHalfSpan THEN
    liDelta := liDelta + liFullSpan;          // 反向回绕展开 / unfold a backward wrap
    bWrapped := TRUE;                         // 标记回绕事件 / flag the wrap event
END_IF
liAccum := liAccum + liDelta;                 // 累计计数（LINT 域，长期不溢出）/ accumulate in the LINT domain, no overflow in practice

// 段 11｜回绕计数与信息码 / segment 11, wrap counter and info code
IF bWrapped THEN
    IF uWrapCount < DL_EES_CNT_MAX THEN
        uWrapCount := uWrapCount + 1;         // 饱和加一 / saturating increment
    END_IF
    eErr := 16#0004_01CD;                     // 信息级：检测到回绕已展开 / info level, a wrap was detected and unfolded
END_IF

// 段 12｜三段折算链（分母已由段 3 / 段 4 保证非零）/ segment 12, three stage conversion chain
fRatio := LINT_TO_REAL(liAccum) / UDINT_TO_REAL(uCountsPerRev); // 圈数（含小数）[rev] / revolutions including the fraction [rev]
fGear := INT_TO_REAL(iGearNum) / INT_TO_REAL(iGearDen);         // 传动比 [无量纲] / gear ratio [dimensionless]
IF bInvert THEN
    fSign := DL_EES_SIGN_NEG;                 // 方向取反 / invert the direction
ELSE
    fSign := DL_EES_SIGN_POS;                 // 方向保持 / keep the direction
END_IF
fPos := fRatio * fPitch * fGear * fSign + fOffset; // 位置折算 [mm] / convert to the engineering position [mm]

// 段 13｜结果非有限闸：保持末次有效位置（掉成 0 会被当成真实回零）/ segment 13, non-finite gate holds the last position
IF (fPos <> fPos) OR (fPos > DL_EES_INF_GUARD) OR (fPos < -DL_EES_INF_GUARD) THEN
    eErr := 16#0004_02E0;                     // 折算结果非有限故障码 / non-finite conversion fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 输出不可用 / the output is not usable
    RETURN;                                   // fPosition 保持末次有效值 / fPosition keeps its last valid value
END_IF

// 段 14｜速度差分（采样周期为 0 时置 0，不做除零）/ segment 14, velocity by difference with a guarded divisor
nDtMs := TIME_TO_DINT(tSampleTime);           // 采样周期整数毫秒 [ms] / sample time in integer milliseconds [ms]
IF (nDtMs > 0) AND (tSampleTime >= DL_EES_DT_MIN) AND (tSampleTime <= DL_EES_DT_MAX) THEN
    fDtSec := DINT_TO_REAL(nDtMs) / DL_EES_MS_PER_S; // 换算为秒 [s] / convert to seconds [s]
    fVelocity := (fPos - fPrevPos) / fDtSec;  // 差分速度 [mm/s] / differential velocity [mm/s]
ELSE
    fVelocity := DL_EES_ZERO;                 // 周期非法则速度不可信，输出 0 / an illegal period makes the velocity untrustworthy, output zero
END_IF

// 段 15｜发布结果 / segment 15, publish the results
fPosition := fPos;                            // 输出折算位置 [mm] / publish the converted position [mm]
liTotalCount := liAccum;                      // 输出多圈累计计数 [count] / publish the accumulated count [count]
fPrevPos := fPos;                             // 记录为下一拍差分基准 / remember it for the next difference
bValid := TRUE;                               // 通过全部闸门，输出可用 / all gates passed, the output is usable
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION_BLOCK
