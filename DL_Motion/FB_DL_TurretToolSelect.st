(*
  ==================================================================
  组件名 Component  : FB_DL_TurretToolSelect
  分类   Category   : DL_Motion
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 高
  版本   Version    : 1.0.1
  功能   Purpose    : 刀塔就近方向换刀选择（刀位环计数 + 最短路径 + 当前刀位校验状态机）。
  来源   Source     : t1-6-plcopen（PLCopen 刀塔换刀公开语义）
  平台   Platform   : 纯 IEC 61131-3（R_TRIG / CASE / MOD），三平台通用
  分工声明 Split     : 与 FB_DL_TurretIndexSeq（顺序换刀属主，若在册）分工——本件
                      只做就近方向解算与校验，不做顺序全环巡检（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : E_DL_TurretPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 刀位号域闸 [1, n] 钳位：越域钳位后仍以钳位值解算（信息级
                         08A6），不拒单（换刀请求尽量满足）；
                      二 就近方向判据整数进位点自证：环差 diff = (req − cur) MOD n，
                         恰对径（diff·2 = n）两向量等长时写死取正向（CW），判据
                         全整数精确比较，无浮点；
                      三 换刀指令单拍脉冲 bToolChange（R256 统一出口预置）；
                      四 状态机 CASE 必带 ELSE 兜底；R_TRIG 段 0 无条件刷新（R7）；
                      五 故障锁存解除式自证：刀位数组态非法（<1 或 >24）锁存
                         08A7，bReset 上升沿解除（恒可达，R152 自证）；
                      七 故障相迁入完备（v1.0.1 修 D3）：段 4 之后设统一迁入闸
                         （_bFault 且当前相 ≠ eFault 即迁 eFault），eMoving 的故障
                         出口亦直接迁 eFault，eFault 成为可达相而非死相位；
                      八 不删 eFault 相的理由（诊断保真）：eFault 是 R274 要求的
                         状态机完整性成员，且与 FB_DL_SingleAxis 族故障相命名一致；
                         删相会让「组态非法」与「空闲」在 eState 出口上不可分，
                         现场读 eState=eIdle 且 bError=TRUE 时无法区分「未换刀」
                         与「组态故障」，损失诊断保真；
                      六 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0004_08A6【信息级】刀位号或刀位数越域已钳位（[1, 24]）
    16#0004_08A7【故障级】刀位数组态非法（<1 或 >24），锁存至复位沿
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 n=8、cur=1、req=3 → 正向 2 步；V2 cur=1、req=7 → 反向 2 步
    V3 n=8、cur=1、req=5（对径）→ 正向 4 步（进位点写死取正）
    V4 req=0 → 钳到 1、码 08A6；n=0 → 码 08A7 锁存
    V5 组态非法（uToolCnt=0）→ eState=eFault 且 bError=TRUE 同拍（v1.0.1 回归向量）
    V6 故障态下 bReset 上升沿且组态已合法 → 清锁存、迁 eIdle
    V7 正常换刀全程 → eState 轨迹 eIdle→eMoving→eIdle，eFault 不出现
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 4 · 序号 15）
    2026-11-21  v1.0.1  R62-D3 返修：①段 4 后加故障统一迁入闸（R274 迁入完备性），补 eFault 死相位；②eMoving 的 ELSIF _bFault 出口由 eIdle 改为 eFault；③eFault 出口「NOT _bFault 才迁出」保持不变；④不删相理由（诊断保真）写入头注释。注：盘面实测入库版本为 v1.0.0（计划书假设 R61 已发 v1.0.1），按实测优先、禁跳号递增一次至 v1.0.1
  ==================================================================
*)
TYPE E_DL_TurretPhase :
(
    eIdle   := 0,  // 空闲：等换刀指令沿 / idle, waiting for the change edge
    eMoving := 10, // 换刀进行：等到位反馈 / moving, waiting for the in position feedback
    eFault  := 20  // 故障：组态非法，锁存待复位 / fault, the illegal configuration latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_TurretToolSelect
VAR_INPUT
    bExec     : BOOL := FALSE;  // 换刀指令电平，上升沿解算并发单拍 / the change command level
    bInPos    : BOOL := FALSE;  // 刀塔到位反馈电平 [-] / the turret in position feedback
    bReset    : BOOL := FALSE;  // 故障复位电平，上升沿清锁存 / the fault reset level
    uCurTool  : UDINT := 1;     // 当前刀位号 [刀位]，域 [1, 24] / the current tool number
    uReqTool  : UDINT := 1;     // 请求刀位号 [刀位]，域 [1, 24] / the requested tool number
    uToolCnt  : UDINT := 8;     // 刀位总数 [刀位]，合法域 1..24 / the tool count, legal from one to twenty four
END_VAR
VAR_OUTPUT
    bDirCW      : BOOL := FALSE;          // 方向指示：TRUE 正向（CW）[-] / the direction indicator, true for the forward
    uSteps      : UDINT := 0;             // 换刀步数 [步] / the change step count
    bToolChange : BOOL := FALSE;          // 换刀指令单拍脉冲 [-] / the change command one shot pulse
    bDone       : BOOL := FALSE;          // 换刀完成单拍脉冲 [-] / the change done one shot pulse
    eState      : E_DL_TurretPhase;       // 主状态机当前态 [状态] / the current state
    bError      : BOOL := FALSE;          // 故障锁存位（与锁存同源，R191）/ the fault bit from the latch
    bValid      : BOOL := FALSE;          // 解算可用标志 [-] / the solve usable flag
    eErr        : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit    : BOOL := FALSE;                        // 首拍初始化标志（R310）/ the first scan flag
    _eState   : E_DL_TurretPhase := E_DL_TurretPhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFault   : BOOL := FALSE;                        // 组态故障锁存副本（仅复位沿清除）/ the fault latch copy
    _nCur     : DINT := 1;                            // 钳位后当前刀位 [刀位] / the clamped current tool
    _nReq     : DINT := 1;                            // 钳位后请求刀位 [刀位] / the clamped requested tool
    _nCnt     : DINT := 8;                            // 钳位后刀位数 [刀位] / the clamped tool count
    _nDiff    : DINT := 0;                            // 环差 [步] / the ring difference
    _nSteps   : DINT := 0;                            // 步数工作副本 [步] / the step count copy
    _bCW      : BOOL := FALSE;                        // 方向工作副本 / the direction copy
    _bChange  : BOOL := FALSE;                        // 换刀单拍内部位，段 1 预清段 5 映射 / the internal change bit
    _bDone    : BOOL := FALSE;                        // 完成单拍内部位 / the internal done bit
    _bClamp   : BOOL := FALSE;                        // 钳位标记（逐拍重算）/ the clamp flag recomputed
    rtExec    : R_TRIG; // 换刀指令沿实例，段 0 无条件刷新 / the command edge instance
    rtReset   : R_TRIG; // 复位沿实例，段 0 无条件刷新 / the reset edge instance
END_VAR
VAR CONSTANT
    DL_TTS_NMAX : DINT := 24; // 刀位容量上界 [刀位] / the tool capacity bound
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtExec(CLK := bExec); // 换刀指令沿 / the command edge
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首拍初始化与单拍标志预清（R310 / FB32-1 / R256）/ segment 1, the first scan init and the preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_TurretPhase.eIdle; // 状态显式落空闲 / place the state to idle
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清锁存 + 迁相位，R311 声明）/ the reset edge with the declared scope
    _bFault := FALSE; // 清锁存（解除路径：复位沿恒可达，R152 自证）/ clear the latch
    _eState := E_DL_TurretPhase.eIdle; // 迁回空闲 / back to idle
END_IF
_bChange := FALSE; // 换刀单拍预清零 / preset the change bit false
_bDone := FALSE; // 完成单拍预清零 / preset the done bit false
_bClamp := FALSE; // 钳位标记预清零 / preset the clamp flag false

// 段 2｜域闸与钳位（整数全精确，边界一二五）/ segment 2, the domain gate with the clamps
_nCnt := UDINT_TO_DINT(uToolCnt); // 刀位数升位接管 / take the tool count widened
IF (_nCnt < 1) OR (_nCnt > DL_TTS_NMAX) THEN // 刀位数组态非法（0807 → 08A7 独立码）/ the illegal tool count
    _bFault := TRUE; // 锁存故障（08A7）/ latch the fault
END_IF
IF _nCnt < 1 THEN // 下界钳位（防环运算除零取模）/ the floor clamp guarding the modulo
    _nCnt := 1; // 钳到一 / clamp to one
END_IF
IF _nCnt > DL_TTS_NMAX THEN // 上界钳位 / the ceiling clamp
    _nCnt := DL_TTS_NMAX; // 钳到容量 / clamp to the capacity
END_IF
_nCur := UDINT_TO_DINT(uCurTool); // 当前刀位接管 / take the current tool
_nReq := UDINT_TO_DINT(uReqTool); // 请求刀位接管 / take the requested tool
IF (_nCur < 1) OR (_nCur > _nCnt) OR (_nReq < 1) OR (_nReq > _nCnt) THEN // 刀位号越域（信息级钳位，边界一）/ the tool numbers out of the domain
    _bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF _nCur < 1 THEN // 当前刀位下界钳位 / the current floor clamp
    _nCur := 1; // 钳到一 / clamp to one
END_IF
IF _nCur > _nCnt THEN // 当前刀位上界钳位 / the current ceiling clamp
    _nCur := _nCnt; // 钳到总数 / clamp to the count
END_IF
IF _nReq < 1 THEN // 请求刀位下界钳位 / the requested floor clamp
    _nReq := 1; // 钳到一 / clamp to one
END_IF
IF _nReq > _nCnt THEN // 请求刀位上界钳位 / the requested ceiling clamp
    _nReq := _nCnt; // 钳到总数 / clamp to the count
END_IF

// 段 3｜就近方向解算（全整数精确比较，进位点写死取正向，边界二）/ segment 3, the nearest direction solve in exact integers
_nDiff := ((_nReq - _nCur) MOD _nCnt + _nCnt) MOD _nCnt; // 环差归一到 [0, n-1]（双 MOD 防负数取模方言差异）/ the ring difference normalized
IF _nDiff = 0 THEN // 同刀位：零步 / the same tool, zero steps
    _nSteps := 0; // 零步 / zero steps
    _bCW := TRUE; // 零步时方向寄存器按正向表态（无方向语义）/ the direction placeholder forward
ELSIF (_nDiff * 2) = _nCnt THEN // 恰对径（进位点）：两向等长，写死取正向（边界二）/ the diametric point takes the forward by the declared rule
    _nSteps := _nDiff; // 正向步数 / the forward steps
    _bCW := TRUE; // 正向 / forward
ELSIF (_nDiff * 2) < _nCnt THEN // 正向更近 / the forward is nearer
    _nSteps := _nDiff; // 正向步数 / the forward steps
    _bCW := TRUE; // 正向 / forward
ELSE // 反向更近 / the reverse is nearer
    _nSteps := _nCnt - _nDiff; // 反向步数 / the reverse steps
    _bCW := FALSE; // 反向 / reverse
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 兜底；指令沿消费带全量闸位复检，R274）/ segment 4, the main machine
CASE _eState OF
    E_DL_TurretPhase.eIdle: // 空闲相 / the idle phase
        IF rtExec.Q AND (NOT _bFault) THEN // 指令沿 + 闸位复检（R274）/ the command edge with the gate recheck
            IF _nSteps = 0 THEN // 同刀位校验：直接完成（整数精确比较，边界二）/ the same tool verified by the exact integer compare
                _bDone := TRUE; // 置完成单拍 / raise the done bit
            ELSE // 异刀位：发换刀单拍并迁入移动相 / a different tool, raise the change pulse and enter moving
                _bChange := TRUE; // 置换刀单拍 / raise the change bit
                _eState := E_DL_TurretPhase.eMoving; // 迁入移动相 / enter the moving phase
            END_IF
        END_IF
    E_DL_TurretPhase.eMoving: // 移动相：等到位反馈 / the moving phase
        IF bInPos THEN // 到位反馈（同刀位目标校验后完成）/ the in position feedback
            _bDone := TRUE; // 置完成单拍 / raise the done bit
            _eState := E_DL_TurretPhase.eIdle; // 迁回空闲 / back to idle
        ELSIF _bFault THEN // 前置条件消失出口（直接迁故障相，不经 eIdle，v1.0.1 修 D3）/ the prerequisite gone exit straight to the fault phase
            _eState := E_DL_TurretPhase.eFault; // 迁入故障相（与统一迁入闸同向，避免同拍先迁 idle 再被拉回）/ enter the fault phase, aligned with the unified gate
        END_IF
    E_DL_TurretPhase.eFault: // 故障相：等复位沿（解除可达，边界五）/ the fault phase until the reset
        IF NOT _bFault THEN // 锁存已清才迁出 / the exit after the latch cleared
            _eState := E_DL_TurretPhase.eIdle; // 迁回空闲 / back to idle
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_TurretPhase.eIdle; // 落回空闲 / force back to idle
        _bFault := TRUE; // 置锁存 / latch the fault
END_CASE

// 段 4b｜故障统一迁入闸（置于状态机之后、解除段之外，R274 迁入完备性；v1.0.1 修 D3）/ segment 4b, the unified fault entry gate
IF _bFault AND (_eState <> E_DL_TurretPhase.eFault) THEN // 已锁存但当前不在故障相（含 eIdle 检出与非法枚举值兜底）/ latched but not yet in the fault phase
    _eState := E_DL_TurretPhase.eFault; // 任何相检出故障一律落故障相，eFault 由此可达 / any phase with a latch lands in the fault phase, which makes it reachable
END_IF

// 段 5｜统一出口（内部副本单点映射；故障码锁存回放，R187）/ segment 5, the unified outlet
bDirCW := _bCW; // 方向出口 / the direction outlet
uSteps := DINT_TO_UDINT(_nSteps); // 步数出口（值已证非负）/ the step outlet proven non negative
bToolChange := _bChange; // 换刀单拍出口 / the change pulse outlet
bDone := _bDone; // 完成单拍出口 / the done pulse outlet
eState := _eState; // 状态出口 / the state outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet
bValid := NOT _bFault; // 解算可用标志 / the solve usable flag
IF _bFault THEN // 故障锁存回放（R187）/ the latched fault replays
    eErr := 16#0004_08A7; // 故障级：刀位数组态非法 / fault grade, the illegal tool count
ELSIF _bClamp THEN // 钳位（信息级不置 bError，R285）/ the clamp informational
    eErr := 16#0004_08A6; // 信息级：刀位号越域已钳位 / informational, the tool numbers clamped
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
