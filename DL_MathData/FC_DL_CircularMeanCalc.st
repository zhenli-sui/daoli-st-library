(*
  ==================================================================
  组件名 Component  : FC_DL_CircularMeanCalc
  分类   Category   : DL_MathData
  版本   Version    : 1.0.0
  功能   Purpose    : 角度集的圆均值（Circular Mean）：Σsin/Σcos 合成向量法，
                      输出归一 [0,360) 的平均角。归一采用「条件加减」搬区间
                      （负角加 360 / 满 360 减 360），禁负数取模（MOD 在实数
                      域三平台余数符号不一致）。零向量退化（|R| < 1E-6，各角
                      完全对消）判定失效返回，不做伪输出。
  来源   Source     : t2-1-lgf-measurement（测量族：向量合成求圆均值为公开
                      数学口径，实现零源码复制）
  互引   Cross-ref  : FC_DL_WrapAngleDeg（同族角度归一原子，本件内联了等价
                      [0,360) 搬移逻辑，避免跨件调用改变 FC 返回契约）；
                      FC_DL_AngleDiffWrap（下游做两均值角差用）
  平台   Platform   : 纯 IEC 61131-3 四则 + SIN/COS/SQRT/ATAN2 标准数学函数
                      （三平台 MATH 内建：CODESYS Math.library / TwinCAT
                      TC Math / InoProShop Math）
  依赖   Depends    : 无 DL_ 内部依赖
  设计偏差 Deviation: nCount > 数组实际长度时按数组长度钳位接管（防御性，头注
                      声明，不静默越界；错误码表未为此设码，见码位反证）
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 元素级非有限闸 + 除法分母显式闸 + 归一域内安全
                      R5 全变量双语同行注释/R6 纯函数无状态机（CASE 不适用）
                      R7 无定时器与沿检测/R8 容差与循环界全常量化
  错误码 Codes      : 01【失效级】空输入（nCount=0），返回 0，bValid=FALSE
                      02【失效级】任一元素非有限（NaN/±Inf），返回 0
                      03【失效级】零向量退化 |R|<1E-6（各角完全对消），返回 0
  码位反证 Note     : 01/02/03 三码分立依据（R90）：01 无效在输入计数层即可
                      观测、02 无效在元素层、03 无效仅在合成结果层，三者的
                      排查入口不同，不可合并；
                      「nCount 超数组长度钳位」与 01 输出组合不可区分（都按
                      实际长度推进、无独立输出通道），按 R 反证条款不为它设码。
  验收   Acceptance : V1 {10, 350} → 0 ｜ V2 {0, 120, 240} → |R|=0 码 03 ｜
                      V3 空 → 码 01 ｜ V4 含 NaN → 码 02 ｜ V5 单元素 → 自身
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 1 序 3）
  ==================================================================
*)
FUNCTION FC_DL_CircularMeanCalc : LREAL
VAR_INPUT
    aAnglesDeg : ARRAY[*] OF LREAL;  // 角度数组 [°] / the angle array [deg]
    nCount     : UDINT;              // 参与计算的角度个数 [个]，超出数组长度按长度钳位 / the count, clamped to the array length
END_VAR
VAR_OUTPUT
    bValid     : BOOL;               // 平均角可用标志 [-] / the mean angle usable flag
    nErrId     : UDINT;              // 错误码，0=正常，01/02/03 见头注 [码] / the error code [code]
END_VAR
VAR
    fxSum      : LREAL;              // Σcos 分量 [无量纲] / the summed cosine component [dimensionless]
    fySum      : LREAL;              // Σsin 分量 [无量纲] / the summed sine component [dimensionless]
    fRad       : LREAL;              // 当前元素弧度 [rad] / the current element in radians [rad]
    fR         : LREAL;              // 合成向量模 [无量纲] / the resultant magnitude [dimensionless]
    fMean      : LREAL;              // 圆均值工作寄存器 [°] / the mean working register [deg]
    uUsed      : UDINT;              // 实际参与个数（钳位后）[个] / the used count after clamping [count]
    uLen       : UDINT;              // 数组实际长度 [个] / the actual array length [count]
    i          : UDINT;              // 循环变量，有界 [索引] / the loop index, bounded [index]
END_VAR
VAR CONSTANT
    CMC_DEG2RAD : LREAL := 0.017453292519943295; // π/180，度转弧度 [rad/°] / pi over 180 [rad per deg]
    CMC_DEG_TURN: LREAL := 360.0;                // 一整圈 [°] / one full turn [deg]
    CMC_R_MIN   : LREAL := 1.0E-6;               // 零向量退化阈值 |R| / the degenerate resultant threshold
    CMC_ERR_NONE : UDINT := 16#0000_0000;        // 无错误 [码] / no error [code]
    CMC_ERR_EMPTY: UDINT := 16#0000_0001;        // 码 01：空输入 / code 01, empty input
    CMC_ERR_NAN  : UDINT := 16#0000_0002;        // 码 02：非有限元素 / code 02, non finite element
    CMC_ERR_ZEROV: UDINT := 16#0000_0003;        // 码 03：零向量退化 / code 03, degenerate zero vector
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
FC_DL_CircularMeanCalc := 0.0;  // 失效缺省返回 0 / fault default returns zero
bValid := FALSE;                // 预置不可用 / preset unusable
nErrId := CMC_ERR_NONE;         // 预置无错误 / preset no error
fxSum  := 0.0;                  // 分量累加器清零 / clear the cosine accumulator
fySum  := 0.0;                  // 分量累加器清零 / clear the sine accumulator

// 段 2｜数组长度闸与空闸（结构 RETURN 早退）/ segment 2, array length gate and the empty gate
uLen := UDINT#0;                                        // 预置长度 / preset the length
IF UPPER_BOUND(aAnglesDeg, 1) >= 0 THEN                 // 防御：变长数组上界有效性 / defensive: variable array bound check
    uLen := DINT_TO_UDINT(1 + UPPER_BOUND(aAnglesDeg, 1) - LOWER_BOUND(aAnglesDeg, 1)); // 实际长度（守卫内恒非负）/ the actual length, non negative inside the guard
END_IF
IF nCount = UDINT#0 THEN        // 空输入（码 01）/ empty input, code 01
    nErrId := CMC_ERR_EMPTY;
    RETURN;
END_IF
uUsed := nCount;                                        // 先取原始个数 / take the raw count first
IF uUsed > uLen THEN
    uUsed := uLen;                                      // 超长钳位接管（头注偏差声明）/ clamp to the actual length, documented deviation
END_IF
IF uUsed = UDINT#0 THEN         // 钳位后为空（空数组 + 非零 nCount）→ 仍判空码 / still empty after clamping
    nErrId := CMC_ERR_EMPTY;
    RETURN;
END_IF

// 段 3｜分量累加：元素级非有限闸（码 02）与循环下标闸（uUsed ≤ uLen 已证）
//      segment 3, accumulate components with the per element finite gate and a proven index bound
FOR i := 0 TO UDINT_TO_DINT(uUsed) - 1 DO               // 有界 FOR，上界 uUsed ≤ uLen / bounded loop
    fRad := aAnglesDeg[i] * CMC_DEG2RAD;                // 度转弧度 [rad] / degrees to radians [rad]
    IF (aAnglesDeg[i] <> aAnglesDeg[i]) OR (ABS(aAnglesDeg[i]) > 1.7976931348623157E308) THEN  // 自反判 NaN + 有限域 / reflexive NaN and finiteness
        nErrId := CMC_ERR_NAN;                          // 码 02：非有限元素 / code 02, non finite element
        RETURN;                                         // 结构早退，返回 0 / structural early return
    END_IF
    fxSum := fxSum + COS(fRad);                         // 累加 cos 分量 / accumulate the cosine component
    fySum := fySum + SIN(fRad);                         // 累加 sin 分量 / accumulate the sine component
END_FOR

// 段 4｜零向量退化闸（码 03）：|R| < 1E-6 视为完全对消 / segment 4, the degenerate vector gate
fR := SQRT(fxSum * fxSum + fySum * fySum);              // 合成向量模（被开方数恒非负）/ the resultant magnitude
IF fR < CMC_R_MIN THEN
    nErrId := CMC_ERR_ZEROV;                            // 码 03：零向量退化 / code 03, degenerate zero vector
    RETURN;
END_IF

// 段 5｜圆均值求解：ATAN2 于 (fxSum, fySum)，fR ≥ 1E-6 保证不会落在 (0,0) 点
//      segment 5, the mean via atan2, the magnitude gate keeps the point off the origin
fMean := ATAN2(fySum, fxSum) / CMC_DEG2RAD;             // 弧度回角度 [°] / radians back to degrees [deg]

// 段 6｜归一 [0,360)：条件加减搬区间，禁负取模 / segment 6, normalise to [0,360) by conditional add or subtract
IF fMean < 0.0 THEN
    fMean := fMean + CMC_DEG_TURN;                      // 负半区搬上去（ATAN2 值域 ±180，一次即够）/ move the negative half up
END_IF
IF fMean >= CMC_DEG_TURN THEN
    fMean := fMean - CMC_DEG_TURN;                      // 满圈搬下来（数值抖动防线）/ bring a full turn down
END_IF

// 段 7｜出口 / segment 7, exit
FC_DL_CircularMeanCalc := fMean;                        // 发布圆均值 [°] / publish the circular mean [deg]
bValid := TRUE;                                         // 结果可用 / the result is usable
END_FUNCTION
