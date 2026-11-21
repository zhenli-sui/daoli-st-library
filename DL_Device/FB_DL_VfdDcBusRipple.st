(*
  ==================================================================
  组件名 Component  : FB_DL_VfdDcBusRipple
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0003_0710 / 0712 / 0713（故障级）｜ 16#0003_0711 / 0714 / 0715 / 0716（信息级）
  版本   Version    : 1.0.1
  复杂度 Complexity  : 中
  功能   Purpose    : 变频器直流母线电压的均值 / 峰峰值纹波率 / 欠压 / 过压三路监视
                      （电解电容老化、整流缺相、制动能量回灌的早期征兆）。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）；
                      纹波率与欠压/过压判据取自公开电力电子测量工程口径（分类与公式借鉴，
                      零代码复制），滤波、闸门、迟滞与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符与 §6.6.1 比较语义；直流母线纹波率
                      的公开工程定义（峰峰值 ÷ 均值）
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（无库调用、无定时器）
  分工声明 Split     : FB_DL_BrakeResistorThermal 为制动电阻热模型、FB_DL_VfdThermalDerate
                      为降额策略、FB_DL_InverterGridSync 为并网同步；本件为母线电气健康
                      监视（只测量不驱动功率级），四件边界写死（R216 双向互引）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 环形窗固定容量 128（禁动态分配），写头 _nHead + 填充计数 _nFill；
                         均值除子用 _nFill（钳 ≥ 1）而非 nWinLen——首填阶段除子若用窗长，
                         均值会系统性偏小并漏报启动期异常（R61-D4 同类陷阱，本件出厂即正确）；
                      二 nWinLen 逐拍可变：变更沿（_nUse ≠ _nUsePrev）全窗清零——和 / 写头 /
                         填充计数 / 环元素逐项清（只清和不清环元素会让减项把陈旧样本扣回和里）；
                      三 fUdNom 既作除子又作基准，故 ≤ 0 或非有限一律判组态故障并置
                         bValid = FALSE（除零防护）；
                      四 纹波率 = (max − min) / avg × 100；|avg| < 1.0 V 时纹波率不可算，
                         判故障码而非静默出零（静默出零会被 HMI 当成「纹波很小」）；
                      五 三路判据各带迟滞（fHystPct）：欠压 trip < 下限、复原 > 下限 + 迟滞；
                         过压 trip > 上限、复原 < 上限 − 迟滞；纹波 trip > 上限、复原 < 上限 − 迟滞；
                      六 非有限样本丢弃并计数，累计超窗长一半即判测量失效（区分「偶发坏点」
                         与「测点整体失效」）；
                      七 故障码策略（本件无 bReset 引脚，R152 解除路径自证）：组态类与测量类
                         故障码逐拍重算不锁存，解除路径 = 修正组态 / 恢复测量（恒可达）；
                         首因保序由判据顺序保证，故障相不回放末因；
                         v1.0.1 返修（R63 · 修 R62-D1 严重）：组态非法由「只置标志不早退」
                         改为「段 3 末尾结构早退」（出口三件套 bValid = FALSE + 码 0710 +
                         bError + RETURN），段 6 均值除法与段 8 (fAvg / fUdNom) 除法在
                         组态故障拍结构性不可达，fUdNom = 0 不再直穿除法；
                      八 bEnable = FALSE：三路判据全 FALSE、纹波率归零、均值保留最后有效值
                         （纯监视件不驱动功率级，保留均值供 HMI 显示是比较读数，非安全出口）；
                      九 首拍 _bInit 初始化全量内部量；无定时器 / 无边沿实例，故段 0 无刷新对象
                         （R6 标注 N/A，本件为无状态机监视器）；无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0003_0710【故障级】组态非法（fUdNom ≤ 0 / 非有限；限值或迟滞非有限）
    16#0003_0711【信息级】nWinLen 越域已钳位（合法 2..128）
    16#0003_0712【故障级】测量失效（非有限样本累计超过窗长一半，或窗内无可算样本）
    16#0003_0713【故障级】窗均值近零（|avg| < 1.0 V），纹波率不可算
    16#0003_0714【信息级】纹波率超上限（bRippleHigh = TRUE）
    16#0003_0715【信息级】母线欠压（bUnder = TRUE）
    16#0003_0716【信息级】母线过压（bOver = TRUE）
  码位反证 Note     :
    0714 / 0715 / 0716 三码不可合并：三路判据各自有独立布尔出口，但 eErr 只有一个，
    若共用一码则「同时欠压且纹波超限」时无法告知先修哪一路（处置人不同：欠压查整流
    输入，纹波查电容，过压查制动能量）（R90 反证句）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 恒定输入（纹波 0）→ fRipplePct = 0、三路判据全 FALSE
    V2 首个样本（_nFill = 1）→ 均值 = 单样本、bValid = FALSE（窗未达 nWinLen/2 门限）
    V3 nWinLen 由 64 改 16 → 窗清零、nFill = 0，均值不含旧样本（R61-D4 回归向量）
    V4 fUdNom = 0 → 码 0710 + bValid = FALSE（禁除零）
    V5 fUd = 0 且 fUdNom > 0 → bUnder = TRUE，纹波率因均值近零走码 0713
    V6 全部样本非有限 → 码 0712 + bValid = FALSE
    V7 欠压在阈值上下抖动 1%（小于迟滞 2%）→ bUnder 不反复跳
    V8 nWinLen = 1 或 129 → 钳位 + 码 0711（与域声明一致）
    V9 fUdNom = 0 且 bEnable = FALSE → 同拍码 0710 + bValid = FALSE，段 6/段 8 除法
       不可达（v1.0.1 结构早退回归向量）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 4 · 序号 10）
    2026-11-21  v1.0.1  R63 返修 R1（R62-D1 严重）：段 3 末尾新增组态非法结构早退
                        （三件套 + 码 0710 + RETURN），fUdNom = 0 除法直穿路径封死
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_VfdDcBusRipple
VAR_INPUT
    bEnable       : BOOL := TRUE;       // 使能，FALSE 时判据全关（边界八）/ the enable, false turns every criterion off
    fUdMeas       : LREAL := 0.0;       // 母线电压实测 [伏]，必须有限 / the measured bus voltage, must be finite
    fUdNom        : LREAL := 540.0;     // 额定母线电压 [伏]，必须 > 0（既作基准又作除子）/ the nominal bus voltage, positive and used as both the reference and the divisor
    tSample       : TIME := T#1MS;      // 采样周期标称值 [毫秒]，仅作记录（本件不设定时器）/ the nominal sample period, recorded only
    nWinLen       : DINT := 64;         // 滑窗样本数 [个]，合法 2..128 / the window length in samples, legal two to one hundred twenty eight
    fRippleLimPct : LREAL := 5.0;       // 纹波率上限 [%]，相对均值 / the ripple rate limit in percent of the mean
    fUnderLimPct  : LREAL := 85.0;      // 欠压阈值 [%]，相对额定 / the undervoltage threshold relative to the nominal
    fOverLimPct   : LREAL := 115.0;     // 过压阈值 [%]，相对额定 / the overvoltage threshold relative to the nominal
    fHystPct      : LREAL := 2.0;       // 三路判据迟滞 [%]，须 ≥ 0 / the hysteresis of all three criteria, non negative
END_VAR
VAR_OUTPUT
    fUdAvg      : LREAL := 0.0;          // 窗均值 [伏] / the window mean voltage
    fRipplePct  : LREAL := 0.0;          // 峰峰值纹波率 [%] / the peak to peak ripple rate in percent
    bUnder      : BOOL := FALSE;         // 欠压判据（带迟滞）[-] / the undervoltage criterion with hysteresis
    bOver       : BOOL := FALSE;         // 过压判据（带迟滞）[-] / the overvoltage criterion with hysteresis
    bRippleHigh : BOOL := FALSE;         // 纹波率超上限判据（带迟滞）[-] / the ripple criterion with hysteresis
    nFill       : DINT := 0;             // 窗已填样本数 [个] / the filled sample count
    bValid      : BOOL := FALSE;         // 测量可用（窗达半满且无故障）[-] / the measurement is usable
    eErr        : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
    bError      : BOOL := FALSE;         // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit      : BOOL := FALSE;              // 首拍初始化标志（R310）/ the first scan flag
    _afWin      : ARRAY[0..127] OF LREAL;     // 母线电压环形窗 [伏]，固定容量 128 / the fixed capacity ring of the bus voltage
    _nHead      : DINT := 0;                  // 环形窗写头 [下标] / the ring write head
    _nFill      : DINT := 0;                  // 环形窗已填样本数 [个]（均值除子）/ the filled sample count used as the mean divisor
    _nUse       : DINT := 64;                 // 钳位后的窗长 [个] / the clamped window length
    _nUsePrev   : DINT := 0;                  // 上拍窗长快照 [个]，置 0 使首拍必触发一次全窗清零 / the previous length, zero forces one full clear
    _nRingIdx   : DINT := 0;                  // 环元素清零遍历索引 [下标] / the ring clearing traversal index
    _nScanIdx   : DINT := 0;                  // 极值统计遍历索引 [下标] / the extreme value traversal index
    _nNonFinite : DINT := 0;                  // 连续非有限样本计数 [个] / the consecutive non finite sample count
    _fSum       : LREAL := 0.0;               // 环窗电压和 [伏] / the ring voltage sum
    _fMax       : LREAL := 0.0;               // 窗内最大值 [伏] / the window maximum
    _fMin       : LREAL := 0.0;               // 窗内最小值 [伏] / the window minimum
    _fAvg       : LREAL := 0.0;               // 本拍均值工作副本 [伏] / the working mean of this scan
    _fRip       : LREAL := 0.0;               // 本拍纹波率工作副本 [%] / the working ripple rate of this scan
    _fPct       : LREAL := 0.0;               // 均值相对额定的百分比 [%] / the mean as a percentage of the nominal
    _bFinMeas   : BOOL := FALSE;              // 样本有限闸结果（逐拍重算）/ the sample finiteness gate result
    _bCfgBad    : BOOL := FALSE;              // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bWinClamp  : BOOL := FALSE;              // 窗长钳位标记（逐拍重算，信息级 0711）/ the window clamp flag
    _bMeasBad   : BOOL := FALSE;              // 测量失效标记（窗内无样本 / 连续坏点超半窗，逐拍重算）/ the measurement failure flag
    _bAvgZero   : BOOL := FALSE;              // 均值近零标记（纹波率不可算，逐拍重算，码 0713）/ the near zero mean flag under which the ripple is undefined
    _fAvgLast   : LREAL := 0.0;               // 最近一次有效均值 [伏]（失能相显示用，禁自赋值出口）/ the last valid mean kept for the disabled phase
    _bUnderL    : BOOL := FALSE;              // 欠压迟滞状态寄存器（跨拍保持）/ the undervoltage hysteresis state
    _bOverL     : BOOL := FALSE;              // 过压迟滞状态寄存器（跨拍保持）/ the overvoltage hysteresis state
    _bRipL      : BOOL := FALSE;              // 纹波迟滞状态寄存器（跨拍保持）/ the ripple hysteresis state
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_VFD_WMAX   : DINT := 128;     // 环形窗容量 [个]，与数组容量一致 / the ring capacity aligned with the array
    DL_VFD_WMIN   : DINT := 2;       // 窗长下界 [个]（单样本无峰峰值语义）/ the window floor, one sample has no peak to peak meaning
    DL_VFD_HALF   : LREAL := 2.0;    // 半满门限除子 [-] / the half full threshold divisor
    DL_VFD_AVGMIN : LREAL := 1.0;    // 均值近零门限 [伏]，低于此值纹波率不可算 / the near zero mean threshold below which the ripple is undefined
    DL_VFD_PCT    : LREAL := 100.0;  // 百分比换算系数 [%] / the percentage scaling factor
    DL_VFD_ZERO   : LREAL := 0.0;    // 实数零常量 [伏] / the real zero constant
    DL_VFD_ONE    : DINT := 1;       // 整型一常量 [个] / the integer one constant
    DL_VFD_DZERO  : DINT := 0;       // 整型零常量 [个] / the integer zero constant
END_VAR

// 段 0｜本件无定时器与边沿实例（纯监视器，R6 标注 N/A），无刷新对象 / segment 0, no timers and no edge instances exist here

// 段 1｜首拍初始化（R310 / FB50-2）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _nFill := DL_VFD_DZERO; // 填充计数显式清零 / clear the filled count explicitly
    _nHead := DL_VFD_DZERO; // 写头显式清零 / clear the write head explicitly
    _fSum := DL_VFD_ZERO; // 环窗和显式清零 / clear the ring sum explicitly
    _nUsePrev := DL_VFD_DZERO; // 窗长快照置 0，使段 3 变更沿必然触发一次全窗清零 / zero the snapshot so the change edge clears the ring once
    _nNonFinite := DL_VFD_DZERO; // 非有限计数显式清零 / clear the non finite count explicitly
    _bUnderL := FALSE; // 欠压迟滞状态显式清零 / clear the undervoltage state explicitly
    _bOverL := FALSE; // 过压迟滞状态显式清零 / clear the overvoltage state explicitly
    _bRipL := FALSE; // 纹波迟滞状态显式清零 / clear the ripple state explicitly
    FOR _nRingIdx := 0 TO DL_VFD_WMAX - DL_VFD_ONE DO // 有界遍历全容量（128 项）/ the bounded traversal over the full capacity
        _afWin[_nRingIdx] := DL_VFD_ZERO; // 环元素逐项清零 / zero every ring element
    END_FOR
    _afWin[DL_VFD_DZERO] := DL_VFD_ZERO; // 显式覆盖首元素（配合上面的有界遍历，防遍历上下界被改动）/ explicitly cover the first element in case the traversal bounds change
    _fAvgLast := DL_VFD_ZERO; // 最近有效均值显式清零 / clear the last valid mean explicitly
END_IF

// 段 2｜单拍量预置 / segment 2, the per scan preset
_bCfgBad := FALSE; // 组态非法标记预清零 / preset the configuration flag false
_bWinClamp := FALSE; // 窗长钳位标记预清零 / preset the window clamp flag false
_bMeasBad := FALSE; // 测量失效标记预清零 / preset the measurement failure flag false
_bAvgZero := FALSE; // 均值近零标记预清零 / preset the near zero mean flag false
_fRip := DL_VFD_ZERO; // 纹波率工作副本预置零 [%] / preset the ripple copy zero

// 段 3｜组态域闸（边界三，全部限值与非有限逐个点名，R272）/ segment 3, the configuration gates
_bFinMeas := (fUdMeas = fUdMeas) AND ((fUdMeas - fUdMeas) = (fUdMeas - fUdMeas)); // 样本有限 / the sample is finite
IF (fUdNom <> fUdNom) OR ((fUdNom - fUdNom) <> (fUdNom - fUdNom)) OR (fUdNom <= DL_VFD_ZERO) THEN // 额定非有限或非正 / the nominal is not finite or not positive
    _bCfgBad := TRUE; // 置组态标记 / raise the configuration flag
ELSIF (fRippleLimPct <> fRippleLimPct) OR ((fRippleLimPct - fRippleLimPct) <> (fRippleLimPct - fRippleLimPct))
   OR (fUnderLimPct <> fUnderLimPct) OR ((fUnderLimPct - fUnderLimPct) <> (fUnderLimPct - fUnderLimPct))
   OR (fOverLimPct <> fOverLimPct) OR ((fOverLimPct - fOverLimPct) <> (fOverLimPct - fOverLimPct))
   OR (fHystPct <> fHystPct) OR ((fHystPct - fHystPct) <> (fHystPct - fHystPct))
   OR (fHystPct < DL_VFD_ZERO) THEN // 限值或迟滞非有限 / a limit or the hysteresis is not finite
    _bCfgBad := TRUE; // 置组态标记 / raise the configuration flag
END_IF

// 段 3A｜组态非法结构早退（v1.0.1 修 R62-D1：出口三件套 + RETURN，除法结构性不可达）/ segment 3A, the structural early exit on an illegal configuration
IF _bCfgBad THEN // 组态非法（额定非正 / 非有限或限值坏）：禁入任何除法段 / an illegal configuration forbids every division segment below
    fUdAvg := _fAvgLast; // 均值保持最近有效值（禁自赋值出口，R261）/ keep the last valid mean instead of a self assignment
    fRipplePct := DL_VFD_ZERO; // 纹波率归零 [%] / the ripple rate falls to zero
    bUnder := FALSE; // 欠压判据关 / the undervoltage criterion off
    bOver := FALSE; // 过压判据关 / the overvoltage criterion off
    bRippleHigh := FALSE; // 纹波判据关 / the ripple criterion off
    nFill := _nFill; // 填充计数照实出口 [个] / the fill count is exported as is
    bValid := FALSE; // 输出不可用 / the measurement is not usable
    eErr := 16#0003_0710; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退：段 6 除法与段 8 (fAvg / fUdNom) 除法在本拍不可达 / early return, the divisions in segment six and segment eight are unreachable on this scan
END_IF

// 段 4｜窗长钳位与变更沿全窗清零（边界二，R61-D4 修法固化）/ segment 4, the window length clamp and the full clear
_nUse := nWinLen; // 窗长接管 [个] / take the window length
IF (_nUse < DL_VFD_WMIN) OR (_nUse > DL_VFD_WMAX) THEN // 窗长越域 / the length is out of the domain
    _bWinClamp := TRUE; // 置钳位标记（信息级 0711）/ raise the clamp flag
    IF _nUse < DL_VFD_WMIN THEN // 下界钳位 / the floor clamp
        _nUse := DL_VFD_WMIN; // 钳到下界 [个] / clamp to the floor
    ELSE // 上界钳位 / the ceiling clamp
        _nUse := DL_VFD_WMAX; // 钳到容量 [个] / clamp to the capacity
    END_IF
END_IF
IF _nUse <> _nUsePrev THEN // 窗长变更沿（含首拍）/ the length change edge, the first scan included
    _fSum := DL_VFD_ZERO; // 环窗和清零 [伏] / clear the ring sum
    _nHead := DL_VFD_DZERO; // 写头回零 / reset the write head
    _nFill := DL_VFD_DZERO; // 填充计数回零 / reset the filled count
    _nNonFinite := DL_VFD_DZERO; // 非有限计数回零 / reset the non finite count
    FOR _nRingIdx := 0 TO DL_VFD_WMAX - DL_VFD_ONE DO // 有界遍历全容量 / the bounded traversal over the full capacity
        _afWin[_nRingIdx] := DL_VFD_ZERO; // 环元素逐项清零：减项读到零才不会把旧样本扣回和里 / zero every element so the subtract term cannot re-inject a stale sample
    END_FOR
    _nUsePrev := _nUse; // 快照本拍窗长 / snapshot the length
END_IF

// 段 5｜样本入窗（非有限样本丢弃并计数，边界六）/ segment 5, push the sample or count the drop
IF _bFinMeas THEN // 有限样本才入窗 / only a finite sample enters the ring
    _fSum := _fSum - _afWin[_nHead] + fUdMeas; // 滑窗和更新（被替换槽已证为有效样本或零）[伏] / update the sliding sum, the replaced slot is a live sample or zero
    _afWin[_nHead] := fUdMeas; // 本拍样本入环 [伏] / push the sample
    _nHead := _nHead + DL_VFD_ONE; // 写头推进 / advance the head
    IF _nHead >= _nUse THEN // 回卷（按钳位窗长）/ wrap by the clamped length
        _nHead := DL_VFD_DZERO; // 写头回零 / reset the head
    END_IF
    IF _nFill < _nUse THEN // 窗未满才累加 / count only while the window is not yet full
        _nFill := _nFill + DL_VFD_ONE; // 填充计数推进 [个] / advance the filled count
    END_IF
    _nNonFinite := DL_VFD_DZERO; // 连续非有限计数归零（按「连续」口径，非累计）/ reset the consecutive drop count
ELSE // 非有限样本：丢弃并计数 / a non finite sample is dropped and counted
    _nNonFinite := _nNonFinite + DL_VFD_ONE; // 非有限计数推进 [个] / advance the drop count
END_IF
IF DINT_TO_LREAL(_nNonFinite) > (DINT_TO_LREAL(_nUse) / DL_VFD_HALF) THEN // 连续坏点超窗长一半 / the consecutive drops exceed half the window
    _bMeasBad := TRUE; // 置测量失效标记（码 0712）/ raise the measurement failure flag
END_IF
IF _nFill < DL_VFD_ONE THEN // 窗内无可算样本（与失效同码，出口不可分，R90）/ no sample is available at all
    _bMeasBad := TRUE; // 置测量失效标记 / raise the measurement failure flag
END_IF

// 段 6｜均值与极值（除子 = _nFill，首填不偏小，边界一）/ segment 6, the mean and the extremes with the fill based divisor
IF _nFill >= DL_VFD_ONE THEN // 除子已证 ≥ 1（禁用裸除子）/ the divisor is proven at least one
    _fAvg := _fSum / DINT_TO_LREAL(_nFill); // 窗均值 [伏] / the window mean
    _fMax := _afWin[DL_VFD_DZERO]; // 最大值初值取首元素 [伏] / seed the maximum from the first element
    _fMin := _afWin[DL_VFD_DZERO]; // 最小值初值取首元素 [伏] / seed the minimum from the first element
    // 遍历口径证明：写头仅在 _nHead 达到 _nUse 时回卷，故填充未满时有效样本恰为下标 0.._nFill-1；
    // 填满后有效样本恰为 0.._nUse-1，两者都等于区间 [0, _nFill-1]（_nFill 已封顶于 _nUse）。
    // traversal proof: the head wraps only after reaching the length, so the live samples always occupy the range from zero to the fill count minus one.
    FOR _nScanIdx := DL_VFD_ONE TO _nFill - DL_VFD_ONE DO // 有界遍历有效样本 / the bounded traversal over the live samples
        IF _afWin[_nScanIdx] > _fMax THEN // 更新最大值 / update the maximum
            _fMax := _afWin[_nScanIdx]; // 最大值替换 [伏] / replace the maximum
        END_IF
        IF _afWin[_nScanIdx] < _fMin THEN // 更新最小值 / update the minimum
            _fMin := _afWin[_nScanIdx]; // 最小值替换 [伏] / replace the minimum
        END_IF
    END_FOR
ELSE // 无样本：均值保持最近有效值（禁自赋值出口，R261）/ no sample, keep the last valid mean instead of a self assignment
    _fAvg := _fAvgLast; // 最近有效均值 [伏] / the last valid mean
END_IF

// 段 7｜纹波率（均值近零判故障，不静默出零，边界四）/ segment 7, the ripple rate with the near zero mean guard
IF _nFill >= DL_VFD_ONE THEN // 有样本才谈纹波 / the ripple is only meaningful with samples
    IF ABS(_fAvg) < DL_VFD_AVGMIN THEN // 均值近零：纹波率不可算 / a near zero mean makes the ripple undefined
        _bAvgZero := TRUE; // 置均值近零标记（码 0713 的独立成因，R190）/ raise the near zero flag as its own cause
    ELSE // 均值可用 / a usable mean
        _fRip := ((_fMax - _fMin) / ABS(_fAvg)) * DL_VFD_PCT; // 峰峰值纹波率 [%] / the peak to peak ripple rate
        _fAvgLast := _fAvg; // 最近有效均值快照（写前已过近零与有限闸）[伏] / snapshot the last valid mean after the gates
    END_IF
END_IF

// 段 8｜三路判据（各带迟滞，边界五，方向各自独立，R146）/ segment 8, the three criteria with independent hysteresis
IF _nFill >= DL_VFD_ONE THEN // 有样本才判 / judge only with samples
    _fPct := (_fAvg / fUdNom) * DL_VFD_PCT; // 均值相对额定 [%]（用本拍均值，不读上拍出口）/ the mean relative to the nominal using this scan value
    // 欠压：低于下限触发，回升超过「下限 + 迟滞」才复原 / undervoltage trips below the limit and releases above the limit plus the hysteresis
    IF NOT _bUnderL THEN // 未报警态 / the released state
        IF _fPct < fUnderLimPct THEN // 跌破下限 / below the limit
            _bUnderL := TRUE; // 置迟滞状态 / set the hysteresis state
        END_IF
    ELSE // 已报警态 / the tripped state
        IF _fPct > (fUnderLimPct + fHystPct) THEN // 回升超过下限加迟滞 / above the limit plus the hysteresis
            _bUnderL := FALSE; // 复原 / release
        END_IF
    END_IF
    // 过压：高于上限触发，回落低于「上限 − 迟滞」才复原 / overvoltage trips above the limit and releases below the limit minus the hysteresis
    IF NOT _bOverL THEN // 未报警态 / the released state
        IF _fPct > fOverLimPct THEN // 超过上限 / above the limit
            _bOverL := TRUE; // 置迟滞状态 / set the hysteresis state
        END_IF
    ELSE // 已报警态 / the tripped state
        IF _fPct < (fOverLimPct - fHystPct) THEN // 回落低于上限减迟滞 / below the limit minus the hysteresis
            _bOverL := FALSE; // 复原 / release
        END_IF
    END_IF
    // 纹波：高于上限触发，回落低于「上限 − 迟滞」才复原 / the ripple trips above the limit and releases below the limit minus the hysteresis
    IF NOT _bRipL THEN // 未报警态 / the released state
        IF _fRip > fRippleLimPct THEN // 超过上限 / above the limit
            _bRipL := TRUE; // 置迟滞状态 / set the hysteresis state
        END_IF
    ELSE // 已报警态 / the tripped state
        IF _fRip < (fRippleLimPct - fHystPct) THEN // 回落低于上限减迟滞 / below the limit minus the hysteresis
            _bRipL := FALSE; // 复原 / release
        END_IF
    END_IF
END_IF

// 段 9｜统一出口（R191 名实双出口：bEnable = FALSE 时判据全关但均值保留）/ segment 9, the unified outlet
IF NOT bEnable THEN // 失能：判据全关、纹波归零、均值保留（边界八）/ disabled, every criterion off, the mean retained
    fUdAvg := _fAvgLast; // 均值保持最近有效值（HMI 比较读数用，禁自赋值）/ keep the last valid mean for the HMI
    fRipplePct := DL_VFD_ZERO; // 纹波率归零 [%] / the ripple rate falls to zero
    bUnder := FALSE; // 欠压判据关 / the undervoltage criterion off
    bOver := FALSE; // 过压判据关 / the overvoltage criterion off
    bRippleHigh := FALSE; // 纹波判据关 / the ripple criterion off
    nFill := _nFill; // 填充计数照实出口 [个] / the fill count is exported as is
    bValid := FALSE; // 失能即不可用 / the measurement is not usable while disabled
    bError := _bCfgBad; // 组态非法照实上报（配置错与失能无关，禁静默）/ an illegal configuration is still reported, it is independent of the enable
    IF _bCfgBad THEN // 组态成因 / the configuration cause
        eErr := 16#0003_0710; // 故障级：组态非法 / fault grade, an illegal configuration
    ELSE // 失能本身不是事件 / a disabled device is not an event
        eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    END_IF
    RETURN; // 早退 / early return
END_IF
fUdAvg := _fAvg; // 均值出口 [伏] / the mean outlet
fRipplePct := _fRip; // 纹波率出口 [%] / the ripple rate outlet
bUnder := _bUnderL; // 欠压判据出口（迟滞状态派生）/ the undervoltage outlet derived from the hysteresis state
bOver := _bOverL; // 过压判据出口 / the overvoltage outlet
bRippleHigh := _bRipL; // 纹波判据出口 / the ripple outlet
nFill := _nFill; // 填充计数出口 [个] / the fill count outlet
bValid := (NOT _bCfgBad) AND (NOT _bMeasBad) AND (NOT _bAvgZero) AND (DINT_TO_LREAL(_nFill) >= (DINT_TO_LREAL(_nUse) / DL_VFD_HALF)); // 可用 = 无故障且窗达半满（边界二门限，显式转换后比较）/ usable, no fault and the window at least half full compared after explicit conversion
bError := _bCfgBad OR _bMeasBad OR _bAvgZero; // 故障位由三路故障成因派生（R190 各成因独立赋值点）/ the fault bit derived from all three fault causes
IF _bCfgBad THEN // 组态成因优先（首因保序，边界七）/ the configuration cause comes first
    eErr := 16#0003_0710; // 故障级：组态非法 / fault grade, an illegal configuration
ELSIF _bMeasBad THEN // 测量失效：窗内无样本或连续坏点超半窗 / the measurement failed on an empty window or a drop burst
    eErr := 16#0003_0712; // 故障级：测量失效 / fault grade, the measurement failed
ELSIF _bAvgZero THEN // 均值近零：纹波率不可算（独立成因，R190）/ a near zero mean under its own cause
    eErr := 16#0003_0713; // 故障级：窗均值近零，纹波率不可算 / fault grade, the mean is near zero and the ripple is undefined
ELSIF _bRipL THEN // 纹波超限（信息级）/ the ripple over the limit, informational
    eErr := 16#0003_0714; // 信息级：纹波率超上限 / informational, the ripple is over the limit
ELSIF _bUnderL THEN // 欠压（信息级）/ undervoltage, informational
    eErr := 16#0003_0715; // 信息级：母线欠压 / informational, the bus is undervoltage
ELSIF _bOverL THEN // 过压（信息级）/ overvoltage, informational
    eErr := 16#0003_0716; // 信息级：母线过压 / informational, the bus is overvoltage
ELSIF _bWinClamp THEN // 窗长钳位（信息级，仅提示）/ the window clamp, informational
    eErr := 16#0003_0711; // 信息级：nWinLen 越域已钳位 / informational, the window length was clamped
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
