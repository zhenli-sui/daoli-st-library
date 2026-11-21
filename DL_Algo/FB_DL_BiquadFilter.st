(*
  ==================================================================
  组件名 Component  : FB_DL_BiquadFilter
  分类   Category   : DL_Algo
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0002_3735 / 3736 / 3737 / 373A（故障级）
                      16#0002_3738 / 3739（信息级）
  版本   Version    : 1.0.1
  复杂度 Complexity  : 高
  功能   Purpose    : 通用二阶 IIR 节（Direct Form I），系数由调用方下发（归一化 a0 = 1），
                      可配低通 / 高通 / 带通 / 带阻 / 全通；带 Jury 三条件稳定域闸、
                      系数变更沿清状态、输出钳位 + 抗 windup 状态回写。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）；
                      差分方程与三角稳定判据取自公开 DSP 教科书与公开滤波器设计手册的
                      通用公式（分类与公式借鉴，零代码复制），本件实现、闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；二阶 IIR 直接I型差分方程的公开
                      定义（RBJ Audio EQ Cookbook 类公开二阶节设计公式，仅借鉴公式结构）
  平台   Platform   : 纯 IEC 61131-3（四则 / ABS / R_TRIG / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（R_TRIG 属标准边沿检测）
  分工声明 Split     : FB_DL_LowPassFilter（一阶 RC）/ FB_DL_HighPassFilter（一阶）/
                      FB_DL_NotchFilter（陷波专用，结构固定）/ FB_DL_FirFilter（FIR）
                      为结构专用轻量件；本件为通用二阶节，适用于「需要带通 / 带阻 /
                      可调 Q 且带 ST 系数下发」的场合（R216 双向互引，选型对照见
                      MANUAL_DL_Algo）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 稳定域闸（v1.0.1 返修 R63 · 修 R62-D2 严重：换 Jury 三条件，废除
                         「|a1|<2 且 |a2|<1 且 |a2−a1|<1」伪判据——该伪判据放行了
                         a1 = −1.9 / a2 = −0.95 的实根 −0.9545 发散极点族）：判据为
                         ABS(a2) < 1 且 (1 + a1 + a2) > 0 且 (1 − a1 + a2) > 0，
                         任一不满足即判组态故障并冻结输出，绝不外泄发散值；
                      二 系数任一非有限（NaN / ±Inf）同走组态故障路径；八个浮点入参
                         （fIn / b0 / b1 / b2 / a1 / a2 / fOutMin / fOutMax）逐个点名闸，
                         换算量与限值一并入闸（R272，禁按「主要参数」手挑）；
                      三 系数变更沿（五系数任一 |新 − 旧| > 1.0E-9）清 w1 / w2：防旧状态
                         冲击新频响，属「在线变系数为无扰切换的保守处置」，非无扰切换本身；
                      四 输出钳位 + 抗 windup：fOut 钳 [fOutMin, fOutMax]，被钳时 w1 := fOut
                         回写状态，防积分式累积发散；
                      五 bEnable = FALSE 的语义二选一并写死（FB33-4 声明行）：本件取
                         「降级为安全值 0.0 + 状态清零 + bValid = FALSE」，理由：滤波器输出
                         是下游控制量，失能须归零而非冻结末值；
                      六 故障码一律锁存至 bResetState 上升沿回放，不在故障相按当下输入
                         重新推断（FB33-1 / R152：首因不会被末因覆盖）；清除路径 = 复位沿；
                      七 信息级码（输出钳位 / 系数变更）逐拍重算不锁存；
                      八 段 0 无条件刷新 R_TRIG；CASE 无（本件为线性节，无顺序状态机，
                         R6 标注 N/A），故 ELSE 兜底要求不适用；首拍 _bInit 初始化全量状态。
  错误码 Codes      :
    16#0002_3735【故障级】系数越过 Jury 三条件稳定域（|a2| ≥ 1 或 1+a1+a2 ≤ 0 或
                         1−a1+a2 ≤ 0），锁存
    16#0002_3736【故障级】系数非有限（五个系数任一为 NaN 或 ±Inf），锁存
    16#0002_3737【故障级】输出钳位域非法（fOutMin > fOutMax 或限值非有限），锁存
    16#0002_3738【信息级】本拍输出被钳位（bSat = TRUE，不锁存）
    16#0002_3739【信息级】系数变更沿触发状态清零（不锁存）
    16#0002_373A【故障级】输入 / 中间量 / 输出非有限（NaN 或 ±Inf），锁存；
                         v1.0.1 返修（R63 · 修 R62-D5）：本码路径不再复用 bCfgBad 表达，
                         改由 bValid = FALSE + eErr = 373A 单独承载（bCfgBad 专指组态族）
  码位反证 Note     :
    3735 / 3736 / 3737 / 373A 四码不可合并：四者的 bCfgBad 与 bValid 组合完全相同，
    现场若只靠输出组合无法区分「系数发散 / 系数采集失败 / 限值配错 / 输入测点坏」，
    而四者的处置人不同（算法工程师 / 仪表工 / 组态工程师 / 现场仪表）（R90 反证句）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 阶跃输入 + 公开二阶低通系数组（b0 = 0.0675, b1 = 0.1349, b2 = 0.0675,
       a1 = -1.1430, a2 = 0.4128）→ 输出单调收敛于稳态 1.0，无过冲爆炸（极点半径 √0.4128 ≈ 0.6426）
    V2 a1 = 2.5（不稳定）→ bCfgBad = TRUE + fOut 冻结 + 码 3735
    V2b a1 = -1.9, a2 = -0.95（v1.0.1 返修向量：旧伪判据放行的发散族）→ Jury 判
       3735 + fOut 冻结 + bCfgBad = TRUE（ABS(a2)=0.95 < 1 成立但 1+a1+a2 = -1.85 ≤ 0 不满足）
    V2c a1 = 0.0, a2 = -0.99（v1.0.1 返修向量：合法边界内）→ Jury 三条件全成立，
       合法放行（旧 |a2−a1|<1 伪判据对该族误杀）
    V3 a1 = NaN → 同 V2，码 3736
    V4 在线把低通系数换成高通系数 → w1 / w2 清零，fOut 单拍跳变被钳位而不发散，码 3739
    V5 bResetState 单拍 → w1 = w2 = 0
    V6 fIn = 1.0E9 持续 → fOut 钳 fOutMax + bSat + w1 回写（下一拍不反向冲）
    V7 bEnable = FALSE → fOut = 0.0、状态零、bValid = FALSE
    V8 fOutMin > fOutMax → 码 3737 + bCfgBad
    V9 首拍 → 状态零、fOut = 0.0（禁首拍用未初始化状态）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 3 · 序号 9）
    2026-11-21  v1.0.1  R63 返修 R2（R62-D2 严重 + D5 轻）：①稳定判据换 Jury 三条件
                        ABS(a2)<1 ∧ (1+a1+a2)>0 ∧ (1−a1+a2)>0，码 3735 语义与头注释同步；
                        ②新增验收向量 V2b（旧伪判据放行族判 3735+冻结）与 V2c（合法边界族放行）；
                        ③373A（输入/中间/输出非有限）路径不再复用 bCfgBad，改 bValid+eErr 表达
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_BiquadFilter
VAR_INPUT
    bEnable     : BOOL := TRUE;    // 使能；FALSE 时输出归零并清状态（边界五）/ the enable, false zeroes the output and clears the state
    bResetState : BOOL := FALSE;   // 状态复位电平，上升沿清 w1 / w2 与故障锁存 / the state reset level, its rising edge clears the states and the fault latch
    fIn         : LREAL := 0.0;    // 输入量 [工程单位]，必须有限 / the input value, must be finite
    fB0         : LREAL := 1.0;    // 归一化前向系数 b0 [−]，a0 已归一为 1 / the normalized feed forward coefficient b0
    fB1         : LREAL := 0.0;    // 归一化前向系数 b1 [−] / the normalized feed forward coefficient b1
    fB2         : LREAL := 0.0;    // 归一化前向系数 b2 [−] / the normalized feed forward coefficient b2
    fA1         : LREAL := 0.0;    // 归一化反馈系数 a1 [−]，须落三角稳定域 / the normalized feedback coefficient a1 inside the triangle
    fA2         : LREAL := 0.0;    // 归一化反馈系数 a2 [−]，须落三角稳定域 / the normalized feedback coefficient a2 inside the triangle
    fOutMin     : LREAL := -1.0E6; // 输出钳位域下界 [工程单位] / the output clamp floor
    fOutMax     : LREAL := 1.0E6;  // 输出钳位域上界 [工程单位] / the output clamp ceiling
    tSample     : TIME := T#10MS;  // 采样周期 [毫秒]，仅作标称记录（系数设计已内含采样率）/ the nominal sample period, recorded only
END_VAR
VAR_OUTPUT
    fOut    : LREAL := 0.0;           // 滤波输出 [工程单位] / the filtered output
    bSat    : BOOL := FALSE;          // 本拍输出被钳位 [-] / the output was clamped on this scan
    bCfgBad : BOOL := FALSE;          // 组态非法（与故障锁存同源，锁存型）[-] / an illegal configuration, latched with the fault
    bValid  : BOOL := FALSE;          // 输出可用（失能 / 故障 / 输入非有限为 FALSE）[-] / the output is usable
    eErr    : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL := FALSE;          // 故障锁存位（由锁存码派生，非单拍标志，R99）/ the latched fault bit derived from the latched code
END_VAR
VAR
    _bInit     : BOOL := FALSE;               // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _fW1       : LREAL := 0.0;                // 状态 w1（上一拍中间量）[工程单位] / the state w1 of the previous scan
    _fW2       : LREAL := 0.0;                // 状态 w2（前两拍中间量）[工程单位] / the state w2 of two scans ago
    _fW        : LREAL := 0.0;                // 本拍中间量 w [工程单位] / the intermediate w of this scan
    _fY        : LREAL := 0.0;                // 本拍未钳位输出 y [工程单位] / the unclamped output y of this scan
    _fOutLast  : LREAL := 0.0;                // 最近一次有效输出（故障冻结源）[工程单位] / the last valid output used while frozen
    _fB0Prev   : LREAL := 0.0;                // 上拍 b0 快照 [−] / the previous b0 snapshot
    _fB1Prev   : LREAL := 0.0;                // 上拍 b1 快照 [−] / the previous b1 snapshot
    _fB2Prev   : LREAL := 0.0;                // 上拍 b2 快照 [−] / the previous b2 snapshot
    _fA1Prev   : LREAL := 0.0;                // 上拍 a1 快照 [−] / the previous a1 snapshot
    _fA2Prev   : LREAL := 0.0;                // 上拍 a2 快照 [−] / the previous a2 snapshot
    _bFinCoef  : BOOL := FALSE;               // 五个系数有限闸结果（逐拍重算）/ the coefficient finiteness gate result
    _bFinIn    : BOOL := FALSE;               // 输入有限闸结果（逐拍重算）/ the input finiteness gate result
    _bFinDom   : BOOL := FALSE;               // 钳位域合法闸结果（逐拍重算）/ the clamp domain gate result
    _bStable   : BOOL := FALSE;               // Jury 三条件稳定域闸结果（逐拍重算，v1.0.1 换判据）/ the Jury three condition stability gate result
    _bCfgBadI  : BOOL := FALSE;               // 本拍组态非法标记（逐拍重算）/ the per scan configuration fault flag
    _bCoefChg  : BOOL := FALSE;               // 系数变更沿标记（逐拍重算，信息级 3739）/ the coefficient change flag
    _bSatI     : BOOL := FALSE;               // 本拍钳位内部位，段 1 预清段 12 映射 / the internal clamp bit
    _uLatch    : UDINT := 16#0000_0000;       // 故障码锁存（仅复位沿清除，FB33-1）/ the latched fault code cleared only by the reset edge
    rtReset    : R_TRIG;                      // 复位沿实例，段 0 无条件刷新（R7）/ the reset edge instance refreshed unconditionally
VAR CONSTANT
    DL_BQ_EPS    : LREAL := 1.0E-9; // 系数变更判定容差 [−]，浮点禁判等 / the coefficient change tolerance, plain equality is forbidden
    DL_BQ_A2LIM  : LREAL := 1.0;    // Jury 条件一 |a2| 边界 [−] / the Jury first condition boundary on the absolute a2
    DL_BQ_ONE    : LREAL := 1.0;    // Jury 条件二三的一常量 [−] / the unit constant of the Jury second and third conditions
    DL_BQ_ZERO   : LREAL := 0.0;    // 实数零常量 [工程单位] / the real zero constant
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional edge refresh
rtReset(CLK := bResetState); // 复位沿 / the reset edge

// 段 1｜首拍初始化与单拍标志预清（R310 / FB32-1；_bInit 与复位沿同款初始化）/ segment 1, the first scan init and the preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _fW1 := DL_BQ_ZERO; // 状态 w1 显式清零 / clear the state w1 explicitly
    _fW2 := DL_BQ_ZERO; // 状态 w2 显式清零 / clear the state w2 explicitly
    _fOutLast := DL_BQ_ZERO; // 最近有效输出显式清零（禁首拍用未初始化状态）/ clear the last valid output explicitly
    _uLatch := 16#0000_0000; // 故障码锁存显式清零 / clear the latched code explicitly
    _fB0Prev := fB0; // 系数快照对齐首拍值，避免首拍误报变更沿 / align the snapshots to avoid a spurious change edge
    _fB1Prev := fB1; // 上拍 b1 快照对齐 / align the b1 snapshot
    _fB2Prev := fB2; // 上拍 b2 快照对齐 / align the b2 snapshot
    _fA1Prev := fA1; // 上拍 a1 快照对齐 / align the a1 snapshot
    _fA2Prev := fA2; // 上拍 a2 快照对齐 / align the a2 snapshot
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清锁存 + 清滤波器状态，R311 声明）/ the reset edge with the declared scope
    _uLatch := 16#0000_0000; // 清故障码锁存（唯一的故障解除路径）/ clear the latched code, the only release path
    _fW1 := DL_BQ_ZERO; // 清状态 w1 / clear the state w1
    _fW2 := DL_BQ_ZERO; // 清状态 w2 / clear the state w2
END_IF
_bSatI := FALSE; // 钳位单拍内部位预清零 / preset the internal clamp bit false
_bCoefChg := FALSE; // 系数变更标记预清零 / preset the coefficient change flag false
_bCfgBadI := FALSE; // 组态非法标记预清零 / preset the configuration fault flag false

// 段 2｜八个浮点入参逐个点名有限闸（R272 全量枚举，含换算量与限值）/ segment 2, the full finiteness gate over all eight real pins
_bFinCoef := (fB0 = fB0) AND ((fB0 - fB0) = (fB0 - fB0))
          AND (fB1 = fB1) AND ((fB1 - fB1) = (fB1 - fB1))
          AND (fB2 = fB2) AND ((fB2 - fB2) = (fB2 - fB2))
          AND (fA1 = fA1) AND ((fA1 - fA1) = (fA1 - fA1))
          AND (fA2 = fA2) AND ((fA2 - fA2) = (fA2 - fA2)); // 五系数有限 / the five coefficients are finite
_bFinIn := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn)); // 输入有限 / the input is finite
_bFinDom := (fOutMin = fOutMin) AND ((fOutMin - fOutMin) = (fOutMin - fOutMin))
         AND (fOutMax = fOutMax) AND ((fOutMax - fOutMax) = (fOutMax - fOutMax)); // 限值有限 / the limits are finite

// 段 3｜稳定域闸与组态归因（边界一二，四个成因独立码，R190；v1.0.1 换 Jury 三条件）/ segment 3, the stability gate and the unique cause attribution
_bStable := (ABS(fA2) < DL_BQ_A2LIM) AND ((DL_BQ_ONE + fA1 + fA2) > DL_BQ_ZERO) AND ((DL_BQ_ONE - fA1 + fA2) > DL_BQ_ZERO); // Jury 三条件：|a2|<1 且 1+a1+a2>0 且 1−a1+a2>0 / the Jury three conditions, the magnitude of a2 below one and both half plane products positive
IF NOT _bFinCoef THEN // 成因一：系数非有限 / cause one, the coefficients are not finite
    _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存（后续成因不覆盖首因，R152）/ latch only the first cause so a later cause never overwrites it
        _uLatch := 16#0002_3736; // 故障级：系数非有限 / fault grade, the coefficients are not finite
    END_IF
ELSIF NOT _bFinDom THEN // 成因二：限值非有限 / cause two, the limits are not finite
    _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存 / latch only the first cause
        _uLatch := 16#0002_3737; // 故障级：输出钳位域非法 / fault grade, the clamp domain is illegal
    END_IF
ELSIF fOutMin > fOutMax THEN // 成因三：钳位域反序 / cause three, the clamp domain is reversed
    _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存 / latch only the first cause
        _uLatch := 16#0002_3737; // 故障级：输出钳位域非法（与限值非有限同一族，出口不可分）/ fault grade under the same clamp domain family
    END_IF
ELSIF NOT _bStable THEN // 成因四：越过 Jury 三条件稳定域（v1.0.1 换判据）/ cause four, the Jury conditions are exceeded
    _bCfgBadI := TRUE; // 置组态标记 / raise the configuration flag
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存 / latch only the first cause
        _uLatch := 16#0002_3735; // 故障级：系数越过 Jury 三条件稳定域 / fault grade, the Jury conditions are exceeded
    END_IF
END_IF
IF (NOT _bFinIn) AND (_uLatch = 16#0000_0000) THEN // 成因五：输入非有限（不覆盖已有首因）/ cause five, the input is not finite, never overwriting an earlier cause
    _uLatch := 16#0002_373A; // 故障级：输入非有限 / fault grade, the input is not finite
END_IF

// 段 4｜使能失能分支最先消费：降级为安全值并清状态（边界五，FB33-4 声明行）/ segment 4, the disabled branch degrades to the safe value
IF NOT bEnable THEN // 失能 / disabled
    _fW1 := DL_BQ_ZERO; // 状态清零（失能即弃用历史）/ clear the state, the history is abandoned
    _fW2 := DL_BQ_ZERO; // 状态清零 / clear the state
    _fOutLast := DL_BQ_ZERO; // 输出归零（下游控制量失能须归零，非冻结末值）/ zero the output, a control quantity must fall to zero rather than freeze
    fOut := DL_BQ_ZERO; // 出口归零 [工程单位] / the outlet falls to zero
    bSat := FALSE; // 钳位位清零 / clear the clamp bit
    bCfgBad := (_uLatch <> 16#0000_0000); // 组态标记照实回放（与锁存同源）/ replay the configuration flag from the latch
    bValid := FALSE; // 输出不可用（安全值不是滤波结果，明示而非静默）/ mark the output unusable, a safe zero is not a filter result
    bError := (_uLatch <> 16#0000_0000); // 故障位照实回放 / replay the fault bit from the latch
    eErr := _uLatch; // 故障码锁存回放（信息级不参与失能分支）/ replay the latched code, informational codes do not apply while disabled
    RETURN; // 早退，不推进滤波 / early return without advancing the filter
END_IF

// 段 5｜组态故障或输入非有限：冻结最近有效输出，不推进状态（边界一二三，R273）/ segment 5, freeze on a fault without advancing the state
IF (_uLatch <> 16#0000_0000) OR _bCfgBadI OR (NOT _bFinIn) THEN // 任一故障相 / any fault phase
    IF (_fOutLast = _fOutLast) AND ((_fOutLast - _fOutLast) = (_fOutLast - _fOutLast)) THEN // 冻结源有限性闸（冻结只防推进不防污染，FB51-3）/ the frozen source finiteness gate
        fOut := _fOutLast; // 冻结最近有效输出 [工程单位] / freeze the last valid output
    ELSE // 冻结源自身被污染（理论上不可达）/ the frozen source itself is polluted, unreachable by theory
        _fOutLast := DL_BQ_ZERO; // 归零重建 / rebuild from zero
        fOut := DL_BQ_ZERO; // 出口归零 [工程单位] / the outlet falls to zero
    END_IF
    bSat := FALSE; // 钳位位清零 / clear the clamp bit
    bCfgBad := (_uLatch = 16#0002_3735) OR (_uLatch = 16#0002_3736) OR (_uLatch = 16#0002_3737); // bCfgBad 专指组态族三码，373A 输入坏不再复用（v1.0.1 修 R62-D5）/ the configuration flag now covers only the three configuration family codes, the input fault code no longer reuses it
    bValid := FALSE; // 输出不可用 / the output is not usable
    bError := TRUE; // 故障位置位 / raise the fault bit
    eErr := _uLatch; // 锁存码回放（不按当下输入重新推断，R152）/ replay the latched code instead of inferring from the current input
    RETURN; // 早退 / early return
END_IF

// 段 6｜系数变更沿：五系数任一 |新 − 旧| > 容差即清状态（边界三）/ segment 6, the coefficient change edge clears the state
IF (ABS(fB0 - _fB0Prev) > DL_BQ_EPS) OR (ABS(fB1 - _fB1Prev) > DL_BQ_EPS)
OR (ABS(fB2 - _fB2Prev) > DL_BQ_EPS) OR (ABS(fA1 - _fA1Prev) > DL_BQ_EPS)
OR (ABS(fA2 - _fA2Prev) > DL_BQ_EPS) THEN // 任一系数变更 / any coefficient changed
    _bCoefChg := TRUE; // 置变更标记（信息级 3739）/ raise the change flag for the informational code
    _fW1 := DL_BQ_ZERO; // 清状态 w1（防旧状态冲击新频响，保守处置）/ clear the state w1 to protect the new response from the old state
    _fW2 := DL_BQ_ZERO; // 清状态 w2 / clear the state w2
END_IF
_fB0Prev := fB0; // 系数快照推进 [−] / advance the b0 snapshot
_fB1Prev := fB1; // 系数快照推进 [−] / advance the b1 snapshot
_fB2Prev := fB2; // 系数快照推进 [−] / advance the b2 snapshot
_fA1Prev := fA1; // 系数快照推进 [−] / advance the a1 snapshot
_fA2Prev := fA2; // 系数快照推进 [−] / advance the a2 snapshot

// 段 7｜Direct Form I 差分方程（本拍中间量与输出）/ segment 7, the Direct Form I difference equation
_fW := fIn - (fA1 * _fW1) - (fA2 * _fW2); // 中间量 w = x − a1·w1 − a2·w2 [工程单位] / the intermediate w
_fY := (fB0 * _fW) + (fB1 * _fW1) + (fB2 * _fW2); // 输出 y = b0·w + b1·w1 + b2·w2 [工程单位] / the output y
_fW2 := _fW1; // 状态右移：w1 → w2 / shift the state, w1 becomes w2
_fW1 := _fW; // 状态推进：本拍 w → w1 / advance the state, the current w becomes w1

// 段 8｜输出钳位 + 抗 windup 状态回写（边界四）/ segment 8, the clamp with the anti windup state write back
IF _fY > fOutMax THEN // 超上界 / above the ceiling
    fOut := fOutMax; // 钳上界 [工程单位] / clamp to the ceiling
    _bSatI := TRUE; // 置钳位内部位 / raise the internal clamp bit
    _fW1 := fOutMax; // 状态回写（防积分式累积发散）[工程单位] / write the state back to stop the accumulating divergence
ELSIF _fY < fOutMin THEN // 超下界 / below the floor
    fOut := fOutMin; // 钳下界 [工程单位] / clamp to the floor
    _bSatI := TRUE; // 置钳位内部位 / raise the internal clamp bit
    _fW1 := fOutMin; // 状态回写 [工程单位] / write the state back
ELSE // 域内 / inside the domain
    fOut := _fY; // 直出输出 [工程单位] / pass the output through
END_IF

// 段 9｜全部内部量非有限复检：中间量或输出被污染即拒收并锁存（FB32-7 保持槽口径）/ segment 9, the finiteness recheck before the state is stored
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut))
OR (_fW <> _fW) OR ((_fW - _fW) <> (_fW - _fW)) THEN // 输出或中间量非有限（NaN 自反 / Inf 差值自减）/ a non finite output or intermediate, tested by reflexivity and by the self difference
    _fW1 := DL_BQ_ZERO; // 状态清零，禁污染物驻留 / clear the state so nothing polluted remains
    _fW2 := DL_BQ_ZERO; // 状态清零 / clear the state
    IF _uLatch = 16#0000_0000 THEN // 仅首因入锁存 / latch only the first cause
        _uLatch := 16#0002_373A; // 故障级：输入或中间量非有限 / fault grade, the input or the intermediate is not finite
    END_IF
    fOut := DL_BQ_ZERO; // 出口归零 [工程单位] / the outlet falls to zero
    bSat := FALSE; // 钳位位清零 / clear the clamp bit
    bCfgBad := FALSE; // 373A 属测量坏而非组态坏，bCfgBad 保持 FALSE（v1.0.1 修 R62-D5）/ the input fault is a measurement issue, the configuration flag stays false
    bValid := FALSE; // 输出不可用 / the output is not usable
    bError := TRUE; // 故障位置位 / raise the fault bit
    eErr := _uLatch; // 锁存码回放 / replay the latched code
    RETURN; // 早退 / early return
END_IF

// 段 10｜最近有效输出写回（写前已过非有限闸）/ segment 10, store the last valid output after the finiteness gate
_fOutLast := fOut; // 快照更新 [工程单位] / update the snapshot

// 段 11｜统一出口（单拍位映射 + 信息级重算，R187 / FB51-8）/ segment 11, the unified outlet
bSat := _bSatI; // 钳位位出口 / the clamp bit outlet
bCfgBad := (_uLatch <> 16#0000_0000); // 组态标记出口（与锁存同源，锁存型非单拍）/ the configuration flag outlet derived from the latch
bValid := TRUE; // 域内输出可用 / the in-domain output is usable
bError := (_uLatch <> 16#0000_0000); // 故障位出口（锁存派生，R99）/ the fault bit outlet derived from the latch
IF _uLatch <> 16#0000_0000 THEN // 故障锁存回放优先 / the latched fault replays first
    eErr := _uLatch; // 锁存码 [码] / the latched code
ELSIF _bSatI THEN // 输出钳位（信息级，逐拍重算）/ the output clamp, informational and recomputed each scan
    eErr := 16#0002_3738; // 信息级：本拍输出被钳位 / informational, the output was clamped on this scan
ELSIF _bCoefChg THEN // 系数变更（信息级，逐拍重算）/ the coefficient change, informational and recomputed each scan
    eErr := 16#0002_3739; // 信息级：系数变更沿触发状态清零 / informational, a coefficient change cleared the state
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
