(*
    FC_DL_TimeAbsSat —— TIME 绝对值（负 TIME 平台歧义统一口径）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（TIME 取绝对值，含 −MAX−1 边界）；
                委托平台内建 TIME_TO_DINT / DINT_TO_TIME 完成显式换算，本件不重实现时间算术内核；
                负值口径统一、不可表边界饱和、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 偏差、超调、节拍抖动的幅值统计经常要把「正的偏差」与「负的偏差」合成同一量纲。
                但 TIME 在 IEC 61131-3 里是时长型：各平台对负 TIME 的文本解释、比较行为与
                隐式转换口径并不一致（R55 教训），直接用平台取反极易得到一个天文正数。
                本件是负 TIME 口径的原子化统一出口：任何需要幅值的场景都走它，不再就地取反。
                核心防御：① 一切判定都在 DINT 毫秒域内进行，显式 TIME_TO_DINT 取值、
                   显式 DINT_TO_TIME 回装，全程禁隐式转换；
                ② −MAX−1 案先判后算：DINT 最小值的相反数无法用 DINT 表，直接取反会静默
                   回绕成一个负数，故先判边界，再取反；
                ③ 边界判据按「极限值 → 类型可表性」反算，取严格小于 −2147483647：
                   −2147483647 取反得 +2147483647，可表且正确，属正常路径；
                   真正不可表的只有 −2147483648 这一个值，故只有它落饱和出口；
                ④ 饱和时返回正向毫秒上限并升故障级——调用方必须知道这个幅值是钳位值；
                ⑤ 负输入取到幅值后发信息级并置 bNegative，方向信息不丢。
                职责边界：带偏移的时刻算术归 FC_DL_TodAddWrap / FC_DL_TodDiffWrap；
                TIME 与秒的换算归 FC_DL_TimeToLrealSec / FC_DL_LrealSecToTime；
                本件只管「幅值」这一件事。
    编译门槛  : 主路径假设 TIME 以 32 位毫秒（DINT）承载，CODESYS V3.5+ / TwinCAT 3 /
                InoProShop 均为该口径。若目标平台 TIME 为 64 位容器，TIME_TO_DINT 会在
                超出 32 位时截断——此时应改用 64 位换算链，本件的闸门顺序与出口不变。
                饱和值以 DINT 常量经 DINT_TO_TIME 落地，不使用超长 TIME 字面量，
                避免 32 位 TIME 平台上字面量本身无法编译。
    错误码    : 16#0001_042E 输入为负，已取绝对值（bNegative 可查）——信息级，值可用
                16#0001_042F 预留禁用（信息级，不得挪用）
                16#0001_0363 −MAX−1 的绝对值不可用 DINT 表达，已饱和至正向上限——故障级，bValid = FALSE
                16#0001_0364 预留（故障级，不得挪用）
                16#0001_0365 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_042E 用 / 16#0001_042F 预留 ｜ 16#0001_0363 用 / 16#0001_0364 预留 / 16#0001_0365 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_TimeAbsSat : TIME
VAR_INPUT
    tIn              : TIME;                  // 输入时长，可负 [ms]，TIME 平台实现为 32 位毫秒 / input duration, signed [ms], TIME is 32-bit milliseconds on the target platforms
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（饱和时为 FALSE）/ return usable, FALSE when saturated
    bNegative        : BOOL;                  // 输入为负，已取绝对值 / the input was negative and its magnitude is published
END_VAR
VAR CONSTANT
    DL_TIME_MS_POS_MAX : DINT := 2147483647;  // DINT 毫秒正向上限，饱和出口值 [ms] / DINT millisecond top, the saturation value [ms]
    DL_TIME_MS_NEG_SAFE : DINT := -2147483647; // 可安全取负的毫秒下界，即 −MAX [ms] / the lowest value that can be negated safely, minus MAX [ms]
    DL_DINT_ZERO     : DINT := 0;             // 有符号零常量，避免裸字面量 [ms] / signed zero constant [ms]
    DL_TIME_ZERO     : TIME := T#0s;          // 零时长，缺省返回 / zero duration returned by default
END_VAR
VAR
    nIn              : DINT;                  // 输入毫秒中间量 [ms] / input milliseconds intermediate [ms]
    nAbs             : DINT;                  // 绝对值毫秒中间量 [ms] / magnitude intermediate in milliseconds [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeAbsSat := DL_TIME_ZERO;             // 缺省返回零时长 / default returns a zero duration
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bNegative := FALSE;                           // 预置输入非负 / preset a non-negative input
nAbs := DL_DINT_ZERO;                         // 幅值中间量清零 / clear the magnitude intermediate

// 段 2｜取值：显式标准转换，禁隐式 / segment 2, explicit standard conversion, never implicit
nIn := TIME_TO_DINT(tIn);                     // TIME → 毫秒 [ms] / TIME to milliseconds [ms]

// 段 3｜非负直通：幅值即原值，零开销 / segment 3, non-negative pass-through with zero overhead
IF nIn >= DL_DINT_ZERO THEN
    FC_DL_TimeAbsSat := DINT_TO_TIME(nIn);    // 幅值即原值 [ms] / the magnitude is the value itself [ms]
    bValid := TRUE;                           // 直通值可用 / the pass-through value is usable
    RETURN;                                   // 出口 / exit
END_IF

// 段 4｜−MAX−1 边界闸：相反数不可表，先判后算 / segment 4, the unrepresentable boundary gate
IF nIn < DL_TIME_MS_NEG_SAFE THEN
    FC_DL_TimeAbsSat := DINT_TO_TIME(DL_TIME_MS_POS_MAX); // 饱和至正向毫秒上限 [ms] / saturate to the positive millisecond top [ms]
    eErr := 16#0001_0363;                     // 故障级：−MAX−1 的绝对值不可表达 / fault level, the magnitude of minus MAX minus one is not representable
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 饱和值不可作统计依据 / the saturated value must not feed the statistics
    bNegative := TRUE;                        // 输入确实为负 / the input really was negative
    RETURN;                                   // 出口 / exit
END_IF

// 段 5｜正常负值取幅值（此处取反结构性安全：nIn 严格大于可安全下界）/ segment 5, negate a safe negative value
nAbs := -nIn;                                 // 取绝对值 [ms] / take the magnitude [ms]
FC_DL_TimeAbsSat := DINT_TO_TIME(nAbs);       // 回装为时长 [ms] / convert back into a duration [ms]
eErr := 16#0001_042E;                         // 信息级：输入为负，已取绝对值 / info level, the negative input was turned into a magnitude
bNegative := TRUE;                            // 方向信息不丢 / the direction information is kept
bValid := TRUE;                               // 幅值可用 / the magnitude is usable
END_FUNCTION
