(*
    FB_DL_WindingLayerCounter —— 卷绕层数计数
    ------------------------------------------------------------------
    分类      : DL_Motion / Winding
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 层数递推为公开几何关系（层数 = (卷径 − 芯径) / (2·厚度)）；
                与算直径件构成「算一个值 / 数一件事」的职责切分；
                交叉校核、饱和钳位、换卷语义、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 由「卷径 + 芯径 + 材料厚度」推算已绕层数与剩余层数，并与卷轴累计圈计数
                交叉校核：两者差超过 1 层即置 bInconsistent，但只提示不报故障——
                打滑/叠绕/测距噪声在薄膜与极片卷绕里是常态，报故障会误停整条线。
                核心防御：① 厚度或芯径非法即故障级 02E7 并冻结层数（厚度在分母上，
                   是本件除零唯一出口）；
                ② 卷径小于芯径即故障级 02E8——物理上不可能，通常是测距件故障或
                   参数填反，此时硬算会得到负层数；
                ③ 层数超上限只钳位并置信息码；④ 剩余层数由上限减去已绕层数，下溢钳 0；
                ⑤ 等效厚度反推的分母用 MAX(|圈数|, 1) 而不是除零闸——圈数为 0 是开机常态；
                ⑥ 圈计数取模长参与校核（层数是标量，方向由 bDirPositive 另行表达），
                   取模长先升位到 LINT 再取负，规避 DINT 最小值取负回绕（R55）。
                职责边界：卷径测量与滤波归测距/卷径件，本件只数层；张力与排线另有专件。
    错误码    : 16#0004_01D3 层数超上限已钳位 / 圈计数与卷径推算不一致（打滑或叠绕，仅提示）——信息级，正常防御
                16#0004_01D4 预留禁用（信息级，不得挪用）
                16#0004_02E7 厚度或芯径非法（<= 0 / 非有限）——故障级，层数冻结
                16#0004_02E8 卷径非有限或小于芯径（含测距件故障）——故障级，层数冻结
                16#0004_02E9 预留禁用（故障级，不得挪用）
    码位总账  : 16#0004_01D3 用 / 16#0004_01D4 预留 ｜ 16#0004_02E7 用 / 16#0004_02E8 用 / 16#0004_02E9 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : fbTrigReset / fbTrigNewRoll 在本体首部无条件刷新；本件无时间量，
                bLayerEdge 为单周期脉冲（每拍先清后置），结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION_BLOCK FB_DL_WindingLayerCounter
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 冻结层数 / enable, FALSE freezes the layer count
    bReset          : BOOL;                   // 复位，上升沿清零（含累计统计）/ reset, rising edge clears everything including the statistics
    bNewRoll        : BOOL;                   // 换卷，上升沿视为换卷（保留累计统计）/ new roll, rising edge starts a new roll while keeping the statistics
    fCoilDiameter   : REAL := 76.2;           // 当前卷径（外部卷径件/测距给出）[mm] / current coil diameter from the measurement block [mm]
    fCoreDiameter   : REAL := 76.2;           // 芯径 [mm]，必须 > 0 / core diameter [mm], must be > 0
    fThickness      : REAL := 0.1;            // 材料厚度（含隔膜/铜箔）[mm]，必须 > 0 / material thickness [mm], must be > 0
    diRevCount      : DINT := 0;              // 卷轴累计圈计数（方向敏感）[圈] / accumulated shaft revolutions, direction sensitive [rev]
    uLayerMax       : UINT := 5000;           // 层数饱和上限 [层]，范围 10~60000 / layer saturation bound [layer], range 10~60000
    bDirPositive    : BOOL := TRUE;           // 当前旋转方向（反向时圈计数按模长校核）/ current rotation direction, magnitude is used for the cross-check
END_VAR
VAR_OUTPUT
    uLayerDone      : UINT;                   // 已绕层数（由卷径推算）[层] / layers wound, derived from the diameter [layer]
    uLayerRemain    : UINT;                   // 剩余层数（相对上限）[层] / remaining layers relative to the bound [layer]
    bLayerEdge      : BOOL;                   // 层数变化单周期脉冲 / single-cycle pulse on a layer change
    bInconsistent   : BOOL;                   // 圈计数与卷径推算不一致（超过 1 层）/ the revolution count disagrees with the diameter estimate by more than one layer
    fThicknessEst   : REAL;                   // 由卷径与圈数反推的等效厚度 [mm] / equivalent thickness reconstructed from diameter and revolutions [mm]
    uRollCount      : UDINT;                  // 累计换卷次数，饱和 [卷] / accumulated roll changes, saturating [roll]
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbTrigNewRoll   : R_TRIG;                 // 换卷上升沿实例，本体首部无条件刷新 / new roll edge instance, refreshed unconditionally
    uLayerPrev      : UINT;                   // 上一拍层数，用于变化沿判定 [层] / previous layer count used by the edge test [layer]
    uLayerMaxEff    : UINT;                   // 钳位后的层数上限 [层] / clamped layer bound [layer]
    nLayerInt       : DINT;                   // 层数整数形态（截断）[层] / integer layer count, truncated [layer]
    fLayerFloat     : REAL;                   // 层数浮点形态 [层] / floating point layer count [layer]
    fRevAbs         : REAL;                   // 圈计数模长 [圈] / magnitude of the revolution count [rev]
    fDen            : REAL;                   // 等效厚度的反推分母（MAX(|圈|,1)）[圈] / denominator of the thickness estimate, at least one [rev]
    liRev           : LINT;                   // 圈计数升位副本（取模长前先升位）[圈] / widened revolution copy before taking the magnitude [rev]
    fDiaDelta       : REAL;                   // 卷径与芯径差 [mm] / diameter difference [mm]
    bInit           : BOOL := FALSE;          // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
END_VAR
VAR CONSTANT
    DL_WLC_LAYER_MIN : UINT := 10;            // 层数上限下限 [层] / layer bound lower limit [layer]
    DL_WLC_LAYER_MAX : UINT := 60000;         // 层数上限上限 [层] / layer bound upper limit [layer]
    DL_WLC_CNT_MAX   : UDINT := 16#FFFF_FFFE; // 换卷计数饱和值 [卷] / roll counter saturation value [roll]
    DL_WLC_TOL_LAYER : REAL := 1.0;           // 交叉校核容差 [层] / cross-check tolerance [layer]
    DL_WLC_ONE       : REAL := 1.0;           // 一值常量，分母下限与容差基底 [无量纲] / one constant used for the divisor floor [dimensionless]
    DL_WLC_TWO       : REAL := 2.0;           // 二值常量，层厚换算用 [无量纲] / two constant used by the thickness conversion [dimensionless]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_WLC_INF_GUARD : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_WLC_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_WLC_CNT_ZERO  : UINT := 0;             // 无符号零常量 [无量纲] / unsigned zero constant [dimensionless]
    DL_WLC_LINT_ZERO : LINT := 0;             // LINT 零常量 [无量纲] / LINT zero constant [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);
fbTrigNewRoll(CLK := bNewRoll);

// 段 2｜输出与错误状态预置（层数与统计为保持量）/ segment 2, preset outputs, the counts are held
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bLayerEdge := FALSE;                          // 单周期脉冲先清 / clear the single-cycle pulse first
bInconsistent := FALSE;                       // 预置一致 / preset consistent

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    uLayerDone := DL_WLC_CNT_ZERO;            // 首扫层数归 0 / layer count starts at zero
    uLayerPrev := DL_WLC_CNT_ZERO;            // 变化沿基准归 0 / the edge reference starts at zero
    uRollCount := 0;                          // 换卷统计清零 / clear the roll statistics
    fThicknessEst := DL_WLC_ZERO;             // 等效厚度清零 / clear the equivalent thickness
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜复位沿：清零全部量（含累计统计）/ segment 4, reset clears everything
IF fbTrigReset.Q THEN
    uLayerDone := DL_WLC_CNT_ZERO;            // 层数清零 / clear the layer count
    uLayerPrev := DL_WLC_CNT_ZERO;            // 变化沿基准清零 / clear the edge reference
    uRollCount := 0;                          // 换卷统计清零 / clear the roll statistics
    fThicknessEst := DL_WLC_ZERO;             // 等效厚度清零 / clear the equivalent thickness
END_IF

// 段 5｜换卷沿：保留累计统计，只重置层数基准 / segment 5, a new roll keeps the statistics
IF fbTrigNewRoll.Q THEN
    uLayerDone := DL_WLC_CNT_ZERO;            // 新卷层数从 0 起 / a new roll starts at zero layers
    uLayerPrev := DL_WLC_CNT_ZERO;            // 变化沿基准重置 / reset the edge reference
    IF uRollCount < DL_WLC_CNT_MAX THEN
        uRollCount := uRollCount + 1;         // 饱和累计换卷次数 / saturating roll counter
    END_IF
END_IF

// 段 6｜使能闸：失能冻结层数 / segment 6, enable gate freezes the counts
IF NOT bEnable THEN
    RETURN;                                   // 失能即出口，输出保持 / disabled is the exit, the outputs are held
END_IF

// 段 7｜厚度与芯径闸（厚度在分母上，是除零唯一出口）/ segment 7, thickness and core gate
IF (fThickness <> fThickness) OR (fThickness <= DL_FLOAT_EPS) OR (fThickness > DL_WLC_INF_GUARD)
   OR (fCoreDiameter <> fCoreDiameter) OR (fCoreDiameter <= DL_FLOAT_EPS) THEN
    eErr := 16#0004_02E7;                     // 厚度或芯径非法故障码 / thickness or core fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    RETURN;                                   // 故障级提前返回，层数冻结 / early return, the layer count is frozen
END_IF

// 段 8｜卷径闸（非有限或小于芯径，物理上不可能）/ segment 8, coil diameter gate
IF (fCoilDiameter <> fCoilDiameter) OR (fCoilDiameter > DL_WLC_INF_GUARD) OR (fCoilDiameter < fCoreDiameter) THEN
    eErr := 16#0004_02E8;                     // 卷径非法故障码 / illegal coil diameter fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    RETURN;                                   // 故障级提前返回，层数冻结 / early return, the layer count is frozen
END_IF

// 段 9｜层数上限钳位（钳位后功能仍可用）/ segment 9, layer bound clamp
uLayerMaxEff := uLayerMax;                    // 取入参副本 / copy the input
IF uLayerMaxEff < DL_WLC_LAYER_MIN THEN
    uLayerMaxEff := DL_WLC_LAYER_MIN;         // 下限钳位 / clamp at the lower limit
    eErr := 16#0004_01D3;                     // 信息级：上限超域已钳位 / info level, the bound was clamped
ELSIF uLayerMaxEff > DL_WLC_LAYER_MAX THEN
    uLayerMaxEff := DL_WLC_LAYER_MAX;         // 上限钳位 / clamp at the upper limit
    eErr := 16#0004_01D3;                     // 信息级：上限超域已钳位 / info level, the bound was clamped
END_IF

// 段 10｜层数推算（分母已由段 7 保证 > 0）/ segment 10, layer computation
fDiaDelta := fCoilDiameter - fCoreDiameter;   // 卷径与芯径差 [mm] / diameter difference [mm]
fLayerFloat := fDiaDelta / (DL_WLC_TWO * fThickness); // 层数 = 差 / (2·厚度) [层] / layers equal the difference divided by twice the thickness [layer]
IF fLayerFloat > UINT_TO_REAL(uLayerMaxEff) THEN
    fLayerFloat := UINT_TO_REAL(uLayerMaxEff); // 超上限钳位 / clamp at the bound
    eErr := 16#0004_01D3;                     // 信息级：层数超上限已钳位 / info level, the layer count was clamped
END_IF
IF fLayerFloat < DL_WLC_ZERO THEN
    fLayerFloat := DL_WLC_ZERO;               // 卷径等于芯径时层数为 0 / a diameter equal to the core gives zero layers
END_IF
nLayerInt := REAL_TO_DINT(fLayerFloat);       // 截断取整为层数 [层] / truncate to an integer layer count [layer]
IF nLayerInt < 0 THEN
    nLayerInt := 0;                           // 防御性下界 / defensive floor
END_IF
uLayerDone := DINT_TO_UINT(nLayerInt);        // 发布已绕层数 [层] / publish the wound layer count [layer]

// 段 11｜剩余层数（下溢钳 0，绝不回绕）/ segment 11, remaining layers without underflow
IF uLayerDone >= uLayerMaxEff THEN
    uLayerRemain := DL_WLC_CNT_ZERO;          // 已到上限即剩余 0 / nothing remains at the bound
ELSE
    uLayerRemain := uLayerMaxEff - uLayerDone; // 剩余层数 [层] / remaining layers [layer]
END_IF

// 段 12｜交叉校核：圈计数取模长（先升 LINT 再取负，规避 DINT 最小值回绕）/ segment 12, cross-check
liRev := DINT_TO_LINT(diRevCount);            // 先升位，再取模长 / widen first, then take the magnitude
IF liRev < DL_WLC_LINT_ZERO THEN
    liRev := -liRev;                          // LINT 域取负安全 / negating inside LINT is safe
END_IF
fRevAbs := LINT_TO_REAL(liRev);               // 圈计数模长 [圈] / revolution magnitude [rev]
IF ABS(fLayerFloat - fRevAbs) > DL_WLC_TOL_LAYER THEN
    bInconsistent := TRUE;                    // 超过 1 层即提示（打滑/叠绕/噪声均可能）/ more than one layer apart is reported
    eErr := 16#0004_01D3;                     // 信息级：仅提示，不报故障（报故障会误停整线）/ info level only, a fault would stop the whole line
END_IF

// 段 13｜等效厚度反推（分母用 MAX(|圈|,1)，不用除零闸）/ segment 13, equivalent thickness
fDen := MAX(fRevAbs, DL_WLC_ONE);             // 圈数为 0 是开机常态，分母取下限 1 / zero revolutions is normal at start-up, use a floor of one
fThicknessEst := fDiaDelta / (DL_WLC_TWO * fDen); // 等效厚度 [mm] / equivalent thickness [mm]

// 段 14｜层数变化沿（单周期脉冲）/ segment 14, layer change edge
IF uLayerDone <> uLayerPrev THEN
    bLayerEdge := TRUE;                       // 层数变化即置单拍脉冲 / raise the single-cycle pulse on any change
    uLayerPrev := uLayerDone;                 // 更新比较基准 / update the reference
END_IF
END_FUNCTION_BLOCK
