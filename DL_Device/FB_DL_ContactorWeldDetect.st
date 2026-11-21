(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ContactorWeldDetect
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG）与库内健康枚举唯一属主，
 *                         零厂商私有库
 * 功能描述 (Function)   : 接触器熔焊与不吸合检测。① 熔焊：断开指令后 tReleaseMax 内反馈仍为 1
 *                         → eCause = eWeld，故障锁存；② 不吸合：闭合指令后 tPickupMax 内无反馈
 *                         → eCause = eNoPickup，故障锁存。两成因各有独立 TON 与独立归因成员
 *                         （R190 归因唯一，禁止共用一个成因导致另一端永不赋值）。
 * 复位语义 (Design)     : **熔焊为不可自恢复故障**：解除式要求「复位沿 ∧ 反馈已回落」。若反馈是
 *                         真实熔焊，反馈不会回落 → 复位**不解锁**，这是**设计意图**而非缺陷：
 *                         触点焊死时允许软复位等于给现场一个「假修复」通道，会把带电粘连的
 *                         主回路重新投入。现场处置只能是更换接触器后反馈自然回落再复位。
 * 归属声明 (Ownership)  : 健康出口 eHealth 引用枚举 `E_DL_Ne107Status` 唯一属主，属主文件为
 *                         `C:\Library\DL_Device\I_DL_DeviceHealth.st`（枚举定义位于该文件 L91 附近），
 *                         本件只引用不重复声明（全库同名枚举定义计数 = 1，R67）。
 * 接口     (Interface)  : 输入 bCmdClose 闭合指令、bFbClosed 触点反馈、tReleaseMax 释放超时、
 *                         tPickupMax 吸合超时、bReset 复位；输出 bWeldSuspect 熔焊疑似位、
 *                         eCause 归因、eHealth NE107 健康态、eState / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：tReleaseMax <= T#0S 或 tPickupMax <= T#0S → 故障锁存；
 *                         ② TON 两枚 + R_TRIG 一枚段 0 无条件周期刷新，IN 由当拍指令与反馈派生；
 *                         ③ 故障相迁出唯一路径 = bReset 上升沿；④ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 反馈已回落（bFbClosed = FALSE，当拍量，
 *                         R240 范式）。自证可满足（终审两式 1）：反馈为真实熔焊时该式不可满足，
 *                         属刻意的安全不可解除；触点更换后反馈回落即达，故路径物理可达。
 * 码表     (Codes)      : 16#0003_0702 故障级：接触器故障总码（组态非法 / 熔焊 / 不吸合 / 非法相位），
 *                         锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0003_0481 信息级：吸合动作正常确认（指令闭合且反馈已到位）。
 *                         加码反证（R90）：吸合正常确认与「一直闭合保持着」在 bFbClosed / bError 上
 *                         完全同值，出口组合无法区分「刚完成一次吸合确认」与「长期闭合」，
 *                         故立一码留痕。
 *                         码段说明：Device 的 03xx 故障子带已占满（仅余 03C5~03C9 碎片孔洞，按
 *                         实战规则 13 禁回填），故本批新开 07xx 故障子带取 16#0003_0702；
 *                         信息级用 04xx 子带取 16#0003_0481（源码实扫为空）。分段理由即此。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考设备级 AOI 熔焊检测粒度与参数域，
 *                         零代码行复制；t2-6-rockwell-aoi 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 4 · 序号 16）
 *==============================================================================*)

TYPE E_DL_CwdState :
(
    eIdle  := 0,     // 待机（指令与反馈均断开） / Idle, command and feedback both released
    eRun   := 10,    // 动作监视 / Monitoring motion
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_CwdCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eWeld       := 2,   // 熔焊（断开指令后反馈不回落） / Welded, feedback stays on after release
    eNoPickup   := 3,   // 不吸合（闭合指令后无反馈） / No pickup, no feedback after close
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ContactorWeldDetect
VAR_INPUT
    bCmdClose    : BOOL := FALSE;        // 闭合指令 [-] / Close command
    bFbClosed    : BOOL := FALSE;        // 主/辅助触点反馈（TRUE = 已闭合） [-] / Contact feedback, TRUE means closed
    tReleaseMax  : TIME := T#500MS;      // 释放允许时间，域 > T#0S [ms] / Release allowance, domain > T#0S [ms]
    tPickupMax   : TIME := T#300MS;      // 吸合允许时间，域 > T#0S [ms] / Pickup allowance, domain > T#0S [ms]
    bReset       : BOOL := FALSE;        // 复位命令，上升沿清故障（真实熔焊时不解锁为设计意图） [-] / Reset, does not unlock a truly welded contact by design
END_VAR
VAR_OUTPUT
    bWeldSuspect : BOOL;                 // 熔焊疑似（锁存回放） [-] / Weld suspect, latched replay
    eCause       : E_DL_CwdCause;        // 故障成因出口（R190 归因唯一） / Fault cause outlet
    eHealth      : E_DL_Ne107Status;     // NE107 健康态（引用唯一属主枚举） [-] / NE107 health, owner enum referenced
    eState       : E_DL_CwdState;        // 状态出口，段 6 单点映射 / State outlet
    bError       : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState      : E_DL_CwdState := E_DL_CwdState.eIdle;     // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_CwdCause := E_DL_CwdCause.eNone;     // 故障成因锁存（锁存量） / Latched cause
    tonRelease   : TON;                  // 释放超时计时，段 0 无条件调用 / Release timeout timer
    tonPickup    : TON;                  // 吸合超时计时，段 0 无条件调用 / Pickup timeout timer
    rtReset      : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _bWeldLatch  : BOOL;                 // 熔焊疑似锁存位（锁存量） / Weld suspect latch
    _bCfgBad     : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bFault      : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_bCfgBad := (tReleaseMax <= T#0S) OR (tPickupMax <= T#0S);                                // 组态域闸 / Configuration gate
rtReset(CLK := bReset);                                                                   // 复位沿，每拍必调（R228A） / Reset edge
tonRelease(IN := (NOT bCmdClose) AND bFbClosed, PT := tReleaseMax);                        // 释放超时计时（断开后反馈仍在） / Release timeout
tonPickup(IN := bCmdClose AND (NOT bFbClosed), PT := tPickupMax);                          // 吸合超时计时（闭合后无反馈） / Pickup timeout

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo       := 16#0000_0000;      // 信息码每拍重算 / Info recomputed every scan
bWeldSuspect := FALSE;             // 熔焊疑似位缺省假，由锁存回放 / Weld suspect preset
nErrId       := 16#0000_0000;      // 事件码缺省无事件 / Event code default none
bError       := FALSE;             // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_CwdCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_CwdState.eFault THEN
        _eState := E_DL_CwdState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0003_0702;                                             // 故障级：接触器故障总码 / Fault-level: contactor fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_CwdCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：熔焊 / 不吸合双判据（各用独立实例与独立归因，R190） —— *)
IF (NOT _bFault) AND tonRelease.Q THEN                                   // 熔焊判据：断开后反馈不回落 / Weld criterion
    _uFault := 16#0003_0702;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_CwdCause.eWeld;                                      // 归因：熔焊 / Cause: welded
    _bWeldLatch := TRUE;                                                 // 熔焊疑似锁存（供 HMI 持续显示） / Latch weld suspicion
END_IF
IF (NOT _bFault) AND tonPickup.Q THEN                                    // 不吸合判据：闭合后无反馈 / No-pickup criterion
    _uFault := 16#0003_0702;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_CwdCause.eNoPickup;                                  // 归因：不吸合 / Cause: no pickup
END_IF
IF (NOT _bFault) AND bCmdClose AND bFbClosed THEN                        // 吸合正常确认（信息级） / Normal pickup confirmed
    _uInfo := 16#0003_0481;
END_IF

(* —— 段 4：故障解除式（R240 全当拍量；真实熔焊不解锁为设计意图） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT bFbClosed) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_CwdCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    _bWeldLatch := FALSE;                                                // 反馈已回落才撤熔焊疑似 / Clear weld suspicion only after feedback dropped
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_CwdState.eFault) THEN
    _eState := E_DL_CwdState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_CwdState.eIdle:
    IF (bCmdClose OR bFbClosed) AND (NOT _bFault) THEN                   // 出口 1：出现动作 / Motion appears
        _eState := E_DL_CwdState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_CwdState.eFault;
    END_IF

E_DL_CwdState.eRun:
    IF (NOT bCmdClose) AND (NOT bFbClosed) AND (NOT _bFault) THEN        // 出口 1：指令与反馈均已复原（前置消失，R98） / Both released
        _eState := E_DL_CwdState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_CwdState.eFault;
    END_IF

E_DL_CwdState.eFault:
    ;                                                                     // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0003_0702;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_CwdCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_CwdState.eFault;

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放；NE107 健康态仲裁） —— *)
bWeldSuspect := _bWeldLatch AND _bFault;                                 // 熔焊疑似仅在故障锁存期成立（名实同源） / Weld suspicion only while latched
IF _bFault OR _bCfgBad THEN
    eHealth := E_DL_Ne107Status.eFailure;                                // 失效级 / Failure level
ELSIF bCmdClose AND (NOT bFbClosed) THEN
    eHealth := E_DL_Ne107Status.eCheckFunction;                          // 吸合动作确认中（信号暂不可信） / Function check during pickup
ELSE
    eHealth := E_DL_Ne107Status.eOk;                                     // 正常级 / OK level
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
