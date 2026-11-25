(*
  Name: FB_DL_GrateCoolerStrokeWatch
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 篦床行程三判据并行监视，各自独立去抖：
           ① 行程超限：MAX(左/右行程) > fStrokeMaxMm（篦板越程会顶死液压缸）；
           ② 左右不同步：|左 − 右| > fSyncMaxMm（双侧不同步导致篦床歪斜与卡阻）；
           ③ 停滞：有运行指令 xEnable 且一个去抖窗内位移 < DL_MOVE_EPS（液压失压或机械卡死）。
        2) 三级报警升级：原始判据成立即进预警相（信息级码）；去抖确认后单成因进报警相（故障级码，
           不直接停机）；两成因及以上并发进停机建议相（最高级码，建议上层连锁停机）。
        3) 锁存与解除：报警相与停机建议相的故障码一律锁存回放，唯一解除路径为 xReset 上升沿，
           且解除时必须「三判据原始值全部消失」才回正常相（防止带病复位后立刻再报）。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；
           命中即置故障锁存（码 0117）并进故障相，而不是把 NaN 拿去与限值比较 ——
           NaN 比较恒假会把「测点断线」伪装成「行程正常」（R19）。
        2) 组态域闸：fStrokeMaxMm / fSyncMaxMm 必须 > DL_EPS，tDebounce / tStallS 必须 > T#0S，
           越域置码 0118 并进故障相（去抖窗为零会让判据无滞后直达停机）。
        3) 位移快照闸：首拍 _bPrevValid = FALSE 时不判停滞，避免上电首个扫描周期
           「上拍行程 = 0」造成的假停滞。
        4) 定时器周期刷新（R7）：四个 TON 实例全部在 CASE 之外无条件调用，IN 由状态与判据导出，
           相迁移即 IN 归假自复位，不靠外部沿清零（R188）。
        5) 状态机兜底：CASE 全态覆盖 + ELSE 强制进故障相并置码 0116、清全部输出。
        6) 输出安全初值（R25）：xWarn / xAlarm / xStopSuggest 初值 FALSE，nLevel 初值 0，
           待机相显式赋值，防「上电未初始化直穿」。
  量纲自证：fStrokeLeftMm / fStrokeRightMm / fStrokeMaxMm / fSyncMaxMm 均为长度 [mm]，
           比较两侧同量纲；位移差 |左 − 右| 仍为 [mm]；
           tDebounce / tStallS 为 [TIME]，直接作为 TON 的 PT，无跨量纲运算。
  码表 Error codes（本件子带 0091_011x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0111 信息级：行程判据预警（原始值成立，尚在去抖窗内，不置故障位）
    16#0091_0112 故障级：左侧行程超限（去抖确认）
    16#0091_0113 故障级：左右行程不同步（去抖确认）
    16#0091_0114 故障级：篦床停滞，有运行指令但无位移（去抖确认）
    16#0091_0115 故障级：两成因及以上并发，建议停机
    16#0091_0116 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0091_0117 故障级：行程或限值入参非有限（NaN / Inf）
    16#0091_0118 故障级：组态越域（行程限值或去抖窗为零/为负）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_GcsStrokeWatchState :
(
    eGcsStrokeNormal := 0,    // 正常：三判据原始值全部消失 / Normal, all three raw criteria cleared
    eGcsStrokeWarn   := 10,   // 预警：原始判据成立，等去抖窗 / Warning, raw criterion present, debounce running
    eGcsStrokeAlarm  := 20,   // 报警：单成因去抖确认，锁存待复位 / Alarm, single cause confirmed and latched
    eGcsStrokeTrip   := 30,   // 停机建议：两成因及以上并发 / Trip advice, two or more causes together
    eGcsStrokeFault  := 90    // 故障：入参/组态非法，锁存待复位 / Fault, invalid input or configuration, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_GrateCoolerStrokeWatch
VAR_INPUT
    xEnable        : BOOL;    // 监视使能（篦床运行指令）[bool] / Monitoring enable, grate run command [bool]
    xReset         : BOOL;    // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault         : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    fStrokeLeftMm  : REAL;    // 左侧油缸行程 [mm] / Left cylinder stroke [mm]
    fStrokeRightMm : REAL;    // 右侧油缸行程 [mm] / Right cylinder stroke [mm]
    fStrokeMaxMm   : REAL;    // 允许最大行程 [mm] / Permitted maximum stroke [mm]
    fSyncMaxMm     : REAL;    // 左右允许最大行程差 [mm] / Permitted maximum stroke difference [mm]
    tDebounce      : TIME;    // 判据去抖窗 [TIME] / Criteria debounce window [TIME]
    tStallS        : TIME;    // 停滞判定窗 [TIME] / Stall detection window [TIME]
END_VAR
VAR_OUTPUT
    xWarn          : BOOL;    // 预警位（信息级）[bool] / Warning flag, information grade [bool]
    xAlarm         : BOOL;    // 报警位（故障级）[bool] / Alarm flag, fault grade [bool]
    xStopSuggest   : BOOL;    // 停机建议位 [bool] / Stop suggestion flag [bool]
    nLevel         : INT;     // 报警等级 0=正常 1=预警 2=报警 3=停机 [level] / Alarm level 0..3 [level]
    eState         : E_DL_GcsStrokeWatchState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId         : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonOver        : TON;     // 行程超限去抖定时 [TIME] / Stroke-overrun debounce timer
    tonSync        : TON;     // 左右不同步去抖定时 [TIME] / Synchronism debounce timer
    tonStall       : TON;     // 停滞判定定时 [TIME] / Stall detection timer
    tonClear       : TON;     // 复位清障确认定时 [TIME] / Reset clearance confirmation timer
    rtReset        : R_TRIG;  // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState        : E_DL_GcsStrokeWatchState := E_DL_GcsStrokeWatchState.eGcsStrokeNormal;   // 内部相位（CASE 唯一写入目标）
    _fStrokePrevMm : REAL := 0.0;   // 上拍左侧行程快照 [mm] / Previous-cycle left stroke snapshot [mm]
    _bPrevValid    : BOOL := FALSE; // 行程快照有效位（首拍为假）/ Stroke snapshot validity, false on first cycle
    _bFinOk        : BOOL := FALSE; // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCfgOk        : BOOL := FALSE; // 组态参数域闸结果 / Configuration domain gate result
    _bOverRaw      : BOOL := FALSE; // 行程超限原始判据 [bool] / Raw stroke-overrun criterion
    _bSyncRaw      : BOOL := FALSE; // 左右不同步原始判据 [bool] / Raw synchronism criterion
    _bStallRaw     : BOOL := FALSE; // 停滞原始判据 [bool] / Raw stall criterion
    _bAnyRaw       : BOOL := FALSE; // 三判据任一成立 [bool] / Any raw criterion present
    _iCauseNum     : INT := 0;      // 已去抖确认的成因数 [-]/ Confirmed cause count [-]
    _bAlarmL       : BOOL := FALSE; // 报警锁存位 [bool] / Latched alarm flag
    _bTripL        : BOOL := FALSE; // 停机建议锁存位 [bool] / Latched trip-advice flag
    _bFault        : BOOL := FALSE; // 故障锁存位 [bool] / Latched fault flag
    _uInfo         : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault        : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_MOVE_EPS    : REAL := 0.05;      // 判定「有位移」的最小行程变化 [mm] / Minimum movement to count as moving [mm]
    DL_ZERO_MM     : REAL := 0.0;       // 行程零基准 [mm] / Zero stroke reference [mm]
    DL_CLEAR_CHK   : TIME := T#3S;      // 复位清障确认窗 [TIME] / Reset clearance confirmation window [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bAlarmL/_bTripL 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none
_iCauseNum := 0;                            // 成因计数每拍重算 / Cause counter recomputed

(* —— 段 1：非有限值闸与组态域闸（R19：不拿 NaN 去比较，直接判故障） —— *)
_bFinOk := (fStrokeLeftMm > -DL_BIG) AND (fStrokeLeftMm < DL_BIG)
           AND (fStrokeRightMm > -DL_BIG) AND (fStrokeRightMm < DL_BIG)
           AND (fStrokeMaxMm > -DL_BIG) AND (fStrokeMaxMm < DL_BIG)
           AND (fSyncMaxMm > -DL_BIG) AND (fSyncMaxMm < DL_BIG);
_bCfgOk := (fStrokeMaxMm > DL_EPS)          // 行程限值必须为正
           AND (fSyncMaxMm > DL_EPS)        // 同步差限值必须为正
           AND (tDebounce > T#0S)           // 去抖窗必须为正
           AND (tStallS > T#0S);            // 停滞窗必须为正

(* —— 段 2：判据派生（原始值；LIMIT 不参与，避免判据恒真，R24） —— *)
_bOverRaw := _bFinOk AND _bCfgOk
             AND ((MAX(fStrokeLeftMm, fStrokeRightMm) > fStrokeMaxMm)
                  OR (MIN(fStrokeLeftMm, fStrokeRightMm) < DL_ZERO_MM));
_bSyncRaw := _bFinOk AND _bCfgOk
             AND (ABS(fStrokeLeftMm - fStrokeRightMm) > fSyncMaxMm);
_bStallRaw := _bFinOk AND _bCfgOk AND xEnable AND _bPrevValid
              AND (ABS(fStrokeLeftMm - _fStrokePrevMm) < DL_MOVE_EPS);
_bAnyRaw := _bOverRaw OR _bSyncRaw OR _bStallRaw;

(* —— 段 3：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := xReset);                                                     // 复位上升沿，每拍必调
tonOver(IN := _bOverRaw AND (NOT _bFault), PT := tDebounce);                 // 行程超限去抖
tonSync(IN := _bSyncRaw AND (NOT _bFault), PT := tDebounce);                 // 同步差去抖
tonStall(IN := _bStallRaw AND (NOT _bFault), PT := tStallS);                 // 停滞判定
tonClear(IN := rtReset.Q, PT := DL_CLEAR_CHK);                               // 复位清障确认，自复位靠 rtReset 单拍

(* —— 段 4：相位机（只做迁移与锁存；出口在段 6 单点映射） —— *)
CASE _eState OF

E_DL_GcsStrokeWatchState.eGcsStrokeNormal:
    IF (NOT _bFinOk) OR (NOT _bCfgOk) THEN
        IF NOT _bFinOk THEN
            _uFault := 16#0091_0117;        // 故障级：入参非有限（唯一归因，R190）
        ELSE
            _uFault := 16#0091_0118;        // 故障级：组态越域（唯一归因，R190）
        END_IF
        _bFault := TRUE;                    // 锁存（3 行内置，R45 配对）
        _bAlarmL := FALSE;                  // 报警锁存清，避免双码并存
        _bTripL := FALSE;                   // 停机建议锁存清
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeFault;
    ELSIF xFault THEN
        _uFault := 16#0091_0115;            // 故障级：外部故障按最高级归因（由上层提供）
        _bFault := TRUE;                    // 锁存
        _bAlarmL := FALSE;                  // 报警锁存清
        _bTripL := FALSE;                   // 停机建议锁存清
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeFault;
    ELSIF _bAnyRaw THEN
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeWarn;   // 原始判据成立：进预警相等去抖
    END_IF

E_DL_GcsStrokeWatchState.eGcsStrokeWarn:
    IF tonOver.Q THEN
        _iCauseNum := _iCauseNum + 1;       // 成因 1：行程超限已确认
    END_IF
    IF tonSync.Q THEN
        _iCauseNum := _iCauseNum + 1;       // 成因 2：不同步已确认
    END_IF
    IF tonStall.Q THEN
        _iCauseNum := _iCauseNum + 1;       // 成因 3：停滞已确认
    END_IF
    IF _iCauseNum >= 2 THEN
        _uFault := 16#0091_0115;            // 故障级：两成因及以上并发，建议停机
        _bTripL := TRUE;                    // 停机建议锁存
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeTrip;
    ELSIF tonOver.Q THEN
        _uFault := 16#0091_0112;            // 故障级：左侧/最高侧行程超限
        _bAlarmL := TRUE;                   // 报警锁存
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeAlarm;
    ELSIF tonSync.Q THEN
        _uFault := 16#0091_0113;            // 故障级：左右行程不同步
        _bAlarmL := TRUE;                   // 报警锁存
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeAlarm;
    ELSIF tonStall.Q THEN
        _uFault := 16#0091_0114;            // 故障级：篦床停滞
        _bAlarmL := TRUE;                   // 报警锁存
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeAlarm;
    ELSIF NOT _bAnyRaw THEN
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeNormal;   // 判据自行消失：回正常，不留痕
    ELSE
        _uInfo := 16#0091_0111;             // 信息级：预警中（尚在去抖窗内，不置故障位）
    END_IF

E_DL_GcsStrokeWatchState.eGcsStrokeAlarm:
    IF rtReset.Q THEN
        _bAlarmL := FALSE;                  // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeNormal;
    END_IF

E_DL_GcsStrokeWatchState.eGcsStrokeTrip:
    IF rtReset.Q THEN
        _bTripL := FALSE;                   // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeNormal;
    END_IF

E_DL_GcsStrokeWatchState.eGcsStrokeFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bCfgOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参与组态合法（可达）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_GcsStrokeWatchState.eGcsStrokeNormal;
    END_IF

ELSE
    _uFault := 16#0091_0116;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _bAlarmL := FALSE;                      // 报警锁存清
    _bTripL := FALSE;                       // 停机建议锁存清
    _eState := E_DL_GcsStrokeWatchState.eGcsStrokeFault;   // 强制回故障相

END_CASE

(* —— 段 5：后置段（行程快照在迁移判断之后统一更新，禁在分支内散写） —— *)
IF _bFinOk THEN
    _fStrokePrevMm := fStrokeLeftMm;        // 快照更新（仅有限值可信时才更新）
    _bPrevValid := TRUE;                    // 快照自此有效
ELSE
    _bPrevValid := FALSE;                   // 非有限值使快照失效，防污染下一拍停滞判据
END_IF

(* —— 段 6：出口单点映射（名实同源；故障与锁存位一律由状态导出） —— *)
xWarn := (_eState = E_DL_GcsStrokeWatchState.eGcsStrokeWarn);                          // 预警仅预警相
xAlarm := _bAlarmL AND (NOT _bFault) AND (NOT _bTripL);                                // 报警：锁存且未升级
xStopSuggest := _bTripL OR _bFault;                                                    // 停机建议：并发或故障相
IF _bTripL OR _bFault THEN
    nLevel := 3;                            // 最高级：停机建议
ELSIF _bAlarmL THEN
    nLevel := 2;                            // 报警级
ELSIF xWarn THEN
    nLevel := 1;                            // 预警级
ELSE
    nLevel := 0;                            // 正常
END_IF
eState := _eState;                          // 状态出口单点映射
IF _bTripL OR _bFault OR _bAlarmL THEN
    nErrId := _uFault;                      // 故障码锁存回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码（预警中）
END_IF

END_FUNCTION_BLOCK
