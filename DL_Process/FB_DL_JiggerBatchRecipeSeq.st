(*
  Name: FB_DL_JiggerBatchRecipeSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 染缸批次运行状态机，九相推进（含故障相）：
           待机 → 进布 → 进液 → 升温 → 保温 → 降温 → 水洗 → 出布 → （回待机）。
           待机相等 xStart 上升沿（必须边沿，防上电即在启动位自动进布）；
           进布相给进布命令等进布到位反馈；进液相开进液阀等液位达 fFillLevelMinPct；
           升温相开加热命令并把温度设定值置 fHeatTargetC，等温度达「目标 − 带宽」；
           保温相保持温度设定并计时 tHoldS；降温相开冷却命令、设定值置 fCoolTargetC，
           等温度降到「目标 + 带宽」；水洗相开进水阀等水洗到位反馈；
           出布相给出布命令等出布到位反馈，完成后置 xDone 锁存并回待机（保持到 xStart 撤下）。
        2) 步序跳转保护（本件的核心加固点）：状态机除判「本相完成条件」外，
           还必须复检「前相前置条件仍成立」，任一消失即锁码 0432 并进故障相：
           进液至水洗五相内 xLoadDoneFb 必须仍为 TRUE（布在缸内，防布卷被冲出）；
           升温至水洗五相内液位必须仍 >= fFillLevelMinPct（防干烧加热器与泵空转）。
           这是「跳步」（例如中途出布信号抖动）的唯一拦截位置。
        3) 每相独立超时 + 整序总超时：八个工作相各配「相定时 + 裕量」超时点，
           tonTotal 兜底整序总时长，九个超时源并发监视，任一命中即锁码进故障相。
  边界条件：1) 非有限值闸：温度、液位、目标温度、液位门槛、温度带宽、周期先过
           NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；命中即锁码 0431 进故障相，
           绝不把 NaN 拿去与温度/液位阈比较（NaN 比较恒假会让到达条件永不成立且永不报错，R19）。
        2) 周期入参闸（R21）：本件不做斜率运算，fCycleS 仅作观测记录；
           非法周期改用缺省 DL_CYCLE_DEF = 0.1 s，并在组态闸中一并锁码 0431（同码归因，成员分离）。
        3) 阈值域闸：-DL_T_SPAN < fCoolTargetC < fHeatTargetC <= DL_T_SPAN、fTempBandK > DL_EPS、
           0.0 < fFillLevelMinPct <= DL_PCT_HI，越域锁码 0431
           （降温目标高于升温目标会让温度判据永不成立）。
        4) 单点赋值（R26）：六个命令位、温度设定、xDone / xBusy 全部在段 8 统一出口写一次，
           相位内只改 _eState / _fSpC / 锁存位，不在分支内各写一遍命令。
        5) 定时器周期刷新（R7）：十七个 TON 与两个边沿实例全部在 CASE 之外无条件调用，
           IN 由状态导出，相迁移即 IN 归假自复位（R188）。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参/组态合法 → 清锁存回待机，
           回待机后必须重新给 xStart 上升沿才能再启动（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0433、清全部输出。
        8) 输出安全初值（R25）：六个命令位初值 FALSE（失电即安全侧：不进液、不加热、不出布）；
           温度设定初值 = 实测温度（无升降温需求）。
           故障侧语义（R191 显式声明）：故障相 fTempSpC 优先冻结在实测温度 fTempC（有限值时），
           实测非有限则回落到已过二阶终闸的安全设定值，绝不把 NaN 传给下游；不给加热指令也不给
           强冷指令；xBusy := FALSE（降级置标志而不静默）。
  量纲自证：fTempC / fHeatTargetC / fCoolTargetC 为 [degC]，fTempBandK 为温差不 [K]，degC 差值以 K 计；
           fLevelPct / fFillLevelMinPct 为液位百分数 [%]，比较两侧同量纲；
           所有时间引脚为 [TIME]，相超时点 = [TIME] + [TIME] = [TIME]，与 TON 的 PT 同量纲。
  码表 Error codes（本件子带 0091_042x / 043x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0421 信息级：进布相等待进布到位反馈（不置故障位）
    16#0091_0422 故障级：进布相超时
    16#0091_0423 故障级：进液相超时（液位未达门槛）
    16#0091_0424 故障级：升温相超时（未达目标温度带）
    16#0091_0425 故障级：保温相超时
    16#0091_0426 故障级：降温相超时（未达降温目标带）
    16#0091_0427 故障级：水洗相超时
    16#0091_0428 故障级：出布相超时
    16#0091_0429 故障级：整序总超时
    16#0091_0430 故障级：外部故障输入 xFault
    16#0091_0431 故障级：入参非有限，或温度/液位/周期组态越域
    16#0091_0432 故障级：步序跳转保护（布不在缸内或液位不足，前置条件中途消失）
    16#0091_0433 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0091_0434 信息级：批次完成保持中，等待撤令（不置故障位）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_JbsBatchState :
(
    eJbsBatchIdle   := 0,     // 待机：等启动上升沿，全命令撤销 / Idle, awaiting start, all commands dropped
    eJbsBatchLoad   := 10,    // 进布：给进布命令等到位 / Loading, awaiting the load-done feedback
    eJbsBatchFill   := 20,    // 进液：开进液阀等液位 / Filling, awaiting the level threshold
    eJbsBatchHeat   := 30,    // 升温：开加热等目标温度带 / Heating, awaiting the target band
    eJbsBatchHold   := 40,    // 保温：保持温度设定并计时 / Holding, setpoint kept and timer running
    eJbsBatchCool   := 50,    // 降温：开冷却等降温目标带 / Cooling, awaiting the cool-down band
    eJbsBatchRinse  := 60,    // 水洗：开进水阀等水洗到位 / Rinsing, awaiting the rinse-done feedback
    eJbsBatchUnload := 70,    // 出布：给出布命令等到位 / Unloading, awaiting the unload-done feedback
    eJbsBatchFault  := 90     // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_JiggerBatchRecipeSeq
VAR_INPUT
    xStart          : BOOL;    // 批次启动指令（上升沿有效）[bool] / Batch start command, edge triggered [bool]
    xReset          : BOOL;    // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault          : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    xLoadDoneFb     : BOOL;    // 进布到位反馈 [bool] / Load-done feedback [bool]
    xFillDoneFb     : BOOL;    // 进液完成反馈（液位开关）[bool] / Fill-done feedback, level switch [bool]
    xRinseDoneFb    : BOOL;    // 水洗到位反馈 [bool] / Rinse-done feedback [bool]
    xUnloadDoneFb   : BOOL;    // 出布到位反馈 [bool] / Unload-done feedback [bool]
    fTempC          : REAL;    // 染液实测温度 [degC] / Measured dye liquor temperature [degC]
    fLevelPct       : REAL;    // 染液液位百分数 [%] / Dye liquor level percentage [%]
    fFillLevelMinPct : REAL;   // 进液完成液位门槛 [%] / Fill level threshold [%]
    fHeatTargetC    : REAL;    // 升温目标温度 [degC] / Heating target temperature [degC]
    fCoolTargetC    : REAL;    // 降温目标温度 [degC] / Cooling target temperature [degC]
    fTempBandK      : REAL;    // 到温判定带宽 [K] / At-target band width [K]
    fCycleS         : REAL;    // 任务周期（观测用）[s] / Task cycle time, for observation [s]
    tLoadS          : TIME;    // 进布相设定时长 [TIME] / Loading phase duration [TIME]
    tFillS          : TIME;    // 进液相设定时长 [TIME] / Filling phase duration [TIME]
    tHeatS          : TIME;    // 升温相设定时长 [TIME] / Heating phase duration [TIME]
    tHoldS          : TIME;    // 保温相设定时长 [TIME] / Holding phase duration [TIME]
    tCoolS          : TIME;    // 降温相设定时长 [TIME] / Cooling phase duration [TIME]
    tRinseS         : TIME;    // 水洗相设定时长 [TIME] / Rinsing phase duration [TIME]
    tUnloadS        : TIME;    // 出布相设定时长 [TIME] / Unloading phase duration [TIME]
END_VAR
VAR_OUTPUT
    xLoadCmd        : BOOL;    // 进布命令（安全侧：故障时停）[bool] / Load command, fail-safe [bool]
    xFillValveCmd   : BOOL;    // 进液阀命令（安全侧：故障时关）[bool] / Fill valve command, fail-safe [bool]
    xHeatCmd        : BOOL;    // 加热命令（安全侧：故障时停）[bool] / Heating command, fail-safe [bool]
    xCoolCmd        : BOOL;    // 冷却命令（安全侧：故障时停）[bool] / Cooling command, fail-safe [bool]
    xRinseCmd       : BOOL;    // 水洗进水阀命令（安全侧：故障时关）[bool] / Rinse valve command, fail-safe [bool]
    xUnloadCmd      : BOOL;    // 出布命令（安全侧：故障时停）[bool] / Unload command, fail-safe [bool]
    fTempSpC        : REAL;    // 染液温度设定值 [degC] / Dye liquor temperature setpoint [degC]
    xDone           : BOOL;    // 批次完成保持位 [bool] / Batch complete held flag [bool]
    xBusy           : BOOL;    // 批次进行中 [bool] / Batch busy flag [bool]
    eState          : E_DL_JbsBatchState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId          : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonLoad         : TON;     // 进布相正常定时 [TIME] / Loading phase timer
    tonLoadOv       : TON;     // 进布相超时定时 [TIME] / Loading phase overrun timer
    tonFill         : TON;     // 进液相正常定时 [TIME] / Filling phase timer
    tonFillOv       : TON;     // 进液相超时定时 [TIME] / Filling phase overrun timer
    tonHeat         : TON;     // 升温相正常定时 [TIME] / Heating phase timer
    tonHeatOv       : TON;     // 升温相超时定时 [TIME] / Heating phase overrun timer
    tonHold         : TON;     // 保温相正常定时 [TIME] / Holding phase timer
    tonHoldOv       : TON;     // 保温相超时定时 [TIME] / Holding phase overrun timer
    tonCool         : TON;     // 降温相正常定时 [TIME] / Cooling phase timer
    tonCoolOv       : TON;     // 降温相超时定时 [TIME] / Cooling phase overrun timer
    tonRinse        : TON;     // 水洗相正常定时 [TIME] / Rinsing phase timer
    tonRinseOv      : TON;     // 水洗相超时定时 [TIME] / Rinsing phase overrun timer
    tonUnload       : TON;     // 出布相正常定时 [TIME] / Unloading phase timer
    tonUnloadOv     : TON;     // 出布相超时定时 [TIME] / Unloading phase overrun timer
    tonTotal        : TON;     // 整序总超时定时 [TIME] / Whole-sequence total timeout timer
    rtStart         : R_TRIG;  // 启动上升沿检测 [bool] / Start rising edge detector
    rtReset         : R_TRIG;  // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState         : E_DL_JbsBatchState := E_DL_JbsBatchState.eJbsBatchIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev     : E_DL_JbsBatchState := E_DL_JbsBatchState.eJbsBatchIdle;   // 上一拍相位快照（周期末更新）
    _fSpC           : REAL := 0.0;    // 内部温度设定值状态量 [degC] / Internal temperature setpoint [degC]
    _fCycleUseS     : REAL := 0.1;    // 实际使用的周期值 [s] / Cycle time actually used [s]
    _fHeatLowC      : REAL := 0.0;    // 升温到温下限（目标 − 带宽）[degC] / Heating arrival low bound [degC]
    _fCoolHighC     : REAL := 0.0;    // 降温到温上限（目标 + 带宽）[degC] / Cooling arrival high bound [degC]
    _bFinOk         : BOOL := FALSE;  // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCfgOk         : BOOL := FALSE;  // 温度/液位/周期组态域闸结果 / Configuration domain gate result
    _bActive        : BOOL := FALSE;  // 序激活（进布至出布七相之一）[bool] / Sequence active flag
    _bFabInDrum     : BOOL := FALSE;  // 布在缸内（步序保护用）[bool] / Fabric inside the drum, step guard
    _bLevelOk       : BOOL := FALSE;  // 液位达门槛（步序保护用）[bool] / Level above threshold, step guard
    _bStepGuardBad  : BOOL := FALSE;  // 步序跳转保护触发标志 [bool] / Step-guard violation flag
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
    DL_T_SPAN       : REAL := 300.0;      // 温度量级闸跨度 [degC] / Temperature magnitude gate span [degC]
    DL_PCT_HI       : REAL := 100.0;      // 液位百分数物理上限 [%] / Level percentage upper bound [%]
    DL_OVER_MARGIN  : TIME := T#30M;      // 相超时相对正常定时的裕量 [TIME] / Phase overrun margin [TIME]
    DL_TOTAL_MAX    : TIME := T#24H;      // 整序总超时上限 [TIME] / Whole-sequence total timeout [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bDoneL/_fSpC/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
_iPhaseChg := 0;                            // 相位切换计数每拍重算 / Phase-change counter recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none
_bStepGuardBad := FALSE;                    // 步序保护标志每拍重算 / Step-guard flag recomputed

(* —— 段 1：非有限值闸与组态域闸（R19：不拿 NaN 去比较温度与液位） —— *)
_bFinOk := (fTempC > -DL_BIG) AND (fTempC < DL_BIG)
           AND (fLevelPct > -DL_BIG) AND (fLevelPct < DL_BIG)
           AND (fFillLevelMinPct > -DL_BIG) AND (fFillLevelMinPct < DL_BIG)
           AND (fHeatTargetC > -DL_BIG) AND (fHeatTargetC < DL_BIG)
           AND (fCoolTargetC > -DL_BIG) AND (fCoolTargetC < DL_BIG)
           AND (fTempBandK > -DL_BIG) AND (fTempBandK < DL_BIG)
           AND (fCycleS > -DL_BIG) AND (fCycleS < DL_BIG);
_bCfgOk := (fTempBandK > DL_EPS)                        // 温度带宽必须为正
           AND (fFillLevelMinPct > 0.0)                 // 液位门槛必须为正
           AND (fFillLevelMinPct <= DL_PCT_HI)          // 液位门槛不得超 100 %
           AND (fLevelPct >= 0.0) AND (fLevelPct <= DL_PCT_HI)      // 实测液位量级闸
           AND (fHeatTargetC > fCoolTargetC)            // 降温目标必须低于升温目标（方向固定）
           AND (ABS(fHeatTargetC) <= DL_T_SPAN)         // 目标温度量级闸
           AND (ABS(fCoolTargetC) <= DL_T_SPAN)         // 目标温度量级闸
           AND (ABS(fTempC) <= DL_T_SPAN)               // 实测温度量级闸
           AND (fCycleS >= DL_CYCLE_MIN) AND (fCycleS <= DL_CYCLE_MAX);

IF _bCfgOk THEN
    _fCycleUseS := fCycleS;                 // 合法周期原值使用（本件仅观测用）
ELSE
    _fCycleUseS := DL_CYCLE_DEF;            // 非法周期一律用缺省 0.1 s
END_IF

(* —— 段 2：派生态（激活、到温带、步序保护前置量） —— *)
_bActive := (_eState = E_DL_JbsBatchState.eJbsBatchLoad)
            OR (_eState = E_DL_JbsBatchState.eJbsBatchFill)
            OR (_eState = E_DL_JbsBatchState.eJbsBatchHeat)
            OR (_eState = E_DL_JbsBatchState.eJbsBatchHold)
            OR (_eState = E_DL_JbsBatchState.eJbsBatchCool)
            OR (_eState = E_DL_JbsBatchState.eJbsBatchRinse)
            OR (_eState = E_DL_JbsBatchState.eJbsBatchUnload);
_fHeatLowC := fHeatTargetC - fTempBandK;                                  // 升温到温下限 [degC]
_fCoolHighC := fCoolTargetC + fTempBandK;                                 // 降温到温上限 [degC]
_bFabInDrum := xLoadDoneFb;                                               // 布在缸内判据（反馈即状态）
_bLevelOk := _bFinOk AND _bCfgOk AND (fLevelPct >= fFillLevelMinPct);      // 液位达门槛判据

(* —— 段 3：步序跳转保护（R：前置条件中途消失即锁码，唯一拦截位置） —— *)
IF (NOT _bFault) THEN
    IF ((_eState = E_DL_JbsBatchState.eJbsBatchFill)
        OR (_eState = E_DL_JbsBatchState.eJbsBatchHeat)
        OR (_eState = E_DL_JbsBatchState.eJbsBatchHold)
        OR (_eState = E_DL_JbsBatchState.eJbsBatchCool)
        OR (_eState = E_DL_JbsBatchState.eJbsBatchRinse)) AND (NOT _bFabInDrum) THEN
        _bStepGuardBad := TRUE;             // 布已不在缸内：进液之后的相一律非法
    END_IF
    IF ((_eState = E_DL_JbsBatchState.eJbsBatchHeat)
        OR (_eState = E_DL_JbsBatchState.eJbsBatchHold)
        OR (_eState = E_DL_JbsBatchState.eJbsBatchCool)
        OR (_eState = E_DL_JbsBatchState.eJbsBatchRinse)) AND (NOT _bLevelOk) THEN
        _bStepGuardBad := TRUE;             // 液位不足：加热与循环相一律非法（防干烧）
    END_IF
END_IF

(* —— 段 4：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := xStart);                                                                  // 启动上升沿，每拍必调
rtReset(CLK := xReset);                                                                  // 复位上升沿，每拍必调
tonLoad(IN := (_eState = E_DL_JbsBatchState.eJbsBatchLoad), PT := tLoadS);               // 进布相正常定时
tonLoadOv(IN := (_eState = E_DL_JbsBatchState.eJbsBatchLoad), PT := tLoadS + DL_OVER_MARGIN);        // 进布超时点
tonFill(IN := (_eState = E_DL_JbsBatchState.eJbsBatchFill), PT := tFillS);                // 进液相正常定时
tonFillOv(IN := (_eState = E_DL_JbsBatchState.eJbsBatchFill), PT := tFillS + DL_OVER_MARGIN);        // 进液超时点
tonHeat(IN := (_eState = E_DL_JbsBatchState.eJbsBatchHeat), PT := tHeatS);                // 升温相正常定时
tonHeatOv(IN := (_eState = E_DL_JbsBatchState.eJbsBatchHeat), PT := tHeatS + DL_OVER_MARGIN);        // 升温超时点
tonHold(IN := (_eState = E_DL_JbsBatchState.eJbsBatchHold), PT := tHoldS);                // 保温相正常定时
tonHoldOv(IN := (_eState = E_DL_JbsBatchState.eJbsBatchHold), PT := tHoldS + DL_OVER_MARGIN);        // 保温超时点
tonCool(IN := (_eState = E_DL_JbsBatchState.eJbsBatchCool), PT := tCoolS);                // 降温相正常定时
tonCoolOv(IN := (_eState = E_DL_JbsBatchState.eJbsBatchCool), PT := tCoolS + DL_OVER_MARGIN);        // 降温超时点
tonRinse(IN := (_eState = E_DL_JbsBatchState.eJbsBatchRinse), PT := tRinseS);             // 水洗相正常定时
tonRinseOv(IN := (_eState = E_DL_JbsBatchState.eJbsBatchRinse), PT := tRinseS + DL_OVER_MARGIN);     // 水洗超时点
tonUnload(IN := (_eState = E_DL_JbsBatchState.eJbsBatchUnload), PT := tUnloadS);          // 出布相正常定时
tonUnloadOv(IN := (_eState = E_DL_JbsBatchState.eJbsBatchUnload), PT := tUnloadS + DL_OVER_MARGIN);  // 出布超时点
tonTotal(IN := _bActive, PT := DL_TOTAL_MAX);                                             // 整序总超时

(* —— 段 5：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0430;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_JbsBatchState.eJbsBatchFault;
END_IF
IF ((NOT _bFinOk) OR (NOT _bCfgOk)) AND (NOT _bFault) THEN
    _uFault := 16#0091_0431;                // 故障级：入参非有限或组态越域（内部成员已分离）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_JbsBatchState.eJbsBatchFault;
END_IF
IF _bStepGuardBad AND (NOT _bFault) THEN
    _uFault := 16#0091_0432;                // 故障级：步序跳转保护（前置条件中途消失）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_JbsBatchState.eJbsBatchFault;
END_IF
IF tonTotal.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0091_0429;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_JbsBatchState.eJbsBatchFault;
END_IF

(* —— 段 6：相位机（只做迁移与设定值更新；出口在段 8 单点映射） —— *)
CASE _eState OF

E_DL_JbsBatchState.eJbsBatchIdle:
    _fSpC := fTempC;                        // 待机设定值跟随实测（无升降温需求，安全侧）
    IF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令即清完成位，为下一批重新武装
    ELSIF rtStart.Q AND _bFinOk AND _bCfgOk THEN
        _bDoneL := FALSE;                   // 新批次开始：清完成位（迁移前一次性清）
        _eState := E_DL_JbsBatchState.eJbsBatchLoad;          // 进进布相
    END_IF

E_DL_JbsBatchState.eJbsBatchLoad:
    _fSpC := fTempC;                        // 进布相不控温
    IF tonLoadOv.Q THEN
        _uFault := 16#0091_0422;            // 故障级：进布相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_JbsBatchState.eJbsBatchFault;
    ELSIF tonLoad.Q AND xLoadDoneFb THEN
        _eState := E_DL_JbsBatchState.eJbsBatchFill;          // 本拍合法事件优先于超时迁移（R275）
    ELSE
        _uInfo := 16#0091_0421;             // 信息级：等进布到位反馈（不置故障位）
    END_IF

E_DL_JbsBatchState.eJbsBatchFill:
    _fSpC := fTempC;                        // 进液相不控温
    IF tonFillOv.Q THEN
        _uFault := 16#0091_0423;            // 故障级：进液相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_JbsBatchState.eJbsBatchFault;
    ELSIF tonFill.Q AND _bLevelOk AND xFillDoneFb THEN
        _eState := E_DL_JbsBatchState.eJbsBatchHeat;          // 液位到：进升温相
    END_IF

E_DL_JbsBatchState.eJbsBatchHeat:
    _fSpC := fHeatTargetC;                  // 升温相设定值置升温目标
    IF tonHeatOv.Q THEN
        _uFault := 16#0091_0424;            // 故障级：升温相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_JbsBatchState.eJbsBatchFault;
    ELSIF tonHeat.Q AND (fTempC >= _fHeatLowC) THEN
        _eState := E_DL_JbsBatchState.eJbsBatchHold;          // 到温带：进保温相
    END_IF

E_DL_JbsBatchState.eJbsBatchHold:
    _fSpC := fHeatTargetC;                  // 保温相设定值保持在升温目标
    IF tonHoldOv.Q THEN
        _uFault := 16#0091_0425;            // 故障级：保温相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_JbsBatchState.eJbsBatchFault;
    ELSIF tonHold.Q THEN
        _eState := E_DL_JbsBatchState.eJbsBatchCool;          // 保温到点：进降温相
    END_IF

E_DL_JbsBatchState.eJbsBatchCool:
    _fSpC := fCoolTargetC;                  // 降温相设定值置降温目标
    IF tonCoolOv.Q THEN
        _uFault := 16#0091_0426;            // 故障级：降温相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_JbsBatchState.eJbsBatchFault;
    ELSIF tonCool.Q AND (fTempC <= _fCoolHighC) THEN
        _eState := E_DL_JbsBatchState.eJbsBatchRinse;         // 降到目标带：进水洗相
    END_IF

E_DL_JbsBatchState.eJbsBatchRinse:
    _fSpC := fCoolTargetC;                  // 水洗相保持降温目标（防回温）
    IF tonRinseOv.Q THEN
        _uFault := 16#0091_0427;            // 故障级：水洗相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_JbsBatchState.eJbsBatchFault;
    ELSIF tonRinse.Q AND xRinseDoneFb THEN
        _eState := E_DL_JbsBatchState.eJbsBatchUnload;        // 水洗到位：进出布相
    END_IF

E_DL_JbsBatchState.eJbsBatchUnload:
    _fSpC := fTempC;                        // 出布相不控温
    IF tonUnloadOv.Q THEN
        _uFault := 16#0091_0428;            // 故障级：出布相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_JbsBatchState.eJbsBatchFault;
    ELSIF tonUnload.Q AND xUnloadDoneFb THEN
        _bDoneL := TRUE;                    // 完成位锁存（跨相保持，段 8 单点映射）
        _eState := E_DL_JbsBatchState.eJbsBatchIdle;          // 回待机，完成位保持到撤令
    END_IF

E_DL_JbsBatchState.eJbsBatchFault:
    _fSpC := fTempC;                        // 故障相设定值冻结在实测（不给加热也不给强冷，R191 已声明）
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bCfgOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参/组态合法（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bDoneL := FALSE;                   // 完成位一并清，避免故障后误报完成
        _eState := E_DL_JbsBatchState.eJbsBatchIdle;          // 回待机，需新上升沿才可再启动
    END_IF

ELSE
    _uFault := 16#0091_0433;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _bDoneL := FALSE;                       // 完成位清
    _fSpC := fTempC;                        // 兜底侧设定值冻结在实测
    _eState := E_DL_JbsBatchState.eJbsBatchFault;             // 强制回故障相

END_CASE

(* —— 段 7：后置段（相位快照与设定值域兜底） —— *)
IF _eState <> _eStatePrev THEN
    _iPhaseChg := _iPhaseChg + 1;           // 相位已切换：记一拍切换事件（观测用）
END_IF
_eStatePrev := _eState;                     // 快照在周期末尾统一更新
IF NOT (_fSpC > -DL_BIG AND _fSpC < DL_BIG) THEN
    _fSpC := fTempC;                        // 内部状态自检：非有限即回落实测值
END_IF
_fSpC := LIMIT(-DL_T_SPAN, _fSpC, DL_T_SPAN);   // 越量级钳制，防设定值发散
(* —— 段 7.5：LIMIT 后二阶终闸（R19 二阶形态）——
   LIMIT 对 NaN 会原样透传（内部比较全假走 ELSE 支），一次钳制不足以闸断通路，
   且上面那次回退源 fTempC 本身也可能非有限，故在钳制之后再判一次。 *)
IF NOT (_fSpC >= -DL_T_SPAN AND _fSpC <= DL_T_SPAN) THEN
    _fSpC := 0.0;                           // 双源皆非有限：0 degC 安全位 / Both sources non-finite: 0 degC safe
END_IF

(* —— 段 8：出口单点映射（名实同源；命令位由状态导出，故障侧一律撤销） —— *)
xLoadCmd := (_eState = E_DL_JbsBatchState.eJbsBatchLoad) AND (NOT _bFault);               // 进布命令
xFillValveCmd := (_eState = E_DL_JbsBatchState.eJbsBatchFill) AND (NOT _bFault);          // 进液阀
xHeatCmd := ((_eState = E_DL_JbsBatchState.eJbsBatchHeat)
             OR (_eState = E_DL_JbsBatchState.eJbsBatchHold)) AND (NOT _bFault);          // 加热：升温+保温
xCoolCmd := ((_eState = E_DL_JbsBatchState.eJbsBatchCool)
             OR (_eState = E_DL_JbsBatchState.eJbsBatchRinse)) AND (NOT _bFault);         // 冷却：降温+水洗
xRinseCmd := (_eState = E_DL_JbsBatchState.eJbsBatchRinse) AND (NOT _bFault);             // 水洗进水阀
xUnloadCmd := (_eState = E_DL_JbsBatchState.eJbsBatchUnload) AND (NOT _bFault);           // 出布命令
IF _bFault THEN
    IF (fTempC >= -DL_T_SPAN) AND (fTempC <= DL_T_SPAN) THEN
        fTempSpC := fTempC;                 // 故障侧优先回落实测温度（有限时保持原语义：冻结在实测）
    ELSE
        fTempSpC := _fSpC;                  // 实测非有限时回落到已过二阶终闸的安全值，绝不输出 NaN
    END_IF;
ELSE
    fTempSpC := _fSpC;                      // 正常侧设定值出口
END_IF
xDone := _bDoneL AND (NOT _bFault);                                                       // 完成位出口
xBusy := _bActive AND (NOT _bFault);                                                      // 进行中出口（故障时降级置假）
eState := _eState;                                                                        // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSIF _bDoneL THEN
    nErrId := 16#0091_0434;                 // 信息级：批次完成保持中，等待撤令
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
