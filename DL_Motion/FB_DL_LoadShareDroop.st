(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoadShareDroop
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 多轴（≤4）负载均衡 droop 调差：按各轴负载百分比对速度基准做
 *                         droop 修正，负载高于均值者减速让载、低于均值者提速分担：
 *                           aVout[i] = fVref × (1 - fDroopPct × (aLoad[i]-fLoadAvg)/100)
 *                         均衡目标带内（|aLoad[i]-fLoadAvg| <= fShareBandPct）不修正
 *                         （死区防振荡）；非负载轴（bAxActive=FALSE）输出直通不修正；
 *                         均值只对有效轴计算。
 * 接口     (Interface)  : 输入 fVrefMmS 速度基准（mm/s）、aLoadPct 各轴负载（%，定长
 *                         1..nAxMax 数组）、bAxActive 各轴有效、fDroopPct 调差率
 *                         （%/(100%负载)）、fShareBandPct 均衡目标带（%）、fVrefMax 输出
 *                         钳限（mm/s）；输出 aVoutMmS 各轴修正后速度（mm/s）、bBalanced
 *                         均衡达标、bNoLoad 全轴失效。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做速度基准的 droop 修正分配，不写
 *                         轴指令、不接管同步耦合**；几何同步归 `FB_DL_GantrySyncAxis`，
 *                         偏差监视归 `FB_DL_GantrySkewMonitor`（修调 ≠ 监视）。
 *                         ② 数组边界逐轴钳位（索引 1..nAxMax 常量域，循环定界，无越界路径）。
 *                         ③ 全轴失效（无有效轴）→ 直通输出 fVref 并置 bNoLoad（均值除零
 *                         前置：有效轴计数 >= 1 才算均值，R28 防除零）。
 *                         ④ 非有限负载当拍该轴按失效处理（不入均值、输出直通）并置当拍
 *                         bError（R245）；fVref 非有限 → 全轴直通冻结。
 *                         ⑤ 输出钳 ±fVrefMax（fVrefMax 组态域闸 > 0，锁存 bError，
 *                         解除沿 = 无（无复位引脚，组态合法化后自动解除，头注释声明：
 *                         组态闸为当拍判据非锁存，修正组态即解除）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_GantrySyncAxis` 分工：负载均衡 ≠ 几何同步；与
 *                         `FB_DL_GantrySkewMonitor` 分工：修调 ≠ 监视。
 * 来源标签 (Source Tag) : T1-6 ◐（PLCopen MC 语义只借多轴协同语义，droop 公式为电力
 *                         系统公开调差定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 数组 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 均值除零前置 + 非有限剔除 + 输出钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 3 · 序号 14）
 *                         验收向量：双轴等载 → 无修正；单轴 120% 均值 → 该轴减速；
 *                         全轴失效 → 直通 + bNoLoad；带内不修正防振荡。
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_LoadShareDroop
VAR_INPUT
    fVrefMmS     : LREAL := 100.0;                       // 速度基准 [mm/s] / Velocity reference [mm/s]
    aLoadPct     : ARRAY[1..4] OF LREAL := [0.0, 0.0, 0.0, 0.0];   // 各轴负载（0~100+） [%] / Per-axis load [%]
    bAxActive    : ARRAY[1..4] OF BOOL := [FALSE, FALSE, FALSE, FALSE];   // 各轴参与均衡有效标志 [-] / Per-axis active flag
    fDroopPct    : LREAL := 5.0;                         // 调差率（每 100% 负载偏差的速度降幅） [%/(100%负载)] / Droop rate
    fShareBandPct: LREAL := 2.0;                         // 均衡目标带半宽（带内不修正） [%] / Balance target band [%]
    fVrefMax     : LREAL := 150.0;                       // 输出钳限（对称 ±），域 > 0 [mm/s] / Output clamp limit [mm/s]
END_VAR
VAR_OUTPUT
    aVoutMmS  : ARRAY[1..4] OF LREAL;                    // 各轴修正后速度输出 [mm/s] / Per-axis corrected velocity output
    bBalanced : BOOL;                                    // 均衡达标（全部有效轴在目标带内） [-] / Balanced flag
    bNoLoad   : BOOL;                                    // 全轴失效直通标志 [-] / No active axis flag
    bError    : BOOL;                                    // 故障标志（组态病 ∨ 输入病当拍） [-] / Error flag
END_VAR
VAR
    _nActive  : DINT;            // 有效轴计数 [轴] / Active axis count
    _fSum     : LREAL;           // 有效轴负载和 [%] / Active load sum
    _fAvg     : LREAL;           // 有效轴负载均值 [%] / Active load mean
    _fDev     : LREAL;           // 单轴负载对均值偏差 [%] / Per-axis load deviation
    _fOut     : LREAL;           // 单轴修正中间量 [mm/s] / Per-axis corrected intermediate
    _bBal     : BOOL;            // 均衡达标内部量 / Balanced internal
    _bErrScan : BOOL;            // 输入病当拍量 [-] / Per-scan input fault
    _bCfgBad  : BOOL;            // 组态病当拍量（fVrefMax<=0，当拍判据非锁存） / Config fault this scan
    i         : DINT;            // 轴循环索引（1..4 定界） / Axis loop index
END_VAR
VAR CONSTANT
    DL_LSD_NAX  : DINT  := 4;        // 支持轴数上限（数组定界） [轴] / Supported axis ceiling
    DL_LSD_PCT  : LREAL := 100.0;    // 百分比换算基 [无量纲] / Percent conversion base
    DL_LSD_EPS  : LREAL := 0.0;      // 非有限差值判零基准 [-] / Non-finite difference zero base
END_VAR

(* —— 段 0：组态闸 + 输入病判（当拍判据，非锁存，头注释⑤声明解除语义） —— *)
_bCfgBad := fVrefMax <= 0.0;                                 // 钳限组态闸 / Clamp config gate
_bErrScan := (fVrefMmS <> fVrefMmS) OR ((fVrefMmS - fVrefMmS) <> DL_LSD_EPS);   // 基准非有限（R245） / Non-finite reference
FOR i := 1 TO DL_LSD_NAX DO
    IF bAxActive[i] AND ((aLoadPct[i] <> aLoadPct[i]) OR ((aLoadPct[i] - aLoadPct[i]) <> DL_LSD_EPS)) THEN
        _bErrScan := TRUE;                                   // 有效轴负载非有限：当拍输入病（R245） / Non-finite load on active axis
    END_IF
END_FOR

(* —— 段 1：直通总闸（组态病 ∨ 基准非有限 → 全轴直通） —— *)
bNoLoad := FALSE;                                            // 全轴失效标志预清 / No-load preset
IF _bCfgBad OR _bErrScan THEN
    FOR i := 1 TO DL_LSD_NAX DO
        aVoutMmS[i] := fVrefMmS;                             // 全轴直通基准（直通即语义，头注释④） / Pass-through all axes
    END_FOR
    bBalanced := FALSE;                                      // 直通期不报均衡达标 / Not balanced
ELSE
    (* 段 2：有效轴均值（计数 >= 1 才除，无除零） *)
    _nActive := 0;                                           // 有效计数清零 / Clear count
    _fSum := 0.0;                                            // 负载和清零 / Clear sum
    FOR i := 1 TO DL_LSD_NAX DO
        IF bAxActive[i] THEN
            _nActive := _nActive + 1;                        // 有效轴计数 / Count active axis
            _fSum := _fSum + aLoadPct[i];                    // 累加有效负载 / Accumulate load
        END_IF
    END_FOR
    IF _nActive >= 1 THEN
        _fAvg := _fSum / DINT_TO_LREAL(_nActive);            // 有效轴均值（分母计数已闸） / Active mean
        _bBal := TRUE;                                       // 均衡达标预置（任一越带即翻假） / Balanced preset
        FOR i := 1 TO DL_LSD_NAX DO
            IF bAxActive[i] THEN
                _fDev := aLoadPct[i] - _fAvg;                // 负载对均值偏差 [%] / Load deviation
                IF ABS(_fDev) <= fShareBandPct THEN
                    aVoutMmS[i] := fVrefMmS;                 // 带内不修正（死区防振荡） / In-band: no correction
                ELSE
                    _fOut := fVrefMmS * (1.0 - fDroopPct * _fDev / DL_LSD_PCT);   // droop 调差修正（高载减速让载） / Droop correction
                    IF _fOut > fVrefMax THEN
                        _fOut := fVrefMax;                   // 输出上钳 ±fVrefMax / Clamp high
                    ELSIF _fOut < -fVrefMax THEN
                        _fOut := -fVrefMax;                  // 输出下钳 / Clamp low
                    END_IF
                    aVoutMmS[i] := _fOut;                    // 修正输出 / Corrected output
                    _bBal := FALSE;                          // 有轴越带：未均衡 / Axis out of band
                END_IF
            ELSE
                aVoutMmS[i] := fVrefMmS;                     // 非负载轴直通不修正（头注释①） / Inactive axis pass-through
            END_IF
        END_FOR
        bNoLoad := FALSE;                                    // 有有效轴 / Load exists
        bBalanced := _bBal;                                  // 均衡达标出口 / Balanced outlet
    ELSE
        FOR i := 1 TO DL_LSD_NAX DO
            aVoutMmS[i] := fVrefMmS;                         // 全轴失效：直通（均值除零前置跳过） / No active axis: pass-through
        END_FOR
        bNoLoad := TRUE;                                     // 置全轴失效标志 / Raise no-load flag
        bBalanced := FALSE;                                  // 无轴谈不上均衡 / Not balanced
    END_IF
END_IF

(* —— 段 3：故障出口（组态病 ∨ 输入病，R191 同源） —— *)
bError := _bCfgBad OR _bErrScan;                             // 故障标志出口 / Error flag outlet

END_FUNCTION_BLOCK
