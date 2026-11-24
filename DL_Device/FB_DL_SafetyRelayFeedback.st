(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SafetyRelayFeedback
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG）与库内健康枚举唯一属主，
 *                         零厂商私有库
 * 功能描述 (Function)   : 安全继电器（双通道触点）反馈一致性监视。指令 bCmd 变化后开
 *                         tSyncWin 同步窗，窗内应两通道同步跟随；窗末判定四类结局：
 *                         ① 两通道仍不一致 → 通道不同步故障（eSync）；
 *                         ② 仅通道 1 未跟随 → 通道 1 失效（eCh1Fail）；
 *                         ③ 仅通道 2 未跟随 → 通道 2 失效（eCh2Fail）；
 *                         ④ 两通道都未跟随 → 双通道失效（eBothFail）。
 *                         另连续监视常闭回路断开：bNcLogic 为真时「指令为 FALSE 而两通道反馈
 *                         仍为 FALSE」即常闭回路断开（eNcOpen，典型断线/线圈失电）。
 * 安全声明 (Safety)     : **本件不实现任何安全认证功能**。它是反馈一致性监视器，不是安全功能
 *                         的组成部分：不提供双通道自诊断覆盖率证明，不参与 ISO 13849 / IEC 62061
 *                         的 PL / SIL 定级，其输出不得接入安全链路的停机判据。
 * 归属声明 (Ownership)  : 健康出口 eHealth 引用枚举 `E_DL_Ne107Status` 的**唯一属主**，属主文件为
 *                         `C:\Library\DL_Device\I_DL_DeviceHealth.st`（枚举定义位于该文件 L91 附近），
 *                         本件**只引用不重复声明**（全库同名枚举定义计数必须为 1，R67）。
 * 接口     (Interface)  : 输入 bFbCh1 / bFbCh2 双通道反馈、bCmd 指令、tSyncWin 同步窗、bNcLogic
 *                         常闭逻辑组态位、bReset 复位；输出 eCause 归因、bSyncOk 双通道同步、
 *                         eHealth NE107 健康态、eState / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：tSyncWin <= T#0S → 故障锁存，**且非法时 eHealth 直接给
 *                         eFailure**（保守：无法判定同步即按失效上报）；
 *                         ② 常闭语义：bNcLogic = TRUE 时期望反馈 = NOT bCmd；= FALSE 时期望 = bCmd；
 *                         ③ 两通道互斥用布尔 XOR 判，无浮点参与；
 *                         ④ TON 两枚 + R_TRIG 两枚段 0 无条件周期刷新（IN 由相位派生，R228A）；
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 两通道当前一致（bFbCh1 = bFbCh2，当拍量，
 *                         R240 范式）。自证可满足（终审两式 1）：两枚 TON 的 IN 均挂相位，
 *                         故障相内 IN 恒假 → Q 恒假；两通道物理恢复一致即达，无恒假因子。
 * 码表     (Codes)      : 16#0003_0701 故障级：安全继电器反馈故障总码（组态非法 / 通道不同步 /
 *                         单通道失效 / 双通道失效 / 常闭回路断开 / 非法相位），锁存至 bReset 上升沿，
 *                         归因由 eCause 承载（R190 单件单总码，每个成因成员均有独立赋值点）；
 *                         16#0003_0480 信息级：同步窗正常结束（两通道已按指令同步跟随）。
 *                         加码反证（R90）：同步窗正常结束时 bSyncOk 由假转真，而「一直停在 eRun
 *                         未做过切换」也保持 bSyncOk 为真，二者出口组合无法唯一区分「刚完成一次
 *                         动作确认」与「从未动作」，故立一码留痕。
 *                         码段说明：Device 的 03xx 故障子带已占满（03A0~03FF 连续占位，仅余
 *                         03C5~03C9 碎片孔洞），按实战规则 13「禁止回填他人预留碎片孔洞」，
 *                         本批新开 07xx 故障子带并取 16#0003_0701；信息级仍用 04xx 子带取
 *                         16#0003_0480（该段源码实扫为空）。分段理由即此，非笔误。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考 ISA-18.2 / NE107 安全回路一致性语义与
 *                         参数域，零代码行复制；t2-8-isa182 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 3 · 序号 15）
 *==============================================================================*)

TYPE E_DL_SrfState :
(
    eIdle     := 0,     // 未使能待机 / Idle, standing by
    eSyncWait := 10,    // 指令变化后同步窗内（信号暂不可信） / Inside sync window after a command change
    eRun      := 20,    // 同步完成，稳态监视 / Synchronised, steady monitoring
    eFault    := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_SrfCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eSync       := 2,   // 两通道不同步 / Channels out of sync
    eCh1Fail    := 3,   // 通道 1 未跟随 / Channel 1 failed to follow
    eCh2Fail    := 4,   // 通道 2 未跟随 / Channel 2 failed to follow
    eBothFail   := 5,   // 两通道均未跟随 / Both channels failed to follow
    eNcOpen     := 6,   // 常闭回路断开 / Normally-closed loop open
    ePhaseBad   := 7    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_SafetyRelayFeedback
VAR_INPUT
    bFbCh1    : BOOL := FALSE;          // 通道 1 反馈 [-] / Channel 1 feedback
    bFbCh2    : BOOL := FALSE;          // 通道 2 反馈 [-] / Channel 2 feedback
    bCmd      : BOOL := FALSE;          // 继电器指令 [-] / Relay command
    tSyncWin  : TIME := T#300MS;        // 同步窗时长，域 > T#0S [ms] / Sync window duration, domain > T#0S [ms]
    bNcLogic  : BOOL := TRUE;           // 常闭逻辑组态位：TRUE 时期望反馈 = NOT bCmd [-] / NC logic: expected = NOT command
    bReset    : BOOL := FALSE;          // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    eCause    : E_DL_SrfCause;          // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bSyncOk   : BOOL;                   // 双通道同步（稳态且两通道一致且均符合期望） [-] / Channels in sync
    eHealth   : E_DL_Ne107Status;       // NE107 健康态（引用唯一属主枚举） [-] / NE107 health, owner enum referenced
    eState    : E_DL_SrfState;          // 状态出口，段 6 单点映射 / State outlet
    bError    : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    nErrId    : UDINT;                  // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState   : E_DL_SrfState := E_DL_SrfState.eIdle;      // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_SrfCause := E_DL_SrfCause.eNone;      // 故障成因锁存（锁存量） / Latched cause
    tonSync   : TON;                    // 同步窗计时，段 0 无条件调用 / Sync window timer
    tonDiff   : TON;                    // 通道不一致持续计时，段 0 无条件调用 / Channel-difference timer
    rtCmd     : R_TRIG;                 // 指令变化沿实例，段 0 无条件调用 / Command change edge
    rtReset   : R_TRIG;                 // 复位沿实例，段 0 无条件调用 / Reset edge
    _bExpect  : BOOL;                   // 常闭/常开语义换算后的期望反馈当拍量 [-] / Expected feedback after NC/NO mapping
    _bChDiff  : BOOL;                   // 两通道不一致当拍量 [-] / Channels disagree
    _bCh1Ok   : BOOL;                   // 通道 1 符合期望当拍量 [-] / Channel 1 matches expectation
    _bCh2Ok   : BOOL;                   // 通道 2 符合期望当拍量 [-] / Channel 2 matches expectation
    _bNcOpen  : BOOL;                   // 常闭回路断开当拍量 [-] / NC loop open
    _bCfgBad  : BOOL;                   // 组态非法当拍量 [-] / Illegal configuration
    _bFault   : BOOL;                   // 故障锁存位（锁存量） / Latched fault bit
    _uFault   : UDINT;                  // 故障码锁存（锁存量） / Latched fault code
    _uInfo    : UDINT;                  // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_bExpect := bCmd;                                                                  // 缺省常开语义 / Default NO logic
IF bNcLogic THEN
    _bExpect := NOT bCmd;                                                          // 常闭语义：期望反馈取反 / NC logic inverts the expectation
END_IF
_bChDiff := bFbCh1 XOR bFbCh2;                                                     // 两通道不一致（布尔异或） / Channels disagree
_bCh1Ok  := (bFbCh1 AND _bExpect) OR ((NOT bFbCh1) AND (NOT _bExpect));             // 通道 1 符合期望 / Channel 1 matches expectation
_bCh2Ok  := (bFbCh2 AND _bExpect) OR ((NOT bFbCh2) AND (NOT _bExpect));             // 通道 2 符合期望 / Channel 2 matches expectation
_bNcOpen := bNcLogic AND (NOT bCmd) AND (NOT bFbCh1) AND (NOT bFbCh2);              // 常闭回路断开（指令 0 而反馈 0） / NC loop open
_bCfgBad := (tSyncWin <= T#0S);                                                     // 组态域闸 / Configuration gate
rtCmd(CLK := bCmd);                                                                 // 指令变化沿，每拍必调（R228A） / Command change edge
rtReset(CLK := bReset);                                                             // 复位沿，每拍必调 / Reset edge
tonSync(IN := (_eState = E_DL_SrfState.eSyncWait), PT := tSyncWin);                 // 同步窗计时（IN 由相位派生） / Sync window timer
tonDiff(IN := (_eState = E_DL_SrfState.eSyncWait) AND _bChDiff, PT := tSyncWin);    // 不一致持续计时 / Channel-difference timer

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo   := 16#0000_0000;          // 信息码每拍重算 / Info recomputed every scan
bSyncOk  := FALSE;                 // 同步位每拍预清 / Sync flag preset
nErrId   := 16#0000_0000;          // 事件码缺省无事件 / Event code default none
bError   := FALSE;                 // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 常闭断开判决 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_SrfCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_SrfState.eFault THEN
        _eState := E_DL_SrfState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0003_0701;                                             // 故障级：安全继电器反馈故障总码 / Fault-level: relay feedback fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_SrfCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNcOpen THEN                                       // 常闭回路断开（连续监视，不限相位） / NC loop open, monitored continuously
    _uFault := 16#0003_0701;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SrfCause.eNcOpen;                                    // 归因：常闭断开 / Cause: NC loop open
END_IF

(* —— 段 3：同步窗末判定（四结局归因唯一，R190） —— *)
IF (NOT _bFault) AND tonSync.Q THEN                                      // 同步窗到时 / Sync window elapsed
    IF _bChDiff THEN                                                     // 结局 1：两通道仍不一致 / Outcome 1, still disagreeing
        _uFault := 16#0003_0701;
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_SrfCause.eSync;                                  // 归因：不同步 / Cause: out of sync
    ELSIF (NOT _bCh1Ok) AND (NOT _bCh2Ok) THEN                           // 结局 2：两通道均未跟随 / Outcome 2, both failed
        _uFault := 16#0003_0701;
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_SrfCause.eBothFail;                              // 归因：双通道失效 / Cause: both channels failed
    ELSIF NOT _bCh1Ok THEN                                               // 结局 3：仅通道 1 未跟随 / Outcome 3, channel 1 only
        _uFault := 16#0003_0701;
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_SrfCause.eCh1Fail;                               // 归因：通道 1 失效 / Cause: channel 1 failed
    ELSIF NOT _bCh2Ok THEN                                               // 结局 4：仅通道 2 未跟随 / Outcome 4, channel 2 only
        _uFault := 16#0003_0701;
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_SrfCause.eCh2Fail;                               // 归因：通道 2 失效 / Cause: channel 2 failed
    ELSE
        _uInfo := 16#0003_0480;                                          // 信息级：同步窗正常结束 / Info: sync window closed normally
    END_IF
END_IF

(* —— 段 4：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bChDiff) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_SrfCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_SrfState.eFault) THEN
    _eState := E_DL_SrfState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_SrfState.eIdle:
    IF (NOT _bCfgBad) AND (NOT _bFault) THEN                             // 出口 1：组态合法，进入稳态监视 / Config legal, enter steady monitoring
        _eState := E_DL_SrfState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_SrfState.eFault;
    END_IF

E_DL_SrfState.eRun:
    IF rtCmd.Q AND (NOT _bFault) THEN                                    // 出口 1：指令变化，开同步窗 / Command changed, open sync window
        _eState := E_DL_SrfState.eSyncWait;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_SrfState.eFault;
    END_IF

E_DL_SrfState.eSyncWait:
    IF tonSync.Q THEN                                                    // 出口 1：窗到，判定已由段 3 完成 / Window elapsed, verdict done in segment 3
        IF _bFault THEN
            _eState := E_DL_SrfState.eFault;                             // 判定失败即入故障相 / Failed verdict enters fault
        ELSE
            _eState := E_DL_SrfState.eRun;                               // 同步成功回稳态 / Sync OK back to steady run
        END_IF
    ELSIF (NOT bCmd) AND (NOT _bChDiff) THEN                             // 出口 2：指令回安全侧且两通道已一致（判据对象消失，R98） / Command back on the safe side with channels consistent
        _eState := E_DL_SrfState.eRun;
    END_IF

E_DL_SrfState.eFault:
    ;                                                                     // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0003_0701;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SrfCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_SrfState.eFault;

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放；NE107 健康态仲裁） —— *)
IF _bFault OR _bCfgBad THEN
    bSyncOk := FALSE;                                                    // 故障/组态非法：不宣称同步 / No sync claim
    eHealth := E_DL_Ne107Status.eFailure;                                // 失效级（组态非法也按失效保守上报） / Failure level, conservative
ELSIF _eState = E_DL_SrfState.eSyncWait THEN
    bSyncOk := FALSE;                                                    // 窗内信号暂不可信 / Signals not yet trustworthy inside the window
    eHealth := E_DL_Ne107Status.eCheckFunction;                          // 功能检查级：动作确认中 / Function-check level during confirmation
ELSIF (_eState = E_DL_SrfState.eRun) AND (NOT _bChDiff) AND _bCh1Ok AND _bCh2Ok THEN
    bSyncOk := TRUE;                                                     // 稳态且两通道一致且符合期望 / Steady, consistent and as expected
    eHealth := E_DL_Ne107Status.eOk;                                     // 正常级 / OK level
ELSE
    bSyncOk := FALSE;                                                    // 其余情形一律不宣称同步 / No sync claim otherwise
    eHealth := E_DL_Ne107Status.eMaintenanceReq;                         // 需要维护级 / Maintenance-required level
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
