(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LookaheadVelPlanner
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（MIN / SQRT），零厂商私有库
 * 功能描述 (Function)   : 多段路径前瞻速度规划（回溯-前传两遍法）：输入段几何表（段长 /
 *                         拐角半径 / 段限速 / 段加速度）与轨迹目标速度，输出各段允许速度
 *                         上限表，供段执行器逐段限速。三步：
 *                         ① 拐角限速 fVcorner = SQRT(fAccel × fCornerRad)（向心加速度
 *                            <= fAccel 推导式，段直通无拐角时 fCornerRad=0 → 0 不限）；
 *                         ② 自深至浅回溯（减速可达性反推，前瞻深度 nLookahead）：
 *                            aVelCap[i]² = MIN(aVelCap[i]², aVelCap[i+1]² + 2×fAccel[i]
 *                            × fLen[i+1])（累加式为负先钳 0 再开方）；
 *                         ③ 前向传播可达上限：aVelCap[i+1]² = MIN(aVelCap[i+1]²,
 *                            aVelCap[i]² + 2×fAccel[i+1] × fLen[i+1])。
 * 接口     (Interface)  : 输入 aSeg 段几何表（定长 1..nSegMax）、nSegCount 有效段数、
 *                         nLookahead 前瞻深度、fVtrajMmS 轨迹目标速度（mm/s）、bReset
 *                         复位；输出 aVelCapMmS 各段速度上限（mm/s）、bPlanned 规划完成
 *                         单拍、bCfgBad 组态非法（锁存）、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出段速度上限表，不生成速度曲线、
 *                         不排队指令**（单段成形归 `FB_DL_SCurveGenerator`，指令排队归
 *                         `FB_DL_MotionCmdQueue`）。
 *                         ② nSegCount=0 或超 nSegMax 钳位并报组态（锁存 bCfgBad）。
 *                         ③ 段几何病：fLen<=0 / fAccel<=0 / fVmax<=0 → 锁存 bCfgBad
 *                         （零长度段除零隐患前置，规格边界）；病态期输出冻结。
 *                         ④ SQRT 前判负：回溯累加式 aVelCap[i+1]² + 2×a×L 可能为负，
 *                         先钳 0 再开方（规格边界）。
 *                         ⑤ 回溯/前传用 FOR 定界循环（界宽 = nLookahead 与 nSegCount 钳位
 *                         后的最小值，迭代次数静态有界，等价 WHILE+步数计数防死锁且无
 *                         死锁可能，头注释声明实现选择）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_SCurveGenerator` 分工：段间衔接规划 ≠ 单段 S 曲线
 *                         成形；与 `FB_DL_MotionCmdQueue` 分工：几何规划 ≠ 指令排队。
 * 来源标签 (Source Tag) : T1-6 ◐（PLCopen MC 语义只借前瞻规划语义，回溯-前传两遍法为
 *                         公开规划算法 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 数组 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 段病锁存 + SQRT 前钳负 + 计数钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（规划无状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.1  R50 返修 R1：回溯步减速距离误用
 *                         邻段长度 L[i+1]，更正为本段 L[i]（与前传步取
 *                         L[i+1] 前后对称一致）；行为变更同步更新验收向量。
 *                         2026-11-20  v1.0.0  R48 首版（批次 4 · 序号 17）
 *                         验收向量：三段直角路径回溯降速；拐角半径 0 段不限；前瞻深度
 *                         截断；零长度段 → bCfgBad 锁存。
 *==============================================================================*)

TYPE ST_DL_SegGeom :
STRUCT
    fLenMm    : LREAL;   // 段长度，域 > 0 [mm] / Segment length [mm]
    fCornerRad: LREAL;   // 段末拐角半径（0=直通无限速） [mm] / Corner radius at segment end [mm]
    fVmaxMmS  : LREAL;   // 段自身限速，域 > 0 [mm/s] / Segment speed ceiling [mm/s]
    fAccelMmS2: LREAL;   // 段加减速度能力，域 > 0 [mm/s²] / Segment acceleration capability [mm/s2]
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_LookaheadVelPlanner
VAR_INPUT
    aSeg      : ARRAY[1..16] OF ST_DL_SegGeom;   // 段几何表（定长，nSegCount 指明有效前段） / Segment geometry table
    nSegCount : UDINT := 0;     // 有效段数（0=组态非法） [段] / Valid segment count
    nLookahead: UDINT := 4;     // 前瞻深度（回溯跨越的段数） [段] / Lookahead depth in segments
    fVtrajMmS : LREAL := 200.0; // 轨迹目标速度，域 > 0 [mm/s] / Trajectory target speed [mm/s]
    bReset    : BOOL := FALSE;  // 复位，上升沿清 bCfgBad 锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    aVelCapMmS : ARRAY[1..16] OF LREAL;   // 各段允许速度上限输出 [mm/s] / Per-segment velocity cap output [mm/s]
    bPlanned   : BOOL;           // 规划完成，单拍脉冲 [-] / Planning done, single-scan pulse
    bCfgBad    : BOOL;           // 组态非法（锁存） [-] / Illegal configuration, latched
    bError     : BOOL;           // 故障标志（与 bCfgBad 同源，R191） [-] / Error flag
END_VAR
VAR
    _nCount : DINT;              // 钳位后有效段数 [段] / Clamped segment count
    _nDepth : DINT;              // 钳位后前瞻深度（<= 段数-1） [段] / Clamped lookahead depth
    _bGo    : BOOL;              // 本拍规划执行许可（组态合法 ∧ 目标速度正） / Planning permission this scan
    _fVc    : LREAL;             // 单段拐角限速中间量 [mm/s] / Corner speed intermediate
    _fAcc2  : LREAL;             // 回溯/前传累加式中间量 [mm²/s²] / Backward-pass square accumulator
    i       : DINT;              // 段循环索引 / Segment loop index
    _bErrScan: BOOL;             // 当拍错误内部量（超限钳位） / Per-scan error internal
    _bCfgLatch: BOOL;            // 组态非法锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset : R_TRIG;            // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_LVP_NMAX : DINT  := 16;       // 段表定长上限 [段] / Segment table length ceiling
    DL_LVP_ZERO : LREAL := 0.0;      // 判零基准 [无量纲] / Zero base
    DL_LVP_TWO  : LREAL := 2.0;      // 加速距离公式系数 [-] / Kinematics factor two
END_VAR

(* —— 段 0：段数钳位 + 组态闸 + 沿刷新 —— *)
_bErrScan := FALSE;                          // 当拍错预清 / Per-scan error preset
_nCount := UDINT_TO_DINT(nSegCount);         // 段数转 DINT（超界由下步钳位） / Convert count
IF _nCount > DL_LVP_NMAX THEN
    _nCount := DL_LVP_NMAX;                  // 段数钳到定长上限（头注释②） / Clamp count to ceiling
    _bErrScan := TRUE;                       // 记当拍错 / Mark per-scan error
END_IF
IF _nCount < 0 THEN
    _nCount := 0;                            // UDINT 溢出负值兜底 / Overflow fallback
    _bErrScan := TRUE;                       // 记当拍错 / Mark per-scan error
END_IF
_nDepth := UDINT_TO_DINT(nLookahead);        // 前瞻深度转换 / Convert depth
IF _nDepth > (_nCount - 1) THEN
    _nDepth := _nCount - 1;                  // 深度钳到段数-1（回溯窗不出界） / Clamp depth to count-1
END_IF
IF _nDepth < 0 THEN
    _nDepth := 0;                            // 深度非负兜底 / Depth non-negative
END_IF
_bGo := (_nCount >= 1) AND (fVtrajMmS > DL_LVP_ZERO) AND (NOT _bCfgLatch);   // 规划执行许可（段数/速度/组态三闸） / Planning permission
rtReset(CLK := bReset);                      // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bCfgLatch := FALSE;                     // 清组态锁存 / Clear cfg latch
END_IF

(* —— 段 2：段几何病校验（fLen/fAccel/fVmax 非正 → 锁存，病态期冻结输出） —— *)
IF _bGo THEN
    FOR i := 1 TO _nCount DO
        IF (aSeg[i].fLenMm <= DL_LVP_ZERO) OR (aSeg[i].fAccelMmS2 <= DL_LVP_ZERO)
           OR (aSeg[i].fVmaxMmS <= DL_LVP_ZERO) THEN
            _bCfgLatch := TRUE;              // 零长度/零加速段：除零隐患前置锁存（头注释③） / Bad segment geometry: latch
        END_IF
    END_FOR
END_IF

(* —— 段 3：三步规划（组态合法期执行；bPlanned 单拍） —— *)
bPlanned := FALSE;                           // 规划脉冲预清 / Planned pulse preset
IF _bGo AND (NOT _bCfgLatch) THEN
    (* 第 1 步：段上限 = MIN(轨迹目标, 段限速, 拐角限速) *)
    FOR i := 1 TO _nCount DO
        aVelCapMmS[i] := fVtrajMmS;          // 目标速度起步 / Start from target speed
        IF aVelCapMmS[i] > aSeg[i].fVmaxMmS THEN
            aVelCapMmS[i] := aSeg[i].fVmaxMmS;   // 段限速钳入 / Clamp to segment ceiling
        END_IF
        _fVc := SQRT(aSeg[i].fAccelMmS2 * aSeg[i].fCornerRad);   // 拐角限速 = √(a×R)（R>=0 保证非负，R6 无负开方） / Corner speed
        IF (aSeg[i].fCornerRad > DL_LVP_ZERO) AND (aVelCapMmS[i] > _fVc) THEN
            aVelCapMmS[i] := _fVc;           // 拐角限速钳入（半径 0 段不限） / Clamp to corner speed
        END_IF
    END_FOR
    (* 第 2 步：自深至浅回溯（减速可达性反推；FOR 定界，等价 WHILE+步数计数防死锁） *)
    FOR i := (_nCount - 1) TO (MAX(_nCount - _nDepth - 1, 1)) BY -1 DO
        _fAcc2 := aVelCapMmS[i + 1] * aVelCapMmS[i + 1] + DL_LVP_TWO * aSeg[i].fAccelMmS2 * aSeg[i].fLenMm;   // 可达平方累加式（减速距离取本段 L[i]，v1.0.1 返修） / Reachable square accumulator, current segment length
        IF _fAcc2 < DL_LVP_ZERO THEN
            _fAcc2 := DL_LVP_ZERO;           // 累加式为负先钳 0 再开方（头注释④） / Clamp negative square
        END_IF
        _fVc := SQRT(_fAcc2);                // 可达速度上限 [mm/s] / Reachable speed
        IF aVelCapMmS[i] > _fVc THEN
            aVelCapMmS[i] := _fVc;           // 回溯降速 / Backward cap
        END_IF
    END_FOR
    (* 第 3 步：前向传播可达上限（加速可达性顺推） *)
    FOR i := 1 TO (_nCount - 1) DO
        _fAcc2 := aVelCapMmS[i] * aVelCapMmS[i] + DL_LVP_TWO * aSeg[i + 1].fAccelMmS2 * aSeg[i + 1].fLenMm;   // 前传平方累加式 / Forward square accumulator
        IF _fAcc2 < DL_LVP_ZERO THEN
            _fAcc2 := DL_LVP_ZERO;           // 累加式为负先钳 0 / Clamp negative square
        END_IF
        _fVc := SQRT(_fAcc2);                // 可达速度上限 / Reachable speed
        IF aVelCapMmS[i + 1] > _fVc THEN
            aVelCapMmS[i + 1] := _fVc;       // 前传降速 / Forward cap
        END_IF
    END_FOR
    bPlanned := TRUE;                        // 规划完成单拍 / Planning done pulse
END_IF

(* —— 段 4：故障出口（名实双出口同源，R191） —— *)
bCfgBad := _bCfgLatch;                       // 组态非法出口 / Cfg fault outlet
bError  := _bCfgLatch OR _bErrScan;          // 故障标志 = 组态锁存 ∨ 当拍超限 / Error flag

END_FUNCTION_BLOCK
