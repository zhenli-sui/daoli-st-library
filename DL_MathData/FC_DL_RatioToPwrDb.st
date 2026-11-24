(*
    FC_DL_RatioToPwrDb —— 功率比值到 dB（10 因子）
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : dB 为公开工程约定（功率型 10·log10，幅值型 20·log10）；本件为
                R17 件 FC_DL_PwrDbToRatio 的严格逆运算，补齐「功率型反向」缺位；
                定义域闸、零功率下限替代、饱和限与错误分级 100% 自有；
                对数一律委托平台内建 LN 换底，禁多项式重实现（T0 判据 2）；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把功率比值报成 dB，用于射频电源、加热功率、光伏组串失配损耗的查表回算。
                核心防御：① fP2 ≤ 0 或 fP1 < 0 是定义域闸（负功率表示方向而非幅值，
                   比值语义失效），故障级 0324 早退；
                ② fP1 = 0 时按数学真值应为 -∞，本件在取对数之前就走定义域闸，
                   直接输出 fDbFloor（工程替代值）+ 信息 0404，绝不让 -∞ 出现；
                ③ 结果超 ±fDbSpan 双侧钳位，禁 NaN / ±INF 穿透；
                ④ 饱和硬限 380 dB 的可表性反算：380 dB → 10^38 < LREAL 上限，可表；
                   400 dB → 10^40 在 REAL 域不可表，故上限取 380 dB（R63 口径）。
                职责边界：本件只做比值→dB，正向换算归 FC_DL_PwrDbToRatio；参数超域按
                VAR CONSTANT 域钳位，钳位本身不置码（0405 只表结果超 span）。
    错误码    : 16#0001_0404 fP1 = 0，已按 fDbFloor 输出（真 -∞ 的工程替代）——信息级，正常防御
                16#0001_0405 结果超 ±fDbSpan 已钳位（bSaturated = TRUE）——信息级，正常防御
                16#0001_0324 功率非法（fP2 ≤ 0 或 fP1 < 0）——故障级，返回 0.0 且 bValid = FALSE
                16#0001_0325 输入或中间结果非有限（NaN / ±INF）——故障级，返回 0.0
                16#0001_0326 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0404 用 / 16#0001_0405 用 ｜ 16#0001_0324 用 / 16#0001_0325 用 / 16#0001_0326 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION FC_DL_RatioToPwrDb : LREAL
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR_INPUT
    fP1             : LREAL := 1.0;           // 分子功率 [W]，域 0.0~1.0E30，0 合法 / numerator power [W], range 0.0~1.0E30, zero allowed
    fP2             : LREAL := 1.0;           // 分母功率（参考功率）[W]，必须 > 0 / denominator reference power [W], must be > 0
    fDbSpan         : LREAL := 380.0;         // dB 绝对值上限 [dB]，域 1.0~1000.0 / absolute dB span [dB], range 1.0~1000.0
    fDbFloor        : LREAL := -380.0;        // fP1 = 0 时的下限替代值 [dB]，域 -1000.0~0.0 / floor substitute when fP1 = 0 [dB], range -1000.0~0.0
END_VAR
VAR_OUTPUT
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 返回值是否可用 / return value valid flag
    bSaturated      : BOOL;                   // 结果被钳位 / result clamped
    bZeroPower      : BOOL;                   // fP1 = 0，真 -∞ 已按下限替代 / fP1 = 0, true minus infinity replaced by the floor
END_VAR
VAR CONSTANT
    DL_DB_PWR_FACTOR : LREAL := 10.0;         // 功率型 dB 因子 [无量纲] / power dB factor [dimensionless]
    DL_LOG_BASE10    : LREAL := 10.0;         // 换底用对数的底 [无量纲] / logarithm base for the base change [dimensionless]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_DB_SPAN_MIN   : LREAL := 1.0;          // dB 上限最小值 [dB] / minimum dB span [dB]
    DL_DB_SPAN_MAX   : LREAL := 1000.0;       // dB 上限最大值 [dB] / maximum dB span [dB]
    DL_DB_FLOOR_MIN  : LREAL := -1000.0;      // 下限替代值最小值 [dB] / minimum floor substitute [dB]
    DL_DB_FLOOR_MAX  : LREAL := 0.0;          // 下限替代值最大值 [dB] / maximum floor substitute [dB]
    DL_DB_INF_GUARD  : LREAL := 1.0E300;      // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_DB_ZERO       : LREAL := 0.0;          // 零值常量，避免裸字面量 [dB] / zero constant, avoids a bare literal [dB]
END_VAR
VAR
    fRatio          : LREAL;                  // 功率比值 fP1/fP2 [无量纲] / power ratio fP1/fP2 [dimensionless]
    fDb             : LREAL;                  // 计算中的 dB 中间量 [dB] / dB intermediate value [dB]
    fSpanEff        : LREAL;                  // 生效 dB 上限，域钳位后使用 [dB] / effective dB span after clamping [dB]
    fFloorEff       : LREAL;                  // 生效下限替代值，域钳位后使用 [dB] / effective floor substitute after clamping [dB]
    bNonFin         : BOOL;                   // 输入非有限判定标志 / non-finite input flag
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_RatioToPwrDb := DL_DB_ZERO;             // 故障缺省返回 0 dB / fault default returns zero dB
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bSaturated := FALSE;                          // 预置未饱和 / preset not saturated
bZeroPower := FALSE;                          // 预置非零功率 / preset non-zero power

// 段 2｜非有限输入闸（NaN 穿透拦截，先于任何比较与对数）/ segment 2, non-finite input gate
bNonFin := (fP1 <> fP1) OR (fP1 > DL_DB_INF_GUARD) OR (fP1 < -DL_DB_INF_GUARD)
        OR (fP2 <> fP2) OR (fP2 > DL_DB_INF_GUARD) OR (fP2 < -DL_DB_INF_GUARD)
        OR (fDbSpan <> fDbSpan) OR (fDbFloor <> fDbFloor);  // 非有限判定 / non-finite detection
IF bNonFin THEN
    eErr := 16#0001_0325;                     // 输入非有限故障码 / non-finite input fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 3｜定义域闸：分母非正、分子为负均为非法功率语义 / segment 3, domain gate on the powers
IF (fP2 <= DL_DB_ZERO) OR (fP1 < DL_DB_ZERO) THEN
    eErr := 16#0001_0324;                     // 功率非法故障码 / illegal power fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    RETURN;                                   // 故障级提前返回，绝不进入对数 / early return, the logarithm is never executed
END_IF

// 段 4｜参数域钳位（上限、下限替代值各自双侧收敛，钳位本身不置码）/ segment 4, parameter domain clamp
fSpanEff := MIN(MAX(fDbSpan, DL_DB_SPAN_MIN), DL_DB_SPAN_MAX);     // 上限收敛到 1.0~1000.0 dB / converge the span into 1.0~1000.0 dB
fFloorEff := MIN(MAX(fDbFloor, DL_DB_FLOOR_MIN), DL_DB_FLOOR_MAX); // 下限替代收敛到 -1000.0~0.0 dB / converge the floor into -1000.0~0.0 dB

// 段 5｜零功率闸：定义域闸优于事后判 -∞，直接给工程替代值 / segment 5, zero power gate
IF ABS(fP1) <= DL_FLOAT_EPS THEN
    bZeroPower := TRUE;                       // 标记零功率 / flag the zero power
    bValid := TRUE;                           // 替代值可用 / the substitute is usable
    eErr := 16#0001_0404;                     // 信息级：真 -∞ 的工程替代 / info level, engineering substitute for minus infinity
    IF fFloorEff > -fSpanEff THEN
        FC_DL_RatioToPwrDb := fFloorEff;      // 下限未越 span 时按入参输出 / publish the floor when it stays inside the span
    ELSE
        FC_DL_RatioToPwrDb := -fSpanEff;      // 下限越 span 时钳到 -span，保持双侧一致 / clamp to minus span to keep both sides consistent
        bSaturated := TRUE;                   // 标记饱和 / flag the saturation
    END_IF
    RETURN;                                   // 零功率分支出口，不取对数 / exit without taking any logarithm
END_IF

// 段 6｜委托内建 LN 换底（禁多项式重实现）/ segment 6, delegate to the built-in LN with a base change
fRatio := fP1 / fP2;                          // 分母已由段 3 保证 > 0，除法安全 / the denominator is positive by segment 3, the division is safe
fDb := DL_DB_PWR_FACTOR * (LN(fRatio) / LN(DL_LOG_BASE10)); // 10·log10(P1/P2) / 10 log10 of the power ratio

// 段 7｜结果非有限复检 / segment 7, non-finite recheck
IF (fDb <> fDb) OR (fDb > DL_DB_INF_GUARD) OR (fDb < -DL_DB_INF_GUARD) THEN
    eErr := 16#0001_0325;                     // 中间结果非有限故障码 / non-finite intermediate fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    FC_DL_RatioToPwrDb := DL_DB_ZERO;         // 明确返回 0 dB / return zero dB explicitly
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 8｜双侧饱和钳位 / segment 8, two-sided saturation clamp
IF fDb > fSpanEff THEN
    fDb := fSpanEff;                          // 正向超限钳位 / clamp the positive overrun
    bSaturated := TRUE;                       // 标记饱和 / flag the saturation
    eErr := 16#0001_0405;                     // 信息级：超 span 已钳位 / info level, clamped to the span
ELSIF fDb < -fSpanEff THEN
    fDb := -fSpanEff;                         // 负向超限钳位 / clamp the negative overrun
    bSaturated := TRUE;                       // 标记饱和 / flag the saturation
    eErr := 16#0001_0405;                     // 同一业务语义复用同一信息码 / the same semantics reuses the same info id
END_IF

// 段 9｜发布结果 / segment 9, publish the result
FC_DL_RatioToPwrDb := fDb;                    // 输出 dB 值 [dB] / publish the dB value [dB]
bValid := TRUE;                               // 通过全部闸门，结果可用 / all gates passed, the result is usable
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION
