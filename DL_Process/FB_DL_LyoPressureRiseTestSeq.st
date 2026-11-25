(*
  Name: FB_DL_LyoPressureRiseTestSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 压力升测试序状态机，七相推进：待机 → 隔离 → 稳压 → 计时 → 判定 → 复压 → 完成。
           待机相等 xStart 上升沿且腔体已达起始真空度（否则只置信息级码 0221 不放行）；
           隔离相关隔离阀并等阀关到位反馈；稳压相等压力稳定 tSettleS（消除吸附气体影响）；
           计时相记录起点压力并等 tTestS；判定相算泄漏率 Q = dP * V / t 并判定；
           复压相开通气阀复压并等 tRepressS，完成相置 xDone 并保持到撤令。
        2) 泄漏超限中止：判定相算得 Q > fLeakMaxMbarLs 即判不合格并锁码 0229、进故障相，
           同时撤销全部阀门命令（安全侧：通气阀关、隔离阀保持关闭，防误开腔）。
        3) 每相独立超时 + 整序总超时：相定时器给正常推进点，相超时定时器给「定时 + 裕量」越限点，
           tonTotal 兜底整序总时长，四者并发监视，任一命中立即锁码进故障相。
  边界条件：1) 非有限值闸：压力、容积、泄漏上限先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；
           命中即锁码 0228 进故障相，绝不把 NaN 拿去与真空度阈值比较（NaN 比较恒假会伪装成「已达真空」，R19）。
        2) 时间参数零闸：tSettleS / tTestS / tRepressS <= T#0S 时对应相定时器立即置 Q（等价跳过该相），
           属合法调试组态；但计时相零时长会计得 Q = 0/0，故在判定相入口对实际计时 > DL_EPS 做显式零闸，
           零闸不通过即锁码 0224 而非输出无穷大泄漏率。
        3) 容积零闸：fVolumeL <= DL_EPS 时泄漏率不可算（乘子为零会把「未组态」伪装成「密封完好」），
           在判定相锁码 0228 并判不合格。
        4) 压力方向：升压为负（隔离后压力下降）说明隔离阀未关严或泵未停，判不合格锁码 0229，
           不取绝对值掩盖隔离失效。
        5) 定时器周期刷新（R7）：十个 TON 与复位边沿全部在 CASE 之外无条件调用。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参有限 → 清锁存回待机，
           回待机后必须重新给 xStart 上升沿才能再测（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0230、清全部输出。
  量纲自证：Q = dP [mbar] * V [L] / t [s] = mbar*L/s，与 fLeakMaxMbarLs 同量纲，可直接比较；
           所有时间引脚为 [TIME]，相超时点 = [TIME] + [TIME] = [TIME]，与 TON 的 PT 同量纲。
  码表 Error codes（本件子带 0091_022x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0221 信息级：腔体压力未达起始真空度，禁止启动测试（不置故障位）
    16#0091_0222 故障级：隔离相超时（隔离阀未关到位）
    16#0091_0223 故障级：稳压相超时
    16#0091_0224 故障级：计时相超时或实际计时为零（泄漏率不可算）
    16#0091_0225 故障级：复压相超时
    16#0091_0226 故障级：整序总超时
    16#0091_0227 故障级：外部故障输入 xFault
    16#0091_0228 故障级：压力/容积/限值入参非有限或容积未组态
    16#0091_0229 故障级：泄漏率超限（不合格，或升压为负即隔离失效）
    16#0091_0230 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_LyoPrTestState :
(
    eLyoPrIdle    := 0,     // 待机：等启动沿与起始真空度 / Idle, awaiting the start edge and base vacuum
    eLyoPrIsolate := 10,    // 隔离：关隔离阀等到位反馈 / Isolate, closing the isolation valve
    eLyoPrSettle  := 20,    // 稳压：等吸附气体平衡 / Settle, awaiting desorption equilibrium
    eLyoPrTiming  := 30,    // 计时：记录起点压力并等测试窗 / Timing, base pressure captured
    eLyoPrJudge   := 40,    // 判定：算泄漏率并判合格 / Judge, computing and comparing the leak rate
    eLyoPrRepress := 50,    // 复压：开通气阀复压 / Repressurise, opening the vent valve
    eLyoPrDone    := 60,    // 完成：保持至撤令 / Done, held until the command is released
    eLyoPrFault   := 90     // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_LyoPressureRiseTestSeq
VAR_INPUT
    xStart           : BOOL;   // 测试启动指令（上升沿有效）[bool] / Test start command, edge triggered [bool]
    xReset           : BOOL;   // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault           : BOOL;   // 外部故障汇总 [bool] / External fault aggregate [bool]
    xIsoValveClosedFb : BOOL;  // 隔离阀关到位反馈 [bool] / Isolation valve closed feedback [bool]
    fChamberPressMbar : REAL;  // 腔体实测压力 [mbar] / Measured chamber pressure [mbar]
    fVolumeL         : REAL;   // 腔体（含管路）内容积 [L] / Chamber and piping internal volume [L]
    fLeakMaxMbarLs   : REAL;   // 泄漏率合格上限 [mbar*L/s] / Leak rate acceptance limit [mbar*L/s]
    tSettleS         : TIME;   // 稳压相设定时长 [TIME] / Settle phase duration [TIME]
    tTestS           : TIME;   // 计时相设定时长 [TIME] / Timing phase duration [TIME]
    tRepressS        : TIME;   // 复压相设定时长 [TIME] / Repressurisation phase duration [TIME]
END_VAR
VAR_OUTPUT
    xIsoValveCmd     : BOOL;   // 隔离阀关闭命令（安全侧：故障时保持关闭）[bool] / Isolation valve close command [bool]
    xVentCmd         : BOOL;   // 通气复压阀命令（安全侧：故障时关）[bool] / Vent valve command, fail-safe [bool]
    fLeakRateMbarLs  : REAL;   // 实测泄漏率 [mbar*L/s] / Measured leak rate [mbar*L/s]
    xTestPass        : BOOL;   // 测试合格（保持至撤令）[bool] / Test passed, held until release [bool]
    xDone            : BOOL;   // 测试完成保持位 [bool] / Test complete held flag [bool]
    xBusy            : BOOL;   // 测试进行中 [bool] / Test sequence busy [bool]
    eState           : E_DL_LyoPrTestState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId           : UDINT;  // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonIso           : TON;    // 隔离相正常定时 [TIME] / Isolation phase timer
    tonIsoOv         : TON;    // 隔离相超时定时 [TIME] / Isolation phase overrun timer
    tonSettle        : TON;    // 稳压相正常定时 [TIME] / Settle phase timer
    tonSettleOv      : TON;    // 稳压相超时定时 [TIME] / Settle phase overrun timer
    tonTiming        : TON;    // 计时相正常定时 [TIME] / Timing phase timer
    tonTimingOv      : TON;    // 计时相超时定时 [TIME] / Timing phase overrun timer
    tonRepress       : TON;    // 复压相正常定时 [TIME] / Repressurisation phase timer
    tonRepressOv     : TON;    // 复压相超时定时 [TIME] / Repressurisation phase overrun timer
    tonTotal         : TON;    // 整序总超时定时 [TIME] / Whole-sequence total timeout timer
    rtStart          : R_TRIG; // 启动上升沿检测 [bool] / Start rising edge detector
    rtReset          : R_TRIG; // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState          : E_DL_LyoPrTestState := E_DL_LyoPrTestState.eLyoPrIdle;   // 内部相位（CASE 唯一写入目标）
    _fPressStartMbar : REAL := 0.0;   // 计时相起点压力快照 [mbar] / Base pressure captured at timing start
    _fLeakRaw        : REAL := 0.0;   // 钳制前的原始泄漏率 [mbar*L/s] / Raw leak rate before limiting [mbar*L/s]
    _tElapsed        : TIME := T#0S;  // 计时相实际经过时间 [TIME] / Actual elapsed timing phase duration [TIME]
    _fElapsedS       : REAL := 0.0;   // 计时相实际经过时间折算 [s] / Elapsed timing duration in seconds [s]
    _bFinOk          : BOOL := FALSE; // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bVacOk          : BOOL := FALSE; // 起始真空度达成 [bool] / Base vacuum reached flag [bool]
    _bActive         : BOOL := FALSE; // 测试序激活（隔离至复压四相之一）[bool] / Sequence active flag [bool]
    _bPassL          : BOOL := FALSE; // 合格位锁存（跨相保持）[bool] / Pass latch held across phases [bool]
    _bDoneL          : BOOL := FALSE; // 完成位锁存（跨相保持）[bool] / Done latch held across phases [bool]
    _bFault          : BOOL := FALSE; // 故障锁存位 [bool] / Latched fault flag [bool]
    _uInfo           : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault          : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;      // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_VAC_MIN     : REAL := 1.0;         // 起始真空度门槛（压力须低于此值）[mbar] / Base vacuum pressure ceiling [mbar]
    DL_OVER_MARGIN : TIME := T#30S;       // 相超时相对正常定时的裕量 [TIME] / Phase overrun margin [TIME]
    DL_ISO_MAX     : TIME := T#20S;       // 隔离阀动作窗口 [TIME] / Isolation valve travel window [TIME]
    DL_TOTAL_MAX   : TIME := T#2H;        // 整序总超时上限 [TIME] / Whole-sequence total timeout [TIME]
    DL_MS_PER_S    : REAL := 1000.0;      // 毫秒到秒的折算 [ms/s] / Milliseconds per second [ms/s]
    DL_LEAK_HI     : REAL := 100.0;       // 泄漏率物理上限 [mbar*L/s] / Leak rate physical upper bound [mbar*L/s]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bPassL/_bDoneL/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸（R19：不拿 NaN 去比较真空度） —— *)
_bFinOk := (fChamberPressMbar > -DL_BIG) AND (fChamberPressMbar < DL_BIG)
           AND (fVolumeL > -DL_BIG) AND (fVolumeL < DL_BIG)
           AND (fLeakMaxMbarLs > -DL_BIG) AND (fLeakMaxMbarLs < DL_BIG);

(* —— 段 2：派生态（真空度达成、序激活、计时换算） —— *)
_bVacOk := _bFinOk AND (fChamberPressMbar <= DL_VAC_MIN);      // 压力低于门槛才算达起始真空
_bActive := (_eState = E_DL_LyoPrTestState.eLyoPrIsolate)
            OR (_eState = E_DL_LyoPrTestState.eLyoPrSettle)
            OR (_eState = E_DL_LyoPrTestState.eLyoPrTiming)
            OR (_eState = E_DL_LyoPrTestState.eLyoPrRepress);
_tElapsed := tonTiming.ET;                                     // 计时相已运行时间（读上拍值，安全）
_fElapsedS := TIME_TO_REAL(_tElapsed) / DL_MS_PER_S;           // 毫秒数折算为秒 [s]（单点赋值，R26）

(* —— 段 3：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := xStart);                                                                 // 启动上升沿，每拍必调
rtReset(CLK := xReset);                                                                 // 复位上升沿，每拍必调
tonIso(IN := (_eState = E_DL_LyoPrTestState.eLyoPrIsolate), PT := DL_ISO_MAX);          // 隔离相阀动作窗口
tonIsoOv(IN := (_eState = E_DL_LyoPrTestState.eLyoPrIsolate), PT := DL_ISO_MAX + DL_OVER_MARGIN);  // 隔离相超时点
tonSettle(IN := (_eState = E_DL_LyoPrTestState.eLyoPrSettle), PT := tSettleS);          // 稳压相正常定时
tonSettleOv(IN := (_eState = E_DL_LyoPrTestState.eLyoPrSettle),
            PT := tSettleS + DL_OVER_MARGIN);                                           // 稳压相超时点
tonTiming(IN := (_eState = E_DL_LyoPrTestState.eLyoPrTiming), PT := tTestS);            // 计时相正常定时
tonTimingOv(IN := (_eState = E_DL_LyoPrTestState.eLyoPrTiming),
            PT := tTestS + DL_OVER_MARGIN);                                             // 计时相超时点
tonRepress(IN := (_eState = E_DL_LyoPrTestState.eLyoPrRepress), PT := tRepressS);       // 复压相正常定时
tonRepressOv(IN := (_eState = E_DL_LyoPrTestState.eLyoPrRepress),
             PT := tRepressS + DL_OVER_MARGIN);                                         // 复压相超时点
tonTotal(IN := _bActive, PT := DL_TOTAL_MAX);                                           // 整序总超时

(* —— 段 4：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0227;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_LyoPrTestState.eLyoPrFault;
END_IF
IF (NOT _bFinOk) AND (NOT _bFault) THEN
    _uFault := 16#0091_0228;                // 故障级：入参非有限
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoPrTestState.eLyoPrFault;
END_IF
IF tonTotal.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0091_0226;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoPrTestState.eLyoPrFault;
END_IF

(* —— 段 5：相位机（只做迁移与锁存；出口在段 7 单点映射） —— *)
CASE _eState OF

E_DL_LyoPrTestState.eLyoPrIdle:
    IF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令即清完成位，为下次测试重新武装
        _bPassL := FALSE;                   // 合格位一并清
    ELSIF NOT _bVacOk THEN
        _uInfo := 16#0091_0221;             // 信息级：未达起始真空度，禁止启动（不置故障位）
    ELSIF rtStart.Q THEN
        _bDoneL := FALSE;                   // 新序开始：清完成位
        _bPassL := FALSE;                   // 新序开始：清合格位
        _eState := E_DL_LyoPrTestState.eLyoPrIsolate;         // 进隔离相
    END_IF

E_DL_LyoPrTestState.eLyoPrIsolate:
    IF NOT xStart THEN
        _uFault := 16#0091_0227;            // 故障级：测试中撤令，按外部中断归因
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoPrTestState.eLyoPrFault;
    ELSIF tonIsoOv.Q THEN
        _uFault := 16#0091_0222;            // 故障级：隔离相超时（隔离阀未关到位）
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoPrTestState.eLyoPrFault;
    ELSIF xIsoValveClosedFb THEN
        _eState := E_DL_LyoPrTestState.eLyoPrSettle;          // 阀关到位：本拍事件优先于超时迁移（R275）
    END_IF

E_DL_LyoPrTestState.eLyoPrSettle:
    IF tonSettleOv.Q THEN
        _uFault := 16#0091_0223;            // 故障级：稳压相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoPrTestState.eLyoPrFault;
    ELSIF tonSettle.Q THEN
        _fPressStartMbar := fChamberPressMbar;                // 计时相起点压力快照（迁移前一次性捕获）
        _eState := E_DL_LyoPrTestState.eLyoPrTiming;          // 进计时相
    END_IF

E_DL_LyoPrTestState.eLyoPrTiming:
    IF tonTimingOv.Q THEN
        _uFault := 16#0091_0224;            // 故障级：计时相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoPrTestState.eLyoPrFault;
    ELSIF tonTiming.Q THEN
        _eState := E_DL_LyoPrTestState.eLyoPrJudge;           // 计时到：进判定相
    END_IF

E_DL_LyoPrTestState.eLyoPrJudge:
    IF (_fElapsedS <= DL_EPS) OR (fVolumeL <= DL_EPS) THEN
        _uFault := 16#0091_0224;            // 故障级：实际计时为零或容积未组态，泄漏率不可算
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoPrTestState.eLyoPrFault;
    ELSE
        _fLeakRaw := (fChamberPressMbar - _fPressStartMbar) * fVolumeL / _fElapsedS;   // 泄漏率 [mbar*L/s]
        IF (_fLeakRaw < 0.0) OR (_fLeakRaw > fLeakMaxMbarLs) THEN
            _uFault := 16#0091_0229;        // 故障级：升压为负（隔离失效）或泄漏率超限
            _bFault := TRUE;                // 锁存
            _eState := E_DL_LyoPrTestState.eLyoPrFault;
        ELSE
            _bPassL := TRUE;                // 合格锁存
            _eState := E_DL_LyoPrTestState.eLyoPrRepress;     // 进复压相
        END_IF
    END_IF

E_DL_LyoPrTestState.eLyoPrRepress:
    IF tonRepressOv.Q THEN
        _uFault := 16#0091_0225;            // 故障级：复压相超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoPrTestState.eLyoPrFault;
    ELSIF tonRepress.Q THEN
        _bDoneL := TRUE;                    // 完成位锁存（跨相保持，段 7 单点映射）
        _eState := E_DL_LyoPrTestState.eLyoPrDone;            // 进完成相
    END_IF

E_DL_LyoPrTestState.eLyoPrDone:
    IF xFault THEN
        _uFault := 16#0091_0227;            // 故障级：完成后外部故障（段 4 已拦，此处兜底同码）
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_LyoPrTestState.eLyoPrFault;
    ELSIF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令：清完成位并回待机
        _eState := E_DL_LyoPrTestState.eLyoPrIdle;
    END_IF

E_DL_LyoPrTestState.eLyoPrFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参有限（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bDoneL := FALSE;                   // 完成位清
        _bPassL := FALSE;                   // 合格位清，避免故障后误报合格
        _fLeakRaw := 0.0;                   // 泄漏率读数清（故障数据不得留作趋势）
        _eState := E_DL_LyoPrTestState.eLyoPrIdle;            // 回待机，需新上升沿才可再测
    END_IF

ELSE
    _uFault := 16#0091_0230;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoPrTestState.eLyoPrFault;               // 强制回故障相

END_CASE

(* —— 段 6：后置段（泄漏率读数域兜底：非有限即清零，防污染趋势记录） —— *)
IF NOT (_fLeakRaw > -DL_BIG AND _fLeakRaw < DL_BIG) THEN
    _fLeakRaw := 0.0;                       // 内部状态自检：非有限即清零
END_IF

(* —— 段 7：出口单点映射（名实同源；阀门由状态导出，故障侧一律关阀） —— *)
xIsoValveCmd := ((_eState = E_DL_LyoPrTestState.eLyoPrIsolate)
                 OR (_eState = E_DL_LyoPrTestState.eLyoPrSettle)
                 OR (_eState = E_DL_LyoPrTestState.eLyoPrTiming)
                 OR (_eState = E_DL_LyoPrTestState.eLyoPrJudge)
                 OR (_eState = E_DL_LyoPrTestState.eLyoPrRepress)) AND (NOT _bFault);   // 隔离阀：五相关闭
xVentCmd := (_eState = E_DL_LyoPrTestState.eLyoPrRepress) AND (NOT _bFault);             // 通气阀：仅复压相开
fLeakRateMbarLs := LIMIT(0.0, _fLeakRaw, DL_LEAK_HI);                                    // 泄漏率钳 0..物理上限
xTestPass := _bPassL AND (NOT _bFault);                                                  // 合格位出口
xDone := _bDoneL AND (NOT _bFault);                                                      // 完成位出口
xBusy := _bActive AND (NOT _bFault);                                                     // 进行中出口
eState := _eState;                                                                       // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
