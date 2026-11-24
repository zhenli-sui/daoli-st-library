(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TrayerNestingCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 电芯托盘堆叠嵌套调度（层 × 列网格占位）。
 *                         按"层从下往上、列从左往右"的蛇形无关直线序逐格占位；每来一颗电芯占一格，
 *                         列到边界回卷到下一层首列；**NG 通道避让**：某一列指定为 NG 列时，
 *                         该列在每一层都被整体跳过（整列不占位、不计入容量）；
 *                         合法格占满即判"栈满"并锁存 bTrayFull，等待取盘沿（bTrayTaken）或复位沿解除。
 *                         **语义复用（非实例复用）**：本件按 R47 批次"批内零 .st 文件级依赖"纪律，
 *                         不实例化 FB_DL_LifoStack，而是复用其三条已固化语义——
 *                         ① 入栈前判满、满则拒入并锁存；② 出栈仅由显式"取走"沿触发；
 *                         ③ 满/空判定以计数与容量比较为准，不以指针相等为准。
 *                         验收向量：
 *                           ① 3 层 × 4 列、NG 列 = 2 → 容量 = 3×(4−1) = 9 格
 *                           ② 2 层 × 2 列、NG 列 = 1 → 容量 = 2×(2−1) = 2 格
 *                           ③ 2 层 × 2 列、NG 列 = 0 → 容量 = 4 格
 *                           ④ 任一层列数 = 0 → 组态非法锁存，不进入占位
 * 接口     (Interface)  : 入 bStart 启动沿、bTrayTaken 取盘沿（解除栈满）、iLayerCnt 层数、iColCnt 列数、
 *                         iNgCol 避让列号（1 基，0 = 无）、bCellPresent 电芯到位沿、bPlaceAllowed 上料允许
 *                         （外部互锁）、bReset 故障复位沿；
 *                         出 iLayerOut / iColOut 当前待占格坐标（1 基）、bPlaceCmd 占位脉冲（单拍）、
 *                         bLayerDone 换层脉冲（单拍）、bTrayFull 栈满锁存、iPlacedCnt 已占格数、
 *                         bNgSkipped 当拍发生 NG 列跳过、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只算"下一颗电芯放哪一格"，不驱动吸盘/夹具/
 *                         升降台伺服**；取放动作由执行件（I_DL_Cylinder 族 / 运动件）承担；
 *                         ② **网格组态闸**：层数或列数 ≤ 0 或超上限（100×100）→ 锁存 eCfgIllegal，
 *                         不进入占位（零容量网格会让"栈满"永假，属静默失效 R179）；
 *                         ③ **NG 列域闸**：iNgCol 越界（<0 或 > 列数）→ 锁存 eCfgIllegal；
 *                         ④ **索引越界钳位**：前进循环带 _uGuard 计数器（上界 = 总格数 + 列数 + 2），
 *                         循环必然收敛，绝不靠"数据一定合法"保证终止；
 *                         ⑤ eFault 可迁出：bReset 上升沿 → eIdle（解除式自证：bReset 为外部引脚，
 *                         不受任何锁存量门控，恒可达）；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"托盘格位调度与栈满判定"。不接管：电芯取放动作时序（顺控件）、
 *                         NG 电芯的下游分选（分选件）、托盘身份绑定（RFID 件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P2（托盘嵌套调度，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 组态双闸 + 循环计数器 + 索引钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 1 · 序号 4）
 *==============================================================================*)

TYPE E_DL_TncState :
(
    eIdle  := 0,    // 待机相（等启动或等取盘） / Idle, awaiting start or tray removal
    eNest  := 10,   // 占位相（逐颗占格） / Nesting, one cell per cell-in
    eFull  := 20,   // 栈满相（锁存等取盘） / Full, latched awaiting tray removal
    eFault := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_TncCause :
(
    eNone      := 0,   // 无异常 / No anomaly
    eCfgIllegal:= 1,   // 组态非法（层数/列数/NG 列越域） / Illegal grid configuration
    eFullNoCell    := 2,   // 栈满后仍有电芯到位（拒入） / Cell arrived while full, rejected
    eRejectNoPermit:= 3,   // 上料允许缺失致电芯被拒 / Cell rejected, place permit absent
    ePhaseBad      := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrayerNestingCtrl
VAR_INPUT
    bStart       : BOOL := FALSE;   // 启动沿，进入占位相 [-] / Start edge, enters nesting
    bTrayTaken   : BOOL := FALSE;   // 取盘沿，解除栈满并清零计数 [-] / Tray-removed edge, clears the full latch
    iLayerCnt    : INT := 1;        // 层数，域 1..100 [层] / Layer count, domain 1..100
    iColCnt      : INT := 1;        // 每层列数，域 1..100 [列] / Columns per layer, domain 1..100
    iNgCol       : INT := 0;        // NG 避让列号（1 基；0 = 不避让） [列] / NG column index, 1-based, 0 = none
    bCellPresent : BOOL := FALSE;   // 电芯到位信号（上升沿占一格） [-] / Cell-present signal, rising edge takes one cell
    bPlaceAllowed: BOOL := FALSE;   // 上料允许（外部互锁，FALSE 时拒占位） [-] / Place permit from the external interlock
    bReset       : BOOL := FALSE;   // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    iLayerOut  : INT := 0;                  // 当前待占格所在层（1 基） [层] / Current target layer, 1-based
    iColOut    : INT := 0;                  // 当前待占格所在列（1 基） [列] / Current target column, 1-based
    bPlaceCmd  : BOOL := FALSE;             // 占位脉冲，单拍 [-] / Place command, single-scan pulse
    bLayerDone : BOOL := FALSE;             // 换层脉冲，单拍 [-] / Layer-change pulse, single-scan
    bTrayFull  : BOOL := FALSE;             // 栈满锁存（等取盘或复位） [-] / Tray full, latched
    iPlacedCnt : INT := 0;                  // 已占格数 [格] / Occupied cell count
    bNgSkipped : BOOL := FALSE;             // 当拍发生过 NG 列跳过 [-] / An NG column was skipped this scan
    eState     : E_DL_TncState := E_DL_TncState.eIdle;   // 相出口 [-] / Phase outlet
    eCause     : E_DL_TncCause := E_DL_TncCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError     : BOOL := FALSE;             // 故障标志 [-] / Error flag
END_VAR
VAR
    _eState    : E_DL_TncState := E_DL_TncState.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_TncCause := E_DL_TncCause.eNone;   // 成因锁存量 / Latched cause
    _bFault    : BOOL := FALSE;             // 故障锁存位 / Latched fault bit
    _bFull     : BOOL := FALSE;             // 栈满锁存位（与 bTrayFull 同源） / Latched full bit
    _iLayer    : INT := 1;                  // 内部层指针（1 基） / Internal layer cursor
    _iCol      : INT := 1;                  // 内部列指针（1 基） / Internal column cursor
    _iPlaced   : INT := 0;                  // 内部已占格计数 / Internal occupied counter
    _iCap      : INT := 0;                  // 本盘合法格容量（不含 NG 列） / Legal capacity excluding the NG column
    _bPlaceCmd : BOOL := FALSE;             // 占位脉冲内部位（单拍） / Internal place pulse
    _bLayerDone: BOOL := FALSE;             // 换层脉冲内部位（单拍） / Internal layer-change pulse
    _bNgSkipped: BOOL := FALSE;             // NG 跳过内部位（单拍） / Internal NG-skip flag
    _bCfgBad   : BOOL := FALSE;             // 组态非法当拍量 / Illegal configuration this scan
    _bAdvDone  : BOOL := FALSE;             // 前进循环收敛标志 / Advance-loop convergence flag
    _uGuard    : UINT := 0;                 // 前进循环计数器（防死循环） / Advance-loop guard counter
    rtStart    : R_TRIG;                    // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtReset    : R_TRIG;                    // 复位沿实例，段 0 无条件调用 / Reset edge instance
    rtTaken    : R_TRIG;                    // 取盘沿实例，段 0 无条件调用 / Tray-removed edge instance
    rtCell     : R_TRIG;                    // 电芯到位沿实例，段 0 无条件调用 / Cell-present edge instance
END_VAR
VAR CONSTANT
    DL_TNC_MAX_LAYER : INT := 100;          // 层数上限（超限判组态非法） [层] / Layer upper bound
    DL_TNC_MAX_COL   : INT := 100;          // 列数上限（超限判组态非法） [列] / Column upper bound
    DL_TNC_GUARD_MAX : UINT := 20002;       // 前进循环守护上限（100×100 + 100 + 2） [次] / Advance guard limit
END_VAR

(* —— 段 0：组态闸 + 四枚沿实例无条件周期刷新（R228A） —— *)
_bCfgBad := (iLayerCnt <= 0) OR (iLayerCnt > DL_TNC_MAX_LAYER)          // 层数须在 1..100 / Layer count within 1..100
         OR (iColCnt <= 0) OR (iColCnt > DL_TNC_MAX_COL)                // 列数须在 1..100 / Column count within 1..100
         OR (iNgCol < 0) OR (iNgCol > iColCnt);                          // NG 列号须为 0 或落在列域内 / NG index within the column domain
rtStart(CLK := bStart);                                                  // 启动沿 / Start edge
rtReset(CLK := bReset);                                                  // 复位沿 / Reset edge
rtTaken(CLK := bTrayTaken);                                              // 取盘沿 / Tray-removed edge
rtCell(CLK := bCellPresent);                                             // 电芯到位沿 / Cell-present edge

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_iPlaced 不入清单，R107） —— *)
_bPlaceCmd  := FALSE;                                                    // 占位脉冲预清 / Place pulse preset
_bLayerDone := FALSE;                                                    // 换层脉冲预清 / Layer pulse preset
_bNgSkipped := FALSE;                                                    // NG 跳过标志预清 / NG-skip preset
bError      := FALSE;                                                    // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸（非法即锁存，不进入占位） —— *)
IF _bCfgBad THEN
    _bFault := TRUE;                                                     // 锁存 / Latch
    _eCause := E_DL_TncCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
    _eState := E_DL_TncState.eFault;                                     // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链与取盘链（两条出口显式写出，R228B） —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;                                                   // 清故障锁存 / Clear fault latch
    _bFull   := FALSE;                                                   // 清栈满锁存 / Clear full latch
    _eCause  := E_DL_TncCause.eNone;                                     // 清成因 / Clear cause
    _iPlaced := 0;                                                       // 计数清零 / Clear the counter
    _iLayer  := 1;                                                       // 层指针回 1 / Layer cursor back to 1
    _iCol    := 1;                                                       // 列指针回 1 / Column cursor back to 1
    _eState  := E_DL_TncState.eIdle;                                     // 回待机相 / Back to idle
END_IF
IF rtTaken.Q AND (_eState <> E_DL_TncState.eFault) THEN
    _bFull   := FALSE;                                                   // 取盘解除栈满 / Tray removal clears the full latch
    _iPlaced := 0;                                                       // 计数清零 / Clear the counter
    _iLayer  := 1;                                                       // 层指针回 1 / Layer cursor back to 1
    _iCol    := 1;                                                       // 列指针回 1 / Column cursor back to 1
    _eState  := E_DL_TncState.eIdle;                                     // 回待机相 / Back to idle
END_IF

(* —— 段 4：容量计算（总格数 − NG 列整列格数；组态合法时恒 ≥ 0） —— *)
IF NOT _bCfgBad THEN
    _iCap := iLayerCnt * iColCnt;                                        // 总格数 / Total cells
    IF iNgCol > 0 THEN
        _iCap := _iCap - iLayerCnt;                                      // 扣除 NG 列整列 / Deduct the whole NG column
    END_IF
END_IF

(* —— 段 5：相迁移（只在无故障时推进；每相出口条件显式成对） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    CASE _eState OF

    E_DL_TncState.eIdle:
        IF rtStart.Q THEN
            _iLayer := 1;                                                // 层指针首层 / First layer
            IF (iNgCol = 1) AND (iColCnt >= 2) THEN
                _iCol := 2;                                              // 首列即 NG：起始列右移一格 / First column is NG, start at column 2
            ELSE
                _iCol := 1;                                              // 否则首列起步 / Otherwise start at column 1
            END_IF
            _iPlaced := 0;                                               // 计数清零 / Counter cleared
            _eState := E_DL_TncState.eNest;                              // 进占位相 / Enter nesting
        END_IF

    E_DL_TncState.eNest:
        IF rtCell.Q AND bPlaceAllowed THEN
            _bPlaceCmd := TRUE;                                          // 占位脉冲（内部位，段 7 单点映射） / Internal place pulse
            _iPlaced := _iPlaced + 1;                                    // 占位计数 +1 / Increment the counter

            (* 前进到下一合法格：列 +1，越界回卷到下一层首列，NG 列整体跳过 *)
            _uGuard  := 0;                                               // 守护计数器归零 / Guard reset
            _bAdvDone:= FALSE;                                           // 收敛标志复位 / Convergence flag reset
            WHILE (NOT _bAdvDone) AND (_uGuard < DL_TNC_GUARD_MAX) DO
                _uGuard := _uGuard + 1;                                  // 计数器推进 / Guard advance
                _iCol := _iCol + 1;                                      // 列前进一格 / Column step
                IF _iCol > iColCnt THEN
                    _iCol := 1;                                          // 列回卷 / Column wrap
                    _iLayer := _iLayer + 1;                              // 换层 / Next layer
                    _bLayerDone := TRUE;                                 // 换层脉冲（内部位） / Internal layer pulse
                END_IF
                IF _iLayer > iLayerCnt THEN
                    _bAdvDone := TRUE;                                   // 层耗尽：指针停（不再寻格） / Layers exhausted
                ELSIF (iNgCol > 0) AND (_iCol = iNgCol) THEN
                    _bNgSkipped := TRUE;                                 // NG 列：跳过并继续寻格 / NG column skipped, keep seeking
                ELSE
                    _bAdvDone := TRUE;                                   // 找到合法格 / Legal cell found
                END_IF
            END_WHILE

            IF _iPlaced >= _iCap THEN
                _bFull   := TRUE;                                        // 栈满锁存（入栈前判满语义） / Full latch, pre-push check
                _eState  := E_DL_TncState.eFull;                         // 进栈满相 / Enter full phase
            END_IF
        ELSIF rtCell.Q AND (NOT bPlaceAllowed) THEN
            _eCause := E_DL_TncCause.eRejectNoPermit;                    // 归因：互锁未放开致电芯被拒 / Cause: cell rejected, permit absent
        END_IF

    E_DL_TncState.eFull:
        IF rtCell.Q THEN
            _eCause := E_DL_TncCause.eFullNoCell;                        // 满盘期电芯到位：拒入并留痕 / Cell during full: rejected and recorded
        END_IF

    E_DL_TncState.eFault:
        ;                                                                // 故障相：由段 3 复位沿迁出 / Exit handled by the reset edge in stage 3

    ELSE
        _eCause := E_DL_TncCause.ePhaseBad;                              // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                                 // 锁存 / Latch
        _eState := E_DL_TncState.eFault;                                 // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 6：栈满与故障的交汇（满盘后故障优先展示，满锁存保持） —— *)
IF _bFull AND (_eState = E_DL_TncState.eNest) THEN
    _eState := E_DL_TncState.eFull;                                      // 满锁存与相对齐 / Align the phase with the full latch
END_IF

(* —— 段 7：出口单点映射（名实双出口，R191） —— *)
iLayerOut  := _iLayer;                                                   // 待占层层号 / Target layer
iColOut    := _iCol;                                                     // 待占格列号 / Target column
bPlaceCmd  := _bPlaceCmd;                                                // 占位脉冲单拍出口 / Place pulse outlet
bLayerDone := _bLayerDone;                                               // 换层脉冲单拍出口 / Layer pulse outlet
bNgSkipped := _bNgSkipped;                                               // NG 跳过标志出口 / NG-skip outlet
bTrayFull  := _bFull;                                                    // 栈满出口 / Full outlet
iPlacedCnt := _iPlaced;                                                  // 已占格数出口 / Occupied count outlet
eState     := _eState;                                                   // 相出口 / Phase outlet
eCause     := _eCause;                                                   // 成因出口 / Cause outlet
bError     := _bFault OR _bCfgBad;                                       // 故障标志 = 锁存或组态非法 / Error = latch or illegal config

END_FUNCTION_BLOCK
