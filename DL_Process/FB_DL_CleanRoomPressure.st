(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CleanRoomPressure
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 MAX / MIN，零厂商方言、零定时器依赖
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 洁净室压差梯级控制公开工艺语义（行业池），道莅
 *                         clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 多房间正压梯级控制防倒流件。梯度校验先于控制：
 *                         逐室核对设定梯度沿洁净度递减方向严格递减，
 *                         倒置即锁存倒置标志并冻结投切（防倒流最高优先）；
 *                         控制层各室独立带回差双限：低于下限请求加大风量、
 *                         高于上限撤回请求、带内保持。
 * 码位     (Codes)      : 16#0005_00A3 信息级：压差/设定非有限该室退出仲裁、
 *                                      房间计数钳位（不置 bError）
 *                         16#0005_00A4 故障级：梯度倒置（锁存，独立复位通道）
 *                         16#0005_00A5~00A7 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 梯度倒置锁存有可达解除式：独立 bRstInv 复位沿，
 *                           复位通道不受 NOT bEn 屏蔽（终审两式之一）；
 *                         2 房间计数钳上限、越界逐位清零；
 *                         3 非有限压差该室退出仲裁保持原投切并计掩码；
 *                         4 首拍全 FALSE；
 *                         5 无定时器/边沿实例（纯组合投切层）。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 13）
 *==============================================================================*)

(*==============================================================================
 * 功能块: FB_DL_CleanRoomPressure
 * 调用约定: 每个扫描周期无条件调用一次；压差与梯度设定经引脚数组注入，
 *           数组维度 1..8（8 室上限），有效室数经 uRoomCnt 给出。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_CleanRoomPressure
VAR_INPUT
    afDp    : ARRAY[1..8] OF REAL;    // 各室实测压差 [帕] / Per-room measured differential pressure [Pa]
    afSet   : ARRAY[1..8] OF REAL;    // 各室压差梯度设定 [帕]，须严格递减 / Per-room gradient setpoints [Pa], strictly decreasing
    uRoomCnt: UINT := 8;              // 有效房间数 [间]，合法域 1..8 / Valid room count, valid 1..8
    fBand   : REAL := 5.0;            // 回差半带宽 [帕] / Hysteresis half band [Pa]
    bEn     : BOOL := FALSE;          // 使能 / Enable flag
    bRstInv : BOOL := FALSE;          // 梯度倒置独立复位沿（不受使能屏蔽）/ Inversion reset edge, never masked by enable
END_VAR
VAR_OUTPUT
    abBoost : ARRAY[1..8] OF BOOL;    // 各室加大风量请求 / Per-room boost request
    bInvert : BOOL;                   // 梯度倒置锁存标志 / Gradient inversion latch flag
    uErrorId: UDINT;                  // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigRst: R_TRIG;                 // 倒置复位沿检测，每拍无条件刷新 / Inversion reset edge detector
    uCntEff : INT;                    // 钳位后有效室数 [间]，INT 域循环 / Effective clamped room count, INT domain
    i       : INT;                    // 逐室循环索引 / Per-room loop index
    bRoomOk : ARRAY[1..8] OF BOOL;    // 各室数据有效掩码 / Per-room data validity mask
    bBadAny : BOOL;                   // 任一室数据无效 / Any room data invalid
    bFirst  : BOOL := TRUE;           // 首拍标志 / First-scan flag
    fLo     : REAL;                   // 本室投切下限 [帕] / Room switching lower bound [Pa]
    fHi     : REAL;                   // 本室投切上限 [帕] / Room switching upper bound [Pa]
END_VAR
VAR CONSTANT
    DL_CRP_ROOM_MAX: INT  := 8;       // 房间数上限 [间] / Room count upper bound
    DL_CRP_FIN     : REAL := 1.0E30;  // REAL 有限幅值判界 / REAL finiteness magnitude bound
END_VAR

// ---- 段 1｜边沿实例无条件刷新（红线：禁入条件分支）----------------------------
rTrigRst(CLK := bRstInv);                             // 倒置复位沿检测 / Inversion reset edge detection

// ---- 段 2｜梯度倒置独立复位：先于一切使能门控（R38 复位通道不屏蔽）--------------
IF rTrigRst.Q THEN
    bInvert := FALSE;                                 // 复位清倒置锁存 / Reset clears inversion latch
END_IF

// ---- 段 3｜计数钳位与首拍初始化 --------------------------------------------------
uCntEff := MIN(UINT_TO_INT(uRoomCnt), DL_CRP_ROOM_MAX); // 计数钳上限，统一 INT 域 / Clamp count, unified INT domain
uCntEff := MAX(uCntEff, 1);                           // 下限保 1 防 0 循环 / Floor at 1 against empty loop
IF bFirst THEN
    FOR i := 1 TO DL_CRP_ROOM_MAX DO
        abBoost[i] := FALSE;                          // 首拍全 FALSE / First scan all FALSE
        bRoomOk[i] := TRUE;                           // 掩码预置有效 / Mask preset valid
    END_FOR
    bFirst := FALSE;                                  // 清首拍标志 / Clear first-scan flag
END_IF

// ---- 段 4｜梯度校验先于控制（防倒流最高优先）--------------------------------------
IF NOT bInvert THEN
    FOR i := 1 TO (uCntEff - 1) DO
        IF (afSet[i] <> afSet[i]) OR (afSet[i + 1] <> afSet[i + 1])
           OR (ABS(afSet[i]) >= DL_CRP_FIN) OR (ABS(afSet[i + 1]) >= DL_CRP_FIN) THEN
            bInvert := TRUE;                          // 非有限设定按倒置保守处理（留档）/ Non-finite set treated as inversion
        ELSIF afSet[i] <= afSet[i + 1] THEN
            bInvert := TRUE;                          // 梯度未严格递减判倒置 / Non-decreasing gradient is inversion
        END_IF
    END_FOR
END_IF

// ---- 段 5｜数据有效性掩码（非有限该室退出仲裁）------------------------------------
bBadAny := FALSE;                                     // 掩码标志先清 / Clear mask flag
FOR i := 1 TO DL_CRP_ROOM_MAX DO
    IF i <= uCntEff THEN
        bRoomOk[i] := (afDp[i] = afDp[i]) AND (ABS(afDp[i]) < DL_CRP_FIN); // 本室压差有限 / Room pressure finite
        bRoomOk[i] := bRoomOk[i] AND (fBand >= 0.0) AND (fBand < DL_CRP_FIN); // 带宽合法性并入 / Band legality merged
    ELSE
        bRoomOk[i] := FALSE;                          // 越界室退出并视为无效 / Out-of-range room excluded
        abBoost[i] := FALSE;                          // 越界逐位清零（R29 输出确定值）/ Out-of-range bits cleared
    END_IF
    IF (NOT bRoomOk[i]) AND (i <= uCntEff) THEN
        bBadAny := TRUE;                              // 有效域内存在无效室 / Invalid room inside valid range
    END_IF
END_FOR

// ---- 段 6｜控制层：各室独立带回差双限（倒置锁存期冻结投切保持原值）----------------
IF (NOT bInvert) AND bEn THEN
    FOR i := 1 TO uCntEff DO
        fLo := afSet[i] - fBand;                      // 本室下限 / Room lower bound
        fHi := afSet[i] + fBand;                      // 本室上限 / Room upper bound
        IF NOT bRoomOk[i] THEN
            abBoost[i] := abBoost[i];                 // 无效室退出仲裁保持原值 / Invalid room holds state
        ELSIF afDp[i] < fLo THEN
            abBoost[i] := TRUE;                       // 低于下限请求加大风量 / Below lower bound, boost on
        ELSIF afDp[i] > fHi THEN
            abBoost[i] := FALSE;                      // 高于上限撤回请求 / Above upper bound, boost off
        ELSE
            abBoost[i] := abBoost[i];                 // 带内保持（回差防抖）/ In band, hold
        END_IF
    END_FOR
END_IF

// ---- 段 7｜错误码装配：倒置锁存故障级优先，信息级居次 ------------------------------
IF bInvert THEN
    uErrorId := 16#0005_00A4;                         // 故障级：梯度倒置锁存 / Fault: inversion latched
ELSIF bBadAny OR (UINT_TO_INT(uRoomCnt) > DL_CRP_ROOM_MAX) THEN
    uErrorId := 16#0005_00A3;                         // 信息级：非有限/计数钳位 / Info: non-finite or count clamp
ELSE
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF
END_FUNCTION_BLOCK
