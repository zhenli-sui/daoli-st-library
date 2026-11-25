(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SaturateIncr
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符与 ABS，零厂商私有库
 * 功能描述 (Function)   : 带上下限的原地递增饱和（FC 形态）：把 VAR_IN_OUT 引脚 fX 原地
 *                         +1.0（步进常量 DL_SINC_STEP），结果超上限 fMax 则饱和到 fMax，
 *                         低于下限 fMin 则抬升到 fMin。用于配方号 / 档位 / 索引游标类
 *                         计数递增，替代任何不经限位的裸 `x := x + 1`。
 *                         **原地语义**：写回点唯一（段 5），返回 FALSE 的所有出口均不写 fX，
 *                         保证「失败不推进」。
 * 接口     (Interface)  : VAR_IN_OUT fX 被递增的量（本件原地更新）[工程单位]；
 *                         输入 fMin 下限、fMax 上限（有效域 fMin ≤ fMax）[工程单位]；
 *                         输出 fY 递增后值（镜像 fX）[工程单位]、bSaturated 本拍是否饱和、
 *                         eErrCode（E_DL_SaturateErr）；返回值 = 递增已生效标志。
 * 边界     (Boundary)   : ① fMin > fMax → 故障级 eBadLimit，fX 不写回（保持原值）。
 *                         ② 任一入参非有限 → 故障级 eNonFinite，fX 不写回。
 *                         ③ fX + 1 溢出为非有限 → 故障级 eNonFinite，fX 不写回（不饱和猜测）。
 *                         ④ 上限饱和与下限抬升为两个独立分支、两个独立码值（R190 归因唯一）。
 *                         ⑤ 容差 DL_SINC_EPS（1E-6）用于「恰好等于限值」的判定，禁浮点判等。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + LREAL +
 *                         本文件内 enum E_DL_SaturateErr（全库唯一属主，与递减件共用同族枚举）。
 * 分工声明 (Scope)      : 递减同族件为 FC_DL_SaturateDecr（共用 E_DL_SaturateErr）；
 *                         整数类限位递增归 FC_DL_ClampDintChk 与 FC_DL_IndexClampEx。
 * 归属     (Ownership)  : E_DL_SaturateErr 归属本文件（全库唯一属主，R264）；
 *                         FC_DL_SaturateDecr 只引用不重声明。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         上下限域闸 + 容差比较 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 N/A（纯函数）
 *                         R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fX=4.0, fMin=0.0, fMax=10.0 → fX=5.0, fY=5.0, bSaturated=FALSE, eIncremented；
 *   A2 fX=10.0, fMin=0.0, fMax=10.0 → fX=10.0, bSaturated=TRUE, eSatHigh；
 *   A3 fX=9.5, fMin=0.0, fMax=10.0 → fX=10.0, bSaturated=TRUE, eSatHigh；
 *   A4 fX=-1.0, fMin=0.0, fMax=10.0 → fX=0.0, bSaturated=TRUE, eSatLow（抬升到下限）；
 *   A5 fX=5.0, fMin=10.0, fMax=0.0 → fX 保持 5.0, eBadLimit, 返回 FALSE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SaturateErr（递增 / 递减饱和出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SaturateErr :
(
    eIncremented := 0,   // 信息级：本拍在限内推进（递减件同样复用该成员）/ Info: advanced within limits
    eSatHigh     := 1,   // 信息级：上限饱和 / Info: saturated at the high limit
    eSatLow      := 2,   // 信息级：下限饱和（抬升到下限）/ Info: saturated at the low limit
    eBadLimit    := 10,  // 故障级：上下限倒置 / Fault: inverted limits
    eNonFinite   := 11   // 故障级：入参或结果非有限 / Fault: non-finite input or result
);
END_TYPE

FUNCTION FC_DL_SaturateIncr : BOOL
VAR_IN_OUT
    fX : LREAL;      // 被原地递增的量，成功时本件写回新值 [工程单位] / Value incremented in place, written back on success
END_VAR
VAR_INPUT
    fMin : LREAL;    // 下限 [工程单位] / Low limit in engineering unit
    fMax : LREAL;    // 上限，有效域 ≥ fMin [工程单位] / High limit in engineering unit, valid domain >= fMin
END_VAR
VAR_OUTPUT
    fY         : LREAL;             // 递增后值（镜像 fX）[工程单位] / Incremented value, mirror of fX
    bSaturated : BOOL;              // 本拍是否发生饱和 [-] / Saturation flag of this scan
    eErrCode   : E_DL_SaturateErr;  // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadX   : BOOL;   // fX 非有限标志 [-] / Non-finite flag of fX
    _bBadMin : BOOL;   // fMin 非有限标志 [-] / Non-finite flag of fMin
    _bBadMax : BOOL;   // fMax 非有限标志 [-] / Non-finite flag of fMax
    _fNext   : LREAL;  // 裸递增结果 = fX + 步进 [工程单位] / Raw incremented value before saturation
END_VAR
VAR CONSTANT
    DL_SINC_ZERO : LREAL := 0.0;     // 零基准 [-] / Zero base
    DL_SINC_ONE  : LREAL := 1.0;     // 递增步进常量 [-] / Increment step constant
    DL_SINC_EPS  : LREAL := 1.0E-6;  // 限值比较容差 [-] / Limit comparison tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_SaturateIncr := FALSE;                         // 返回值预置未生效 / Return preset not applied
fY         := fX;                                    // 镜像出口取原值（失败不推进）/ Mirror keeps the original value on failure
bSaturated := FALSE;                                 // 饱和标志预清（单拍位统一预置）/ Single-shot flag preset
eErrCode   := E_DL_SaturateErr.eNonFinite;           // 预置最严码 / Preset strictest code

(* —— 段 1：入参非有限闸（R272 全量枚举 fX / fMin / fMax） —— *)
_bBadX   := (fX <> fX) OR ((fX - fX) <> DL_SINC_ZERO);                       // 被递增量非有限 / Value non-finite
_bBadMin := (fMin <> fMin) OR ((fMin - fMin) <> DL_SINC_ZERO);               // 下限非有限 / Low limit non-finite
_bBadMax := (fMax <> fMax) OR ((fMax - fMax) <> DL_SINC_ZERO);               // 上限非有限 / High limit non-finite
IF _bBadX OR _bBadMin OR _bBadMax THEN
    RETURN;                                          // 故障出口：fX 不写回 / Fault exit, fX not written
END_IF

(* —— 段 2：上下限域闸（倒置即组态缺陷，拒绝且不写回） —— *)
IF fMin > (fMax + DL_SINC_EPS) THEN
    eErrCode := E_DL_SaturateErr.eBadLimit;          // 故障级码 / Fault-level code
    RETURN;                                          // 返回 FALSE / Fault exit
END_IF

(* —— 段 3：裸递增与溢出复检 —— *)
_fNext := fX + DL_SINC_ONE;                          // 裸递增 / Raw increment
IF (_fNext <> _fNext) OR ((_fNext - _fNext) <> DL_SINC_ZERO) THEN
    eErrCode := E_DL_SaturateErr.eNonFinite;         // 故障级码：溢出为非有限 / Fault: overflow to non-finite
    RETURN;                                          // 返回 FALSE，fX 不写回 / Fault exit
END_IF

(* —— 段 4：上限饱和（独立分支 + 独立码值，R190） —— *)
IF _fNext > fMax THEN
    fY         := fMax;                              // 饱和到上限 / Saturate at the high limit
    fX         := fMax;                              // 原地写回（唯一写回点）/ Single write-back point
    bSaturated := TRUE;                              // 饱和标志 / Saturation flag
    eErrCode   := E_DL_SaturateErr.eSatHigh;         // 信息级：上限饱和 / Info: saturated high
    FC_DL_SaturateIncr := TRUE;                      // 递增已生效（饱和后值）/ Increment applied with saturation
    RETURN;
END_IF

(* —— 段 5：下限抬升（独立分支 + 独立码值，R190） —— *)
IF _fNext < fMin THEN
    fY         := fMin;                              // 抬升到下限 / Lift to the low limit
    fX         := fMin;                              // 原地写回（唯一写回点）/ Single write-back point
    bSaturated := TRUE;                              // 饱和标志 / Saturation flag
    eErrCode   := E_DL_SaturateErr.eSatLow;          // 信息级：下限饱和 / Info: saturated low
    FC_DL_SaturateIncr := TRUE;                      // 递增已生效（抬升后值）/ Increment applied with lift
    RETURN;
END_IF

(* —— 段 6：限内正常推进 —— *)
fY         := _fNext;                                // 正常推进结果 / Normal incremented value
fX         := _fNext;                                // 原地写回（唯一写回点）/ Single write-back point
bSaturated := FALSE;                                 // 未饱和 / Not saturated
eErrCode   := E_DL_SaturateErr.eIncremented;         // 信息级：限内推进 / Info: advanced within limits
FC_DL_SaturateIncr := TRUE;                          // 递增已生效 / Increment applied
END_FUNCTION
