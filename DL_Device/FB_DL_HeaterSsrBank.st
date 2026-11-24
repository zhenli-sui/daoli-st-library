(*
  组件名 Component   : FB_DL_HeaterSsrBank
  子库 Sublibrary    : DL_Device
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : SSR 调功器组（多路时间比例调功 + 均衡 + 断偶降级）：
                       1) 分相输出：各路按 (i-1)/路数 错相起始的时间比例调功（占空比
                       比较内部锯齿相位），错相拉开路间电流峰值，降低电网冲击；
                       2) 路间电流均衡：有效路平均电流基准，单路偏差超 fImbalMaxPct
                       → 均衡告警锁存（维护语义）；
                       3) 断偶/断路降级：占空比高于发波下限而电流低于检测阈，持续
                       tBreakTo 确认 → 该路断偶锁存，出口强制关断（单路降级，其余照常）；
                       4) 每路断偶确认用独立 TON 实例（数组实例，段 0 FOR 无条件刷新）。
  边界 Boundary      : ① 本件只出各路 SSR 开关量与诊断，不写物理 IO；
                       ② 占空比域 [0, 100]，域外钳位 + 均衡告警不置 bError（维护级），
                       断偶锁存置 bError（故障级，bReset 上升沿解除）；
                       ③ 相位换算除法前置域闸：路数域 [1, 8]、周期 > 0；
                       ④ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-2-lbp 三段分层分类与参数域，
                       零代码行复制）
  码位 Code          : 16#03_3_1（Device 05xx 副带 0531）
  码表 Error codes（Device 故障窗口 0531，本件无信息码，单故障总码 + 成因枚举归因）:
    16#0003_0531 故障级：SSR 组故障总码（任一路断偶锁存 / 组态非法 / 输入非有限），
                 锁存至 bReset 上升沿，归因见 eCause 与 abChBreak 分量
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 3 · 序号 13）
*)

TYPE E_DL_HsbState :
(
    eIdle  := 0,    // 空闲：未使能，全路关断 / Idle, all channels off
    eRun   := 10,   // 运行：分相发波 + 诊断 / Running, phased firing and diagnostics
    eFault := 90    // 故障：总码锁存 / Fault, latched
);
END_TYPE

TYPE E_DL_HsbCause :
(
    eNone      := 0,  // 无故障成因 / No cause
    eChBreak   := 1,  // 任一路断偶锁存 / Any channel break latched
    eCfgIllegal:= 2,  // 组态非法 / Illegal configuration
    eNonFinite := 3   // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeaterSsrBank
VAR_INPUT
    bEnable    : BOOL;                     // 使能（电平）[-] / Enable
    bReset     : BOOL;                     // 上升沿清故障锁存 [-] / Reset edge
    nChUse     : INT := 4;                 // 有效路数 [路]，域 1..8 / Active channel count
    afDutyPct  : ARRAY[1..8] OF REAL;      // 各路占空比 [%]，域 0..100 / Duty per channel
    afCurrentA : ARRAY[1..8] OF REAL;      // 各路实测电流 [安培] / Current per channel
    fImbalMaxPct: REAL := 20.0;            // 均衡偏差限 [%] / Imbalance limit
    fBreakDetectA: REAL := 0.5;            // 断偶电流检测阈 [安培] / Break detect threshold
    tPhaseCycle: TIME := T#1S;             // 时间比例周期 [毫秒] / Time-proportional cycle
    tBreakTo   : TIME := T#3S;             // 断偶确认窗 [毫秒] / Break confirm window
END_VAR
VAR_OUTPUT
    abSsrOut   : ARRAY[1..8] OF BOOL;      // 各路 SSR 开关量输出 [-] / SSR output per channel
    abChBreak  : ARRAY[1..8] OF BOOL;      // 各路断偶锁存位 [-] / Break latch per channel
    bImbalAlm  : BOOL;                     // 均衡告警锁存位 [-] / Imbalance alarm latch
    nBreakCount: INT;                      // 断偶路数 [路] / Broken channel count
    eState     : E_DL_HsbState;            // 状态出口，段尾单点映射 / State outlet
    eCause     : E_DL_HsbCause;            // 故障成因出口（R190） / Fault cause outlet
    bError     : BOOL;                     // 故障锁存标志 [-] / Fault latch flag
    uErrId     : UDINT;                    // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset  : R_TRIG;                     // 复位沿实例，段 0 无条件刷新 / Reset edge
    atonBreak: ARRAY[1..8] OF TON;         // 各路断偶确认实例（数组，段 0 无条件刷新）/ Break timers
    _tPhase  : TIME := T#0S;               // 锯齿相位 [毫秒] / Sawtooth phase
    _eState  : E_DL_HsbState := E_DL_HsbState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _eCause  : E_DL_HsbCause := E_DL_HsbCause.eNone;   // 故障成因锁存（锁存量）/ Latched cause
    _fPhaseMs: REAL;                       // 相位毫秒值 [毫秒] / Phase in milliseconds
    _fWinMs  : REAL;                       // 周期毫秒值 [毫秒] / Cycle in milliseconds
    _fDutyUse: REAL;                       // 单路钳位占空比 [%] / Clamped duty
    _fAvgA   : REAL;                       // 有效路平均电流 [安培] / Average current
    _nAvgCnt : INT;                        // 有效路计数 [路] / Averaged channel count
    _fImbal  : REAL;                       // 单路偏差 [%] / Per channel imbalance
    _nIdx    : INT;                        // 路索引 [-] / Channel index
    _bFault  : BOOL;                       // 故障锁存位（锁存量） / Latched fault bit
    _uFault  : UDINT;                      // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad : BOOL;                       // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin : BOOL;                       // 输入非有限当拍量 [-] / Non-finite input flag
    _bImbal  : BOOL;                       // 均衡越限当拍量 [-] / Imbalance breach flag
END_VAR
VAR CONSTANT
    DL_CH_MAX   : INT  := 8;               // 路数上限，与数组维度一致 [路] / Channel ceiling
    DL_CH_MIN   : INT  := 1;               // 路数下限 [路] / Channel floor
    DL_DUTY_MAX : REAL := 100.0;           // 占空比上限 [%] / Duty ceiling
    DL_DUTY_MIN : REAL := 0.0;             // 占空比下限 [%] / Duty floor
    DL_DUTY_ONMIN: REAL := 10.0;           // 断偶判据发波下限 [%] / Duty floor for break test
    DL_100      : REAL := 100.0;           // 百分比换算系数 [无量纲] / Percent scale
    DL_ZERO     : REAL := 0.0;             // 零常量 [工程单位] / Zero constant
    DL_ABS_MAX  : REAL := 1.0E30;          // 有限值判定上界 [工程单位] / Finite bound
END_VAR

(* —— 段 0｜沿、相位与定时器每拍无条件刷新（数组实例 FOR 全量刷新，禁置于 CASE 内） —— *)
rtReset(CLK := bReset);
_tPhase := _tPhase + tPhaseCycle;        // 锯齿相位累加（周期性推进）
IF _tPhase >= tPhaseCycle THEN
    _tPhase := _tPhase - tPhaseCycle;    // 相位回卷（差值比较，非取模）
END_IF
_fPhaseMs := TIME_TO_REAL(_tPhase);
_fWinMs   := TIME_TO_REAL(tPhaseCycle);
FOR _nIdx := DL_CH_MIN TO DL_CH_MAX DO
    atonBreak[_nIdx](IN := (_eState = E_DL_HsbState.eRun) AND (NOT _bFault)
                     AND (afDutyPct[_nIdx] >= DL_DUTY_ONMIN)
                     AND (afCurrentA[_nIdx] < fBreakDetectA), PT := tBreakTo);
END_FOR

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/abChBreak/bImbalAlm 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
_bImbal  := FALSE;
nBreakCount := 0;
_fAvgA   := DL_ZERO;
_nAvgCnt := 0;

(* —— 段 2｜复位沿：故障与全路断偶锁存一次性清干净（唯一解除路径 = rtReset.Q，
        输入引脚当拍量，调用方拉上升沿即可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eCause := E_DL_HsbCause.eNone;
    bImbalAlm := FALSE;
    FOR _nIdx := DL_CH_MIN TO DL_CH_MAX DO
        abChBreak[_nIdx] := FALSE;
    END_FOR
    _eState := E_DL_HsbState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与判据换算引脚） —— *)
IF (nChUse < DL_CH_MIN) OR (nChUse > DL_CH_MAX) OR (tPhaseCycle = T#0S)
   OR (fImbalMaxPct <= DL_ZERO) OR (fBreakDetectA <= DL_ZERO) OR (tBreakTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
FOR _nIdx := DL_CH_MIN TO DL_CH_MAX DO
    IF (afDutyPct[_nIdx] <> afDutyPct[_nIdx]) OR ((afDutyPct[_nIdx] - afDutyPct[_nIdx]) <> DL_ZERO)
       OR (afCurrentA[_nIdx] <> afCurrentA[_nIdx]) OR ((afCurrentA[_nIdx] - afCurrentA[_nIdx]) <> DL_ZERO) THEN
        _bNonFin := TRUE;
    END_IF
END_FOR

(* —— 段 4｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_HsbState.eIdle:
    FOR _nIdx := DL_CH_MIN TO DL_CH_MAX DO
        abSsrOut[_nIdx] := FALSE;        // 空闲相全路关断（安全侧）
    END_FOR
    IF bEnable AND (NOT _bCfgBad) THEN
        _eState := E_DL_HsbState.eRun;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;
        _uFault := 16#0003_0531;
        _eCause := E_DL_HsbCause.eCfgIllegal;
        bError  := TRUE;
        _eState := E_DL_HsbState.eFault;
    END_IF

E_DL_HsbState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_HsbState.eIdle;  // 使能撤销回空闲
    ELSE
        (* 有效路平均电流基准（仅统计未断偶路） *)
        FOR _nIdx := DL_CH_MIN TO nChUse DO
            IF NOT abChBreak[_nIdx] THEN
                _fAvgA := _fAvgA + afCurrentA[_nIdx];
                _nAvgCnt := _nAvgCnt + 1;
            END_IF
        END_FOR
        IF _nAvgCnt > 0 THEN
            _fAvgA := _fAvgA / INT_TO_REAL(_nAvgCnt);
        END_IF
        FOR _nIdx := DL_CH_MIN TO DL_CH_MAX DO
            IF _nIdx <= nChUse THEN
                (* 分相时间比例调功：窗口起点 = 相位偏移 (i-1)/路数 × 周期 *)
                _fDutyUse := MIN(MAX(afDutyPct[_nIdx], DL_DUTY_MIN), DL_DUTY_MAX);
                IF NOT abChBreak[_nIdx] THEN
                    abSsrOut[_nIdx] := (_fPhaseMs >= (_fWinMs * INT_TO_REAL(_nIdx - 1) / INT_TO_REAL(nChUse)))
                                       AND (_fPhaseMs < (_fWinMs * INT_TO_REAL(_nIdx - 1) / INT_TO_REAL(nChUse)
                                            + _fWinMs * _fDutyUse / DL_100));
                ELSE
                    abSsrOut[_nIdx] := FALSE;    // 断偶路降级强制关断
                END_IF
                (* 断偶确认：Q 置锁存并配对故障码（R45） *)
                IF atonBreak[_nIdx].Q THEN
                    abChBreak[_nIdx] := TRUE;
                    _bFault := TRUE;
                    _uFault := 16#0003_0531;
                    _eCause := E_DL_HsbCause.eChBreak;
                    bError  := TRUE;
                END_IF
            ELSE
                abSsrOut[_nIdx] := FALSE;    // 超出有效路数：强制关断
            END_IF
        END_FOR
        IF _bNonFin THEN
            _bFault := TRUE;                 // 输入非有限：锁存
            _uFault := 16#0003_0531;
            _eCause := E_DL_HsbCause.eNonFinite;
            bError  := TRUE;
            _eState := E_DL_HsbState.eFault;
        ELSE
            (* 均衡监督：有效路偏差超限置告警锁存（维护级，不置 bError） *)
            FOR _nIdx := DL_CH_MIN TO nChUse DO
                IF (NOT abChBreak[_nIdx]) AND (_fAvgA > DL_ZERO) THEN
                    _fImbal := ABS(afCurrentA[_nIdx] - _fAvgA) / _fAvgA * DL_100;
                    IF _fImbal > fImbalMaxPct THEN
                        _bImbal := TRUE;
                    END_IF
                END_IF
            END_FOR
            IF _bImbal THEN
                bImbalAlm := TRUE;           // 均衡告警锁存（bReset 沿解除）
            END_IF
            IF _bFault THEN
                _eState := E_DL_HsbState.eFault;   // 断偶或非有限：进故障相
            END_IF
        END_IF
    END_IF

E_DL_HsbState.eFault:
    FOR _nIdx := DL_CH_MIN TO DL_CH_MAX DO
        abSsrOut[_nIdx] := FALSE;        // 故障相全路关断（安全侧）
    END_FOR
    bError := TRUE;
    ;                                    // 故障相驻留：断偶锁存回放，只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0003_0531;
    _eCause := E_DL_HsbCause.eCfgIllegal;
    bError  := TRUE;
    _eState := E_DL_HsbState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射（名实同源） —— *)
eState := _eState;
END_FUNCTION_BLOCK
