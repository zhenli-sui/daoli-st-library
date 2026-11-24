(*
    FC_DL_DwordToIntSat —— DWORD 到 INT 的降位饱和
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（DWORD 32 位无符号 → INT 16 位有符号）；
                域内委托平台内建 DWORD_TO_INT，本件不重实现数学内核；
                上饱和出口、无损模式复核、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 长计数器、累计电量、批次总数这类 32 位累计值往 16 位 HMI 或老表写时，
                必须显式降位：本件统一取上饱和口径（钳到 32767），不做截断、不做回绕。
                截断会让 HMI 显示成随机跳动的小数，比钳位危险得多。
                核心防御：① 比较一律在 DWORD 字面量常量之间进行，绝不把 INT 上限先当 INT
                   再与 DWORD 比（隐式跨符号域比较在平台间有歧义，R56 纪律）；
                ② 上饱和置 bSatHigh 供 HMI 显示「已封顶」，避免把 32767 误读成真实值；
                ③ bRequireLossless = TRUE 时任何饱和即升故障级——结算与报表场景
                   不容许静默封顶，宁可停机也不出错数；
                ④ 域内路径零钳位、零额外比较开销。
                职责边界：WORD 16 位双语义归 FC_DL_WordToIntSat（它有补码口径），
                LWORD 64 位降位归 FC_DL_LwordToLintSat；本件只管 32 → 16 上饱和。
    编译门槛  : 主路径依赖平台内建 DWORD_TO_INT，IEC 61131-3 标准转换函数，
                三平台标准库均提供，无厂商方言。
    错误码    : 16#0001_0418 超域已饱和至 32767（bSatHigh 可查）——信息级，值可用
                16#0001_0419 预留禁用（信息级，不得挪用）
                16#0001_0342 调用方要求无损（bRequireLossless = TRUE）却发生饱和——故障级，bValid = FALSE
                16#0001_0343 预留（故障级，不得挪用）
                16#0001_0344 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0418 用 / 16#0001_0419 预留 ｜ 16#0001_0342 用 / 16#0001_0343 预留 / 16#0001_0344 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DwordToIntSat : INT
VAR_INPUT
    uIn              : DWORD;                 // 输入值 [无量纲]，全域 0~4294967295 / input value [dimensionless], full DWORD domain
    bRequireLossless : BOOL := FALSE;         // TRUE = 发生饱和即判故障（计量/结算场景）/ TRUE turns any saturation into a fault
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（要求无损却饱和时为 FALSE）/ return usable, FALSE when saturated in lossless mode
    bSatHigh         : BOOL;                  // 上饱和发生（输入 > 32767）/ high saturation occurred
END_VAR
VAR CONSTANT
    DL_INT_MAX_AS_DWORD : DWORD := 32767;     // INT 上限的 DWORD 形态 [无量纲] / the INT maximum expressed as DWORD [dimensionless]
    DL_INT_MAX       : INT := 32767;          // INT 上限值 [无量纲] / the INT maximum value [dimensionless]
    DL_INT_ZERO      : INT := 0;              // 有符号零常量，避免裸字面量 [无量纲] / signed zero constant [dimensionless]
END_VAR
VAR
    nOut             : INT;                   // 结果中间量 [无量纲] / result intermediate [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DwordToIntSat := DL_INT_ZERO;           // 故障缺省返回 0 [无量纲] / fault default returns zero [dimensionless]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bSatHigh := FALSE;                            // 预置未饱和 / preset no saturation
nOut := DL_INT_ZERO;                          // 结果中间量清零 / clear the result intermediate

// 段 2｜降位闸：用 DWORD 字面量比较，禁跨符号域比较 / segment 2, narrowing gate with a DWORD literal comparison
IF uIn > DL_INT_MAX_AS_DWORD THEN
    nOut := DL_INT_MAX;                       // 上饱和至 32767 / saturate to the INT maximum
    bSatHigh := TRUE;                         // 标记上饱和 / flag the high saturation
    eErr := 16#0001_0418;                     // 信息级：超域已饱和 / info level, saturated on the overrun
ELSE
    // 段 3｜域内才委托内建 / segment 3, delegate only inside the domain
    nOut := DWORD_TO_INT(uIn);                // 域内无损降位 [无量纲] / lossless narrowing inside the domain [dimensionless]
END_IF

// 段 4｜无损模式复核（要求无损却发生饱和即故障级）/ segment 4, lossless recheck
IF bRequireLossless AND bSatHigh THEN
    eErr := 16#0001_0342;                     // 故障级：要求无损却发生饱和 / fault level, saturation under the lossless requirement
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可进结算 / the value must not enter settlements
    FC_DL_DwordToIntSat := nOut;              // 仍发布钳位值供 HMI 观察 / still publish the clamped value for observation
    RETURN;                                   // 出口 / exit
END_IF

// 段 5｜发布结果 / segment 5, publish the result
FC_DL_DwordToIntSat := nOut;                  // 输出 16 位有符号结果 [无量纲] / publish the signed 16-bit result [dimensionless]
bValid := TRUE;                               // 直通或钳位均可用 / usable either way
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION
