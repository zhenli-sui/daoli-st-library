(*
  组件名 Component   : FB_DL_RelayAutoTune
  子库 Sublibrary    : DL_Algo
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 继电器反馈法 PID 自整定（只出参数、不闭环）：
                       1) 继电器试验：被控量低于（设定值-迟滞）输出继电器上限，高于
                       （设定值+迟滞）输出继电器下限，形成极限环；
                       2) 极限环测量：继电器同向切换沿间隔 = 振荡周期 Tu，切换沿间
                       被控量峰谷差 / 2 = 振荡幅值 a；
                       3) 临界增益 Ku = 4d / (π·a)（幅值近零前置拦截，不进入除法）；
                       4) Ziegler-Nichols 公开判据初值：Kp = 0.6Ku，Ti = 0.5Tu，Td = 0.125Tu；
                       5) 连续 3 个完整振荡周期取均值后才出参数，试验无切换超时即判故障。
  边界 Boundary      : ① 本件只出初值参数，不接管回路闭环（上层自选时机装载）；
                       ② 振幅近零（a < 容差）→ 故障锁存：被控量不振荡，Ku 无意义；
                       ③ 幅值测量在切换沿间闭环刷新，峰谷快照在切换沿复归；
                       ④ 试验超时计时以切换沿重启（bGuardHold 单拍驻留，见段 0 注释）；
                       ⑤ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑥ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-5-modpid 参数域与公开 Ziegler-Nichols
                       判据文献语义，零代码行复制）
  码位 Code          : 16#02_3_8D
  码表 Error codes（Algo 格 02_3_8D，单轨：故障 0x038D / 信息 0x028D）:
    16#0002_038D 故障级：试验非法（无切换超时 / 振幅近零 / 组态非法 / 输入非有限），
                 锁存至 bReset 上升沿
    16#0002_028D 信息级：整定完成沿（参数写定拍，锁存至 bReset）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 1 · 序号 3）
*)

TYPE E_DL_RatState :
(
    eIdle  := 0,    // 空闲：等启动沿 / Idle, waiting start edge
    eTune  := 10,   // 试验：继电器极限环运行中 / Tuning, relay limit cycle running
    eDone  := 20,   // 完成：参数驻留待装载 / Done, parameters held
    eFault := 90    // 故障：试验非法锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_RelayAutoTune
VAR_INPUT
    bStartCmd  : BOOL;                     // 启动沿（试验以上升沿承载）[-] / Start command edge
    bReset     : BOOL;                     // 上升沿清故障与完成结果 [-] / Reset edge
    fPv        : REAL;                     // 被控量 [工程单位] / Process variable
    fBiasPv    : REAL;                     // 继电器中心（目标值）[工程单位] / Relay bias point
    fHysteresis: REAL := 1.0;              // 继电器迟滞半宽 [工程单位] / Relay hysteresis half band
    fRelayHi   : REAL := 100.0;            // 继电器上限输出 [%] / Relay high output
    fRelayLo   : REAL := 0.0;              // 继电器下限输出 [%] / Relay low output
    fRelayAmp  : REAL := 5.0;              // 继电器幅值 d = (上限-下限)/2 [%] / Relay amplitude d
    tGuardTo   : TIME := T#120S;           // 无切换超时 [毫秒]，以切换沿重启 / No-switch timeout
    tCycle     : TIME := T#10MS;           // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    fRelayOut  : REAL;                     // 试验期继电器输出 [%]，空闲相 0 / Relay output during test
    bTuning    : BOOL;                     // 试验进行中标志 [-] / Tuning active flag
    bDone      : BOOL;                     // 整定完成锁存标志 [-] / Tune done latch
    fKpInit    : REAL;                     // Z-N 初值比例增益 [无量纲] / ZN initial Kp
    fTiInit    : REAL;                     // Z-N 初值积分时间 [秒] / ZN initial Ti
    fTdInit    : REAL;                     // Z-N 初值微分时间 [秒] / ZN initial Td
    fTuMeas    : REAL;                     // 实测振荡周期 [秒] / Measured ultimate period
    fKuMeas    : REAL;                     // 实测临界增益 [无量纲] / Measured ultimate gain
    eState     : E_DL_RatState;            // 状态出口，段尾单点映射 / State outlet
    bError     : BOOL;                     // 故障锁存标志 [-] / Fault latch flag
    uErrId     : UDINT;                    // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtStart    : R_TRIG;                   // 启动沿实例，段 0 无条件刷新 / Start edge
    rtReset    : R_TRIG;                   // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtRelayHi  : R_TRIG;                   // 继电器上沿实例，段 0 无条件刷新 / Relay rising edge
    rtRelayLo  : R_TRIG;                   // 继电器下沿实例，段 0 无条件刷新 / Relay falling edge
    tonGuardTo : TON;                      // 无切换超时（专用超时件（R228A 合法豁免命名）） / No-switch timeout
    _eState    : E_DL_RatState := E_DL_RatState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _bRelHi    : BOOL;                     // 继电器上电平（迟滞内部态）[-] / Relay high level state
    _fPk       : REAL;                     // 本周期峰快照 [工程单位] / Peak snapshot
    _fVl       : REAL;                     // 本周期谷快照 [工程单位] / Valley snapshot
    _fAmpSum   : REAL;                     // 幅值累加 [工程单位] / Amplitude accumulator
    _fTuSum    : REAL;                     // 周期累加 [秒] / Period accumulator
    _fTuCur    : REAL;                     // 本周期秒计 [秒] / Current period seconds
    _nCyc      : DINT;                     // 切换沿计数 [个] / Switch edge count
    _fAmpAvg   : REAL;                     // 幅值均值 [工程单位] / Amplitude average
    _bGuardHold: BOOL;                     // 超时重启驻留（切换沿置位，下拍段 1 清除）[-] / Guard restart hold
    _bFault    : BOOL;                     // 故障锁存位（锁存量） / Latched fault bit
    _uFault    : UDINT;                    // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad   : BOOL;                     // 组态非法当拍量 [-] / Config illegal flag
    _fCyS      : REAL;                     // 扫描周期秒值 [秒] / Cycle seconds
END_VAR
VAR CONSTANT
    DL_CYC_REQ  : INT   := 3;              // 取均值所需完整周期数 [个] / Cycles to average
    DL_EDGES_REQ: DINT  := 6;              // 完整周期对应切换沿数 = 2 × 周期数 [个] / Required edges
    DL_ZN_KP    : REAL  := 0.6;            // Z-N 比例判据系数 [无量纲] / ZN Kp coefficient
    DL_ZN_TI    : REAL  := 0.5;            // Z-N 积分判据系数 [无量纲] / ZN Ti coefficient
    DL_ZN_TD    : REAL  := 0.125;          // Z-N 微分判据系数 [无量纲] / ZN Td coefficient
    DL_PI       : REAL  := 3.14159265;     // 圆周率 [无量纲] / Pi constant
    DL_AMP_MIN  : REAL  := 1.0E-6;         // 幅值近零判据 [工程单位] / Amplitude near-zero threshold
    DL_AMP_FACT : REAL  := 4.0;            // Ku = 4d/(π·a) 分子系数 [无量纲] / Ku numerator factor
    DL_HALF     : REAL  := 0.5;            // 峰谷差折半系数 [无量纲] / Half factor
    DL_KU_MIN   : REAL  := 1.0E-6;         // 临界增益下限护栏 [无量纲] / Ku floor
    DL_ABS_MAX  : REAL  := 1.0E30;         // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO     : REAL  := 0.0;            // 零常量 [工程单位] / Zero constant
    DL_TWO      : REAL  := 2.0;            // 二常量 [无量纲] / Two constant
    DL_MS_PER_S : REAL  := 1000.0;         // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内；bGuardHold 切换沿置位、
        下拍段 1 清除，tonGuardTo 以此实现逐切换沿重启，IN 两拍一断合法复位） —— *)
rtStart  (CLK := bStartCmd);
rtReset  (CLK := bReset);
rtRelayHi(CLK := _bRelHi);
rtRelayLo(CLK := NOT _bRelHi);
tonGuardTo(IN := (_eState = E_DL_RatState.eTune) AND (NOT _bGuardHold), PT := tGuardTo);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/bDone/_bRelHi 不入清单） —— *)
_bGuardHold := FALSE;                    // 超时重启驻留只驻留一拍
_bCfgBad    := FALSE;
uErrId      := 16#0000_0000;
_fCyS       := TIME_TO_REAL(tCycle) / DL_MS_PER_S;

(* —— 段 2｜复位沿：故障、完成结果、测量累计一次性清干净 —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;
    _uFault  := 16#0000_0000;
    bDone    := FALSE;
    _nCyc    := 0;
    _fAmpSum := DL_ZERO;
    _fTuSum  := DL_ZERO;
    _fTuCur  := DL_ZERO;
    IF _eState = E_DL_RatState.eFault THEN
        _eState := E_DL_RatState.eIdle;  // eFault 迁出唯一属主 = rtReset.Q（可达）
    END_IF
END_IF

(* —— 段 3｜组态闸：迟滞/幅值/周期域与非有限值前置拦截 —— *)
IF (fHysteresis <= DL_ZERO) OR (fRelayAmp <= DL_ZERO) OR (tGuardTo = T#0S) OR (tCycle = T#0S)
   OR (fPv <> fPv) OR (fBiasPv <> fBiasPv) OR (fHysteresis > DL_ABS_MAX) THEN
    _bCfgBad := TRUE;
END_IF

(* —— 段 4｜主状态机：四态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_RatState.eIdle:
    fRelayOut := DL_ZERO;                // 空闲继电器输出回零（安全侧）
    IF _bFault THEN
        bError := TRUE;                  // 故障锁存回放（R189）
    END_IF
    IF rtStart.Q AND (NOT _bFault) AND (NOT _bCfgBad) THEN
        _bRelHi  := FALSE;               // 继电器从下限起振
        _fPk     := fPv;                 // 峰谷快照初始化
        _fVl     := fPv;
        _fTuCur  := DL_ZERO;
        _nCyc    := 0;
        _fAmpSum := DL_ZERO;
        _fTuSum  := DL_ZERO;
        bDone    := FALSE;
        _eState  := E_DL_RatState.eTune;
    ELSIF rtStart.Q AND (_bCfgBad OR _bFault) THEN
        _bFault := TRUE;                 // 带病启动拒绝
        _uFault := 16#0002_038D;
        bError  := TRUE;
        _eState := E_DL_RatState.eFault;
    END_IF

E_DL_RatState.eTune:
    bTuning := TRUE;
    (* 继电器迟滞逻辑：低于中心-迟滞输出上限，高于中心+迟滞输出下限 *)
    IF (NOT _bRelHi) AND (fPv < fBiasPv - fHysteresis) THEN
        _bRelHi := TRUE;
    ELSIF _bRelHi AND (fPv > fBiasPv + fHysteresis) THEN
        _bRelHi := FALSE;
    END_IF
    IF _bRelHi THEN
        fRelayOut := fRelayHi;
    ELSE
        fRelayOut := fRelayLo;
    END_IF

    (* 峰谷跟踪与周期秒计 *)
    IF fPv > _fPk THEN
        _fPk := fPv;
    END_IF
    IF fPv < _fVl THEN
        _fVl := fPv;
    END_IF
    _fTuCur := _fTuCur + _fCyS;

    IF rtRelayHi.Q OR rtRelayLo.Q THEN
        (* 切换沿：相邻沿间隔 × 2 = 一个完整振荡周期，幅值按沿取样 *)
        _fTuSum := _fTuSum + _fTuCur * DL_TWO;
        _fAmpSum := _fAmpSum + (_fPk - _fVl) * DL_HALF;
        _fTuCur  := DL_ZERO;
        _fPk     := fPv;                 // 峰谷快照按沿复归
        _fVl     := fPv;
        _bGuardHold := TRUE;             // 超时计时重启驻留（下拍断 IN）
        _nCyc := _nCyc + 1;
        IF _nCyc >= DL_EDGES_REQ THEN
            (* 收口：均值 → 临界参数 → Z-N 公开判据初值（除数 = 沿数 > 0 已由闸保证） *)
            _fAmpAvg := _fAmpSum / DINT_TO_REAL(_nCyc);
            IF _fAmpAvg < DL_AMP_MIN THEN
                _bFault := TRUE;         // 振幅近零：Ku 无意义
                _uFault := 16#0002_038D;
                bError  := TRUE;
                _eState := E_DL_RatState.eFault;
            ELSE
                fTuMeas := _fTuSum / DINT_TO_REAL(_nCyc);
                fKuMeas := (DL_AMP_FACT * fRelayAmp) / (DL_PI * _fAmpAvg);
                IF fKuMeas < DL_KU_MIN THEN
                    fKuMeas := DL_KU_MIN;            // 临界增益下限钳位
                END_IF
                fKpInit := DL_ZN_KP * fKuMeas;
                fTiInit := DL_ZN_TI * fTuMeas;
                fTdInit := DL_ZN_TD * fTuMeas;
                uErrId  := 16#0002_028D;     // 信息级：整定完成沿（锁存至复位）
                bDone   := TRUE;
                bTuning := FALSE;
                _eState := E_DL_RatState.eDone;
            END_IF
        END_IF
    END_IF

    IF tonGuardTo.Q THEN
        _bFault := TRUE;                 // 无切换超时：过程不振荡
        _uFault := 16#0002_038D;
        bError  := TRUE;
        bTuning := FALSE;
        fRelayOut := DL_ZERO;            // 安全侧回零
        _eState := E_DL_RatState.eFault;
    END_IF

E_DL_RatState.eDone:
    bTuning := FALSE;
    fRelayOut := DL_ZERO;                // 完成相继电器输出回零
    IF NOT bStartCmd THEN
        _eState := E_DL_RatState.eIdle;  // 启动指令撤销：回空闲（结果锁存保留）
    END_IF

E_DL_RatState.eFault:
    bTuning := FALSE;
    fRelayOut := DL_ZERO;
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 承载迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0002_038D;
    bError  := TRUE;
    _eState := E_DL_RatState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
