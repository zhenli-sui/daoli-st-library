(*
  FB_DL_CleaningBrushWear  —  清扫机器人刷辊磨损与换刷里程 / Cleaning-robot brush wear and replacement mileage
  分类 Category : DL_Device
  码位 Code     : 16#03_2_1A
  段位说明      : 03_2 段低半字节已满，1x 段续号，19 格由 ElMutingGantry 启用，本件启用 1A 格（R192）
  版本 Version  : 1.0.0
  来源 Source   : t2-6-rockwell-aoi — 三分类诊断结构借 T2-6 AOI 语义（里程类 / 电流类 / 组态类）
  溯源 Origin   : clean-room 实现，未复制任何源码行
                  （判据取「磨损累计」语义：里程累计 + 电流趋势窗双判据，非单件越限）
  功能 Function : 1) 里程类：FB_DL_EventCounter 累计里程脉冲 → 折算里程 fWearMeters，
                  达 fWearDistMaxM 判磨损（bWearDist 锁存）；
                  2) 电流类：FB_DL_SignalStatistics 电流趋势窗（均值口径），窗口均值 / 标称电流
                  比值达 fWearRatioMax 判磨损（bWearCur 锁存）；
                  3) 组态类：参数域非法判组态故障（bCfgFault 锁存）；
                  4) 换刷沿 bBrushReplaced：三件基准全量重置（计数 / 运行时长 / 统计窗），诊断归零；
                  5) 伴随量：FB_DL_RuntimeMeter 刷辊累计运行时长（保养随行台账）。
  边界 Boundary : ① 三分类诊断结构（里程 / 电流 / 组态）各有独立码值，归因唯一，禁共用枚举成员（R190）；
                  ② fMetersPerPulse <= 0 里程折算除零守卫：判组态类故障，折算出口置 0；
                  ③ fCurrentNomA <= 0 电流比值除零守卫：判组态类故障，比值出口置 0；
                  ④ 换刷沿用 R_TRIG 捕获后以单拍电平喂三件的复位/清零引脚（沿消费纪律）；
                  ⑤ 无状态机 CASE 主相（诊断型 FB）：故障经独立锁存位承载，无跨相 TON 复用问题。
  依赖 Depends  : FB_DL_EventCounter / FB_DL_RuntimeMeter / FB_DL_SignalStatistics（实例化，引脚按 registry 实名）
  码表 Error codes（本件格 03_2_1A，子码步进 +0x100）:
    16#0003_011A 信息级：换刷重置完成（基准全量归零）
    16#0003_021A 故障级：组态类故障（里程折算系数 / 标称电流 / 阈值 / 窗长域非法），锁存至复位
    16#0003_031A 故障级：里程类磨损（累计里程达阈值），锁存至复位或换刷沿
    16#0003_041A 故障级：电流类磨损（趋势窗均值/标称比达阈值），锁存至复位或换刷沿
    16#0003_051A 信息级：统计窗未满（电流判据尚未生效，bCurReady = FALSE）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 3 · 序号 12）
*)

TYPE E_DL_BrushDiag :
(
    eNone    := 0,    // 无诊断结论 / No diagnosis
    eConfig  := 10,   // 组态类 / Configuration class
    eMileage := 20,   // 里程类 / Mileage class
    eCurrent := 30,   // 电流类 / Current class
    eBoth    := 40    // 里程 + 电流双判 / Both mileage and current
);
END_TYPE

FUNCTION_BLOCK FB_DL_CleaningBrushWear
VAR_INPUT
    bBrushRun      : BOOL := FALSE;      // 刷辊运行反馈（电平）[-] / Brush running feedback, level
    bDistPulse     : BOOL := FALSE;      // 里程脉冲（上升沿有效）[-] / Mileage pulse, rising edge
    fMetersPerPulse: REAL := 0.01;       // 每脉冲折算里程 [m/脉冲]，域 > 0 / Meters per pulse, must exceed zero
    fCurrentNomA   : REAL := 2.0;        // 刷辊电机标称电流 [A]，域 > 0 / Nominal motor current
    fMotorCurrentA : REAL := 0.0;        // 刷辊电机实测电流 [A] / Measured motor current
    fWearDistMaxM  : REAL := 50000.0;    // 换刷里程阈值 [m]，域 > 0 / Replacement mileage threshold
    fWearRatioMax  : REAL := 1.3;        // 电流磨损比值阈值 [无量纲]，域 > 1 / Current wear ratio threshold
    nStatWindow    : INT  := 32;         // 电流统计窗长 [个]，2..64（越界钳位）/ Current statistics window length
    bBrushReplaced : BOOL := FALSE;      // 换刷指令沿，上升沿重置三件基准 / Brush replaced, rising edge resets baselines
    uDeltaTimeMs   : UDINT := 10;        // 任务周期注入 [ms]（运行时长折算用）/ Task cycle time for runtime meter
    bReset         : BOOL := FALSE;      // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    fWearMeters : REAL;                   // 累计磨损里程 [m] / Accumulated wear mileage
    fCurMeanA   : REAL;                   // 电流趋势窗均值 [A] / Current window mean
    fCurRatio   : REAL;                   // 电流比值 = 窗均值 / 标称 [无量纲] / Current ratio mean over nominal
    uRunMinutes : UDINT;                  // 刷辊累计运行时长 [min] / Brush accumulated runtime
    bCurReady   : BOOL;                   // 电流判据生效（统计窗已满）[-] / Current criterion ready, window full
    bWearDist   : BOOL;                   // 里程类磨损锁存 [-] / Mileage wear latch
    bWearCur    : BOOL;                   // 电流类磨损锁存 [-] / Current wear latch
    bCfgFault   : BOOL;                   // 组态类故障锁存 [-] / Configuration fault latch
    eDiag       : E_DL_BrushDiag;         // 三分类诊断出口 / Three-class diagnosis outlet
    bReplaceReq : BOOL;                   // 换刷请求（任一磨损锁存）[-] / Replacement request, any wear latch
    bError      : BOOL;                   // 故障聚合位（任一故障锁存）[-] / Aggregate fault flag
    uErrorId    : UDINT;                  // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR
    fbDist    : FB_DL_EventCounter;       // 里程脉冲计数实例（主体首部无条件刷新）/ Mileage pulse counter instance
    fbRun     : FB_DL_RuntimeMeter;       // 刷辊运行时长实例（主体首部无条件刷新）/ Brush runtime meter instance
    fbCur     : FB_DL_SignalStatistics;   // 电流趋势统计窗实例（主体首部无条件刷新）/ Current statistics window instance
    rtPulse   : R_TRIG;                   // 里程脉冲上升沿 / Mileage pulse rising edge
    rtReplaced: R_TRIG;                   // 换刷指令上升沿 / Brush replaced rising edge
    rtReset   : R_TRIG;                   // 故障复位上升沿 / Fault reset rising edge
    _rWearM   : REAL;                     // 里程折算中间量 [m] / Mileage conversion working value
    _rRatio   : REAL;                     // 电流比值中间量 [无量纲] / Current ratio working value
    _uPulseTh : DINT;                     // 里程阈值换算脉冲数 [个] / Mileage threshold in pulse count
    _bInit    : BOOL := FALSE;            // 首扫标志，初值 FALSE，判据 NOT bInit（R19 范式）/ First-scan flag
    _bFault   : BOOL;                     // 故障锁存位 / Latched fault bit
    _uFault   : UDINT;                    // 故障码锁存寄存 / Latched fault code register
    _uInfo    : UDINT;                    // 信息码，每拍重算 / Info code
    _bCfgBad  : BOOL;                     // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_CBW_INF_CAP  : REAL := 1.0E15;        // 非有限值筛查幅值上限 / Non-finite screening cap
    DL_CBW_RATIO_MIN: REAL := 1.0001;        // 电流比值阈值下限（须大于 1，防阈值=1 误判） / Ratio threshold lower bound
END_VAR

(* —— 段 0：依赖件与边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtPulse(CLK := bDistPulse);                                 // 里程脉冲沿刷新，每拍必调
rtReplaced(CLK := bBrushReplaced);                          // 换刷沿刷新，每拍必调
rtReset(CLK := bReset);                                     // 复位沿刷新，每拍必调
fbDist(bCntUp := rtPulse.Q,                                 // 里程脉冲计数
       bCntDown := FALSE,                                   // 无递减
       bLoad := FALSE,                                      // 无装载
       nPreset := 0,                                        // 装载值（未用）
       bWrap := FALSE,                                      // 饱和口径
       nCompHigh := _uPulseTh,                              // 高阈值 = 里程阈值换算脉冲数
       nCompLow := 0,                                       // 低阈值（未用）
       bReset := rtReplaced.Q);                             // 换刷沿单拍喂复位（沿消费纪律）
fbRun(bRunning := bBrushRun,                                // 刷辊运行时长累计
      uDeltaTimeMs := uDeltaTimeMs,                         // 任务周期注入
      uMaintIntervalMin := UDINT#0,                         // 保养预警关闭（由上层另行组态）
      bMaintAck := FALSE,                                   // 无保养确认
      bReset := rtReplaced.Q);                              // 换刷沿单拍清零
fbCur(fIn := fMotorCurrentA,                                // 电流趋势窗采样
      bSample := bBrushRun,                                 // 仅运行时采样（停机电流不入窗）
      nWindow := nStatWindow,                               // 窗长（组态透传，内部钳位）
      bClear := rtReplaced.Q);                              // 换刷沿单拍清窗

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/bWearDist/bWearCur/bCfgFault 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
bReplaceReq := FALSE;               // 换刷请求缺省 FALSE（段 6 单点重写）
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151；含除零守卫） —— *)
IF (fMetersPerPulse <= 0.0) OR (ABS(fMetersPerPulse) > DL_CBW_INF_CAP)
   OR (fCurrentNomA <= 0.0) OR (ABS(fCurrentNomA) > DL_CBW_INF_CAP) THEN
    _bCfgBad := TRUE;               // 折算系数/标称电流非法（除零守卫命中）
END_IF
IF (fMotorCurrentA <> fMotorCurrentA) OR (ABS(fMotorCurrentA) > DL_CBW_INF_CAP) OR ((fMotorCurrentA - fMotorCurrentA) <> 0.0) THEN
    _bCfgBad := TRUE;               // 实测电流非有限
END_IF
IF (fWearDistMaxM <= 0.0) OR (fWearRatioMax < DL_CBW_RATIO_MIN) OR (nStatWindow < 2) OR (nStatWindow > 64) THEN
    _bCfgBad := TRUE;               // 阈值/窗长域非法
END_IF

(* —— 段 3：组态类故障锁存与解除（R228-B：rtReset.Q 为输入引脚恒可达） —— *)
IF _bCfgBad THEN
    bCfgFault := TRUE;              // 组态类锁存（独立归因，禁并入磨损类）
    IF NOT _bFault THEN
        _uFault := 16#0003_021A;    // 故障级：组态类（仅首次进入时写入）
        _bFault := TRUE;
    END_IF
END_IF
IF rtReset.Q THEN
    _bFault := FALSE;               // 清聚合故障位
    _uFault := 16#0000_0000;
    bCfgFault := FALSE;             // 组态类解除（重置后由段 2 复判）
END_IF

(* —— 段 4：首扫基准与里程阈值换算（分母已闸 > 0） —— *)
IF NOT _bInit THEN
    _uPulseTh := REAL_TO_DINT(fWearDistMaxM / fMetersPerPulse);   // 里程阈值换算脉冲数（分母已闸）
    IF _uPulseTh < 1 THEN
        _uPulseTh := 1;             // 换算下限兜底（防阈值过小永不比较）
    END_IF
    _bInit := TRUE;
END_IF
IF (fMetersPerPulse > 0.0) AND (NOT bCfgFault) THEN
    _rWearM := DINT_TO_REAL(fbDist.nCount) * fMetersPerPulse;   // 里程折算（分母已闸；计数域内标准转换）
ELSE
    _rWearM := 0.0;                 // 组态故障：折算出口置 0（防御口径）
END_IF
fWearMeters := _rWearM;             // 里程出口镜像

(* —— 段 5：电流判据换算（分母已闸；窗未满只给信息级） —— *)
fCurMeanA := fbCur.fMean;           // 窗均值出口镜像
bCurReady := fbCur.bStatValid;      // 方差/统计有效口径（n >= 2）作为判据生效标志
IF (fCurrentNomA > 0.0) AND (NOT bCfgFault) THEN
    _rRatio := fCurMeanA / fCurrentNomA;      // 电流比值（分母已闸）
ELSE
    _rRatio := 0.0;                 // 组态故障：比值出口置 0（防御口径）
END_IF
fCurRatio := _rRatio;               // 比值出口镜像
IF bCurReady AND (NOT bCfgFault) THEN
    IF _rWearM >= fWearDistMaxM THEN
        bWearDist := TRUE;          // 里程类磨损锁存
    END_IF
    IF _rRatio >= fWearRatioMax THEN
        bWearCur := TRUE;           // 电流类磨损锁存
    END_IF
ELSE
    _uInfo := 16#0003_051A;         // 信息级：判据未生效（窗未满或组态故障）
END_IF
IF (bWearDist OR bWearCur) AND (NOT _bFault) THEN
    IF bWearDist AND bWearCur THEN
        _uFault := 16#0003_041A;    // 双判同锁：电流类码承载（里程类独立位 bWearDist 仍可观测，归因不混叠）
    ELSIF bWearDist THEN
        _uFault := 16#0003_031A;    // 里程类磨损
    ELSE
        _uFault := 16#0003_041A;    // 电流类磨损
    END_IF
    _bFault := TRUE;
END_IF
IF rtReplaced.Q THEN
    bWearDist := FALSE;             // 换刷沿：里程类解除
    bWearCur := FALSE;              // 换刷沿：电流类解除
    _uInfo := 16#0003_011A;         // 信息级：换刷重置完成
END_IF

(* —— 段 6：诊断聚合出口（名实同源） —— *)
uRunMinutes := fbRun.uRunTotalMin;  // 运行时长出口镜像
IF bCfgFault THEN
    eDiag := E_DL_BrushDiag.eConfig;            // 组态类优先归因
ELSIF bWearDist AND bWearCur THEN
    eDiag := E_DL_BrushDiag.eBoth;              // 双判
ELSIF bWearDist THEN
    eDiag := E_DL_BrushDiag.eMileage;           // 里程类
ELSIF bWearCur THEN
    eDiag := E_DL_BrushDiag.eCurrent;           // 电流类
ELSE
    eDiag := E_DL_BrushDiag.eNone;              // 无结论
END_IF
bReplaceReq := bWearDist OR bWearCur;           // 换刷请求 = 任一磨损锁存
bError := bCfgFault OR bWearDist OR bWearCur;   // 故障聚合位
IF bError THEN
    uErrorId := _uFault;            // 故障锁存码回放
ELSE
    uErrorId := _uInfo;             // 信息码
END_IF

END_FUNCTION_BLOCK
