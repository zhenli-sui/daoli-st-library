(*
  Name: FB_DL_LyoVacuumPullSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 抽真空状态机，六相推进：待机 → 粗抽 → 精抽 → 保持 → 就绪 → （通气）。
           待机相等 xStart 上升沿；腔体压力已低于粗抽目标时跳过粗抽相（信息级码 0231 声明跳过）；
           粗抽相开粗抽泵阀组，压力降到 fRoughTargetMbar 即转精抽；精抽相关粗抽阀、开精抽阀，
           压力降到 fFineTargetMbar 即转保持相；保持相关全部抽气、观察 tHoldS 内压力升幅，
           升幅 <= fHoldRiseMaxMbar 判真空保持合格，置 xHoldOk 并进就绪相；
           就绪相保持 xReady 直到 xStart 撤下；撤令后进通气相复压并回待机。
        2) 泵故障兜底：粗抽/精抽/保持三相内，泵运行反馈丢失或泵过载上升即锁码 0237 并立即进故障相，
           同时撤销全部抽气命令、不打开通气阀（避免带故障强行复压把油雾带入腔体）。
        3) 每相独立超时 + 整序总超时：四个相定时器各配一个「定时 + 裕量」超时点，
           tonTotal 兜底整序总时长；保持相另配真空上升超限判据（0234）与稳定超时（0235）双归因。
  边界条件：1) 非有限值闸：压力、三个目标限值先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；
           命中即锁码 0239 进故障相，绝不把 NaN 拿去与真空目标比较（NaN 比较恒假会让抽气永不停止，R19）。
        2) 组态域闸：三个压力阈须满足 0.0 < fFineTargetMbar < fRoughTargetMbar（真空度方向由粗到精），
           fHoldRiseMaxMbar > DL_EPS，越域锁码 0239（组态错误与入参非有限共用同一归因码前缀，
           但内部用两个独立成员区分，见 _bCfgOk / _bFinOk）。
        3) 压力单调性：抽气相内压力不得上升；若在粗抽/精抽相检测到压力高于本相入口压力且超过
           DL_PRESS_TOL，视为泵失效实测证据，锁码 0232 / 0233（与超时归因区分：这里不是等不到，而是反向）。
        4) 时间参数零闸：tRoughS / tFineS / tHoldS <= T#0S 时对应相定时器立即置 Q（等价跳过），
           属调试合法组态；但保持相零窗会使升幅判据恒成立，故保持相入口对 tHoldS 做显式零闸 → 锁码 0235。
        5) 定时器周期刷新（R7）：八个 TON 与复位边沿全部在 CASE 之外无条件调用。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参/组态合法 → 清锁存回待机，
           回待机后必须重新给 xStart 上升沿才能再启动（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0240、清全部输出。
        8) 输出安全初值（R25）：三个阀门命令初值 FALSE、xReady 初值 FALSE，待机相显式赋值。
  量纲自证：fChamberPressMbar / fRoughTargetMbar / fFineTargetMbar / fHoldRiseMaxMbar 全为压力 [mbar]，
           比较两侧同量纲；升幅 = 保持末压力 − 保持初压力，仍为 [mbar]；
           所有时间引脚为 [TIME]，相超时点 = [TIME] + [TIME] = [TIME]，与 TON 的 PT 同量纲。
  码表 Error codes（本件子带 0091_024x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0231 信息级：腔体压力已低于粗抽目标，跳过粗抽相（不置故障位）
    16#0091_0232 故障级：粗抽相超时（定时到但未达粗抽目标）
    16#0091_0233 故障级：精抽相超时（定时到但未达精抽目标）
    16#0091_0234 故障级：保持相真空度上升超限（泄漏或放气）
    16#0091_0235 故障级：保持相超时或保持窗为零（压力未稳定/判据恒真）
    16#0091_0236 故障级：整序总超时
    16#0091_0237 故障级：泵运行反馈丢失或泵过载
    16#0091_0238 故障级：外部故障输入 xFault
    16#0091_0239 故障级：压力/限值入参非有限，或压力阈组态越域
    16#0091_0240 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0091_0241 信息级：就绪保持中，等待撤令（不置故障位）
    16#0091_0242 信息级：通气复压相进行中（不置故障位）
    16#0091_0243 信息级：泵未就绪（无运行反馈或过载），暂不启动抽气（不置故障位）
    16#0091_0244 故障级：粗抽相压力反向上升（泵失效实证，与超时成因分离）
    16#0091_0245 故障级：精抽相压力反向上升（泄漏或阀未开，与超时成因分离）
    16#0091_0246 故障级：通气相超时（复压未完成）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_LyoVacuumPullState :
(
    eLyoVacIdle  := 0,      // 待机：等启动上升沿 / Idle, awaiting the start rising edge
    eLyoVacRough := 10,     // 粗抽：粗抽泵组开，降到粗抽目标 / Rough pull, pump group on
    eLyoVacFine  := 20,     // 精抽：关粗抽阀开精抽阀，降到精抽目标 / Fine pull, fine valve open
    eLyoVacHold  := 30,     // 保持：关全部抽气，测压力升幅 / Hold, all pumping off, rise measured
    eLyoVacReady := 40,     // 就绪：真空保持合格，保持到位 / Ready, vacuum hold accepted
    eLyoVacVent  := 50,     // 通气：开通气阀复压回待机 / Vent, repressurising back to idle
    eLyoVacFault := 90      // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_LyoVacuumPullSeq
VAR_INPUT
    xStart           : BOOL;   // 抽真空启动指令（上升沿有效）[bool] / Vacuum pull start, edge triggered [bool]
    xReset           : BOOL;   // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault           : BOOL;   // 外部故障汇总 [bool] / External fault aggregate [bool]
    xPumpRunFb       : BOOL;   // 真空泵运行反馈 [bool] / Vacuum pump running feedback [bool]
    xPumpOverload    : BOOL;   // 真空泵过载信号 [bool] / Vacuum pump overload signal [bool]
    fChamberPressMbar : REAL;  // 腔体实测压力 [mbar] / Measured chamber pressure [mbar]
    fRoughTargetMbar : REAL;   // 粗抽目标压力 [mbar] / Rough pull target pressure [mbar]
    fFineTargetMbar  : REAL;   // 精抽目标压力 [mbar] / Fine pull target pressure [mbar]
    fHoldRiseMaxMbar : REAL;   // 保持相允许压力升幅 [mbar] / Permitted pressure rise during hold [mbar]
    tRoughS          : TIME;   // 粗抽相设定时长 [TIME] / Rough pull phase duration [TIME]
    tFineS           : TIME;   // 精抽相设定时长 [TIME] / Fine pull phase duration [TIME]
    tHoldS           : TIME;   // 保持相设定时长 [TIME] / Hold phase duration [TIME]
END_VAR
VAR_OUTPUT
    xRoughValveCmd   : BOOL;   // 粗抽阀命令（安全侧：故障时关）[bool] / Rough valve command, fail-safe [bool]
    xFineValveCmd    : BOOL;   // 精抽阀命令（安全侧：故障时关）[bool] / Fine valve command, fail-safe [bool]
    xVentValveCmd    : BOOL;   // 通气阀命令（安全侧：故障时关）[bool] / Vent valve command, fail-safe [bool]
    xHoldOk          : BOOL;   // 真空保持判据通过（跨相保持）[bool] / Vacuum hold accepted, held across phases [bool]
    xReady           : BOOL;   // 抽真空就绪保持位 [bool] / Vacuum ready held flag [bool]
    xBusy            : BOOL;   // 抽真空进行中 [bool] / Vacuum pull busy [bool]
    eState           : E_DL_LyoVacuumPullState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId           : UDINT;  // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonRough         : TON;    // 粗抽相正常定时 [TIME] / Rough pull phase timer
    tonRoughOv       : TON;    // 粗抽相超时定时 [TIME] / Rough pull phase overrun timer
    tonFine          : TON;    // 精抽相正常定时 [TIME] / Fine pull phase timer
    tonFineOv        : TON;    // 精抽相超时定时 [TIME] / Fine pull phase overrun timer
    tonHold          : TON;    // 保持相正常定时 [TIME] / Hold phase timer
    tonHoldOv        : TON;    // 保持相超时定时 [TIME] / Hold phase overrun timer
    tonVent          : TON;    // 通气相正常定时 [TIME] / Vent phase timer
    tonVentOv        : TON;    // 通气相超时定时 [TIME] / Vent phase overrun timer
    tonTotal         : TON;    // 整序总超时定时 [TIME] / Whole-sequence total timeout timer
    rtStart          : R_TRIG; // 启动上升沿检测 [bool] / Start rising edge detector
    rtReset          : R_TRIG; // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState          : E_DL_LyoVacuumPullState := E_DL_LyoVacuumPullState.eLyoVacIdle;   // 内部相位（CASE 唯一写入目标）
    _fPressEntryMbar : REAL := 0.0;   // 本相入口压力快照 [mbar] / Pressure snapshot at phase entry [mbar]
    _fHoldStartMbar  : REAL := 0.0;   // 保持相起点压力快照 [mbar] / Pressure snapshot at hold start [mbar]
    _fRiseMbar       : REAL := 0.0;   // 保持相压力升幅 [mbar] / Pressure rise during the hold phase [mbar]
    _bFinOk          : BOOL := FALSE; // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCfgOk          : BOOL := FALSE; // 压力阈组态域闸结果 / Pressure threshold domain gate result
    _bPumpOk         : BOOL := FALSE; // 泵健康（运行反馈有且无过载）[bool] / Pump healthy flag [bool]
    _bActive         : BOOL := FALSE; // 序激活（粗抽至通气五相之一）[bool] / Sequence active flag [bool]
    _bHoldL          : BOOL := FALSE; // 保持合格位锁存（跨相保持）[bool] / Hold-accepted latch [bool]
    _bFault          : BOOL := FALSE; // 故障锁存位 [bool] / Latched fault flag [bool]
    _uInfo           : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault          : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;      // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PRESS_TOL   : REAL := 0.05;        // 抽气相压力反向容差 [mbar] / Reverse-trend tolerance while pumping [mbar]
    DL_P_HI        : REAL := 1100.0;      // 压力量级闸上限（略高于常压）[mbar] / Pressure magnitude gate upper bound [mbar]
    DL_OVER_MARGIN : TIME := T#60S;       // 相超时相对正常定时的裕量 [TIME] / Phase overrun margin [TIME]
    DL_TOTAL_MAX   : TIME := T#4H;        // 整序总超时上限 [TIME] / Whole-sequence total timeout [TIME]
    DL_ZERO_PRES   : REAL := 0.0;         // 压力零基准 [mbar] / Zero pressure reference [mbar]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bHoldL 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸与组态域闸（R19：不拿 NaN 去比较真空目标） —— *)
_bFinOk := (fChamberPressMbar > -DL_BIG) AND (fChamberPressMbar < DL_BIG)
           AND (fRoughTargetMbar > -DL_BIG) AND (fRoughTargetMbar < DL_BIG)
           AND (fFineTargetMbar > -DL_BIG) AND (fFineTargetMbar < DL_BIG)
           AND (fHoldRiseMaxMbar > -DL_BIG) AND (fHoldRiseMaxMbar < DL_BIG);
_bCfgOk := (fFineTargetMbar > DL_EPS)                       // 精抽目标须为正压
           AND (fFineTargetMbar < fRoughTargetMbar)         // 精抽必须比粗抽更深（方向由粗到精）
           AND (fRoughTargetMbar < DL_P_HI)                 // 粗抽目标须在压力量级内
           AND (fHoldRiseMaxMbar > DL_EPS);                 // 允许升幅须组态为正

(* —— 段 2：泵健康判据（运行反馈 + 过载；过载优先） —— *)
_bPumpOk := xPumpRunFb AND (NOT xPumpOverload);

(* —— 段 3：派生态（序激活、保持升幅） —— *)
_bActive := (_eState = E_DL_LyoVacuumPullState.eLyoVacRough)
            OR (_eState = E_DL_LyoVacuumPullState.eLyoVacFine)
            OR (_eState = E_DL_LyoVacuumPullState.eLyoVacHold)
            OR (_eState = E_DL_LyoVacuumPullState.eLyoVacReady)
            OR (_eState = E_DL_LyoVacuumPullState.eLyoVacVent);
_fRiseMbar := fChamberPressMbar - _fHoldStartMbar;          // 保持相压力升幅 [mbar]

(* —— 段 4：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := xStart);                                                                   // 启动上升沿，每拍必调
rtReset(CLK := xReset);                                                                   // 复位上升沿，每拍必调
tonRough(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacRough), PT := tRoughS);          // 粗抽相正常定时
tonRoughOv(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacRough),
           PT := tRoughS + DL_OVER_MARGIN);                                               // 粗抽相超时点
tonFine(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacFine), PT := tFineS);             // 精抽相正常定时
tonFineOv(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacFine),
          PT := tFineS + DL_OVER_MARGIN);                                                 // 精抽相超时点
tonHold(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacHold), PT := tHoldS);             // 保持相正常定时
tonHoldOv(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacHold),
          PT := tHoldS + DL_OVER_MARGIN);                                                 // 保持相超时点
tonVent(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacVent), PT := tRoughS);            // 通气相正常定时（借用粗抽时长作复压窗）
tonVentOv(IN := (_eState = E_DL_LyoVacuumPullState.eLyoVacVent),
          PT := tRoughS + DL_OVER_MARGIN);                                                // 通气相超时点
tonTotal(IN := _bActive, PT := DL_TOTAL_MAX);                                             // 整序总超时

(* —— 段 5：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0238;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
END_IF
IF ((NOT _bFinOk) OR (NOT _bCfgOk)) AND (NOT _bFault) THEN
    _uFault := 16#0091_0239;                // 故障级：入参非有限或压力阈组态越域（同一码，成员已分离）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
END_IF
IF tonTotal.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0091_0236;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
END_IF
IF (NOT _bPumpOk) AND _bActive AND (NOT _bFault)
   AND (_eState <> E_DL_LyoVacuumPullState.eLyoVacVent) THEN
    _uFault := 16#0091_0237;                // 故障级：泵反馈丢失或过载（通气相不需泵，故排除）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
END_IF

(* —— 段 6：相位机（只做迁移与锁存；出口在段 8 单点映射） —— *)
CASE _eState OF

E_DL_LyoVacuumPullState.eLyoVacIdle:
    IF NOT xStart THEN
        _bHoldL := FALSE;                   // 撤令即清保持合格位，为下次抽真空重新武装
        _fPressEntryMbar := fChamberPressMbar;   // 待机相刷新入口压力快照（有限性由段 5 保证）
    ELSIF rtStart.Q AND _bFinOk AND _bCfgOk THEN
        _bHoldL := FALSE;                   // 新序开始：清保持合格位
        _fPressEntryMbar := fChamberPressMbar;   // 捕获入口压力，供粗抽反向判据使用
        IF fChamberPressMbar <= fRoughTargetMbar THEN
            _uInfo := 16#0091_0231;         // 信息级：已低于粗抽目标，声明跳过粗抽相
            _eState := E_DL_LyoVacuumPullState.eLyoVacFine;      // 直接进精抽相
        ELSE
            _eState := E_DL_LyoVacuumPullState.eLyoVacRough;     // 进粗抽相
        END_IF
    ELSIF NOT _bPumpOk THEN
        _uInfo := 16#0091_0243;             // 信息级：泵未就绪，暂不启动（不置故障位）
    END_IF

E_DL_LyoVacuumPullState.eLyoVacRough:
    IF tonRoughOv.Q THEN
        _uFault := 16#0091_0232;            // 故障级：粗抽相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
    ELSIF (fChamberPressMbar - _fPressEntryMbar) > DL_PRESS_TOL THEN
        _uFault := 16#0091_0244;            // 故障级：粗抽中压力反向上升（泵失效实证，独立成因）
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
    ELSIF fChamberPressMbar <= fRoughTargetMbar THEN
        _fPressEntryMbar := fChamberPressMbar;                   // 达粗抽目标：刷新入口快照（迁移前一次性）
        _eState := E_DL_LyoVacuumPullState.eLyoVacFine;          // 进精抽相
    END_IF

E_DL_LyoVacuumPullState.eLyoVacFine:
    IF tonFineOv.Q THEN
        _uFault := 16#0091_0233;            // 故障级：精抽相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
    ELSIF (fChamberPressMbar - _fPressEntryMbar) > DL_PRESS_TOL THEN
        _uFault := 16#0091_0245;            // 故障级：精抽中压力反向上升（泄漏或阀未开，独立成因）
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
    ELSIF fChamberPressMbar <= fFineTargetMbar THEN
        _fHoldStartMbar := fChamberPressMbar;                    // 达精抽目标：捕获保持相起点压力
        _eState := E_DL_LyoVacuumPullState.eLyoVacHold;          // 进保持相
    END_IF

E_DL_LyoVacuumPullState.eLyoVacHold:
    IF tHoldS <= T#0S THEN
        _uFault := 16#0091_0235;            // 故障级：保持窗为零，升幅判据恒成立（不可接受组态）
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
    ELSIF tonHoldOv.Q THEN
        _uFault := 16#0091_0235;            // 故障级：保持相超时（压力未稳定）
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
    ELSIF tonHold.Q THEN
        IF _fRiseMbar > fHoldRiseMaxMbar THEN
            _uFault := 16#0091_0234;        // 故障级：保持相真空度上升超限（泄漏/放气）
            _bFault := TRUE;                // 锁存
            _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
        ELSE
            _bHoldL := TRUE;                // 真空保持合格：锁存（跨相保持）
            _eState := E_DL_LyoVacuumPullState.eLyoVacReady;     // 进就绪相
        END_IF
    END_IF

E_DL_LyoVacuumPullState.eLyoVacReady:
    IF NOT xStart THEN
        _bHoldL := FALSE;                   // 撤令：清保持合格位并进通气相
        _eState := E_DL_LyoVacuumPullState.eLyoVacVent;
    ELSE
        _uInfo := 16#0091_0241;             // 信息级：就绪保持中，等撤令（不置故障位）
    END_IF

E_DL_LyoVacuumPullState.eLyoVacVent:
    IF tonVentOv.Q THEN
        _uFault := 16#0091_0246;            // 故障级：通气相超时（复压未完成，独立成因）
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoVacuumPullState.eLyoVacFault;
    ELSIF tonVent.Q THEN
        _eState := E_DL_LyoVacuumPullState.eLyoVacIdle;          // 复压完成：回待机
    ELSE
        _uInfo := 16#0091_0242;             // 信息级：通气复压进行中（不置故障位）
    END_IF

E_DL_LyoVacuumPullState.eLyoVacFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bCfgOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参/组态合法（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bHoldL := FALSE;                   // 保持合格位一并清，避免故障后误报就绪
        _eState := E_DL_LyoVacuumPullState.eLyoVacIdle;          // 回待机，需新上升沿才可再启动
    END_IF

ELSE
    _uFault := 16#0091_0240;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoVacuumPullState.eLyoVacFault;             // 强制回故障相

END_CASE

(* —— 段 7：后置段（压力快照域兜底：非有限即清零，防污染下拍反向判据） —— *)
IF NOT (_fPressEntryMbar > -DL_BIG AND _fPressEntryMbar < DL_BIG) THEN
    _fPressEntryMbar := DL_ZERO_PRES;       // 内部状态自检：非有限即清零
END_IF
IF NOT (_fHoldStartMbar > -DL_BIG AND _fHoldStartMbar < DL_BIG) THEN
    _fHoldStartMbar := DL_ZERO_PRES;        // 内部状态自检：非有限即清零
END_IF

(* —— 段 8：出口单点映射（名实同源；阀门由状态导出，故障侧一律关阀） —— *)
xRoughValveCmd := (_eState = E_DL_LyoVacuumPullState.eLyoVacRough) AND (NOT _bFault);    // 粗抽阀：仅粗抽相
xFineValveCmd := (_eState = E_DL_LyoVacuumPullState.eLyoVacFine) AND (NOT _bFault);      // 精抽阀：仅精抽相
xVentValveCmd := (_eState = E_DL_LyoVacuumPullState.eLyoVacVent) AND (NOT _bFault);      // 通气阀：仅通气相
xHoldOk := _bHoldL AND (NOT _bFault);                                                    // 保持合格位出口
xReady := (_eState = E_DL_LyoVacuumPullState.eLyoVacReady) AND _bHoldL AND (NOT _bFault);   // 就绪位出口
xBusy := _bActive AND (NOT _bFault);                                                     // 进行中出口
eState := _eState;                                                                       // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
