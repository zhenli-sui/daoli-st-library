(*
  Name        : FB_DL_PumpSurgeGuard
  Category    : DL_Algo
  Version     : 1.0.0
  Purpose     : 泵喘振区逼近保护：以流量-压力工况点对线性喘振线求裕度，裕度低于门槛自动降载（流量上限限幅输出），恢复期斜坡回升；/ Pump surge guard: margin of the operating point against a linear surge line; below threshold the flow setpoint is automatically derated and ramped back on recovery
  溯源        : 借 t1-1-oscat-basic ◐/自研 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：流量量程/裕度门槛/斜坡速率/周期任一越域或裕度门槛 > 1 → 锁存故障（量程 0 使裕度无定义）；
                ② 除零前置：流量上限比除子为 fFlowCmd，仅 |fFlowCmd| > eps 时计算（流量命令近零视为已充分降载，斜坡目标取 1）；
                ③ 非有限流量/压力该拍不更新判据（斜坡保持上拍值，防污染降载器）；
                ④ 裕度与降载系数均饱和 0..1，饱和是该变量最后一次写；
                ⑤ 降载斜坡按 fRampRate（1/s）× 周期秒值逐拍逼近目标，无突跳；
                ⑥ 本件为保护层，只限幅不切泵（启停由上层顺序控制，属主边界）。
*)
TYPE E_DL_PsgState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 喘振保护运行 / Guarding *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_PsgCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：量程/门槛/斜坡越域 / Illegal config *)
    eSurge      := 2,                        (* 裕度低于门槛（降载激活） / Margin below threshold *)
    ePhaseBad   := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PumpSurgeGuard
VAR_INPUT
    fFlow      : REAL := 0.0;                (* 泵流量实测 [m3/h] / Measured pump flow *)
    fPress     : REAL := 0.0;                (* 泵出口压力实测（扬程口径）[bar] / Measured discharge pressure *)
    fFlowCmd   : REAL := 0.0;                (* 上层流量设定（降载比基准）[m3/h] / Upstream flow setpoint *)
    fPressRef  : REAL := 5.0;               (* 喘振线参考压力（线截距基准），域 >= 0 [bar] / Surge-line reference pressure *)
    fSlope     : REAL := 0.2;                (* 喘振线斜率（压升 1 bar 对应喘振流量下限增量），域 >= 0 [(m3/h)/bar] / Surge-line slope *)
    fFlowSpan  : REAL := 100.0;              (* 流量量程（裕度归一化分母），域 > 0 [m3/h] / Flow span for margin normalisation *)
    fMarginMin : REAL := 0.15;               (* 裕度门槛（低于即降载），域 (0..1] [-] / Margin threshold, (0..1] *)
    fRampRate  : REAL := 0.1;               (* 降载/恢复斜坡速率，域 > 0 [1/s] / Ramp rate, > 0 *)
    tCycle     : TIME := T#100MS;           (* 运行周期，域 > T#0S [ms] / Cycle period, > 0 *)
    bEnable    : BOOL := TRUE;              (* 保护使能 [-] / Enable *)
    bReset     : BOOL := FALSE;             (* 复位命令，上升沿清降载与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fMargin    : REAL;                      (* 工况点距喘振线归一化裕度 0..1（饱和）[-] / Normalised surge margin, saturated *)
    fFlowLimit : REAL;                      (* 降载后流量上限（fFlowCmd × 系数）[m3/h] / Derated flow limit *)
    fDerateFac : REAL;                      (* 降载系数 0..1（斜坡逼近）[-] / Derating factor, ramped *)
    bSurgeWarn : BOOL;                      (* 喘振逼近告警（裕度 < 门槛，电平）[-] / Surge proximity warning *)
    eState     : E_DL_PsgState;             (* 状态出口 / State outlet *)
    eCause     : E_DL_PsgCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_PsgState := E_DL_PsgState.eIdle;    (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_PsgCause := E_DL_PsgCause.eNone;    (* 故障成因锁存量 / Latched cause *)
    rtReset   : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault   : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFin     : BOOL;                         (* 输入有限性当拍量（流量/压力联合） / Input finiteness joint *)
    _fDtSec   : REAL;                         (* 周期折算秒值，域 > eps [s] / Period in seconds *)
    _fSurgeFl : REAL;                         (* 当前压力下喘振流量下限 [m3/h] / Surge flow limit at pressure *)
    _fMargI   : REAL;                         (* 裕度中间量（饱和前）[-] / Margin intermediate *)
    _fTarget  : REAL;                         (* 降载系数斜坡目标 [-] / Derating ramp target *)
    _fStep    : REAL;                         (* 本拍斜坡步长 [1/s 口径] / Ramp step this scan *)
    _fFac     : REAL;                         (* 降载系数内部量 0..1 [-] / Derating factor internal *)
END_VAR
VAR CONSTANT
    DL_PSG_EPS    : REAL := 1.0E-6;           (* 判零容差 [-] / Epsilon *)
    DL_PSG_PCTMAX : REAL := 1.0;              (* 裕度/系数满量程（归一化上限）[-] / Full scale *)
    DL_PSG_PCTMIN : REAL := 0.0;              (* 裕度/系数下限 [-] / Lower bound *)
    DL_PSG_DERMAX : REAL := 0.4;              (* 降载系数下限（最多降到 40%，防深喘振区反复进出）[-] / Derating floor *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tCycle) / 1000.0;                                     (* 周期秒化（除子常量 1000） / Period to seconds *)
_bCfgBad := NOT (tCycle > T#0S)                                                (* 周期正域闸 / Period gate *)
            OR (fFlowSpan <= DL_PSG_EPS)                                       (* 流量量程正域闸（裕度除子） / Flow span gate *)
            OR (fPressRef < 0.0) OR (fSlope < 0.0)                             (* 参考压力/斜率非负闸 / Reference and slope gates *)
            OR (fMarginMin <= DL_PSG_EPS) OR (fMarginMin > DL_PSG_PCTMAX)      (* 裕度门槛域闸 (0..1] / Margin threshold gate *)
            OR (fRampRate <= DL_PSG_EPS);                                      (* 斜坡速率正域闸 / Ramp rate gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fFlow = fFlow) AND (fPress = fPress)                                 (* 流量/压力 NaN 自反闸 / Flow and pressure NaN gates *)
            AND ((fFlow - fFlow) = (fFlow - fFlow))                            (* 流量 Inf 差判闸 / Flow Inf gate *)
            AND ((fPress - fPress) = (fPress - fPress));                       (* 压力 Inf 差判闸 / Pressure Inf gate *)

(* —— 段 1：单拍量预清零（R107；fDerateFac 为斜坡状态量，不在此预清） —— *)
fMargin := 0.0;                                                                (* 裕度出口预清 / Margin outlet preset *)
bSurgeWarn := FALSE;                                                           (* 告警出口预清 / Warn outlet preset *)
_fMargI := 0.0;                                                                (* 裕度中间量预置（非有限拍保持 0 语义） / Margin intermediate preset *)
_fTarget := DL_PSG_PCTMAX;                                                     (* 斜坡目标预置（默认全流量） / Ramp target preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清降载系数与限幅 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_PsgCause.eNone;                                            (* 清成因 / Clear cause *)
    _fFac := DL_PSG_PCTMAX;                                                    (* 降载系数回 1（不降载） / Factor back to 1 *)
    fDerateFac := DL_PSG_PCTMAX;                                               (* 系数出口回 1 / Factor outlet back to 1 *)
    fFlowLimit := 0.0;                                                         (* 清限幅出口 / Clear limit outlet *)
    _eState := E_DL_PsgState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_PsgCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_PsgState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PsgState.eIdle:                                                       (* 未使能：不保护，出口确定值 / Disabled *)
        fMargin := 0.0;                                                        (* 失能清裕度出口 / Clear margin outlet *)
        bSurgeWarn := FALSE;                                                   (* 失能清告警出口 / Clear warn outlet *)
        fFlowLimit := 0.0;                                                     (* 失能清限幅出口 / Clear limit outlet *)
        fDerateFac := DL_PSG_PCTMAX;                                           (* 失能系数回 1（不降载语义） / Factor outlet back to 1 *)
        _fFac := DL_PSG_PCTMAX;                                                (* 内部系数同步回 1 / Internal factor reset *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_PsgState.eRun;                                     (* 使能进入保护 / Enter guarding *)
        END_IF
    E_DL_PsgState.eRun:                                                        (* 保护相：裕度判据 + 斜坡降载 / Guarding *)
        IF NOT bEnable THEN
            _eState := E_DL_PsgState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF _bFin AND (_fDtSec > DL_PSG_EPS) THEN
            _fSurgeFl := fSlope * (fPress - fPressRef);                        (* 喘振流量下限 = 斜率 × (压力-参考)（乘性，无除零；可为负即无喘振约束） / Surge flow limit *)
            _fMargI := (fFlow - _fSurgeFl) / fFlowSpan;                        (* 归一化裕度：除子量程已过闸 [-] / Normalised margin *)
            IF _fMargI > DL_PSG_PCTMAX THEN
                _fMargI := DL_PSG_PCTMAX;                                      (* 裕度上限饱和 1（最后一次写） / Margin upper saturation *)
            ELSIF _fMargI < DL_PSG_PCTMIN THEN
                _fMargI := DL_PSG_PCTMIN;                                      (* 裕度下限饱和 0（最后一次写） / Margin lower saturation *)
            END_IF
            fMargin := _fMargI;                                                (* 裕度出口 / Margin outlet *)
            IF _fMargI < fMarginMin THEN
                bSurgeWarn := TRUE;                                            (* 裕度低于门槛：逼近告警（电平） / Margin below threshold *)
                _eCause := E_DL_PsgCause.eSurge;                               (* 成因更新：喘振逼近（诊断归因，非锁存故障） / Cause: surge proximity *)
                _fTarget := DL_PSG_DERMAX;                                     (* 降载目标 = 系数下限（深降载） / Target = derating floor *)
            ELSE
                _fTarget := DL_PSG_PCTMAX;                                     (* 裕度充足：恢复目标 = 全流量 / Target = full flow *)
            END_IF
            _fStep := fRampRate * _fDtSec;                                     (* 本拍斜坡步长（周期已过闸，REAL×REAL） / Ramp step *)
            IF _fFac < _fTarget THEN
                _fFac := _fFac + _fStep;                                       (* 恢复方向斜坡递增 / Ramp up *)
                IF _fFac > _fTarget THEN
                    _fFac := _fTarget;                                         (* 步长越目标即钳到目标（最后一次写） / Clamp to target *)
                END_IF
            ELSIF _fFac > _fTarget THEN
                _fFac := _fFac - _fStep;                                       (* 降载方向斜坡递减 / Ramp down *)
                IF _fFac < _fTarget THEN
                    _fFac := _fTarget;                                         (* 步长越目标即钳到目标（最后一次写） / Clamp to target *)
                END_IF
                IF _fFac < DL_PSG_DERMAX THEN
                    _fFac := DL_PSG_DERMAX;                                    (* 系数下限钳位（最后一次写） / Derating floor clamp *)
                END_IF
            END_IF
            fDerateFac := _fFac;                                               (* 系数出口（斜坡状态镜像） / Factor outlet *)
            IF ABS(fFlowCmd) > DL_PSG_EPS THEN                                 (* 流量命令有效才算限幅（除零前置，边界②） / Limit only with valid command *)
                fFlowLimit := fFlowCmd * _fFac;                                (* 限幅 = 命令 × 系数 [m3/h] / Limit = command times factor *)
            ELSE
                fFlowLimit := 0.0;                                             (* 命令近零：限幅 0（已充分降载语义） / Zero command: limit zero *)
            END_IF
        END_IF                                                                 (* 非有限输入：斜坡保持上拍值（边界③） / Non-finite: hold ramp *)
    E_DL_PsgState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PsgState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_PsgCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
