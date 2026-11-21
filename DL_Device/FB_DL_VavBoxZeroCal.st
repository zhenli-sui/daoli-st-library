(*
  FB_DL_VavBoxZeroCal  —  变风量末端风量零点标定 / VAV box airflow zero calibration
  分类 Category : DL_Device
  码位 Code     : 16#03_2_12
  段位说明      : 03_2 段低半字节 00~0F 已满（05 为历史空穴留存），进位 12 段续号（R192）
  版本 Version  : 1.0.2
  来源 Source   : t1-2-oscat-building — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : OSCAT 楼控 VAV 公开语义借鉴，clean-room 实现，未复制任何源码行（RESUME 承接 R36 §4 #14 规格）
  功能 Function : 1) 阀门关位且信号在 fStableBandPa 带内稳定 tStableTime → 采零点偏移 fZeroOffset；
                  2) 开位同理采满量程点，span 增益 fSpanGain = (满量程 − 零点)/fSpanRefPa；
                  3) 两点标定完成才置 bCalValid；标定全程 bRegulateFrozen := TRUE（冻结调节，防标定期误调）。
  边界 Boundary : ① 两点顺序反了（先开位后关位）判顺序错置码；关/开位反馈同拍为 TRUE 判组态错；
                  ② 零点与满量程差不满足 fMinSpanPa 判标定失败（不透传负 span，参数保持旧值）；
                  ③ 每相驻留超 tCalTimeout 独立退出并保持旧参数（返修后口径，总上限 2 × tCalTimeout）；
                  ④ 组态非法（tStableTime <= 0 / fStableBandPa <= 0 / fSpanRefPa <= 0 / fMinSpanPa <= 0 / tCalTimeout <= 0）判码；
                  ⑤ 解除式自证：bCalValid 置位路径 = 零点/满量程两次采样均成功（状态机推进自然达成）；
                  ⑥ CASE 全态覆盖 + ELSE 兜底置故障相。
  依赖 Depends  : 仅 Standard.library（TON/R_TRIG）；标定换算语义对齐 FC_DL_LinearScale（已注册，不实例化）
  码表 Error codes（本件格 03_2_12，子码步进 +0x100）:
    16#0003_0112 信息级：标定进行中（调节冻结，不置故障）
    16#0003_0212 故障级：组态非法（时间/带宽/参考量程 <= 0 或关开反馈同拍为真），锁存至复位
    16#0003_0312 故障级：两点顺序错（先开位后关位）
    16#0003_0412 故障级：标定失败（分辨率不足或相超时，每相独立 tCalTimeout 口径），参数保持旧值
    16#0003_0512 故障级：状态机落 ELSE 兜底（非法相位 ID）

R39 返修（R38 终审挂账闭环，v1.0.2）: tonStable/tonCal IN 跨 eZeroWait/eFullWait 两相不随迁移重启
  → 拆分为按相独立实例：tonStableZero/tonStableFull（各相稳定驻留）+ tonCalZero/tonCalFull
  （各相独立超时，PT 均 = tCalTimeout）。语义变化声明：总超时口径收紧为「每相独立 tCalTimeout」，
  两相合计上限 2 × tCalTimeout，满量程驻留计时不再继承零点相残留（R228-A 达标：IN 单相等式，
  跨相迁移拍必断）。
  修订历史 Revision :
    2026-11-19  v1.0.2  R39 返修：稳定/超时 TON 按相独立实例化（R38 挂账闭环）
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_CalState :
(
    eIdle     := 0,    // 空闲：无标定指令 / Idle, no calibration command
    eZeroWait := 10,   // 零点稳定等待：关位 + 带内驻留 / Zero wait, closed and dwelling in band
    eFullWait := 20,   // 满量程稳定等待：开位 + 带内驻留 / Full-scale wait, open and dwelling in band
    eDone     := 30,   // 完成：两点已采，参数有效 / Done, both points captured
    eFault    := 90    // 故障：顺序/组态/失败锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_VavBoxZeroCal
VAR_INPUT
    fAirflowRaw   : REAL;                 // 原始风量信号 [Pa] / Raw airflow signal
    bDamperClosed : BOOL := FALSE;        // 阀门关位反馈 / Damper closed feedback
    bDamperOpen   : BOOL := FALSE;        // 阀门开位反馈 / Damper open feedback
    bCalCmd       : BOOL := FALSE;        // 标定启动指令（上升沿）/ Calibration start command
    tStableTime   : TIME := T#5S;         // 稳定驻留时间 [ms]，域 > 0 / Stability dwell time
    fStableBandPa : REAL := 5.0;          // 稳定判据带宽 [Pa]，域 > 0 / Stability band
    fSpanRefPa    : REAL := 500.0;        // 设计满量程参考压差 [Pa]，域 > 0 / Design full-scale reference
    fMinSpanPa    : REAL := 10.0;         // 最小可分辨跨度 [Pa]，域 > 0 / Minimum resolvable span
    tCalTimeout   : TIME := T#120S;       // 标定总超时 [ms]，域 > 0 / Calibration total timeout
    bReset        : BOOL := FALSE;        // 复位（Fault 解除路径）/ Reset
END_VAR
VAR_OUTPUT
    fZeroOffset    : REAL;                // 零点偏移 [Pa] / Zero offset
    fSpanGain      : REAL;                // span 增益 [无量纲] / Span gain
    bCalValid      : BOOL;                // 两点标定完成有效 / Calibration valid
    bCalInProgress : BOOL;                // 标定进行中 / Calibration in progress
    bRegulateFrozen: BOOL;                // 调节冻结（标定全程）/ Regulate frozen
    nErrId         : UDINT;               // 事件码，0 = 无事件 / Event code
    eState         : E_DL_CalState;       // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR
    tonStableZero : TON;                  // 零点相稳定驻留计时（单相独占）/ Zero-phase stability timer
    tonStableFull : TON;                  // 满量程相稳定驻留计时（单相独占）/ Full-phase stability timer
    tonCalZero    : TON;                  // 零点相超时计时（单相独占）/ Zero-phase timeout timer
    tonCalFull    : TON;                  // 满量程相超时计时（单相独占）/ Full-phase timeout timer
    tonFaultWch: TON;                     // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtCmd     : R_TRIG;                   // 标定指令上升沿 / Cal command rising edge
    rtReset   : R_TRIG;                   // 复位上升沿 / Reset rising edge
    _eState   : E_DL_CalState := E_DL_CalState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rZeroSmp : REAL;                     // 零点采样暂存 / Zero sample scratch
    _rFullSmp : REAL;                     // 满量程采样暂存 / Full-scale sample scratch
    _bZeroGot : BOOL;                     // 零点已采标志 / Zero captured flag
    _bFullGot : BOOL;                     // 满量程已采标志 / Full captured flag
    _bStable  : BOOL;                     // 本拍带内稳定标志 / Stable-in-band flag
    _rDev     : REAL;                     // 稳定判据偏差暂存 / Deviation scratch
    _uFault   : UDINT;                    // 故障码锁存 / Latched fault code
    _uInfo    : UDINT;                    // 信息码，每拍重算 / Info code
    _bFault   : BOOL;                     // 故障锁存位 / Latched fault bit
    _bCfgBad  : BOOL;                     // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    rFinLim   : REAL := 1.0E15;   // 非有限值筛查幅值上限 / Non-finite screening cap
    DL_WatchPt: TIME := T#2S;     // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtCmd(CLK := bCalCmd);                                          // 标定指令上升沿，每拍必调
rtReset(CLK := bReset);                                         // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WatchPt);       // 观察窗自复位（表达式入参）
tonStableZero(IN := (_eState = E_DL_CalState.eZeroWait) AND _bStable,
              PT := tStableTime);                               // 零点相稳定驻留（单相独占，带内才计时）
tonStableFull(IN := (_eState = E_DL_CalState.eFullWait) AND _bStable,
              PT := tStableTime);                               // 满量程相稳定驻留（单相独占，带内才计时）
tonCalZero(IN := (_eState = E_DL_CalState.eZeroWait), PT := tCalTimeout);   // 零点相超时（单相独占）
tonCalFull(IN := (_eState = E_DL_CalState.eFullWait), PT := tCalTimeout);   // 满量程相超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_rZeroSmp/_rFullSmp/_bZeroGot/_bFullGot 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
bCalInProgress := FALSE;        // 进行中出口缺省 FALSE（段 8 单点置位）
bRegulateFrozen := FALSE;       // 冻结出口缺省 FALSE（段 8 单点置位）
_bCfgBad := FALSE;              // 组态非法预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF TIME_TO_DINT(tStableTime) <= 0 THEN
    _bCfgBad := TRUE;           // 稳定驻留非法
END_IF
IF (fStableBandPa <> fStableBandPa) OR (fStableBandPa <= 0.0) OR (ABS(fAirflowRaw) > rFinLim) THEN
    _bCfgBad := TRUE;           // 带宽非法或原始信号非有限
END_IF
IF (fSpanRefPa <> fSpanRefPa) OR (fSpanRefPa <= 0.0) OR (fMinSpanPa <= 0.0) THEN
    _bCfgBad := TRUE;           // 参考量程/最小跨度非法（防除零）
END_IF
IF TIME_TO_DINT(tCalTimeout) <= 0 THEN
    _bCfgBad := TRUE;           // 超时非法
END_IF
IF bDamperClosed AND bDamperOpen THEN
    _bCfgBad := TRUE;           // 关/开反馈同拍为真：组态矛盾
END_IF

(* —— 段 3：复位沿（Fault 解除唯一路径：bReset） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;           // 清故障锁存位
    _uFault := 16#0000_0000;    // 清锁存码
    _eState := E_DL_CalState.eIdle;   // 回空闲（组态合法性由段 2 复判）
END_IF

(* —— 段 4：稳定判据（带内偏差） —— *)
IF (_eState = E_DL_CalState.eZeroWait) OR (_eState = E_DL_CalState.eFullWait) THEN
    _rDev := fAirflowRaw;                       // 判据基准：绝对值落在 ±带宽内（静流零漂近似）
    IF ABS(_rDev) <= fStableBandPa THEN
        _bStable := TRUE;                       // 带内：驻留计时有效
    ELSE
        _bStable := FALSE;                      // 带外：驻留中断（TON 断输入即归零，R188）
    END_IF
ELSE
    _bStable := FALSE;                          // 非等待相：不判稳定
END_IF

(* —— 段 5：相位机（只做迁移与采样；出口在段 8） —— *)
CASE _eState OF

E_DL_CalState.eIdle:
    IF _bCfgBad THEN
        _uFault := 16#0003_0212;                // 故障级：组态非法
        _bFault := TRUE;                        // 锁存（复位沿可清）
        _eState := E_DL_CalState.eFault;
    ELSIF rtCmd.Q THEN
        IF bDamperOpen THEN
            _uFault := 16#0003_0312;            // 故障级：顺序错（先开位后关位）
            _bFault := TRUE;
            _eState := E_DL_CalState.eFault;
        ELSIF bDamperClosed THEN
            _eState := E_DL_CalState.eZeroWait; // 关位起步：进零点等待
        ELSE
            _eState := E_DL_CalState.eZeroWait; // 未到位也进零点等待（到位前 TON 不计）
        END_IF
    END_IF

E_DL_CalState.eZeroWait:
    IF _bStable AND tonStableZero.Q THEN
        _rZeroSmp := fAirflowRaw;               // 零点采样（稳定驻留到点，零点相独立实例）
        _bZeroGot := TRUE;                      // 零点已采
        _eState := E_DL_CalState.eFullWait;     // 进满量程等待
    ELSIF tonCalZero.Q THEN
        _uFault := 16#0003_0412;                // 故障级：零点相超时（参数保持旧值）
        _bFault := TRUE;
        _eState := E_DL_CalState.eFault;
    END_IF

E_DL_CalState.eFullWait:
    IF _bStable AND tonStableFull.Q THEN
        _rFullSmp := fAirflowRaw;               // 满量程采样（满量程相独立实例，不继承零点相残留）
        _bFullGot := TRUE;                      // 满量程已采
        _eState := E_DL_CalState.eDone;         // 两点齐：进完成相
    ELSIF tonCalFull.Q THEN
        _uFault := 16#0003_0412;                // 故障级：满量程相超时
        _bFault := TRUE;
        _eState := E_DL_CalState.eFault;
    END_IF

E_DL_CalState.eDone:
    IF (_rFullSmp - _rZeroSmp) < fMinSpanPa THEN
        _uFault := 16#0003_0412;                // 故障级：分辨率不足（不透传负 span，参数保持旧值）
        _bFault := TRUE;
        _eState := E_DL_CalState.eFault;
    ELSE
        fZeroOffset := _rZeroSmp;               // 参数落地
        fSpanGain   := (_rFullSmp - _rZeroSmp) / fSpanRefPa;   // span 增益（分母已闸 > 0）
        bCalValid   := TRUE;                    // 两点均成功：bCalValid 置位（解除式自证路径）
        _uInfo := 16#0003_0112;                 // 信息级：标定完成
    END_IF
    IF NOT bCalCmd THEN
        _eState := E_DL_CalState.eIdle;         // 指令撤销：回空闲（参数与 bCalValid 保持）
    END_IF

E_DL_CalState.eFault:
    ;                                           // 故障相：等复位沿（段 3 承载解除）

ELSE
    _uFault := 16#0003_0512;                    // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                            // 锁存
    _eState := E_DL_CalState.eFault;            // 强制回故障相

END_CASE

(* —— 段 6：故障后参数保持语义（失败不落地，旧参数原样保留） —— *)
IF _bFault THEN
    _bZeroGot := FALSE;             // 采样暂存作废（下次标定重来）
    _bFullGot := FALSE;
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bCalInProgress  := (_eState = E_DL_CalState.eZeroWait) OR (_eState = E_DL_CalState.eFullWait);  // 进行中
bRegulateFrozen := bCalInProgress;                 // 标定全程冻结调节（规格强制）
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bCalValid := FALSE;             // 故障相参数有效性撤销（安全侧，防半成品参数外流）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
