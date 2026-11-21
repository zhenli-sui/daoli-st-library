//==============================================================================
// 功能块：FB_DL_StackingAlignCtrl ｜ 中文名称：叠片对位纠偏控制
// 所属子库：DL_Motion ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：叠片机 CCD 对位纠偏量的解算件。输入像素偏差与角度偏差，经「像素→机械」
//           标定矩阵的逆映射得机械纠偏量（mm / mrad），输出双轴纠偏指令、超差 NG 与
//           行程限幅标志。标定矩阵求逆委托 FC_DL_Affine2DInvert（组合调用，不复制
//           低层实现）；矩阵奇异时沿用上次有效逆矩阵并置 bMatrixFallback，无历史有效
//           值时判故障。本件只解算纠偏量，不定义轴状态、不发运动指令——轴状态与运动
//           指令的唯一属主是运动层（T1-6 纪律），本件仅输出「允许上层下发纠偏」的
//           bReady 许可位。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：像素偏差[像素] / 纠偏量[mm] / 角度偏差与角度纠偏量[mrad] / 标定矩阵线性块
//         [mm 每像素] / 标定矩阵平移列[mm] / 行程门限[mm] / 超差门限[mm 或 mrad] /
//         行列式[无量纲]
// 错误码表：16#0004_01EB 信息级（纠偏量被行程限幅，bClamped 置位，限幅后值不得当作
//           正常纠偏量计数，须 HMI 可辨，不置 bError）/ 16#0004_01EC 信息级（标定矩阵
//           退化不可逆，沿用上次有效逆矩阵，bMatrixFallback 置位，不置 bError）/
//           16#0004_030C 故障级（标定矩阵非法/不可逆且无历史有效值，置 bError，纠偏量
//           回零）/ 16#0004_030D 故障级（输入非有限或纠偏解算溢出，置 bError，纠偏量
//           回零）/ 16#0004_030E 故障级兜底（状态机落 ELSE 非法状态，置 bError，纠偏量
//           回零）。码位 16#0004 段，信息带 01xx、故障带 03xx，不越段不挪用预留槽。
// 状态机：E_DL_StackAlignState（eIdle=0 失能/待机 / eAlign=10 正常纠偏解算 /
//           eLimited=20 行程限幅生效 / eCamLost=30 相机无效不纠偏 / eFault=99 故障
//           兜底），CASE 含 ELSE 兜底，ELSE 置 030E 且纠偏量回零 bValid := FALSE。
// 边界行为：① 标定矩阵经 FC_DL_Affine2DInvert 求逆（每拍无条件调用恰好一次）；奇异
//           时若有历史有效逆矩阵 → 信息 01EC + bMatrixFallback := TRUE + 沿用上次值，
//           若无历史有效值 → 故障 030C；② 纠偏量限幅到行程 → bClamped := TRUE +
//           信息 01EB；③ 超差判据取「限幅前」原始纠偏量与角度偏差（限幅会把超差量压成
//           行程端点，用限幅后值判超差会漏判），命中即 bNg := TRUE 并锁存至 bReset；
//           ④ bCamValid := FALSE → 纠偏量回零、bReady := FALSE、bClamped := FALSE、
//           不改 bNg（不做判定即不改判定结果），状态进 eCamLost；⑤ 非有限（NaN 自反判
//           + Inf 幅值上限判，R79）→ 故障 030D 且纠偏量回零；⑥ 失能 → 纠偏量回零 +
//           bReady := FALSE（R72 许可类输出显式 FALSE）；⑦ 行程域倒置（下限 ≥ 上限）
//           按零行程处理，归入 01EB 限幅语义并撤 bReady，不新占码位。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.11，依赖 §4.1 件 FC_DL_Affine2DInvert 语义）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_StackAlignState（归属 DL_Motion，与 FB_DL_StackingAlignCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StackAlignState :
(
    eIdle    := 0,   // 失能/待机：纠偏量回零，bReady 撤销 / Disabled, corrections zeroed, bReady dropped
    eAlign   := 10,  // 正常解算：纠偏量在行程内，允许上层下发 / Normal solve, corrections within travel
    eLimited := 20,  // 行程限幅生效：纠偏量被夹到行程端点 / Travel clamp active, corrections clipped
    eCamLost := 30,  // 相机无效：不纠偏、不改超差判定 / Camera invalid, no correction, NG untouched
    eFault   := 99   // 故障兜底：矩阵非法/非有限/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_StackingAlignCtrl
 * 调用约定: 每个扫描周期无条件调用一次；像素偏差与角度偏差由上层刷新。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_StackingAlignCtrl
VAR_INPUT
    fOffsetXPx      : LREAL;                       // 像素偏差 X [像素]，正 = 偏右 / Pixel offset X [px], positive = right
    fOffsetYPx      : LREAL;                       // 像素偏差 Y [像素]，正 = 偏下 / Pixel offset Y [px], positive = down
    fAngleMrad      : LREAL;                       // 角度偏差 [mrad]，正 = 逆时针 / Angular offset [mrad], positive = counter-clockwise
    afPixelToMachine : ARRAY[0..2, 0..2] OF LREAL; // 像素→机械标定矩阵 [mm 每像素]，行主序 / Pixel-to-machine calibration matrix [mm per px], row-major
    fAxisXMinMm     : LREAL;                       // 纠偏轴 X 行程下限 [mm] / Correction axis X travel floor [mm]
    fAxisXMaxMm     : LREAL;                       // 纠偏轴 X 行程上限 [mm] / Correction axis X travel ceiling [mm]
    fAxisYMinMm     : LREAL;                       // 纠偏轴 Y 行程下限 [mm] / Correction axis Y travel floor [mm]
    fAxisYMaxMm     : LREAL;                       // 纠偏轴 Y 行程上限 [mm] / Correction axis Y travel ceiling [mm]
    fNgTolMm        : LREAL := 0.05;               // 位置超差门限 [mm] / Position NG tolerance [mm]
    fNgTolMrad      : LREAL := 2.0;                // 角度超差门限 [mrad] / Angular NG tolerance [mrad]
    bCamValid       : BOOL;                        // 相机结果有效（取像成功且特征识别置信） / Camera result valid
    bAxisInPos      : BOOL;                        // 纠偏轴在定位完成状态（上层反馈） / Correction axis in position
    bEnable         : BOOL;                        // 总使能 / Master enable
    bReset          : BOOL;                        // 复位，上升沿清超差锁存与故障 / Reset, rising edge clears NG latch and fault
END_VAR
VAR_OUTPUT
    fCorrXMm        : LREAL;                       // 纠偏量 X [mm]，已按行程限幅 / Correction X [mm], travel-clamped
    fCorrYMm        : LREAL;                       // 纠偏量 Y [mm]，已按行程限幅 / Correction Y [mm], travel-clamped
    fCorrAngleMrad  : LREAL;                       // 角度纠偏量 [mrad] / Angular correction [mrad]
    bNg             : BOOL;                        // 超差判定，锁存至 bReset / Out-of-tolerance latch, cleared by reset
    bClamped        : BOOL;                        // 行程限幅生效标志 / Travel clamp active flag
    bReady          : BOOL;                        // 允许上层下发纠偏（相机有效且在位且在行程内） / Correction may be issued by the upper layer
    bMatrixFallback : BOOL;                        // 沿用上次有效逆矩阵标志 / Reusing the last valid inverse matrix
    eErr            : UDINT;                       // 错误码，0 = 无错，码位 16#0004_01EB 起信息级、16#0004_030C 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError          : BOOL;                        // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                        // 纠偏量可用标志，失能/故障闸显式 FALSE / Correction usable flag, explicit FALSE on disable/fault gates
    eState          : E_DL_StackAlignState;        // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset         : R_TRIG;                      // 复位上升沿检测实例 / Reset rising edge detector
    afMInvNew       : ARRAY[0..2, 0..2] OF LREAL;  // 本拍求得的逆矩阵 [mm 每像素] / Inverse matrix of this scan
    afMInvLast      : ARRAY[0..2, 0..2] OF LREAL;  // 上次有效逆矩阵（退化时沿用）[mm 每像素] / Last valid inverse matrix
    afMInvEff       : ARRAY[0..2, 0..2] OF LREAL;  // 本拍生效逆矩阵（新值或沿用值）[mm 每像素] / Effective inverse matrix of this scan
    nI              : INT;                         // 行循环索引 [—] / Row loop index
    nJ              : INT;                         // 列循环索引 [—] / Column loop index
    uInvErr         : UDINT;                       // 求逆件错误码暂存 / Inverse-function error code staging
    fDetNew         : LREAL;                       // 本拍线性块行列式 [无量纲] / Linear block determinant of this scan
    bInvFault       : BOOL;                        // 求逆件故障标志暂存 / Inverse-function fault flag staging
    bInvValid       : BOOL;                        // 求逆件结果可用暂存 / Inverse-function usable flag staging
    bInvOk          : BOOL;                        // 求逆件返回值暂存（与可用标志同口径） / Inverse-function return staging
    bHasValidInv    : BOOL;                        // 已存在历史有效逆矩阵 / A valid inverse matrix has been stored
    fRawXMm         : LREAL;                       // 限幅前纠偏量 X [mm] / Unclamped correction X [mm]
    fRawYMm         : LREAL;                       // 限幅前纠偏量 Y [mm] / Unclamped correction Y [mm]
    fLimX           : LREAL;                       // 生效 X 行程上限（倒置时夹零）[mm] / Effective X travel ceiling [mm]
    fLimY           : LREAL;                       // 生效 Y 行程上限（倒置时夹零）[mm] / Effective Y travel ceiling [mm]
    bTravelXBad     : BOOL;                        // X 行程域倒置标志 / X travel range inverted flag
    bTravelYBad     : BOOL;                        // Y 行程域倒置标志 / Y travel range inverted flag
    bNonFin         : BOOL;                        // 非有限判定中间标志 / Non-finite detection intermediate flag
    bFirstScan      : BOOL := TRUE;                // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_SAC_CODE_INFO_1 : UDINT := 16#0004_01EB;    // 信息级槽 1（纠偏量被行程限幅） / info slot 1
    DL_SAC_CODE_INFO_2 : UDINT := 16#0004_01EC;    // 信息级槽 2（标定矩阵退化沿用上次） / info slot 2
    DL_SAC_CODE_FLT_1  : UDINT := 16#0004_030C;    // 故障级槽 1（矩阵非法且无历史有效值） / fault slot 1
    DL_SAC_CODE_FLT_2  : UDINT := 16#0004_030D;    // 故障级槽 2（输入非有限/解算溢出） / fault slot 2
    DL_SAC_CODE_FLT_3  : UDINT := 16#0004_030E;    // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_SAC_DET_EPS     : LREAL := 1.0E-9;          // 逆矩阵相对奇异判据 [无量纲] / Relative singularity threshold of the inverse
    DL_SAC_ZERO        : LREAL := 0.0;             // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_SAC_TOL         : LREAL := 1.0E-6;          // 浮点比较容差 [—] / Float comparison tolerance
    DL_SAC_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿检测在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）：清超差锁存与故障码；
 *       历史有效逆矩阵属标定事实，不随复位清除（头注释边界行为①）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    bNg     := FALSE;                              // 超差锁存清除 / NG latch cleared
    bError  := FALSE;                              // 故障标志清除 / fault flag cleared
    eErr    := 16#0000_0000;                       // 错误码清除 / error code cleared
    eState  := E_DL_StackAlignState.eIdle;         // 回待机 / back to idle
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（标量、行程、门限逐个：NaN 自反判 + Inf 幅值上限判）
 *       命中即纠偏量回零 + 撤许可，安全侧不留上次值（红线 6）
 *----------------------------------------------------------------------------*)
bNonFin := (fOffsetXPx <> fOffsetXPx) OR (ABS(fOffsetXPx) >= DL_SAC_INF)
        OR (fOffsetYPx <> fOffsetYPx) OR (ABS(fOffsetYPx) >= DL_SAC_INF)
        OR (fAngleMrad <> fAngleMrad) OR (ABS(fAngleMrad) >= DL_SAC_INF)
        OR (fAxisXMinMm <> fAxisXMinMm) OR (ABS(fAxisXMinMm) >= DL_SAC_INF)
        OR (fAxisXMaxMm <> fAxisXMaxMm) OR (ABS(fAxisXMaxMm) >= DL_SAC_INF)
        OR (fAxisYMinMm <> fAxisYMinMm) OR (ABS(fAxisYMinMm) >= DL_SAC_INF)
        OR (fAxisYMaxMm <> fAxisYMaxMm) OR (ABS(fAxisYMaxMm) >= DL_SAC_INF)
        OR (fNgTolMm <> fNgTolMm) OR (ABS(fNgTolMm) >= DL_SAC_INF)
        OR (fNgTolMrad <> fNgTolMrad) OR (ABS(fNgTolMrad) >= DL_SAC_INF); // 引脚非有限汇总判定 / aggregated non-finite check
IF bNonFin THEN
    eState := E_DL_StackAlignState.eFault;          // 进故障相 / enter fault state
    eErr   := DL_SAC_CODE_FLT_2;                    // 故障级：输入非有限 / fault: non-finite input
    bError := TRUE;                                 // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                                // 输出不可用 / outputs unusable
    fCorrXMm := DL_SAC_ZERO;                        // 纠偏量回零安全侧 / correction zeroed, safe side
    fCorrYMm := DL_SAC_ZERO;                        // 纠偏量回零安全侧 / correction zeroed, safe side
    fCorrAngleMrad := DL_SAC_ZERO;                  // 角度纠偏回零安全侧 / angular correction zeroed
    bClamped := FALSE;                              // 限幅标志撤 / clamp flag withdrawn
    bReady := FALSE;                                // 许可撤（R72）/ permission dropped
    bMatrixFallback := FALSE;                       // 降级标志撤 / fallback flag withdrawn
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜标定矩阵求逆：组合调用 FC_DL_Affine2DInvert（每拍无条件调用恰好一次，
 *       禁止复制低层 2x2 伴随求逆实现）；引脚契约以源码头注释为准
 *----------------------------------------------------------------------------*)
bInvOk := FC_DL_Affine2DInvert(afM := afPixelToMachine,   // 待求逆标定矩阵 [mm 每像素] / calibration matrix to invert
                               fDetEps := DL_SAC_DET_EPS, // 相对奇异判据 [无量纲] / relative singularity threshold
                               afMInv => afMInvNew,       // 逆矩阵输出 [mm 每像素] / inverse matrix output
                               fDet => fDetNew,           // 行列式输出 [无量纲] / determinant output
                               eErr => uInvErr,           // 下游错误码暂存 / downstream error code staging
                               bError => bInvFault,       // 下游故障标志暂存 / downstream fault flag staging
                               bValid => bInvValid);      // 下游可用标志暂存 / downstream usable flag staging

(*------------------------------------------------------------------------------
 * 段 5｜逆矩阵不可用降级：有历史有效值 → 信息 01EC 沿用上次；无历史 → 故障 030C。
 *       下游信息级码不升格为故障（§5.5 纪律），仅在逆结果不可用时按本件语义处置
 *----------------------------------------------------------------------------*)
IF (NOT bInvValid) OR (NOT bInvOk) THEN
    IF bHasValidInv THEN
        FOR nI := 0 TO 2 DO
            FOR nJ := 0 TO 2 DO
                afMInvEff[nI, nJ] := afMInvLast[nI, nJ];   // 沿用上次有效逆矩阵 / reuse the last valid inverse
            END_FOR
        END_FOR
        bMatrixFallback := TRUE;                   // 降级标志置位 / fallback flag raised
        eState := E_DL_StackAlignState.eAlign;     // 按正常解算相继续 / continue in the normal solve state
        eErr   := DL_SAC_CODE_INFO_2;              // 信息级：矩阵退化沿用上次（不置 bError）/ info: singular matrix, last valid reused
        bError := FALSE;                           // 信息级不置 bError（R45/R101）/ info never raises bError
    ELSE
        eState := E_DL_StackAlignState.eFault;     // 进故障相 / enter fault state
        eErr   := DL_SAC_CODE_FLT_1;               // 故障级：矩阵非法且无历史有效值 / fault: illegal matrix with no history
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 输出不可用 / outputs unusable
        fCorrXMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrYMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrAngleMrad := DL_SAC_ZERO;             // 角度纠偏回零安全侧 / angular correction zeroed
        bClamped := FALSE;                         // 限幅标志撤 / clamp flag withdrawn
        bReady := FALSE;                           // 许可撤（R72）/ permission dropped
        bMatrixFallback := FALSE;                  // 无历史可沿用，降级标志不得冒充 / fallback flag must not fake reuse
        RETURN;
    END_IF
ELSE
    FOR nI := 0 TO 2 DO
        FOR nJ := 0 TO 2 DO
            afMInvEff[nI, nJ] := afMInvNew[nI, nJ];        // 采用本拍逆矩阵 / take the inverse of this scan
            afMInvLast[nI, nJ] := afMInvNew[nI, nJ];       // 记账：历史有效逆矩阵 / bookkeeping: last valid inverse
        END_FOR
    END_FOR
    bHasValidInv := TRUE;                          // 历史有效值成立 / history becomes valid
    bMatrixFallback := FALSE;                      // 正常路径不置降级 / no fallback on the normal path
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜相机无效闸：不纠偏、撤许可、不改超差判定（两条退出条件在 CASE eCamLost 相）
 *----------------------------------------------------------------------------*)
IF NOT bCamValid THEN
    fCorrXMm := DL_SAC_ZERO;                       // 纠偏量回零（不纠偏）/ correction zeroed, no correction
    fCorrYMm := DL_SAC_ZERO;                       // 纠偏量回零（不纠偏）/ correction zeroed, no correction
    fCorrAngleMrad := DL_SAC_ZERO;                 // 角度纠偏回零 / angular correction zeroed
    bClamped := FALSE;                             // 限幅标志撤 / clamp flag withdrawn
    bReady := FALSE;                               // 许可撤（R72）/ permission dropped
    bValid := FALSE;                               // 纠偏量不可用 / corrections unusable
    eErr   := 16#0000_0000;                        // 相机无效不占码位（无对应分配槽）/ no code allocated for a camera dropout
    bError := FALSE;                               // 不升格为故障 / not escalated to a fault
    IF bEnable THEN
        eState := E_DL_StackAlignState.eCamLost;   // 相机丢失相 / camera-lost state
    ELSE
        eState := E_DL_StackAlignState.eIdle;      // 失能优先回待机 / disable outranks, back to idle
    END_IF
    // 超差锁存原样保持：本拍不做判定即不改判定结果，绝不在此处清 bNg / NG latch held verbatim, never cleared here
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜纠偏量解算：逆映射 p_mech = M^(-1) x [dx_px, dy_px, 1]^T，
 *       角度纠偏量按标定链直通（本件不另设角度增益，增益归标定矩阵）
 *----------------------------------------------------------------------------*)
fRawXMm := afMInvEff[0, 0] * fOffsetXPx + afMInvEff[0, 1] * fOffsetYPx + afMInvEff[0, 2];   // 纠偏量 X [mm] / correction X [mm]
fRawYMm := afMInvEff[1, 0] * fOffsetXPx + afMInvEff[1, 1] * fOffsetYPx + afMInvEff[1, 2];   // 纠偏量 Y [mm] / correction Y [mm]
fCorrAngleMrad := fAngleMrad;                      // 角度纠偏量直通 [mrad] / angular correction passed through
IF (fRawXMm <> fRawXMm) OR (ABS(fRawXMm) >= DL_SAC_INF)
   OR (fRawYMm <> fRawYMm) OR (ABS(fRawYMm) >= DL_SAC_INF) THEN
    eState := E_DL_StackAlignState.eFault;         // 解算溢出进故障相 / solve overflow enters fault state
    eErr   := DL_SAC_CODE_FLT_2;                   // 故障级：解算结果非有限（复用输入非法槽）/ fault: non-finite result, shares the input slot
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 输出不可用 / outputs unusable
    fCorrXMm := DL_SAC_ZERO;                       // 纠偏量回零安全侧 / correction zeroed, safe side
    fCorrYMm := DL_SAC_ZERO;                       // 纠偏量回零安全侧 / correction zeroed, safe side
    fCorrAngleMrad := DL_SAC_ZERO;                 // 角度纠偏回零安全侧 / angular correction zeroed
    bClamped := FALSE;                             // 限幅标志撤 / clamp flag withdrawn
    bReady := FALSE;                               // 许可撤（R72）/ permission dropped
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜行程限幅：先判行程域（下限 ≥ 上限 → 零行程），再逐轴夹取；
 *       一旦夹取即置 bClamped + 信息 01EB（限幅值不得当正常纠偏量计数）
 *----------------------------------------------------------------------------*)
bTravelXBad := (fAxisXMinMm >= fAxisXMaxMm - DL_SAC_TOL);   // X 行程域倒置判定 / X travel inverted predicate
bTravelYBad := (fAxisYMinMm >= fAxisYMaxMm - DL_SAC_TOL);   // Y 行程域倒置判定 / Y travel inverted predicate
IF bTravelXBad THEN
    fLimX := fAxisXMinMm;                          // 零行程：上限夹到下限 / zero travel: ceiling pinned to the floor
ELSE
    fLimX := fAxisXMaxMm;                          // 正常行程上限 / normal travel ceiling
END_IF
IF bTravelYBad THEN
    fLimY := fAxisYMinMm;                          // 零行程：上限夹到下限 / zero travel: ceiling pinned to the floor
ELSE
    fLimY := fAxisYMaxMm;                          // 正常行程上限 / normal travel ceiling
END_IF
bClamped := FALSE;                                 // 限幅标志逐拍重判 / clamp flag re-judged per scan
fCorrXMm := fRawXMm;                               // 先取原始值再夹取 / take the raw value before clipping
IF fCorrXMm > fLimX THEN
    fCorrXMm := fLimX;                             // 上限夹取 [mm] / clipped to the ceiling
    bClamped := TRUE;                              // 限幅生效 / clamp active
END_IF
IF fCorrXMm < fAxisXMinMm THEN
    fCorrXMm := fAxisXMinMm;                       // 下限夹取 [mm] / clipped to the floor
    bClamped := TRUE;                              // 限幅生效 / clamp active
END_IF
fCorrYMm := fRawYMm;                               // 先取原始值再夹取 / take the raw value before clipping
IF fCorrYMm > fLimY THEN
    fCorrYMm := fLimY;                             // 上限夹取 [mm] / clipped to the ceiling
    bClamped := TRUE;                              // 限幅生效 / clamp active
END_IF
IF fCorrYMm < fAxisYMinMm THEN
    fCorrYMm := fAxisYMinMm;                       // 下限夹取 [mm] / clipped to the floor
    bClamped := TRUE;                              // 限幅生效 / clamp active
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜超差判定与锁存：判据取限幅前原始量（限幅后值被压成行程端点会漏判超差），
 *       命中即锁存 bNg，仅 bReset 可清（超差件不因下一拍合格而自动放行）
 *----------------------------------------------------------------------------*)
IF (ABS(fRawXMm) > fNgTolMm) OR (ABS(fRawYMm) > fNgTolMm)
   OR (ABS(fCorrAngleMrad) > fNgTolMrad) THEN
    bNg := TRUE;                                   // 超差锁存 / NG latched
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜状态机：CASE 含 ELSE 兜底（非法状态 → 030E + 纠偏量回零 + 撤许可）
 *        eCamLost 与 eFault 相各给两条以上退出条件（事件沿之外必含前置消失）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_StackAlignState.eIdle:
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        bReady := FALSE;                           // 许可撤 / permission dropped
        fCorrXMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrYMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrAngleMrad := DL_SAC_ZERO;             // 角度纠偏回零安全侧 / angular correction zeroed
        bClamped := FALSE;                         // 限幅标志撤 / clamp flag withdrawn
        bMatrixFallback := FALSE;                  // 降级标志撤 / fallback flag withdrawn
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF bEnable AND bCamValid THEN
            eState := E_DL_StackAlignState.eAlign; // 使能且相机有效进解算相 / enable with a valid camera enters solve
            bFirstScan := FALSE;                   // 首拍标志清除 / first-scan flag cleared
        END_IF

    E_DL_StackAlignState.eAlign:
        bValid := TRUE;                            // 纠偏量可用 / corrections usable
        bError := FALSE;                           // 解算相无故障 / no fault in the solve state
        IF bClamped THEN
            eErr := DL_SAC_CODE_INFO_1;            // 信息级：限幅生效 / info: clamp active
            eState := E_DL_StackAlignState.eLimited;   // 转限幅相 / enter the limited state
        ELSE
            eErr := 16#0000_0000;                  // 行程内无错 / within travel, no error
        END_IF
        bReady := bAxisInPos AND bCamValid;        // 在位且相机有效才允许下发 / issue only when in position and camera valid
        IF NOT bEnable THEN
            eState := E_DL_StackAlignState.eIdle;  // 失能回待机 / disable returns to idle
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
            bReady := FALSE;                       // 许可撤 / permission dropped
        ELSIF NOT bCamValid THEN
            eState := E_DL_StackAlignState.eCamLost;   // 相机丢失转丢失相 / camera dropout enters the lost state
            bValid := FALSE;                       // 输出不可用 / outputs unusable
            bReady := FALSE;                       // 许可撤 / permission dropped
        END_IF

    E_DL_StackAlignState.eLimited:
        bValid := TRUE;                            // 限幅后值可用（须 HMI 可辨）/ clipped values usable, flagged for HMI
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        eErr := DL_SAC_CODE_INFO_1;                // 信息级：纠偏量被行程限幅 / info: correction clamped by travel
        bReady := bAxisInPos AND bCamValid AND (NOT bTravelXBad) AND (NOT bTravelYBad);   // 行程域倒置时撤许可 / travel range inverted drops permission
        IF NOT bEnable THEN
            eState := E_DL_StackAlignState.eIdle;  // 失能回待机（退出条件一）/ disable returns to idle, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
            bReady := FALSE;                       // 许可撤 / permission dropped
        ELSIF NOT bCamValid THEN
            eState := E_DL_StackAlignState.eCamLost;   // 相机丢失（退出条件二）/ camera dropout, second exit
            bValid := FALSE;                       // 输出不可用 / outputs unusable
            bReady := FALSE;                       // 许可撤 / permission dropped
        ELSIF NOT bClamped THEN
            eState := E_DL_StackAlignState.eAlign; // 限幅消失回解算相（退出条件三）/ clamp gone, third exit to solve
        END_IF

    E_DL_StackAlignState.eCamLost:
        bValid := FALSE;                           // 输出不可用 / outputs unusable
        bReady := FALSE;                           // 许可撤 / permission dropped
        fCorrXMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrYMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrAngleMrad := DL_SAC_ZERO;             // 角度纠偏回零安全侧 / angular correction zeroed
        bClamped := FALSE;                         // 限幅标志撤 / clamp flag withdrawn
        eErr := 16#0000_0000;                      // 相机丢失不占码位 / no code allocated for a camera dropout
        bError := FALSE;                           // 不升格为故障 / not escalated to a fault
        IF bEnable AND bCamValid THEN
            eState := E_DL_StackAlignState.eAlign; // 相机恢复且使能回解算相（退出条件一）/ camera back, first exit
        ELSIF NOT bEnable THEN
            eState := E_DL_StackAlignState.eIdle;  // 失能回待机（退出条件二）/ disable, second exit
        END_IF

    E_DL_StackAlignState.eFault:
        bValid := FALSE;                           // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
        bReady := FALSE;                           // 许可撤 / permission dropped
        fCorrXMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrYMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrAngleMrad := DL_SAC_ZERO;             // 角度纠偏回零安全侧 / angular correction zeroed
        bClamped := FALSE;                         // 限幅标志撤 / clamp flag withdrawn
        IF eErr = 16#0000_0000 THEN
            eErr := DL_SAC_CODE_FLT_1;             // 入口无码时按矩阵非法解释（R45：bError 必须有对应码）/ default to the matrix slot so bError always maps to a code
        END_IF
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        IF bEnable AND bInvValid AND bCamValid AND bHasValidInv THEN
            eState := E_DL_StackAlignState.eAlign; // 前置条件全部恢复才回解算相（退出条件 ≥2）/ only when every precondition recovers
        END_IF

    ELSE
        eState := E_DL_StackAlignState.eFault;     // 非法状态兜底 / illegal-state fallback
        eErr := DL_SAC_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 输出不可用 / outputs unusable
        bReady := FALSE;                           // 许可撤 / permission dropped
        fCorrXMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrYMm := DL_SAC_ZERO;                   // 纠偏量回零安全侧 / correction zeroed, safe side
        fCorrAngleMrad := DL_SAC_ZERO;             // 角度纠偏回零安全侧 / angular correction zeroed

END_CASE
END_FUNCTION_BLOCK
