(*==============================================================================
 * 组件名称 (Component)  : FB_DL_NightPurgeCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON 与库内 FC_DL_VaporPressureSat，
 *                         零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 夜间通风/免费冷却公开控制语义（T1-2 ROOM_CONTROL
 *                         族待挖子项），道莅 clean-room 防御性实现，
 *                         未复制任何外部源码行
 * 功能描述 (Function)   : 夜间吹扫顺控件（降温除湿侧方向写死，不出加热吹扫
 *                         变体）。三判据同时成立进入：无人员占用 + 室外比
 *                         室内凉（带死区）+ 室外绝对湿度不高于室内。窗时到
 *                         或判据失效退出；退出后经冷却时长抑制防频启。
 *                         Magnus-Tetens 饱和压常数唯一属主为库内
 *                         FC_DL_VaporPressureSat，本件只调用不内联公式。
 * 码位     (Codes)      : 16#0005_0094 信息级：温湿度非有限保持现状、
 *                         冷却期吹扫请求被拒、相对湿度越域已钳位（不置 bError）
 *                         16#0005_0095~0098 故障级保留未启用（本轮无故障级条件，
 *                         码表与实现对齐，不虚声明）
 * 边界防错 (Boundary)   : 1 温湿度非有限（x<>x 自反判加幅值界）保持现状+信息码；
 *                         2 相对湿度先钳 0..100 再参与换算；
 *                         3 TON 每拍无条件刷新，条件经入参传递；
 *                         4 CASE 带 ELSE 锁安全侧（不吹扫）；
 *                         5 饱和压调用失败按数据无效保持现状。
 * 规格偏离 (Deviation)   : 1 规格时戳类型 DTL 为平台扩展，改用 IEC 标准
 *                         DATE_AND_TIME（跨平台红线裁定），本轮判据不消费该
 *                         引脚，仅作观测时戳保留契约；
 *                         2 规格枚举名 E_DL_PurgeState 属主为库内
 *                         FB_DL_InertPurgeSeq（氮气置换语义），跨域语义不
 *                         复用，改立本文件私有枚举 E_DL_NightPurgeState。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 4）
 *                         2026-11-23 v1.0.1 R73 补 bValid 回执：段 3 两处饱和压
 *                         调用补收 bValid 局部回执，回执无效并入既有 bSat*Ok
 *                         拒绝语义（数据无效合取路径），契约不变
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_NightPurgeState（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 夜间吹扫（降温除湿侧）顺控状态，成员与 CASE 标签双向完备。
 *----------------------------------------------------------------------------*)
TYPE E_DL_NightPurgeState :
(
    eIdle     := 0,    // 待机：判据未齐或未使能 / Idle, criteria not met or disabled
    ePurging  := 10,   // 吹扫中：请求输出置位 / Purging, request output active
    eCooldown := 20,   // 冷却抑制：退出后重启抑制 / Cooldown, restart suppression after exit
    eFault    := 99    // 故障兜底：非法状态拦截 / Fault fallback, illegal state catch
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_NightPurgeCtrl
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_NightPurgeCtrl
VAR_INPUT
    bEn       : BOOL := FALSE;        // 使能 / Enable flag
    dtNow     : DT   := DT#1970-01-01-00:00:00; // 观测时戳（保留契约，本轮不消费）/ Observation timestamp, reserved
    fTOut     : REAL := 25.0;         // 室外温度 [摄氏度] / Outdoor temperature [degC]
    fTIn      : REAL := 25.0;         // 室内温度 [摄氏度] / Indoor temperature [degC]
    fRhOut    : REAL := 50.0;         // 室外相对湿度 [百分数] / Outdoor relative humidity [%]
    fRhIn     : REAL := 50.0;         // 室内相对湿度 [百分数] / Indoor relative humidity [%]
    fTDead    : REAL := 1.0;          // 温差判据死区 [摄氏度] / Temperature deadband [degC]
    tPurgeWin : TIME := T#60M;        // 吹扫窗口时长 [ms] / Purge window duration [ms]
    tCooldown : TIME := T#30M;        // 冷却抑制时长 [ms] / Cooldown suppression duration [ms]
    bOcc      : BOOL := FALSE;        // 人员占用信号 / Occupancy signal
END_VAR
VAR_OUTPUT
    bPurgeReq : BOOL;                 // 吹扫请求输出 / Purge request output
    eState    : E_DL_NightPurgeState; // 顺控当前状态 / Current sequence state
    uErrorId  : UDINT;                // 信息级码，0 = 无信息 / Info code, 0 = none
END_VAR
VAR
    tonWin    : TON;                  // 吹扫窗定时器，每拍无条件刷新 / Purge window timer, refreshed every scan
    tonCool   : TON;                  // 冷却抑制定时器，每拍无条件刷新 / Cooldown timer, refreshed every scan
    bCritOcc  : BOOL;                 // 判据一：无占用 / Criterion one: unoccupied
    bCritTemp : BOOL;                 // 判据二：室外比室内凉 / Criterion two: outdoor cooler
    bCritHum  : BOOL;                 // 判据三：室外绝对湿度不高于室内 / Criterion three: outdoor humidity not higher
    bCritOk   : BOOL;                 // 三判据合取 / All three criteria AND
    bDataOk   : BOOL;                 // 温湿度输入有效性 / Input data validity
    fRhOutC   : REAL;                 // 钳位后室外湿度 [百分数] / Clamped outdoor humidity [%]
    fRhInC    : REAL;                 // 钳位后室内湿度 [百分数] / Clamped indoor humidity [%]
    fPwsOut   : LREAL;                // 室外饱和水汽压 [帕] / Outdoor saturation vapour pressure [Pa]
    fPwsIn    : LREAL;                // 室内饱和水汽压 [帕] / Indoor saturation vapour pressure [Pa]
    fAhOut    : REAL;                 // 室外绝对湿度 [克每立方米] / Outdoor absolute humidity [g per m3]
    fAhIn     : REAL;                 // 室内绝对湿度 [克每立方米] / Indoor absolute humidity [g per m3]
    bSatOutOk : BOOL;                 // 室外饱和压调用有效 / Outdoor saturation call valid
    bSatInOk  : BOOL;                 // 室内饱和压调用有效 / Indoor saturation call valid
    bRhClamp  : BOOL;                 // 湿度越域钳位标志 / Humidity clamp flag
    _bPwsValid: BOOL;                 // 饱和压属主件输出可用回执 / Saturation owner FC outputs-usable receipt
    _bPwsClamped : BOOL;    // 属主件钳位回执（本件不消费，仅契约全回执） / Owner clamp receipt (unused, full-receipt contract)
    _nPwsErr     : UDINT;   // 属主件错误码回执 / Owner error-code receipt
    _bPwsError   : BOOL;    // 属主件故障级回执 / Owner fault-flag receipt
END_VAR
VAR CONSTANT
    DL_NPC_FIN   : REAL  := 1.0E30;   // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_NPC_AH_K  : REAL  := 2.1674;   // 绝对湿度换算系数 [克·帕每开尔文每立方米] / Absolute humidity factor [g Pa per K per m3]
    DL_NPC_T0    : REAL  := 273.15;   // 绝对温标偏移 [开尔文] / Absolute temperature offset [K]
    DL_NPC_RHMAX : REAL  := 100.0;    // 相对湿度域上限 [百分数] / Relative humidity upper bound [%]
END_VAR

// ---- 段 1｜定时器无条件刷新（红线：禁入条件分支）------------------------------
tonWin(IN := (eState = ePurging), PT := tPurgeWin);   // 吹扫窗计时按态断输入 / Window timer input per state
tonCool(IN := (eState = eCooldown), PT := tCooldown); // 冷却计时按态断输入 / Cooldown timer input per state

// ---- 段 2｜输入有效性与湿度钳位 ------------------------------------------------
bDataOk := (fTOut = fTOut) AND (fTIn = fTIn)
       AND (ABS(fTOut) < DL_NPC_FIN) AND (ABS(fTIn) < DL_NPC_FIN)
       AND (fRhOut = fRhOut) AND (fRhIn = fRhIn)
       AND (ABS(fRhOut) < DL_NPC_FIN) AND (ABS(fRhIn) < DL_NPC_FIN); // 温湿度四点有限 / Four inputs finite
fRhOutC := MIN(MAX(fRhOut, 0.0), DL_NPC_RHMAX);       // 室外湿度钳 0..100 / Clamp outdoor humidity
fRhInC  := MIN(MAX(fRhIn, 0.0), DL_NPC_RHMAX);        // 室内湿度钳 0..100 / Clamp indoor humidity
bRhClamp := (fRhOut < 0.0) OR (fRhOut > DL_NPC_RHMAX)
         OR (fRhIn < 0.0) OR (fRhIn > DL_NPC_RHMAX);  // 越域判定 / Out-of-range detection

// ---- 段 3｜饱和压查询：常数唯一属主 FC_DL_VaporPressureSat，只调用不内联 --------
bSatOutOk := FC_DL_VaporPressureSat(fTempC := REAL_TO_LREAL(fTOut),
               fPvSat => fPwsOut, bValid => _bPwsValid, bClamped => _bPwsClamped, eErr => _nPwsErr, bError => _bPwsError); // 室外饱和压查询 / Query outdoor saturation pressure
bSatOutOk := bSatOutOk AND _bPwsValid;                 // 输出可用回执并入既有拒绝语义 / Merge outputs-usable receipt into existing reject semantics
bSatInOk := FC_DL_VaporPressureSat(fTempC := REAL_TO_LREAL(fTIn),
               fPvSat => fPwsIn, bValid => _bPwsValid, bClamped => _bPwsClamped, eErr => _nPwsErr, bError => _bPwsError); // 室内饱和压查询 / Query indoor saturation pressure
bSatInOk := bSatInOk AND _bPwsValid;                   // 输出可用回执并入既有拒绝语义 / Merge outputs-usable receipt into existing reject semantics

// ---- 段 4｜绝对湿度换算：AH = 2.1674·pv/(273.15+T) [克每立方米] -----------------
IF bDataOk AND bSatOutOk AND bSatInOk AND ((fTOut + DL_NPC_T0) > 0.0) AND ((fTIn + DL_NPC_T0) > 0.0) THEN
    fAhOut := DL_NPC_AH_K * REAL_TO_LREAL(fRhOutC) / 100.0 * fPwsOut
            / (REAL_TO_LREAL(fTOut) + DL_NPC_T0);      // 室外绝对湿度 / Outdoor absolute humidity
    fAhIn  := DL_NPC_AH_K * REAL_TO_LREAL(fRhInC) / 100.0 * fPwsIn
            / (REAL_TO_LREAL(fTIn) + DL_NPC_T0);       // 室内绝对湿度 / Indoor absolute humidity
    bCritHum := fAhOut <= fAhIn;                       // 判据三：室外不高（降温除湿侧）/ Outdoor not higher
ELSE
    fAhOut  := 0.0;                                    // 异常路径确定值 / Deterministic fallback value
    fAhIn   := 0.0;                                    // 异常路径确定值 / Deterministic fallback value
    bCritHum := FALSE;                                 // 数据无效判据不成立 / Invalid data fails criterion
END_IF

// ---- 段 5｜判据装配 ------------------------------------------------------------
bCritOcc  := NOT bOcc;                                // 判据一：无占用 / Unoccupied
bCritTemp := (fTOut + fTDead) < fTIn;                 // 判据二：室外加死区仍低于室内 / Outdoor plus deadband still cooler
bCritOk   := bCritOcc AND bCritTemp AND bCritHum AND bDataOk
          AND bSatOutOk AND bSatInOk;                 // 合取含数据有效性 / AND with data validity

// ---- 段 6｜状态机（CASE 带 ELSE 锁安全侧不吹扫）--------------------------------
CASE eState OF
    eIdle:
        bPurgeReq := FALSE;                            // 待机不吹扫 / No purge in idle
        IF bEn AND bCritOk THEN
            eState := ePurging;                        // 三判据齐进入吹扫 / Criteria met, start purge
        END_IF
    ePurging:
        bPurgeReq := bEn;                              // 吹扫请求随使能 / Purge follows enable
        IF (NOT bEn) OR (NOT bCritOk) OR tonWin.Q THEN
            eState := eCooldown;                       // 判据失效或窗时到退入冷却 / Exit to cooldown
        END_IF
    eCooldown:
        bPurgeReq := FALSE;                            // 冷却期不吹扫 / No purge in cooldown
        IF bCritOk THEN
            uErrorId := 16#0005_0094;                  // 信息级：冷却期请求被拒 / Info: request rejected in cooldown
        END_IF
        IF tonCool.Q THEN
            eState := eIdle;                           // 冷却满回待机 / Cooldown elapsed, back to idle
        END_IF
    eFault:
        bPurgeReq := FALSE;                            // 故障态安全侧不吹扫 / Fault keeps purge off
        IF NOT bEn THEN
            eState := eIdle;                           // 撤使能自愈回待机 / Self-heal on disable
        END_IF
    ELSE
        eState := eFault;                              // 非法状态兜底 / Illegal state fallback
END_CASE

// ---- 段 7｜信息码装配（数据无效/钳位/冷却期拒绝共用信息级槽）--------------------
IF (NOT bDataOk) OR (NOT bSatOutOk) OR (NOT bSatInOk) THEN
    uErrorId := 16#0005_0094;                          // 信息级：非有限或查询无效保持现状 / Info: non-finite or invalid call, hold
ELSIF bRhClamp THEN
    uErrorId := 16#0005_0094;                          // 信息级：湿度越域已钳位 / Info: humidity clamped
END_IF
END_FUNCTION_BLOCK
