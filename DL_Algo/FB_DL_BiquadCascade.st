(*
  ==================================================================
  组件名 Component  : FB_DL_BiquadCascade
  分类   Category   : DL_Algo
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0002_3743 / 3744 / 3745 / 3748（故障级）
                      16#0002_3746 / 3747（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 高
  功能   Purpose    : 多节二阶 IIR 级联（≤ 4 节，Direct Form II 每节独立状态），
                      用于高阶滤波（8 阶 = 4 节）现场组合；逐节 Jury 稳定闸。
  开源溯源 Origin    : 公开公式 clean-room，参考公开 DSP 教科书的二阶节级联结构与
                      Jury 稳定判据（分类与公式借鉴，零代码复制），本件实现、闸门
                      与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；Jury 三条件 |a2|<1 ∧
                      1+a1+a2>0 ∧ 1−a1+a2>0（与返修件 FB_DL_BiquadFilter v1.0.1
                      同源固化判据）
  平台   Platform   : 纯 IEC 61131-3（FOR / CASE / 四则 / ABS / R_TRIG），三平台通用
  依赖   Depends    : 仅 Standard.library（R_TRIG 属标准边沿检测）
  分工声明 Split     : FB_DL_BiquadFilter 为单节属主（R63 返修件，Jury 判据同源）；
                      本件多节级联，单节需求禁用本件（状态开销 ×4）；互引并注明
                      选型对照见 MANUAL_DL_Algo（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 逐节 Jury 稳定闸（返修 R2 固化判据）：任一**活动节**
                         （i < nStages）NOT (ABS(a2)<1 AND (1+a1+a2)>0 AND
                         (1−a1+a2)>0) → bCfgBad + 故障级 3744 + 三件套 + RETURN
                         结构早退（fOut 冻结最后有效值）；未激活节（i >= nStages）
                         的系数**不参与判据**（死节坏系数不误锁，写死）；
                      二 活动节系数任一非有限 → 故障级 3745（与 Jury 越域分码，
                         处置人不同：数值平台 / 算法工程师，R90）；
                      三 nStages 越域（< 1 或 > 4）或钳位域非法（fOutMin > fOutMax
                         或限值非有限）→ 故障级 3743（两组态场景出口同形：冻结 +
                         bCfgBad，R90 不另立）；
                      四 系数变更沿（任一活动系数 |新 − 旧| > 1.0E-9）→ 全链状态
                         清零（防新旧系数混算，BiquadFilter 同口径）+ 信息级 3747；
                      五 输出钳位 + bSat + 末活动节 w1 抗 windup 回写；非有限复检
                         → 故障级 3748 + 全链状态清零；
                      六 bEnable = FALSE 的语义写死（FB33-4 声明行）：fOut := 0 +
                         全链状态清零 + bValid = FALSE（下游控制量失能须归零）；
                      七 故障码锁存至 bResetState 上升沿回放（FB33-1 / R152）；
                         信息级逐拍重算不锁存；
                      八 段 0 无条件刷新 R_TRIG；CASE 无（线性级联，R6 标注 N/A）；
                         首拍 _bInit 全量初始化；无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0002_3743【故障级】组态非法（nStages 越域 / 钳位域反序 / 限值非有限），锁存
    16#0002_3744【故障级】活动节系数越过 Jury 三条件稳定域，锁存
    16#0002_3745【故障级】活动节系数非有限（NaN 或 ±Inf），锁存
    16#0002_3748【故障级】输入 / 中间量 / 输出非有限（NaN 或 ±Inf），锁存
    16#0002_3746【信息级】本拍输出被钳位（bSat = TRUE，不锁存）
    16#0002_3747【信息级】系数变更沿触发全链状态清零（不锁存）
  码位反证 Note     :
    3743 / 3744 / 3745 / 3748 四码不可合并：四者的 bCfgBad 与 bValid 组合完全相同，
    但处置人不同（组态工程师 / 算法工程师 / 数值平台 / 现场仪表），仅靠输出组合无法
    还原成因，按 R90 分立（R90 反证句与返修件 FB_DL_BiquadFilter 同口径）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 4 节低通级联（每节 RBJ 巴特沃斯 2 阶）阶跃 → 单调收敛无发散
    V2 节 3 系数失稳（a2 = −1.5, a1 = −1.9 违 Jury）→ bCfgBad + 全链冻结 + 3744
    V3 nStages = 0 / = 5 → 越域故障早退（3743）
    V4 节 4 系数坏但 nStages = 2 → 不影响（死节豁免，边界一回归向量）
    V5 在线改节 1 系数 → 全链清零 + 3747
    V6 bEnable = FALSE → fOut = 0、全链状态零、bValid = FALSE
    V7 输出大信号钳位 + bSat + 3746
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 3 · 序号 8）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_BiquadCascade
VAR_INPUT
    bEnable     : BOOL := TRUE;    // 使能；FALSE 时输出归零并清全链状态（边界六）/ the enable, false zeroes the output and clears the chain
    bResetState : BOOL := FALSE;   // 状态复位电平，上升沿清全链状态与故障锁存 / the state reset level, its rising edge clears the chain and the fault latch
    fIn         : LREAL := 0.0;    // 输入量 [工程单位]，必须有限 / the input value, must be finite
    aB0         : ARRAY[0..3] OF LREAL; // 各节归一化前向系数 b0 [−] / the per stage normalized b0
    aB1         : ARRAY[0..3] OF LREAL; // 各节归一化前向系数 b1 [−] / the per stage normalized b1
    aB2         : ARRAY[0..3] OF LREAL; // 各节归一化前向系数 b2 [−] / the per stage normalized b2
    aA1         : ARRAY[0..3] OF LREAL; // 各节归一化反馈系数 a1 [−] / the per stage normalized a1
    aA2         : ARRAY[0..3] OF LREAL; // 各节归一化反馈系数 a2 [−] / the per stage normalized a2
    nStages     : DINT := 2;       // 节数 [节]，合法域 1..4 / the stage count, legal one to four
    fOutMin     : LREAL := -1.0E6; // 输出钳位域下界 [工程单位] / the output clamp floor
    fOutMax     : LREAL := 1.0E6;  // 输出钳位域上界 [工程单位] / the output clamp ceiling
END_VAR
VAR_OUTPUT
    fOut    : LREAL := 0.0;           // 滤波输出 [工程单位] / the filtered output
    bSat    : BOOL := FALSE;          // 本拍输出被钳位 [-] / the output was clamped on this scan
    bCfgBad : BOOL := FALSE;          // 组态非法（与故障锁存同源，锁存型）[-] / an illegal configuration latched with the fault
    bValid  : BOOL := FALSE;          // 输出可用 [-] / the output is usable
    eErr    : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL := FALSE;          // 故障锁存位（由锁存码派生，R99）/ the latched fault bit derived from the latched code
END_VAR
VAR
    _bInit   : BOOL := FALSE;                  // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _afW1    : ARRAY[0..3] OF LREAL;           // 各节状态 w1 [工程单位] / the per stage state w1
    _afW2    : ARRAY[0..3] OF LREAL;           // 各节状态 w2 [工程单位] / the per stage state w2
    _afB0Prev : ARRAY[0..3] OF LREAL;          // 上拍 b0 快照 [−] / the previous b0 snapshots
    _afB1Prev : ARRAY[0..3] OF LREAL;          // 上拍 b1 快照 [−] / the previous b1 snapshots
    _afB2Prev : ARRAY[0..3] OF LREAL;          // 上拍 b2 快照 [−] / the previous b2 snapshots
    _afA1Prev : ARRAY[0..3] OF LREAL;          // 上拍 a1 快照 [−] / the previous a1 snapshots
    _afA2Prev : ARRAY[0..3] OF LREAL;          // 上拍 a2 快照 [−] / the previous a2 snapshots
    _fW      : LREAL := 0.0;                   // 本拍节内中间量 w [工程单位] / the intermediate w of this scan
    _fY      : LREAL := 0.0;                   // 本拍节内输出 y（级联传递量）[工程单位] / the stage output passed down the chain
    _fOutLast: LREAL := 0.0;                   // 最近一次有效输出（故障冻结源）[工程单位] / the last valid output used while frozen
    _nUse    : DINT := 0;                      // 钳位后的节数 [节] / the clamped stage count
    _i       : DINT := 0;                      // 节遍历索引 [下标] / the stage traversal index
    _iClr    : DINT := 0;                      // 清零遍历索引 [下标] / the clearing traversal index
    _bFinCoef: BOOL := FALSE;                  // 活动节系数有限闸结果（逐拍重算）/ the active stage finiteness gate result
    _bFinIn  : BOOL := FALSE;                  // 输入有限闸结果（逐拍重算）/ the input finiteness gate result
    _bFinDom : BOOL := FALSE;                  // 钳位限值有限闸结果（逐拍重算）/ the clamp limit finiteness gate result
    _bStable : BOOL := FALSE;                  // 活动节 Jury 闸结果（逐拍重算）/ the active stage Jury gate result
    _bCfgBadI: BOOL := FALSE;                  // 本拍组态非法标记（逐拍重算）/ the per scan configuration fault flag
    _bCoefChg: BOOL := FALSE;                  // 系数变更沿标记（逐拍重算，信息级 3747）/ the coefficient change flag
    _bSatI   : BOOL := FALSE;                  // 本拍钳位内部位 / the internal clamp bit
    _uLatch  : UDINT := 16#0000_0000;          // 故障码锁存（仅复位沿清除，FB33-1）/ the latched fault code cleared only by the reset edge
    rtReset  : R_TRIG;                         // 复位沿实例，段 0 无条件刷新（R7）/ the reset edge instance refreshed unconditionally
VAR CONSTANT
    DL_BC_EPS   : LREAL := 1.0E-9;  // 系数变更判定容差 [−] / the coefficient change tolerance
    DL_BC_SMIN  : DINT := 1;        // 节数下界 [节] / the stage floor
    DL_BC_SMAX  : DINT := 4;        // 节数上界 [节] / the stage ceiling
    DL_BC_A2LIM : LREAL := 1.0;     // Jury 条件一 |a2| 边界 [−] / the Jury first condition boundary
    DL_BC_ONE   : LREAL := 1.0;     // Jury 条件二三的一常量 [−] / the unit constant of the Jury conditions
    DL_BC_ZERO  : LREAL := 0.0;     // 实数零常量 [工程单位] / the real zero constant
    DL_BC_ZEROI : DINT := 0;        // 整型零常量 [节] / the integer zero constant
    DL_BC_ONEI  : DINT := 1;        // 整型一常量 [节] / the integer one constant
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional edge refresh
rtReset(CLK := bResetState); // 复位沿 / the reset edge

// 段 1｜首拍初始化（R310 / FB50-2；_bInit 与复位沿同款初始化）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    FOR _iClr := DL_BC_ZEROI TO DL_BC_SMAX - DL_BC_ONE DO // 有界遍历全部节槽 / the bounded traversal over every stage slot
        _afW1[_iClr] := DL_BC_ZERO; // 状态 w1 显式清零 / clear the state w1 explicitly
        _afW2[_iClr] := DL_BC_ZERO; // 状态 w2 显式清零 / clear the state w2 explicitly
        _afB0Prev[_iClr] := aB0[_iClr]; // 系数快照对齐首拍值（防首拍误报变更沿）/ align the snapshot to avoid a spurious change edge
        _afB1Prev[_iClr] := aB1[_iClr]; // 快照对齐 / align the snapshot
        _afB2Prev[_iClr] := aB2[_iClr]; // 快照对齐 / align the snapshot
        _afA1Prev[_iClr] := aA1[_iClr]; // 快照对齐 / align the snapshot
        _afA2Prev[_iClr] := aA2[_iClr]; // 快照对齐 / align the snapshot
    END_FOR
    _fOutLast := DL_BC_ZERO; // 最近有效输出显式清零 / clear the last valid output explicitly
    _uLatch := 16#0000_0000; // 故障码锁存显式清零 / clear the latched code explicitly
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清锁存 + 清全链状态，R311 声明）/ the reset edge with the declared scope
    _uLatch := 16#0000_0000; // 清故障码锁存（唯一的故障解除路径）/ clear the latched code, the only release path
    FOR _iClr := DL_BC_ZEROI TO DL_BC_SMAX - DL_BC_ONE DO // 有界遍历全部节槽 / the bounded traversal over every stage slot
        _afW1[_iClr] := DL_BC_ZERO; // 清状态 w1 / clear the state w1
        _afW2[_iClr] := DL_BC_ZERO; // 清状态 w2 / clear the state w2
    END_FOR
END_IF
_bSatI := FALSE; // 钳位单拍内部位预清零 / preset the internal clamp bit false
_bCoefChg := FALSE; // 系数变更标记预清零 / preset the coefficient change flag false
_bCfgBadI := FALSE; // 组态非法标记预清零 / preset the configuration fault flag false

// 段 2｜组态闸（边界一三：nStages 越域 / 钳位域 / 活动节系数非有限 / Jury，成因独立码 R190）/ segment 2, the configuration gates
_nUse := nStages; // 节数接管 [节] / take the stage count
IF (_nUse < DL_BC_SMIN) OR (_nUse > DL_BC_SMAX) THEN // 节数越域 / the stage count is out of the domain
    _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存（R152）/ latch only the first cause
        _uLatch := 16#0002_3743; // 故障级：组态非法（节数越域）/ fault grade, an illegal configuration
    END_IF
    IF _nUse < DL_BC_SMIN THEN // 下界钳位（防遍历越界）/ the floor clamp for the traversal safety
        _nUse := DL_BC_SMIN; // 钳到一节 / clamp to one stage
    ELSE // 上界钳位 / the ceiling clamp
        _nUse := DL_BC_SMAX; // 钳到四节 / clamp to four stages
    END_IF
END_IF
_bFinDom := (fOutMin = fOutMin) AND ((fOutMin - fOutMin) = (fOutMin - fOutMin))
         AND (fOutMax = fOutMax) AND ((fOutMax - fOutMax) = (fOutMax - fOutMax)); // 限值有限 / the limits are finite
IF (NOT _bFinDom) OR (fOutMin > fOutMax) THEN // 限值非有限或域反序 / the limits are not finite or the domain is reversed
    _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存 / latch only the first cause
        _uLatch := 16#0002_3743; // 故障级：组态非法（钳位域）/ fault grade, an illegal clamp domain
    END_IF
END_IF
_bFinIn := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn)); // 输入有限 / the input is finite
FOR _i := DL_BC_ZEROI TO _nUse - DL_BC_ONE DO // 有界遍历活动节（死节豁免，边界一）/ the bounded traversal over the active stages, dead stages exempt
    _bFinCoef := (aB0[_i] = aB0[_i]) AND ((aB0[_i] - aB0[_i]) = (aB0[_i] - aB0[_i]))
              AND (aB1[_i] = aB1[_i]) AND ((aB1[_i] - aB1[_i]) = (aB1[_i] - aB1[_i]))
              AND (aB2[_i] = aB2[_i]) AND ((aB2[_i] - aB2[_i]) = (aB2[_i] - aB2[_i]))
              AND (aA1[_i] = aA1[_i]) AND ((aA1[_i] - aA1[_i]) = (aA1[_i] - aA1[_i]))
              AND (aA2[_i] = aA2[_i]) AND ((aA2[_i] - aA2[_i]) = (aA2[_i] - aA2[_i])); // 本节五系数有限 / the five coefficients of this stage are finite
    _bStable := (ABS(aA2[_i]) < DL_BC_A2LIM) AND ((DL_BC_ONE + aA1[_i] + aA2[_i]) > DL_BC_ZERO) AND ((DL_BC_ONE - aA1[_i] + aA2[_i]) > DL_BC_ZERO); // Jury 三条件（与 FB_DL_BiquadFilter v1.0.1 同口径）/ the Jury three conditions aligned with the single stage owner
    IF (NOT _bFinCoef) AND (_uLatch = 16#0000_0000) THEN // 成因：活动节系数非有限（不覆盖已有首因）/ the coefficients of an active stage are not finite
        _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
        _uLatch := 16#0002_3745; // 故障级：活动节系数非有限 / fault grade, the coefficients are not finite
        bError := TRUE; // 同拍置故障标志（R45 配对，段 4 故障分支沿用）/ raise the fault flag on the same scan
    ELSIF (NOT _bStable) AND (_uLatch = 16#0000_0000) THEN // 成因：活动节越 Jury 域 / the Jury conditions are exceeded
        _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
        _uLatch := 16#0002_3744; // 故障级：活动节越过 Jury 三条件稳定域 / fault grade, the Jury conditions are exceeded
        bError := TRUE; // 同拍置故障标志（R45 配对，段 4 故障分支沿用）/ raise the fault flag on the same scan
    END_IF
END_FOR
IF (NOT _bFinIn) AND (_uLatch = 16#0000_0000) THEN // 成因：输入非有限（不覆盖已有首因）/ the input is not finite
    _uLatch := 16#0002_3748; // 故障级：输入非有限 / fault grade, the input is not finite
END_IF

// 段 3｜使能失能分支最先消费：降级为安全值并清全链（边界六声明行）/ segment 3, the disabled branch degrades to the safe value
IF NOT bEnable THEN // 失能 / disabled
    FOR _iClr := DL_BC_ZEROI TO DL_BC_SMAX - DL_BC_ONE DO // 有界遍历全部节槽 / the bounded traversal over every stage slot
        _afW1[_iClr] := DL_BC_ZERO; // 状态清零（失能即弃用历史）/ clear the state, the history is abandoned
        _afW2[_iClr] := DL_BC_ZERO; // 状态清零 / clear the state
    END_FOR
    _fOutLast := DL_BC_ZERO; // 输出归零（下游控制量失能须归零，非冻结末值）/ zero the output, a control quantity must fall to zero
    fOut := DL_BC_ZERO; // 出口归零 [工程单位] / the outlet falls to zero
    bSat := FALSE; // 钳位位清零 / clear the clamp bit
    bCfgBad := (_uLatch <> 16#0000_0000); // 组态标记照实回放（与锁存同源）/ replay the configuration flag from the latch
    bValid := FALSE; // 输出不可用（安全值不是滤波结果，明示而非静默）/ mark the output unusable, a safe zero is not a filter result
    bError := (_uLatch <> 16#0000_0000); // 故障位照实回放 / replay the fault bit from the latch
    eErr := _uLatch; // 故障码锁存回放（信息级不参与失能分支）/ replay the latched code
    RETURN; // 早退，不推进级联 / early return without advancing the chain
END_IF

// 段 4｜组态故障：冻结最近有效输出，不推进状态（边界一五，结构早退；冻结源做有限性闸，FB51-3）/ segment 4, freeze on a fault without advancing the chain
IF (_uLatch <> 16#0000_0000) OR _bCfgBadI THEN // 任一故障相 / any fault phase
    IF (_fOutLast = _fOutLast) AND ((_fOutLast - _fOutLast) = (_fOutLast - _fOutLast)) THEN // 冻结源有限性闸（冻结只防推进不防污染）/ the frozen source finiteness gate
        fOut := _fOutLast; // 冻结最近有效输出 [工程单位] / freeze the last valid output
    ELSE // 冻结源自身被污染（理论上不可达）/ the frozen source itself is polluted
        _fOutLast := DL_BC_ZERO; // 归零重建 / rebuild from zero
        fOut := DL_BC_ZERO; // 出口归零 [工程单位] / the outlet falls to zero
    END_IF
    bSat := FALSE; // 钳位位清零 / clear the clamp bit
    bCfgBad := _bCfgBadI OR (_uLatch = 16#0002_3743) OR (_uLatch = 16#0002_3744) OR (_uLatch = 16#0002_3745); // bCfgBad 专指组态族三码，3748 输入坏不复用 / the configuration flag covers only the configuration family codes
    bValid := FALSE; // 输出不可用 / the output is not usable
    bError := TRUE; // 故障位置位 / raise the fault bit
    eErr := _uLatch; // 锁存码回放（不按当下输入重新推断，R152）/ replay the latched code
    RETURN; // 结构早退 / the structural early exit
END_IF

// 段 5｜系数变更沿：任一活动系数 |新 − 旧| > 容差即清全链状态（边界四）/ segment 5, the coefficient change edge clears the chain
FOR _i := DL_BC_ZEROI TO _nUse - DL_BC_ONE DO // 有界遍历活动节 / the bounded traversal over the active stages
    IF (ABS(aB0[_i] - _afB0Prev[_i]) > DL_BC_EPS) OR (ABS(aB1[_i] - _afB1Prev[_i]) > DL_BC_EPS)
    OR (ABS(aB2[_i] - _afB2Prev[_i]) > DL_BC_EPS) OR (ABS(aA1[_i] - _afA1Prev[_i]) > DL_BC_EPS)
    OR (ABS(aA2[_i] - _afA2Prev[_i]) > DL_BC_EPS) THEN // 本节任一系数变更 / any coefficient of this stage changed
        _bCoefChg := TRUE; // 置变更标记（信息级 3747）/ raise the change flag
        FOR _iClr := DL_BC_ZEROI TO DL_BC_SMAX - DL_BC_ONE DO // 有界遍历全部节槽（全链清零防混算）/ the bounded traversal over every slot
            _afW1[_iClr] := DL_BC_ZERO; // 清状态 w1 / clear the state w1
            _afW2[_iClr] := DL_BC_ZERO; // 清状态 w2 / clear the state w2
        END_FOR
    END_IF
    _afB0Prev[_i] := aB0[_i]; // 系数快照推进 [−] / advance the b0 snapshot
    _afB1Prev[_i] := aB1[_i]; // 快照推进 [−] / advance the b1 snapshot
    _afB2Prev[_i] := aB2[_i]; // 快照推进 [−] / advance the b2 snapshot
    _afA1Prev[_i] := aA1[_i]; // 快照推进 [−] / advance the a1 snapshot
    _afA2Prev[_i] := aA2[_i]; // 快照推进 [−] / advance the a2 snapshot
END_FOR

// 段 6｜逐节 Direct Form II 递推（节间串接：本拍节输出即下一节输入）/ segment 6, the per stage recursion chained down
_fY := fIn; // 级联入口 = 输入 [工程单位] / the chain inlet is the input
FOR _i := DL_BC_ZEROI TO _nUse - DL_BC_ONE DO // 有界遍历活动节 / the bounded traversal over the active stages
    _fW := _fY - (aA1[_i] * _afW1[_i]) - (aA2[_i] * _afW2[_i]); // 节内中间量 w [工程单位] / the intermediate w of this stage
    _fY := (aB0[_i] * _fW) + (aB1[_i] * _afW1[_i]) + (aB2[_i] * _afW2[_i]); // 节输出 y [工程单位] / the stage output
    _afW2[_i] := _afW1[_i]; // 状态右移：w1 → w2 / shift the state
    _afW1[_i] := _fW; // 状态推进：本拍 w → w1 / advance the state
END_FOR

// 段 7｜输出钳位 + 末活动节 w1 抗 windup 状态回写 / segment 7, the clamp with the anti windup write back
IF _fY > fOutMax THEN // 超上界 / above the ceiling
    fOut := fOutMax; // 钳上界 [工程单位] / clamp to the ceiling
    _bSatI := TRUE; // 置钳位内部位 / raise the internal clamp bit
    _afW1[_nUse - DL_BC_ONE] := fOutMax; // 末活动节状态回写（防积分式累积发散）[工程单位] / write the last active state back
ELSIF _fY < fOutMin THEN // 超下界 / below the floor
    fOut := fOutMin; // 钳下界 [工程单位] / clamp to the floor
    _bSatI := TRUE; // 置钳位内部位 / raise the internal clamp bit
    _afW1[_nUse - DL_BC_ONE] := fOutMin; // 末活动节状态回写 [工程单位] / write the state back
ELSE // 域内 / inside the domain
    fOut := _fY; // 直出输出 [工程单位] / pass the output through
END_IF

// 段 8｜全部内部量非有限复检：污染即拒收并锁存（FB32-7 保持槽口径）/ segment 8, the finiteness recheck before the states are stored
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut))
OR (_fY <> _fY) OR ((_fY - _fY) <> (_fY - _fY)) THEN // 输出或级联传递量非有限（NaN 自反 / Inf 差值自减）/ a non finite output or intermediate
    FOR _iClr := DL_BC_ZEROI TO DL_BC_SMAX - DL_BC_ONE DO // 有界遍历全部节槽 / the bounded traversal over every slot
        _afW1[_iClr] := DL_BC_ZERO; // 状态清零，禁污染物驻留 / clear the state so nothing polluted remains
        _afW2[_iClr] := DL_BC_ZERO; // 状态清零 / clear the state
    END_FOR
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存 / latch only the first cause
        _uLatch := 16#0002_3748; // 故障级：输入或中间量非有限 / fault grade, the input or the intermediate is not finite
    END_IF
    fOut := DL_BC_ZERO; // 出口归零 [工程单位] / the outlet falls to zero
    bSat := FALSE; // 钳位位清零 / clear the clamp bit
    bCfgBad := FALSE; // 3748 属测量坏而非组态坏 / the input fault is a measurement issue
    bValid := FALSE; // 输出不可用 / the output is not usable
    bError := TRUE; // 故障位置位 / raise the fault bit
    eErr := _uLatch; // 锁存码回放 / replay the latched code
    RETURN; // 早退 / early return
END_IF

// 段 9｜最近有效输出写回（写前已过非有限闸）/ segment 9, store the last valid output
_fOutLast := fOut; // 快照更新 [工程单位] / update the snapshot

// 段 10｜统一出口（单拍位映射 + 信息级重算，R187 / FB51-8）/ segment 10, the unified outlet
bSat := _bSatI; // 钳位位出口 / the clamp bit outlet
bCfgBad := (_uLatch = 16#0002_3743) OR (_uLatch = 16#0002_3744) OR (_uLatch = 16#0002_3745); // 组态标记出口（与锁存同源，3748 不复用）/ the configuration flag outlet from the latch
bValid := TRUE; // 域内输出可用 / the in-domain output is usable
bError := (_uLatch <> 16#0000_0000); // 故障位出口（锁存派生，R99）/ the fault bit outlet derived from the latch
IF _uLatch <> 16#0000_0000 THEN // 故障锁存回放优先 / the latched fault replays first
    eErr := _uLatch; // 锁存码 [码] / the latched code
ELSIF _bSatI THEN // 输出钳位（信息级，逐拍重算）/ the output clamp, informational
    eErr := 16#0002_3746; // 信息级：本拍输出被钳位 / informational, the output was clamped
ELSIF _bCoefChg THEN // 系数变更（信息级，逐拍重算）/ the coefficient change, informational
    eErr := 16#0002_3747; // 信息级：系数变更沿触发全链状态清零 / informational, a coefficient change cleared the chain
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
