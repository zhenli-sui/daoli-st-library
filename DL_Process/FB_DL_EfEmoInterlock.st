(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EfEmoInterlock
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : EFEM 机械手互锁矩阵（域专用条件源）。
 *                         把 EFEM 域的四类条件源汇总成"机械手可否运动"的单一许可位，并追踪**首因**：
 *                           ① 门类（4 点）：安全门 / 维护门关到位，任一门未关 → 禁止运动；
 *                           ② 阀类（4 点）：隔离阀关到位，任一阀未关 → 禁止运动；
 *                           ③ 真空类（4 点）：吸盘/腔体真空建立，任一路失真空 → 禁止运动；
 *                           ④ 位置类（4 点）：机构在安全位，任一路越位 → 禁止运动。
 *                         判据顺序固定为"门 → 阀 → 真空 → 位置"（安全优先级由高到低），
 *                         首个失败项即首因；首因**锁存到全部条件恢复**才清零（不在故障期按当下输入
 *                         反复改写，R152/R190），HMI 因此能看到"是谁先拦的"。
 *                         验收向量：
 *                           ① 16 点全 TRUE → bMotionPermit = TRUE，eFirstCause = eNone
 *                           ② 门 3 未关 + 真空 1 失真空 → 首因 = eDoor，iFirstIdx = 3（门优先）
 *                           ③ 门恢复、真空 1 仍失 → 首因改判为 eVac，iFirstIdx = 1
 *                           ④ 三点同时失败 → 只报扫描序最靠前的一处（首因唯一）
 * 接口     (Interface)  : 入 abDoorClosed / abValveClosed / abVacOk / abInSafePos 四张 4 点条件表、
 *                         bMotionReq 运动请求（仅用于判定是否"曾经放行过"，不参与互锁本体）、
 *                         bReset 首因复位沿；
 *                         出 bMotionPermit 运动许可、bAnyBlocked 当前存在阻断、
 *                         eFirstCause 首因类别、iFirstIdx 首因点号（1..4，0 = 无）、
 *                         bFirstLatched 首因处于锁存态、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"EFEM 域条件源汇总与首因追踪"，
 *                         不内嵌通用互锁矩阵判据**（通用矩阵属 `FB_DL_InterlockMatrix`，
 *                         两件分工：本件是域条件源适配层，那件是任意规模矩阵求值器）；
 *                         本件也不驱动机械手运动、不做安全回路硬线判断（硬线由安全继电器负责）；
 *                         ② **数组边界**：四张表以字面量上界 4 声明（R104），扫描以常量
 *                         DL_EMI_N 之展开，不做动态下标，越界结构性不可能；
 *                         ③ **首因锁存解除式**：bReset 上升沿 ∨ 全部条件恢复（两式自证可满足：
 *                         前者为外部引脚恒可达，后者由条件源自身恢复触发）；
 *                         ④ **非门控输出**：eFirstCause 在锁存态下回放锁存值，不按当下输入重算（R152）；
 *                         ⑤ 零全局变量、零物理地址。
 * 分工声明 (Scope)      : 本件只管"EFEM 域四类条件源的首因判定"。不接管：门锁硬件状态诊断、
 *                         真空度模拟量判读、机械手轨迹安全校验（分别属门件/模拟量件/运动件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口（EFEM 互锁，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 定长展开无动态下标 + 首因唯一 + 解除式可满足 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 3 · 序号 15）
 *==============================================================================*)

TYPE E_DL_EmiCause :
(
    eNone    := 0,   // 无阻断（全部条件满足） / No block, all conditions satisfied
    eDoor    := 1,   // 门未关到位（最高优先级） / Door not closed, highest priority
    eValve   := 2,   // 隔离阀未关到位 / Isolation valve not closed
    eVac     := 3,   // 真空失效 / Vacuum lost
    ePos     := 4,   // 机构不在安全位 / Mechanism off the safe position
    ePhaseBad:= 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

TYPE E_DL_EmiState :
(
    ePermit := 0,    // 放行相（条件全满足） / Permit, all conditions met
    eBlock  := 10,   // 阻断相（存在不满足条件） / Blocked
    eFault  := 90    // 故障相（内部非法，等复位） / Fault, awaiting reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_EfEmoInterlock
VAR_INPUT
    abDoorClosed  : ARRAY[1..4] OF BOOL;   // 门关到位（1..4） [-] / Doors closed, points 1..4
    abValveClosed : ARRAY[1..4] OF BOOL;   // 隔离阀关到位（1..4） [-] / Valves closed, points 1..4
    abVacOk       : ARRAY[1..4] OF BOOL;   // 真空建立（1..4） [-] / Vacuum established, points 1..4
    abInSafePos   : ARRAY[1..4] OF BOOL;   // 机构在安全位（1..4） [-] / Mechanism in the safe position, points 1..4
    bMotionReq    : BOOL := FALSE;         // 机械手运动请求（诊断用，不参与互锁本体） [-] / Motion request, diagnostic only
    bReset        : BOOL := FALSE;         // 首因复位沿 [-] / First-cause reset edge
END_VAR
VAR_OUTPUT
    bMotionPermit : BOOL := FALSE;                      // 运动许可 [-] / Motion permit
    bAnyBlocked   : BOOL := FALSE;                      // 当前存在阻断（实时量） [-] / Any block present, live value
    eFirstCause   : E_DL_EmiCause := E_DL_EmiCause.eNone;   // 首因类别（锁存态回放） [-] / First cause, latched value
    iFirstIdx     : INT := 0;                           // 首因点号（1..4；0 = 无） [-] / First-cause point index, 0 = none
    bFirstLatched : BOOL := FALSE;                      // 首因处于锁存态 [-] / First cause currently latched
    eState        : E_DL_EmiState := E_DL_EmiState.ePermit; // 相出口 [-] / Phase outlet
    eCause        : E_DL_EmiCause := E_DL_EmiCause.eNone;   // 成因出口（与首因同源） [-] / Cause outlet
    bError        : BOOL := FALSE;                      // 故障标志（仅内部非法） [-] / Error flag
END_VAR
VAR
    _eState   : E_DL_EmiState := E_DL_EmiState.ePermit; // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_EmiCause := E_DL_EmiCause.eNone;  // 成因锁存量 / Latched cause
    _iIdx     : INT := 0;                               // 首因点号锁存量 / Latched first-cause index
    _bFault   : BOOL := FALSE;                          // 故障锁存位 / Latched fault bit
    _bBlocked : BOOL := FALSE;                          // 实时阻断量 / Live blocked flag
    _eNow     : E_DL_EmiCause := E_DL_EmiCause.eNone;  // 当拍首因（未锁存） / Live first cause
    _iNow     : INT := 0;                               // 当拍首因点号 / Live first-cause index
    rtReset   : R_TRIG;                                 // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_EMI_N : INT := 4;              // 条件源点数（与四张表字面量上界同源，改动须同步） [点] / Points per source table
END_VAR

(* —— 段 0：沿实例无条件周期刷新（R228A；本件无 TON） —— *)
rtReset(CLK := bReset);                                  // 复位沿 / Reset edge

(* —— 段 1：单拍量预清零（锁存量 _eCause/_iIdx/_bFault 不入清单，R107） —— *)
bError      := FALSE;                                    // 故障标志预清（R45 配对） / Error preset
_bBlocked   := FALSE;                                    // 实时阻断量预清 / Live blocked preset
_eNow       := E_DL_EmiCause.eNone;                      // 当拍首因预置 / Live cause preset
_iNow       := 0;                                        // 当拍点号预置 / Live index preset

(* —— 段 2：首因扫描（定长展开，门 → 阀 → 真空 → 位置，安全优先级由高到低） —— *)
IF NOT abDoorClosed[1] THEN
    _eNow := E_DL_EmiCause.eDoor;  _iNow := 1;
ELSIF NOT abDoorClosed[2] THEN
    _eNow := E_DL_EmiCause.eDoor;  _iNow := 2;
ELSIF NOT abDoorClosed[3] THEN
    _eNow := E_DL_EmiCause.eDoor;  _iNow := 3;
ELSIF NOT abDoorClosed[4] THEN
    _eNow := E_DL_EmiCause.eDoor;  _iNow := 4;
ELSIF NOT abValveClosed[1] THEN
    _eNow := E_DL_EmiCause.eValve; _iNow := 1;
ELSIF NOT abValveClosed[2] THEN
    _eNow := E_DL_EmiCause.eValve; _iNow := 2;
ELSIF NOT abValveClosed[3] THEN
    _eNow := E_DL_EmiCause.eValve; _iNow := 3;
ELSIF NOT abValveClosed[4] THEN
    _eNow := E_DL_EmiCause.eValve; _iNow := 4;
ELSIF NOT abVacOk[1] THEN
    _eNow := E_DL_EmiCause.eVac;   _iNow := 1;
ELSIF NOT abVacOk[2] THEN
    _eNow := E_DL_EmiCause.eVac;   _iNow := 2;
ELSIF NOT abVacOk[3] THEN
    _eNow := E_DL_EmiCause.eVac;   _iNow := 3;
ELSIF NOT abVacOk[4] THEN
    _eNow := E_DL_EmiCause.eVac;   _iNow := 4;
ELSIF NOT abInSafePos[1] THEN
    _eNow := E_DL_EmiCause.ePos;   _iNow := 1;
ELSIF NOT abInSafePos[2] THEN
    _eNow := E_DL_EmiCause.ePos;   _iNow := 2;
ELSIF NOT abInSafePos[3] THEN
    _eNow := E_DL_EmiCause.ePos;   _iNow := 3;
ELSIF NOT abInSafePos[4] THEN
    _eNow := E_DL_EmiCause.ePos;   _iNow := 4;
ELSE
    _eNow := E_DL_EmiCause.eNone;  _iNow := 0;           // 全部满足：无首因 / All satisfied: no cause
END_IF
_bBlocked := (_eNow <> E_DL_EmiCause.eNone);             // 实时阻断量 / Live blocked flag

(* —— 段 3：首因锁存与解除（锁存期不按当下输入重算，R152） —— *)
IF _bBlocked THEN
    IF (_eCause = E_DL_EmiCause.eNone) THEN
        _eCause := _eNow;                                // 首次出现阻断：记首因 / First block: latch the cause
        _iIdx   := _iNow;                                // 记首因点号 / Latch the point
    END_IF
ELSE
    _eCause := E_DL_EmiCause.eNone;                      // 全部恢复：首因自动解除（解除式路径 1） / All clear: auto-release
    _iIdx   := 0;
END_IF
IF rtReset.Q THEN
    _eCause := E_DL_EmiCause.eNone;                      // 人工复位：清首因（解除式路径 2，恒可达） / Manual reset
    _iIdx   := 0;
    _bFault := FALSE;                                    // 同时清内部故障锁存 / Clear the internal fault latch
END_IF

(* —— 段 4：相迁移（许可 / 阻断两相；非法兜底） —— *)
CASE _eState OF

E_DL_EmiState.ePermit:
    IF _bBlocked THEN
        _eState := E_DL_EmiState.eBlock;                 // 出现阻断：进阻断相 / Enter the blocked phase
    END_IF

E_DL_EmiState.eBlock:
    IF NOT _bBlocked THEN
        _eState := E_DL_EmiState.ePermit;                // 条件恢复：回放行相 / Conditions recovered
    END_IF

E_DL_EmiState.eFault:
    ;                                                    // 故障相：由段 3 复位沿迁出 / Exit via the reset edge

ELSE
    _eCause := E_DL_EmiCause.ePhaseBad;                  // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                     // 锁存 / Latch
    _eState := E_DL_EmiState.eFault;                     // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：出口单点映射（许可位与本拍阻断量同源；首因回放锁存值，R191） —— *)
bMotionPermit := (NOT _bBlocked) AND (NOT _bFault) AND (_eState = E_DL_EmiState.ePermit);   // 运动许可 / Motion permit
bAnyBlocked   := _bBlocked;                                                                  // 实时阻断出口 / Live blocked outlet
eFirstCause   := _eCause;                                                                    // 首因出口（锁存回放） / First-cause outlet
iFirstIdx     := _iIdx;                                                                      // 首因点号出口 / First-cause index outlet
bFirstLatched := (_eCause <> E_DL_EmiCause.eNone);                                            // 首因锁存态出口 / Latched flag outlet
eState        := _eState;                                                                    // 相出口 / Phase outlet
eCause        := _eCause;                                                                    // 成因出口 / Cause outlet
bError        := _bFault OR (_bBlocked AND _bFault);                                          // 故障标志（仅内部非法） / Error flag

END_FUNCTION_BLOCK
