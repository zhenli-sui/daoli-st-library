(*
  Name        : FB_DL_DieBinCounter
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 晶粒分箱计数与满箱切换：按来料脉冲累加晶粒数，接近容量即预警，满箱置切换请求，收到换箱确认后清零并箱号递增；/ Count dies per bin with near-full warning, full-bin switch request and post-acknowledge bin index advance
  溯源        : ROADMAP L647（未勾真缺口），IEC 61131-3 标准语义的道莅防御性实现
  Boundary    : ① 组态闸：箱容量 < 2 / 预警余量 < 0 或 >= 容量 → 锁存故障（余量需严格小于容量，否则预警永不触发）；
                ② 计数只认单拍脉冲上升沿（防电平长时间为真时多计）；
                ③ 满箱锁存后不再接收计数脉冲（拒收计 nReject），避免溢出把计数推过容量；
                ④ 切换请求为状态量（eFull 相保持），换箱确认为上升沿（跨周期动作不用单拍标志门控）；
                ⑤ 箱号 UDINT 饱和累加，满容量计数上限钳到箱容量（防越界显示）。
*)
TYPE E_DL_DbcState :
(
    eIdle   := 0,                            (* 未使能 / Disabled *)
    eCount  := 10,                           (* 计数中 / Counting *)
    eFull   := 20,                           (* 满箱待换箱 / Full, awaiting switch *)
    eFault  := 90                            (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_DbcCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：容量/余量越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_DieBinCounter
VAR_INPUT
    bDiePulse   : BOOL := FALSE;             (* 晶粒来料脉冲（上升沿计 1 颗）[-] / Die arrival pulse, rising edge counts one *)
    nBinCap     : INT := 5000;               (* 箱容量，域 >= 2 [颗] / Bin capacity, >= 2 *)
    nWarnMargin : INT := 200;                (* 满箱预警余量，域 0 <= x < nBinCap [颗] / Near-full margin *)
    bSwitchAck  : BOOL := FALSE;             (* 换箱完成确认（上升沿）[-] / Bin switch acknowledge edge *)
    bEnable     : BOOL := TRUE;              (* 使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清计数/箱号/故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nCount      : INT;                       (* 当前箱已装颗数（钳到容量）[颗] / Current bin count, clamped to capacity *)
    nBinIdx     : UDINT;                     (* 当前箱号（从 1 起，饱和）[-] / Current bin index, from 1, saturated *)
    bNearFull   : BOOL;                      (* 接近满箱预警 [-] / Near-full warning *)
    bBinFull    : BOOL;                      (* 满箱锁存 [-] / Bin full latch *)
    bSwitchReq  : BOOL;                      (* 换箱请求（满箱相保持）[-] / Switch request while full *)
    nReject     : INT;                       (* 满箱期拒收脉冲数（诊断，饱和）[颗] / Rejected pulses while full *)
    eState      : E_DL_DbcState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_DbcCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_DbcState := E_DL_DbcState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_DbcCause := E_DL_DbcCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtPulse  : R_TRIG;                       (* 来料脉冲上升沿，段 0 无条件调用 / Die pulse edge *)
    rtAck    : R_TRIG;                       (* 换箱确认上升沿，段 0 无条件调用 / Ack edge *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFull   : BOOL;                         (* 满箱锁存位 / Full latch *)
    _nCount  : INT;                          (* 计数内部量 [颗] / Count internal *)
    _nRej    : INT;                          (* 拒收计数内部量 [颗] / Reject internal *)
    _nWarnTh : INT;                          (* 预警门槛 = 容量 - 余量 [颗] / Warning threshold *)
END_VAR
VAR CONSTANT
    DL_DBC_CNTMAX : UDINT := 4294967295;     (* 箱号饱和上限（R28）[-] / Bin index cap *)
    DL_DBC_REJMAX : INT   := 32767;          (* 拒收计数饱和上限（INT 可表上限）[颗] / Reject count cap *)
    DL_DBC_NMIN   : INT   := 2;              (* 容量下限（需能容纳预警余量逻辑）[颗] / Capacity lower bound *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nBinCap < DL_DBC_NMIN)                                            (* 容量域闸 / Capacity gate *)
            OR (nWarnMargin < 0) OR (nWarnMargin >= nBinCap);                  (* 余量域闸（须严格小于容量） / Margin gate *)
rtPulse(CLK := bDiePulse);                                                     (* 来料沿每拍必调 / Pulse edge every scan *)
rtAck(CLK := bSwitchAck);                                                      (* 确认沿每拍必调 / Ack edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_nWarnTh := nBinCap - nWarnMargin;                                             (* 预警门槛反算（容量 > 余量，差恒正）[颗] / Warning threshold *)

(* —— 段 1：单拍量预清零（R107） —— *)
bNearFull := FALSE;                                                            (* 预警位预清 / Near-full preset *)
bSwitchReq := FALSE;                                                           (* 换箱请求预清（仅满箱相置位） / Request preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 清箱号 + 清满箱锁存 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_DbcCause.eNone;                                            (* 清成因 / Clear cause *)
    _bFull := FALSE;                                                           (* 清满箱锁存（隐性回夹防护） / Clear full latch *)
    _nCount := 0;                                                              (* 清计数 / Clear count *)
    _nRej := 0;                                                                (* 清拒收计数 / Clear reject count *)
    nCount := 0;                                                               (* 清计数出口 / Clear count outlet *)
    nBinIdx := 1;                                                              (* 箱号回 1（从 1 起） / Bin index back to 1 *)
    bBinFull := FALSE;                                                         (* 清满箱出口 / Clear full outlet *)
    nReject := 0;                                                              (* 清拒收出口 / Clear reject outlet *)
    _eState := E_DL_DbcState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_DbcCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_DbcState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_DbcState.eIdle:                                                       (* 未使能：不计数 / Disabled *)
        nCount := _nCount;                                                     (* 出口镜像（保留进度） / Outlet mirror *)
        IF bEnable AND NOT _bFault THEN
            IF nBinIdx = 0 THEN
                nBinIdx := 1;                                                  (* 未初始化箱号兜底为 1（首次使能） / Init bin index *)
            END_IF
            _eState := E_DL_DbcState.eCount;                                   (* 使能进入计数 / Enter counting *)
        END_IF
    E_DL_DbcState.eCount:                                                      (* 计数相：脉冲累加 + 满箱推进 / Counting *)
        IF NOT bEnable THEN
            _eState := E_DL_DbcState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            IF rtPulse.Q THEN                                                  (* 单拍脉冲上升沿计 1 颗 / One die per rising edge *)
                IF _nCount < nBinCap THEN
                    _nCount := _nCount + 1;                                    (* 容量内递增（满后拒收） / Increment within capacity *)
                END_IF
            END_IF
            IF _nCount >= nBinCap THEN
                _nCount := nBinCap;                                            (* 计数钳到容量（防越界显示） / Clamp to capacity *)
                _bFull := TRUE;                                                (* 满箱锁存 / Latch full *)
            END_IF
            nCount := _nCount;                                                 (* 计数出口 / Count outlet *)
            IF NOT _bFull THEN
                IF _nCount >= _nWarnTh THEN
                    bNearFull := TRUE;                                         (* 接近满箱预警 / Near-full warning *)
                END_IF
            END_IF
            bBinFull := _bFull;                                                (* 满箱出口镜像（名实同源，R191） / Full outlet mirror *)
            IF _bFull THEN
                _eState := E_DL_DbcState.eFull;                                (* 迁满箱相（请求换箱） / To full *)
            END_IF
        END_IF
    E_DL_DbcState.eFull:                                                       (* 满箱相：保持请求，拒收脉冲，等确认 / Full *)
        bBinFull := TRUE;                                                      (* 满箱出口保持 / Full outlet held *)
        bSwitchReq := TRUE;                                                    (* 换箱请求状态量保持（非单拍标志） / Request held as state *)
        nCount := _nCount;                                                     (* 计数出口保持 / Count outlet held *)
        IF rtPulse.Q THEN
            IF _nRej < DL_DBC_REJMAX THEN
                _nRej := _nRej + 1;                                            (* 满箱期拒收脉冲计数（诊断） / Count rejects *)
            END_IF
        END_IF
        nReject := _nRej;                                                      (* 拒收出口 / Reject outlet *)
        IF rtAck.Q THEN                                                        (* 换箱确认上升沿：清零换箱 / Ack: reset bin *)
            _nCount := 0;                                                      (* 清计数 / Clear count *)
            _bFull := FALSE;                                                   (* 清满箱锁存 / Clear full *)
            bBinFull := FALSE;                                                 (* 清满箱出口 / Clear full outlet *)
            nCount := 0;                                                       (* 清计数出口 / Clear count outlet *)
            IF nBinIdx < DL_DBC_CNTMAX THEN
                nBinIdx := nBinIdx + 1;                                        (* 箱号饱和递增 / Saturating bin index *)
            END_IF
            _eState := E_DL_DbcState.eCount;                                   (* 回计数相 / Back to counting *)
        END_IF
    E_DL_DbcState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_DbcState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_DbcCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
