(*
  ==================================================================
  组件名 Component  : FC_DL_Hypot3D
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : 三维矢量模长 √(x²+y²+z²)，中途缩放防 x² 溢出。
  来源   Source     : self-std（公开数学语义自研包装）
  平台   Platform   : 纯 IEC 61131-3（SQRT / ABS / 四则运算），三平台通用
  分工声明 Split     : 与 FC_DL_Hypot（二维属主，若在册）互引——本件只做三维；
                      T0 防御性包装：内核即 SQRT 一次委托，不重实现数学内核。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限闸逐个点名三个浮点入参（R272 全量枚举：fX / fY /
                         fZ 三个各判 NaN 自反 + Inf 差值自减），命中即拒绝出值；
                      二 溢出防护：先取三轴绝对值最大者 fMax 缩放，归一化分量
                         |fXn| ≤ 1，平方和 ≤ 3 结构性不溢出，再乘回 fMax；
                      三 全零矢量：fMax = 0 时直接返回 0（禁除零，除子已证 > 0）；
                      四 结果复检兜底同拍置 eErr + bError + bValid 三件套（R258）；
                      五 无状态纯函数：局部量段 1 显式预置（R254）。
  错误码   Codes    :
    16#0001_0631【故障级】入参含非有限值（fX / fY / fZ 逐个点名），拒绝出值
    16#0001_0632【故障级】结果非有限（复检兜底，结构性不可达仍保留）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 (3,4,0) → 5.0；V2 (1E200,1E200,1E200) → 缩放后 ≈1.7320508E200 不溢出
    V3 fX=NaN → 码 0631、bValid=FALSE、返回 0
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 1 · 序号 3）
  ==================================================================
*)
FUNCTION FC_DL_Hypot3D : LREAL
VAR_INPUT
    fX : LREAL; // X 分量 [用户单位] / the X component
    fY : LREAL; // Y 分量 [用户单位] / the Y component
    fZ : LREAL; // Z 分量 [用户单位] / the Z component
END_VAR
VAR_OUTPUT
    bValid : BOOL;  // 结果可用标志 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志，故障级码置位（R45 配对）/ the error flag
END_VAR
VAR
    fMax : LREAL; // 三轴绝对值最大者 [用户单位] / the largest absolute component
    fXn  : LREAL; // 归一化 X 分量 [-] / the normalised X component
    fYn  : LREAL; // 归一化 Y 分量 [-] / the normalised Y component
    fZn  : LREAL; // 归一化 Z 分量 [-] / the normalised Z component
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 局部量显式预置（R254）/ segment 1, the preset
FC_DL_Hypot3D := 0.0; // 返回值预置安全值零 / preset the return zero
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
fMax := 0.0; // 最大分量预置零 / preset the max zero
fXn := 0.0; // 归一化 X 预置零 / preset the normalised X zero
fYn := 0.0; // 归一化 Y 预置零 / preset the normalised Y zero
fZn := 0.0; // 归一化 Z 预置零 / preset the normalised Z zero

// 段 2｜非有限闸：三个入参逐个点名（R272 全量，边界一）/ segment 2, the finiteness gate naming every input
IF (fX <> fX) OR ((fX - fX) <> (fX - fX))
OR (fY <> fY) OR ((fY - fY) <> (fY - fY))
OR (fZ <> fZ) OR ((fZ - fZ) <> (fZ - fZ)) THEN // 任一分量非有限 / any component is not finite
    eErr := 16#0001_0631; // 故障级：入参含非有限值 / fault grade, a non finite input
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF

// 段 3｜缩放防溢出：先取最大绝对值（边界二）/ segment 3, the scaling against the overflow
fMax := ABS(fX); // 以 X 绝对值起步 / start from the absolute X
IF ABS(fY) > fMax THEN // Y 更大 / the Y is larger
    fMax := ABS(fY); // 接管最大值 / take over the max
END_IF
IF ABS(fZ) > fMax THEN // Z 更大 / the Z is larger
    fMax := ABS(fZ); // 接管最大值 / take over the max
END_IF
IF fMax = 0.0 THEN // 全零矢量（整数零精确比较，非浮点容差场景）/ the all zero vector with an exact integer zero compare
    FC_DL_Hypot3D := 0.0; // 模长为零 / the length is zero
    bValid := TRUE; // 结果可用 / the result is usable
    FC_DL_Hypot3D := 0.0; // 返回零 / return zero
ELSE // 非零矢量：归一化后开方再乘回 / the nonzero vector
    fXn := fX / fMax; // 归一化 X（除子 fMax 已证 > 0）/ the normalised X with a proven divisor
    fYn := fY / fMax; // 归一化 Y / the normalised Y
    fZn := fZ / fMax; // 归一化 Z / the normalised Z
    FC_DL_Hypot3D := fMax * SQRT(fXn * fXn + fYn * fYn + fZn * fZn); // 模长（平方和 ≤ 3 结构性不溢出）/ the length, the sum of squares bounded by three
END_IF

// 段 4｜结果复检兜底（非有限同拍三件套，边界四）/ segment 4, the result recheck
IF (FC_DL_Hypot3D <> FC_DL_Hypot3D)
OR ((FC_DL_Hypot3D - FC_DL_Hypot3D) <> (FC_DL_Hypot3D - FC_DL_Hypot3D)) THEN // 结果非有限 / the result is not finite
    FC_DL_Hypot3D := 0.0; // 兜底安全值 / the bottom line safe value
    eErr := 16#0001_0632; // 故障级：结果非有限 / fault grade, the non finite result
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
ELSE // 结果有限 / a finite result
    bValid := TRUE; // 结果可用 / the result is usable
END_IF
END_FUNCTION
