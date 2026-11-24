(*
  Name        : FB_DL_PrbsSignal
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : PRBS 伪随机二进序列激励发生（LFSR 整数实现，阶数 4..31 抽头表），供回路辨识/继电器整定的持续激励源；/ PRBS pseudo-random binary sequence excitation generator (integer LFSR, degree 4..31 tap table) for loop identification and relay tuning
  溯源        : 借 oscat-basic 的 PRBS 行为定义组织，clean-room 实现
  Boundary    : ① 抽头多项式合法域校验：阶数 4..31 之外的阶数锁存故障（抽头表 CASE 全覆盖 + ELSE 兜底）；
                ② LFSR 全零态检测：每步推进前遇全零强制注入 1（防死序列）；
                ③ 使能撤除保持相位与序列值，重使能不重启序列；仅 bRestart 上升沿显式重载种子重启；
                ④ 输出脉冲宽度以扫描周期为时基（每 nBitScan 拍推进一位），nBitScan 钳位下限 ≥ 2；
                ⑤ 种子 0 视为非法（与全零态同源），组态期锁存故障；
                ⑥ 零外部全局、零物理地址，纯整数实现跨平台移植。
*)
TYPE E_DL_PbsState :
(
    eIdle  := 0,                             (* 未使能（相位保持） / Disabled, phase held *)
    eRun   := 10,                            (* 序列激励运行 / Sequence running *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_PbsCause :
(
    eNone      := 0,                         (* 无故障成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：阶数/种子/位宽越域 / Illegal config *)
    ePhaseBad  := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PrbsSignal
VAR_INPUT
    nDegree : INT := 31;                     (* LFSR 阶数，域 4..31 [阶] / LFSR degree *)
    nSeed   : DWORD := DWORD#16#ACE1;        (* 种子（0 非法）[-] / Seed, zero illegal *)
    nBitScan: INT := 10;                     (* 每位驻留扫描拍数，域 >= 2 [拍] / Bit dwell in scans *)
    bEnable : BOOL := TRUE;                  (* 使能（撤除保持相位）[-] / Enable, phase held on disable *)
    bRestart: BOOL := FALSE;                 (* 重启命令，上升沿重载种子 [-] / Restart command, edge reload seed *)
    bReset  : BOOL := FALSE;                 (* 复位命令，上升沿清故障与序列 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bOut    : BOOL;                          (* PRBS 位输出（当前 LFSR 最低位）[-] / PRBS bit output *)
    nBitCnt : UDINT;                         (* 已推进位数（饱和，诊断）[位] / Bits advanced, saturated *)
    eState  : E_DL_PbsState;                 (* 状态出口 / State outlet *)
    eCause  : E_DL_PbsCause;                 (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError  : BOOL;                          (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_PbsState := E_DL_PbsState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_PbsCause := E_DL_PbsCause.eNone;  (* 故障成因锁存量 / Latched cause *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    rtRestart: R_TRIG;                       (* 重启沿实例，段 0 无条件调用 / Restart edge instance *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _nLfsr  : DWORD;                         (* LFSR 状态寄存器（整数实现）[-] / LFSR state register *)
    _nTapMsk: DWORD;                         (* 抽头掩码（CASE 表派生）[-] / Tap mask from table *)
    _bFb    : BOOL;                          (* 反馈位异或累加量 [-] / Feedback parity *)
    _bZero  : BOOL;                          (* 全零态检测当拍量 / All-zero state detect *)
    _nDiv   : INT;                           (* 扫描分频计数器 [拍] / Scan divider counter *)
    _nDwell : INT;                           (* 钳位后生效位驻留拍数 [拍] / Clamped bit dwell *)
    _i      : INT;                           (* 抽头位扫描游标 [位] / Tap bit cursor *)
END_VAR
VAR CONSTANT
    DL_PBS_NMIN : INT   := 4;                (* 阶数下限（边界①）[阶] / Degree lower bound *)
    DL_PBS_NMAX : INT   := 31;               (* 阶数上限（边界①）[阶] / Degree upper bound *)
    DL_PBS_DMIN : INT   := 2;                (* 位驻留下限（边界④）[拍] / Dwell lower bound *)
    DL_PBS_CNTMAX: UDINT := 4294967295;      (* 推进计数饱和上限（R28）[位] / Count saturation cap *)
    DL_PBS_ONE  : DWORD := DWORD#1;          (* 位掩码常量 1 [-] / Bit mask one *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nDegree < DL_PBS_NMIN) OR (nDegree > DL_PBS_NMAX)          (* 阶数域闸（边界①） / Degree gate *)
            OR (nSeed = DWORD#0)                                        (* 种子零非法闸（边界⑤） / Seed gate *)
            OR (nBitScan < DL_PBS_DMIN);                                (* 位驻留下限闸（边界④） / Dwell gate *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
rtRestart(CLK := bRestart);                              (* 重启沿每拍必调 / Restart edge every scan *)
_nDwell := nBitScan;                                     (* 驻留拍数初值 / Dwell init *)
IF _nDwell < DL_PBS_DMIN THEN
    _nDwell := DL_PBS_DMIN;                              (* 驻留钳位下限（防 0 拍高频抖动） / Dwell clamp *)
END_IF

(* —— 段 0B：抽头掩码 CASE 表（本原多项式，位号 = 抽头位 - 1；每拍派生，全枚举覆盖 + ELSE 兜底，红线 5/6） —— *)
CASE nDegree OF
    4 : _nTapMsk := DWORD#16#0000000C;                   (* 抽头 4,3 → 位 3,2 / Taps 4,3 *)
    5 : _nTapMsk := DWORD#16#00000014;                   (* 抽头 5,3 → 位 4,2 / Taps 5,3 *)
    6 : _nTapMsk := DWORD#16#00000030;                   (* 抽头 6,5 → 位 5,4 / Taps 6,5 *)
    7 : _nTapMsk := DWORD#16#00000060;                   (* 抽头 7,6 → 位 6,5 / Taps 7,6 *)
    8 : _nTapMsk := DWORD#16#000000B8;                   (* 抽头 8,6,5,4 → 位 7,5,4,3 / Taps 8,6,5,4 *)
    9 : _nTapMsk := DWORD#16#00000110;                   (* 抽头 9,5 → 位 8,4 / Taps 9,5 *)
    10: _nTapMsk := DWORD#16#00000240;                   (* 抽头 10,7 → 位 9,6 / Taps 10,7 *)
    11: _nTapMsk := DWORD#16#00000500;                   (* 抽头 11,9 → 位 10,8 / Taps 11,9 *)
    12: _nTapMsk := DWORD#16#00000820;                   (* 抽头 12,6 → 位 11,5 / Taps 12,6 *)
    13: _nTapMsk := DWORD#16#0000100D;                   (* 抽头 13,4,3,1 → 位 12,3,2,0 / Taps 13,4,3,1 *)
    14: _nTapMsk := DWORD#16#00002015;                   (* 抽头 14,5,3,1 → 位 13,4,2,0 / Taps 14,5,3,1 *)
    15: _nTapMsk := DWORD#16#00006000;                   (* 抽头 15,14 → 位 14,13 / Taps 15,14 *)
    16: _nTapMsk := DWORD#16#0000B400;                   (* 抽头 16,14,13,11 → 位 15,13,12,10 / Taps 16,14,13,11 *)
    17: _nTapMsk := DWORD#16#00012000;                   (* 抽头 17,14 → 位 16,13 / Taps 17,14 *)
    18: _nTapMsk := DWORD#16#00020400;                   (* 抽头 18,11 → 位 17,10 / Taps 18,11 *)
    19: _nTapMsk := DWORD#16#00040023;                   (* 抽头 19,6,2,1 → 位 18,5,1,0 / Taps 19,6,2,1 *)
    20: _nTapMsk := DWORD#16#00090000;                   (* 抽头 20,17 → 位 19,16 / Taps 20,17 *)
    21: _nTapMsk := DWORD#16#00140000;                   (* 抽头 21,19 → 位 20,18 / Taps 21,19 *)
    22: _nTapMsk := DWORD#16#00300000;                   (* 抽头 22,21 → 位 21,20 / Taps 22,21 *)
    23: _nTapMsk := DWORD#16#00420000;                   (* 抽头 23,18 → 位 22,17 / Taps 23,18 *)
    24: _nTapMsk := DWORD#16#00E10000;                   (* 抽头 24,23,22,17 → 位 23,22,21,16 / Taps 24,23,22,17 *)
    25: _nTapMsk := DWORD#16#01200000;                   (* 抽头 25,22 → 位 24,21 / Taps 25,22 *)
    26: _nTapMsk := DWORD#16#2000023;                    (* 抽头 26,6,2,1 → 位 25,5,1,0 / Taps 26,6,2,1 *)
    27: _nTapMsk := DWORD#16#4000013;                    (* 抽头 27,5,2,1 → 位 26,4,1,0 / Taps 27,5,2,1 *)
    28: _nTapMsk := DWORD#16#09000000;                   (* 抽头 28,25 → 位 27,24 / Taps 28,25 *)
    29: _nTapMsk := DWORD#16#14000000;                   (* 抽头 29,27 → 位 28,26 / Taps 29,27 *)
    30: _nTapMsk := DWORD#16#30000000;                   (* 抽头 30,29 → 位 29,28 / Taps 30,29 *)
    31: _nTapMsk := DWORD#16#48000000;                   (* 抽头 31,28 → 位 30,27 / Taps 31,28 *)
    ELSE
        _nTapMsk := DWORD#0;                             (* 越域阶数：掩码清零（域闸已另行锁故障） / Out-of-domain degree *)
END_CASE

(* —— 段 1：单拍量预清零（R107） —— *)
bOut := FALSE;                                           (* 位输出预清（派生拍覆盖） / Bit output preset *)
_bFb := FALSE;                                           (* 反馈奇偶累加清零 / Feedback parity clear *)
_bZero := FALSE;                                         (* 全零态检测清零 / Zero detect clear *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清序列状态 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_PbsCause.eNone;                      (* 清成因 / Clear cause *)
    _nLfsr := DWORD#0;                                   (* 清序列寄存器 / Clear LFSR register *)
    _nDiv := 0;                                          (* 清分频计数 / Clear divider *)
    nBitCnt := UDINT#0;                                  (* 清推进计数出口 / Clear bit count *)
    bOut := FALSE;                                       (* 清位输出出口 / Clear bit output *)
    _eState := E_DL_PbsState.eIdle;                      (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_PbsCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_PbsState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PbsState.eIdle:                                 (* 未使能：相位与序列值保持（边界③） / Disabled, phase held *)
        bOut := FALSE;                                   (* 失能位输出确定值 0 / Disabled bit output zero *)
        _nDiv := 0;                                      (* 失能清分频计数（重使能重新计时） / Clear divider *)
        IF bEnable AND NOT _bFault THEN
            _nLfsr := nSeed;                             (* 使能迁入拍装载种子（相位起点） / Load seed at entry *)
            _nDiv := 0;                                  (* 分频计数归零 / Divider zero *)
            _eState := E_DL_PbsState.eRun;               (* 进入运行相 / Enter running *)
        END_IF
    E_DL_PbsState.eRun:                                  (* 运行相：分频推进 + 抽头反馈 / Running *)
        IF NOT bEnable THEN
            _eState := E_DL_PbsState.eIdle;              (* 失能回未使能（相位保持不重启） / Back to idle *)
        ELSE
            IF rtRestart.Q THEN
                _nLfsr := nSeed;                         (* 显式重启重载种子（边界③） / Explicit restart reload *)
                _nDiv := 0;                              (* 分频计数归零 / Divider zero *)
            END_IF
            _nDiv := _nDiv + 1;                          (* 分频计数递进 / Divider advance *)
            IF _nDiv >= _nDwell THEN                     (* 满驻留拍数推进一位（边界④） / Advance one bit *)
                _nDiv := 0;                              (* 分频计数回零 / Divider reset *)
                IF _nLfsr = DWORD#0 THEN
                    _bZero := TRUE;                      (* 全零态检测（边界②） / All-zero detect *)
                END_IF
                IF _bZero THEN
                    _nLfsr := DL_PBS_ONE;                (* 全零强制注入 1 防死序列（边界②） / Inject one on zero *)
                END_IF
                _bFb := FALSE;                           (* 反馈奇偶清零重算 / Parity clear recompute *)
                FOR _i := 0 TO 30 DO                     (* 抽头位扫描（0..30 有界） / Tap bit scan *)
                    IF (_nTapMsk AND SHL(DL_PBS_ONE, _i)) <> DWORD#0 THEN    (* 该位在抽头集内 / Bit in tap set *)
                        IF (_nLfsr AND SHL(DL_PBS_ONE, _i)) <> DWORD#0 THEN  (* 该位为 1 / Bit is one *)
                            _bFb := NOT _bFb;            (* 异或奇偶累加 / XOR parity accumulate *)
                        END_IF
                    END_IF
                END_FOR
                _nLfsr := SHR(_nLfsr, 1);                (* 右移推进 / Shift advance *)
                IF _bFb THEN
                    _nLfsr := _nLfsr OR SHL(DL_PBS_ONE, _nDegree - 1);   (* 反馈位插入最高位 / Insert feedback bit *)
                END_IF
                IF nBitCnt < DL_PBS_CNTMAX THEN
                    nBitCnt := nBitCnt + UDINT#1;        (* 推进计数净额累加（饱和） / Bit count accumulate *)
                END_IF
            END_IF
            bOut := (_nLfsr AND DL_PBS_ONE) = DL_PBS_ONE;    (* 位输出 = LFSR 最低位（位等比较） / Output = LFSR LSB *)
        END_IF
    E_DL_PbsState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PbsState.eFault;                 (* 迁故障相 / To fault *)
        _bFault := TRUE;                                 (* 同步锁存 / Latch *)
        _eCause := E_DL_PbsCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
