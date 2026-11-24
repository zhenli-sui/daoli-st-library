(*
    FC_DL_TimeClampEx —— TIME 三参钳制（跨平台 LIMIT 等价实现）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （LIMIT(MN, IN, MX) 的 TIME 版本；部分平台只对数值类型定义
                  LIMIT / MAX / MIN，对 TIME 未定义或不接受混型实参，故以纯比较式
                  等价实现，禁用任何平台内建 LIMIT，保证四平台行为逐字一致；
                  clean-room 编写，未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R69 构建轮 · 批 1 · N2）
    ------------------------------------------------------------------
    功能说明  : 把时长钳在 [tMin, tMax] 闭区间内。跨平台口径说明（这是本件存在的
                唯一理由）：IEC 61131-3 对 LIMIT 只给出数值类型形式，TIME 实参在
                CODESYS 上可编译而在部分平台直接报「不支持的类型组合」，现场
                换平台时同一行代码从「可编译」变成「编译失败」，属不可移植风险。
                本件以两条比较改写，语义与 LIMIT 逐字等价：
                IN < MN -> MN ；IN > MX -> MX ；区间内直通。
                区间序闸：tMin > tMax 视为组态非法（区间退化 / 反向），**禁入**并
                报故障级；故障缺省返回 tMin（安全侧：钳制件的安全端是下限，避免
                把「区间填反」放大成「超长保持」）。tMin = tMax 是合法退化区间
                （退化为定值），不报码。
                越界钳位报信息级（值可用），区间内直通不报码。
    错误码    : 16#0001_03F9 钳位区间非法（tMin > tMax），输出 tMin —— 故障级
                16#0001_04F7 输入越界已被钳制（bClamped 可查）—— 信息级，值可用
    码位总账  : 16#0001_03F9 用 ｜ 16#0001_04F7 用
    状态机    : R6 标注 N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 无定时器 / 无沿检测 / 无跨周期状态，结论与任务周期无关
    修订记录  : 2026-11-22 v1.0.0 首次入库（R69 构建轮 · 批 1 · N2）
*)
FUNCTION FC_DL_TimeClampEx : TIME
VAR_INPUT
    tIn   : TIME;                              // 待钳制时长 [ms] / duration to clamp [ms]
    tMin  : TIME;                              // 区间下限（含） [ms] / lower bound, inclusive [ms]
    tMax  : TIME;                              // 区间上限（含） [ms] / upper bound, inclusive [ms]
END_VAR
VAR_OUTPUT
    eErr     : UDINT;                          // 错误码，0 = 正常 / error id, 0 = ok
    bError   : BOOL;                           // 故障标志，仅故障级码置 TRUE / error flag, TRUE on fault level only
    bValid   : BOOL;                           // 返回值可用（故障级为 FALSE）/ return usable, FALSE on fault level
    bClamped : BOOL;                           // 本次发生了钳制 / a clamp actually happened
END_VAR
VAR CONSTANT
    DL_TC_ZERO : TIME := T#0S;                 // TIME 零值常量（占位，不参与钳制） [ms] / TIME zero constant
END_VAR

// 段 1｜返回值与错误状态预置（实战规则 1①）/ segment 1, preset the return value and the status
FC_DL_TimeClampEx := DL_TC_ZERO;   // 缺省返回 T#0S，过闸后按分支覆盖 [ms] / default T#0S, overwritten below
eErr     := 0;                     // 预置无错误 / preset no error
bError   := FALSE;                 // 预置无故障 / preset no fault
bValid   := FALSE;                 // 预置不可用 / preset unusable
bClamped := FALSE;                 // 预置未钳制 / preset unclamped

// 段 2｜区间序闸：tMin > tMax 属组态非法，禁入（安全侧返回下限）/ segment 2, interval order gate
IF tMin > tMax THEN
    FC_DL_TimeClampEx := tMin;     // 安全侧返回下限，绝不把反向区间放大成超长值 [ms] / safe side returns the lower bound
    eErr   := 16#0001_03F9;        // 故障级：钳位区间非法 / fault level: illegal clamp interval
    bError := TRUE;                // R45 配对 / paired with the code
    bValid := FALSE;               // 返回值不可用 / return unusable
    RETURN;                        // 出口 / exit
END_IF

// 段 3｜钳制主体：两条比较改写，语义与 LIMIT(MN, IN, MX) 逐字等价 / segment 3, clamp body
IF tIn < tMin THEN
    FC_DL_TimeClampEx := tMin;     // 低于下限：钳到下限 [ms] / below the floor, clamp up
    bClamped := TRUE;              // 钳制发生 / clamp happened
    eErr     := 16#0001_04F7;      // 信息级：输入越界已钳制 / info level: input out of range, clamped
ELSIF tIn > tMax THEN
    FC_DL_TimeClampEx := tMax;     // 高于上限：钳到上限 [ms] / above the ceiling, clamp down
    bClamped := TRUE;              // 钳制发生 / clamp happened
    eErr     := 16#0001_04F7;      // 信息级：输入越界已钳制 / info level: input out of range, clamped
ELSE
    FC_DL_TimeClampEx := tIn;      // 区间内（含两端）直通 [ms] / inside the interval, pass through
END_IF

bError := FALSE;   // 信息级钳制不置故障（钳制是防御而非故障）/ info-level clamping is a defence, not a fault
bValid := TRUE;    // 三条分支的输出均可用 / usable in all three branches
END_FUNCTION
