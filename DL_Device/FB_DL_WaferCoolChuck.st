(*
  FB_DL_WaferCoolChuck  —  晶圆冷却吸盘（真空吸附确认 / 温控投运联锁 / 温度-真空双条件释放）/ Wafer cooling chuck
  分类 Category : DL_Device
  码位 Code     : 16#03_2_0B
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : Lam LBP（背压冷却 / LBP 公开语义）借鉴，clean-room 实现，未复制任何源码行
  功能 Function : 1) 吸附链：发建立真空指令 → 真空度（负压绝对值）达 fVacConfirmKpa 且持续 tAttachConfirm
                     才确认 bClamped；确认后**才允许** bTempEnable（温控投运与吸附强联锁）；
                  2) 吸附失败按 nRetryMax 重试，每次重试重发建立指令，重试耗尽锁存 021B；
                  3) 释放链：须同时满足「温度 <= fTempAttachMaxC − 2 °C（回差）」与「真空已破」两条件，
                     任一不满足则不推进状态（温度不满足置 bInterlockBlocked，真空未破由 tReleaseTimeout 升级）；
                  4) 温度越限按「吸附中 / 未吸附」两路独立码归因（022B / 023B，R190 归因唯一）。
  边界 Boundary : ① fTempAttachMaxC 与环境上限 fAmbientMaxC 倒置（attach 上限 <= 环境上限）判组态错 020B，
                      状态进 eFault 且不投运；fVacConfirmKpa <= 0 / nRetryMax < 0 / 时间参数 <= 0 同判组态错；
                  ② **两路温度故障码不得共用**：吸附中越上限 = 022B（晶圆可能已吸附在超温盘面，必须锁存并
                      禁止再投温控）；未吸附时越上限 = 023B（只是盘面过温，允许冷却后继续）；
                  ③ 解除式自证：_bFault 清除 = rtReset.Q（引脚可满足）；022B / 023B 另可由
                      「温度回落至 fTempAttachMaxC − DL_TEMP_HYST_C 以下」按码专清（R188 可达清除边）；
                  ④ 释放期真空未破不推进状态（不靠延时硬推），由 tReleaseTimeout 升级为 024B 锁存；
                  ⑤ 注入件故障（iVac.bFault / iTempZone.bFault）→ 拒绝新吸附并置信息级 013B（不置 bError，
                      故障属主是被注入件，本件只用其 uErrorId 做归因透出）；
                  ⑥ bTempEnable 仅在 eClamped / eCooling 两相为真，其余相（含 eReleasing / eFault）恒 FALSE。
  依赖 Depends  : I_DL_VacuumGenerator（DL_Device 既有契约）、I_DL_TemperatureZone（DL_Device 既有契约）；
                  仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX），接口只注入不实例化
  同拍双窗配比  : tAttachConfirm（吸附确认驻留）与 tReleaseTimeout（释放超时）不同源；配比约束
                  tAttachConfirm <= tReleaseTimeout，避免释放判据比吸附确认更早失效（R100）

  码表 Error codes（本件格 03_2_0B，子码步进 +0x10）:
    16#0003_020B 故障级：组态非法（温度上限倒置 / 真空确认门限 <= 0 / 重试次数 < 0 / 时间参数 <= 0）
    16#0003_021B 故障级：吸附失败且重试耗尽（真空未达 fVacConfirmKpa，锁存）
    16#0003_022B 故障级：吸附保持中盘面温度越上限（禁止再投温控，锁存）
    16#0003_023B 故障级：未吸附状态下盘面温度越上限（盘面过温，冷却后可解）
    16#0003_024B 故障级：释放超时（tReleaseTimeout 到点真空仍未破，锁存）
    16#0003_025B 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0003_010B 信息级：释放被温度联锁阻断（温度未回落到允许上限以下，不置 bError）
    16#0003_011B 信息级：吸附确认完成（bClamped 上升拍，不置 bError）
    16#0003_012B 信息级：吸附重试一次（本次未达真空门限，重发建立指令）
    16#0003_013B 信息级：注入件故障，拒绝吸附（iVac.bFault 或 iTempZone.bFault，不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
*)

TYPE E_DL_ChuckState :
(
    eIdle       := 0,   // 空闲：未吸附、温控断开 / Idle, no clamping, temperature control off
    eEvacuating := 10,  // 吸附中：建立真空并等待确认 / Evacuating, waiting for the vacuum confirmation
    eClamped    := 20,  // 已吸附：真空确认，温控待投运 / Clamped, vacuum confirmed, temperature control pending
    eCooling    := 30,  // 冷却中：温控已投运并保持 / Cooling, temperature control commissioned and holding
    eReleasing  := 40,  // 释放中：破真空，等温度与真空双条件 / Releasing, awaiting both temperature and vacuum release
    eFault      := 90   // 故障：锁存待复位（温度回落或复位沿）/ Fault, latched until reset or temperature recovery
);
END_TYPE

FUNCTION_BLOCK FB_DL_WaferCoolChuck
VAR_INPUT
    bEnable      : BOOL := FALSE;              // 总使能，FALSE 时断温控并停吸附 / Master enable, low level cuts the temperature control
    bReset       : BOOL := FALSE;              // 复位，上升沿清故障锁存 / Reset, rising edge clears the latch
    bClampCmd    : BOOL := FALSE;              // 吸附命令（电平，上升沿受理）/ Clamp command, accepted on a rising edge
    bReleaseCmd  : BOOL := FALSE;              // 释放命令（电平，上升沿受理）/ Release command, accepted on a rising edge
    fTempAttachMaxC : REAL := 45.0;            // 脱附允许温度上限 [°C]，域 > fAmbientMaxC / Maximum temperature permitting a release [degC]
    fAmbientMaxC : REAL := 25.0;               // 环境温度上限 [°C]，组态交叉校验用 / Ambient ceiling used by the configuration cross-check [degC]
    fVacConfirmKpa  : REAL := 60.0;            // 真空确认门限（负压绝对值）[kPa]，域 > 0 / Vacuum confirmation threshold, magnitude [kPa]
    fVacBreakKpa : REAL := 5.0;                // 判破真空门限（负压绝对值）[kPa]，域 > 0 / Vacuum-broken threshold, magnitude [kPa]
    tAttachConfirm : TIME := T#300MS;          // 吸附确认驻留时间 [ms]，域 > 0 / Attachment confirm dwell [ms]
    tRetryTimeout : TIME := T#2S;              // 单次吸附等待上限 [ms]，超时即重试 / Per-attempt vacuum budget [ms]
    tReleaseTimeout : TIME := T#5S;            // 释放超时 [ms]，超时升级故障 / Release timeout before raising a fault [ms]
    nRetryMax    : INT := 3;                   // 最大重试次数 [次]，域 >= 0 / Maximum retry count
    fCoolSetpointC : REAL := 20.0;             // 冷却设定温度 [°C]，投运时下发 / Cooling setpoint pushed on commissioning [degC]
END_VAR
VAR_OUTPUT
    bClamped     : BOOL;                       // 已吸附（真空确认）标志 / Clamped flag, vacuum confirmed
    bTempEnable  : BOOL;                       // 温控投运命令（吸附确认后才为真）/ Temperature control enable, true only while clamped
    bInterlockBlocked : BOOL;                  // 联锁阻断标志（释放被温度条件挡住）/ Interlock blocked, the release is held by temperature
    fVacKpa      : REAL;                       // 真空度（负压绝对值）[kPa]，诊断用 / Vacuum magnitude [kPa] for diagnostics
    fTempC       : REAL;                       // 盘面实测温度 [°C] / Chuck temperature [degC]
    nRetryCount  : INT;                        // 已重试次数 [次] / Retry counter
    bValid       : BOOL;                       // 判据可用标志 / Criteria usable
    bError       : BOOL;                       // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId       : UDINT;                      // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut    : E_DL_ChuckState;            // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR_IN_OUT
    iVac         : I_DL_VacuumGenerator;       // 真空发生器接口引用（注入，不实例化）/ Vacuum generator reference, injected
    iTempZone    : I_DL_TemperatureZone;       // 温控区接口引用（注入，不实例化）/ Temperature zone reference, injected
END_VAR
VAR
    tonAttach    : TON;                        // 吸附确认驻留计时，每拍无条件调用 / Attachment confirm timer, called unconditionally
    tonAttempt   : TON;                        // 单次吸附等待计时，每拍无条件调用 / Per-attempt budget timer, called unconditionally
    tonRelease   : TON;                        // 释放超时计时，每拍无条件调用 / Release timeout timer, called unconditionally
    tonHeart     : TON;                        // 周期心跳窗，自复位 / Periodic heartbeat window, self-resetting
    rtReset      : R_TRIG;                     // 复位上升沿 / Reset rising edge
    rtClamp      : R_TRIG;                     // 吸附命令上升沿 / Clamp command rising edge
    rtRelease    : R_TRIG;                     // 释放命令上升沿 / Release command rising edge
    _eState      : E_DL_ChuckState := E_DL_ChuckState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault      : UDINT;                      // 故障码锁存 / Latched fault code
    _uInfo       : UDINT;                      // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault      : BOOL;                       // 故障锁存位 / Latched fault bit
    _bParamBad   : BOOL;                       // 组态非法聚合 / Configuration invalid aggregate
    _bVacOk      : BOOL;                       // 真空达确认门限 / Vacuum reached the confirm threshold
    _bVacBroken  : BOOL;                       // 真空已破 / Vacuum broken
    _bTempHigh   : BOOL;                       // 温度越脱附允许上限 / Temperature above the release limit
    _bTempOkRel  : BOOL;                       // 温度满足释放条件（带回差）/ Temperature satisfies the release with hysteresis
    _bInjectFault: BOOL;                       // 注入件故障 / An injected component reports a fault
    _bCmdEvac    : BOOL;                       // 建立真空单发请求（段 6 落地）/ One-shot evacuate request, applied in segment 6
    _bCmdBlow    : BOOL;                       // 破真空单发请求（段 6 落地）/ One-shot blow-off request, applied in segment 6
    _bCmdStop    : BOOL;                       // 双阀全断单发请求（段 6 落地）/ One-shot stop request, applied in segment 6
    _bTempSet    : BOOL;                       // 下发设定温度单发请求 / One-shot setpoint request
    _bTempOn     : BOOL;                       // 温控投运单发请求 / One-shot temperature commission request
    _bTempOff    : BOOL;                       // 温控断电单发请求 / One-shot temperature decommission request
    _bClampedPrev: BOOL;                       // 上拍吸附快照 / Previous-scan clamped snapshot
    _bHeartBreak : BOOL := TRUE;               // 心跳窗断输入一拍 / One-scan heartbeat break
    _nRetry      : INT;                        // 重试计数保持量 [次] / Held retry counter
    _bAttemptBrk : BOOL := TRUE;               // 单次等待计时断输入一拍 / One-scan budget break
    _bRelBreak   : BOOL := TRUE;               // 释放超时计时断输入一拍 / One-scan release break
END_VAR
VAR CONSTANT
    DL_TEMP_HYST_C : REAL := 2.0;      // 释放温度回差 [°C]（规格固定 2 °C）/ Release temperature hysteresis, fixed at two degrees
    DL_EPS         : REAL := 1.0E-6;   // 判零容差 [1] / Zero tolerance
    DL_HEART_WINDOW : TIME := T#2S;    // 心跳观察窗 [ms]，自复位节拍 / Heartbeat window, self-resetting
    DL_VAL_LIM_C   : REAL := 500.0;    // 温度有限性上限 [°C] / Temperature magnitude ceiling [degC]
    DL_VAL_LIM_KPA : REAL := 200.0;    // 真空有限性上限 [kPa] / Vacuum magnitude ceiling [kPa]
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：调用语句不得置于 IF / CASE 内） —— *)
rtReset(CLK := bReset);                                        // 复位上升沿，每拍必调
rtClamp(CLK := bClampCmd);                                     // 吸附命令上升沿，每拍必调
rtRelease(CLK := bReleaseCmd);                                 // 释放命令上升沿，每拍必调
tonHeart(IN := (NOT tonHeart.Q) AND (NOT _bHeartBreak), PT := DL_HEART_WINDOW);  // 心跳窗自复位
_bHeartBreak := FALSE;                                         // 断输入拍在调用后自清
tonAttach(IN := (_eState = E_DL_ChuckState.eEvacuating) AND _bVacOk, PT := tAttachConfirm);  // 吸附确认驻留
tonAttempt(IN := (_eState = E_DL_ChuckState.eEvacuating) AND (NOT _bVacOk) AND (NOT _bAttemptBrk),
           PT := tRetryTimeout);                               // 单次等待（表达式入参）
_bAttemptBrk := FALSE;                                         // 断输入拍在调用后自清
tonRelease(IN := (_eState = E_DL_ChuckState.eReleasing) AND (NOT _bVacBroken) AND (NOT _bRelBreak),
           PT := tReleaseTimeout);                             // 释放超时（表达式入参）
_bRelBreak := FALSE;                                           // 断输入拍在调用后自清

(* —— 段 1：单拍量预清零（计数 / 保持量 / 锁存不入清单，R187①） —— *)
_uInfo        := 16#0000_0000;   // 信息码每拍重算
bError        := FALSE;          // 故障出口每拍重算，段 7 由锁存派生
bValid        := FALSE;          // 可用标志缺省 FALSE
bClamped      := FALSE;          // 吸附出口缺省 FALSE，段 8 单点置位
bTempEnable   := FALSE;          // 温控投运缺省 FALSE（失能优先）
bInterlockBlocked := FALSE;      // 联锁阻断缺省 FALSE
_bParamBad    := FALSE;          // 组态非法预清零
_bVacOk       := FALSE;          // 真空确认判据预清零
_bVacBroken   := FALSE;          // 破真空判据预清零
_bTempHigh    := FALSE;          // 温度越限判据预清零
_bTempOkRel   := FALSE;          // 释放温度条件预清零
_bInjectFault := FALSE;          // 注入件故障预清零
_bCmdEvac     := FALSE;          // 单发请求预清零（本次 CASE 可重新置位）
_bCmdBlow     := FALSE;          // 破真空请求预清零
_bCmdStop     := FALSE;          // 全断请求预清零
_bTempSet     := FALSE;          // 设温请求预清零
_bTempOn      := FALSE;          // 投运请求预清零
_bTempOff     := FALSE;          // 断电请求预清零

(* —— 段 2：复位沿清锁存（按码专清 / 恢复沿清码两路径互不掩盖，R188） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;            // 复位沿清锁存位
    _uFault := 16#0000_0000;     // 复位沿清锁存码
    _nRetry := 0;                // 复位沿清重试计数（吸附链重新起算）
    _uInfo  := 16#0000_0000;     // 复位拍不报旧信息
END_IF

(* —— 段 3：组态域闸 + 输入有限性（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fTempAttachMaxC <> fTempAttachMaxC) OR (fTempAttachMaxC > DL_VAL_LIM_C) OR
   (fTempAttachMaxC <= fAmbientMaxC) THEN
    _bParamBad := TRUE;          // 脱附允许上限非法或与环境上限倒置（上限须高于环境）
END_IF
IF (fVacConfirmKpa <> fVacConfirmKpa) OR (fVacConfirmKpa <= 0.0) OR (fVacConfirmKpa > DL_VAL_LIM_KPA) THEN
    _bParamBad := TRUE;          // 真空确认门限非法（确认判据的分母语义）
END_IF
IF (fVacBreakKpa <> fVacBreakKpa) OR (fVacBreakKpa <= 0.0) OR (fVacBreakKpa >= fVacConfirmKpa) THEN
    _bParamBad := TRUE;          // 破真空门限非法或与确认门限倒置（会形成永判未破的死区）
END_IF
IF (fCoolSetpointC <> fCoolSetpointC) OR (fCoolSetpointC <= fAmbientMaxC) THEN
    _bParamBad := TRUE;          // 冷却设定非法（须高于环境上限，否则只在环境温度上打转）
END_IF
IF nRetryMax < 0 THEN
    _bParamBad := TRUE;          // 重试次数为负非法
END_IF
IF (TIME_TO_DINT(tAttachConfirm) <= 0) OR (TIME_TO_DINT(tRetryTimeout) <= 0) OR
   (TIME_TO_DINT(tReleaseTimeout) <= 0) THEN
    _bParamBad := TRUE;          // 三个时间参数均须 > 0
END_IF
IF _bParamBad THEN
    _uFault := 16#0003_020B;     // 故障级：组态非法
    _bFault := TRUE;             // 锁存位置位（复位沿可清）
    bError  := TRUE;             // 故障标志置位（R45 配对）
    _eState := E_DL_ChuckState.eFault;  // 进故障相
END_IF

(* —— 段 4：反馈采集与判据（只读属性，零命令下发） —— *)
fVacKpa := ABS(iVac.fPressure);                 // 真空度 = 负压绝对值 [kPa]
fTempC  := iTempZone.fTempActual;               // 盘面实测温度 [°C]
IF (fVacKpa <> fVacKpa) OR (fVacKpa > DL_VAL_LIM_KPA) THEN
    _bParamBad := TRUE;                         // 真空反馈非有限或超上界：判输入异常（不得静默当作无真空）
    _uFault := 16#0003_020B;                    // 故障级：输入异常归入组态/输入异常码
    _bFault := TRUE;                            // 锁存
    bError  := TRUE;                            // 故障标志置位（R45 配对）
    _eState := E_DL_ChuckState.eFault;          // 进故障相
END_IF
_bVacOk      := (fVacKpa >= fVacConfirmKpa);    // 达确认门限
_bVacBroken  := (fVacKpa <= fVacBreakKpa);      // 已破真空（门限带迟滞，两门限已证不倒置）
_bTempHigh   := (fTempC > fTempAttachMaxC);     // 越脱附允许上限
_bTempOkRel  := (fTempC <= (fTempAttachMaxC - DL_TEMP_HYST_C));  // 释放条件：回落 2 °C（回差）
_bInjectFault := iVac.bFault OR iTempZone.bFault;                // 注入件故障聚合

(* —— 段 5：温度越限两路归因（吸附中 / 未吸附，码不共用，R190） —— *)
IF (fTempC < -DL_VAL_LIM_C) OR (fTempC > DL_VAL_LIM_C) THEN
    _bParamBad := TRUE;                          // 温度非有限：按组态/输入异常处理，不伪造越限
    _uFault := 16#0003_020B;                     // 故障级：输入非有限归入组态/输入异常码
    _bFault := TRUE;                             // 锁存
    bError  := TRUE;                             // 故障标志置位（R45 配对）
    _eState := E_DL_ChuckState.eFault;           // 进故障相
ELSIF _bTempHigh THEN
    IF (_eState = E_DL_ChuckState.eClamped) OR (_eState = E_DL_ChuckState.eCooling) THEN
        _uFault := 16#0003_022B;                 // 故障级：吸附保持中温度越上限（独立码）
        _bFault := TRUE;                         // 锁存
        bError  := TRUE;                         // 故障标志置位（R45 配对）
        _eState := E_DL_ChuckState.eFault;       // 进故障相（温控强制断）
    ELSE
        _uFault := 16#0003_023B;                 // 故障级：未吸附状态下盘面过温（独立码，冷却后可解）
        _bFault := TRUE;                         // 锁存
        bError  := TRUE;                         // 故障标志置位（R45 配对）
        _eState := E_DL_ChuckState.eFault;       // 进故障相
    END_IF
END_IF
IF (_uFault = 16#0003_022B) OR (_uFault = 16#0003_023B) THEN
    IF _bTempOkRel THEN
        _uFault := 16#0000_0000;                 // 按码专清：温度回落至回差带以下 → 温度类故障可解
        _bFault := FALSE;                        // 锁存位同步清（复位沿路径互不掩盖）
    END_IF
END_IF

(* —— 段 6：相位机（只做迁移与单发请求置位；命令下发在本段末统一执行） —— *)
CASE _eState OF

E_DL_ChuckState.eIdle:
    _nRetry := 0;                                            // 空闲：重试计数归零（唯一清零点在本相）
    IF rtClamp.Q THEN
        IF (NOT bEnable) OR _bInjectFault THEN
            _uInfo := 16#0003_013B;                          // 信息级：注入件故障或未使能，拒绝吸附
        ELSIF _bFault THEN
            _uInfo := 16#0003_013B;                          // 信息级：存在未复位故障，拒绝吸附
        ELSE
            _eState := E_DL_ChuckState.eEvacuating;          // 进吸附相
            _bCmdEvac := TRUE;                               // 首个建立真空指令（单发）
            _bAttemptBrk := TRUE;                            // 单次等待计时从零开始
        END_IF
    END_IF

E_DL_ChuckState.eEvacuating:
    IF (NOT bEnable) OR _bInjectFault THEN
        _bCmdStop := TRUE;                                   // 全断双阀（安全侧），退出吸附
        _uInfo := 16#0003_013B;                              // 信息级：注入件故障，中止吸附
        _eState := E_DL_ChuckState.eIdle;                    // 回空闲
    ELSIF tonAttach.Q THEN
        _eState := E_DL_ChuckState.eClamped;                 // 吸附确认：真空达标并驻留完成
        _nRetry := 0;                                        // 确认成功：重试计数归零
        _uInfo  := 16#0003_011B;                             // 信息级：吸附确认完成
        _bTempSet := TRUE;                                   // 下发冷却设定温度（单发）
    ELSIF tonAttempt.Q THEN
        IF _nRetry < nRetryMax THEN
            _nRetry := _nRetry + 1;                          // 重试计数 +1
            _bCmdEvac := TRUE;                               // 重发建立真空指令（单发）
            _bAttemptBrk := TRUE;                            // 单次等待计时重启
            _uInfo := 16#0003_012B;                          // 信息级：吸附重试一次
        ELSE
            _uFault := 16#0003_021B;                         // 故障级：重试耗尽，吸附失败锁存
            _bFault := TRUE;                                 // 锁存
            bError  := TRUE;                                 // 故障标志置位（R45 配对）
            _bCmdStop := TRUE;                               // 全断双阀（不在失败态继续抽气）
            _eState := E_DL_ChuckState.eFault;               // 进故障相
        END_IF
    ELSIF rtRelease.Q THEN
        _bCmdStop := TRUE;                                   // 吸附未确认即释放：全断双阀
        _eState := E_DL_ChuckState.eIdle;                    // 回空闲（真空未建立，无需破真空）
    END_IF

E_DL_ChuckState.eClamped:
    _bTempOn := TRUE;                                        // 已吸附：允许投运温控（本相唯一置位点）
    IF (NOT bEnable) OR _bInjectFault THEN
        _bTempOff := TRUE;                                   // 断温控
        _bCmdStop := TRUE;                                   // 全断双阀（保守：失能即解除吸附保持）
        _uInfo := 16#0003_013B;                              // 信息级：注入件故障或失能
        _eState := E_DL_ChuckState.eIdle;                    // 回空闲
    ELSIF rtRelease.Q THEN
        _eState := E_DL_ChuckState.eReleasing;               // 进释放相（温度与真空双条件在相内判）
        _bRelBreak := TRUE;                                  // 释放超时计时从零开始
        _bCmdBlow := TRUE;                                   // 破真空指令（单发）
    ELSE
        _eState := E_DL_ChuckState.eCooling;                 // 确认后进冷却保持相
    END_IF

E_DL_ChuckState.eCooling:
    _bTempOn := TRUE;                                        // 冷却中：温控保持投运
    IF (NOT bEnable) OR _bInjectFault THEN
        _bTempOff := TRUE;                                   // 断温控
        _bCmdStop := TRUE;                                   // 全断双阀
        _uInfo := 16#0003_013B;                              // 信息级：注入件故障或失能
        _eState := E_DL_ChuckState.eIdle;                    // 回空闲
    ELSIF rtRelease.Q THEN
        _eState := E_DL_ChuckState.eReleasing;               // 进释放相
        _bRelBreak := TRUE;                                  // 释放超时计时从零开始
        _bCmdBlow := TRUE;                                   // 破真空指令（单发）
    END_IF

E_DL_ChuckState.eReleasing:
    IF _bVacBroken AND _bTempOkRel THEN
        _bTempOff := TRUE;                                   // 温控断电（释放完成，不再控温）
        _eState := E_DL_ChuckState.eIdle;                    // 双条件成立：回空闲
    ELSIF NOT _bTempOkRel THEN
        bInterlockBlocked := TRUE;                           // 温度未回落：联锁阻断，**状态不推进**
        _uInfo := 16#0003_010B;                              // 信息级：释放被温度联锁阻断
        IF tonRelease.Q THEN
            _uFault := 16#0003_024B;                         // 故障级：释放超时（温度与真空双失败）
            _bFault := TRUE;                                 // 锁存
            bError  := TRUE;                                 // 故障标志置位（R45 配对）
            _eState := E_DL_ChuckState.eFault;               // 进故障相
        END_IF
    ELSIF tonRelease.Q THEN
        _uFault := 16#0003_024B;                             // 故障级：真空未破且超时（真空侧失败）
        _bFault := TRUE;                                     // 锁存
        bError  := TRUE;                                     // 故障标志置位（R45 配对）
        _eState := E_DL_ChuckState.eFault;                   // 进故障相
    END_IF

E_DL_ChuckState.eFault:
    _bTempOff := TRUE;                                       // 故障：温控强制断电（安全侧）
    _bCmdStop := TRUE;                                       // 故障：双阀全断（保持现状，不主动吹气）
    IF (NOT _bFault) AND (NOT _bParamBad) AND bEnable THEN
        _eState := E_DL_ChuckState.eIdle;                    // 锁存已清且组态合法：回空闲
    END_IF

ELSE
    _uFault := 16#0003_025B;                                 // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                         // 锁存
    bError  := TRUE;                                         // 故障标志置位（R45 配对）
    _eState := E_DL_ChuckState.eFault;                       // 强制回故障相
END_CASE

(* —— 段 6A：单发命令落地（每拍最多一次，禁在 CASE 内直呼接口方法） —— *)
_bTempOn  := _bTempOn  AND (NOT _bFault);   // 故障期不投运温控（门控挂状态量）
_bTempSet := _bTempSet AND (NOT _bFault);   // 故障期不下发设定
IF _bCmdEvac THEN
    _bCmdEvac := FALSE;                     // 先清标志再下发，防方法内异常导致重复调用
    _bCmdEvac := iVac.CmdEvacuate();        // 建立真空（返回受理结果，未受理则由重试链兜底）
END_IF
IF _bCmdBlow THEN
    _bCmdBlow := FALSE;                     // 先清标志
    _bCmdBlow := iVac.CmdBlowOff();         // 破真空（实现块输出定宽脉冲）
END_IF
IF _bCmdStop THEN
    _bCmdStop := FALSE;                     // 先清标志
    _bCmdStop := iVac.CmdStop();            // 双阀全断（保持现状）
END_IF
IF _bTempSet THEN
    _bTempSet := FALSE;                     // 先清标志
    _bTempSet := iTempZone.SetSetpoint(fTemp := fCoolSetpointC);  // 下发冷却设定
END_IF
IF _bTempOn THEN
    _bTempOn := FALSE;                      // 先清标志
    iTempZone.CmdEnable(bOn := TRUE);       // 温控投运（无返回，靠反馈确认）
END_IF
IF _bTempOff THEN
    _bTempOff := FALSE;                     // 先清标志
    iTempZone.CmdEnable(bOn := FALSE);      // 温控断电（无返回，安全侧动作）
END_IF

(* —— 段 7：故障码优先级链（每个 bError 置位源在此均有码，R45 配对） —— *)
IF _bParamBad THEN
    bError := TRUE;                         // 组态非法：码已在段 3/段 5 置位（020B），此处仅保证配对
END_IF

(* —— 段 8：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bClamped := (_eState = E_DL_ChuckState.eClamped) OR (_eState = E_DL_ChuckState.eCooling);  // 吸附保持出口
bTempEnable := bClamped AND bEnable AND (NOT _bFault);   // 温控投运：仅吸附保持且无故障且使能
nRetryCount := _nRetry;                                  // 重试计数出口
eStateOut   := _eState;                                  // 状态出口
IF _bFault THEN
    nErrId := _uFault;                                   // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                                      // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                                    // 信息码
END_IF
bValid := bEnable AND (NOT _bFault) AND (NOT _bParamBad);  // 判据可用

END_FUNCTION_BLOCK
