(*
    FC_DL_DegToRadEx —— 度到弧度转换原子（LREAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / Angle
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托乘法运算语义与 π 常数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 度到弧度转换：返回 fDeg × (π / 180)，换算常数取 LREAL 精度
                字面量（≥16 位有效数字，R51 口径：REAL 精度常数禁入换算路径）；
                输入非有限（NaN 或 ±Inf）判为故障级 16#0001_03D0，返回 0.0 且
                bValid=FALSE（非有限值参与换算在三平台行为不一致，一律拦截）；
                溢出预判采用比较式消灭溢出路径（R54 口径：比较表达式内禁止出现
                乘法运算符，先判域后计算）：|fDeg| > LREAL 最大有限值 ÷ (π/180)
                时判乘积将溢出，判为故障级 16#0001_03D1，返回 0.0（不输出 Inf）；
                预判式除法合法性留档：换算常数 π/180 ≈ 0.017453292519943295 恒正
                且非零，除法本身无除零面；
                域内换算后再做结果非有限复检兜底（理论不可达：域闸后的乘积恒有限）。
    错误码    : 16#0001_03D0 输入非有限（NaN 或 ±Inf）——故障级，返回 0.0
                16#0001_03D1 换算乘积将溢出 LREAL 域（预判命中或复检失败）——故障级，返回 0.0
                （R90 反证句：溢出场景无法由输入非有限码观测——该场景输入有限而
                  结果非有限，与 16#0001_03D0 的「输入坏」语义无法区分，现有输出
                  组合无法还原「值大溢出」首因，故独立占码）
    非有限口径 : NaN 用自不等 f <> f，±Inf 用 (f − f) <> (f − f) 差值自减判定（R15）。
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 2 · T0 快车道）
*)
FUNCTION FC_DL_DegToRadEx : LREAL
VAR_INPUT
    fDeg : LREAL; // 角度输入 [°] ｜ angle input in degrees
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_03XX=fault level
    bError : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR
VAR CONSTANT
    DL_DEG2RAD  : LREAL := 0.017453292519943295;      // 换算常数 π/180，LREAL 精度 ≥16 位有效数字 [rad/°] ｜ conversion constant pi/180, LREAL precision of at least 16 significant digits
    DL_LREAL_MAX: LREAL := 1.7976931348623157E308;    // LREAL 最大有限值 [无量纲] ｜ largest finite LREAL
END_VAR
VAR
    bNonFinite : BOOL; // 输入非有限判定结果 ｜ non-finite detection result of the input
    fOut       : LREAL; // 换算结果暂存，供出口复检 ｜ staging of the converted result for exit recheck
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_DegToRadEx := 0.0; // 故障缺省返回 0 [rad] ｜ fault default returns 0
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes
fOut   := 0.0;   // 暂存清零 ｜ clear the staging value

// 段 2｜输入非有限防御闸（早退） ｜ segment 2, input non-finite guard (early return)
bNonFinite := (fDeg <> fDeg) OR ((fDeg - fDeg) <> (fDeg - fDeg)); // NaN 自不等 + 差值自减判 ±Inf [°] ｜ NaN by self-inequality, +/-Inf by self-subtraction
IF bNonFinite THEN
    FC_DL_DegToRadEx := 0.0; // 故障级返回 0 [rad] ｜ fault level returns 0
    eErr   := 16#0001_03D0;  // 输入非有限故障码 ｜ non-finite input fault id
    bError := TRUE;          // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;         // 输出无效 ｜ output invalid
    RETURN;                  // 早退 ｜ early return
END_IF

// 段 3｜溢出预判域闸（比较式，比较表达式内无乘法运算符） ｜ segment 3, overflow pre-check gate (comparison form, no multiplication inside the comparison)
IF ABS(fDeg) > (DL_LREAL_MAX / DL_DEG2RAD) THEN
    FC_DL_DegToRadEx := 0.0; // 预判命中不计算，返回 0 [rad] ｜ pre-check hit, no computation, returns 0
    eErr   := 16#0001_03D1;  // 换算溢出故障码 ｜ conversion overflow fault id
    bError := TRUE;          // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;         // 输出无效 ｜ output invalid
    RETURN;                  // 早退 ｜ early return
END_IF

// 段 4｜域内换算主体（末段） ｜ segment 4, in-domain conversion body (final)
fOut := fDeg * DL_DEG2RAD; // 度乘以换算常数得弧度 [rad] ｜ degrees times the conversion constant gives radians

// 段 5｜结果非有限复检兜底（理论不可达：域闸后的乘积恒有限） ｜ segment 5, result non-finite recheck (unreachable: the product after the gate is always finite)
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut)) THEN
    FC_DL_DegToRadEx := 0.0; // 复检失败按溢出处置 [rad] ｜ recheck failure treated as overflow
    eErr   := 16#0001_03D1;  // 复用溢出码（同因同码，不新占码位）｜ reuse the overflow code (same cause, no new code)
    bError := TRUE;          // 置故障标志 ｜ raise the fault flag
    bValid := FALSE;         // 输出无效 ｜ output invalid
    RETURN;                  // 早退 ｜ early return
END_IF

// 段 6｜出口装配 ｜ segment 6, exit assembly
FC_DL_DegToRadEx := fOut; // 换算结果直通 ｜ converted result pass-through
bError := FALSE;          // 正常出口不置故障 ｜ normal exit raises no fault
bValid := TRUE;           // 输出有效可用 ｜ output valid
END_FUNCTION
