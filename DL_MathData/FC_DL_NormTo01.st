(*
  ==================================================================
  组件名 Component  : FC_DL_NormTo01
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : 值域线性归一化至 0..1：fNorm = (fVal − fMin) /
                      (fMax − fMin)。反向域（fMax < fMin）与零域宽
                      （|fMax − fMin| < 容差，浮点容差判禁等号）双闸分
                      立；输入超 [fMin, fMax] 结果钳位至 0/1 并置信息码，
                      不静默。域宽为有限大数相减仍可能溢出 Inf，结果非
                      有限复核兜底。
  来源   Source     : t2-1-lgf-math（min-max 归一化为公开数学口径，
                      实现零源码复制）
  互引   Cross-ref  : FC_DL_Scaling（同族线性标定原子：其按工程量程
                      双点标定，本件为 0..1 归一口径属主）
  平台   Platform   : 纯 IEC 61131-3 四则 + ABS，三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 除零三闸（反向域/零域宽容差判/结果非有限复核）
                      + 钳位显式/R5 全变量双语同行注释/R6 纯函数无状态机
                      （CASE 不适用）/R7 无定时器与沿检测/R8 容差常量化
  错误码 Codes      : 01【失效级】反向域（fMax < fMin），返回 0
                      02【失效级】零域宽（|fMax − fMin| < 1E-9，浮点容差
                      判）或任一输入非有限或结果非有限，返回 0
                      03【信息级】超界钳位（fVal 出 [fMin,fMax]，结果钳
                      至 0 或 1，不置 bError）
  码位反证 Note     : 01/02 分立依据（R90）：01 在域序面（参数对调类组
                      态错）、02 在域宽/数值面（量程退化类组态错）可观测，
                      整定入口同但缺陷性质不同；03 信息级不置 bError，与
                      01/02 双通道可区分。
  验收   Acceptance : V1 fVal=fMin → 0 ｜ V2 fVal=fMax → 1 ｜ V3 中点 →
                      0.5 ｜ V4 fMax<fMin → 码 01 ｜ V5 fMax=fMin → 码 02
                      ｜ V6 超界 → 钳位 + 码 03（bValid=TRUE）
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 2 序 3）
  ==================================================================
*)
FUNCTION FC_DL_NormTo01 : LREAL
VAR_INPUT
    fVal  : LREAL;  // 待归一值 [物理单位] / the value to normalize
    fMin  : LREAL;  // 域下界 [物理单位] / the domain lower bound
    fMax  : LREAL;  // 域上界 [物理单位] / the domain upper bound
END_VAR
VAR_OUTPUT
    bValid : BOOL;  // 归一值可用标志（钳位仍为 TRUE，头注 V6）[-] / the normalized value usable flag
    nErrId : UDINT; // 错误码，0=正常，01/02/03 见头注 [码] / the error code [code]
END_VAR
VAR
    fSpan  : LREAL; // 域宽工作寄存器 / the domain span working register
    fNorm  : LREAL; // 归一中间量工作寄存器 [-] / the normalized intermediate register
END_VAR
VAR CONSTANT
    N01_EPS     : LREAL := 1.0E-9;                 // 零域宽容差 [无量纲] / the zero span tolerance
    N01_FIN_MAX : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    N01_ERR_NONE : UDINT := 16#0000_0000;          // 无错误 [码] / no error [code]
    N01_ERR_REV  : UDINT := 16#0000_0001;          // 码 01：反向域 / code 01, reversed domain
    N01_ERR_ZSP  : UDINT := 16#0000_0002;          // 码 02：零域宽/非有限 / code 02, zero span or non finite
    N01_ERR_CLP  : UDINT := 16#0000_0003;          // 码 03：超界钳位（信息级）/ code 03, clamped, info level
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
FC_DL_NormTo01 := 0.0;        // 失效缺省返回 0 / fault default returns zero
bValid := FALSE;              // 预置不可用 / preset unusable
nErrId := N01_ERR_NONE;       // 预置无错误 / preset no error

// 段 2｜输入非有限闸（并入码 02，头注口径）/ segment 2, the input finite gate
IF (fVal <> fVal) OR (fMin <> fMin) OR (fMax <> fMax)
   OR (ABS(fVal) > N01_FIN_MAX) OR (ABS(fMin) > N01_FIN_MAX) OR (ABS(fMax) > N01_FIN_MAX) THEN
    nErrId := N01_ERR_ZSP;
    RETURN;
END_IF

// 段 3｜反向域闸（码 01）：域序面缺陷 / segment 3, the reversed domain gate
IF fMax < fMin THEN
    nErrId := N01_ERR_REV;
    RETURN;
END_IF

// 段 4｜零域宽闸（码 02）：浮点容差判，禁 = 判等，除法前置 / segment 4, the zero span gate
fSpan := fMax - fMin;                      // 域宽（有限差可能 Inf，段 6 复核）/ the span
IF (ABS(fSpan) < N01_EPS) OR (fSpan <> fSpan) THEN
    nErrId := N01_ERR_ZSP;
    RETURN;
END_IF

// 段 5｜归一与超界钳位（码 03 信息级，钳位显式不静默）/ segment 5, normalize and clamp
fNorm := (fVal - fMin) / fSpan;            // 分母 = fSpan，已闸 / the denominator gated
IF (fNorm <> fNorm) OR (ABS(fNorm) > N01_FIN_MAX) THEN
    nErrId := N01_ERR_ZSP;                 // 结果非有限复核兜底 / the result finiteness recheck
    RETURN;
END_IF
IF fNorm < 0.0 THEN                        // 超下界钳 0 / clamp below
    fNorm := 0.0;
    nErrId := N01_ERR_CLP;
ELSIF fNorm > 1.0 THEN                     // 超上界钳 1 / clamp above
    fNorm := 1.0;
    nErrId := N01_ERR_CLP;
END_IF

// 段 6｜出口 / segment 6, the exit
FC_DL_NormTo01 := fNorm;                   // 归一值 [-] / the normalized value
bValid := TRUE;                            // 可用（钳位仍可用，头注 V6）/ usable, clamped still usable
END_FUNCTION
