(*
  FB_DL_OrificeDpZeroTrim  —  孔板差压零点漂移补偿 / Orifice DP zero-drift trim
  分类 Category : DL_Device
  码位 Code     : 16#03_2_1B
  段位说明      : 03_2 段低半字节已满，1x 段续号，1A 格由 CleaningBrushWear 启用，本件启用 1B 格（R192）
  版本 Version  : 1.0.0
  来源 Source   : t2-8-ne43 — 孔板计量零漂补偿待挖项
  溯源 Origin   : clean-room 实现，未复制任何源码行
                  （与 FC_DL_OrificeFlowCalc 分工：那件算流量，本件只供零点修正量，不算流量）
  功能 Function : 1) 静流时段判定：FC_DL_Deadband 归零型判 |fDpRawPa| 在静流带内 +
                  FB_DL_SignalStatistics 窗口峰峰值不超稳定阈（双判据防假静流）；
                  2) FB_DL_MedianFilter 对静流期样本取中值（抗单点毛刺），作为零漂观测值；
                  3) 静流持续 tZeroDwell（tonZero，单用途计时）→ 零点学习：
                  fZeroOffsetPa += (中值 − 旧零点) × fLearnRate（一阶趋近，学习率组态）；
                  4) 修正量出口：fDpCorrPa = fDpRawPa − fZeroOffsetPa（零点平移语义）。
  边界 Boundary : ① 本件只供修正量出口，不做流量换算、不做量程标定（分工见头注释）；
                  ② 零点学习值限幅 ±fTrimMaxPa（越限钳位 + 信息级码，防坏采样把零点学飞）；
                  ③ fLearnRate 域 (0, 1]，越域判组态故障（学习率 0 = 永不学习亦属组态错）；
                  ④ 非有限原始信号：保持上次有效值 + 信息级码（不中断，修正出口按保持值）；
                  ⑤ R228-A 达标声明：tonZero 单用途计时（IN = 静流判据电平），无跨相复用问题；
                  ⑥ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此。
  依赖 Depends  : FC_DL_Deadband（函数调用）；FB_DL_MedianFilter / FB_DL_SignalStatistics（实例化，引脚按 registry 实名）
  码表 Error codes（本件格 03_2_1B，子码步进 +0x100）:
    16#0003_011B 信息级：静流零点学习完成一次（本拍发生学习写入）
    16#0003_021B 故障级：组态非法（静流带/驻留时长/学习率/限幅域非法），锁存至复位
    16#0003_031B 故障级：保留码，本件无 CASE 主状态机，仅作后续维护者新增分支时的防御式默认码
    16#0003_041B 信息级：原始信号非有限，已保持上次有效值
    16#0003_051B 信息级：零点学习值越限幅，已钳制到 ±fTrimMaxPa

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 3 · 序号 13）
*)

FUNCTION_BLOCK FB_DL_OrificeDpZeroTrim
VAR_INPUT
    fDpRawPa     : REAL := 0.0;       // 原始差压信号 [Pa] / Raw differential pressure signal
    fStaticBandPa: REAL := 20.0;      // 静流判定带半宽 [Pa]，域 > 0 / Static-flow band half width
    fStabRangePa : REAL := 10.0;      // 稳定判据峰峰值阈 [Pa]，域 > 0 / Stability peak-to-peak threshold
    tZeroDwell   : TIME := T#60S;     // 静流驻留学习时长 [ms]，域 > 0 / Static dwell before learning
    fLearnRate   : REAL := 0.2;       // 零点学习率 [无量纲 (0,1]] / Zero learning rate
    fTrimMaxPa   : REAL := 50.0;      // 零点学习值限幅 [Pa]，域 > 0 / Zero offset clamp
    nMedWindow   : INT  := 9;         // 中值窗长 [个]，3..15 奇数（越界钳位）/ Median window length
    bEnable      : BOOL := TRUE;      // 学习使能，FALSE 时只修正不学习 [-] / Learning enable
    bReset       : BOOL := FALSE;     // 故障复位，上升沿生效 / Fault reset, rising edge
    bZeroClr     : BOOL := FALSE;     // 零点清零沿，上升沿 fZeroOffsetPa 归零 / Zero offset clear, rising edge
END_VAR
VAR_OUTPUT
    fDpCorrPa    : REAL;              // 修正后差压 [Pa] = 原始 − 零点 / Corrected DP output
    fZeroOffsetPa: REAL;              // 当前零点学习值 [Pa] / Current learned zero offset
    bStaticFlow  : BOOL;              // 静流判定生效中 [-] / Static flow active flag
    bTrimValid   : BOOL;              // 修正有效（组态合法且输入有限）[-] / Trim validity flag
    bError       : BOOL;              // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch
    uErrorId     : UDINT;             // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR
    fbMed      : FB_DL_MedianFilter;  // 中值滤波实例（主体首部无条件刷新）/ Median filter instance
    fbStat     : FB_DL_SignalStatistics;  // 差压统计窗实例（主体首部无条件刷新）/ DP statistics window instance
    tonZero    : TON;                 // 静流驻留计时（单用途，R228-A 口径）/ Static dwell timer, single purpose
    rtReset    : R_TRIG;              // 复位上升沿 / Reset rising edge
    rtZeroClr  : R_TRIG;              // 零点清零上升沿 / Zero clear rising edge
    _fDpEff    : REAL;                // 生效原始差压 [Pa]（非有限保持载体）/ Effective raw DP with hold carrier
    _fDpLast   : REAL := 0.0;         // 上次有效原始差压 [Pa] / Last valid raw DP
    _fZeroInt  : REAL := 0.0;         // 零点学习值内部量 [Pa]，出口镜像 / Internal zero offset register
    _bStaticDb : BOOL;                // 死区件静流判定 / Deadband static flag
    _bStatic   : BOOL;                // 双判据静流标志 / Combined static flag
    _bLearnEvt : BOOL;                // 本拍发生学习写入标志 / Learning write happened this cycle
    _bLearnBrk : BOOL;                // 学习拍断输入标志（TON 自复位纪律，用后即清）/ Learning break flag for timer reset
    _bRawBad   : BOOL;                // 本拍原始信号非有限标志 / Raw non-finite flag this cycle
    _uInfo     : UDINT;               // 信息码，每拍重算 / Info code
    _uFault    : UDINT;               // 故障码锁存寄存 / Latched fault code register
    _bFault    : BOOL;                // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_ODZ_INF_CAP : REAL := 1.0E15;  // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 0：定时器与边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                 // 复位沿刷新，每拍必调
rtZeroClr(CLK := bZeroClr);                             // 零点清零沿刷新，每拍必调
fbMed(fIn := _fDpEff,                                   // 中值滤波（输入为生效原始值）
      bSample := TRUE,                                  // 每拍采样（静流判据由外部承载）
      nWindow := nMedWindow,                            // 窗长（组态透传，内部钳位）
      bClear := FALSE);                                 // 不清窗（连续观测）
fbStat(fIn := _fDpEff,                                  // 统计窗（稳定判据用）
       bSample := TRUE,                                 // 每拍采样
       nWindow := 32,                                   // 窗长（稳定判据标准口径）
       bClear := FALSE);                                // 不清窗

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_fZeroInt 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
_bLearnEvt := FALSE;                // 学习写入标志预清零
bStaticFlow := FALSE;               // 静流出口缺省 FALSE（段 4 单点重写）
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151；含除零口径） —— *)
IF (fStaticBandPa <= 0.0) OR (fStabRangePa <= 0.0) OR (fTrimMaxPa <= 0.0)
   OR (fLearnRate <= 0.0) OR (fLearnRate > 1.0)
   OR (TIME_TO_DINT(tZeroDwell) <= 0) THEN
    _bCfgBad := TRUE;               // 静流带/稳定阈/限幅/学习率/驻留域非法
END_IF

(* —— 段 3：故障锁存与迁出沿（R228-B：rtReset.Q 恒可达） —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0003_021B;        // 故障级：组态非法（仅首次进入时写入）
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT _bCfgBad) THEN
    _bFault := FALSE;               // 清故障锁存位（组态恢复合法为前提）
    _uFault := 16#0000_0000;
END_IF

(* —— 段 4：非有限防御与静流双判据 —— *)
_bRawBad := (fDpRawPa <> fDpRawPa) OR (ABS(fDpRawPa) > DL_ODZ_INF_CAP) OR ((fDpRawPa - fDpRawPa) <> 0.0);
IF _bRawBad THEN
    _fDpEff := _fDpLast;            // 非有限：保持上次有效值
    _uInfo := 16#0003_041B;         // 信息级：已保持
ELSE
    _fDpEff := fDpRawPa;            // 有效值入载体
    _fDpLast := fDpRawPa;
END_IF
_bStaticDb := (FC_DL_Deadband(fIn := _fDpEff,          // 归零型死区判静流带
                              fWidth := fStaticBandPa, // 带半宽
                              fCenter := 0.0,          // 零点中心
                              bZeroMode := TRUE) = 0.0);   // 归零型输出为 0 即在带内
IF (NOT _bRawBad) AND _bStaticDb AND fbStat.bValid AND (fbStat.fRange <= fStabRangePa) THEN
    _bStatic := TRUE;               // 双判据：带内 + 窗峰峰不超阈
ELSE
    _bStatic := FALSE;              // 任一判据不成立：非静流（TON 断输入即归零，R188）
END_IF
bStaticFlow := _bStatic;            // 静流出口镜像
tonZero(IN := _bStatic AND bEnable AND (NOT _bLearnBrk), PT := tZeroDwell);   // 静流驻留计时（顶层无条件调用；学习拍断输入一拍）
_bLearnBrk := FALSE;                // 断输入标志用后即清（R188 自复位纪律）

(* —— 段 5：零点学习（驻留到点 + 使能 + 组态合法） —— *)
IF tonZero.Q AND bEnable AND (NOT _bFault) THEN
    _fZeroInt := _fZeroInt + (fbMed.fMedian - _fZeroInt) * fLearnRate;   // 一阶趋近学习（中值抗毛刺）
    IF ABS(_fZeroInt) > fTrimMaxPa THEN
        _fZeroInt := MAX(-fTrimMaxPa, MIN(fTrimMaxPa, _fZeroInt));       // 限幅钳位
        _uInfo := 16#0003_051B;     // 信息级：学习值越限幅已钳制
    END_IF
    _bLearnEvt := TRUE;             // 本拍发生学习写入
    _bLearnBrk := TRUE;             // 学习拍断输入标志（下一拍复位驻留计时）
END_IF
IF rtZeroClr.Q THEN
    _fZeroInt := 0.0;               // 零点清零沿生效
END_IF
fZeroOffsetPa := _fZeroInt;         // 零点出口镜像
IF _bLearnEvt AND (NOT _bFault) THEN
    _uInfo := 16#0003_011B;         // 信息级：学习完成（覆盖限幅码优先级见两分支写入次序）
END_IF

(* —— 段 6：修正量出口（名实同源） —— *)
fDpCorrPa := _fDpEff - _fZeroInt;   // 修正 = 原始 − 零点（零点平移语义）
bTrimValid := (NOT _bFault) AND (NOT _bRawBad);   // 有效性 = 组态合法且输入有限

(* —— 段 7：事件码单点回放（故障锁存优先） —— *)
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放
    bError := TRUE;
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF

END_FUNCTION_BLOCK
