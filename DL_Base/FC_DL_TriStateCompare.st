(*
  ==================================================================
  组件名 Component  : FC_DL_TriStateCompare
  分类   Category   : DL_Base
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0660（故障级）｜ 16#0001_0661（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : 三态比较器：fA 与 fB 的归一判定返回 -1 / 0 / +1（小于 /
                      容差内相等 / 大于），fEps 为浮点容差闸；供排序分发、
                      分档判定、死区判断等调用方做无歧义三分支分发。
  开源溯源 Origin    : 西门子 LGF V5.3.0（文档 ID 109479728）Comparator 组
                      「比较结果归一化分级」分类事实借鉴（只借骨不抄肉）；
                      fEps 容差判据与全部实现 clean-room，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.1 比较运算符与选择语义
  平台   Platform   : 纯 IEC 61131-3（ABS / 比较 / 四则），三平台通用
  依赖   Depends    : 无（零委托、零库件）
  分工声明 Split     : FC_DL_Hysteresis（迟滞切换，带历史态）/ FC_DL_LimitClassify
                      （单点 → 档位，多档分发）与本件互引；本件为两值 → 三态
                      的最小归一原子，不带历史态、不分多档（R216）。
  归属 Ownership     : 本件无 TYPE 声明；返回值用 IEC 原生 DINT 三值语义
                      （-1 / 0 / +1），不另立枚举（三态已由返回值契约穷尽）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限闸（fA / fB / fEps 逐个点名，R272）：任一非有限
                         → 故障级 0660 + 返回 0 哨兵 + bValid = FALSE + 早退
                         （禁 NaN 参与比较产生伪三态）；
                      二 fEps 域闸：负容差非法 → 钳到 0 并置信息级 0661
                         （不置 bError，钳位后按严格比较继续，出口可用）；
                         fEps = 0 合法（退化为严格比较口径）；
                      三 判定口径：fDiff = fA - fB；fDiff > fEps → +1；
                         fDiff < -fEps → -1；其余 → 0（容差带内归零）；
                      四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      五 无除法、无循环、无数组访问：不存在除零 / 越界风险；
                      六 无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0001_0660【故障级】输入非有限（fA / fB / fEps 为 NaN / ±Inf）
    16#0001_0661【信息级】fEps 为负已钳到 0（按严格比较继续，不置 bError）
  码位反证 Note     :
    0660 与 0661 不可合并：0660 出口 bValid = FALSE（结果不可用），0661 出口
    bValid = TRUE（钳位后结果可用），bValid 可唯一区分两场景，按 R90 分立。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 fA = 3.0、fB = 1.0、fEps = 1E-6 → +1；V2 对调入参 → -1
    V3 fA = 1.0、fB = 1.0 + 1E-9、fEps = 1E-6 → 0（容差带内归零）
    V4 fA = NaN → 码 0660 + bValid = FALSE + 返回 0
    V5 fEps = -1.0 → 钳 0 + 码 0661（bError = FALSE，bValid = TRUE）
    V6 fEps = 0、fA = fB → 0（严格比较口径）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 1 · 序号 1，LGF Comparator 组第 7 件）
  ==================================================================
*)
FUNCTION FC_DL_TriStateCompare : DINT
VAR_INPUT
    fA   : LREAL := 0.0;    // 比较左值 [工程单位]，必须有限 / the left operand, must be finite
    fB   : LREAL := 0.0;    // 比较右值 [工程单位]，必须有限 / the right operand, must be finite
    fEps : LREAL := 1.0E-6; // 容差 [工程单位]，≥ 0，负值钳 0 / the tolerance, non negative, a negative value is clamped to zero
END_VAR
VAR_OUTPUT
    bValid : BOOL;  // 判定可用 [-] / the verdict is usable
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    fDiff  : LREAL := 0.0; // 差值工作副本 fA - fB [工程单位] / the difference working copy of the left minus the right
    fEpsUse: LREAL := 0.0; // 容差工作副本（钳位后）[工程单位] / the tolerance working copy after the clamp
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_TSC_ZERO  : LREAL := 0.0;   // 实数零常量 [工程单位] / the real zero constant
    DL_TSC_EPSMIN: LREAL := 1.0E-6; // 默认容差常量 [工程单位] / the default tolerance constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_TriStateCompare := 0; // 返回值预置 0 哨兵（不可判语义）/ preset the return to the zero sentinel
bValid := FALSE; // 判定可用预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
fDiff := DL_TSC_ZERO; // 差值工作副本预置零 [工程单位] / preset the difference copy zero
fEpsUse := DL_TSC_EPSMIN; // 容差工作副本预置默认容差 [工程单位] / preset the tolerance copy to the default

// 段 2｜非有限闸（边界一，逐个点名，R272）/ segment 2, the finiteness gate over all three operands
IF (fA <> fA) OR ((fA - fA) <> (fA - fA))
OR (fB <> fB) OR ((fB - fB) <> (fB - fB))
OR (fEps <> fEps) OR ((fEps - fEps) <> (fEps - fEps)) THEN // 任一操作数非有限（NaN 或 ±Inf）/ any operand is not finite
    eErr := 16#0001_0660; // 故障级：输入非有限 / fault grade, an input is not finite
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 判定不可用 / the verdict is not usable
    RETURN; // 早退，返回 0 哨兵 / early return with the zero sentinel
END_IF

// 段 3｜fEps 域闸（边界二：负容差钳 0 + 信息级）/ segment 3, the tolerance domain gate
fEpsUse := fEps; // 容差接管 [工程单位] / take the tolerance
IF fEpsUse < DL_TSC_ZERO THEN // 负容差非法 / a negative tolerance is illegal
    fEpsUse := DL_TSC_ZERO; // 钳到 0（严格比较口径）/ clamp to zero, the strict comparison
    eErr := 16#0001_0661; // 信息级：负容差已钳 0（不置 bError，R285）/ informational, the negative tolerance was clamped
    bError := FALSE; // 信息级不置故障标志 / keep the fault flag false, this is informational
END_IF

// 段 4｜三态判定（边界三，容差带内归零）/ segment 4, the tri state verdict inside the tolerance band
fDiff := fA - fB; // 差值 [工程单位] / the difference
IF fDiff > fEpsUse THEN // 左值显著大于右值 / the left is significantly greater
    FC_DL_TriStateCompare := 1; // 三态 +1 / the plus one state
    bValid := TRUE; // 判定可用 / the verdict is usable
ELSIF fDiff < -fEpsUse THEN // 左值显著小于右值 / the left is significantly smaller
    FC_DL_TriStateCompare := -1; // 三态 -1 / the minus one state
    bValid := TRUE; // 判定可用 / the verdict is usable
ELSE // 容差带内归零 / inside the tolerance band
    FC_DL_TriStateCompare := 0; // 三态 0（相等）/ the zero state, an equality
    bValid := TRUE; // 判定可用 / the verdict is usable
END_IF
END_FUNCTION
