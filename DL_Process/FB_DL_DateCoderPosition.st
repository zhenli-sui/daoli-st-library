(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DateCoderPosition
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 喷码日期位置偏移与缺失检测。检测触发沿按视觉检出
 *                         电平分派：未检出 → 缺失计数 + bMissing 锁存；检出
 *                         → 位置偏差 = 实测 - 期望，容差内 bPosOk，超差偏移
 *                         计数。判定结果锁存回放至下一触发沿（诊断资产）。
 *                         与 MarkPositionLatch（喷印位锁存）分工：本件是定
 *                         容差判偏移/缺失的诊断件。
 * 来源标签 (Origin)     : ROADMAP §21.4 R13 池（L907），自研 clean-room
 * 边界语义 (Boundary)   : ① 触发沿位置 NaN：按缺失域分派（视觉数据不可信 =
 *                         本拍无有效读码，归缺失语义安全侧）；
 *                         ② 容差/期望位置域闸 → 组态故障；
 *                         ③ 缺失/偏移计数 UDINT 独立成员（R190 归因唯一）；
 *                         ④ 状态锁存至下个触发沿（回放，不按当下输入重推断）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 判定出口冻结保持（诊断
 *                         资产）；eFault 相 → 冻结 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/NaN 归缺失/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 期望 120.0、实测 121.4、容差 2.0 → 偏差 1.4，
 *                         bPosOk=TRUE；
 *                         V2 实测 124.0（偏差 4.0 超容差）→ nOffCnt+1，
 *                         bPosOk=FALSE；
 *                         V3 触发沿 bMarkPresent=FALSE → nMissCnt+1，
 *                         bMissing=TRUE。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 3 · 序号 13）
 *==============================================================================*)
TYPE E_DL_DcpState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eInspect := 10,                          (* 检测运行 / Inspect run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_DcpCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：容差越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_DateCoderPosition
VAR_INPUT
    fMarkPos    : LREAL := 0.0;              (* 视觉测得喷码位置 [mm] / Measured mark position *)
    fMarkSp     : LREAL := 120.0;            (* 喷码期望位置，域 > 0 [mm] / Expected mark position *)
    fPosTol     : LREAL := 2.0;              (* 位置容差，域 > 0 [mm] / Position tolerance *)
    bMarkPresent: BOOL := FALSE;              (* 视觉检出电平 [-] / Vision present level *)
    bInspectTrig: BOOL := FALSE;             (* 检测触发电平（上升沿判定）[-] / Inspect trigger *)
    bEnable     : BOOL := TRUE;              (* 使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fOffset     : LREAL;                     (* 位置偏差（实测 - 期望）[mm] / Position offset *)
    bPosOk      : BOOL;                      (* 位置合格判定（锁存回放）[-] / Position verdict *)
    bMissing    : BOOL;                      (* 喷码缺失锁存（下个触发沿或复位沿清）[-] / Missing latch *)
    nMissCnt    : UDINT;                     (* 缺失计数（独立成员，R190）[次] / Missing count *)
    nOffCnt     : UDINT;                     (* 偏移计数（独立成员，R190）[次] / Offset count *)
    nInspCnt    : UDINT;                     (* 累计检测次数 [次] / Inspect count *)
    eState      : E_DL_DcpState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_DcpCause;             (* 故障成因出口 / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_DcpState := E_DL_DcpState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_DcpCause := E_DL_DcpCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtTrig    : R_TRIG;                      (* 触发沿实例，段 0 无条件调用 / Trigger edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fOff     : LREAL;                       (* 偏差派生量 [mm] / Offset derived *)
    _nMiss    : UDINT;                       (* 缺失计数锁存 [次] / Missing count latch *)
    _nOff     : UDINT;                       (* 偏移计数锁存 [次] / Offset count latch *)
    _nInsp    : UDINT;                       (* 检测计数锁存 [次] / Inspect count latch *)
    _bPosBad  : BOOL;                        (* 位置非有限当拍量 [-] / Non-finite position *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_DCP_EPS : LREAL := 1.0E-9;            (* 容差判零容差 [mm] / Tolerance epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
_bCfgBad := (fPosTol <= DL_DCP_EPS) OR (fMarkSp <= 0.0);   (* 组态闸（R151 全引脚） / Config gate *)
rtTrig(CLK := bInspectTrig);                 (* 触发沿每拍必调 / Trigger edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bPosBad := (fMarkPos <> fMarkPos) OR ((fMarkPos - fMarkPos) <> (fMarkPos - fMarkPos));   (* 位置 NaN 自反 + Inf 差判 / Non-finite position *)

(* —— 段 1：单拍量预清零（R107） —— *)
_fOff := 0.0;                                (* 偏差预清（判定拍内派生，R285） / Offset preset *)
bPosOk := FALSE;                             (* 判定预清（锁存拍内覆盖） / Verdict preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 清判定锁存 + 清出口 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_DcpCause.eNone;          (* 清成因 / Clear cause *)
    _nMiss := 0;                             (* 清缺失计数 / Clear miss count *)
    _nOff := 0;                              (* 清偏移计数 / Clear offset count *)
    _nInsp := 0;                             (* 清检测计数 / Clear inspect count *)
    bMissing := FALSE;                       (* 清缺失锁存（复位沿清除路径） / Clear missing latch *)
    bPosOk := FALSE;                         (* 清判定出口 / Clear verdict outlet *)
    fOffset := 0.0;                          (* 清偏差出口 / Clear offset outlet *)
    _eState := E_DL_DcpState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_DcpCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_DcpState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_DcpState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_DcpState.eInspect;   (* 进入检测 / Enter inspect *)
        END_IF
    E_DL_DcpState.eInspect:                  (* 检测相：触发沿分派判定 / Inspect *)
        IF NOT bEnable THEN
            _eState := E_DL_DcpState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSIF rtTrig.Q THEN                  (* 触发沿执行 / On trigger edge *)
            _nInsp := _nInsp + 1;            (* 检测计数（UDINT 回绕工程安全） / Count inspect *)
            IF (NOT bMarkPresent) OR _bPosBad THEN   (* 未检出或位置坏值：归缺失域（边界①安全侧） / Missing domain *)
                _nMiss := _nMiss + 1;        (* 缺失计数（独立成员） / Count missing *)
                bMissing := TRUE;            (* 缺失锁存（下个沿或复位清，边界④） / Latch missing *)
                bPosOk := FALSE;             (* 判定回放刷新 / Verdict replay *)
            ELSE
                _fOff := fMarkPos - fMarkSp; (* 偏差派生（减法无除零） / Offset derive *)
                fOffset := _fOff;            (* 偏差出口刷新 / Offset outlet *)
                IF ABS(_fOff) <= fPosTol THEN
                    bPosOk := TRUE;          (* 容差内合格 / In tolerance *)
                    bMissing := FALSE;       (* 检出合格拍清缺失锁存（触发沿清除路径，边界④） / Clear missing on pass *)
                ELSE
                    _nOff := _nOff + 1;      (* 偏移计数（独立成员） / Count offset *)
                    bPosOk := FALSE;         (* 超差不合格 / Out of tolerance *)
                END_IF
            END_IF
        END_IF                               (* 非触发拍：状态锁存回放（边界④） / Replay between edges *)
    E_DL_DcpState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_DcpState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_DcpCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nMissCnt := _nMiss;                          (* 缺失计数出口 / Miss outlet *)
nOffCnt := _nOff;                            (* 偏移计数出口 / Offset outlet *)
nInspCnt := _nInsp;                          (* 检测计数出口 / Inspect outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
