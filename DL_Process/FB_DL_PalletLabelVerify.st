(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PalletLabelVerify
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / MID / LEN / MOD），零厂商私有库
 * 功能描述 (Function)   : 托盘标签 EAN-13 校验与错标拦截。触发沿对 13 位码
 *                         串做三段校验：① 长度 = 13；② 逐位数字字符域；
 *                         ③ 校验位复算（位 1..12 权 1/3 交替，chk = (10 -
 *                         Σ mod 10) mod 10 对位 13）。任一段失败即拦截
 *                         bReject 并给出独立错因分码（R190）。与 Crc16Modbus/
 *                         StringTrim（原子件）分工：本件是分段+复算+拦截的
 *                         组合契约件。
 * 来源标签 (Origin)     : ROADMAP §19.4 R12 池（L832），自研 clean-room
 * 边界语义 (Boundary)   : ① 字符提取用标准 MID（下标 1..13 结构性有界）；
 *                         ② 非数字字符在逐位域闸拦截（短路计错即停扫描）；
 *                         ③ 校验复算的 MOD 只作用于非负 INT 和（结构性安全）；
 *                         ④ 长度闸先行：长度不对不进逐位扫描（省时且防越界）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 判定输出冻结保持；eFault
 *                         相（非法相位兜底）→ 冻结 + bError = TRUE；校验失败
 *                         是业务结果不是 FB 故障（不置 bError）。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 越界（MID 有界）/MOD 非负 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 sCode='4006381333931' → 三段全过，bVerifyOk=TRUE
 *                         （EAN-13 公开标准样例码）；
 *                         V2 sCode='4006381333930'（末位错）→ bChkOk=FALSE，
 *                         eErrKind=eChk，bReject 单拍；
 *                         V3 sCode='40063'（长度 5）→ eErrKind=eLen，不进逐位扫描。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 3 · 序号 11）
 *==============================================================================*)
TYPE E_DL_PlvErrKind :
(
    eOk    := 0,                             (* 校验通过 / Verify pass *)
    eLen   := 1,                             (* 长度不为 13 / Length fault *)
    eChar  := 2,                             (* 存在非数字字符 / Non-digit char *)
    eChk   := 3                              (* 校验位复算不符 / Check-digit mismatch *)
);
END_TYPE

TYPE E_DL_PlvState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eCheck := 10,                            (* 校验运行 / Check run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_PlvCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    ePhaseBad := 3                           (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PalletLabelVerify
VAR_INPUT
    sCode     : STRING := '';                (* 待校验码串（触屏/扫码器接入）[-] / Code string *)
    bVerifyReq: BOOL := FALSE;               (* 校验触发电平（上升沿执行）[-] / Verify trigger *)
    bEnable   : BOOL := TRUE;                (* 使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bVerifyOk : BOOL;                        (* 三段校验全过（保持到下个触发沿）[-] / Verify verdict *)
    bLenOk    : BOOL;                        (* 长度段结果 [-] / Length verdict *)
    bCharOk   : BOOL;                        (* 字符域段结果 [-] / Char verdict *)
    bChkOk    : BOOL;                        (* 校验位段结果 [-] / Check-digit verdict *)
    eErrKind  : E_DL_PlvErrKind;             (* 错因分码（信息级逐拍重算，R189） / Error kind *)
    bReject   : BOOL;                        (* 拦截单拍位 [-] / Reject pulse *)
    nVerifyCnt: UDINT;                       (* 累计校验次数 [次] / Verify count *)
    eState    : E_DL_PlvState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_PlvCause;               (* 故障成因出口 / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_PlvState := E_DL_PlvState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_PlvCause := E_DL_PlvCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReq     : R_TRIG;                      (* 触发沿实例，段 0 无条件调用 / Trigger edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _nLen     : INT;                         (* 码串长度工作量 [字符] / Length work *)
    _i        : INT;                         (* 位扫描游标（每趟重置，R227）[-] / Digit cursor *)
    _c        : STRING(1);                   (* 当前位单字符工作量 [-] / Current char work *)
    _nD       : INT;                         (* 当前位数值工作量 [-] / Digit value work *)
    _nSum     : INT;                         (* 加权和工作量 [-] / Weighted sum work *)
    _nChk     : INT;                         (* 复算校验位工作量 [-] / Recomputed check work *)
    _bCharBad : BOOL;                        (* 本串含非数字当拍量 [-] / Non-digit flag *)
    _nVerC    : UDINT;                       (* 校验计数锁存 [次] / Verify count latch *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
END_VAR
VAR CONSTANT
    DL_PLV_EANLEN : INT := 13;               (* EAN-13 码长 [字符] / EAN-13 length *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A） —— *)
rtReq(CLK := bVerifyReq);                    (* 触发沿每拍必调 / Trigger edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
bReject := FALSE;                            (* 拦截脉冲预清，唯一分支置位 / Reject preset *)
eErrKind := E_DL_PlvErrKind.eOk;             (* 错因预置通过（判定分支覆盖） / Err kind preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清判定出口 + 清计数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_PlvCause.eNone;          (* 清成因 / Clear cause *)
    bVerifyOk := FALSE;                      (* 清判定出口 / Clear verdict outlet *)
    bLenOk := FALSE;                         (* 清长度段出口 / Clear len outlet *)
    bCharOk := FALSE;                        (* 清字符段出口 / Clear char outlet *)
    bChkOk := FALSE;                         (* 清校验段出口 / Clear chk outlet *)
    _nVerC := 0;                             (* 清计数 / Clear count *)
    _eState := E_DL_PlvState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PlvState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_PlvState.eCheck; (* 进入校验 / Enter check *)
        END_IF
    E_DL_PlvState.eCheck:                    (* 校验相：三段串行闸 / Check *)
        IF NOT bEnable THEN
            _eState := E_DL_PlvState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSIF rtReq.Q THEN                   (* 触发沿执行 / On trigger edge *)
            _nVerC := _nVerC + 1;            (* 校验计数（UDINT 回绕工程安全） / Count verify *)
            _nLen := LEN(sCode);             (* 长度段（标准 LEN） / Length stage *)
            bLenOk := (_nLen = DL_PLV_EANLEN);   (* 长度判定 / Length verdict *)
            bCharOk := FALSE;                (* 字符段预置（短路语义：长度错时保持 FALSE） / Char preset *)
            bChkOk := FALSE;                 (* 校验段预置 / Chk preset *)
            bVerifyOk := FALSE;              (* 总判定预置（各通过段刷新） / Verdict preset *)
            IF bLenOk THEN
                _i := 1;                     (* 位游标重置（R227） / Digit cursor reset *)
                _bCharBad := FALSE;          (* 非数字标志重置 / Non-digit reset *)
                _nSum := 0;                  (* 加权和重置 / Sum reset *)
                WHILE _i <= 12 DO            (* 位 1..12：字符域 + 加权和（MID 下标 1..13 有界，边界①） / Digits 1..12 *)
                    _c := MID(sCode, 1, _i); (* 单字符提取（标准 MID） / Extract char *)
                    IF _c = '0' THEN
                        _nD := 0;            (* 数字 0 / Digit 0 *)
                    ELSIF _c = '1' THEN
                        _nD := 1;            (* 数字 1 / Digit 1 *)
                    ELSIF _c = '2' THEN
                        _nD := 2;            (* 数字 2 / Digit 2 *)
                    ELSIF _c = '3' THEN
                        _nD := 3;            (* 数字 3 / Digit 3 *)
                    ELSIF _c = '4' THEN
                        _nD := 4;            (* 数字 4 / Digit 4 *)
                    ELSIF _c = '5' THEN
                        _nD := 5;            (* 数字 5 / Digit 5 *)
                    ELSIF _c = '6' THEN
                        _nD := 6;            (* 数字 6 / Digit 6 *)
                    ELSIF _c = '7' THEN
                        _nD := 7;            (* 数字 7 / Digit 7 *)
                    ELSIF _c = '8' THEN
                        _nD := 8;            (* 数字 8 / Digit 8 *)
                    ELSIF _c = '9' THEN
                        _nD := 9;            (* 数字 9 / Digit 9 *)
                    ELSE
                        _nD := -1;           (* 非数字哨兵 / Non-digit sentinel *)
                        _bCharBad := TRUE;   (* 置非数字标志 / Set flag *)
                    END_IF
                    IF (NOT _bCharBad) AND (_nD >= 0) THEN   (* 域内才累计（短路计错即停，边界②） / Accumulate in-domain *)
                        IF (_i MOD 2) = 1 THEN
                            _nSum := _nSum + _nD;        (* 奇位权 1 / Odd weight 1 *)
                        ELSE
                            _nSum := _nSum + 3 * _nD;    (* 偶位权 3 / Even weight 3 *)
                        END_IF
                    END_IF
                    _i := _i + 1;            (* 游标递进 / Cursor advance *)
                END_WHILE
                bCharOk := NOT _bCharBad;    (* 字符段判定 / Char verdict *)
                IF bCharOk THEN
                    _nChk := (10 - (_nSum MOD 10)) MOD 10;   (* 校验位复算（Σ >= 0 非负，MOD 结构性安全，边界③） / Recompute check digit *)
                    _c := MID(sCode, 1, 13); (* 第 13 位字符 / 13th char *)
                    IF ((_nChk = 0) AND (_c = '0')) OR ((_nChk = 1) AND (_c = '1'))
                       OR ((_nChk = 2) AND (_c = '2')) OR ((_nChk = 3) AND (_c = '3'))
                       OR ((_nChk = 4) AND (_c = '4')) OR ((_nChk = 5) AND (_c = '5'))
                       OR ((_nChk = 6) AND (_c = '6')) OR ((_nChk = 7) AND (_c = '7'))
                       OR ((_nChk = 8) AND (_c = '8')) OR ((_nChk = 9) AND (_c = '9')) THEN
                        bChkOk := TRUE;      (* 校验位匹配 / Chk match *)
                    END_IF
                END_IF
                bVerifyOk := bChkOk;         (* 总判定（长度与字符段已过） / Verdict *)
                IF NOT bLenOk THEN
                    eErrKind := E_DL_PlvErrKind.eLen;    (* 错因：长度 / Kind: length *)
                ELSIF NOT bCharOk THEN
                    eErrKind := E_DL_PlvErrKind.eChar;   (* 错因：字符（独立分码，R190） / Kind: char *)
                ELSIF NOT bChkOk THEN
                    eErrKind := E_DL_PlvErrKind.eChk;    (* 错因：校验位（独立分码） / Kind: chk *)
                END_IF
                bReject := NOT bVerifyOk;    (* 拦截单拍（错标即拦） / Reject on fail *)
            ELSE
                eErrKind := E_DL_PlvErrKind.eLen;    (* 长度闸先行（边界④） / Length gate first *)
                bReject := TRUE;             (* 拦截单拍 / Reject pulse *)
            END_IF
        END_IF
    E_DL_PlvState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PlvState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_PlvCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nVerifyCnt := _nVerC;                        (* 校验计数出口 / Count outlet *)
bError := _bFault;                           (* 故障标志镜像（业务拒绝不置 bError，输出语义声明） / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
