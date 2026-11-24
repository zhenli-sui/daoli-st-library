//==============================================================================
// 功能块：FB_DL_PalletizerLayerSeq ｜ 中文名称：码垛层排布顺控
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：码垛机层排布顺控：层容量自算（正交与旋转两取向各算一遍，逐层按本层取向校验）→ 层内位置
//           序列 → 取放指令与夹手完成反馈握手（超时重试一次）→ 层满/垛满判定。
//           奇偶层旋转时偶数层整体旋转 90 度，层内落点由 FC_DL_Affine2Apply 施加旋转
//           矩阵得到（库内低层复用，禁止在本件重写点变换与矩阵乘）。旋转矩阵的元素以
//           VAR CONSTANT 标量常量声明（恒等 1/0、90 度 0/-1/+1），每拍装配成生效阵；
//           平移列恒为 0，运行时平移量（托盘长度）在阵外补偿——阵中不含运行时量，才配
//           得上常量语义（二维数组行主序字面量初始化在三平台可移植性差，故用标量常量
//           装配，避免方言差异）。本件只出位姿与指令，不做轨迹规划、不控夹手电磁阀
//           （执行器归设备层）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：托盘与箱体尺寸[mm] / 层高[mm] / 坐标[mm] / 旋转角[度] / 层数与位置序号[个] /
//         取放超时[s] / 扫描间隔[ms] / 垛计数[垛]
// 错误码表：16#0005_0408 信息级（末层不满垛，留空位，不置 bError）/ 16#0005_0409 信息级
//           （取放超时首次重试，不置 bError）/ 16#0005_034E 故障级（层容量不足或箱体/
//           托盘尺寸规格不匹配，含尺寸非有限——非有限尺寸即规格不可信，映射见本行）/
//           16#0005_034F 故障级（取放超时重试耗尽，垛型中断，置 bError + 撤指令）/
//           16#0005_0350 故障级兜底（状态机落 ELSE 非法状态，置 bError）。034E 非有限
//           映射的反证句：尺寸非有限与容量不足在现有输出组合下不可观测出差异（均为
//           bError + bPlaceCmd 撤 + bValid 撤 + eState 进 eFault），§3 未给本件独立非有限
//           槽，故显式复用不越段。
// 状态机：E_DL_PalletLayerState（eIdle=0 待机 / eWaitCase=10 等来料 / ePlace=20 出取放
//           指令 / eWaitGrip=30 等夹手反馈 / eLayerEnd=40 层边界 / ePalletEnd=50 垛边界 /
//           eFault=99 故障兜底），CASE 含 ELSE 兜底，ELSE 置 0350 且撤指令、许可撤。
// 边界行为：① 层容量自算：正交取向 floor(托盘长/箱长) x floor(托盘宽/箱宽)、旋转取向
//           floor(托盘长/箱宽) x floor(托盘宽/箱长)，两取向各自校验——nCasePerLayer 超
//           正交容量 → 故障 034E；启用奇偶层旋转时还须不超旋转容量，否则同样 034E
//           （取大者会让旋转层"蒙混过关"，故逐取向验，绝不硬塞）；② 取放超时先重试
//           一次（信息 0409），二次超时 → 故障 034F 并中断垛型；③ 层高累计 Z =
//           (层号 − 1) x 层高，LREAL 承载防溢出；④ 末层不满 → 信息 0408；⑤ bStop 只在
//           层边界与等来料相生效（不在抓取中停，安全侧）；⑥ 失能/停止 → 撤指令 +
//           bValid := FALSE（R72）；⑦ 旋转落点必须走 FC_DL_Affine2Apply（常量纯旋转阵，
//           平移在阵外补偿），点变换件返回不可用 → 034E 并撤指令。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.16，依赖 §4.2 件 FC_DL_Affine2Apply 语义）
//           v1.0.1 2026-11-17 终审修正两处（对外引脚契约零变更）：①旋转层阵外平移量由 fPalletLengthMm
//           改为 (nRowsEff − 1) x fCaseWidthMm（原式整体多推一个箱宽，首行落点越出托盘边界）；
//           ②bPalletDone 取消本相同拍自撤，撤销点移交 eIdle 相（原实现同拍置位又撤位，脉冲永不外显）。
//           层容量口径经总监独立验算：1200x1000 托盘配 400x300 箱体 → 正交 3x3=9、旋转 4x2=8，
//           派单书 §4.16 验收向量①所写「容量 6」为派单算术笔误，本件实现（9）为准。
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_PalletLayerState（归属 DL_Process，与 FB_DL_PalletizerLayerSeq 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PalletLayerState :
(
    eIdle      := 0,   // 待机：指令撤，等 bStart / Idle, command dropped, waiting for start
    eWaitCase  := 10,  // 等来料：本层下一格位已算好，等 bCaseReady / Waiting for the next case
    ePlace     := 20,  // 出指令：bPlaceCmd 置位，等夹手动作 / Command issued, gripper acting
    eWaitGrip  := 30,  // 等反馈：等 bGripDone 或超时 / Waiting for feedback or timeout
    eLayerEnd  := 40,  // 层边界：本层放满，允许在此停止 / Layer boundary, a safe stop point
    ePalletEnd := 50,  // 垛边界：整垛完成，垛计数 +1 / Pallet boundary, pallet counter increments
    eFault     := 99   // 故障兜底：规格不匹配/超时耗尽/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_PalletizerLayerSeq
 * 调用约定: 每个扫描周期无条件调用一次；uDeltaTimeMs 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PalletizerLayerSeq
VAR_INPUT
    nCasePerLayer    : INT;                        // 每层箱数 [个]，须 <= 层容量 / Cases per layer [pcs], must not exceed the capacity
    nLayersPerPallet : INT;                        // 每垛层数 [层]，合法域 1~20 / Layers per pallet [layers], domain 1..20
    fPalletLengthMm  : LREAL;                      // 托盘长度 [mm]，须 > 0 / Pallet length [mm], must be > 0
    fPalletWidthMm   : LREAL;                      // 托盘宽度 [mm]，须 > 0 / Pallet width [mm], must be > 0
    fCaseLengthMm    : LREAL;                      // 箱体长度 [mm]，须 > 0 / Case length [mm], must be > 0
    fCaseWidthMm     : LREAL;                      // 箱体宽度 [mm]，须 > 0 / Case width [mm], must be > 0
    fLayerHeightMm   : LREAL;                      // 层高 [mm]，须 > 0 / Layer height [mm], must be > 0
    bOddLayerRotate  : BOOL;                       // 奇偶层旋转使能（偶数层旋转 90 度）/ Odd/even layer rotation, even layers rotate 90 degrees
    bCaseReady       : BOOL;                       // 来料在位 / Case available at the pick point
    bGripDone        : BOOL;                       // 夹手完成反馈 / Gripper completion feedback
    tGripTimeout     : TIME := T#8S;               // 取放超时 [ms] / Pick-and-place timeout [ms]
    bStart           : BOOL;                       // 启动（取上升沿）/ Start, rising edge
    bStop            : BOOL;                       // 停止（只在层边界与等来料相生效）/ Stop, honoured only at layer boundaries and while waiting
    bReset           : BOOL;                       // 复位，上升沿回待机并清垛计数锁存位 / Reset, rising edge returns to idle
    uDeltaTimeMs     : UDINT;                      // 扫描间隔 [ms]，调用方注入，禁系统时间函数 / Scan interval [ms], caller-injected
END_VAR
VAR_OUTPUT
    nLayerIndex      : INT;                        // 当前层号 [层]，从 1 起 / Current layer index, 1-based
    nPosIndex        : INT;                        // 层内位置序号 [个]，从 1 起 / In-layer position index, 1-based
    fTargetXMm       : LREAL;                      // 目标位 X [mm] / Target X [mm]
    fTargetYMm       : LREAL;                      // 目标位 Y [mm] / Target Y [mm]
    fTargetZMm       : LREAL;                      // 目标位 Z [mm] / Target Z [mm]
    fTargetRotDeg    : LREAL;                      // 目标旋转角 [度]，0 或 90 / Target rotation [deg], 0 or 90
    bPlaceCmd        : BOOL;                       // 取放指令（层放满/故障/停止即撤）/ Pick-and-place command
    bLayerDone       : BOOL;                       // 本层已放满 / Layer completed
    bPalletDone      : BOOL;                       // 整垛完成 / Pallet completed
    nCaseCount       : INT;                        // 本垛已放件数 [件] / Cases placed on this pallet [pcs]
    uPalletCount     : UDINT;                      // 完成垛数 [垛]，饱和 / Completed pallets [pallets], saturating
    eErr             : UDINT;                      // 错误码，0 = 无错，码位 16#0005_0408 起信息级、16#0005_034E 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError           : BOOL;                       // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid           : BOOL;                       // 位姿输出可用标志，失能/故障闸显式 FALSE / Pose usable flag, explicit FALSE on disable/fault gates
    eState           : E_DL_PalletLayerState;      // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset          : R_TRIG;                     // 复位上升沿检测实例 / Reset rising edge detector
    fbStart          : R_TRIG;                     // 启动上升沿检测实例 / Start rising edge detector
    fbTonGrip        : TON;                        // 取放超时定时器实例 / Pick-and-place timeout timer
    afRotZero        : ARRAY[0..2, 0..2] OF LREAL; // 本拍生效旋转矩阵（恒等或 90 度）/ Effective rotation matrix of this scan
    nCapOrtho        : INT;                        // 正交取向层容量 [件] / Capacity with the orthogonal orientation [pcs]
    nCapRot          : INT;                        // 旋转取向层容量 [件] / Capacity with the rotated orientation [pcs]
    nCapEff          : INT;                        // 本层取向容量 [件] / Capacity of the current orientation [pcs]
    nColsEff         : INT;                        // 本层列数 [个] / Columns of this layer [pcs]
    nRowsEff         : INT;                        // 本层行数 [个] / Rows of this layer [pcs]
    nIdx0            : INT;                        // 层内零基位置序号 [—] / Zero-based in-layer index
    nCol             : INT;                        // 本格位列号（1 基）[列] / Column of this cell, 1-based
    nRow             : INT;                        // 本格位行号（1 基）[行] / Row of this cell, 1-based
    nRetryCnt        : INT;                        // 本格位超时重试次数 [次] / Timeout retry count of this cell
    nLoop            : INT;                        // 赋值循环索引 [—] / Assignment loop index
    fLocalXMm        : LREAL;                      // 箱体自身坐标系 X [mm] / X in the case-local frame [mm]
    fLocalYMm        : LREAL;                      // 箱体自身坐标系 Y [mm] / Y in the case-local frame [mm]
    fOutXMm          : LREAL;                      // 点变换结果 X [mm] / Transformed X [mm]
    fOutYMm          : LREAL;                      // 点变换结果 Y [mm] / Transformed Y [mm]
    uApplyErr        : UDINT;                      // 点变换件错误码暂存 / Point-transform error code staging
    bApplyFault      : BOOL;                       // 点变换件故障标志暂存 / Point-transform fault flag staging
    bApplyValid      : BOOL;                       // 点变换件可用标志暂存 / Point-transform usable flag staging
    bApplyOk         : BOOL;                       // 点变换件返回值暂存 / Point-transform return staging
    bLayerRotated    : BOOL;                       // 本层旋转标志 / This layer is rotated
    bSpaceWarn       : BOOL;                       // 末层不满提示标志 / Under-filled top layer hint
    bGripTimedOut    : BOOL;                       // 取放超时命中 / Pick-and-place timeout hit
    bRearm           : BOOL;                       // 定时器重装脉冲（本拍强制 IN 为 FALSE 一拍）/ Timer re-arm pulse, forces IN FALSE for one scan
    bNonFin          : BOOL;                       // 非有限判定中间标志 / Non-finite detection intermediate flag
    bFirstScan       : BOOL := TRUE;               // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_PLS_CODE_INFO_1 : UDINT := 16#0005_0408;    // 信息级槽 1（末层不满垛留空位） / info slot 1
    DL_PLS_CODE_INFO_2 : UDINT := 16#0005_0409;    // 信息级槽 2（取放超时重试） / info slot 2
    DL_PLS_CODE_FLT_1  : UDINT := 16#0005_034E;    // 故障级槽 1（容量不足/规格不匹配） / fault slot 1
    DL_PLS_CODE_FLT_2  : UDINT := 16#0005_034F;    // 故障级槽 2（超时重试耗尽） / fault slot 2
    DL_PLS_CODE_FLT_3  : UDINT := 16#0005_0350;    // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_PLS_ROT90       : LREAL := 90.0;            // 旋转层目标角 [度] / Rotated layer angle [deg]
    DL_PLS_LAYER_MIN   : INT := 1;                 // 层数下限 [层] / Layer count floor
    DL_PLS_LAYER_MAX   : INT := 20;                // 层数上限 [层] / Layer count ceiling
    DL_PLS_CELL_MIN    : INT := 1;                 // 层容量下限 [件] / Layer capacity floor [pcs]
    DL_PLS_CNT_MAX     : UDINT := 16#FFFF_FFFE;    // 垛计数饱和值 [垛] / Pallet counter saturation
    DL_PLS_RETRY_MAX   : INT := 1;                 // 超时重试次数上限 [次] / Retry ceiling [times]
    DL_PLS_ZERO        : LREAL := 0.0;             // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_PLS_ONE         : LREAL := 1.0;             // 单位常量，齐次项 [—] / Unity constant, homogeneous entry
    DL_PLS_TOL         : LREAL := 1.0E-6;          // 浮点比较容差 [—] / Float comparison tolerance
    DL_PLS_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
    // 纯旋转常量阵（行主序平铺展开）：恒等映射 / pure rotation constants, row-major flat
    DL_PLS_M_ID_X      : LREAL := 1.0;             // 恒等阵 (0,0) / identity (0,0)
    DL_PLS_M_ID_Y      : LREAL := 1.0;             // 恒等阵 (1,1) / identity (1,1)
    DL_PLS_M_R90_C     : LREAL := -1.0;            // 90 度阵 (0,1) = -1 / rot90 (0,1) = -1
    DL_PLS_M_R90_S     : LREAL := 1.0;             // 90 度阵 (1,0) = +1 / rot90 (1,0) = +1
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位/启动沿与超时定时器在任意分支之外周期调用；
 *       定时器 IN 取上拍状态（单拍滞后对 8 s 窗无影响），保证各分支计时链不断流
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbStart(CLK := bStart);                            // 启动沿检测无条件刷新 / start edge refreshed unconditionally
fbTonGrip(IN := (eState = E_DL_PalletLayerState.eWaitGrip) AND (NOT bGripDone)
                AND (NOT bRearm),                  // 重装拍强制 IN 为 FALSE 使定时器复位 / the re-arm scan forces IN FALSE, resetting the timer
          PT := tGripTimeout);                     // 取放超时 [ms] / pick-and-place timeout
IF bRearm THEN
    bRearm := FALSE;                               // 重装脉冲单拍自清（下一拍起重新计时）/ re-arm pulse self-cleared, timing restarts next scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_PalletLayerState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    nLayerIndex := 0;                              // 层号清 / layer index cleared
    nPosIndex := 0;                                // 位置序号清 / position index cleared
    nCaseCount := 0;                               // 本垛件数清 / pallet case count cleared
    nRetryCnt := 0;                                // 重试计数清 / retry count cleared
    bPlaceCmd := FALSE;                            // 指令撤 / command dropped
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（尺寸类，R79）：映射入 034E（规格不可信，见错误码表反证句）
 *----------------------------------------------------------------------------*)
bNonFin := (fPalletLengthMm <> fPalletLengthMm) OR (ABS(fPalletLengthMm) >= DL_PLS_INF)
        OR (fPalletWidthMm <> fPalletWidthMm) OR (ABS(fPalletWidthMm) >= DL_PLS_INF)
        OR (fCaseLengthMm <> fCaseLengthMm) OR (ABS(fCaseLengthMm) >= DL_PLS_INF)
        OR (fCaseWidthMm <> fCaseWidthMm) OR (ABS(fCaseWidthMm) >= DL_PLS_INF)
        OR (fLayerHeightMm <> fLayerHeightMm) OR (ABS(fLayerHeightMm) >= DL_PLS_INF);   // 尺寸非有限汇总 / dimensions non-finite
IF bNonFin THEN
    eState := E_DL_PalletLayerState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_PLS_CODE_FLT_1;                   // 故障级：规格不可信 / fault: specification untrustworthy
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bPlaceCmd := FALSE;                            // 指令撤安全侧 / command dropped, safe side
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜尺寸与层数域闸：尺寸非正会致除零与负坐标倒排（先判后除）
 *----------------------------------------------------------------------------*)
IF (fPalletLengthMm <= DL_PLS_TOL) OR (fPalletWidthMm <= DL_PLS_TOL)
   OR (fCaseLengthMm <= DL_PLS_TOL) OR (fCaseWidthMm <= DL_PLS_TOL)
   OR (fLayerHeightMm <= DL_PLS_TOL)
   OR (nLayersPerPallet < DL_PLS_LAYER_MIN) OR (nLayersPerPallet > DL_PLS_LAYER_MAX) THEN
    eState := E_DL_PalletLayerState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_PLS_CODE_FLT_1;                   // 故障级：尺寸/层数域非法 / fault: dimension or layer domain invalid
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bPlaceCmd := FALSE;                            // 指令撤安全侧 / command dropped, safe side
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜层容量自算（正交与旋转两取向各算一遍）与数量校验：
 *       容量不足绝不硬塞——基本取向与旋转取向都要单独验，取大者不能让旋转层蒙混过关
 *----------------------------------------------------------------------------*)
nCapOrtho := LREAL_TO_INT(fPalletLengthMm / fCaseLengthMm) * LREAL_TO_INT(fPalletWidthMm / fCaseWidthMm);   // 正交取向容量 [件] / orthogonal capacity [pcs]
nCapRot := LREAL_TO_INT(fPalletLengthMm / fCaseWidthMm) * LREAL_TO_INT(fPalletWidthMm / fCaseLengthMm);     // 旋转取向容量 [件] / rotated capacity [pcs]
IF (nCapOrtho < DL_PLS_CELL_MIN) OR (nCapRot < DL_PLS_CELL_MIN) THEN
    eState := E_DL_PalletLayerState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_PLS_CODE_FLT_1;                   // 故障级：任一取向放不下一个箱 / fault: a case does not fit in one orientation
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bPlaceCmd := FALSE;                            // 指令撤安全侧 / command dropped, safe side
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    RETURN;
END_IF
IF (nCasePerLayer < DL_PLS_CELL_MIN) OR (nCasePerLayer > nCapOrtho) THEN
    eState := E_DL_PalletLayerState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_PLS_CODE_FLT_1;                   // 故障级：层容量不足/规格不匹配 / fault: layer capacity or specification mismatch
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bPlaceCmd := FALSE;                            // 指令撤安全侧 / command dropped, safe side
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    RETURN;
END_IF
IF bOddLayerRotate AND (nCasePerLayer > nCapRot) THEN
    eState := E_DL_PalletLayerState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_PLS_CODE_FLT_1;                   // 故障级：旋转层容量不足（奇偶层旋转必用旋转取向）/ fault: rotated layers cannot hold the count
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bPlaceCmd := FALSE;                            // 指令撤安全侧 / command dropped, safe side
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜本层取向与列行数：旋转层箱体足迹长宽互换（足迹互换由矩阵变换真实体现）
 *----------------------------------------------------------------------------*)
bLayerRotated := bOddLayerRotate AND (((nLayerIndex MOD 2) = 0) AND (nLayerIndex >= 1));   // 偶数层旋转（层号 1 基）/ even layers rotate
IF bLayerRotated THEN
    fTargetRotDeg := DL_PLS_ROT90;                 // 目标旋转角 90 度 [度] / target rotation 90 degrees
    nColsEff := LREAL_TO_INT(fPalletWidthMm / fCaseLengthMm);    // 旋转层：列沿托盘宽方向 / rotated: columns run along the pallet width
    nRowsEff := LREAL_TO_INT(fPalletLengthMm / fCaseWidthMm);    // 旋转层：行沿托盘长方向 / rotated: rows run along the pallet length
    nCapEff := nCapRot;                            // 本层容量取旋转取向 [件] / capacity of the rotated orientation [pcs]
    afRotZero[0, 0] := DL_PLS_ZERO;                // rot90 (0,0) = 0 / rot90 (0,0) = 0
    afRotZero[0, 1] := DL_PLS_M_R90_C;             // rot90 (0,1) = -1 / rot90 (0,1) = -1
    afRotZero[0, 2] := DL_PLS_ZERO;                // rot90 平移列 x = 0（运行时平移在阵外补偿）/ rot90 translation x = 0, compensated outside
    afRotZero[1, 0] := DL_PLS_M_R90_S;             // rot90 (1,0) = +1 / rot90 (1,0) = +1
    afRotZero[1, 1] := DL_PLS_ZERO;                // rot90 (1,1) = 0 / rot90 (1,1) = 0
    afRotZero[1, 2] := DL_PLS_ZERO;                // rot90 平移列 y = 0 / rot90 translation y = 0
ELSE
    fTargetRotDeg := DL_PLS_ZERO;                  // 正交层不旋转 [度] / orthogonal layer, no rotation
    nColsEff := LREAL_TO_INT(fPalletLengthMm / fCaseLengthMm);   // 正交层：列沿托盘长方向 / orthogonal: columns along the pallet length
    nRowsEff := LREAL_TO_INT(fPalletWidthMm / fCaseWidthMm);     // 正交层：行沿托盘宽方向 / orthogonal: rows along the pallet width
    nCapEff := nCapOrtho;                          // 本层容量取正交取向 [件] / capacity of the orthogonal orientation [pcs]
    afRotZero[0, 0] := DL_PLS_M_ID_X;              // 恒等阵 (0,0) / identity (0,0)
    afRotZero[0, 1] := DL_PLS_ZERO;                // 恒等阵 (0,1) / identity (0,1)
    afRotZero[0, 2] := DL_PLS_ZERO;                // 恒等阵平移 x = 0 / identity translation x = 0
    afRotZero[1, 0] := DL_PLS_ZERO;                // 恒等阵 (1,0) / identity (1,0)
    afRotZero[1, 1] := DL_PLS_M_ID_Y;              // 恒等阵 (1,1) / identity (1,1)
    afRotZero[1, 2] := DL_PLS_ZERO;                // 恒等阵平移 y = 0 / identity translation y = 0
END_IF
FOR nLoop := 0 TO 2 DO
    afRotZero[2, nLoop] := DL_PLS_ZERO;            // 第三行清零 / third row cleared
END_FOR
afRotZero[2, 2] := DL_PLS_ONE;                     // 齐次项 1（仿射语义要求第三行 0/0/1）/ homogeneous entry 1

(*------------------------------------------------------------------------------
 * 段 7｜层内格位解码与旋转落点：点变换走 FC_DL_Affine2Apply（每拍恰好一次，
 *       禁止复制低层矩阵乘）；旋转层再按托盘长度做阵外平移补偿
 *----------------------------------------------------------------------------*)
nIdx0 := nPosIndex - 1;                            // 零基位置序号 / zero-based index
IF nIdx0 < 0 THEN
    nIdx0 := 0;                                    // 负序号防护 / negative-index guard
END_IF
IF nColsEff < DL_PLS_LAYER_MIN THEN
    nColsEff := DL_PLS_LAYER_MIN;                  // 列数下限防护（防除零）/ column floor guard
END_IF
nRow := (nIdx0 / nColsEff) + 1;                    // 行号（1 基）[行] / row number, 1-based
nCol := nIdx0 - ((nRow - 1) * nColsEff) + 1;       // 列号（1 基）[列] / column number, 1-based
fLocalXMm := INT_TO_LREAL(nCol - 1) * fCaseLengthMm;   // 箱体自身坐标 X [mm] / case-local X [mm]
fLocalYMm := INT_TO_LREAL(nRow - 1) * fCaseWidthMm;    // 箱体自身坐标 Y [mm] / case-local Y [mm]
bApplyOk := FC_DL_Affine2Apply(afM := afRotZero,   // 本拍旋转矩阵 [无量纲+mm] / rotation matrix of this scan
                               fX := fLocalXMm,    // 源点 X [mm] / source X [mm]
                               fY := fLocalYMm,    // 源点 Y [mm] / source Y [mm]
                               fOutX => fOutXMm,   // 变换后 X [mm] / transformed X [mm]
                               fOutY => fOutYMm,   // 变换后 Y [mm] / transformed Y [mm]
                               eErr => uApplyErr,  // 下游错误码暂存 / downstream error code staging
                               bError => bApplyFault,   // 下游故障标志暂存 / downstream fault flag staging
                               bValid => bApplyValid);  // 下游可用标志暂存 / downstream usable flag staging
IF (NOT bApplyValid) OR (NOT bApplyOk) THEN
    eState := E_DL_PalletLayerState.eFault;        // 点变换不可用进故障相 / transform unusable enters fault
    eErr   := DL_PLS_CODE_FLT_1;                   // 故障级：落点不可信（归规格不匹配槽，反证句见头注释）/ fault: pose untrustworthy
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bPlaceCmd := FALSE;                            // 指令撤安全侧 / command dropped, safe side
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    RETURN;
END_IF
IF bLayerRotated THEN
    // 旋转 90 度后箱体沿托盘长方向的足迹 = 箱宽 fCaseWidthMm。源点旋转得 X' ∈ [-(nRowsEff−1)x箱宽, 0]，
    // 平移量必须取「满排跨度 − 一个足迹」= (nRowsEff − 1) x 箱宽，落点才严格落在 [0, 托盘长 − 箱宽]。
    // v1.0.1 修正：原式加 fPalletLengthMm 会整体多推一个箱宽，首行落点越出托盘边界（1200x1000 / 箱 400x300 时
    // 得 {300,600,900,1200}，最大角 1500 > 1200）；末角对齐后才与正交取向的 0 基足迹约定一致。
    fTargetXMm := fOutXMm + INT_TO_LREAL(nRowsEff - 1) * fCaseWidthMm;   // 旋转层阵外平移补偿（跨度减一个足迹）[mm] / rotated translation, span minus one footprint
    fTargetYMm := fOutYMm;                         // 旋转层 Y 直接取变换值 [mm] / rotated Y as transformed
ELSE
    fTargetXMm := fOutXMm;                         // 正交层 X 直接取变换值 [mm] / orthogonal X as transformed
    fTargetYMm := fOutYMm;                         // 正交层 Y 直接取变换值 [mm] / orthogonal Y as transformed
END_IF
fTargetZMm := INT_TO_LREAL(nLayerIndex - 1) * fLayerHeightMm;   // 层高累计（LREAL 承载）[mm] / layer height accumulation
bSpaceWarn := (nCasePerLayer < nCapEff);            // 本层留空位（末层不满常见）/ empty slots in this layer

(*------------------------------------------------------------------------------
 * 段 8｜超时判定（各格位独立计时，指令撤后定时器自然复位，禁相内累计）
 *----------------------------------------------------------------------------*)
bGripTimedOut := (eState = E_DL_PalletLayerState.eWaitGrip) AND fbTonGrip.Q AND (NOT bGripDone);   // 超时命中 / timeout hit
IF bGripTimedOut AND (nRetryCnt < DL_PLS_RETRY_MAX) THEN
    nRetryCnt := nRetryCnt + 1;                    // 首次超时：重试计数 +1 [次] / first timeout, retry once
    bRearm := TRUE;                                // 定时器重装：下一拍强制 IN 为 FALSE 一拍再重新计时 / re-arm the timer with one FALSE sample
    eState := E_DL_PalletLayerState.ePlace;        // 回出指令相重发（定时器随之复位）/ re-issue, the timer re-arms
    eErr := DL_PLS_CODE_INFO_2;                    // 信息级：取放超时重试 / info: timeout retried
    bError := FALSE;                               // 信息级不置 bError（R45/R101）/ info never raises bError
ELSIF bGripTimedOut AND (nRetryCnt >= DL_PLS_RETRY_MAX) THEN
    bPlaceCmd := FALSE;                            // 二次超时撤指令（安全侧）/ second timeout drops the command
    eState := E_DL_PalletLayerState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_PLS_CODE_FLT_2;                   // 故障级：超时重试耗尽，垛型中断 / fault: retries exhausted, pallet pattern broken
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 位姿不可用 / poses unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜状态机：CASE 含 ELSE 兜底（非法状态 → 0350 + 撤指令 + 许可撤）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_PalletLayerState.eIdle:
        bPlaceCmd := FALSE;                        // 待机指令撤 / command dropped in idle
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        bLayerDone := FALSE;                       // 层完成标志撤 / layer-done flag withdrawn
        bPalletDone := FALSE;                      // 垛完成标志撤 / pallet-done flag withdrawn
        nLayerIndex := 0;                          // 层号清 / layer index cleared
        nPosIndex := 1;                            // 位置序号预置 1，便于首件定位 / position index preset to 1
        nCaseCount := 0;                           // 本垛件数清 / pallet case count cleared
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF fbStart.Q THEN
            eState := E_DL_PalletLayerState.eWaitCase;   // 启动上升沿进等来料 / start edge enters waiting
            nLayerIndex := 1;                      // 从第 1 层开始 / start from layer 1
            nPosIndex := 1;                        // 从第 1 位开始 / start from position 1
            nRetryCnt := 0;                        // 重试计数清 / retry count cleared
            bFirstScan := FALSE;                   // 首拍标志清除 / first-scan flag cleared
        END_IF

    E_DL_PalletLayerState.eWaitCase:
        bPlaceCmd := FALSE;                        // 等来料不出指令 / no command while waiting
        bValid := TRUE;                            // 位姿已算好可用 / the pose is ready and usable
        bError := FALSE;                           // 等料相无故障 / no fault while waiting
        eErr := 16#0000_0000;                      // 等料相先清码 / clear the code first
        IF NOT bCaseReady THEN
            IF bSpaceWarn THEN
                eErr := DL_PLS_CODE_INFO_1;        // 信息级：本层留空位提示 / info: empty slots in this layer
            END_IF
        ELSE
            eState := E_DL_PalletLayerState.ePlace;   // 来料在位出指令（退出条件一）/ case ready, first exit
            nRetryCnt := 0;                        // 新格位重试计数清 / retry count cleared for the new cell
        END_IF
        IF bStop THEN
            eState := E_DL_PalletLayerState.eIdle; // 停止只在等来料相生效（安全侧：不在抓取中停，退出条件二）/ stop honoured here only
            bValid := FALSE;                       // 停止闸显式不可用 / explicit FALSE on the stop gate
            bPlaceCmd := FALSE;                    // 指令撤 / command dropped
        END_IF

    E_DL_PalletLayerState.ePlace:
        bPlaceCmd := TRUE;                         // 取放指令置位 / pick-and-place command raised
        bValid := TRUE;                            // 位姿可用 / poses usable
        bError := FALSE;                           // 出指令相无故障（超时已由段 8 处置）/ no fault here, timeouts handled earlier
        IF eErr <> DL_PLS_CODE_INFO_2 THEN
            eErr := 16#0000_0000;                  // 保留重试提示一拍，其余清码 / keep the retry hint for one scan
        END_IF
        eState := E_DL_PalletLayerState.eWaitGrip; // 无条件进等反馈相（指令保持）/ always enter the feedback wait

    E_DL_PalletLayerState.eWaitGrip:
        bPlaceCmd := TRUE;                         // 指令保持到反馈 / command held until feedback
        bValid := TRUE;                            // 位姿可用 / poses usable
        bError := FALSE;                           // 等反馈相无故障 / no fault while waiting
        IF bGripDone THEN
            nCaseCount := nCaseCount + 1;          // 本垛已放件数 +1 [件] / pallet case count increments
            nPosIndex := nPosIndex + 1;            // 位置序号推进 / position index advances
            nRetryCnt := 0;                        // 重试计数清 / retry count cleared
            bPlaceCmd := FALSE;                    // 反馈到即撤指令 / command dropped on feedback
            IF nPosIndex > nCasePerLayer THEN
                eState := E_DL_PalletLayerState.eLayerEnd;   // 本层放满进层边界 / layer full, enter the layer boundary
            ELSE
                eState := E_DL_PalletLayerState.eWaitCase;   // 本层未满等下一件 / next case in the same layer
            END_IF
        END_IF

    E_DL_PalletLayerState.eLayerEnd:
        bPlaceCmd := FALSE;                        // 层边界指令撤 / command dropped at the layer boundary
        bLayerDone := TRUE;                        // 层完成标志置位 / layer-done flag raised
        bValid := TRUE;                            // 状态可用 / status usable
        bError := FALSE;                           // 层边界无故障 / no fault at the boundary
        eErr := 16#0000_0000;                      // 层边界先清码 / clear the code first
        IF bSpaceWarn THEN
            eErr := DL_PLS_CODE_INFO_1;            // 信息级：本层留空位 / info: empty slots in this layer
        END_IF
        IF bStop THEN
            eState := E_DL_PalletLayerState.eIdle; // 层边界是合法停止点（退出条件一）/ the layer boundary is a legal stop point
            bLayerDone := FALSE;                   // 层完成标志撤 / layer-done flag withdrawn
            bValid := FALSE;                       // 停止闸显式不可用 / explicit FALSE on the stop gate
        ELSIF nLayerIndex >= nLayersPerPallet THEN
            eState := E_DL_PalletLayerState.ePalletEnd;   // 末层已满进垛边界（退出条件二）/ last layer done, second exit
        ELSE
            nLayerIndex := nLayerIndex + 1;        // 升层 / next layer
            nPosIndex := 1;                        // 位置序号回 1 / position index rewound
            bLayerDone := FALSE;                   // 层完成标志撤（升层即清）/ layer-done cleared on the layer change
            eState := E_DL_PalletLayerState.eWaitCase;   // 回等来料（退出条件三）/ back to waiting
        END_IF

    E_DL_PalletLayerState.ePalletEnd:
        bPlaceCmd := FALSE;                        // 垛边界指令撤 / command dropped at the pallet boundary
        bPalletDone := TRUE;                       // 垛完成标志置位 / pallet-done flag raised
        bValid := TRUE;                            // 状态可用 / status usable
        bError := FALSE;                           // 垛边界无故障 / no fault at the boundary
        eErr := 16#0000_0000;                      // 垛边界无错 / no error at the boundary
        IF uPalletCount < DL_PLS_CNT_MAX THEN
            uPalletCount := uPalletCount + 1;      // 完成垛数饱和自增 [垛] / saturating pallet increment
        END_IF
        nLayerIndex := 0;                          // 层号回 0（等下次启动）/ layer index reset
        nPosIndex := 1;                            // 位置序号回 1 / position index rewound
        nCaseCount := 0;                           // 本垛件数清 / pallet case count cleared
        // v1.0.1 修正：bPalletDone 在本相置位后不得同拍自撤（同拍置位+撤位 = 脉冲永不外显）。
        // 撤销点统一放在 eIdle 相（下一拍），保证调用方能采到恰好一拍的 TRUE。
        eState := E_DL_PalletLayerState.eIdle;     // 回待机（bPalletDone 由 eIdle 相撤销）/ back to idle, withdrawn by the idle state

    E_DL_PalletLayerState.eFault:
        bPlaceCmd := FALSE;                        // 故障闸撤指令（R72）/ command dropped on the fault gate
        bValid := FALSE;                           // 故障闸显式不可用 / explicit FALSE on the fault gate
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bLayerDone := FALSE;                       // 层完成标志撤 / layer-done flag withdrawn
        IF eErr = 16#0000_0000 THEN
            eErr := DL_PLS_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
        END_IF
        IF bReset THEN
            eState := E_DL_PalletLayerState.eIdle; // 仅复位可退出故障相 / only reset leaves the fault state
        END_IF

    ELSE
        eState := E_DL_PalletLayerState.eFault;    // 非法状态兜底 / illegal-state fallback
        eErr := DL_PLS_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bPlaceCmd := FALSE;                        // 指令撤安全侧 / command dropped, safe side
        bValid := FALSE;                           // 位姿不可用 / poses unusable
        bLayerDone := FALSE;                       // 层完成标志撤 / layer-done flag withdrawn
        bPalletDone := FALSE;                      // 垛完成标志撤 / pallet-done flag withdrawn

END_CASE
END_FUNCTION_BLOCK
