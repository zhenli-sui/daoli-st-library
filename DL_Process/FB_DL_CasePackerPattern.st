//==============================================================================
// 功能块：FB_DL_CasePackerPattern ｜ 中文名称：装箱排列模式生成
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：装箱机的排列模式生成件：按箱型规格（列数 / 行数 / 层数 / 节距 / 交错方式）
//           把「盒号」解码成「目标位姿 X/Y/Z + 旋转标志」的抓取序列，支持行交错（奇数行
//           半节距平移）与整层 90 度旋转（层号循环 0/90/180/270，旋转层 X/Y 轴互换）。
//           本件只生成序列与握手位，不执行任何动作、不驱动机器人、不做轨迹规划（位姿
//           给到上层定位层）。序号推进用 bStepDone 握手位的上升沿：上层置位表示本步已
//           执行完毕，本件取沿推进并自清（单拍标志自清，防同一格位重复取件）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：节距/层距/坐标[mm] / 旋转角[度] / 行列层[个] / 槽位与盒数[件]
// 错误码表：16#0005_0404 信息级（装箱容量大于本箱数量，末层留空位，不置 bError）/
//           16#0005_0405 信息级（交错/层旋转配置与单层配置冲突被规格钳位为无交错，
//           不置 bError）/ 16#0005_0348 故障级（排列容量小于本箱数量，或行列层域外
//           1~20，或数量域非法，置 bError）/ 16#0005_0349 故障级（节距/层距非正或任一
//           浮点输入非有限，置 bError——尺寸非法与非有限共用本槽，反证句：二者在现有
//           输出组合下不可观测出差异，均为 bValid 撤 + 序列回序号 1）/ 16#0005_034A
//           故障级兜底（状态机落 ELSE 非法状态，置 bError）。码位 16#0005 段。
// 状态机：E_DL_CasePackState（eIdle=0 待机 / eRunning=10 序列输出中 / eDone=20 末位已
//           输出 / eFault=99 故障兜底），CASE 含 ELSE 兜底，ELSE 置 034A 且序列回 1、
//           许可撤。
// 边界行为：① 容量 nCols x nRows x nLayers 与 nBoxCount 校验：nBoxCount > 容量 → 故障
//           0348（绝不硬塞）；nBoxCount < 容量 → 合法（末层留空位）+ 信息 0404 +
//           nEmptySlots 出口；② 行列层域外（≤ 0 或 > 20）→ 故障 0348；③ 节距 ≤ 0 或
//           非有限 → 故障 0349（防负坐标倒排、防非有限坐标外泄）；④ 序列越界防护：
//           nSeqIndex 达 nBoxCount 即 bLast 且不再推进；⑤ nLayers = 1 且 eLayerRotate
//           → 钳为 eNone + 信息 0405；⑥ 失能 → 序列复位到序号 1 + bValid := FALSE
//           （R72）；⑦ 坐标解算只做乘加与整除，除子为已判正的行列数（先判后除）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.14）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_PackInterlock（归属 DL_Process，与 FB_DL_CasePackerPattern 同文件）
 *       装箱交错方式；数值步长留空位，便于后续插值不破坏已有工程
 *----------------------------------------------------------------------------*)
TYPE E_DL_PackInterlock :
(
    eNone        := 0,   // 无交错：行列正交直排 / No interlock, orthogonal grid
    eRowShift    := 10,  // 行交错：奇数行沿列方向平移半个节距 / Row interlock, odd rows shifted half a pitch
    eLayerRotate := 20   // 层旋转：逐层循环旋转 0/90/180/270 度 / Layer rotation cycling 0/90/180/270 degrees
);
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_CasePackState（归属 DL_Process，与 FB_DL_CasePackerPattern 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CasePackState :
(
    eIdle    := 0,   // 待机：序列复位到序号 1，许可撤 / Idle, sequence reset to index 1, permission dropped
    eRunning := 10,  // 输出中：逐盒给出目标位姿 / Running, target pose emitted per case
    eDone    := 20,  // 末位已输出：bLast 置位，等待复位 / Last slot emitted, waiting for reset
    eFault   := 99   // 故障兜底：规格非法/非有限/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CasePackerPattern
 * 调用约定: 每个扫描周期无条件调用一次；上层在完成一次抓取后把 bStepDone 置 TRUE。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CasePackerPattern
VAR_INPUT
    nCols          : INT;                          // 列数 [个]，合法域 1~20 / Column count [pcs], domain 1..20
    nRows          : INT;                          // 行数 [个]，合法域 1~20 / Row count [pcs], domain 1..20
    nLayers        : INT;                          // 层数 [个]，合法域 1~20 / Layer count [pcs], domain 1..20
    fPitchXMm      : LREAL;                        // 列方向节距 [mm]，须 > 0 / Column pitch [mm], must be > 0
    fPitchYMm      : LREAL;                        // 行方向节距 [mm]，须 > 0 / Row pitch [mm], must be > 0
    fLayerGapMm    : LREAL;                        // 层间高度差 [mm]，须 > 0 / Layer height gap [mm], must be > 0
    eInterlock     : E_DL_PackInterlock;           // 交错方式（无 / 行交错 / 层旋转）/ Interlock mode
    nBoxCount      : INT;                          // 本箱数量 [件]，合法域 1~容量 / Cases in this carton [pcs], domain 1..capacity
    bEnable        : BOOL;                         // 总使能 / Master enable
    bReset         : BOOL;                         // 复位，上升沿把序列复位到序号 1 / Reset, rising edge rewinds the sequence to index 1
END_VAR
VAR_OUTPUT
    nSeqIndex      : INT;                          // 当前序号 [个]，从 1 起 / Current sequence index, 1-based
    fTargetXMm     : LREAL;                        // 目标位 X [mm] / Target X [mm]
    fTargetYMm     : LREAL;                        // 目标位 Y [mm] / Target Y [mm]
    fTargetZMm     : LREAL;                        // 目标位 Z [mm]，按层高累计 / Target Z [mm], accumulated per layer
    fTargetRotDeg  : LREAL;                        // 目标旋转角 [度]，取 0 / 90 / 180 / 270 / Target rotation [deg], 0/90/180/270
    bStepDone      : BOOL;                         // 本步完成握手位（上层置 TRUE，本件取沿后自清）/ Step handshake, caller sets TRUE, the block clears it after consuming
    bLast          : BOOL;                         // 末位标志（本箱最后一个非空槽位）/ Last slot of this carton
    nSlotCount     : INT;                          // 总槽位数 [件] = 列 x 行 x 层 / Total slots [pcs]
    nEmptySlots    : INT;                          // 空槽位数 [件] = 总槽位 − 本箱数量 / Empty slots [pcs]
    eErr           : UDINT;                        // 错误码，0 = 无错，码位 16#0005_0404 起信息级、16#0005_0348 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                         // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                        // 位姿输出可用标志，失能/故障闸显式 FALSE / Pose usable flag, explicit FALSE on disable/fault gates
    eState         : E_DL_CasePackState;           // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset        : R_TRIG;                       // 复位上升沿检测实例 / Reset rising edge detector
    fbStep         : R_TRIG;                       // 步完成握手上升沿检测实例 / Step handshake rising edge detector
    eInterlockEff  : E_DL_PackInterlock;           // 生效交错方式（钳位后）/ Effective interlock mode after clamping
    nCapacity      : INT;                          // 总容量 [件] = 列 x 行 x 层 / Total capacity [pcs]
    nIdx0          : INT;                          // 零基序号 [—] / Zero-based sequence index
    nPerLayer      : INT;                          // 每层盒数 [件] = 列 x 行 / Cases per layer [pcs]
    nLayer         : INT;                          // 层号（1 基）[层] / Layer number, 1-based
    nRemain        : INT;                          // 层内余量序号 [—] / In-layer remainder index
    nRow           : INT;                          // 行号（1 基）[行] / Row number, 1-based
    nCol           : INT;                          // 列号（1 基）[列] / Column number, 1-based
    nRotQuarter    : INT;                          // 旋转四分之一圈数 [—] / Rotation quarter count
    fShiftXMm      : LREAL;                        // 行交错平移量 [mm] / Row interlock shift [mm]
    bClampInterlock : BOOL;                        // 交错配置被钳位标志 / Interlock clamped flag
    bSpaceWarn     : BOOL;                         // 末层留空位提示标志 / Empty-slot hint flag
    bFirstScan     : BOOL := TRUE;                 // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_CPP_CODE_INFO_1 : UDINT := 16#0005_0404;    // 信息级槽 1（容量大于数量，末层留空位） / info slot 1
    DL_CPP_CODE_INFO_2 : UDINT := 16#0005_0405;    // 信息级槽 2（交错/层旋转配置被钳位） / info slot 2
    DL_CPP_CODE_FLT_1  : UDINT := 16#0005_0348;    // 故障级槽 1（容量不足/行列层域非法） / fault slot 1
    DL_CPP_CODE_FLT_2  : UDINT := 16#0005_0349;    // 故障级槽 2（尺寸非法/输入非有限） / fault slot 2
    DL_CPP_CODE_FLT_3  : UDINT := 16#0005_034A;    // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_CPP_DIM_MIN     : INT := 1;                 // 行列层下限 [个] / Dimension floor [pcs]
    DL_CPP_DIM_MAX     : INT := 20;                // 行列层上限 [个] / Dimension ceiling [pcs]
    DL_CPP_ZERO        : LREAL := 0.0;             // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_CPP_TOL         : LREAL := 1.0E-6;          // 浮点比较容差 [—] / Float comparison tolerance
    DL_CPP_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
    DL_CPP_HALF        : LREAL := 0.5;             // 半节距系数 [—] / Half-pitch factor
    DL_CPP_QUARTER_DEG : LREAL := 90.0;            // 每层旋转步长 [度] / Rotation step per layer [deg]
    DL_CPP_QUARTERS    : INT := 4;                 // 旋转循环周期 [层] / Rotation cycle length [layers]
    DL_CPP_IDX_FIRST   : INT := 1;                 // 序号起点 [个] / First sequence index
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿与步完成握手沿在任意分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbStep(CLK := bStepDone);                          // 步完成沿检测无条件刷新（先取沿后自清）/ step edge refreshed before the output is cleared

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_CasePackState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    nSeqIndex := DL_CPP_IDX_FIRST;                 // 序列复位到序号 1 / sequence rewound to index 1
    bStepDone := FALSE;                            // 握手位清 / handshake cleared
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸：尺寸类浮点非有限 → 0349（与尺寸非法共用本槽，见头注释反证句）
 *----------------------------------------------------------------------------*)
IF (fPitchXMm <> fPitchXMm) OR (ABS(fPitchXMm) >= DL_CPP_INF)
   OR (fPitchYMm <> fPitchYMm) OR (ABS(fPitchYMm) >= DL_CPP_INF)
   OR (fLayerGapMm <> fLayerGapMm) OR (ABS(fLayerGapMm) >= DL_CPP_INF) THEN
    eState := E_DL_CasePackState.eFault;           // 进故障相 / enter fault state
    eErr   := DL_CPP_CODE_FLT_2;                   // 故障级：输入非有限 / fault: non-finite input
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    nSeqIndex := DL_CPP_IDX_FIRST;                 // 序列回序号 1 安全侧 / sequence rewound, safe side
    fTargetXMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetYMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetZMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetRotDeg := DL_CPP_ZERO;                  // 旋转角回零安全侧 / rotation zeroed, safe side
    bLast := FALSE;                                // 末位标志撤 / last flag withdrawn
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸：行列层域（1~20）+ 节距层距为正（防负坐标倒排、防除零）
 *----------------------------------------------------------------------------*)
IF (nCols < DL_CPP_DIM_MIN) OR (nCols > DL_CPP_DIM_MAX)
   OR (nRows < DL_CPP_DIM_MIN) OR (nRows > DL_CPP_DIM_MAX)
   OR (nLayers < DL_CPP_DIM_MIN) OR (nLayers > DL_CPP_DIM_MAX) THEN
    eState := E_DL_CasePackState.eFault;           // 进故障相 / enter fault state
    eErr   := DL_CPP_CODE_FLT_1;                   // 故障级：行列层域非法 / fault: dimension out of range
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    nSeqIndex := DL_CPP_IDX_FIRST;                 // 序列回序号 1 安全侧 / sequence rewound, safe side
    fTargetXMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetYMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetZMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetRotDeg := DL_CPP_ZERO;                  // 旋转角回零安全侧 / rotation zeroed, safe side
    bLast := FALSE;                                // 末位标志撤 / last flag withdrawn
    RETURN;
END_IF
IF (fPitchXMm <= DL_CPP_TOL) OR (fPitchYMm <= DL_CPP_TOL) OR (fLayerGapMm <= DL_CPP_TOL) THEN
    eState := E_DL_CasePackState.eFault;           // 进故障相 / enter fault state
    eErr   := DL_CPP_CODE_FLT_2;                   // 故障级：尺寸非法 / fault: dimension invalid
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    nSeqIndex := DL_CPP_IDX_FIRST;                 // 序列回序号 1 安全侧 / sequence rewound, safe side
    fTargetXMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetYMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetZMm := DL_CPP_ZERO;                     // 坐标回零安全侧 / coordinates zeroed, safe side
    fTargetRotDeg := DL_CPP_ZERO;                  // 旋转角回零安全侧 / rotation zeroed, safe side
    bLast := FALSE;                                // 末位标志撤 / last flag withdrawn
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜容量自算与数量校验：容量不足绝不硬塞（0348），容量富余属合法（0404）
 *----------------------------------------------------------------------------*)
nCapacity := nCols * nRows * nLayers;              // 总容量 [件] / total capacity [pcs]
nPerLayer := nCols * nRows;                        // 每层盒数 [件] / cases per layer [pcs]
nSlotCount := nCapacity;                           // 总槽位出口 / total slot count outlet
IF (nBoxCount < DL_CPP_DIM_MIN) OR (nBoxCount > nCapacity) THEN
    eState := E_DL_CasePackState.eFault;           // 进故障相 / enter fault state
    eErr   := DL_CPP_CODE_FLT_1;                   // 故障级：数量域非法或容量不足 / fault: count out of range or capacity exceeded
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    nEmptySlots := nCapacity - nBoxCount;          // 空位数为负则如实透出（诊断用）/ empty slots reported even when negative, for diagnosis
    nSeqIndex := DL_CPP_IDX_FIRST;                 // 序列回序号 1 安全侧 / sequence rewound, safe side
    RETURN;
END_IF
nEmptySlots := nCapacity - nBoxCount;              // 空槽位数 [件] / empty slots [pcs]
bSpaceWarn := (nEmptySlots > 0);                   // 末层留空位提示 / empty-slot hint

(*------------------------------------------------------------------------------
 * 段 6｜交错方式钳位：单层配置下的层旋转无意义，钳为无交错（0405）；
 *       枚举越界值同样钳为无交错并提示，不新增码位
 *----------------------------------------------------------------------------*)
eInterlockEff := eInterlock;                       // 先取引脚值 / take the pin value first
bClampInterlock := FALSE;                          // 钳位标志逐拍重判 / clamp flag re-judged per scan
IF (eInterlockEff <> E_DL_PackInterlock.eNone)
   AND (eInterlockEff <> E_DL_PackInterlock.eRowShift)
   AND (eInterlockEff <> E_DL_PackInterlock.eLayerRotate) THEN
    eInterlockEff := E_DL_PackInterlock.eNone;     // 枚举越界：钳为无交错 / out-of-range enumeration clamped to none
    bClampInterlock := TRUE;                       // 钳位提示 / clamp hint
END_IF
IF (eInterlockEff = E_DL_PackInterlock.eLayerRotate) AND (nLayers <= 1) THEN
    eInterlockEff := E_DL_PackInterlock.eNone;     // 单层无层旋转可言 / layer rotation is meaningless with a single layer
    bClampInterlock := TRUE;                       // 钳位提示 / clamp hint
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜握手推进：bStepDone 上升沿推进序号；末位不再推进（序列越界防护）
 *----------------------------------------------------------------------------*)
IF fbStep.Q THEN
    bStepDone := FALSE;                            // 握手位自清（单拍标志自清，红线 5）/ handshake self-cleared
    IF nSeqIndex < nBoxCount THEN
        nSeqIndex := nSeqIndex + 1;                // 推进到下一盒号 / advance to the next case
    END_IF
END_IF
IF nSeqIndex < DL_CPP_IDX_FIRST THEN
    nSeqIndex := DL_CPP_IDX_FIRST;                 // 序号下限防护 / index floor guard
END_IF
IF nSeqIndex > nBoxCount THEN
    nSeqIndex := nBoxCount;                        // 序号上限防护 / index ceiling guard
END_IF
bLast := (nSeqIndex >= nBoxCount);                 // 末位标志（本箱最后一个非空槽位）/ last slot of this carton

(*------------------------------------------------------------------------------
 * 段 8｜盒号解码：零基序号 → 层 / 行 / 列（除子 nPerLayer 与 nCols 已由段 4 保证为正）
 *----------------------------------------------------------------------------*)
nIdx0 := nSeqIndex - DL_CPP_IDX_FIRST;             // 零基序号 / zero-based index
nLayer := (nIdx0 / nPerLayer) + 1;                 // 层号（1 基）[层] / layer number, 1-based
nRemain := nIdx0 - ((nLayer - 1) * nPerLayer);     // 层内余量（显式减法，避开 MOD 的负数方言差异）/ in-layer remainder
nRow := (nRemain / nCols) + 1;                     // 行号（1 基）[行] / row number, 1-based
nCol := nRemain - ((nRow - 1) * nCols) + 1;        // 列号（1 基）[列] / column number, 1-based

(*------------------------------------------------------------------------------
 * 段 9｜位姿解算：层旋转 exch 轴序，行交错平移半节距；Z 按层高累计
 *----------------------------------------------------------------------------*)
fShiftXMm := DL_CPP_ZERO;                          // 交错平移量初值 / interlock shift seed
IF eInterlockEff = E_DL_PackInterlock.eRowShift THEN
    IF ((nRow - 1) MOD 2) = 1 THEN
        fShiftXMm := fPitchXMm * DL_CPP_HALF;      // 奇数行平移半节距 [mm] / odd rows shifted half a pitch
    END_IF
END_IF
nRotQuarter := 0;                                  // 旋转四分之一圈数初值 / rotation quarter seed
IF eInterlockEff = E_DL_PackInterlock.eLayerRotate THEN
    nRotQuarter := (nLayer - 1) MOD DL_CPP_QUARTERS;   // 逐层循环 0/1/2/3 个四分之一圈 / per-layer quarter cycle
END_IF
fTargetRotDeg := INT_TO_LREAL(nRotQuarter) * DL_CPP_QUARTER_DEG;   // 目标旋转角 [度] / target rotation [deg]
IF (nRotQuarter = 1) OR (nRotQuarter = 3) THEN
    fTargetXMm := (INT_TO_LREAL(nRow - 1) * fPitchYMm) + fShiftXMm;   // 旋转层：X 走行方向节距 [mm] / rotated layer, X follows the row pitch
    fTargetYMm := INT_TO_LREAL(nCol - 1) * fPitchXMm;                 // 旋转层：Y 走列方向节距 [mm] / rotated layer, Y follows the column pitch
ELSE
    fTargetXMm := (INT_TO_LREAL(nCol - 1) * fPitchXMm) + fShiftXMm;   // 正交层：X 走列方向节距 [mm] / orthogonal layer, X follows the column pitch
    fTargetYMm := INT_TO_LREAL(nRow - 1) * fPitchYMm;                 // 正交层：Y 走行方向节距 [mm] / orthogonal layer, Y follows the row pitch
END_IF
fTargetZMm := INT_TO_LREAL(nLayer - 1) * fLayerGapMm;                 // 层高累计（LREAL 承载）[mm] / layer height accumulation

(*------------------------------------------------------------------------------
 * 段 10｜状态机：CASE 含 ELSE 兜底（非法状态 → 034A + 序列回 1 + 许可撤）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_CasePackState.eIdle:
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        nSeqIndex := DL_CPP_IDX_FIRST;             // 待机序列固守序号 1 / idle holds index 1
        bLast := (nBoxCount <= DL_CPP_IDX_FIRST);  // 单件箱待机即末位 / a single-case carton is already last
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_CasePackState.eRunning; // 使能进输出相 / enable enters the running state
            bFirstScan := FALSE;                   // 首拍标志清除 / first-scan flag cleared
        END_IF

    E_DL_CasePackState.eRunning:
        bValid := TRUE;                            // 位姿可用 / poses usable
        bError := FALSE;                           // 输出相无故障 / no fault in the running state
        eErr := 16#0000_0000;                      // 输出相先清码 / clear the code first
        IF bClampInterlock THEN
            eErr := DL_CPP_CODE_INFO_2;            // 信息级：交错配置被钳位 / info: interlock clamped
        END_IF
        IF bSpaceWarn THEN
            eErr := DL_CPP_CODE_INFO_1;            // 信息级：末层留空位（与钳位提示并列时以空位为主）/ info: empty slots, the primary hint
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_CasePackState.eIdle;    // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
            nSeqIndex := DL_CPP_IDX_FIRST;         // 序列复位到序号 1 / sequence rewound
        ELSIF bLast AND fbStep.Q THEN
            eState := E_DL_CasePackState.eDone;    // 末位已完成转完成相（退出条件二）/ last slot done, second exit
        END_IF

    E_DL_CasePackState.eDone:
        bValid := TRUE;                            // 末位位姿仍可读（现场常需复核）/ the last pose stays readable
        bLast := TRUE;                             // 末位标志保持 / last flag held
        bError := FALSE;                           // 完成相无故障 / no fault in the done state
        eErr := DL_CPP_CODE_INFO_1;                // 信息级：末层留空位情况在此相持续提示 / empty-slot hint kept in this state
        IF (NOT bEnable) OR bReset OR (nEmptySlots = 0 AND (NOT bSpaceWarn)) THEN
            eState := E_DL_CasePackState.eIdle;    // 失能 / 复位 / 无空位提示三条退出条件 / three exits
            IF bReset THEN
                nSeqIndex := DL_CPP_IDX_FIRST;     // 复位沿直接回序号 1 / reset rewinds immediately
            END_IF
        END_IF

    E_DL_CasePackState.eFault:
        bValid := FALSE;                           // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        nSeqIndex := DL_CPP_IDX_FIRST;             // 故障侧序列回 1，防上层按旧序号取件 / rewind so the upper layer cannot pick on a stale index
        fTargetXMm := DL_CPP_ZERO;                 // 坐标回零安全侧 / coordinates zeroed, safe side
        fTargetYMm := DL_CPP_ZERO;                 // 坐标回零安全侧 / coordinates zeroed, safe side
        fTargetZMm := DL_CPP_ZERO;                 // 坐标回零安全侧 / coordinates zeroed, safe side
        fTargetRotDeg := DL_CPP_ZERO;              // 旋转角回零安全侧 / rotation zeroed, safe side
        bLast := FALSE;                            // 末位标志撤 / last flag withdrawn
        IF eErr = 16#0000_0000 THEN
            eErr := DL_CPP_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
        END_IF
        IF bEnable AND (nCols >= DL_CPP_DIM_MIN) AND (nCols <= DL_CPP_DIM_MAX)
           AND (nRows >= DL_CPP_DIM_MIN) AND (nRows <= DL_CPP_DIM_MAX)
           AND (nLayers >= DL_CPP_DIM_MIN) AND (nLayers <= DL_CPP_DIM_MAX)
           AND (fPitchXMm > DL_CPP_TOL) AND (fPitchYMm > DL_CPP_TOL) AND (fLayerGapMm > DL_CPP_TOL)
           AND (nBoxCount >= DL_CPP_DIM_MIN) AND (nBoxCount <= nCapacity) THEN
            eState := E_DL_CasePackState.eIdle;    // 全部组态恢复才回待机（退出条件 ≥2）/ recover only when every configuration item is sane
        END_IF

    ELSE
        eState := E_DL_CasePackState.eFault;       // 非法状态兜底 / illegal-state fallback
        eErr := DL_CPP_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 位姿不可用 / poses unusable
        nSeqIndex := DL_CPP_IDX_FIRST;             // 序列回序号 1 安全侧 / sequence rewound, safe side
        fTargetXMm := DL_CPP_ZERO;                 // 坐标回零安全侧 / coordinates zeroed, safe side
        fTargetYMm := DL_CPP_ZERO;                 // 坐标回零安全侧 / coordinates zeroed, safe side
        fTargetZMm := DL_CPP_ZERO;                 // 坐标回零安全侧 / coordinates zeroed, safe side
        fTargetRotDeg := DL_CPP_ZERO;              // 旋转角回零安全侧 / rotation zeroed, safe side
        bLast := FALSE;                            // 末位标志撤 / last flag withdrawn

END_CASE
END_FUNCTION_BLOCK
