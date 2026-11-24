(*
    FC_DL_LintToUdintSat —— LINT 到 UDINT 的双向饱和转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 类型定义的道莅防御性实现（LINT 64 位有符号 → UDINT 32 位无符号）；
                库内 FC_DL_LintToDintSat 只有「正向饱和」一个闸，本件补「负值落到无符号域」
                这一独立方向：两向的判据、出口与业务语义完全不同（负计数一律是组态错，
                超顶才是量程溢出）；双向闸、无损模式与错误分级 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把 LINT 域内的计量/累计值安全落到 UDINT 域：负值饱和到 0，超顶饱和到
                4294967295；域内才委托内建 LINT_TO_UDINT（域外调用是三平台回绕行为
                不一致的根源，R56「无符号双分支钳位」同纪律）。
                核心防御：① 比较一律用 LINT 字面量常量，绝不把 UDINT 上限先当 UDINT 再比
                   （隐式升位在跨平台上有歧义）；
                ② 负向/正向各占一条信息码，方向可区分（R56 可 grep 化判据）；
                ③ bRequireLossless = TRUE 时任何饱和即判故障级 0327——计量与结算场景
                   不容许静默截断，宁可停机也不出错的数；
                ④ 域内路径零钳位、零额外比较开销。
                职责边界：有符号域内饱和（LINT→DINT）归 FC_DL_LintToDintSat，本件只管无符号落地。
    错误码    : 16#0001_0406 负向饱和（输入 < 0 → 0），组态错但已安全兜底——信息级，正常防御
                16#0001_0407 正向饱和（输入 > 4294967295 → 上限）——信息级，正常防御
                16#0001_0327 调用方要求无损（bRequireLossless = TRUE）却发生饱和——故障级，bValid = FALSE
                16#0001_0328 预留禁用（故障级，不得挪用）
                16#0001_0329 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0406 用 / 16#0001_0407 用 ｜ 16#0001_0327 用 / 16#0001_0328 预留 / 16#0001_0329 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION FC_DL_LintToUdintSat : UDINT
VAR_INPUT
    liIn            : LINT := 0;              // 输入值 [无量纲]，全域 -2^63~2^63-1 / input value [dimensionless], full LINT domain
    bRequireLossless : BOOL := FALSE;         // TRUE = 发生任何饱和即判故障（计量/累计场景）/ TRUE turns any saturation into a fault for metering use
END_VAR
VAR_OUTPUT
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 返回值是否可用（饱和且要求无损时为 FALSE）/ return usable, FALSE when saturated in lossless mode
    bSatLow         : BOOL;                   // 负向饱和发生（输入 < 0）/ negative saturation occurred, input < 0
    bSatHigh        : BOOL;                   // 正向饱和发生（输入 > 4294967295）/ positive saturation occurred, input > 4294967295
END_VAR
VAR CONSTANT
    DL_UDINT_MAX_AS_LINT : LINT := 4294967295; // UDINT 上限的 LINT 形态 [无量纲] / the UDINT maximum expressed as LINT [dimensionless]
    DL_LINT_ZERO         : LINT := 0;          // 有符号零常量，避免裸字面量 [无量纲] / signed zero constant, avoids a bare literal [dimensionless]
    DL_UDINT_MAX         : UDINT := 16#FFFF_FFFF; // UDINT 上限值 [无量纲] / the UDINT maximum value [dimensionless]
    DL_UDINT_ZERO        : UDINT := 0;         // 无符号零常量 [无量纲] / unsigned zero constant [dimensionless]
END_VAR
VAR
    liWork          : LINT;                   // 输入副本，避免改动调用方数据 [无量纲] / input copy, never modifies caller data [dimensionless]
    uResult         : UDINT;                  // 转换结果中间量 [无量纲] / conversion result intermediate [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LintToUdintSat := DL_UDINT_ZERO;        // 故障缺省返回 0 / fault default returns zero
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bSatLow := FALSE;                             // 预置未负向饱和 / preset no negative saturation
bSatHigh := FALSE;                            // 预置未正向饱和 / preset no positive saturation
uResult := DL_UDINT_ZERO;                     // 结果中间量清零 / clear the result intermediate

// 段 2｜负向闸门（负计数落到无符号域即组态错，先于正向判定）/ segment 2, negative gate
liWork := liIn;                               // 取入参副本参与比较 / copy the input for the comparisons
IF liWork < DL_LINT_ZERO THEN
    uResult := DL_UDINT_ZERO;                 // 负值饱和到 0 / saturate a negative value to zero
    bSatLow := TRUE;                          // 标记负向饱和 / flag the negative saturation
    eErr := 16#0001_0406;                     // 信息级：组态错但已安全兜底 / info level, configuration error handled safely
ELSE
    // 段 3｜正向闸门（用 LINT 字面量比较，绝不先转无符号再比）/ segment 3, positive gate
    IF liWork > DL_UDINT_MAX_AS_LINT THEN
        uResult := DL_UDINT_MAX;              // 超顶饱和到 4294967295 / saturate an overrun to the UDINT maximum
        bSatHigh := TRUE;                     // 标记正向饱和 / flag the positive saturation
        eErr := 16#0001_0407;                 // 信息级：量程溢出已兜底 / info level, range overrun handled safely
    ELSE
        // 段 4｜域内才委托内建（域外调用是三平台回绕不一致的根源）/ segment 4, delegate only inside the domain
        uResult := LINT_TO_UDINT(liWork);     // 域内无损转换 / lossless conversion inside the domain
        eErr := 0;                            // 域内无错误 / in-domain, no error
    END_IF
END_IF

// 段 5｜无损模式复核（要求无损却发生饱和即故障级）/ segment 5, lossless recheck
IF bRequireLossless AND (bSatLow OR bSatHigh) THEN
    eErr := 16#0001_0327;                     // 无损模式下发生饱和故障码 / saturation under lossless requirement
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值标记为不可用 / flag the return as unusable
    FC_DL_LintToUdintSat := uResult;          // 仍返回钳位值，便于 HMI 观察越界量 / still publish the clamped value so HMI can see the overrun
    RETURN;                                   // 出口 / exit
END_IF

// 段 6｜发布结果 / segment 6, publish the result
FC_DL_LintToUdintSat := uResult;              // 输出钳位后的无符号结果 [无量纲] / publish the clamped unsigned result [dimensionless]
bValid := TRUE;                               // 钳位或无损均可用 / usable either clamped or lossless
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION
