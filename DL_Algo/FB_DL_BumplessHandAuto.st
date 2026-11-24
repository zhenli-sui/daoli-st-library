(*
  组件名 Component   : FB_DL_BumplessHandAuto
  子库 Sublibrary    : DL_Algo
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 手/自动无扰切换（T0 标准语义件）：
                       1) 手动相：输出 = fManualOut，同时以自动需求做双向跟踪监督；
                       2) 切自动：切换偏差 |fAutoOut - 当前输出| <= fSwDevMaxPct 时直接无扰
                       切入；超限时经 eAutoRamp 相以 fSwRampPctS 斜率逼近自动需求后切入；
                       3) 切手动：输出立即跟随 fManualOut（跟踪量恒可用，无扰返回）；
                       4) 跟踪失效报警：手动相下执行器反馈偏离手动指令超 fTrackTolPct
                       持续 tTrackTo → 报警锁存（故障级，bReset 上升沿解除）。
  边界 Boundary      : ① 本件只做输出选择与切换监督，不内嵌 PID（需求由上层回路提供）；
                       ② 除法/斜率换算前置域闸：fSwRampPctS <= 0 判组态非法；
                       ③ 非有限值（NaN 自反 + 无穷差值自减）判输入非法，锁存安全侧；
                       ④ eAutoRamp 相退出双条件：偏差入容差（达成）或需求翻转回手动；
                       ⑤ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑥ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : IEC 61131-3 标准语义的道莅防御性实现（双向跟踪无扰切换为标准
                       控制回路手/自动语义，T0 口径）
  码位 Code          : 16#02_3_8B
  码表 Error codes（Algo 格 02_3_8B，单轨：故障 0x038B / 信息 0x028B）:
    16#0002_038B 故障级：跟踪失效锁存（手动相反馈偏离超容差持续 tTrackTo）或
                 组态非法/输入非有限，锁存至 bReset 上升沿
    16#0002_028B 信息级：斜坡切入自动沿（eAutoRamp → eAuto 迁移拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 1 · 序号 4）
*)

TYPE E_DL_BhaState :
(
    eManual   := 0,    // 手动：输出跟随手动指令 / Manual, output follows hand command
    eAutoRamp := 10,   // 斜坡：输出限速逼近自动需求 / Ramp, output slews to auto demand
    eAuto     := 20,   // 自动：输出 = 自动需求 / Auto, output equals auto demand
    eFault    := 90    // 故障：跟踪失效或组态锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_BumplessHandAuto
VAR_INPUT
    bAutoMode   : BOOL;                    // 自动模式请求（电平）[-] / Auto mode request
    bReset      : BOOL;                    // 上升沿清故障锁存 [-] / Reset edge
    fAutoOut    : REAL;                    // 自动需求（上层回路输出）[%] / Auto demand
    fManualOut  : REAL;                    // 手动指令 [%] / Manual command
    fFbPos      : REAL;                    // 执行器反馈位置 [%] / Actuator feedback
    fSwDevMaxPct: REAL := 10.0;            // 直接切换允许偏差 [%] / Direct switch deviation limit
    fSwRampPctS : REAL := 20.0;            // 斜坡切入速率 [%/秒] / Switch slew rate
    fTrackTolPct: REAL := 5.0;             // 跟踪容差 [%] / Tracking tolerance
    tTrackTo    : TIME := T#5S;            // 跟踪失效确认窗 [毫秒] / Tracking fail confirm window
    tCycle      : TIME := T#10MS;          // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    fOut        : REAL;                    // 选择输出 [%] / Selected output
    bAuto       : BOOL;                    // 自动相电平标志 [-] / Auto state level
    bRamping    : BOOL;                    // 斜坡相电平标志 [-] / Ramping state level
    bError      : BOOL;                    // 故障锁存标志 [-] / Fault latch flag
    uErrId      : UDINT;                   // 事件码，0 = 无事件 / Event code
    eState      : E_DL_BhaState;           // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR
    rtReset     : R_TRIG;                  // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtToAuto    : R_TRIG;                  // 切自动沿实例，段 0 无条件刷新 / To-auto edge
    rtToManual  : R_TRIG;                  // 切手动沿实例，段 0 无条件刷新 / To-manual edge
    tonTrackTo  : TON;                     // 跟踪失效确认（专用超时件命名（R228A 豁免））/ Tracking timeout
    _eState     : E_DL_BhaState := E_DL_BhaState.eManual;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fDev       : REAL;                    // 切换偏差绝对值 [%] / Switch deviation
    _fFbDev     : REAL;                    // 跟踪偏差绝对值 [%] / Tracking deviation
    _fStep      : REAL;                    // 本拍斜坡步长 [%] / Slew step per scan
    _fCyS       : REAL;                    // 扫描周期秒值 [秒] / Cycle seconds
    _bFault     : BOOL;                    // 故障锁存位（锁存量） / Latched fault bit
    _uFault     : UDINT;                   // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad    : BOOL;                    // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin    : BOOL;                    // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_DEV_EPS  : REAL := 1.0E-6;          // 偏差入容差判据 [％] / Deviation snap tolerance
    DL_ABS_MAX  : REAL := 1.0E30;          // 有限值判定上界 [%] / Finite value bound
    DL_ZERO     : REAL := 0.0;             // 零常量 [%] / Zero constant
    DL_MS_PER_S : REAL := 1000.0;          // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内） —— *)
_fFbDev := ABS(fFbPos - fManualOut);     // 跟踪偏差先行计算，供定时器 IN 引用
rtReset   (CLK := bReset);
rtToAuto  (CLK := bAutoMode);
rtToManual(CLK := NOT bAutoMode);
tonTrackTo(IN := (_eState = E_DL_BhaState.eManual) AND (_fFbDev > fTrackTolPct) AND (NOT _bFault),
           PT := tTrackTo);

(* —— 段 1｜瞬时量预清零与周期换算（锁存量 _bFault/_uFault 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
_fCyS    := TIME_TO_REAL(tCycle) / DL_MS_PER_S;

(* —— 段 2｜复位沿：故障一次性清干净，相位回手动（安全侧待机） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eState := E_DL_BhaState.eManual;    // 复位后回手动待机，由沿重新切入自动
END_IF

(* —— 段 3｜组态闸与输入非有限判据 —— *)
IF (fSwRampPctS <= DL_ZERO) OR (fSwDevMaxPct < DL_ZERO) OR (fTrackTolPct <= DL_ZERO)
   OR (tCycle = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fAutoOut <> fAutoOut) OR ((fAutoOut - fAutoOut) <> DL_ZERO)
   OR (fManualOut <> fManualOut) OR ((fManualOut - fManualOut) <> DL_ZERO)
   OR (fFbPos <> fFbPos) OR ((fFbPos - fFbPos) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜故障触发：组态/输入非法或跟踪失效（tonTrackTo.Q 为保持量级判据） —— *)
IF _bCfgBad OR _bNonFin THEN
    _bFault := TRUE;
    _uFault := 16#0002_038B;
    _eState := E_DL_BhaState.eFault;
ELSIF (_eState = E_DL_BhaState.eManual) AND tonTrackTo.Q THEN
    _bFault := TRUE;                     // 手动相跟踪失效：反馈偏离超容差持续超窗
    _uFault := 16#0002_038B;
    _eState := E_DL_BhaState.eFault;
END_IF

(* —— 段 5｜主状态机：四态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_BhaState.eManual:
    fOut   := fManualOut;                // 输出跟随手动指令
    bAuto  := FALSE;
    bRamping := FALSE;
    ;                                    // 跟踪监督判据 _fFbDev 已在段 0 预算，经 tonTrackTo 承载
    IF rtToAuto.Q AND (NOT _bFault) THEN
        _fDev := ABS(fAutoOut - fOut);
        IF _fDev <= fSwDevMaxPct THEN
            _eState := E_DL_BhaState.eAuto;      // 小偏差直接无扰切入
        ELSE
            _eState := E_DL_BhaState.eAutoRamp;  // 大偏差限速逼近
        END_IF
    END_IF

E_DL_BhaState.eAutoRamp:
    bAuto    := FALSE;
    bRamping := TRUE;
    _fStep   := fSwRampPctS * _fCyS;     // 本拍步长 = 速率 × 周期
    IF fOut < fAutoOut THEN
        fOut := MIN(fOut + _fStep, fAutoOut);    // 上行逼近，不越过需求
    ELSIF fOut > fAutoOut THEN
        fOut := MAX(fOut - _fStep, fAutoOut);    // 下行逼近，不越过需求
    END_IF
    IF ABS(fAutoOut - fOut) <= DL_DEV_EPS THEN
        uErrId  := 16#0002_028B;         // 信息级：斜坡切入自动沿
        _eState := E_DL_BhaState.eAuto;  // 迁出条件 1：偏差达成
    ELSIF rtToManual.Q THEN
        _eState := E_DL_BhaState.eManual;    // 迁出条件 2：需求翻转回手动
    END_IF

E_DL_BhaState.eAuto:
    fOut      := fAutoOut;               // 输出 = 自动需求
    bAuto     := TRUE;
    bRamping  := FALSE;
    IF rtToManual.Q THEN
        _eState := E_DL_BhaState.eManual;    // 无扰返回：手动相输出立即跟手
    END_IF

E_DL_BhaState.eFault:
    bError := TRUE;                      // 故障相驻留：出口冻结保持，只认复位沿（段 2 迁出）
    ;                                    // （故障相 fOut 保持最后值，禁止任何迁移）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0002_038B;
    bError  := TRUE;
    _eState := E_DL_BhaState.eFault;
END_CASE

(* —— 段 6｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
