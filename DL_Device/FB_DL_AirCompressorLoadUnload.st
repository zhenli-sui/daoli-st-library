(*
  Name        : FB_DL_AirCompressorLoadUnload
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : 空压机加卸载调压：压力带双阈迟滞加卸载切换，加载最小驻留防短周期振荡，卸载超时置维护级告警不自动停机；/ Air compressor load/unload pressure control: dual-threshold hysteresis switching, minimum load dwell against short cycling, unload timeout raising a maintenance-level warning without auto stop
  溯源        : 借 lbp-basic-process 与行业池的调压组织，clean-room 实现
  Boundary    : ① 压力带组态闸：加载阈 < 卸载阈否则锁存故障（相等不立）；
                ② 双阈迟滞直比（加载阈/卸载阈比较，禁浮点等值）；
                ③ 卸载持续 > 卸载超时 → 置维护级告警（bMaintWarn 锁存至复位沿，不自动停机不迁故障相，属主边界）；
                ④ 加载最小驻留防短周期振荡：驻留期内卸载请求暂存不丢（驻留满即执行）；
                ⑤ 压力传感器非有限 → 保持当前负载态 + bSensorBad 当拍出口（不切态防误动作）；
                ⑥ 本件为命令层，不直接驱动接触器（属主边界，出加/卸载命令信号）。
*)
TYPE E_DL_AclState :
(
    eIdle   := 0,                            (* 未使能（命令全停） / Idle, commands off *)
    eLoad   := 10,                           (* 加载相 / Loading *)
    eUnload := 20,                           (* 卸载相 / Unloading *)
    eFault  := 90                            (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_AclCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：压力带阈值倒挂 / Illegal config *)
    eUnloadTime:= 2,                        (* 维护级：卸载超时（不置 bError，边界③） / Maintenance: unload timeout *)
    ePhaseBad  := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AirCompressorLoadUnload
VAR_INPUT
    fPress   : REAL := 0.0;                  (* 储气罐压力 [bar] / Receiver pressure *)
    fLoadTh  : REAL := 6.0;                  (* 加载阈（下限），域 < 卸载阈 [bar] / Load threshold *)
    fUnloadTh: REAL := 8.0;                  (* 卸载阈（上限）[bar] / Unload threshold *)
    tLoadMin : TIME := T#30S;                (* 加载最小驻留，域 > T#0S [ms] / Minimum load dwell *)
    tUnloadMax: TIME := T#10M;               (* 卸载超时，域 > T#0S [ms] / Unload timeout *)
    tScan    : TIME := T#100MS;              (* 扫描周期，域 > T#0S [ms] / Scan period *)
    bEnable  : BOOL := TRUE;                 (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障与告警 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bLoadCmd : BOOL;                         (* 加载命令信号 [-] / Load command *)
    bUnloadCmd: BOOL;                        (* 卸载命令信号 [-] / Unload command *)
    bMaintWarn: BOOL;                        (* 维护级告警锁存（卸载超时，复位沿清，边界③）[-] / Maintenance warning latched *)
    bSensorBad: BOOL;                        (* 压力传感器失效当拍出口（边界⑤）[-] / Sensor bad outlet *)
    eState   : E_DL_AclState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_AclCause;                (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_AclState := E_DL_AclState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_AclCause := E_DL_AclCause.eNone;  (* 成因锁存量 / Latched cause *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonLoad : TON;                           (* 加载驻留计时（IN 串 eLoad 相闸，R40） / Load dwell timer *)
    tonUnl  : TON;                           (* 卸载持续计时（IN 串 eUnload 相闸，R40） / Unload duration timer *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                          (* 压力有限性当拍量（边界⑤） / Pressure finiteness *)
    _bUnlReq: BOOL;                          (* 卸载请求暂存量（驻留期内不丢，边界④） / Buffered unload request *)
    _fDtSec : REAL;                          (* 扫描周期秒值（信息级备用派生）[s] / Scan period seconds *)
END_VAR
VAR CONSTANT
    DL_ACL_EPS : REAL := 1.0E-6;             (* 判零容差 [-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；TON 全段 0 无 IF 包裹，R40） —— *)
_bCfgBad := NOT (fLoadTh < fUnloadTh)                    (* 压力带组态闸：加载阈 < 卸载阈（边界①） / Band config gate *)
            OR (fLoadTh <= DL_ACL_EPS)                   (* 加载阈正域闸 / Load threshold gate *)
            OR NOT (tLoadMin > T#0S) OR NOT (tUnloadMax > T#0S) OR NOT (tScan > T#0S);   (* 周期域闸 / Period gates *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fPress = fPress) AND ((fPress - fPress) = (fPress - fPress));   (* 压力 NaN 自反 + Inf 差判闸（边界⑤） / Pressure NaN and Inf gate *)
_fDtSec := TIME_TO_LREAL(tScan) / 1000.0;                (* 扫描周期秒化（除子常量 1000） / Scan period seconds *)
tonLoad(IN := (_eState = E_DL_AclState.eLoad), PT := tLoadMin);          (* 加载驻留：相位闸 + 无条件调用（R40） / Load dwell timer *)
tonUnl(IN := (_eState = E_DL_AclState.eUnload), PT := tUnloadMax);       (* 卸载持续：相位闸 + 无条件调用（R40） / Unload timer *)

(* —— 段 1：单拍量预清零（R107） —— *)
bLoadCmd := FALSE;                                       (* 加载命令出口预清（派生拍覆盖） / Load command preset *)
bUnloadCmd := FALSE;                                     (* 卸载命令出口预清 / Unload command preset *)
bSensorBad := FALSE;                                     (* 传感器失效当拍出口预清 / Sensor bad preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清维护告警 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_AclCause.eNone;                      (* 清成因 / Clear cause *)
    bMaintWarn := FALSE;                                 (* 清维护告警锁存 / Clear maintenance warning *)
    _bUnlReq := FALSE;                                   (* 清卸载请求暂存 / Clear buffered request *)
    _eState := E_DL_AclState.eIdle;                      (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_AclCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_AclState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_AclState.eIdle:                                 (* 未使能：命令全停确定值 / Idle *)
        bLoadCmd := FALSE;                               (* 失能加载命令 FALSE / Disabled load false *)
        bUnloadCmd := FALSE;                             (* 失能卸载命令 FALSE / Disabled unload false *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_AclState.eLoad;              (* 使能先入加载相（建压优先） / Enter loading *)
        END_IF
    E_DL_AclState.eLoad:                                 (* 加载相：驻留 + 双阈迟滞切换 / Loading *)
        IF NOT bEnable THEN
            _eState := E_DL_AclState.eIdle;              (* 失能回未使能 / Back to idle *)
        ELSIF NOT _bFin THEN
            bSensorBad := TRUE;                          (* 传感器失效：保持当前态（边界⑤） / Sensor bad hold *)
        ELSE
            IF fPress >= fUnloadTh THEN
                _bUnlReq := TRUE;                        (* 驻留期内卸载请求暂存不丢（边界④） / Buffer unload request *)
            END_IF
            IF tonLoad.Q AND _bUnlReq THEN               (* 驻留满 + 有暂存请求：迁卸载（边界④） / Dwell done and request *)
                _bUnlReq := FALSE;                       (* 请求消费清零 / Request consumed *)
                _eState := E_DL_AclState.eUnload;        (* 迁卸载相 / To unloading *)
            END_IF
        END_IF
    E_DL_AclState.eUnload:                               (* 卸载相：下阈回加载 + 超时维护告警 / Unloading *)
        IF NOT bEnable THEN
            _eState := E_DL_AclState.eIdle;              (* 失能回未使能 / Back to idle *)
        ELSIF NOT _bFin THEN
            bSensorBad := TRUE;                          (* 传感器失效：保持当前态（边界⑤） / Sensor bad hold *)
        ELSE
            IF tonUnl.Q THEN                             (* 卸载持续超时（边界③） / Unload timeout *)
                bMaintWarn := TRUE;                      (* 维护级告警锁存（复位沿清，不自动停机） / Maintenance warning latch *)
                _eCause := E_DL_AclCause.eUnloadTime;    (* 成因：卸载超时（信息级不置 bError，边界③） / Cause unload time *)
            END_IF
            IF fPress <= fLoadTh THEN                    (* 压力回落到加载阈：迁加载（双阈迟滞直比，边界②） / Back to load *)
                _eState := E_DL_AclState.eLoad;          (* 迁加载相 / To loading *)
            END_IF
        END_IF
    E_DL_AclState.eFault:                                (* 故障相：命令全停冻结，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_AclState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_AclCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（名实双出口，R191；bError/eState 同源） —— *)
bLoadCmd := (_eState = E_DL_AclState.eLoad);             (* 加载命令 = 加载相镜像 / Load command mirror *)
bUnloadCmd := (_eState = E_DL_AclState.eUnload);         (* 卸载命令 = 卸载相镜像 / Unload command mirror *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
