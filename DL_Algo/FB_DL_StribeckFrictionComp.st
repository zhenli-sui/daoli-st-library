(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StribeckFrictionComp
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS / EXP / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : Stribeck 三段摩擦补偿模型本体 + 过零平滑。
 *                         摩擦模型（速度域，三段合一式）：
 *                           F(v) = [Fc + Fs × exp(−|v| / vs)] × s(v) + Fv × v
 *                         其中 Fc 库仑项、Fs Stribeck 附加项、vs Stribeck 特征速度、Fv 黏滞
 *                         系数；s(v) 是过零平滑后的符号函数：
 *                           |v| >= fVelZeroBand  → s = sign(v)（±1，纯符号段）
 *                           |v| <  fVelZeroBand  → s = v / fVelZeroBand（线性过渡，±1 内）
 *                         三段语义（eRegion）：
 *                           eViscous  黏滞段：|v| 超 fVelZeroBand × 3，Stribeck 项已衰减到可忽略，
 *                                     主导项为 Fv × v；
 *                           eStribeck 过渡段：fVelZeroBand <= |v| <= fVelZeroBand × 3，
 *                                     Stribeck 指数项显著，补偿量随速度非线性变化；
 *                           eStiction 预滑段：|v| < fVelZeroBand，静摩擦主导，符号平滑避免
 *                                     在零点附近 ±Fc 硬跳变（硬跳变会让速度环在过零时抖振）。
 *                         输出 fComp 为**补偿量**（与运动方向同号），由轴级注入到转矩/电流前馈。
 * 接口     (Interface)  : 输入 fVel 当前速度、fVelZeroBand 过零平滑带宽、fCoulomb 库仑摩擦、
 *                         fStiction Stribeck 附加幅值、fStribeckVel 特征速度 vs、fViscous 黏滞
 *                         系数、fCompMax 补偿量硬限、bEnable 使能；输出 fComp 补偿量、eRegion
 *                         当前段、fSignSoft 平滑符号、bLimited 是否触限、eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件是摩擦模型的"本体"，只算补偿量，不直接改轴
 *                         输出、不访问任何轴接口、不做使能联动**。与 `FB_DL_AxisFrictionFf`
 *                         （轴级前馈注入件）分工：那件负责把补偿量按轴单位/方向/限幅注入到
 *                         转矩前馈并把住"轴未使能不注入"的门，本件只出模型量。二者串接时
 *                         以本件 fComp 为源、以那件为汇，禁止本件内联注入。
 *                         ② 组态闸：fVelZeroBand <= DL_SFC_EPS（平滑带宽为 0 则退化为硬符号，
 *                         过零抖振风险回归）、fStribeckVel <= DL_SFC_EPS（指数分母除零）、
 *                         fCompMax <= 0.0、fCoulomb < 0.0、fStiction < 0.0、fViscous < 0.0、
 *                         任一浮点引脚 NaN → 故障锁存，fComp 输出 0（安全侧：不注入错误补偿）。
 *                         ③ bEnable=FALSE 分支语义（R191 名实双出口声明）：**fComp 置 0（冻结注入）
 *                         而不保持上拍值**——保持上拍值会在停机瞬间留下残余前馈，属危险默认；
 *                         同时不置 bError（未使能不是故障）。该语义写死在此，不得由调用方假设。
 *                         ④ 补偿量硬限 ±fCompMax 为饱和实现并置 bLimited（饱和不等于故障）。
 *                         ⑤ 无 TON/R_TRIG（纯组合模型），故无周期刷新与跨相复位问题。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 来源标签 (Source Tag) : T2-1 ◐（公开经典模型 Stribeck 摩擦曲线，参考参数域与分段口径，
 *                         零代码行复制；过零平滑为本库自研包装）
 * 解除式   (Release)    : 本件故障为锁存型，解除路径 = bReset 上升沿 ∧ 组态合法。
 *                         自证可满足：组态修好后复位即解除，无恒假因子。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 REAL 补偿量 + ENUM 段别 +
 *                         BOOL（bLimited / bError）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 指数分母除零闸 + 饱和硬限 + 浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 2 · 序号 8）
 *==============================================================================*)

TYPE E_DL_SfcRegion :
(
    eStiction := 0,    // 预滑（静摩擦主导）段 / Pre-sliding, stiction dominated
    eStribeck := 10,   // Stribeck 过渡段 / Stribeck transition region
    eViscous  := 20,   // 黏滞主导段 / Viscous dominated region
    eOff      := 30,   // 未使能（补偿置 0） / Disabled, compensation forced to zero
    eFault    := 90    // 组态故障相（补偿置 0） / Configuration fault, compensation forced to zero
);
END_TYPE

TYPE E_DL_SfcCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（带宽/特征速度为 0，或系数为负，或非有限） / Illegal configuration
    ePhaseBad   := 2    // 非法段别兜底 / Illegal region fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_StribeckFrictionComp
VAR_INPUT
    fVel         : REAL := 0.0;     // 当前速度（带符号） [mm/s] / Current velocity, signed [mm/s]
    fVelZeroBand : REAL := 1.0;     // 过零平滑带宽，域 > DL_SFC_EPS [mm/s] / Zero-cross smoothing band, > epsilon [mm/s]
    fCoulomb     : REAL := 2.0;     // 库仑摩擦 Fc，域 >= 0.0 [N] / Coulomb friction Fc, >= 0.0 [N]
    fStiction    : REAL := 1.0;     // Stribeck 附加幅值 Fs，域 >= 0.0 [N] / Stribeck amplitude Fs, >= 0.0 [N]
    fStribeckVel : REAL := 2.0;     // Stribeck 特征速度 vs，域 > DL_SFC_EPS [mm/s] / Stribeck characteristic velocity vs [mm/s]
    fViscous     : REAL := 0.1;     // 黏滞系数 Fv，域 >= 0.0 [N/(mm/s)] / Viscous coefficient Fv, >= 0.0 [N/(mm/s)]
    fCompMax     : REAL := 20.0;    // 补偿量硬限，域 > 0.0 [N] / Compensation hard limit, > 0.0 [N]
    bEnable      : BOOL := TRUE;    // 使能；FALSE 时 fComp 置 0（冻结注入，非保持） [-] / Enable; FALSE forces fComp to 0
    bReset       : BOOL := FALSE;   // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears configuration fault
END_VAR
VAR_OUTPUT
    fComp     : REAL;               // 摩擦补偿量（与运动方向同号，已饱和） [N] / Friction compensation, saturated [N]
    eRegion   : E_DL_SfcRegion;     // 当前摩擦段别出口 [-] / Current friction region
    fSignSoft : REAL;               // 平滑符号函数值，域 [−1, +1] [-] / Smoothed sign in [-1, +1]
    bLimited  : BOOL;               // 补偿量触硬限（饱和发生） [-] / Compensation hit the hard limit
    eState    : E_DL_SfcRegion;     // 状态出口（与 eRegion 同源，段 8 单点映射） [-] / State outlet
    eCause    : E_DL_SfcCause;      // 异常成因出口 [-] / Cause outlet
    bError    : BOOL;               // 组态故障标志（锁存） [-] / Configuration fault flag, latched
END_VAR
VAR
    _eState   : E_DL_SfcRegion := E_DL_SfcRegion.eOff;    // 内部段别（CASE 唯一写入目标） / Internal region
    _eCause   : E_DL_SfcCause := E_DL_SfcCause.eNone;     // 成因锁存量 / Latched cause
    rtReset   : R_TRIG;             // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bFault   : BOOL;               // 组态故障锁存位（锁存量） / Latched configuration fault
    _bCfgBad  : BOOL;               // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin  : BOOL;               // 输入非有限当拍量 [-] / Non-finite input this scan
    _fSign    : REAL;               // 当拍平滑符号中间量 [-] / Smoothed sign intermediate
    _fRaw     : REAL;               // 当拍未限幅补偿量 [N] / Unlimited compensation [N]
    _fStrib   : REAL;               // 当拍 Stribeck 指数项 [N] / Stribeck exponential term [N]
END_VAR
VAR CONSTANT
    DL_SFC_EPS      : REAL := 1.0E-6;   // 浮点判零容差 [无量纲] / Float epsilon
    DL_SFC_ONE      : REAL := 1.0;      // 单位常量（符号上限） [无量纲] / Unit constant, sign ceiling
    DL_SFC_BAND_X3  : REAL := 3.0;      // 段别分界倍数：3 倍带宽以上判黏滞段 [-] / Region factor, 3x band marks viscous
END_VAR

(* —— 段 0：当拍量派生 + 沿实例无条件周期刷新 —— *)
_bNonFin := (fVel <> fVel) OR (fVelZeroBand <> fVelZeroBand)            // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fCoulomb <> fCoulomb) OR (fStiction <> fStiction)
         OR (fStribeckVel <> fStribeckVel) OR (fViscous <> fViscous)
         OR (fCompMax <> fCompMax);                                     // 引脚 NaN 全量判 / All-pin NaN tests
_bCfgBad := (fVelZeroBand <= DL_SFC_EPS)                                // 平滑带宽须显著为正 / Smoothing band must be clearly positive
         OR (fStribeckVel <= DL_SFC_EPS)                                // 指数分母须显著为正 / Exponential denominator must be positive
         OR (fCompMax <= 0.0) OR (fCoulomb < 0.0)                       // 硬限与系数下界 / Hard limit and coefficient floors
         OR (fStiction < 0.0) OR (fViscous < 0.0) OR _bNonFin;          // 系数下界 + 非有限 / Coefficient floors and non-finite
rtReset(CLK := bReset);                                                 // 复位沿，每拍必调（R228A） / Reset edge, every scan

(* —— 段 1：复位沿 + 组态闸 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                   // 清组态故障锁存 / Clear the latched configuration fault
    _eCause := E_DL_SfcCause.eNone;                                     // 清成因 / Clear cause
END_IF
IF _bCfgBad THEN
    _bFault := TRUE;                                                    // 组态非法锁存 / Latch illegal configuration
    _eCause := E_DL_SfcCause.eCfgIllegal;                               // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 2：平滑符号函数（过零段线性过渡，段外纯符号） —— *)
IF _bCfgBad THEN
    _fSign := 0.0;                                                      // 组态非法：符号不宣称（配合 fComp=0） / Illegal config: sign not claimed
ELSIF ABS(fVel) >= fVelZeroBand THEN
    IF fVel > 0.0 THEN
        _fSign := DL_SFC_ONE;                                           // 正速度纯符号 +1 / Positive velocity, sign +1
    ELSE
        _fSign := -DL_SFC_ONE;                                          // 负速度纯符号 −1 / Negative velocity, sign -1
    END_IF
ELSE
    _fSign := fVel / fVelZeroBand;                                      // 带内线性过渡，分母已过零闸 / Linear in-band transition, denominator gated
END_IF

(* —— 段 3：Stribeck 三段补偿量（指数项 + 黏滞项，未限幅） —— *)
IF _bCfgBad THEN
    _fRaw := 0.0;                                                       // 组态非法：补偿量置 0（安全侧） / Illegal config: compensation zeroed
ELSE
    IF ABS(fVel) >= (fVelZeroBand * DL_SFC_BAND_X3) THEN
        _eState := E_DL_SfcRegion.eViscous;                             // 黏滞主导段 / Viscous dominated region
    ELSIF ABS(fVel) >= fVelZeroBand THEN
        _eState := E_DL_SfcRegion.eStribeck;                            // Stribeck 过渡段 / Stribeck transition region
    ELSE
        _eState := E_DL_SfcRegion.eStiction;                            // 预滑段 / Pre-sliding region
    END_IF
    _fStrib := fStiction * EXP(-ABS(fVel) / fStribeckVel);              // Stribeck 指数项（分母已闸） / Stribeck exponential, denominator gated
    _fRaw   := (fCoulomb + _fStrib) * _fSign + (fViscous * fVel);       // 三段合一时 / Combined three-region model
END_IF

(* —— 段 4：硬限饱和（饱和即置 bLimited，饱和不等于故障） —— *)
fComp    := 0.0;                                                        // 补偿出口每拍预清 / Compensation outlet preset
bLimited := FALSE;                                                      // 触限位每拍预清 / Limited flag preset
IF bEnable AND (NOT _bCfgBad) THEN
    IF _fRaw > fCompMax THEN
        fComp    := fCompMax;                                           // 正向上限饱和 / Saturate at the positive limit
        bLimited := TRUE;                                               // 触限 / Limited
    ELSIF _fRaw < -fCompMax THEN
        fComp    := -fCompMax;                                          // 负向下限饱和 / Saturate at the negative limit
        bLimited := TRUE;                                               // 触限 / Limited
    ELSE
        fComp := _fRaw;                                                 // 未触限直通 / Pass through when within limits
    END_IF
ELSE
    fComp := 0.0;                                                       // 未使能或组态非法：冻结注入为 0（R191 语义声明） / Disabled or illegal: injection frozen at 0
END_IF

(* —— 段 5：段别机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_SfcRegion.eStiction:
    ;                                                                   // 预滑段：段别已在段 3 判定，此处无额外动作 / Region already decided in stage 3
E_DL_SfcRegion.eStribeck:
    ;                                                                   // 过渡段：段别已在段 3 判定 / Region already decided in stage 3
E_DL_SfcRegion.eViscous:
    ;                                                                   // 黏滞段：段别已在段 3 判定 / Region already decided in stage 3

ELSE
    IF _bFault THEN
        _eState := E_DL_SfcRegion.eFault;                               // 故障相：段别出口明确为故障 / Fault region explicit
    ELSIF NOT bEnable THEN
        _eState := E_DL_SfcRegion.eOff;                                 // 未使能：段别出口明确为关断 / Off region explicit
    ELSE
        _eCause := E_DL_SfcCause.ePhaseBad;                             // 归因：非法段别 / Cause: illegal region
        _eState := E_DL_SfcRegion.eFault;                               // 兜底强拉故障 / Fallback to fault
    END_IF

END_CASE

(* —— 段 6：出口单点映射（名实双出口，R191） —— *)
IF _bFault THEN
    eRegion := E_DL_SfcRegion.eFault;                                   // 故障相段别 / Fault region
ELSE
    eRegion := _eState;                                                 // 正常段别 / Nominal region
END_IF
fSignSoft := _fSign;                                                    // 平滑符号出口 / Smoothed sign outlet
eState    := eRegion;                                                   // 状态出口与段别同源 / State outlet mirrors the region
eCause    := _eCause;                                                   // 成因出口 / Cause outlet
bError    := _bFault;                                                   // 故障标志与锁存同源 / Error flag from latch

END_FUNCTION_BLOCK
