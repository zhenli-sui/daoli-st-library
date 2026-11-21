(*==============================================================================
 * 组件名称 (Component)  : FC_DL_CoilDiameterCalc
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 卷绕工艺量反算
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅用标准算术、ABS、LIMIT
 * 功能描述 (Function)   : 由「材料线速度 + 卷轴转速 + 机械传动比」反算瞬时卷径
 *                         直径 = 线速度 乘以 传动比 除以 (派 乘以 转速)，并同时
 *                         给出卷径变化率与相对卷芯的累计层数。是收放卷张力控制
 *                         （扭矩等于张力乘卷径除二）、线速度匹配、排线节距计算
 *                         的数据源头。
 * 与既有件边界 (Boundary): 本件只做瞬时几何反算（无状态、无记忆）；层厚积分
 *                         递推与排线执行属 FB_DL_WindingTraverse 的职责；两者
 *                         互为校验关系（可把本件结果注入该块的注入卷径引脚做
 *                         比对），但代码零调用、零耦合，禁止在本件内调用任何
 *                         功能块。
 * 设计要点 (Key notes)  : ① 低速保护是核心工程语义：转速低于 0.5 转每分时
 *                           编码器低频量化会让反算卷径跳动到毫米级，此时沿用
 *                           上次有效卷径而不是归零。停机瞬间卷径突然归零会让
 *                           张力给定瞬间飙到上限，是现场最常见的事故源；
 *                         ② 卷芯保护：反算卷径小于卷芯直径说明打滑或测速错，
 *                           按卷芯直径修正并置码，绝不把几何上不可能的值下发；
 *                         ③ 一阶低通首拍无滞后：上次卷径为 0 时直接取原始值，
 *                           避免从 0 缓慢爬升（R19 精神）；
 *                         ④ 变化率先算再更新历史值，次序颠倒会得到恒 0；
 *                         ⑤ 所有除法分母（转速、滤波时间常数加周期、上次卷径、
 *                           厚度）均有守卫或常量域保证，无除零面。
 * 开源溯源 (Origin)     : lgf-technology。参考 LGF（Libre Graphical Framework）
 *                         公开函数库「Technology」分类中卷绕类函数的功能分类
 *                         与参数域（线速度 / 转速 / 传动比 三段入口形态），只借
 *                         分类、参数域与命名习惯，公式重排与实现 100% 自有
 *                         clean-room，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 故障码表 (Error codes):
 *   16#0002_1D01【信息级】线速度越界被钳位
 *   16#0002_1D02【信息级】传动比越界被钳位
 *   16#0002_1D03【信息级】卷芯直径或材料厚度越界被钳位
 *   16#0002_1D04【信息级】反算卷径小于卷芯直径，已按卷芯修正（疑似打滑）
 *   16#0002_1D10【信息级】转速过低不可信或入参非有限，沿用上次有效值
 * 验收向量 (Acceptance) :
 *   V1 线速度 100 米每分 / 转速 100 转每分 / 传动比 1 → 卷径约 0.3183 米
 *   V2 转速 0.2 转每分（低于 0.5）→ 返回上次卷径、变化率 0、码 1D10
 *   V3 线速度 10 / 转速 100 / 卷芯 0.2 → 原始值 0.0318 小于卷芯，修正为 0.2
 *      并置 1D04
 *   V4 上次卷径 0 且滤波使能 → 首拍输出等于原始值（无滞后）
 *   V5 上次卷径 0.3 / 当前 0.302 / 周期 0.01 → 变化率 0.2 米每秒
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 全部除法分母有守卫、浮点判等
 *                         用容差、非有限值筛查 ｜ R5 全变量中英双语同行注释
 *                         R6 N/A（纯函数）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · 工艺物理量链）
 *============================================================================*)

FUNCTION FC_DL_CoilDiameterCalc : LREAL
VAR_INPUT
    fLineSpeed : LREAL := 0.0;      // 材料线速度，域 0 到 3000 [米每分] / Material line speed, 0 to 3000 metres per minute
    fShaftRpm  : LREAL := 0.0;      // 卷轴转速，域 0 到 6000，低于 0.5 视为停机 [转每分] / Shaft speed, below 0.5 rpm treated as standstill
    fGearRatio : LREAL := 1.0;      // 卷轴对电机传动比，域 0.01 到 1000，1.0 为直连 [-] / Shaft to motor gear ratio, 1.0 means direct drive
    fCoreDia   : LREAL := 0.100;    // 卷芯（纸管）直径，域 0.01 到 1.0 [米] / Core diameter, 0.01 to 1.0 m
    fThickness : LREAL := 0.0001;   // 材料厚度，域 1 微米到 10 毫米，层数积分用 [米] / Material thickness, used by the layer count
    fPrevDia   : LREAL := 0.0;      // 上拍卷径，0 表示无历史（变化率出口置 0）[米] / Previous diameter, 0 means no history
    fTaskCycle : LREAL := 0.01;     // 任务周期，域 1 毫秒到 1 秒，变化率换算用 [s] / Task cycle time
    bFilterEn  : BOOL := TRUE;      // 一阶低通使能，用于抑制编码器量化噪声 [-] / First-order low-pass enable
    fFilterTau : LREAL := 1.0;      // 低通时间常数，域 0.1 到 10 [s] / Low-pass time constant
END_VAR
VAR_OUTPUT
    fDia        : LREAL;    // 估算卷径，低通使能时为滤波后的值 [米] / Estimated diameter, filtered when enabled
    fDiaRaw     : LREAL;    // 未滤波原始卷径，用于诊断与比对 [米] / Unfiltered diameter for diagnostics
    fDiaRate    : LREAL;    // 卷径变化率，正值为收卷增大 [米每秒] / Diameter rate, positive when winding up
    fLayerCount : LREAL;    // 相对卷芯的累计层数，由厚度推算 [层] / Layer count relative to the core
    bValid      : BOOL;     // 计算有效，任一钳位或修正事件为 FALSE [-] / TRUE when no clamping or correction happened
    uErrorId    : UDINT;    // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    fGearUse  : LREAL;      // 生效传动比（已钳位）[-] / Effective gear ratio
    fCoreUse  : LREAL;      // 生效卷芯直径（已钳位）[米] / Effective core diameter
    fThickUse : LREAL;      // 生效材料厚度（已钳位）[米] / Effective thickness
    fLineUse  : LREAL;      // 生效线速度（已钳位）[米每分] / Effective line speed
    fDtUse    : LREAL;      // 生效任务周期（已钳位）[s] / Effective task cycle
    fTauUse   : LREAL;      // 生效滤波时间常数（已钳位）[s] / Effective filter time constant
    fAlpha    : LREAL;      // 一阶低通权重 [-] / First-order filter weight
    bDirty    : BOOL;       // 是否发生过钳位或修正事件 [-] / TRUE when any clamp or correction fired
END_VAR
VAR CONSTANT
    DL_PI         : LREAL := 3.141592653589793;  // 圆周率 [-] / Pi
    DL_SEC_PER_MIN: LREAL := 60.0;               // 分钟转秒 [s每分] / Seconds per minute
    DL_VMAX       : LREAL := 3000.0;             // 线速度上限，约 50 米每秒，覆盖高速分切 [米每分] / Line speed upper bound
    DL_NMAX       : LREAL := 6000.0;             // 转速上限 [转每分] / Shaft speed upper bound
    DL_RPM_EPS    : LREAL := 0.5;                // 转速判零门限，低于此不反算 [转每分] / Speed floor below which the inverse is untrustworthy
    DL_DIA_MIN    : LREAL := 0.01;               // 卷径下限 [米] / Diameter lower bound
    DL_DIA_MAX    : LREAL := 3.0;                // 卷径上限 [米] / Diameter upper bound
    DL_CORE_MIN   : LREAL := 0.01;               // 卷芯直径下限 [米] / Core diameter lower bound
    DL_CORE_MAX   : LREAL := 1.0;                // 卷芯直径上限 [米] / Core diameter upper bound
    DL_THICK_MIN  : LREAL := 1.0E-6;             // 厚度下限，1 微米 [米] / Thickness lower bound
    DL_THICK_MAX  : LREAL := 0.01;               // 厚度上限，10 毫米 [米] / Thickness upper bound
    DL_GEAR_MIN   : LREAL := 0.01;               // 传动比下限 [-] / Gear ratio lower bound
    DL_GEAR_MAX   : LREAL := 1000.0;             // 传动比上限 [-] / Gear ratio upper bound
    DL_TAU_MIN    : LREAL := 0.1;                // 滤波时间常数下限 [s] / Filter time constant lower bound
    DL_TAU_MAX    : LREAL := 10.0;               // 滤波时间常数上限 [s] / Filter time constant upper bound
    DL_CYCLE_MIN  : LREAL := 0.001;              // 任务周期下限 [s] / Task cycle lower bound
    DL_CYCLE_MAX  : LREAL := 1.0;                // 任务周期上限 [s] / Task cycle upper bound
    DL_FLOAT_EPS  : LREAL := 1.0E-9;             // 浮点容差 [-] / Float tolerance
    DL_BIG        : LREAL := 1.0E300;            // 非有限值兜底门限 [-] / Magnitude guard
    DL_LAYER_DIV  : LREAL := 2.0;                // 层数公式中的二倍因子，单层增径为两倍厚度 [-] / Two-times factor of the layer formula
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置
 *      Pre-set outputs
 *-----------------------------------------------------------------------------*)
FC_DL_CoilDiameterCalc := 0.0;
fDia        := 0.0;
fDiaRaw     := 0.0;
fDiaRate    := 0.0;
fLayerCount := 0.0;
bValid      := FALSE;
uErrorId    := 16#0000_0000;
bDirty      := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜入参有限性筛查（边界 B1）：任一非有限即按不可信处理，沿用上次值
 *      Input finiteness check: any non-finite value is untrusted
 *-----------------------------------------------------------------------------*)
IF (fLineSpeed <> fLineSpeed) OR (fShaftRpm <> fShaftRpm) OR (fGearRatio <> fGearRatio)
   OR (fCoreDia <> fCoreDia) OR (fThickness <> fThickness) OR (fPrevDia <> fPrevDia)
   OR (fTaskCycle <> fTaskCycle) OR (fFilterTau <> fFilterTau) THEN
    fDia     := fPrevDia;            // 沿用上次有效卷径，绝不归零
    fDiaRaw  := fPrevDia;
    fDiaRate := 0.0;
    uErrorId := 16#0002_1D10;
    RETURN;
END_IF

IF (ABS(fLineSpeed) > DL_BIG) OR (ABS(fShaftRpm) > DL_BIG) OR (ABS(fPrevDia) > DL_BIG) THEN
    fDia     := fPrevDia;
    fDiaRaw  := fPrevDia;
    fDiaRate := 0.0;
    uErrorId := 16#0002_1D10;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数域钳位（信息级）：钳位后继续计算，宁可给近似值也不给 0 断链
 *      Parameter clamping with informational codes, computation always continues
 *-----------------------------------------------------------------------------*)
fLineUse := fLineSpeed;
IF fLineUse < 0.0 THEN
    fLineUse := 0.0;
    uErrorId := 16#0002_1D01;
    bDirty   := TRUE;
ELSIF fLineUse > DL_VMAX THEN
    fLineUse := DL_VMAX;
    uErrorId := 16#0002_1D01;
    bDirty   := TRUE;
END_IF

fGearUse := fGearRatio;
IF fGearUse < DL_GEAR_MIN THEN
    fGearUse := DL_GEAR_MIN;
    uErrorId := 16#0002_1D02;
    bDirty   := TRUE;
ELSIF fGearUse > DL_GEAR_MAX THEN
    fGearUse := DL_GEAR_MAX;
    uErrorId := 16#0002_1D02;
    bDirty   := TRUE;
END_IF

fCoreUse := fCoreDia;
IF fCoreUse < DL_CORE_MIN THEN
    fCoreUse := DL_CORE_MIN;
    uErrorId := 16#0002_1D03;
    bDirty   := TRUE;
ELSIF fCoreUse > DL_CORE_MAX THEN
    fCoreUse := DL_CORE_MAX;
    uErrorId := 16#0002_1D03;
    bDirty   := TRUE;
END_IF

fThickUse := fThickness;
IF fThickUse < DL_THICK_MIN THEN
    fThickUse := DL_THICK_MIN;
    uErrorId  := 16#0002_1D03;
    bDirty    := TRUE;
ELSIF fThickUse > DL_THICK_MAX THEN
    fThickUse := DL_THICK_MAX;
    uErrorId  := 16#0002_1D03;
    bDirty    := TRUE;
END_IF

fDtUse := fTaskCycle;
IF fDtUse < DL_CYCLE_MIN THEN
    fDtUse := DL_CYCLE_MIN;
ELSIF fDtUse > DL_CYCLE_MAX THEN
    fDtUse := DL_CYCLE_MAX;
END_IF

fTauUse := fFilterTau;
IF fTauUse < DL_TAU_MIN THEN
    fTauUse := DL_TAU_MIN;
ELSIF fTauUse > DL_TAU_MAX THEN
    fTauUse := DL_TAU_MAX;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜低速保护（关键工程语义，边界 B2）：转速低于门限不反算，沿用上次值
 *      Low-speed protection: below the speed floor the inverse is skipped
 *      现场理由：停机瞬间反算卷径会突然塌到接近 0，若直接下发会让张力扭矩
 *      给定瞬间飙到上限，是收放卷最常见的断料与飞车诱因
 *-----------------------------------------------------------------------------*)
IF fShaftRpm < DL_RPM_EPS THEN
    fDia     := fPrevDia;                          // 沿用上次有效卷径
    fDiaRaw  := fPrevDia;
    fDiaRate := 0.0;
    uErrorId := 16#0002_1D10;
    IF fPrevDia >= DL_DIA_MIN THEN
        bValid := TRUE;                            // 有历史值时结果仍可用
    ELSE
        bValid := FALSE;                           // 无历史值时结果不可用
    END_IF
    FC_DL_CoilDiameterCalc := fDia;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主反算：直径 = 线速度 乘以 传动比 除以 (派 乘以 转速)
 *      Main inverse: diameter equals line speed times ratio over pi times rpm
 *      写法一（保留单位可读性，分子分母同除 60）：
 *        原始值 = (线速度 除以 60) 乘以 传动比 除以 (派 乘以 (转速 除以 60))
 *      化简后等价于：原始值 = 线速度 乘以 传动比 除以 (派 乘以 转速)
 *      两式完全等价，此处按写法一书写以便维护者核对量纲，禁止改成其它形式
 *      分母的转速已由段 4 保证不小于 0.5，派为常量，无除零面
 *-----------------------------------------------------------------------------*)
fDiaRaw := (fLineUse / DL_SEC_PER_MIN) * fGearUse
           / (DL_PI * (fShaftRpm / DL_SEC_PER_MIN));

(*------------------------------------------------------------------------------
 * 段 6｜卷芯保护与卷径钳位（边界 B3）：几何上不可能的值必须修正
 *      Core protection and diameter clamping: geometrically impossible values fixed
 *-----------------------------------------------------------------------------*)
IF fDiaRaw < fCoreUse THEN
    fDiaRaw  := fCoreUse;          // 卷径不可能小于卷芯：疑似打滑或测速错
    uErrorId := 16#0002_1D04;
    bDirty   := TRUE;
END_IF

fDiaRaw := LIMIT(DL_DIA_MIN, fDiaRaw, DL_DIA_MAX);

(*------------------------------------------------------------------------------
 * 段 7｜一阶低通（首拍无滞后）：分母恒大于 0.1，无除零面
 *      First-order low pass with no lag on the first cycle
 *-----------------------------------------------------------------------------*)
IF bFilterEn THEN
    IF fPrevDia < DL_FLOAT_EPS THEN
        fDia := fDiaRaw;                            // 首拍直接取原始值，避免从 0 爬升
    ELSE
        fAlpha := fDtUse / (fTauUse + fDtUse);      // 分母不小于 0.101
        fDia   := fPrevDia + fAlpha * (fDiaRaw - fPrevDia);
    END_IF
ELSE
    fDia := fDiaRaw;
END_IF

fDia := LIMIT(DL_DIA_MIN, fDia, DL_DIA_MAX);

(*------------------------------------------------------------------------------
 * 段 8｜变化率（先算再更新历史值，次序写死）
 *      Diameter rate computed before the history value is refreshed
 *-----------------------------------------------------------------------------*)
IF fPrevDia > DL_FLOAT_EPS THEN
    fDiaRate := (fDia - fPrevDia) / fDtUse;         // 周期已被钳到不小于 1 毫秒
ELSE
    fDiaRate := 0.0;                                // 无历史值时不产生变化率
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜层数：单层增径为两倍厚度，故层数等于半径差除以厚度
 *      Layer count: each layer adds two thicknesses to the diameter
 *-----------------------------------------------------------------------------*)
fLayerCount := (fDia - fCoreUse) / (DL_LAYER_DIV * fThickUse);

IF fLayerCount < 0.0 THEN
    fLayerCount := 0.0;                             // 层数不得为负（卷芯修正后的边界）
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜有效性与返回值收口
 *      Validity and return value close-out
 *-----------------------------------------------------------------------------*)
IF bDirty THEN
    bValid := FALSE;                                // 发生过钳位或修正，结果标注为近似
ELSE
    bValid := TRUE;
END_IF

FC_DL_CoilDiameterCalc := fDia;
END_FUNCTION
