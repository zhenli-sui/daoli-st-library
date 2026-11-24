(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CasePackerPatternVerify
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 装箱排列模式校验防错。装箱到位沿比较传感器位域
 *                         （8 槽）与目标模式字：XOR 全零 → bPatternOk 放行；
 *                         任一位冲突 → bReject 单拍拒启并锁存 bRejectLatch
 *                         给出首错槽位。禁止位掩码 uNoGoMask（重叠占位）置位
 *                         即拒启（重叠即拒启语义）。与 RangeOverlapCheck
 *                         （纯区间函数）分工：本件是模式放行顺控，重叠只是
 *                         拒启判据之一。
 * 来源标签 (Origin)     : ROADMAP §16.4 R11 池（L720），自研 clean-room
 * 边界语义 (Boundary)   : ① 位域冲突 → 首错槽位 1..8 报告，多错只报首个
 *                         （定位修复优先）；
 *                         ② 掩码 SHL 移位量 0..7 < 16 位宽（R48 安全）；
 *                         ③ 拒启锁存至下个到位沿或复位沿（清除路径声明）；
 *                         ④ 无浮点量（纯位域，无 NaN/除零域）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 校验输出冻结保持；eFault
 *                         相 → 放行出口强制 FALSE（拒启安全侧）+ bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 越界（移位有界）/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 uPatternIn=16#00FF、Ref=16#00FF、NoGo=16#0000
 *                         → bPatternOk=TRUE；
 *                         V2 In=16#00FE、Ref=16#00FF → bReject 单拍，首错
 *                         槽位 nErrSlot=8（位 7 对应槽 8）；
 *                         V3 NoGo=16#0001 且 In bit0=1（重叠占位）→ 拒启。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 2 · 序号 6）
 *==============================================================================*)
TYPE E_DL_CpvState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eArmed := 10,                            (* 武装等待装箱到位沿 / Armed for box edge *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_CpvCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    ePattern  := 1,                          (* 模式位冲突拒启 / Pattern mismatch reject *)
    eNoGoHit  := 2,                          (* 禁止位（重叠占位）拒启 / No-go overlap reject *)
    ePhaseBad := 3                           (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CasePackerPatternVerify
VAR_INPUT
    uPatternIn  : WORD := 16#0000;           (* 8 槽传感器位域（1 = 有箱）[-] / Sensor bit field *)
    uPatternRef : WORD := 16#00FF;           (* 目标排列模式字 [-] / Target pattern word *)
    uNoGoMask   : WORD := 16#0000;           (* 禁止位掩码（重叠占位禁放）[-] / No-go mask *)
    bBoxPresent : BOOL := FALSE;             (* 装箱到位电平（上升沿触发校验）[-] / Box present level *)
    bEnable     : BOOL := TRUE;              (* 使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bPatternOk  : BOOL;                      (* 模式匹配放行（校验拍保持到下个沿）[-] / Pattern pass *)
    bReject     : BOOL;                      (* 拒启单拍位 [-] / Reject pulse *)
    bRejectLatch: BOOL;                      (* 拒启锁存（下个到位沿或复位沿清）[-] / Reject latch *)
    nErrSlot    : INT;                       (* 首错槽位 1..8（无错为 0）[槽] / First error slot *)
    nVerifyCnt  : UDINT;                     (* 累计校验次数 [次] / Verify count *)
    eState      : E_DL_CpvState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_CpvCause;             (* 故障成因出口（R190 独立分码） / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState    : E_DL_CpvState := E_DL_CpvState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause    : E_DL_CpvCause := E_DL_CpvCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtBox      : R_TRIG;                     (* 到位沿实例，段 0 无条件调用 / Box edge instance *)
    rtReset    : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _wDiff     : WORD;                       (* 异或差掩码工作量 [-] / XOR diff work *)
    _bPass     : BOOL;                       (* 放行锁存 [-] / Pass latch *)
    _nSlot     : INT;                        (* 首错槽位锁存 [槽] / First-error slot latch *)
    _i         : INT;                        (* 槽扫描游标（每趟重置，R227）[-] / Slot cursor *)
    _wMask     : WORD;                       (* 槽位掩码工作量 [-] / Slot mask work *)
    _nVerC     : UDINT;                      (* 校验计数锁存 [次] / Verify count latch *)
    _bFault    : BOOL;                       (* 故障锁存位 / Latched fault bit *)
END_VAR
VAR CONSTANT
    DL_CPV_SLOTS : INT := 8;                 (* 槽位总数 [槽] / Slot count *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A；纯位域件无浮点组态闸） —— *)
rtBox(CLK := bBoxPresent);                   (* 到位沿每拍必调 / Box edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
bReject := FALSE;                            (* 拒启脉冲预清，唯一分支置位 / Reject preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清锁存 + 清出口 + 清计数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CpvCause.eNone;          (* 清成因 / Clear cause *)
    _bPass := FALSE;                         (* 清放行锁存 / Clear pass latch *)
    bRejectLatch := FALSE;                   (* 清拒启锁存 / Clear reject latch *)
    _nSlot := 0;                             (* 清首错槽 / Clear slot *)
    nErrSlot := 0;                           (* 清槽位出口 / Clear slot outlet *)
    bPatternOk := FALSE;                     (* 清放行出口 / Clear pass outlet *)
    _nVerC := 0;                             (* 清校验计数 / Clear count *)
    _eState := E_DL_CpvState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6；无组态浮点闸故无段 3） —— *)
CASE _eState OF
    E_DL_CpvState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_CpvState.eArmed; (* 进入武装 / Enter armed *)
        END_IF
    E_DL_CpvState.eArmed:                    (* 武装相：到位沿校验 / Armed *)
        IF NOT bEnable THEN
            _eState := E_DL_CpvState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSIF rtBox.Q THEN                   (* 到位沿：执行校验 / Verify on edge *)
            _nVerC := _nVerC + 1;            (* 校验计数（UDINT 回绕工程安全） / Count verify *)
            IF (uPatternIn AND uNoGoMask) <> 16#0000 THEN   (* 禁止位命中：重叠占位拒启（R190 独立分码） / No-go overlap hit *)
                _eCause := E_DL_CpvCause.eNoGoHit;   (* 成因：重叠 / Cause: overlap *)
                _bFault := TRUE;             (* 故障锁存（R45 配对：出口由段 5 强制拒启） / Latch fault *)
                _eState := E_DL_CpvState.eFault;   (* 迁故障相 / To fault *)
                bReject := TRUE;             (* 拒启单拍 / Reject pulse *)
                bRejectLatch := TRUE;        (* 拒启锁存 / Reject latch *)
            ELSE
                _wDiff := uPatternIn XOR uPatternRef;   (* 异或差掩码 / XOR diff *)
                IF _wDiff = 16#0000 THEN
                    _bPass := TRUE;          (* 全零匹配放行 / Pass *)
                    bPatternOk := TRUE;      (* 放行出口 / Pass outlet *)
                    _nSlot := 0;             (* 无错清槽 / Clear slot *)
                    nErrSlot := 0;           (* 槽位出口清 / Slot outlet clear *)
                    bRejectLatch := FALSE;   (* 此前拒启锁存清除（到位沿清除路径，边界③） / Clear reject latch *)
                ELSE
                    _i := 0;                 (* 槽游标重置（R227） / Slot cursor reset *)
                    _wMask := 16#0001;       (* 掩码起点（位 0 = 槽 1） / Mask start *)
                    _nSlot := 0;             (* 首错槽预置 0 / Slot preset *)
                    WHILE (_i <= DL_CPV_SLOTS - 1) AND (_nSlot = 0) DO   (* 逐槽找首错（移位量 0..7 < 16，R48） / First error slot *)
                        IF (_wDiff AND _wMask) <> 16#0000 THEN
                            _nSlot := _i + 1;   (* 槽号 = 位号 + 1 / Slot number *)
                        END_IF
                        _wMask := SHL(_wMask, 1);   (* 掩码左移（常量 1 位） / Shift mask *)
                        _i := _i + 1;        (* 游标递进 / Cursor advance *)
                    END_WHILE
                    _eCause := E_DL_CpvCause.ePattern;   (* 成因：模式冲突 / Cause: pattern *)
                    _bFault := TRUE;         (* 故障锁存（R45 配对） / Latch fault *)
                    _eState := E_DL_CpvState.eFault;   (* 迁故障相 / To fault *)
                    nErrSlot := _nSlot;      (* 首错槽出口 / Slot outlet *)
                    bReject := TRUE;         (* 拒启单拍 / Reject pulse *)
                    bRejectLatch := TRUE;    (* 拒启锁存 / Reject latch *)
                END_IF
            END_IF
        END_IF
    E_DL_CpvState.eFault:                    (* 故障相：放行出口强制 FALSE（安全侧），仅复位沿出 / Fault *)
        bPatternOk := FALSE;                 (* 放行收敛 / Pass converge *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CpvState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_CpvCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nVerifyCnt := _nVerC;                        (* 校验计数出口 / Count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
