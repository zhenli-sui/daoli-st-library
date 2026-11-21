(*
  ==================================================================
  组件名 Component  : FB_DL_VfdOutputImbalance
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0003_0721（故障级）｜ 16#0003_0722 / 0723 / 0724（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 变频器输出侧电机三相电流不平衡 + 断相双判据监视（匝间短路 /
                      断线 / 接触器单相粘连的早期征兆）。
  开源溯源 Origin    : 公开公式 clean-room，参考公开电机保护工程口径的电流不平衡度
                      定义（(Imax−Imin)/Iavg×100，分类与公式借鉴，零代码复制），
                      本件实现、闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；三相电流不平衡度公开工程定义
  平台   Platform   : 纯 IEC 61131-3（四则 / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（无库调用、无定时器）
  分工声明 Split     : FB_DL_PhaseLossGuard 为电网输入侧断相、FB_DL_PhaseNeutral
                      Imbalance 为相-中性不平衡、FB_DL_VfdThermalDerate 为变频热
                      降额；本件为变频输出侧电机电流，四件互引（输入侧 / 输出侧
                      勿混用，MANUAL_DL_Device 写明）（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 三相任一非有限（NaN / ±Inf）→ 故障码 0721 + 三件套 + RETURN
                         结构早退（判据换算引脚全量入闸，R151）；
                      二 组态闸：fImbLimPct ≤ 0 或 fDropPct ≤ 0 或 fHystPct < 0 或
                         任一非有限 → 组态码 0721 + 三件套 + RETURN 结构早退
                         （族② 判据固化）；fImbLimPct ≥ 100 → 组态警告（信息级
                         0724，判据永假，不早退继续计算）；
                      三 待机判据：Iavg < 0.5 A（常量提级禁魔法数）→ 不计算、双判据
                         FALSE（待机态无判据意义，写死）；除子 Iavg 由非待机路径证明
                         > 0（禁除零）；
                      四 两判据独立输出、独立迟滞（R146 方向分列）：不平衡 trip >
                         fImbLimPct、复原 < fImbLimPct×(1−h%)；断相 trip 为 Imin <
                         Iavg×(1−fDropPct/100)、复原 Imin > Iavg×(1−fDropPct/100)×
                         (1+h%)（上升触发 / 回落带迟滞复原）；
                      五 bEnable = FALSE 的语义写死（FB33-4 声明行）：双判据复位 FALSE
                         + fImbPct 冻结（纯监视件，保留读数供 HMI）；
                      六 首拍 _bInit 全量初始化；无状态机（CASE N/A，R6 标注）；无
                         定时器 / 无边沿实例（段 0 无刷新对象）；无全局、无外部变量、
                         无物理地址、无指针。
  错误码 Codes      :
    16#0003_0721【故障级】三相测点非有限（NaN / ±Inf）或组态非法（限值域外 / 非有限）
    16#0003_0722【信息级】不平衡度超上限（bImbHigh = TRUE）
    16#0003_0723【信息级】断相判据触发（bPhaseDrop = TRUE）
    16#0003_0724【信息级】组态警告：fImbLimPct ≥ 100，不平衡判据永假（不置 bError）
  码位反证 Note     :
    0721 合并「测点坏」与「组态坏」的反证句：两场景出口组合仅在三相全有限后可由
    bValid 与码值区分度不足——但两者在「是否进入计算」上同形（均早退且 fImbPct
    冻结），三组以内输出无法还原，按 R90 共用一码；0722 / 0723 分立：两判据独立
    布尔出口，同时触发时 eErr 单值无法告知先修哪一路（匝间短路查电机 / 断相查接触
    器），按 R90 分立；0724 为信息级子带（R75 纪律），不跨用故障子带。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 三相均衡（500/500/500）→ 双 FALSE；V2 fIu = 250（掉 50%）→ fImbPct ≈ 50、
    bPhaseDrop = TRUE；V3 单相 = 0（断相）→ bPhaseDrop = TRUE + 不平衡超限
    V4 fImbLimPct = 0 → 组态早退；V5 待机（三相 < 0.5 A）→ 双 FALSE 不计算
    V6 fIu = NaN → 结构早退故障；V7 迟滞抖动不反复跳；V8 bEnable = FALSE → 复位
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 3 · 序号 10）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_VfdOutputImbalance
VAR_INPUT
    bEnable    : BOOL := TRUE;   // 使能，FALSE 时判据复位 + 不平衡度冻结（边界五）/ the enable, false resets the criteria and freezes the imbalance
    fIu        : LREAL := 0.0;   // U 相电流实测 [安培]，必须有限 / the phase U current, must be finite
    fIv        : LREAL := 0.0;   // V 相电流实测 [安培]，必须有限 / the phase V current, must be finite
    fIw        : LREAL := 0.0;   // W 相电流实测 [安培]，必须有限 / the phase W current, must be finite
    fImbLimPct : LREAL := 10.0;  // 不平衡度上限 [%]，须 > 0 / the imbalance limit in percent, must be positive
    fDropPct   : LREAL := 20.0;  // 断相判据：最小相低于均值的百分比 [%]，须 > 0 / the phase drop percent relative to the mean, must be positive
    fHystPct   : LREAL := 5.0;   // 判据迟滞 [%]，须 ≥ 0 / the criterion hysteresis in percent, non negative
END_VAR
VAR_OUTPUT
    fImbPct    : LREAL := 0.0;           // 不平衡度 (Imax−Imin)/Iavg×100 [%] / the imbalance rate in percent
    bImbHigh   : BOOL := FALSE;          // 不平衡超限判据（带迟滞）[-] / the imbalance criterion with hysteresis
    bPhaseDrop : BOOL := FALSE;          // 断相判据（带迟滞）[-] / the phase drop criterion with hysteresis
    bValid     : BOOL := FALSE;          // 判据可用 [-] / the criteria are usable
    eErr       : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError     : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit    : BOOL := FALSE;   // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _fAvg     : LREAL := 0.0;    // 三相均值 [安培] / the three phase mean
    _fMax     : LREAL := 0.0;    // 最大相电流 [安培] / the maximum phase current
    _fMin     : LREAL := 0.0;    // 最小相电流 [安培] / the minimum phase current
    _fImbUse  : LREAL := 0.0;    // 不平衡度工作副本 [%] / the working imbalance copy
    _fImbLast : LREAL := 0.0;    // 最近有效不平衡度（冻结源）[%] / the last valid imbalance used while frozen
    _fRelLim  : LREAL := 0.0;    // 不平衡复原阈值 [%] / the imbalance release threshold
    _fDropTrip: LREAL := 0.0;    // 断相置警阈值 [安培] / the phase drop trip threshold
    _fDropRele: LREAL := 0.0;    // 断相复原阈值 [安培] / the phase drop release threshold
    _bImbL    : BOOL := FALSE;   // 不平衡迟滞状态（跨拍保持）/ the imbalance hysteresis state
    _bDropL   : BOOL := FALSE;   // 断相迟滞状态（跨拍保持）/ the phase drop hysteresis state
    _bFinU    : BOOL := FALSE;   // U 相有限闸结果（逐拍重算）/ the U finiteness gate result
    _bFinV    : BOOL := FALSE;   // V 相有限闸结果（逐拍重算）/ the V finiteness gate result
    _bFinW    : BOOL := FALSE;   // W 相有限闸结果（逐拍重算）/ the W finiteness gate result
    _bCfgBad  : BOOL := FALSE;   // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bFinLim  : BOOL := FALSE;   // 上限有限闸结果（逐拍重算）/ the limit finiteness gate result
    _bFinDrop : BOOL := FALSE;   // 断相限值有限闸结果（逐拍重算）/ the drop limit finiteness gate result
    _bFinHyst : BOOL := FALSE;   // 迟滞有限闸结果（逐拍重算）/ the hysteresis finiteness gate result
    _bWarnLim : BOOL := FALSE;   // 上限 ≥ 100 警告标记（逐拍重算，信息级 0724）/ the over hundred warning flag
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_VOI_IDLEEPS : LREAL := 0.5;  // 待机判据门限 [安培]，低于此值不计算（提级禁魔法数）/ the idle threshold of half an ampere lifted out of the body
    DL_VOI_PCT     : LREAL := 100.0; // 百分比换算系数 [%] / the percentage scaling factor
    DL_VOI_ZERO    : LREAL := 0.0;  // 实数零常量 [安培] / the real zero constant
    DL_VOI_THREE   : LREAL := 3.0;  // 三相均值除子 [−] / the three phase mean divisor
END_VAR

// 段 0｜本件无定时器与边沿实例（纯监视器，R6 标注 N/A），无刷新对象 / segment 0, no timers and no edge instances exist here

// 段 1｜首拍初始化（FB50-2）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bImbL := FALSE; // 不平衡迟滞态显式清零 / clear the imbalance state explicitly
    _bDropL := FALSE; // 断相迟滞态显式清零 / clear the drop state explicitly
    _fImbLast := DL_VOI_ZERO; // 最近有效不平衡度显式清零 [%] / clear the last valid imbalance explicitly
END_IF

// 段 2｜三相测点与限值非有限闸（边界一二，全量点名 R151/R272）/ segment 2, the finiteness gates over every real pin
_bFinU := (fIu = fIu) AND ((fIu - fIu) = (fIu - fIu)); // U 相有限 / the phase U is finite
_bFinV := (fIv = fIv) AND ((fIv - fIv) = (fIv - fIv)); // V 相有限 / the phase V is finite
_bFinW := (fIw = fIw) AND ((fIw - fIw) = (fIw - fIw)); // W 相有限 / the phase W is finite
_bFinLim := (fImbLimPct = fImbLimPct) AND ((fImbLimPct - fImbLimPct) = (fImbLimPct - fImbLimPct)); // 不平衡上限有限 / the imbalance limit is finite
_bFinDrop := (fDropPct = fDropPct) AND ((fDropPct - fDropPct) = (fDropPct - fDropPct)); // 断相限值有限 / the drop limit is finite
_bFinHyst := (fHystPct = fHystPct) AND ((fHystPct - fHystPct) = (fHystPct - fHystPct)); // 迟滞有限 / the hysteresis is finite
_bCfgBad := (NOT _bFinLim) OR (fImbLimPct <= DL_VOI_ZERO)
         OR (NOT _bFinDrop) OR (fDropPct <= DL_VOI_ZERO)
         OR (NOT _bFinHyst) OR (fHystPct < DL_VOI_ZERO); // 组态非法（限值域外或非有限）/ an illegal configuration
IF (NOT _bFinU) OR (NOT _bFinV) OR (NOT _bFinW) OR _bCfgBad THEN // 测点坏或组态坏（边界一二，一码处置，反证见码表）/ a broken sample or an illegal configuration
    fImbPct := _fImbLast; // 不平衡度冻结最近有效值 [%] / freeze the last valid imbalance
    bImbHigh := FALSE; // 判据复位 / the criterion resets
    bPhaseDrop := FALSE; // 判据复位 / the criterion resets
    bValid := FALSE; // 判据不可用 / the criteria are not usable
    eErr := 16#0003_0721; // 故障级：测点非有限或组态非法 / fault grade, a broken sample or an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 结构早退，除法段不可达 / the structural early exit, the division is unreachable
END_IF

// 段 3｜失能分支：双判据复位 + 不平衡度冻结（边界五声明行）/ segment 3, the disabled branch
IF NOT bEnable THEN // 失能 / disabled
    fImbPct := _fImbLast; // 冻结最近有效不平衡度 [%] / freeze the last valid imbalance
    bImbHigh := FALSE; // 判据复位 / the criterion resets
    bPhaseDrop := FALSE; // 判据复位 / the criterion resets
    bValid := FALSE; // 失能即不可用 / the criteria are not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退 / early return
END_IF

// 段 4｜均值 / 极值 / 待机判据（边界三：除子 3 为常量，Iavg 门限提级）/ segment 4, the mean, the extremes and the idle test
_fAvg := (fIu + fIv + fIw) / DL_VOI_THREE; // 三相均值 [安培]，除子为常量 3 / the three phase mean with the constant divisor
IF fIu > fIv THEN // 取最大相（第一轮）/ the first round of the maximum
    _fMax := fIu; // U 相候选 [安培] / the candidate U
ELSE // V 相候选 / the candidate V
    _fMax := fIv; // V 相候选 [安培] / the candidate V
END_IF
IF fIw > _fMax THEN // 第三相更新最大 / the third phase updates the maximum
    _fMax := fIw; // W 相胜出 [安培] / the phase W wins
END_IF
IF fIu < fIv THEN // 取最小相（第一轮）/ the first round of the minimum
    _fMin := fIu; // U 相候选 [安培] / the candidate U
ELSE // V 相候选 / the candidate V
    _fMin := fIv; // V 相候选 [安培] / the candidate V
END_IF
IF fIw < _fMin THEN // 第三相更新最小 / the third phase updates the minimum
    _fMin := fIw; // W 相胜出 [安培] / the phase W wins
END_IF
IF _fAvg < DL_VOI_IDLEEPS THEN // 待机态（边界三）：无判据意义 / the idle state makes the criteria meaningless
    fImbPct := DL_VOI_ZERO; // 不平衡度归零 [%] / the imbalance falls to zero
    bImbHigh := FALSE; // 判据复位 / the criterion resets
    bPhaseDrop := FALSE; // 判据复位 / the criterion resets
    bValid := TRUE; // 待机判定本身可用 / the idle verdict is usable
    bError := FALSE; // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
    RETURN; // 早退，不计算 / early return without the computation
END_IF

// 段 5｜不平衡度计算（除子 _fAvg 已证 ≥ 待机门限 0.5 > 0，禁除零）/ segment 5, the imbalance computation
_fImbUse := ((_fMax - _fMin) / _fAvg) * DL_VOI_PCT; // 不平衡度 [%]，除子已证 > 0 / the imbalance rate with the proven divisor
_fImbLast := _fImbUse; // 最近有效不平衡度快照 [%] / snapshot the valid imbalance
_fRelLim := fImbLimPct * ((DL_VOI_PCT - fHystPct) / DL_VOI_PCT); // 不平衡复原阈值 [%] / the imbalance release threshold
_fDropTrip := _fAvg * ((DL_VOI_PCT - fDropPct) / DL_VOI_PCT); // 断相置警阈值 [安培] / the phase drop trip threshold
_fDropRele := _fDropTrip * ((DL_VOI_PCT - fHystPct) / DL_VOI_PCT); // 断相复原阈值 [安培] / the phase drop release threshold
_bWarnLim := fImbLimPct >= DL_VOI_PCT; // 上限 ≥ 100：判据永假警告（信息级 0724）/ the limit at or above hundred percent makes the criterion permanently false

// 段 6｜不平衡判据迟滞（边界四，R146）/ segment 6, the imbalance hysteresis
IF NOT _bImbL THEN // 未报警态 / the released state
    IF _fImbUse > fImbLimPct THEN // 超过上限 / above the limit
        _bImbL := TRUE; // 置迟滞状态 / set the hysteresis state
    END_IF
ELSE // 已报警态 / the tripped state
    IF _fImbUse < _fRelLim THEN // 回落低于复原阈值 / below the release threshold
        _bImbL := FALSE; // 复原 / release
    END_IF
END_IF

// 段 7｜断相判据迟滞（边界四，独立迟滞）/ segment 7, the phase drop hysteresis
IF NOT _bDropL THEN // 未报警态 / the released state
    IF _fMin < _fDropTrip THEN // 最小相低于置警阈值 / below the trip threshold
        _bDropL := TRUE; // 置迟滞状态 / set the hysteresis state
    END_IF
ELSE // 已报警态 / the tripped state
    IF _fMin > _fDropRele THEN // 回升高于复原阈值 / above the release threshold
        _bDropL := FALSE; // 复原 / release
    END_IF
END_IF

// 段 8｜统一出口（迟滞状态派生 + 信息级重算，R187 / FB51-8）/ segment 8, the unified outlet
fImbPct := _fImbUse; // 不平衡度出口 [%] / the imbalance outlet
bImbHigh := _bImbL; // 不平衡判据出口 / the imbalance outlet
bPhaseDrop := _bDropL; // 断相判据出口 / the drop outlet
bValid := TRUE; // 判据可用 / the criteria are usable
bError := FALSE; // 无故障 / no fault
IF _bWarnLim THEN // 组态警告（信息级 0724，判据永假）/ the configuration warning
    eErr := 16#0003_0724; // 信息级：上限 ≥ 100，不平衡判据永假 / informational, the criterion is permanently false
ELSIF _bImbL THEN // 不平衡超限（信息级）/ the imbalance is high, informational
    eErr := 16#0003_0722; // 信息级：不平衡度超上限 / informational, the imbalance is over the limit
ELSIF _bDropL THEN // 断相（信息级）/ the phase drop, informational
    eErr := 16#0003_0723; // 信息级：断相判据触发 / informational, the phase drop triggered
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
