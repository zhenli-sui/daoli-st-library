(*==============================================================================
 * 组件名称 (Component)  : FC_DL_PressUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 压力工程量单位换算（系数表驱动）：以 Pa 为中介单位，
 *                         fPaAbs = fValue × kSrc，fResult = fPaAbs ÷ kDst，
 *                         kSrc/kDst 取自本文件常量系数表（纯常量除法，分母为非零
 *                         字面常量，结构性无除零）。负压域合法（表压/真空侧负读数
 *                         允许换算），换算结果落在绝对真空下限（0 Pa）之下时钳位
 *                         至 0 并置信息码 eClampVacuum（量值方向可饱和，规格指定）。
 *                         非有限输入 → 故障码 eNonFinite，输出哨兵 0。
 * 接口     (Interface)  : 输入 fValue 被换算压力值（Pa 域口径，含负压）[Pa]、
 *                         eSrc 源单位枚举、eDst 目标单位枚举；
 *                         输出 fConverted 换算结果（钳位后）[目标单位]、
 *                         eErrCode 错误码（E_DL_PressConvErr）、
 *                         返回值 = 换算有效标志（BOOL，TRUE = 数值可信）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做单位换算，不做量程标定、
 *                         不做表压/绝压模式判别**（调用方自行决定口径后传入）。
 *                         ② eSrc/eDst 超出枚举合法域（<0 或 >eMmHg）→ 故障码
 *                         eInvalidUnit，输出哨兵 0（ENUM 强转越域防御）。
 *                         ③ 系数表五个系数均为非零编译期常量，除法分母结构性
 *                         非零，无除零路径。
 *                         ④ 非有限判据：NaN 用自反 x <> x，Inf 用 (x−x) <> (x−x)
 *                         （R79 双判，无裸近似阈值）。
 *                         ⑤ 真空下限钳位只钳下限不设上限（量值饱和单向，正解
 *                         方向故障级码不启用，信息级 eClampVacuum 不置 bError）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AnalogTransmitter` 分工：原始量程标定归那件、
 *                         工程量单位间换算归本件；本件不调用任何 FB，纯函数。
 * 来源标签 (Source Tag) : 自研线（SI 换算系数为公开物理常数定义，clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 返回 +
 *                         LREAL 结果 + ENUM eErrCode（本文件内定义，全库唯一）；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 单位域闸 + 真空下限钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 1 · 序号 1）
 * 验收向量 (Acceptance) : ① fValue=1.0, eSrc=eBar, eDst=ePa → 1×100000÷1
 *                         = 100000.0 Pa，返回 TRUE，eErrCode=eOk；
 *                         ② fValue=14.6959488, eSrc=ePsi, eDst=eBar →
 *                         14.6959488×6894.757293168761 ≈ 101325.0 Pa，
 *                         ÷100000 ≈ 1.01325 bar（容差 1E-6），eOk；
 *                         ③ fValue=760.0, eSrc=eMmHg, eDst=eKpa →
 *                         760×133.322387415 ≈ 101325.014 Pa，÷1000
 *                         ≈ 101.325014 kPa，eOk；
 *                         ④ fValue=-50000.0, eSrc=ePa, eDst=ePa → 中介值
 *                         <0 钳 0，输出 0.0，返回 TRUE，eErrCode=eClampVacuum
 *                         （信息级，bError 不置）。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PressUnit（压力单位表，归属 DL_MathData，与 FC_DL_PressUnitConvert
 *       同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PressUnit :
(
    ePa    := 0,   // 帕斯卡（中介单位） / Pascal, hub unit
    eKpa   := 1,   // 千帕 / Kilopascal
    eBar   := 2,   // 巴 / Bar
    ePsi   := 3,   // 磅每平方英寸 / Pound per square inch
    eMmHg  := 4    // 毫米汞柱（0 ℃ 托） / Millimetre of mercury at 0 degC
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PressConvErr（错误码，故障级置 bError，信息级不置）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PressConvErr :
(
    eOk          := 0,   // 成功 / Success
    eInvalidUnit := 1,   // 故障级：源/目标单位枚举越域 / Fault: unit enum out of domain
    eNonFinite   := 2,   // 故障级：输入非有限（NaN/Inf） / Fault: non-finite input
    eClampVacuum := 3    // 信息级：低于绝对真空下限已钳 0 / Info: clamped to absolute vacuum floor
);
END_TYPE

FUNCTION FC_DL_PressUnitConvert : BOOL
VAR_INPUT
    fValue   : LREAL;                 // 被换算压力值（负压域合法） [Pa] / Input pressure value, negative domain legal [Pa]
    eSrc     : E_DL_PressUnit;        // 源单位枚举 [-] / Source unit enum
    eDst     : E_DL_PressUnit;        // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;               // 换算结果（真空下限钳位后） [目标单位] / Converted result after vacuum floor clamp
    eErrCode   : E_DL_PressConvErr;   // 错误码出口 / Error code outlet
END_VAR
VAR
    _bNonFin  : BOOL;                 // 输入非有限当拍量 [-] / Non-finite input flag
    _fPaAbs   : LREAL;                // 中介绝对压力值 [Pa] / Hub absolute pressure value
END_VAR
VAR CONSTANT
    DL_PUC_KPA    : LREAL := 1000.0;              // kPa → Pa 换算系数 [Pa/kPa] / kPa to Pa factor
    DL_PUC_BAR    : LREAL := 100000.0;            // bar → Pa 换算系数 [Pa/bar] / bar to Pa factor
    DL_PUC_PSI    : LREAL := 6894.757293168761;   // psi → Pa 换算系数（15 位有效数字） [Pa/psi] / psi to Pa factor
    DL_PUC_MMHG   : LREAL := 133.322387415;       // mmHg(0℃) → Pa 换算系数 [Pa/mmHg] / mmHg to Pa factor
    DL_PUC_ONE    : LREAL := 1.0;                 // Pa → Pa 恒等系数 [Pa/Pa] / Pa identity factor
    DL_PUC_ZERO   : LREAL := 0.0;                 // 真空下限与非有限判零基准 [Pa] / Vacuum floor and non-finite zero base
    DL_PUC_UNITMAX: INT   := 4;                   // 枚举合法域上限（eMmHg） [-] / Unit enum domain ceiling
END_VAR

(* —— 段 0：出口预置安全值（四段式第一段：预置） —— *)
FC_DL_PressUnitConvert := FALSE;                  // 返回值预置无效 / Return preset invalid
fConverted := DL_PUC_ZERO;                        // 结果哨兵 0 / Result sentinel zero
eErrCode := E_DL_PressConvErr.eInvalidUnit;       // 预置最严码，域闸命中直接早退 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判：NaN 自反 + Inf 差自减） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_PUC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_PressConvErr.eNonFinite;     // 故障级码（R45 配对见段 6） / Fault code
    RETURN;                                       // 早退保持哨兵输出 / Early exit with sentinel
END_IF

(* —— 段 2：单位枚举域闸（按枚举成员逐值比较，不依赖平台 ENUM→INT 强转方言） —— *)
(* 按枚举成员逐值比较，避免依赖平台 ENUM→INT 强转方言 *)
IF (eSrc = E_DL_PressUnit.ePa) THEN
    _fPaAbs := fValue * DL_PUC_ONE;               // Pa 直通 / Pa pass-through
ELSIF (eSrc = E_DL_PressUnit.eKpa) THEN
    _fPaAbs := fValue * DL_PUC_KPA;               // kPa × 1000 / kPa scaled
ELSIF (eSrc = E_DL_PressUnit.eBar) THEN
    _fPaAbs := fValue * DL_PUC_BAR;               // bar × 100000 / bar scaled
ELSIF (eSrc = E_DL_PressUnit.ePsi) THEN
    _fPaAbs := fValue * DL_PUC_PSI;               // psi × 6894.757... / psi scaled
ELSIF (eSrc = E_DL_PressUnit.eMmHg) THEN
    _fPaAbs := fValue * DL_PUC_MMHG;              // mmHg × 133.322... / mmHg scaled
ELSE
    RETURN;                                       // 源单位越域：保持预置故障码与哨兵 0 / Source unit out of domain
END_IF

(* —— 段 3：真空下限钳位（负压域合法，仅钳绝对真空以下） —— *)
eErrCode := E_DL_PressConvErr.eOk;                // 预置成功 / Preset success
IF _fPaAbs < DL_PUC_ZERO THEN
    _fPaAbs := DL_PUC_ZERO;                       // 钳至绝对真空下限 / Clamp to vacuum floor
    eErrCode := E_DL_PressConvErr.eClampVacuum;   // 信息级（不置 bError，规格⑤） / Info-level code
END_IF

(* —— 段 4：目标单位反换算（常量除法，分母非零结构性无除零） —— *)
IF (eDst = E_DL_PressUnit.ePa) THEN
    fConverted := _fPaAbs / DL_PUC_ONE;           // ÷1 直通 / Divide by one
ELSIF (eDst = E_DL_PressUnit.eKpa) THEN
    fConverted := _fPaAbs / DL_PUC_KPA;           // ÷1000 / Divide by kPa factor
ELSIF (eDst = E_DL_PressUnit.eBar) THEN
    fConverted := _fPaAbs / DL_PUC_BAR;           // ÷100000 / Divide by bar factor
ELSIF (eDst = E_DL_PressUnit.ePsi) THEN
    fConverted := _fPaAbs / DL_PUC_PSI;           // ÷6894.757... / Divide by psi factor
ELSIF (eDst = E_DL_PressUnit.eMmHg) THEN
    fConverted := _fPaAbs / DL_PUC_MMHG;          // ÷133.322... / Divide by mmHg factor
ELSE
    eErrCode := E_DL_PressConvErr.eInvalidUnit;   // 目标单位越域：回置故障码 / Destination unit out of domain
    fConverted := DL_PUC_ZERO;                    // 结果回哨兵 0 / Result back to sentinel
    RETURN;                                       // 早退 / Early exit
END_IF

(* —— 段 5：结果非有限复检兜底（四段式第四段：复检） —— *)
IF (_fPaAbs <> _fPaAbs) OR ((_fPaAbs - _fPaAbs) <> DL_PUC_ZERO) THEN
    fConverted := DL_PUC_ZERO;                    // 中介值复检异常：回哨兵 / Hub recheck failed: sentinel
    eErrCode := E_DL_PressConvErr.eNonFinite;     // 故障级码 / Fault code
    RETURN;                                       // 早退 / Early exit
END_IF

(* —— 段 6：成功出口（bError 由调用方按 eErrCode 归约；故障级码恒伴返回 FALSE） —— *)
FC_DL_PressUnitConvert := TRUE;                   // 换算有效（信息级钳位也算有效换算） / Conversion valid

END_FUNCTION
