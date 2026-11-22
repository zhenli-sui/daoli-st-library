(*
  ==================================================================
  组件名 Component  : FC_DL_AngleDiffRad
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : 两弧度角最短带符号差：fDiff = fAngleA − fAngleB 归一
                      至 [−π, π]。回绕处理两步：先 TRUNC 整圈数把差值压入
                      (−2π, 2π)（TRUNC 向零取整，余数保号），再按 ±π 边界
                      单次平移进 [−π, π]。跨 ±π 回绕（359°→1° 类）输出 ≈
                      −0.035 而非 ≈ 6.26。超大量级角（|差| > π·2^52）精
                      度受 LREAL 整数位尾差限制，头注声明为固有边界。
  来源   Source     : t2-1-lgf-math（角度最短差归一为公开数学口径
                      （mod-2π 最短代表元），实现零源码复制）
  互引   Cross-ref  : FC_DL_AngleDiffWrap / FC_DL_WrapAngleDeg（既有角度
                      族邻件：Wrap 件为角度自身回绕，本件为两角差值归一，
                      弧度口径属主；度口径见 WrapAngleDeg）
  平台   Platform   : 纯 IEC 61131-3 四则 + ABS/TRUNC，三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 非有限闸 + 输出域显式（[−π,π] 复核）/R5 全变量
                      双语同行注释/R6 纯函数无状态机（CASE 不适用）
                      /R7 无定时器与沿检测/R8 阈值全常量化
  错误码 Codes      : 01【失效级】任一输入角非有限（NaN 自反判 / Inf 上限
                      兜底判），返回 0
                      02【失效级】归一后输出越出 [−π−ε, π+ε] 域（结构性
                      罕见兜底），返回 0
  码位反证 Note     : 01/02 分立依据（R90）：01 在输入面、02 在输出域面
                      可观测；02 若并入 01，则「回绕算法自身失效」这一信
                      号将不可观测，故必须分立。
  验收   Acceptance : V1 A=0.1,B=−0.1 → 0.2 ｜ V2 A=6.26,B=0.02 → ≈−0.04
                      （跨 π 回绕）｜ V3 A=−3.2,B=3.2 → ≈3.083（跨 −π）
                      ｜ V4 A=B+2π → ≈0 ｜ V5 含 NaN → 码 01
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 2 序 2）
  ==================================================================
*)
FUNCTION FC_DL_AngleDiffRad : LREAL
VAR_INPUT
    fAngleA : LREAL;  // 角 A [rad] / the angle A in radians
    fAngleB : LREAL;  // 角 B [rad] / the angle B in radians
END_VAR
VAR_OUTPUT
    bValid  : BOOL;   // 差值可用标志 [-] / the difference usable flag
    nErrId  : UDINT;  // 错误码，0=正常，01/02 见头注 [码] / the error code [code]
END_VAR
VAR
    fD      : LREAL;  // 原始差值工作寄存器 [rad] / the raw difference register
    nTurn   : LREAL;  // 整圈数工作寄存器（TRUNC 向零取整）/ the full turn count register
END_VAR
VAR CONSTANT
    ADR_PI       : LREAL := 3.141592653589793;     // π [rad] / the pi constant
    ADR_TWO_PI   : LREAL := 6.283185307179586;     // 2π [rad] / the two pi constant
    ADR_EPS      : LREAL := 1.0E-9;                // 输出域复核容差 [rad] / the output domain tolerance
    ADR_FIN_MAX  : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    ADR_ERR_NONE : UDINT := 16#0000_0000;          // 无错误 [码] / no error [code]
    ADR_ERR_NAN  : UDINT := 16#0000_0001;          // 码 01：输入非有限 / code 01, non finite input
    ADR_ERR_DOM  : UDINT := 16#0000_0002;          // 码 02：输出域越界 / code 02, output domain breach
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
FC_DL_AngleDiffRad := 0.0;  // 失效缺省返回 0 / fault default returns zero
bValid := FALSE;            // 预置不可用 / preset unusable
nErrId := ADR_ERR_NONE;     // 预置无错误 / preset no error

// 段 2｜输入非有限闸（码 01）/ segment 2, the input finite gate
IF (fAngleA <> fAngleA) OR (fAngleB <> fAngleB)
   OR (ABS(fAngleA) > ADR_FIN_MAX) OR (ABS(fAngleB) > ADR_FIN_MAX) THEN
    nErrId := ADR_ERR_NAN;
    RETURN;
END_IF

// 段 3｜原始差值与整圈归约（TRUNC 向零取整，余数保号压入 (−2π, 2π)）
//      segment 3, the raw difference and the full turn reduction
fD := fAngleA - fAngleB;                  // 原始差 [rad] / the raw difference
nTurn := TRUNC(fD / ADR_TWO_PI);          // 整圈数（LREAL 口径，不进 DINT 溢出面）/ the turn count
fD := fD - nTurn * ADR_TWO_PI;            // 压入 (−2π, 2π) / reduce into the open two pi band

// 段 4｜半圈平移进 [−π, π]（单次判界，无循环）/ segment 4, the half turn shift into the pi band
IF fD > ADR_PI THEN                       // 正侧越界回绕 / the positive wrap
    fD := fD - ADR_TWO_PI;
ELSIF fD < -ADR_PI THEN                  // 负侧越界回绕 / the negative wrap
    fD := fD + ADR_TWO_PI;
END_IF

// 段 5｜输出域复核（码 02）与出口 / segment 5, the output domain recheck and exit
IF (fD <> fD) OR (fD < -ADR_PI - ADR_EPS) OR (fD > ADR_PI + ADR_EPS) THEN
    nErrId := ADR_ERR_DOM;                // 归一后仍越域（结构性罕见兜底）/ the breach after reduction
    RETURN;
END_IF
FC_DL_AngleDiffRad := fD;                 // 最短带符号差 [rad] / the shortest signed difference
bValid := TRUE;                           // 差值可用 / the difference is usable
END_FUNCTION
