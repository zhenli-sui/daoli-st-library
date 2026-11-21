(*
    组件名称 : FC_DL_WrapAngleDeg
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 角度归一原子，把任意角度折算到 (−180, 180]（缺省）或 [0, 360)，并顺带出口圈数供多圈相位追溯。
              取舍 ①：禁 MOD —— REAL/LREAL 上的 MOD 在三平台上的「余数符号」与「负零」行为不一致，
              而且 MOD 结果可能给出 -0.0 与 360.0 两种等价表示，会让下游的相等判据抖动。
              本件改用「TRUNC 求整圈数 + 一次条件加减」，最多一次加减即可落到目标半开区间。
              取舍 ②：超可归一域直接报故障而不钳位 —— 角度钳位会静默改变转向语义（-720° 被钳成 -180°
              就成了反向），运动链上这是灾难；宁可停机让调用方查清输入来源。
              取舍 ③：零容差归一为 +0.0 —— 消除 -0.0 与「恰好 360.0」两种抖动值，让下游可以用符号判方向。
              取舍 ④：DL_GUARD_MAX 仅作防御性预留常量而非死代码 —— 本实现全文无循环（条件加减最多一次），
              守卫计数器无使用场景；保留该常量是为了在扩展为多圈归一时有现成的上限口径，
              避免届时再引入裸数值。此处显式留档，不留未解释常量。
    开源溯源 : 原创实现。运动层 CamPhaseTrim / ElectronicCam 反复手写同一段归一并多次留痕，；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              本件为其唯一原子出口。无外部源码参考，码位与分级 100% 自有。
    本文件内含 : FUNCTION FC_DL_WrapAngleDeg（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限闸 + 可归一域闸 + 零容差归一（禁 MOD、禁循环、禁钳位）
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 全部域与容差常量化（含守卫常量用途说明）
    错误码   : 16#0001_043C [信息级] 输入超一圈已归一，bValid = TRUE
               16#0001_043D [信息级] 结果落零容差已归一为 +0.0，bValid = TRUE
               16#0001_0378 [故障级] 输入非有限（NaN 或 ±INF），返回 0，bValid = FALSE
               16#0001_0379 [故障级] 超可归一域（|角度| > DL_ANGLE_ABS_MAX），返回 0，bValid = FALSE
               16#0001_037A [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_043C 用 / 16#0001_043D 用 ｜ 16#0001_0378 用 / 16#0001_0379 用 / 16#0001_037A 预留
    遗留假设 : ① LREAL_TO_DINT 对超出 DINT 域的输入行为未定义，本件已用 DL_ANGLE_ABS_MAX = 1E6 把商限制在 ±2778，
              结构性不进该分支；该上限本身为推导，未三平台实测。
              ② TRUNC 返回值宽度与入参一致（LREAL），用于 LREAL_TO_DINT 前置 —— IEC 语义推导，未逐平台实测。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 1 入库
*)
FUNCTION FC_DL_WrapAngleDeg : LREAL
VAR_INPUT
    fAngleDeg       : LREAL := 0.0;   // 任意角度，有效域 |x| ≤ 1E6 [°] / arbitrary angle, valid up to one million degrees [deg]
    bZeroTo360      : BOOL := FALSE;  // FALSE → (−180, 180]；TRUE → [0, 360) / FALSE gives minus 180 to 180, TRUE gives zero to 360 [range]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;          // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;           // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;           // 归一结果是否可用 / normalised result usable flag
    nTurns          : DINT;           // 圈数，向零取整，供多圈相位追溯 [圈] / completed turns truncated toward zero, for multi-turn phase tracing [turn]
END_VAR
VAR
    fQuot           : LREAL;          // 角 / 360 的商 [圈] / quotient of the angle over one turn [turn]
    fRet            : LREAL;          // 归一结果工作寄存器 [°] / normalisation working register [deg]
    bOverOneTurn    : BOOL;           // 输入绝对值是否已超一圈 / whether the magnitude already exceeds one turn
END_VAR
VAR CONSTANT
    DL_DEG_PER_TURN     : LREAL := 360.0;                      // 一圈的角度 [°] / degrees per turn [deg]
    DL_DEG_HALF_TURN    : LREAL := 180.0;                      // 半圈，区间判定边界 [°] / half turn, the interval boundary [deg]
    DL_ANGLE_ABS_MAX    : LREAL := 1.0E6;                      // 可归一域上限，超此值 LREAL 已无 0.001° 分辨率 [°] / normalisable domain limit [deg]
    DL_FLOAT_EPS        : LREAL := 1.0E-9;                     // 零容差，比 0.001° 分辨率小两个量级 [°] / zero tolerance, two decades below the resolution [deg]
    DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308;     // LREAL 最大有限值 [无量纲] / largest finite LREAL [dimensionless]
    DL_LREAL_ZERO       : LREAL := 0.0;                        // 零哨兵，归一目标值 [无量纲] / zero sentinel and normalisation target [dimensionless]
    DL_GUARD_MAX        : DINT := 1000;                        // 守卫上限预留（本件无循环，见头注释取舍 ④）[次] / reserved guard limit, unused here because there is no loop [count]
    DL_ERR_NONE         : UDINT := 16#0000_0000;               // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_WrapAngleDeg := DL_LREAL_ZERO;    // 故障缺省返回 0 / fault default returns zero
eErr   := DL_ERR_NONE;                  // 预置无错误 / preset no error
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 预置结果不可用 / preset unusable
nTurns := 0;                            // 预置圈数 0 / preset the turn count to zero

// 段 2｜输入有限性闸 / segment 2, input finiteness gate
IF (fAngleDeg <> fAngleDeg) OR (ABS(fAngleDeg) > DL_LREAL_MAX_FINITE) THEN
    eErr   := 16#0001_0378;             // 输入非有限（故障级）/ non-finite input, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 3｜可归一域闸：超域不钳位，钳位会静默改转向 / segment 3, domain gate, clamping would silently flip the direction
IF ABS(fAngleDeg) > DL_ANGLE_ABS_MAX THEN
    eErr   := 16#0001_0379;             // 超可归一域（故障级）/ beyond the normalisable domain, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 4｜整圈剥离：TRUNC 求圈数，再一次性减掉，禁 MOD / segment 4, whole turns stripped with TRUNC, never with MOD
fQuot  := fAngleDeg / DL_DEG_PER_TURN;                                  // 商，域内 |商| ≤ 2778，转换结构性安全 / the quotient stays within plus or minus 2778 by construction
nTurns := LREAL_TO_DINT(TRUNC(fQuot));                                  // 向零取整得圈数 / truncate toward zero to get the turns
fRet   := fAngleDeg - DINT_TO_LREAL(nTurns) * DL_DEG_PER_TURN;          // 剥离整圈后的余量，落在 (−360, 360) / the remainder after stripping whole turns
bOverOneTurn := ABS(fAngleDeg) > DL_DEG_PER_TURN;                       // 记录「曾超一圈」/ remember that the input exceeded one turn

// 段 5｜一次条件加减落到目标半开区间（最多一次，不写循环）/ segment 5, one conditional add or subtract at most
IF fRet > DL_DEG_HALF_TURN THEN
    fRet := fRet - DL_DEG_PER_TURN;     // 上半圈搬下来 / bring the upper half down
ELSIF fRet <= -DL_DEG_HALF_TURN THEN
    fRet := fRet + DL_DEG_PER_TURN;     // 下半圈搬上去，(-180] 边界归 +180 / bring the lower half up, the boundary joins plus 180
END_IF

// 段 6｜零容差归一：消除 −0.0 与 360.0 抖动 / segment 6, zero tolerance normalisation removes minus zero and 360 jitter
IF ABS(fRet) < DL_FLOAT_EPS THEN
    fRet := DL_LREAL_ZERO;              // 一律归 +0.0 / always normalise to positive zero
    eErr := 16#0001_043D;               // 零容差归一（信息级，不置 bError）/ zero tolerance hit, info level
END_IF

// 段 7｜区间搬移：0..360 口径 / segment 7, shift into the zero to 360 interval when requested
IF bZeroTo360 THEN
    IF fRet < DL_LREAL_ZERO THEN
        fRet := fRet + DL_DEG_PER_TURN; // 负半区搬到正半区，结果恒 < 360 / move the negative half up, the result stays below 360
    END_IF
END_IF

// 段 8｜超一圈提示（先置者保留原则：043C 若已被占则不覆盖）/ segment 8, one-turn hint, never overwriting an existing code
IF bOverOneTurn AND (eErr = DL_ERR_NONE) THEN
    eErr := 16#0001_043C;               // 输入超一圈已归一（信息级）/ input beyond one turn, info level
END_IF

// 段 9｜出口 / segment 9, exit
FC_DL_WrapAngleDeg := fRet;             // 输出归一角度 / publish the normalised angle
bValid := TRUE;                         // 结果可用 / the result is usable
END_FUNCTION
