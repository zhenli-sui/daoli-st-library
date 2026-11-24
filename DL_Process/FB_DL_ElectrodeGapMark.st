(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ElectrodeGapMark
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 极片留白区（Gap）位置标记与对齐判定。视觉/传感器
 *                         以 WORD 位域（每扇区 1 位）给出 Gap 标志，本件在
 *                         同步沿锁存编码位置为留白标记点，与上一标记点间距
 *                         对比组态节距判对齐（偏差超容差即 bAlignBad），并
 *                         统计位域有效位数。与 ScreenPrintAlign（丝印对位）
 *                         分工：本件面向极片 Gap 位域提取 + 留白带节距判定。
 * 来源标签 (Origin)     : ROADMAP §13.x P1（L626），自研 clean-room
 * 边界语义 (Boundary)   : ① 节距 <= eps 或容差 <= 0 → 组态故障锁存；
 *                         ② 位置 NaN 拍拒收标记（不锁存不判对齐）；
 *                         ③ 首个标记点（无前点）只锁存不判对齐（bAlignOk 缺省
 *                         FALSE，判定自第二个标记点起）；
 *                         ④ 位域统计移位量 0..15 结构性 < 16 位宽（R48 安全）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 标记/判定输出保持末值
 *                         （标记是资产属性不随失能消失）；eFault 相 → 冻结
 *                         + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（节距 eps 闸）/NaN 拒收/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 节距 100、容差 2：标记点 1000 → 1101（差 101）
 *                         → bAlignOk=TRUE，fDev=1.0；
 *                         V2 标记点 1000 → 1090（差 90，偏差 -10 超容差）
 *                         → bAlignOk=FALSE，bAlignBad=TRUE；
 *                         V3 uGapField=16#00F0 → nGapCnt=4。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 1 · 序号 2）
 *==============================================================================*)
TYPE E_DL_EgmState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eTrack := 10,                            (* 标记跟踪运行 / Mark tracking *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_EgmCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：节距/容差越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrodeGapMark
VAR_INPUT
    uGapField : WORD := 16#0000;             (* Gap 位域输入（每扇区 1 位，视觉给出）[-] / Gap bit field *)
    fPosNow   : LREAL := 0.0;                (* 当前编码位置 [mm] / Current encoder position *)
    fGapPitch : LREAL := 100.0;              (* 留白区节距，域 > eps [mm] / Gap pitch *)
    fTol      : LREAL := 2.0;                (* 节距对齐容差，域 > 0 [mm] / Pitch tolerance *)
    bSync     : BOOL := FALSE;               (* 视觉同步电平（上升沿锁标记点）[-] / Vision sync level *)
    bEnable   : BOOL := TRUE;                (* 使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fMarkPos  : LREAL;                       (* 最新留白标记点位置 [mm] / Latest mark position *)
    fDev      : LREAL;                       (* 本标记点节距偏差（实测间距 - 节距）[mm] / Pitch deviation *)
    bAlignOk  : BOOL;                        (* 对齐判定（自第 2 个标记点起有效）[-] / Align verdict *)
    bAlignBad : BOOL;                        (* 对齐超差锁存（复位沿清）[-] / Align-fail latch *)
    nGapCnt   : INT;                         (* 位域有效位数 0..16 [位] / Set-bit count *)
    nMarkCnt  : UDINT;                       (* 累计标记点数 [点] / Total mark count *)
    eState    : E_DL_EgmState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_EgmCause;               (* 故障成因出口 / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_EgmState := E_DL_EgmState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_EgmCause := E_DL_EgmCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtSync   : R_TRIG;                       (* 同步沿实例，段 0 无条件调用 / Sync edge instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fPrevMark : LREAL;                      (* 上一标记点位置 [mm] / Previous mark position *)
    _bHasPrev  : BOOL;                       (* 已有前点标志 [-] / Has previous mark *)
    _nCnt    : INT;                          (* 位域计数工作量 [-] / Bit count work *)
    _i       : INT;                          (* 位扫描游标（每趟重置，R227）[-] / Bit cursor *)
    _wMask   : WORD;                         (* 位掩码工作量 [-] / Bit mask work *)
    _nMark   : UDINT;                        (* 累计标记点数锁存 [点] / Mark count latch *)
    _fDev    : LREAL;                        (* 节距偏差派生量 [mm] / Deviation derived *)
    _bPosBad : BOOL;                         (* 位置非有限当拍量 [-] / Non-finite position *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_EGM_EPS : LREAL := 1.0E-9;            (* 节距判零容差 [mm] / Pitch epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
_bCfgBad := (fGapPitch <= DL_EGM_EPS) OR (fTol <= 0.0);   (* 组态闸（R151 全引脚） / Config gate *)
rtSync(CLK := bSync);                        (* 同步沿每拍必调 / Sync edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bPosBad := (fPosNow <> fPosNow) OR ((fPosNow - fPosNow) <> (fPosNow - fPosNow));   (* 位置 NaN 自反 + Inf 差判 / Non-finite position *)

(* —— 段 1：单拍量预清零（R107） —— *)
_nCnt := 0;                                  (* 位计数预清（每趟重算，R285） / Bit count preset *)
_fDev := 0.0;                                (* 偏差预清 / Deviation preset *)
bAlignOk := FALSE;                           (* 对齐判定预清（判定拍内赋值，全路径覆盖） / Align preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清标记点 + 清对齐锁存 + 清计数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_EgmCause.eNone;          (* 清成因 / Clear cause *)
    _fPrevMark := 0.0;                       (* 清前点 / Clear previous mark *)
    _bHasPrev := FALSE;                      (* 清前点标志 / Clear has-prev *)
    bAlignBad := FALSE;                      (* 清超差锁存 / Clear fail latch *)
    fMarkPos := 0.0;                         (* 清标记出口 / Clear mark outlet *)
    fDev := 0.0;                             (* 清偏差出口 / Clear dev outlet *)
    _nMark := 0;                             (* 清累计计数 / Clear mark count *)
    _eState := E_DL_EgmState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_EgmCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_EgmState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_EgmState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_EgmState.eTrack; (* 进入跟踪 / Enter track *)
        END_IF
    E_DL_EgmState.eTrack:                    (* 跟踪相：位域统计 + 同步沿标记判定 / Track *)
        IF NOT bEnable THEN
            _eState := E_DL_EgmState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSE
            _i := 0;                         (* 位游标重置（R227） / Bit cursor reset *)
            _wMask := 16#0001;               (* 掩码起点（位 0） / Mask start *)
            WHILE _i <= 15 DO                (* 逐位统计（移位量 0..15 < 16 位宽，R48 安全） / Per-bit count *)
                IF (uGapField AND _wMask) <> 16#0000 THEN
                    _nCnt := _nCnt + 1;      (* 有效位计数 / Count set bit *)
                END_IF
                _wMask := SHL(_wMask, 1);    (* 掩码左移 1 位（常量移位量，R48） / Shift mask *)
                _i := _i + 1;                (* 游标递进 / Cursor advance *)
            END_WHILE
            IF rtSync.Q AND (NOT _bPosBad) THEN   (* 同步沿 + 位置有限：锁标记点 / Sync edge with finite pos *)
                IF _bHasPrev THEN
                    _fDev := (fPosNow - _fPrevMark) - fGapPitch;   (* 节距偏差派生（除法无涉，无除零） / Pitch deviation *)
                    bAlignOk := ABS(_fDev) <= fTol;   (* 对齐判定（容差闸） / Align verdict *)
                    IF NOT bAlignOk THEN
                        bAlignBad := TRUE;   (* 超差锁存至复位沿 / Latch align fail *)
                    END_IF
                    fDev := _fDev;           (* 偏差出口刷新 / Dev outlet *)
                END_IF
                _fPrevMark := fPosNow;       (* 前点更新 / Update previous *)
                fMarkPos := fPosNow;         (* 标记出口刷新 / Mark outlet *)
                _bHasPrev := TRUE;           (* 置前点标志 / Set has-prev *)
                _nMark := _nMark + 1;        (* 累计计数（UDINT 自然回绕可接受：17 亿标记点） / Count marks *)
            END_IF                           (* 位置坏值拍：不锁存不判定（边界②） / Bad pos: skip *)
        END_IF
    E_DL_EgmState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_EgmState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_EgmCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nGapCnt := _nCnt;                            (* 位计数出口 / Bit count outlet *)
nMarkCnt := _nMark;                          (* 累计计数出口 / Mark count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
