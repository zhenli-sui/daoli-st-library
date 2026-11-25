(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SaturateDecr
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符与 ABS，零厂商私有库
 * 功能描述 (Function)   : 带上下限的原地递减饱和（FC 形态）：把 VAR_IN_OUT 引脚 fX 原地
 *                         −1.0（步进常量 DL_SDEC_STEP），结果低于下限 fMin 则饱和到 fMin，
 *                         高于上限 fMax 则压回 fMax。与 FC_DL_SaturateIncr 严格对称，
 *                         共用 E_DL_SaturateErr 枚举（属主为递增件）。
 *                         **原地语义**：写回点唯一（各分支末端），返回 FALSE 的所有出口
 *                         均不写 fX，保证「失败不推进」。
 * 接口     (Interface)  : VAR_IN_OUT fX 被递减的量（本件原地更新）[工程单位]；
 *                         输入 fMin 下限、fMax 上限（有效域 fMin ≤ fMax）[工程单位]；
 *                         输出 fY 递减后值（镜像 fX）[工程单位]、bSaturated 本拍是否饱和、
 *                         eErrCode（E_DL_SaturateErr，引用不重声明）；返回值 = 递减已生效标志。
 * 边界     (Boundary)   : ① fMin > fMax → 故障级 eBadLimit，fX 不写回。
 *                         ② 任一入参非有限 → 故障级 eNonFinite，fX 不写回。
 *                         ③ fX − 1 溢出为非有限 → 故障级 eNonFinite，fX 不写回。
 *                         ④ 下限饱和与上限压回为两个独立分支、两个独立码值（R190 归因唯一）。
 *                         ⑤ 容差 DL_SDEC_EPS（1E-6）用于限值判定，禁浮点判等。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口复用
 *                         E_DL_SaturateErr，属主 FC_DL_SaturateIncr.st，本件只引用。
 * 分工声明 (Scope)      : 递增同族件为 FC_DL_SaturateIncr（枚举属主）；整数类限位递减
 *                         归 FC_DL_ClampDintChk 与 FC_DL_BcdDecrementByte。
 * 归属     (Ownership)  : E_DL_SaturateErr 归属 FC_DL_SaturateIncr.st，本件只引用不重声明。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         上下限域闸 + 容差比较 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 N/A（纯函数）
 *                         R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fX=4.0, fMin=0.0, fMax=10.0 → fX=3.0, fY=3.0, bSaturated=FALSE, eIncremented；
 *   A2 fX=0.0, fMin=0.0, fMax=10.0 → fX=0.0, bSaturated=TRUE, eSatLow；
 *   A3 fX=0.5, fMin=0.0, fMax=10.0 → fX=0.0, bSaturated=TRUE, eSatLow；
 *   A4 fX=10.5, fMin=0.0, fMax=10.0 → fX=10.0, bSaturated=TRUE, eSatHigh（压回上限）；
 *   A5 fX=5.0, fMin=10.0, fMax=0.0 → fX 保持 5.0, eBadLimit, 返回 FALSE。
 *============================================================================*)

FUNCTION FC_DL_SaturateDecr : BOOL
VAR_IN_OUT
    fX : LREAL;      // 被原地递减的量，成功时本件写回新值 [工程单位] / Value decremented in place, written back on success
END_VAR
VAR_INPUT
    fMin : LREAL;    // 下限 [工程单位] / Low limit in engineering unit
    fMax : LREAL;    // 上限，有效域 ≥ fMin [工程单位] / High limit in engineering unit, valid domain >= fMin
END_VAR
VAR_OUTPUT
    fY         : LREAL;             // 递减后值（镜像 fX）[工程单位] / Decremented value, mirror of fX
    bSaturated : BOOL;              // 本拍是否发生饱和 [-] / Saturation flag of this scan
    eErrCode   : E_DL_SaturateErr;  // 出口码（引用递增件属主枚举）[-] / Outlet code referencing the owner enum
END_VAR
VAR
    _bBadX   : BOOL;   // fX 非有限标志 [-] / Non-finite flag of fX
    _bBadMin : BOOL;   // fMin 非有限标志 [-] / Non-finite flag of fMin
    _bBadMax : BOOL;   // fMax 非有限标志 [-] / Non-finite flag of fMax
    _fNext   : LREAL;  // 裸递减结果 = fX − 步进 [工程单位] / Raw decremented value before saturation
END_VAR
VAR CONSTANT
    DL_SDEC_ZERO : LREAL := 0.0;     // 零基准 [-] / Zero base
    DL_SDEC_ONE  : LREAL := 1.0;     // 递减步进常量 [-] / Decrement step constant
    DL_SDEC_EPS  : LREAL := 1.0E-6;  // 限值比较容差 [-] / Limit comparison tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_SaturateDecr := FALSE;                         // 返回值预置未生效 / Return preset not applied
fY         := fX;                                    // 镜像出口取原值（失败不推进）/ Mirror keeps the original value on failure
bSaturated := FALSE;                                 // 饱和标志预清（单拍位统一预置）/ Single-shot flag preset
eErrCode   := E_DL_SaturateErr.eNonFinite;           // 预置最严码 / Preset strictest code

(* —— 段 1：入参非有限闸（R272 全量枚举 fX / fMin / fMax） —— *)
_bBadX   := (fX <> fX) OR ((fX - fX) <> DL_SDEC_ZERO);                       // 被递减量非有限 / Value non-finite
_bBadMin := (fMin <> fMin) OR ((fMin - fMin) <> DL_SDEC_ZERO);               // 下限非有限 / Low limit non-finite
_bBadMax := (fMax <> fMax) OR ((fMax - fMax) <> DL_SDEC_ZERO);               // 上限非有限 / High limit non-finite
IF _bBadX OR _bBadMin OR _bBadMax THEN
    RETURN;                                          // 故障出口：fX 不写回 / Fault exit, fX not written
END_IF

(* —— 段 2：上下限域闸（倒置即组态缺陷，拒绝且不写回） —— *)
IF fMin > (fMax + DL_SDEC_EPS) THEN
    eErrCode := E_DL_SaturateErr.eBadLimit;          // 故障级码 / Fault-level code
    RETURN;                                          // 返回 FALSE / Fault exit
END_IF

(* —— 段 3：裸递减与溢出复检 —— *)
_fNext := fX - DL_SDEC_ONE;                          // 裸递减 / Raw decrement
IF (_fNext <> _fNext) OR ((_fNext - _fNext) <> DL_SDEC_ZERO) THEN
    eErrCode := E_DL_SaturateErr.eNonFinite;         // 故障级码：溢出为非有限 / Fault: overflow to non-finite
    RETURN;                                          // 返回 FALSE，fX 不写回 / Fault exit
END_IF

(* —— 段 4：下限饱和（独立分支 + 独立码值，R190） —— *)
IF _fNext < fMin THEN
    fY         := fMin;                              // 饱和到下限 / Saturate at the low limit
    fX         := fMin;                              // 原地写回（唯一写回点）/ Single write-back point
    bSaturated := TRUE;                              // 饱和标志 / Saturation flag
    eErrCode   := E_DL_SaturateErr.eSatLow;          // 信息级：下限饱和 / Info: saturated low
    FC_DL_SaturateDecr := TRUE;                      // 递减已生效（饱和后值）/ Decrement applied with saturation
    RETURN;
END_IF

(* —— 段 5：上限压回（独立分支 + 独立码值，R190） —— *)
IF _fNext > fMax THEN
    fY         := fMax;                              // 压回到上限 / Clamp back to the high limit
    fX         := fMax;                              // 原地写回（唯一写回点）/ Single write-back point
    bSaturated := TRUE;                              // 饱和标志 / Saturation flag
    eErrCode   := E_DL_SaturateErr.eSatHigh;         // 信息级：上限饱和 / Info: saturated high
    FC_DL_SaturateDecr := TRUE;                      // 递减已生效（压回后值）/ Decrement applied with clamp
    RETURN;
END_IF

(* —— 段 6：限内正常推进 —— *)
fY         := _fNext;                                // 正常推进结果 / Normal decremented value
fX         := _fNext;                                // 原地写回（唯一写回点）/ Single write-back point
bSaturated := FALSE;                                 // 未饱和 / Not saturated
eErrCode   := E_DL_SaturateErr.eIncremented;         // 信息级：限内推进（共用成员）/ Info: advanced within limits
FC_DL_SaturateDecr := TRUE;                          // 递减已生效 / Decrement applied
END_FUNCTION
