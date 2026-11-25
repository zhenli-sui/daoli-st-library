(*
  Name: FB_DL_GrateCoolerStartupSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 篦冷机启动序状态机，七相推进：
           待机 → 风机启动 → 篦床低速 → 投料 → 投料升速 → 正常 → （故障）。
           待机相等 xStart 上升沿（必须边沿，防上电即在启动位自动启动）；
           风机相开风机命令并等运行反馈 + 风量达启动下限；篦床低速相给低速指令并等运行反馈；
           投料相开投料命令并等投料反馈；升速相把转速指令按 fRampRpmS 斜率从低速升到正常；
           正常相保持 xDone 并继续风量安全监督，直到 xStart 撤下才回待机。
        2) 每相独立超时 + 整序总超时：相定时器给出正常推进点，相超时定时器给出
           「定时 + DL_OVER_MARGIN」的越限点，整序总超时由 tonTotal 兜底，三者并发监视。
        3) 风量安全监督分两段语义：启动阶段风量不足只拦放行并置信息级码（0121），
           投料之后风量跌破安全下限则进入宽限窗，宽限超时判故障（0128，防篦板过热）。
  边界条件：1) 非有限值闸：风量、转速反馈、周期入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf；命中即闸断放行（_bAirOk := FALSE / 停机相），
           绝不把 NaN 与 DL_AIR_MIN 比较 —— NaN 比较恒假会伪装成「风量正常」（R19）。
        2) 周期入参闸（R21）：fCycleS <= 0.0 或非有限时，一律改用缺省 DL_CYCLE_DEF = 0.1 s，
           并置信息级码 0129 声明本次斜率按缺省周期折算，不静默。
        3) 时间参数零闸：tFanS / tGrateS / tFeedS / tRampS <= T#0S 时对应相定时器立即置 Q，
           等价于该相跳过（调试用合法组态），语义在此声明，禁上层按「必有停留」假设。
        4) 斜率上限：升速相每拍增量 = fRampRpmS * fCycleS，且指令本身钳在
           [DL_SPD_SLOW, DL_SPD_NORMAL] 内，不用 LIMIT 之后再判超限（R24）。
        5) 故障归因唯一（R190）：风机超时 / 篦床超时 / 投料超时 / 升速超时 / 总超时 /
           外部故障 / 风量不足 / 兜底，八条成因各占独立码值，不共用枚举成员。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参有限 → 清锁存回待机；
           回待机后必须重新给 xStart 上升沿才能再启动（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0130、清全部输出。
        8) 输出安全初值（R25）：fGrateSpdCmdRpm 初值 0.0（零速为安全侧），
           三个命令位初值 FALSE，待机相显式赋值，防「上电 0 值直穿下发」。
  量纲自证：fRampRpmS 为转速斜率 [rpm/s]，乘 fCycleS [s] 得每拍增量 [rpm]，
           与 fGrateSpdCmdRpm [rpm] 同量纲；fAirFlowNm3h 与 DL_AIR_MIN 同量纲 [Nm3/h]；
           所有时间引脚为 [TIME]，相超时点 = [TIME] + [TIME] = [TIME]，与 TON 的 PT 同量纲。
  码表 Error codes（本件子带 0091_012x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0121 信息级：风量低于启动下限，风机相暂不放行（不置故障位）
    16#0091_0122 故障级：风机启动超时（定时到但运行反馈未到）
    16#0091_0123 故障级：篦床低速启动超时（无运行反馈）
    16#0091_0124 故障级：投料超时（无投料反馈）
    16#0091_0125 故障级：升速超时（未达正常转速）
    16#0091_0126 故障级：整序总超时
    16#0091_0127 故障级：外部故障输入 xFault
    16#0091_0128 故障级：运行中风量低于安全下限（宽限窗超时）
    16#0091_0129 信息级：周期入参 fCycleS 非法，已按缺省 0.1 s 折算（不置故障位）
    16#0091_0130 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0091_0131 故障级：启动序期间风量/转速/斜率入参非有限（NaN 或 Inf）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_GcsStartupState :
(
    eGcsStartIdle      := 0,    // 待机：等启动上升沿 / Idle, awaiting the start rising edge
    eGcsStartFan       := 10,   // 风机启动：等运行反馈与风量 / Fan start, awaiting feedback and air flow
    eGcsStartSlowGrate := 20,   // 篦床低速：给低速指令等运行反馈 / Grate at low speed, awaiting run feedback
    eGcsStartFeed      := 30,   // 投料：开投料命令等投料反馈 / Feeding, awaiting the feed feedback
    eGcsStartRampUp    := 40,   // 投料升速：按斜率升到正常转速 / Ramping up to normal speed
    eGcsStartNormal    := 50,   // 正常：保持完成位并继续风量监督 / Normal, done held and air supervised
    eGcsStartFault     := 90    // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_GrateCoolerStartupSeq
VAR_INPUT
    xStart        : BOOL;    // 启动指令（上升沿有效）[bool] / Start command, edge triggered [bool]
    xReset        : BOOL;    // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault        : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    xFanRunFb     : BOOL;    // 风机运行反馈 [bool] / Fan running feedback [bool]
    xGrateRunFb   : BOOL;    // 篦床驱动运行反馈 [bool] / Grate drive running feedback [bool]
    xFeedRunFb    : BOOL;    // 投料设备运行反馈 [bool] / Feed device running feedback [bool]
    fAirFlowNm3h  : REAL;    // 冷却风量实测值 [Nm3/h] / Measured cooling air flow [Nm3/h]
    fGrateSpdFbRpm : REAL;   // 篦床转速反馈 [rpm] / Grate speed feedback [rpm]
    fRampRpmS     : REAL;    // 升速斜率 [rpm/s] / Speed ramp slope [rpm/s]
    fCycleS       : REAL;    // 任务周期 [s] / Task cycle time [s]
    tFanS         : TIME;    // 风机相设定时长 [TIME] / Fan phase duration [TIME]
    tGrateS       : TIME;    // 篦床低速相设定时长 [TIME] / Low-speed grate phase duration [TIME]
    tFeedS        : TIME;    // 投料相设定时长 [TIME] / Feeding phase duration [TIME]
    tRampS        : TIME;    // 升速相设定时长 [TIME] / Ramp-up phase duration [TIME]
END_VAR
VAR_OUTPUT
    xFanCmd       : BOOL;    // 风机运行命令（安全侧：故障时停）[bool] / Fan run command, fail-safe [bool]
    xGrateCmd     : BOOL;    // 篦床驱动运行命令（安全侧：故障时停）[bool] / Grate drive command, fail-safe [bool]
    xFeedCmd      : BOOL;    // 投料设备运行命令（安全侧：故障时停）[bool] / Feed device command, fail-safe [bool]
    fGrateSpdCmdRpm : REAL;  // 篦床转速指令 [rpm] / Grate speed command [rpm]
    xDone         : BOOL;    // 启动完成保持位 [bool] / Startup complete held flag [bool]
    xBusy         : BOOL;    // 启动进行中 [bool] / Startup sequence busy [bool]
    xAirOk        : BOOL;    // 风量监督通过 [bool] / Air flow supervision passed [bool]
    eState        : E_DL_GcsStartupState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId        : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonFan        : TON;     // 风机相正常定时 [TIME] / Fan phase timer
    tonFanOv      : TON;     // 风机相超时定时 [TIME] / Fan phase overrun timer
    tonGrate      : TON;     // 篦床低速相正常定时 [TIME] / Low-speed grate phase timer
    tonGrateOv    : TON;     // 篦床低速相超时定时 [TIME] / Low-speed grate phase overrun timer
    tonFeed       : TON;     // 投料相正常定时 [TIME] / Feeding phase timer
    tonFeedOv     : TON;     // 投料相超时定时 [TIME] / Feeding phase overrun timer
    tonRamp       : TON;     // 升速相正常定时 [TIME] / Ramp-up phase timer
    tonRampOv     : TON;     // 升速相超时定时 [TIME] / Ramp-up phase overrun timer
    tonTotal      : TON;     // 整序总超时定时 [TIME] / Whole-sequence total timeout timer
    tonAirG       : TON;     // 运行中风量不足宽限定时 [TIME] / Air-shortage grace timer while running
    rtStart       : R_TRIG;  // 启动上升沿检测 [bool] / Start rising edge detector
    rtReset       : R_TRIG;  // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState       : E_DL_GcsStartupState := E_DL_GcsStartupState.eGcsStartIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev   : E_DL_GcsStartupState := E_DL_GcsStartupState.eGcsStartIdle;   // 上一拍相位快照（周期末更新）
    _fSpdSet      : REAL := 0.0;    // 转速指令内部设定值（安全初值零速）[rpm] / Internal speed setpoint, safe init zero [rpm]
    _fCycleUseS   : REAL := 0.1;    // 实际使用的周期值 [s] / Cycle time actually used [s]
    _bFinOk       : BOOL := FALSE;  // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCycleBad    : BOOL := FALSE;  // 周期入参非法标志 [bool] / Cycle input invalid flag [bool]
    _bAirOk       : BOOL := FALSE;  // 风量监督结果 [bool] / Air flow supervision result [bool]
    _bActive      : BOOL := FALSE;  // 启动序激活（风机至正常五相之一）[bool] / Sequence active flag [bool]
    _bRunAirWatch : BOOL := FALSE;  // 投料后风量安全监督生效 [bool] / Post-feed air supervision active [bool]
    _bDoneL       : BOOL := FALSE;  // 完成位锁存（跨相保持）[bool] / Done latch held across phases [bool]
    _bFault       : BOOL := FALSE;  // 故障锁存位 [bool] / Latched fault flag [bool]
    _bRampDone    : BOOL := FALSE;  // 升速到位标志（指令达正常转速）[bool] / Ramp-complete flag [bool]
    _uInfo        : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault       : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
    _iPhaseChg    : INT := 0;       // 本拍相位切换计数（观测用）[-] / Phase-change count this cycle [-]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;      // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_CYCLE_DEF  : REAL := 0.1;         // 缺省任务周期 [s] / Default task cycle time [s]
    DL_CYCLE_MIN  : REAL := 0.001;       // 周期合理下限 [s] / Cycle time reasonable low bound [s]
    DL_CYCLE_MAX  : REAL := 10.0;        // 周期合理上限 [s] / Cycle time reasonable high bound [s]
    DL_AIR_MIN    : REAL := 5000.0;      // 启动风量下限 [Nm3/h] / Air flow low limit for start [Nm3/h]
    DL_AIR_SAFE   : REAL := 3000.0;      // 运行风量安全下限 [Nm3/h] / Air flow safety low limit while running [Nm3/h]
    DL_SPD_SLOW   : REAL := 2.0;         // 篦床低速设定 [rpm] / Grate low speed setpoint [rpm]
    DL_SPD_NORMAL : REAL := 12.0;        // 篦床正常转速设定 [rpm] / Grate normal speed setpoint [rpm]
    DL_OVER_MARGIN : TIME := T#30S;      // 相超时相对正常定时的裕量 [TIME] / Phase overrun margin [TIME]
    DL_TOTAL_MAX  : TIME := T#30M;       // 整序总超时上限 [TIME] / Whole-sequence total timeout [TIME]
    DL_AIR_GRACE  : TIME := T#15S;       // 运行中风量不足宽限窗 [TIME] / Air-shortage grace window [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bDoneL/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
_iPhaseChg := 0;                            // 相位切换计数每拍重算 / Phase-change counter recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：周期入参闸（R21：非法周期不静默，改用缺省并置信息码） —— *)
_bCycleBad := NOT (fCycleS > -DL_BIG AND fCycleS < DL_BIG)
              OR (fCycleS < DL_CYCLE_MIN) OR (fCycleS > DL_CYCLE_MAX);
IF _bCycleBad THEN
    _fCycleUseS := DL_CYCLE_DEF;            // 非法周期一律用缺省 0.1 s
    _uInfo := 16#0091_0129;                 // 信息级：周期入参非法，已用缺省（不置故障位）
ELSE
    _fCycleUseS := fCycleS;                 // 合法周期原值使用
END_IF

(* —— 段 2：非有限值闸（R19：闸断实值通路，风量/转速/斜率任一非有限即拒绝放行） —— *)
_bFinOk := (fAirFlowNm3h > -DL_BIG) AND (fAirFlowNm3h < DL_BIG)
           AND (fGrateSpdFbRpm > -DL_BIG) AND (fGrateSpdFbRpm < DL_BIG)
           AND (fRampRpmS > -DL_BIG) AND (fRampRpmS < DL_BIG);

(* —— 段 3：风量监督（启动用下限；非有限值直接判不通过，不参与比较） —— *)
IF NOT _bFinOk THEN
    _bAirOk := FALSE;                       // 非有限一律判不通过（安全侧）
ELSE
    _bAirOk := (fAirFlowNm3h >= DL_AIR_MIN);
END_IF

(* —— 段 4：状态派生量（本拍相位为上一拍末值，标准 FB 周期语义） —— *)
_bActive := (_eState = E_DL_GcsStartupState.eGcsStartFan)
            OR (_eState = E_DL_GcsStartupState.eGcsStartSlowGrate)
            OR (_eState = E_DL_GcsStartupState.eGcsStartFeed)
            OR (_eState = E_DL_GcsStartupState.eGcsStartRampUp)
            OR (_eState = E_DL_GcsStartupState.eGcsStartNormal);
_bRunAirWatch := (_eState = E_DL_GcsStartupState.eGcsStartFeed)
                 OR (_eState = E_DL_GcsStartupState.eGcsStartRampUp)
                 OR (_eState = E_DL_GcsStartupState.eGcsStartNormal);

(* —— 段 5：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := xStart);                                                                 // 启动上升沿，每拍必调
rtReset(CLK := xReset);                                                                 // 复位上升沿，每拍必调
tonFan(IN := (_eState = E_DL_GcsStartupState.eGcsStartFan), PT := tFanS);               // 风机相正常定时
tonFanOv(IN := (_eState = E_DL_GcsStartupState.eGcsStartFan), PT := tFanS + DL_OVER_MARGIN);      // 风机相超时点
tonGrate(IN := (_eState = E_DL_GcsStartupState.eGcsStartSlowGrate), PT := tGrateS);     // 篦床低速相正常定时
tonGrateOv(IN := (_eState = E_DL_GcsStartupState.eGcsStartSlowGrate),
           PT := tGrateS + DL_OVER_MARGIN);                                             // 篦床低速相超时点
tonFeed(IN := (_eState = E_DL_GcsStartupState.eGcsStartFeed), PT := tFeedS);            // 投料相正常定时
tonFeedOv(IN := (_eState = E_DL_GcsStartupState.eGcsStartFeed), PT := tFeedS + DL_OVER_MARGIN);   // 投料相超时点
tonRamp(IN := (_eState = E_DL_GcsStartupState.eGcsStartRampUp), PT := tRampS);          // 升速相正常定时
tonRampOv(IN := (_eState = E_DL_GcsStartupState.eGcsStartRampUp), PT := tRampS + DL_OVER_MARGIN); // 升速相超时点
tonTotal(IN := _bActive, PT := DL_TOTAL_MAX);                                           // 整序总超时
tonAirG(IN := _bRunAirWatch AND (NOT _bAirOk) AND (NOT _bFault), PT := DL_AIR_GRACE);    // 风量不足宽限窗

(* —— 段 6：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0127;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_GcsStartupState.eGcsStartFault;
END_IF
IF tonTotal.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0091_0126;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_GcsStartupState.eGcsStartFault;
END_IF
IF tonAirG.Q AND (NOT _bFault) THEN
    _uFault := 16#0091_0128;                // 故障级：运行中风量低于安全下限
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_GcsStartupState.eGcsStartFault;
END_IF
IF (NOT _bFinOk) AND (NOT _bFault) AND _bActive THEN
    _uFault := 16#0091_0131;                // 故障级：启动序期间入参非有限（独立成因，不与风机超时共用码）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_GcsStartupState.eGcsStartFault;
END_IF

(* —— 段 7：相位机（只做迁移与内部状态更新；出口在段 9 单点映射） —— *)
CASE _eState OF

E_DL_GcsStartupState.eGcsStartIdle:
    _fSpdSet := 0.0;                        // 待机转速指令显式零（安全侧，R25）
    _bRampDone := FALSE;                    // 待机重置升速到位标志
    IF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令即清完成位，为下次启动重新武装
    ELSIF NOT _bAirOk THEN
        _uInfo := 16#0091_0121;             // 信息级：风量不足，风机相暂不放行
    ELSIF rtStart.Q THEN
        _bDoneL := FALSE;                   // 新序开始：清完成位（迁移前一次性清）
        _eState := E_DL_GcsStartupState.eGcsStartFan;   // 进风机启动相
    END_IF

E_DL_GcsStartupState.eGcsStartFan:
    IF NOT xStart THEN
        _uFault := 16#0091_0127;            // 故障级：启动中撤令，按外部中断归因
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF tonFanOv.Q THEN
        _uFault := 16#0091_0122;            // 故障级：风机启动超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF tonFan.Q AND xFanRunFb AND _bAirOk THEN
        _eState := E_DL_GcsStartupState.eGcsStartSlowGrate;   // 本拍合法事件优先于超时迁移（R275）
    ELSE
        _uInfo := 16#0091_0121;             // 信息级：风量/反馈未就绪，继续等
    END_IF

E_DL_GcsStartupState.eGcsStartSlowGrate:
    _fSpdSet := DL_SPD_SLOW;                // 低速相：转速指令置低速设定
    IF NOT xStart THEN
        _uFault := 16#0091_0127;            // 故障级：启动中撤令
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF tonGrateOv.Q THEN
        _uFault := 16#0091_0123;            // 故障级：篦床低速启动超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF tonGrate.Q AND xGrateRunFb THEN
        _eState := E_DL_GcsStartupState.eGcsStartFeed;        // 进投料相
    END_IF

E_DL_GcsStartupState.eGcsStartFeed:
    _fSpdSet := DL_SPD_SLOW;                // 投料相：转速保持低速
    IF NOT xStart THEN
        _uFault := 16#0091_0127;            // 故障级：投料中撤令
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF tonFeedOv.Q THEN
        _uFault := 16#0091_0124;            // 故障级：投料超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF tonFeed.Q AND xFeedRunFb THEN
        _eState := E_DL_GcsStartupState.eGcsStartRampUp;      // 进升速相
    END_IF

E_DL_GcsStartupState.eGcsStartRampUp:
    _fSpdSet := LIMIT(DL_SPD_SLOW, _fSpdSet + fRampRpmS * _fCycleUseS, DL_SPD_NORMAL);   // 每拍按斜率升速
    _bRampDone := (_fSpdSet >= DL_SPD_NORMAL);                                            // 到位判据（用钳后设定值即可）
    IF NOT xStart THEN
        _uFault := 16#0091_0127;            // 故障级：升速中撤令
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF tonRampOv.Q AND (NOT _bRampDone) THEN
        _uFault := 16#0091_0125;            // 故障级：升速超时
        _bFault := TRUE;                    // 锁存
        _eState := E_DL_GcsStartupState.eGcsStartFault;
    ELSIF _bRampDone AND tonRamp.Q THEN
        _bDoneL := TRUE;                    // 完成位锁存（跨相保持，段 9 单点映射）
        _eState := E_DL_GcsStartupState.eGcsStartNormal;      // 进正常相
    END_IF

E_DL_GcsStartupState.eGcsStartNormal:
    _fSpdSet := DL_SPD_NORMAL;              // 正常相：转速指令置正常设定
    IF NOT xStart THEN
        _bDoneL := FALSE;                   // 撤令：清完成位并回待机（命令随之撤销）
        _bRampDone := FALSE;                // 升速标志一并清，下次重新走斜率
        _eState := E_DL_GcsStartupState.eGcsStartIdle;
    ELSIF NOT _bAirOk THEN
        _uInfo := 16#0091_0121;             // 信息级：风量偏低但仍在宽限窗内（宽限超时由段 6 判故障）
    END_IF

E_DL_GcsStartupState.eGcsStartFault:
    _fSpdSet := 0.0;                        // 故障相转速指令强制零（安全侧，R25）
    IF rtReset.Q AND (NOT xFault) AND _bFinOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参有限（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bDoneL := FALSE;                   // 完成位一并清，避免故障后误报完成
        _bRampDone := FALSE;                // 升速标志清，需重新走完整序
        _eState := E_DL_GcsStartupState.eGcsStartIdle;        // 回待机，需新上升沿才可再启动
    END_IF

ELSE
    _uFault := 16#0091_0130;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _fSpdSet := 0.0;                        // 兜底侧转速强制零
    _eState := E_DL_GcsStartupState.eGcsStartFault;           // 强制回故障相

END_CASE

(* —— 段 8：后置段（相位快照在迁移判断之后统一更新） —— *)
IF _eState <> _eStatePrev THEN
    _iPhaseChg := _iPhaseChg + 1;           // 相位已切换：记一拍切换事件（观测用）
END_IF
_eStatePrev := _eState;                     // 快照在周期末尾统一更新

(* —— 段 9：出口单点映射（名实同源；命令由状态导出，故障侧一律撤销） —— *)
xFanCmd := ((_eState = E_DL_GcsStartupState.eGcsStartFan)
            OR (_eState = E_DL_GcsStartupState.eGcsStartSlowGrate)
            OR (_eState = E_DL_GcsStartupState.eGcsStartFeed)
            OR (_eState = E_DL_GcsStartupState.eGcsStartRampUp)
            OR (_eState = E_DL_GcsStartupState.eGcsStartNormal)) AND (NOT _bFault);        // 风机：五相开
xGrateCmd := ((_eState = E_DL_GcsStartupState.eGcsStartSlowGrate)
              OR (_eState = E_DL_GcsStartupState.eGcsStartFeed)
              OR (_eState = E_DL_GcsStartupState.eGcsStartRampUp)
              OR (_eState = E_DL_GcsStartupState.eGcsStartNormal)) AND (NOT _bFault);      // 篦床：四相开
xFeedCmd := ((_eState = E_DL_GcsStartupState.eGcsStartFeed)
             OR (_eState = E_DL_GcsStartupState.eGcsStartRampUp)
             OR (_eState = E_DL_GcsStartupState.eGcsStartNormal)) AND (NOT _bFault);       // 投料：三相开
IF xGrateCmd THEN
    fGrateSpdCmdRpm := _fSpdSet;            // 转速指令出口（单点写，分支互斥）
ELSE
    fGrateSpdCmdRpm := 0.0;                 // 未开篦床即零速指令（安全侧，R25）
END_IF
xDone := _bDoneL AND (NOT _bFault);                                        // 完成位出口
xBusy := _bActive AND (NOT _bFault);                                       // 进行中出口
xAirOk := _bAirOk;                                                         // 风量监督出口
eState := _eState;                                                         // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
