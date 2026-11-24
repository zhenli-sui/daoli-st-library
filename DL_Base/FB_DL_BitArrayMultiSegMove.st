(*
  Name        : FB_DL_BitArrayMultiSegMove
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 位数组多段一次搬：单遍遍历段表（目的/源起位 + 宽度数组）在双字数组间批量搬移，搬前整表重叠预检一次拒；/ Multi-segment bit-array bulk move: one pass over a segment table (dest/src bit offset plus width arrays) between DWORD word arrays, with a whole-table overlap precheck before any copy
  溯源        : 借 lgf-bitlogic 的分类/参数域组织，clean-room 实现
  Boundary    : ① 段宽 > 64 → 锁存故障（拒绝拆半字搬，整表不动）；
                ② 段间目的区间重叠（两两交叠预检）→ 整表一次拒，不搬半截，锁存故障至复位沿；
                ③ 移位量一律 MOD 32 归一、按位搬运，全程无 64 位移位（R28 双字安全口径）；
                ④ 段数 0 = 幂等直通：bDone 照发、不置错、不动数组；
                ⑤ 数组读写只经输入输出引用参数，零外部全局、零物理地址；
                ⑥ 字号/位偏越域逐段校验，任一越域整表拒搬并锁存故障。
*)
TYPE E_DL_BsmState :
(
    eIdle  := 0,                             (* 等待执行沿 / Wait for execute edge *)
    eRun   := 10,                            (* 预检 + 单遍搬运执行中 / Precheck and one-pass move *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_BsmCause :
(
    eNone      := 0,                         (* 无故障成因 / No cause *)
    eWidthIll  := 1,                        (* 段宽 > 64 或 < 1 / Segment width out of domain *)
    eOverlap   := 2,                        (* 段间目的区间重叠 / Destination ranges overlap *)
    eIdxIll    := 3,                        (* 字号/位偏越域 / Word or bit index out of domain *)
    ePhaseBad  := 4                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BitArrayMultiSegMove
VAR_INPUT
    nSeg     : INT := 0;                    (* 段数（0 = 幂等直通），域 0..16 [段] / Segment count, 0 = pass-through *)
    aDstW    : ARRAY[1..16] OF INT;         (* 各段目的字号，域 1..64 [字] / Dest word index per segment *)
    aDstB    : ARRAY[1..16] OF INT;         (* 各段目的位偏，域 0..31 [位] / Dest bit offset per segment *)
    aSrcW    : ARRAY[1..16] OF INT;         (* 各段源字号，域 1..64 [字] / Source word index per segment *)
    aSrcB    : ARRAY[1..16] OF INT;         (* 各段源位偏，域 0..31 [位] / Source bit offset per segment *)
    aWid     : ARRAY[1..16] OF INT;         (* 各段宽度，域 1..64 [位] / Width per segment *)
    bExec    : BOOL := FALSE;               (* 执行命令，上升沿触发一次整表搬运 [-] / Execute command, edge triggered *)
    bReset   : BOOL := FALSE;               (* 复位命令，上升沿清故障 [-] / Reset command *)
END_VAR
VAR_IN_OUT
    aSrcWords: ARRAY[1..64] OF DWORD;       (* 源位数组（双字字数组）[-] / Source bit array as words *)
    aDstWords: ARRAY[1..64] OF DWORD;       (* 目的位数组（双字字数组）[-] / Dest bit array as words *)
END_VAR
VAR_OUTPUT
    bDone    : BOOL;                        (* 本拍整表搬运完成（单拍脉冲）[-] / Move done this scan pulse *)
    nMovedBit: UDINT;                       (* 本次实际搬移位数 [位] / Bits moved this pass *)
    eState   : E_DL_BsmState;               (* 状态出口 / State outlet *)
    eCause   : E_DL_BsmCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError   : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_BsmState := E_DL_BsmState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_BsmCause := E_DL_BsmCause.eNone;  (* 故障成因锁存量 / Latched cause *)
    rtExec  : R_TRIG;                       (* 执行沿实例，段 0 无条件调用 / Execute edge instance *)
    rtReset : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bDoneI : BOOL;                         (* 完成脉冲内部量（统一出口映射，R187） / Done pulse internal *)
    _i      : INT;                          (* 段表外层游标 [段] / Segment outer cursor *)
    _j      : INT;                          (* 段表内层游标（重叠两两预检）[段] / Segment inner cursor *)
    _dI     : UDINT;                        (* 第 i 段目的线性起位 [位] / Dest linear start of seg i *)
    _dJ     : UDINT;                        (* 第 j 段目的线性起位 [位] / Dest linear start of seg j *)
    _eI     : UDINT;                        (* 第 i 段目的线性尾位 [位] / Dest linear end of seg i *)
    _eJ     : UDINT;                        (* 第 j 段目的线性尾位 [位] / Dest linear end of seg j *)
    _nSum   : UDINT;                        (* 本次累计搬移位数中间量 [位] / Moved bits accumulator *)
    _nSegE  : INT;                          (* 钳位后生效段数 [段] / Effective segment count *)
    _k      : INT;                          (* 位搬运游标 [位] / Bit copy cursor *)
    _sLin   : UDINT;                        (* 源线性位址 [位] / Source linear bit address *)
    _dLin   : UDINT;                        (* 目的线性位址 [位] / Dest linear bit address *)
    _nSw    : INT;                          (* 源字号（线性位址除 32 派生）[字] / Source word index *)
    _nDw    : INT;                          (* 目的字号（线性位址除 32 派生）[字] / Dest word index *)
    _nSb    : INT;                          (* 源位偏（MOD 32 归一派生）[位] / Source bit offset *)
    _nDb    : INT;                          (* 目的位偏（MOD 32 归一派生）[位] / Dest bit offset *)
    _dMsk   : DWORD;                        (* 位掩码（常量 1 移位 MOD 32 归一派生）[-] / Bit mask *)
END_VAR
VAR CONSTANT
    DL_BSM_WMAX : INT   := 64;              (* 字数组容量上限 [字] / Word array capacity *)
    DL_BSM_SMAX : INT   := 16;              (* 段表容量上限 [段] / Segment table capacity *)
    DL_BSM_WMAX64: INT  := 64;              (* 单段宽度上限（边界①）[位] / Single width limit *)
    DL_BSM_BIT  : INT   := 32;              (* 每字位宽（移位归一基数）[位] / Bits per word *)
END_VAR

(* —— 段 0：实例无条件刷新（R228A） —— *)
rtExec(CLK := bExec);                                                       (* 执行沿每拍必调 / Execute edge every scan *)
rtReset(CLK := bReset);                                                     (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
bDone := FALSE;                                                             (* 完成脉冲出口预清 / Done pulse preset *)
_bDoneI := FALSE;                                                           (* 完成脉冲内部量预清 / Done internal preset *)
nMovedBit := 0;                                                             (* 搬移位数出口预清 / Moved bits preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清成因 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                       (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_BsmCause.eNone;                                         (* 清成因 / Clear cause *)
    _eState := E_DL_BsmState.eIdle;                                         (* 迁等待相 / Back to idle *)
END_IF

(* —— 段 3：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_BsmState.eIdle:                                                    (* 等待执行沿 / Wait edge *)
        IF rtExec.Q AND NOT _bFault THEN
            _eState := E_DL_BsmState.eRun;                                  (* 进入单遍搬运相 / Enter run *)
        END_IF
    E_DL_BsmState.eRun:                                                     (* 预检 + 单遍搬运 / Precheck and move *)
        _nSegE := nSeg;                                                     (* 生效段数初值 / Effective count init *)
        IF _nSegE < 0 THEN
            _nSegE := 0;                                                    (* 负段数归零（幂等直通） / Negative count to zero *)
        END_IF
        IF _nSegE > DL_BSM_SMAX THEN
            _nSegE := DL_BSM_SMAX;                                          (* 段数钳上限（防越界） / Count clamp *)
        END_IF
        IF _nSegE = 0 THEN
            _bDoneI := TRUE;                                                (* 段数 0：幂等直通发完成（边界④） / Zero segs pass-through *)
        ELSE
            (* 逐段域校验：宽度 + 字号 + 位偏 *)
            _i := 1;                                                        (* 校验游标起头 / Check cursor init *)
            WHILE (_i <= _nSegE) AND NOT _bFault DO                         (* 逐段扫 / Per-seg scan *)
                IF (aWid[_i] < 1) OR (aWid[_i] > DL_BSM_WMAX64) THEN        (* 段宽域闸（边界①） / Width gate *)
                    _bFault := TRUE;                                        (* 锁存故障 / Latch fault *)
                    _eCause := E_DL_BsmCause.eWidthIll;                     (* 成因：段宽越域 / Cause width *)
                ELSIF (aDstW[_i] < 1) OR (aDstW[_i] > DL_BSM_WMAX) OR (aSrcW[_i] < 1) OR (aSrcW[_i] > DL_BSM_WMAX)
                     OR (aDstB[_i] < 0) OR (aDstB[_i] > DL_BSM_BIT - 1) OR (aSrcB[_i] < 0) OR (aSrcB[_i] > DL_BSM_BIT - 1) THEN
                    _bFault := TRUE;                                        (* 字号/位偏越域锁故障 / Index fault *)
                    _eCause := E_DL_BsmCause.eIdxIll;                       (* 成因：下标越域 / Cause index *)
                END_IF
                _i := _i + 1;                                               (* 游标递进 / Cursor advance *)
            END_WHILE
            (* 重叠两两预检：任一交叠 → 整表一次拒（边界②） *)
            _i := 1;                                                        (* 外层游标重置 / Outer cursor reset *)
            WHILE (_i < _nSegE) AND NOT _bFault DO                          (* 两两配对 / Pairwise pairs *)
                _j := _i + 1;                                               (* 内层游标 / Inner cursor *)
                WHILE (_j <= _nSegE) AND NOT _bFault DO                     (* 内层扫 / Inner scan *)
                    _dI := UDINT(aDstW[_i] - 1) * UDINT(DL_BSM_BIT) + UDINT(aDstB[_i]);   (* i 段目的线性起位 / Dest start i *)
                    _dJ := UDINT(aDstW[_j] - 1) * UDINT(DL_BSM_BIT) + UDINT(aDstB[_j]);   (* j 段目的线性起位 / Dest start j *)
                    _eI := _dI + UDINT(aWid[_i]) - UDINT(1);                (* i 段线性尾位 / Dest end i *)
                    _eJ := _dJ + UDINT(aWid[_j]) - UDINT(1);                (* j 段线性尾位 / Dest end j *)
                    IF (_dI <= _eJ) AND (_dJ <= _eI) THEN                   (* 区间交叠判定 / Range intersect *)
                        _bFault := TRUE;                                    (* 整表拒绝锁故障 / Reject whole table *)
                        _eCause := E_DL_BsmCause.eOverlap;                  (* 成因：区间重叠 / Cause overlap *)
                    END_IF
                    _j := _j + 1;                                           (* 内层递进 / Inner advance *)
                END_WHILE
                _i := _i + 1;                                               (* 外层递进 / Outer advance *)
            END_WHILE
            (* 预检通过：单遍按位搬运（移位量 MOD 32 归一，边界③） *)
            _nSum := UDINT#0;                                               (* 搬移位数累加量清零 / Moved bits clear *)
            _i := 1;                                                        (* 段游标起头 / Segment cursor init *)
            WHILE (_i <= _nSegE) AND NOT _bFault DO                         (* 逐段搬 / Per-seg move *)
                _k := 0;                                                    (* 位游标起头 / Bit cursor init *)
                WHILE _k < aWid[_i] DO                                      (* 按位搬 / Bit-wise copy *)
                    _sLin := UDINT(aSrcW[_i] - 1) * UDINT(DL_BSM_BIT) + UDINT(aSrcB[_i]) + UDINT(_k);  (* 源线性位址 / Source address *)
                    _dLin := UDINT(aDstW[_i] - 1) * UDINT(DL_BSM_BIT) + UDINT(aDstB[_i]) + UDINT(_k);  (* 目的线性位址 / Dest address *)
                    _nSw := UDINT_TO_INT(_sLin / UDINT(DL_BSM_BIT)) + 1;    (* 源字号（除子常量非零，防除零） / Source word index *)
                    _nDw := UDINT_TO_INT(_dLin / UDINT(DL_BSM_BIT)) + 1;    (* 目的字号 / Dest word index *)
                    _nSb := UDINT_TO_INT(_sLin MOD UDINT(DL_BSM_BIT));      (* 源位偏 MOD 32 归一（边界③） / Source bit normalized *)
                    _nDb := UDINT_TO_INT(_dLin MOD UDINT(DL_BSM_BIT));      (* 目的位偏 MOD 32 归一（边界③） / Dest bit normalized *)
                    _dMsk := SHL(DWORD#1, _nSb);                            (* 源位掩码（移位量 < 32） / Source bit mask *)
                    IF (aSrcWords[_nSw] AND _dMsk) <> DWORD#0 THEN          (* 读源位（位等比较） / Read source bit *)
                        aDstWords[_nDw] := aDstWords[_nDw] OR SHL(DWORD#1, _nDb);   (* 置目的位 / Set dest bit *)
                    ELSE
                        aDstWords[_nDw] := aDstWords[_nDw] AND NOT SHL(DWORD#1, _nDb);  (* 清目的位 / Clear dest bit *)
                    END_IF
                    _nSum := _nSum + UDINT#1;                               (* 搬移位数净额累加 / Moved bits count *)
                    _k := _k + 1;                                           (* 位游标递进 / Bit cursor advance *)
                END_WHILE
                _i := _i + 1;                                               (* 段游标递进 / Segment advance *)
            END_WHILE
            IF NOT _bFault THEN
                _bDoneI := TRUE;                                            (* 整表完成脉冲 / Done pulse *)
                nMovedBit := _nSum;                                         (* 搬移位数出口 / Moved bits outlet *)
            END_IF
        END_IF
        _eState := E_DL_BsmState.eIdle;                                     (* 回等待相（单遍语义） / Back to idle *)
    E_DL_BsmState.eFault:                                                   (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                                   (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                    (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_BsmState.eFault;                                    (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                    (* 同步锁存 / Latch *)
        _eCause := E_DL_BsmCause.ePhaseBad;                                 (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 4：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bDone := _bDoneI;                                                           (* 完成脉冲单拍出口 / Done pulse outlet *)
bError := _bFault;                                                          (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                          (* 状态出口 / State outlet *)
eCause := _eCause;                                                          (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
