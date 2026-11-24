(*
    FC_DL_TimeMulSat —— TIME 整数乘法（乘数域闸 + 溢出饱和）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （对照 IEC 61131-3 第 3 版 MUL_TIME 标准语义，委托平台内建 `*`
                  与 `/` 运算符，外围全部闸门 / 饱和 / 码位 / 双语文档 100% 自有；
                  clean-room 编写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache）
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R69 构建轮 · 批 1 · N1）
    ------------------------------------------------------------------
    功能说明  : TIME × 乘数。与库内既有 FC_DL_TimeScaleSat 的分工：ScaleSat 是
                「负乘子钳零、双乘子全放行」的宽松包装；本件是 MUL_TIME 的**严格域闸**
                版本——负乘子属于语义非法（时长无负语义）必须**禁入**并报故障级，
                乘数超 INT 正域上界（32767）同样禁入（防以超域乘子绕过溢出预判），
                只有域内合法乘子才进入乘法内核。
                溢出预判采用除法比较口径（R54 / 实战规则 6）：`tIn > MAX / nScale`，
                比较表达式中不出现乘 / 加运算符，命中即饱和夹 LTIME 上界并报信息级。
                乘数域上界反算依据（实战规则 9）：TIME 为 32 位毫秒容器
                （上限 4294967295 ms ≈ T#49D17H2M47S295MS），乘子上界取 32767（INT 正域）
                是为让 `MAX / nScale` 恒有整数解且不产生 0 除；乘子更大时预判式
                本身会因整数除法结果为 0 而把一切非零时长误判为溢出，故必须在域闸
                先行禁入，不得放大上界。
    错误码    : 16#0001_03F7 负乘子禁入（语义非法），输出 T#0S —— 故障级
                16#0001_03F8 乘子超上界 32767，输出 T#0S —— 故障级
                16#0001_04F6 乘法溢出，输出已饱和至 TIME 上界 —— 信息级，值可用
    码位总账  : 16#0001_03F7 / 03F8 用 ｜ 16#0001_04F6 用
    状态机    : R6 标注 N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 无定时器 / 无沿检测 / 无跨周期状态，结论与任务周期无关
    修订记录  : 2026-11-22 v1.0.0 首次入库（R69 构建轮 · 批 1 · N1）
*)
FUNCTION FC_DL_TimeMulSat : TIME
VAR_INPUT
    tIn     : TIME;                            // 被乘时长 [ms] / multiplicand duration [ms]
    diScale : DINT;                            // 乘数 [倍]，域 0..32767，负值与超上界禁入 / scale factor [x], domain 0..32767
END_VAR
VAR_OUTPUT
    eErr        : UDINT;                       // 错误码，0 = 正常 / error id, 0 = ok
    bError      : BOOL;                        // 故障标志，故障级码时为 TRUE / error flag, TRUE on fault level
    bValid      : BOOL;                        // 返回值可用（故障级为 FALSE）/ return usable, FALSE on fault level
    bSaturated  : BOOL;                        // 已饱和至 TIME 上界 / saturated at the TIME ceiling
END_VAR
VAR CONSTANT
    DL_TM_MAX   : TIME := T#49D17H2M47S295MS;  // 32 位 TIME 容器上限，等价 4294967295 ms [ms] / 32-bit TIME ceiling [ms]
    DL_TM_ZERO  : TIME := T#0S;                // TIME 零值（故障缺省返回） [ms] / TIME zero, the fault default
    DL_TM_SCALE_MAX : DINT := 32767;           // 乘数上界 [倍]，INT 正域上界（反算依据见头注释）/ scale ceiling [x]
    DL_TM_SCALE_MIN : DINT := 0;               // 乘数下界 [倍]，负值禁入 / scale floor [x]
END_VAR
VAR
    nScaleInt : INT;                           // 域内乘数（已过闸，可直接参与 TIME 运算）[倍] / in-domain scale as INT
END_VAR

// 段 1｜返回值与错误状态预置（实战规则 1① 四段式第一段）/ segment 1, preset return and status
FC_DL_TimeMulSat := DL_TM_ZERO;   // 故障缺省返回 T#0S [ms] / fault default returns T#0S
eErr       := 0;                  // 预置无错误 / preset no error
bError     := FALSE;              // 预置无故障 / preset no fault
bValid     := FALSE;              // 预置不可用，过闸后置位 / preset unusable, set TRUE after the gates
bSaturated := FALSE;              // 预置未饱和 / preset not saturated

// 段 2｜乘数域闸：负值禁入（语义非法）/ segment 2, scale domain gate, negative is refused
IF diScale < DL_TM_SCALE_MIN THEN
    eErr   := 16#0001_03F7;       // 故障级：负乘子禁入 / fault level: negative factor refused
    bError := TRUE;               // R45 配对置故障标志 / raise the error flag, paired with the code
    bValid := FALSE;              // 返回值不可用 / return unusable
    RETURN;                       // 出口，不触碰乘法内核 / exit, the kernel is never touched
END_IF

// 段 3｜乘数域闸：超上界禁入（防以超域乘子绕过溢出预判）/ segment 3, upper domain gate
IF diScale > DL_TM_SCALE_MAX THEN
    eErr   := 16#0001_03F8;       // 故障级：乘子超上界 / fault level: factor above the ceiling
    bError := TRUE;               // R45 配对 / paired with the code
    bValid := FALSE;              // 返回值不可用 / return unusable
    RETURN;                       // 出口 / exit
END_IF
nScaleInt := DINT_TO_INT(diScale);   // 域内乘数降为 INT（域已证 <= 32767，无窄化风险）[倍] / in-domain scale to INT

// 段 4｜零乘子：合法零乘，输出 T#0S 且无码（零乘不是错误）/ segment 4, legal zero multiply
IF nScaleInt = 0 THEN
    FC_DL_TimeMulSat := DL_TM_ZERO;   // 零乘结果 [ms] / zero product
    bValid := TRUE;                   // 零是可用结果 / zero is a usable result
    RETURN;                           // 出口 / exit
END_IF

// 段 5｜溢出预判（除法比较口径）+ 域内委托乘法内核 / segment 5, divide-compare pre-check then delegate
IF tIn > (DL_TM_MAX / nScaleInt) THEN
    FC_DL_TimeMulSat := DL_TM_MAX;    // 预判命中：饱和夹上界（除子 nScaleInt > 0 恒非零）[ms] / saturate to the ceiling
    eErr       := 16#0001_04F6;       // 信息级：乘法溢出已饱和 / info level: overflow saturated
    bSaturated := TRUE;               // 饱和标志供上层计量 / saturation flag for the caller
ELSE
    FC_DL_TimeMulSat := tIn * nScaleInt;   // 域内委托 `*` 运算符内核 [ms] / in-domain multiplication kernel
END_IF
bError := FALSE;   // 信息级饱和不置故障（饱和是防御而非故障）/ info-level saturation is a defence, not a fault
bValid := TRUE;    // 域内或饱和输出均可用 / usable in the in-domain and the saturated path
END_FUNCTION
