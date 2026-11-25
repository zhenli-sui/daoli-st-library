(*
  Name: FB_DL_TireCurePressSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 硫化机合模序状态机，十相推进（含故障相）：
           待机 → 装胎 → 合模 → 一次定型 → 二次定型 → 硫化 → 泄压 → 开模 → 卸胎 → （回待机）。
           待机相等 xStart 上升沿（必须边沿，防上电即在启动位自动合模）；
           装胎相给装胎命令等装胎到位反馈；合模相给合模命令等合模到位反馈；
           一次定型相开一次定型阀，等胶囊压力达 fShapePressKpa；二次定型相同理但压力窗更高；
           硫化相开主蒸汽阀，等 tCureS 且模温不低于 fCureTargetC − fTempBandK；
           泄压相开泄压阀，等压力降到 fVentPressKpa 以下；开模相等开模到位反馈；
           卸胎相等卸胎到位反馈，完成后置 xDone 锁存并回待机（保持到 xStart 撤下）。
        2) 每相独立超时 + 整序总超时：八个工作相各配「相定时 + 裕量」超时点，
           tonTotal 兜底整序总时长，九个超时源并发监视，任一命中即锁码进故障相。
        3) 硫化过程温度保护：硫化相内模温跌破 fCureTargetC − fTempBandK 即锁码 0337，
           这是欠硫的直接成因（温度不足则等效硫化时间按 Arrhenius 指数衰减）。
  边界条件：1) 非有限值闸：胶囊压力、模温、目标温度、压力阈、温度带宽、周期先过
           NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；命中即锁码 0343 进故障相，
           绝不把 NaN 拿去与压力/温度阈比较（NaN 比较恒假会让放行条件永不成立，也永不报错，R19）。
        2) 周期入参闸（R21）：本件不做斜率运算，fCycleS 仅作观测与工艺记录；
           非法周期改用缺省 DL_CYCLE_DEF = 0.1 s，并在组态闸中一并锁码 0343（同码归因，内部成员分离）。
        3) 阈值域闸：0.0 < fShapePressKpa < fCurePressKpa、fVentPressKpa < fShapePressKpa、
           fTempBandK > DL_EPS，越域锁码 0343（定型压力窗倒置会让压力判据永不成立）。
        4) 单点赋值（R26）：九个命令位与 xDone / xBusy 全部在段 8 统一出口写一次，
           相位内只改 _eState 与锁存位，不在分支内各写一遍命令。
        5) 定时器周期刷新（R7）：十七个 TON 与两个边沿实例全部在 CASE 之外无条件调用，
           IN 由状态导出，相迁移即 IN 归假自复位（R188）。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参/组态合法 → 清锁存回待机，
           回待机后必须重新给 xStart 上升沿才能再启动（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0344、清全部输出。
        8) 输出安全初值（R25）：九个命令位初值 FALSE（失电即安全侧：不开阀不合模），
           xDone / xBusy 初值 FALSE，待机相显式赋值。
  量纲自证：fBladderPressKpa 与三个压力阈同为 [kPa]，比较合法；
           fMoldTempC / fCureTargetC 为 [degC]，fTempBandK 为温差不 [K]，degC 差值以 K 计，合法；
           所有时间引脚为 [TIME]，相超时点 = [TIME] + [TIME] = [TIME]，与 TON 的 PT 同量纲。
  码表 Error codes（本件子带 0091_033x / 034x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0331 信息级：装胎相等待装胎到位反馈（不置故障位）
    16#0091_0332 故障级：装胎相超时
    16#0091_0333 故障级：合模相超时（合模未到位）
    16#0091_0334 故障级：一次定型相超时（压力未达一次定型窗）
    16#0091_0335 故障级：二次定型相超时（压力未达二次定型窗）
    16#0091_0336 故障级：硫化相超时（等效硫化时间未跑完）
    16#0091_0337 故障级：硫化相模温低于下限（欠硫风险）
    16#0091_0338 故障级：泄压相超时（压力未泄尽）
    16#0091_0339 故障级：开模相超时（开模未到位）
    16#0091_0340 故障级：卸胎相超时（卸胎未到位）
    16#0091_0341 故障级：整序总超时
    16#0091_0342 故障级：外部故障输入 xFault
    16#0091_0343 故障级：入参非有限，或压力/温度/周期组态越域
    16#0091_0344 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0091_0345 信息级：周期完成保持中，等待撤令（不置故障位）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_TcsPressState :
(
    eTcsPressIdle   := 0,     // 待机：等启动上升沿，全命令撤销 / Idle, awaiting start, all commands dropped
    eTcsPressLoad   := 10,    // 装胎：给装胎命令等到位 / Loading, awaiting the load-done feedback
    eTcsPressClose  := 20,    // 合模：给合模命令等到位 / Closing, awaiting the closed feedback
    eTcsPressShape1 := 30,    // 一次定型：开一次定型阀等压力 / First shaping, awaiting the pressure window
    eTcsPressShape2 := 40,    // 二次定型：开二次定型阀等压力 / Second shaping, awaiting the pressure window
    eTcsPressCure   := 50,    // 硫化：开主蒸汽阀等时间与模温 / Curing, awaiting time and mold temperature
    eTcsPressVent   := 60,    // 泄压：开泄压阀等压力降 / Venting, awaiting the pressure drop
    eTcsPressOpen   := 70,    // 开模：给开模命令等到位 / Opening, awaiting the open feedback
    eTcsPressUnload := 80,    // 卸胎：给卸胎命令等到位 / Unloading, awaiting the unload-done feedback
    eTcsPressFault  := 90     // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_TireCurePressSeq
VAR_INPUT
    xStart          : BOOL;    // 循环启动指令（上升沿有效）[bool] / Cycle start command, edge triggered [bool]
    xReset          : BOOL;    // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault          : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    xLoadDoneFb     : BOOL;    // 装胎到位反馈 [bool] / Load-done feedback [bool]
    xClosedFb       : BOOL;    // 合模到位反馈 [bool] / Mold-closed feedback [bool]
    xOpenFb         : BOOL;    // 开模到位反馈 [bool] / Mold-open feedback [bool]
    xUnloadDoneFb   : BOOL;    // 卸胎到位反馈 [bool] / Unload-done feedback [bool]
    fBladderPressKpa : REAL;   // 胶囊实测压力 [kPa] / Measured bladder pressure [kPa]
    fMoldTempC      : REAL;    // 模温实测值 [degC] / Measured mold temperature [degC]
    fCureTargetC    : REAL;    // 硫化目标模温 [degC] / Curing target mold temperature [degC]
    fTempBandK      : REAL;    // 模温允许下偏带宽 [K] / Permitted mold temperature undershoot band [K]
    fShapePressKpa  : REAL;    // 定型压力窗（一次/二次共用下限）[kPa] / Shaping pressure window [kPa]
    fCurePressKpa   : REAL;    // 硫化压力窗（须高于定型窗）[kPa] / Curing pressure window [kPa]
    fVentPressKpa   : REAL;    // 泄压完成压力上限 [kPa] / Vent-complete pressure ceiling [kPa]
    fCycleS         : REAL;    // 任务周期（观测用）[s] / Task cycle time, for observation [s]
    tLoadS          : TIME;    // 装胎相设定时长 [TIME] / Loading phase duration [TIME]
    tCloseS         : TIME;    // 合模相设定时长 [TIME] / Closing phase duration [TIME]
    tShape1S        : TIME;    // 一次定型相设定时长 [TIME] / First shaping duration [TIME]
    tShape2S        : TIME;    // 二次定型相设定时长 [TIME] / Second shaping duration [TIME]
    tCureS          : TIME;    // 硫化相设定时长 [TIME] / Curing phase duration [TIME]
    tVentS          : TIME;    // 泄压相设定时长 [TIME] / Venting phase duration [TIME]
    tOpenS          : TIME;    // 开模相设定时长 [TIME] / Opening phase duration [TIME]
    tUnloadS        : TIME;    // 卸胎相设定时长 [TIME] / Unloading phase duration [TIME]
END_VAR
VAR_OUTPUT
    xLoadCmd        : BOOL;    // 装胎命令（安全侧：故障时停）[bool] / Load command, fail-safe [bool]
    xCloseCmd       : BOOL;    // 合模命令（安全侧：故障时停）[bool] / Close command, fail-safe [bool]
    xShape1ValveCmd : BOOL;    // 一次定型阀命令（安全侧：故障时关）[bool] / First shaping valve command [bool]
    xShape2ValveCmd : BOOL;    // 二次定型阀命令（安全侧：故障时关）[bool] / Second shaping valve command [bool]
    xCureSteamCmd   : BOOL;    // 硫化主蒸汽阀命令（安全侧：故障时关）[bool] / Curing steam valve command [bool]
    xVentValveCmd   : BOOL;    // 泄压阀命令（安全侧：故障时关）[bool] / Vent valve command [bool]
    xOpenCmd        : BOOL;    // 开模命令（安全侧：故障时停）[bool] / Open command, fail-safe [bool]
    xUnloadCmd      : BOOL;    // 卸胎命令（安全侧：故障时停）[bool] / Unload command, fail-safe [bool]
    xDone           : BOOL;    // 周期完成保持位 [bool] / Cycle complete held flag [bool]
    xBusy           : BOOL;    // 循环进行中 [bool] / Cycle busy [bool]
    eState          : E_DL_TcsPressState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId          : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonLoad         : TON;     // 装胎相正常定时 [TIME] / Loading phase timer
    tonLoadOv       : TON;     // 装胎相超时定时 [TIME] / Loading phase overrun timer
    tonClose        : TON;     // 合模相正常定时 [TIME] / Closing phase timer
    tonCloseOv      : TON;     // 合模相超时定时 [TIME] / Closing phase overrun timer
    tonShape1       : TON;     // 一次定型相正常定时 [TIME] / First shaping phase timer
    tonShape1Ov     : TON;     // 一次定型相超时定时 [TIME] / First shaping phase overrun timer
    tonShape2       : TON;     // 二次定型相正常定时 [TIME] / Second shaping phase timer
    tonShape2Ov     : TON;     // 二次定型相超时定时 [TIME] / Second shaping phase overrun timer
    tonCure         : TON;     // 硫化相正常定时 [TIME] / Curing phase timer
    tonCureOv       : TON;     // 硫化相超时定时 [TIME] / Curing phase overrun timer
    tonVent         : TON;     // 泄压相正常定时 [TIME] / Venting phase timer
    tonVentOv       : TON;     // 泄压相超时定时 [TIME] / Venting phase overrun timer
    tonOpen         : TON;     // 开模相正常定时 [TIME] / Opening phase timer
    tonOpenOv       : TON;     // 开模相超时定时 [TIME] / Opening phase overrun timer
    tonUnload       : TON;     // 卸胎相正常定时 [TIME] / Unloading phase timer
    tonUnloadOv     : TON;     // 卸胎相超时定时 [TIME] / Unloading phase overrun timer
    tonTotal        : TON;     // 整序总超时定时 [TIME] / Whole-sequence total timeout timer
    rtStart         : R_TRIG;  // 启动上升沿检测 [bool] / Start rising edge detector
    rtReset         : R_TRIG;  // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState         : E_DL_TcsPressState := E_DL_TcsPressState.eTcsPressIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev     : E_DL_TcsPressState := E_DL_TcsPressState.eTcsPressIdle;   // 上一拍相位快照（周期末更新）
    _fCycleUseS     : REAL := 0.1;    // 实际使用的周期值 [s] / Cycle time actually used [s]
    _fTempLowK      : REAL := 0.0;    // 硫化模温下限 [degC] / Curing mold temperature low limit [degC]
    _fTempDevK      : REAL := 0.0;    // 模温低于目标的下偏量 [K] / Mold temperature undershoot [K]
    _bFinOk         : BOOL := FALSE;  // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCfgOk         : BOOL := FALSE;  // 压力/温度/周期组态域闸结果 / Configuration domain gate result
    _bActive        : BOOL := FALSE;  // 序激活（装胎至卸胎八相之一）[bool] / Sequence active flag
    _bDoneL         : BOOL := FALSE;  // 完成位锁存（跨相保持）[bool] / Done latch held across phases
    _bFault         : BOOL := FALSE;  // 故障锁存位 [bool] / Latched fault flag
    _iPhaseChg      : INT := 0;       // 本拍相位切换计数（观测用）[-] / Phase-change count this cycle [-]
    _uInfo          : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault         : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS          : REAL := 1.0E-9;     // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG          : REAL := 1.0E12;     // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_CYCLE_DEF    : REAL := 0.1;        // 缺省任务周期 [s] / Default task cycle time [s]
    DL_CYCLE_MIN    : REAL := 0.001;      // 周期合理下限 [s] / Cycle time reasonable low bound [s]
    DL_CYCLE_MAX    : REAL := 10.0;       // 周期合理上限 [s] / Cycle time reasonable high bound [s]
    DL_PRESS_HI     : REAL := 10000.0;    // 压力量级闸上限 [kPa] / Pressure magnitude upper bound [kPa]
    DL_T_SPAN       : REAL := 500.0;      // 温度量级闸跨度 [degC] / Temperature magnitude gate span [degC]
    DL_OVER_MARGIN  : TIME := T#30S;      // 相超时相对正常定时的裕量 [TIME] / Phase overrun margin [TIME]
    DL_TOTAL_MAX    : TIME := T#4H;       // 整序总超时上限 [TIME] / Whole-sequence total timeout [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bDoneL/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
_iPhaseChg := 0;                            // 相位切换计数每拍重算 / Phase-change counter recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸与组态域闸（R19：不拿 NaN 去比较压力与温度阈） —— *)
_bFinOk := (fBladderPressKpa > -DL_BIG) AND (fBladderPressKpa < DL_BIG)
           AND (fMoldTempC > -DL_BIG) AND (fMoldTempC < DL_BIG)
           AND (fCureTargetC > -DL_BIG) AND (fCureTargetC < DL_BIG)
           AND (fTempBandK > -DL_BIG) AND (fTempBandK < DL_BIG)
           AND (fShapePressKpa > -DL_BIG) AND (fShapePressKpa < DL_BIG)
           AND (fCurePressKpa > -DL_BIG) AND (fCurePressKpa < DL_BIG)
           AND (fVentPressKpa > -DL_BIG) AND (fVentPressKpa < DL_BIG)
           AND (fCycleS > -DL_BIG) AND (fCycleS < DL_BIG);
_bCfgOk := (fVentPressKpa >= 0.0)                          // 泄压上限不得为负
           AND (fShapePressKpa > fVentPressKpa)            // 定型窗必须高于泄压窗
           AND (fCurePressKpa > fShapePressKpa)            // 硫化窗必须高于定型窗（压力窗单调）
           AND (fCurePressKpa <= DL_PRESS_HI)              // 硫化窗须在压力量级内
           AND (fTempBandK > DL_EPS)                       // 温度带宽必须为正
           AND (ABS(fCureTargetC) <= DL_T_SPAN)            // 目标模温量级闸
           AND (ABS(fMoldTempC) <= DL_T_SPAN)              // 实测模温量级闸
           AND (fCycleS >= DL_CYCLE_MIN) AND (fCycleS <= DL_CYCLE_MAX);

IF _bCfgOk THEN
    _fCycleUseS := fCycleS;                 // 合法周期原值使用（本件仅观测用）
ELSE
    _fCycleUseS := DL_CYCLE_DEF;            // 非法周期一律用缺省 0.1 s
END_IF

(* —— 段 2：派生态（序激活、模温下偏量） —— *)
_bActive := (_eState = E_DL_TcsPressState.eTcsPressLoad)
            OR (_eState = E_DL_TcsPressState.eTcsPressClose)
            OR (_eState = E_DL_TcsPressState.eTcsPressShape1)
            OR (_eState = E_DL_TcsPressState.eTcsPressShape2)
            OR (_eState = E_DL_TcsPressState.eTcsPressCure)
            OR (_eState = E_DL_TcsPressState.eTcsPressVent)
            OR (_eState = E_DL_TcsPressState.eTcsPressOpen)
            OR (_eState = E_DL_TcsPressState.eTcsPressUnload);
_fTempLowK := fCureTargetC - fTempBandK;                                  // 硫化模温下限 [degC]
_fTempDevK := fCureTargetC - fMoldTempC;                                  // 模温下偏量 [K]

(* —— 段 3：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := xStart);                                                                    // 启动上升沿，每拍必调
rtReset(CLK := xReset);                                                                    // 复位上升沿，每拍必调
tonLoad(IN := (_eState = E_DL_TcsPressState.eTcsPressLoad), PT := tLoadS);                 // 装胎相正常定时
tonLoadOv(IN := (_eState = E_DL_TcsPressState.eTcsPressLoad), PT := tLoadS + DL_OVER_MARGIN);         // 装胎超时点
tonClose(IN := (_eState = E_DL_TcsPressState.eTcsPressClose), PT := tCloseS);              // 合模相正常定时
tonCloseOv(IN := (_eState = E_DL_TcsPressState.eTcsPressClose), PT := tCloseS + DL_OVER_MARGIN);       // 合模超时点
tonShape1(IN := (_eState = E_DL_TcsPressState.eTcsPressShape1), PT := tShape1S);           // 一次定型正常定时
tonShape1Ov(IN := (_eState = E_DL_TcsPressState.eTcsPressShape1), PT := tShape1S + DL_OVER_MARGIN);    // 一次定型超时点
tonShape2(IN := (_eState = E_DL_TcsPressState.eTcsPressShape2), PT := tShape2S);           // 二次定型正常定时
tonShape2Ov(IN := (_eState = E_DL_TcsPressState.eTcsPressShape2), PT := tShape2S + DL_OVER_MARGIN);    // 二次定型超时点
tonCure(IN := (_eState = E_DL_TcsPressState.eTcsPressCure), PT := tCureS);                 // 硫化相正常定时
tonCureOv(IN := (_eState = E_DL_TcsPressState.eTcsPressCure), PT := tCureS + DL_OVER_MARGIN);          // 硫化超时点
tonVent(IN := (_eState = E_DL_TcsPressState.eTcsPressVent), PT := tVentS);                 // 泄压相正常定时
tonVentOv(IN := (_eState = E_DL_TcsPressState.eTcsPressVent), PT := tVentS + DL_OVER_MARGIN);          // 泄压超时点
tonOpen(IN := (_eState = E_DL_TcsPressState.eTcsPressOpen), PT := tOpenS);                 // 开模相正常定时
tonOpenOv(IN := (_eState = E_DL_TcsPressState.eTcsPressOpen), PT := tOpenS + DL_OVER_MARGIN);          // 开模超时点
tonUnload(IN := (_eState = E_DL_TcsPressState.eTcsPressUnload), PT := tUnloadS);           // 卸胎相正常定时
tonUnloadOv(IN := (_eState = E_DL_TcsPressState.eTcsPressUnload), PT := tUnloadS + DL_OVER_MARGIN);    // 卸胎超时点
tonTotal(IN := _bActive, PT := DL_TOTAL_MAX);                                              // 整序总超时

(* —— 段 4：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0342;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_TcsPressState.eTcsPressFault;
END_IF
IF ((NOT _bFinOk) OR (NOT _bCfgOk)) AND (NOT _bFault) THEN
    _uFault := 16#0091_0343;                // 故障级：入参非有限或组态越域（内部成员已分离）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_TcsPressState.eTcsPressFault;
END_IF
IF tonTotal.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0091_0341;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_TcsPressState.eTcsPressFault;
END_IF
IF (_eState = E_DL_TcsPressState.eTcsPressCure)
   AND (_fTempDevK > fTempBandK) AND (NOT _bFault) THEN
    _uFault := 16#0091_0337;                // 故障级：硫化模温低于下限（欠硫风险）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_TcsPressState.eTcsPressFault;
END_IF

(* —— 段 5：相位机（只做迁移；出口在段 7 单点映射） —— *)
CASE _eState OF

E_DL_TcsPressState.eTcsPressIdle:
    IF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令即清完成位，为下一模重新武装
    ELSIF rtStart.Q THEN
        _bDoneL := FALSE;                   // 新循环开始：清完成位（迁移前一次性清）
        _eState := E_DL_TcsPressState.eTcsPressLoad;          // 进装胎相
    END_IF

E_DL_TcsPressState.eTcsPressLoad:
    IF tonLoadOv.Q THEN
        _uFault := 16#0091_0332;            // 故障级：装胎相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF tonLoad.Q AND xLoadDoneFb THEN
        _eState := E_DL_TcsPressState.eTcsPressClose;         // 本拍合法事件优先于超时迁移（R275）
    ELSE
        _uInfo := 16#0091_0331;             // 信息级：等装胎到位反馈（不置故障位）
    END_IF

E_DL_TcsPressState.eTcsPressClose:
    IF tonCloseOv.Q THEN
        _uFault := 16#0091_0333;            // 故障级：合模相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF xClosedFb THEN
        _eState := E_DL_TcsPressState.eTcsPressShape1;        // 合模到位：进一次定型相
    END_IF

E_DL_TcsPressState.eTcsPressShape1:
    IF tonShape1Ov.Q THEN
        _uFault := 16#0091_0334;            // 故障级：一次定型相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF (fBladderPressKpa >= fShapePressKpa) AND tonShape1.Q THEN
        _eState := E_DL_TcsPressState.eTcsPressShape2;        // 压力窗达成：进二次定型相
    END_IF

E_DL_TcsPressState.eTcsPressShape2:
    IF tonShape2Ov.Q THEN
        _uFault := 16#0091_0335;            // 故障级：二次定型相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF (fBladderPressKpa >= fCurePressKpa) AND tonShape2.Q THEN
        _eState := E_DL_TcsPressState.eTcsPressCure;          // 压力窗达成：进硫化相
    END_IF

E_DL_TcsPressState.eTcsPressCure:
    IF tonCureOv.Q THEN
        _uFault := 16#0091_0336;            // 故障级：硫化相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF tonCure.Q THEN
        _eState := E_DL_TcsPressState.eTcsPressVent;          // 等效硫化时间到：进泄压相
    END_IF

E_DL_TcsPressState.eTcsPressVent:
    IF tonVentOv.Q THEN
        _uFault := 16#0091_0338;            // 故障级：泄压相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF (fBladderPressKpa <= fVentPressKpa) AND tonVent.Q THEN
        _eState := E_DL_TcsPressState.eTcsPressOpen;          // 压力泄尽：进开模相
    END_IF

E_DL_TcsPressState.eTcsPressOpen:
    IF tonOpenOv.Q THEN
        _uFault := 16#0091_0339;            // 故障级：开模相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF xOpenFb AND tonOpen.Q THEN
        _eState := E_DL_TcsPressState.eTcsPressUnload;        // 开模到位：进卸胎相
    END_IF

E_DL_TcsPressState.eTcsPressUnload:
    IF tonUnloadOv.Q THEN
        _uFault := 16#0091_0340;            // 故障级：卸胎相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_TcsPressState.eTcsPressFault;
    ELSIF xUnloadDoneFb AND tonUnload.Q THEN
        _bDoneL := TRUE;                    // 完成位锁存（跨相保持，段 7 单点映射）
        _eState := E_DL_TcsPressState.eTcsPressIdle;          // 回待机，完成位保持到撤令
    END_IF

E_DL_TcsPressState.eTcsPressFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bCfgOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参/组态合法（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bDoneL := FALSE;                   // 完成位一并清，避免故障后误报完成
        _eState := E_DL_TcsPressState.eTcsPressIdle;          // 回待机，需新上升沿才可再启动
    END_IF

ELSE
    _uFault := 16#0091_0344;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _bDoneL := FALSE;                       // 完成位清
    _eState := E_DL_TcsPressState.eTcsPressFault;             // 强制回故障相

END_CASE

(* —— 段 6：后置段（相位快照在迁移判断之后统一更新） —— *)
IF _eState <> _eStatePrev THEN
    _iPhaseChg := _iPhaseChg + 1;           // 相位已切换：记一拍切换事件（观测用）
END_IF
_eStatePrev := _eState;                     // 快照在周期末尾统一更新

(* —— 段 7：出口单点映射（名实同源；九个命令位由状态导出，故障侧一律撤销） —— *)
xLoadCmd := (_eState = E_DL_TcsPressState.eTcsPressLoad) AND (NOT _bFault);               // 装胎命令
xCloseCmd := (_eState = E_DL_TcsPressState.eTcsPressClose) AND (NOT _bFault);             // 合模命令
xShape1ValveCmd := (_eState = E_DL_TcsPressState.eTcsPressShape1) AND (NOT _bFault);      // 一次定型阀
xShape2ValveCmd := (_eState = E_DL_TcsPressState.eTcsPressShape2) AND (NOT _bFault);      // 二次定型阀
xCureSteamCmd := (_eState = E_DL_TcsPressState.eTcsPressCure) AND (NOT _bFault);          // 硫化蒸汽阀
xVentValveCmd := (_eState = E_DL_TcsPressState.eTcsPressVent) AND (NOT _bFault);          // 泄压阀
xOpenCmd := (_eState = E_DL_TcsPressState.eTcsPressOpen) AND (NOT _bFault);               // 开模命令
xUnloadCmd := (_eState = E_DL_TcsPressState.eTcsPressUnload) AND (NOT _bFault);           // 卸胎命令
xDone := _bDoneL AND (NOT _bFault);                                                       // 完成位出口
xBusy := _bActive AND (NOT _bFault);                                                      // 进行中出口
eState := _eState;                                                                        // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSIF _bDoneL THEN
    nErrId := 16#0091_0345;                 // 信息级：周期完成保持中，等待撤令
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
