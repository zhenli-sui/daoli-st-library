(*
  ==================================================================
  组件名 Component  : FC_DL_IntervalGapCalc
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0665（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 两区间相离间隙计算：相离返回正间隙宽 [工程单位]，相接 /
                      重叠 / 包含返回 0 并带关系码；供工艺窗对撞分析、换型
                      死区校验、安全包络间距核算等调用方使用。
  开源溯源 Origin    : 西门子 LGF V5.3.0 Comparator 组「区间关系」分类事实
                      借鉴（只借骨不抄肉，与 R11 RangeOverlapCheck 同组既有
                      件互引）；间隙计算 clean-room，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.1 比较 / MAX 语义
  平台   Platform   : 纯 IEC 61131-3（MAX / ABS / 比较），三平台通用
  依赖   Depends    : 无（零委托、零库件）
  分工声明 Split     : FC_DL_RangeOverlapCheck（五分支关系判定，输出重叠长度）
                      为姊妹件（互引）；本件为「间隙方向」补口：输出相离
                      间隙宽（RangeOverlapCheck 只输出重叠长度，相离时恒 0，
                      间隙量不可观测），两件口径差异显式声明（R216）。
  归属 Ownership     : E_DL_IntervalGap 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限闸（四个端点 + fEps 逐个点名，R272）：任一
                         非有限 → 故障级 0665 + 返回 eInvalid + fGap = 0 +
                         bValid = FALSE + 早退；
                      二 端点归一：每区间无序端点自动对调，保证下限 ≤ 上限；
                      三 fEps 域闸：负容差非法 → 按默认容差 1.0E-6 接管并
                         并入 0665 处置（与端点非有限出口同形：eInvalid +
                         fGap = 0 + bValid = FALSE，反证句见码表）；
                      四 判定次序写死：相离（正间隙 > fEps）→ 相接（端点
                         重合在容差内）→ 包含 → 部分重叠；相离必须先于
                         相接，相接必须先于重叠（次序不可调换，防多解）；
                      五 完全相等归入 eContained（含端点重合的包含）：相等
                         是包含的退化特例，间隙同为 0，出口无法区分（R90
                         不另立关系码，与 RangeOverlapCheck 的 eEqual 五分
                         支口径差异显式声明）；
                      六 fGap 返回前置非负钳位：舍入产生的微小负值钳到 0；
                      七 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      八 无除法、无循环、无数组访问；无全局、无外部变量、
                         无物理地址。
  错误码 Codes      :
    16#0001_0665【故障级】输入非有限（四端点 / fEps 为 NaN / ±Inf）或 fEps
                         为负（组态非法）
  码位反证 Note     :
    0665 合并「端点 / 容差非有限」与「fEps 为负」的理由：两场景出口组合完全
    相同（eInvalid、fGap = 0、bValid = FALSE、bError = TRUE），三组以内输出
    无法唯一还原该场景，按 R90 不另立码；eInvalid 关系码与 0665 分立：前者
    是返回值语义（关系不可判），后者是诊断码，通道不同不互斥。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 相离：A = [0, 10]、B = [20, 30] → eDisjoint、fGap = 10.0
    V2 相接：A = [0, 10]、B = [10, 20] → eTouching、fGap = 0.0
    V3 部分重叠：A = [0, 10]、B = [5, 15] → eOverlap、fGap = 0.0
    V4 包含：A = [0, 10]、B = [2, 8] → eContained、fGap = 0.0
    V5 完全相等：A = B = [0, 10] → eContained（边界五口径）
    V6 无序端点：A = [10, 0] → 归一后同 V1
    V7 端点 NaN → 码 0665 + eInvalid + bValid = FALSE
    V8 fEps = -1.0 → 同码 0665（边界三）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 1 · 序号 4，LGF Comparator 区间间隙补口）
  ==================================================================
*)
TYPE E_DL_IntervalGap :
(
    eInvalid   := 0,  // 输入非法，关系不可判 / the inputs are illegal, the relation is undecidable
    eDisjoint  := 10, // 完全相离，存在正间隙 / fully disjoint with a positive gap
    eTouching  := 20, // 仅端点相接，间隙为零 / the endpoint touch only with a zero gap
    eOverlap   := 30, // 部分重叠，互不包含 / a partial overlap, neither contains the other
    eContained := 40  // 一方包含另一方（完全相等归入本档）/ one range contains the other, an equality is folded here
);
END_TYPE

FUNCTION FC_DL_IntervalGapCalc : E_DL_IntervalGap
VAR_INPUT
    fA1  : LREAL := 0.0;    // 区间 A 端点 1 [工程单位]，无序自动对调 / the range A endpoint one, auto swapped
    fA2  : LREAL := 10.0;   // 区间 A 端点 2 [工程单位] / the range A endpoint two
    fB1  : LREAL := 0.0;    // 区间 B 端点 1 [工程单位]，无序自动对调 / the range B endpoint one, auto swapped
    fB2  : LREAL := 10.0;   // 区间 B 端点 2 [工程单位] / the range B endpoint two
    fEps : LREAL := 1.0E-6; // 容差 [工程单位]，≥ 0 / the tolerance, non negative
END_VAR
VAR_OUTPUT
    fGap   : LREAL; // 相离间隙宽 [工程单位]，恒非负，非相离 = 0.0 / the gap width, never negative, zero unless disjoint
    bValid : BOOL;  // 结果可用 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _fLoA   : LREAL := 0.0; // 区间 A 归一下限 [工程单位] / the normalised lower bound of the range A
    _fHiA   : LREAL := 0.0; // 区间 A 归一上限 [工程单位] / the normalised upper bound of the range A
    _fLoB   : LREAL := 0.0; // 区间 B 归一下限 [工程单位] / the normalised lower bound of the range B
    _fHiB   : LREAL := 0.0; // 区间 B 归一上限 [工程单位] / the normalised upper bound of the range B
    _fTmp   : LREAL := 0.0; // 对调临时量 [工程单位] / the swap temporary
    _fGapUse: LREAL := 0.0; // 间隙工作副本 [工程单位] / the gap working copy
    _fEpsUse: LREAL := 0.0; // 容差工作副本 [工程单位] / the tolerance working copy
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_IGP_ZERO : LREAL := 0.0;    // 实数零常量 [工程单位] / the real zero constant
    DL_IGP_EPSDF: LREAL := 1.0E-6; // 默认容差常量 [工程单位]（fEps 非法时接管）/ the default tolerance taken over when the input is illegal
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_IntervalGapCalc := E_DL_IntervalGap.eInvalid; // 返回值预置不可判（任何早退天然带不可判语义）/ preset the return to undecidable
fGap := DL_IGP_ZERO; // 间隙预置零 [工程单位] / preset the gap zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
_fLoA := DL_IGP_ZERO; // 归一下限 A 预置零 / preset the lower bound A zero
_fHiA := DL_IGP_ZERO; // 归一上限 A 预置零 / preset the upper bound A zero
_fLoB := DL_IGP_ZERO; // 归一下限 B 预置零 / preset the lower bound B zero
_fHiB := DL_IGP_ZERO; // 归一上限 B 预置零 / preset the upper bound B zero
_fTmp := DL_IGP_ZERO; // 对调临时量预置零 / preset the swap temporary zero
_fGapUse := DL_IGP_ZERO; // 间隙工作副本预置零 / preset the gap copy zero
_fEpsUse := DL_IGP_EPSDF; // 容差工作副本预置默认容差 / preset the tolerance copy to the default

// 段 2｜非有限闸与容差域闸（边界一 / 边界三，逐个点名，R272）/ segment 2, the finiteness gate and the tolerance gate
IF (fA1 <> fA1) OR ((fA1 - fA1) <> (fA1 - fA1))
OR (fA2 <> fA2) OR ((fA2 - fA2) <> (fA2 - fA2))
OR (fB1 <> fB1) OR ((fB1 - fB1) <> (fB1 - fB1))
OR (fB2 <> fB2) OR ((fB2 - fB2) <> (fB2 - fB2))
OR (fEps <> fEps) OR ((fEps - fEps) <> (fEps - fEps))
OR (fEps < DL_IGP_ZERO) THEN // 任一端点 / 容差非有限或容差为负 / any endpoint or the tolerance is not finite or negative
    eErr := 16#0001_0665; // 故障级：输入非有限或容差非法（出口同形合并一码，R90）/ fault grade under the merged code
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，返回 eInvalid / early return with undecidable
END_IF
_fEpsUse := fEps; // 容差接管（已证非负有限）[工程单位] / take the tolerance proven nonnegative and finite

// 段 3｜端点归一（边界二：无序端点自动对调）/ segment 3, the endpoint normalisation with the auto swap
_fLoA := fA1; // A 下限暂存端点 1 / the A lower takes the endpoint one
_fHiA := fA2; // A 上限暂存端点 2 / the A upper takes the endpoint two
IF _fLoA > _fHiA THEN // A 端点逆序 / the A endpoints in reverse order
    _fTmp := _fLoA; // 暂存下限 / save the lower
    _fLoA := _fHiA; // 下限取原上限 / the lower takes the former upper
    _fHiA := _fTmp; // 上限取原下限 / the upper takes the former lower
END_IF
_fLoB := fB1; // B 下限暂存端点 1 / the B lower takes the endpoint one
_fHiB := fB2; // B 上限暂存端点 2 / the B upper takes the endpoint two
IF _fLoB > _fHiB THEN // B 端点逆序 / the B endpoints in reverse order
    _fTmp := _fLoB; // 暂存下限 / save the lower
    _fLoB := _fHiB; // 下限取原上限 / the lower takes the former upper
    _fHiB := _fTmp; // 上限取原下限 / the upper takes the former lower
END_IF

// 段 4｜关系与间隙判定（边界四：次序写死，相离 → 相接 → 包含 → 重叠）/ segment 4, the relation and gap in the frozen order
IF (_fLoB - _fHiA) > _fEpsUse THEN // B 整体在 A 右侧且存在正间隙 / the B sits right with a positive gap
    _fGapUse := _fLoB - _fHiA; // 间隙 = B 下限 − A 上限 [工程单位] / the gap of the B lower minus the A upper
    FC_DL_IntervalGapCalc := E_DL_IntervalGap.eDisjoint; // 相离关系 / the disjoint relation
ELSIF (_fLoA - _fHiB) > _fEpsUse THEN // A 整体在 B 右侧且存在正间隙 / the A sits right with a positive gap
    _fGapUse := _fLoA - _fHiB; // 间隙 = A 下限 − B 上限 [工程单位] / the gap of the A lower minus the B upper
    FC_DL_IntervalGapCalc := E_DL_IntervalGap.eDisjoint; // 相离关系 / the disjoint relation
ELSIF (ABS(_fHiA - _fLoB) < _fEpsUse) OR (ABS(_fHiB - _fLoA) < _fEpsUse) THEN // 端点几何重合（容差内）/ the endpoints coincide inside the tolerance
    _fGapUse := DL_IGP_ZERO; // 相接间隙为零 [工程单位] / the touching gap zero
    FC_DL_IntervalGapCalc := E_DL_IntervalGap.eTouching; // 相接关系 / the touching relation
ELSIF ((_fLoA <= _fLoB + _fEpsUse) AND (_fHiA >= _fHiB - _fEpsUse))
OR ((_fLoB <= _fLoA + _fEpsUse) AND (_fHiB >= _fHiA - _fEpsUse)) THEN // 一方包含另一方（含完全相等退化特例，边界五）/ one contains the other, an equality folded in
    _fGapUse := DL_IGP_ZERO; // 包含间隙为零 [工程单位] / the contained gap zero
    FC_DL_IntervalGapCalc := E_DL_IntervalGap.eContained; // 包含关系 / the contained relation
ELSE // 部分重叠（互不包含，间隙恒 0）/ a partial overlap with a zero gap
    _fGapUse := DL_IGP_ZERO; // 重叠间隙为零 [工程单位] / the overlap gap zero
    FC_DL_IntervalGapCalc := E_DL_IntervalGap.eOverlap; // 部分重叠关系 / the partial overlap relation
END_IF

// 段 5｜间隙非负钳位与统一出口（边界六）/ segment 5, the nonnegative clamp and the unified outlet
IF _fGapUse < DL_IGP_ZERO THEN // 舍入产生微小负值 / a tiny negative from the rounding
    _fGapUse := DL_IGP_ZERO; // 钳到 0，维持非负承诺 / clamp to zero, keep the promise
END_IF
fGap := _fGapUse; // 间隙出口 [工程单位] / the gap outlet
bValid := TRUE; // 结果可用 / the result is usable
END_FUNCTION
