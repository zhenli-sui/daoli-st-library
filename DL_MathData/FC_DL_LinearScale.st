(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LinearScale
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / MIN / MAX），全 REAL 运算
 * 功能描述 (Function)   : 模拟量原始码 → 工程量的线性标定。如 0..27648 对应 0..1.6MPa，
 *                         或 4..20mA 对应 0..100%。内置量程为零防御（除零保护）、
 *                         反向量程支持、输出双侧钳位、输入占量程百分比输出。
 *                         钳位判定使用浮点容差，不做浮点判等。
 * 开源溯源 (Origin)     : 原创实现。防御结构与模板库 05-algorithm-templates.md
 *                         的 FC_LinearScale 思路同源，按本库故障码体系重写并加严。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 说明     (Note)       : NaN / Inf 检测在纯 IEC 61131-3 中无标准手段（各平台对
 *                         比较运算返回值处理不一致），故 v1.0.0 不做该检测，
 *                         故障码 16#0001_0006 预留给支持 NaN 检测的平台版本。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 除零/排序/双侧钳位/容差判等（本轮 R4 样板）
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_LinearScale : REAL
VAR_INPUT
    fIn      : REAL;                 // 原始输入值 [raw] / Raw input value [raw]
    fInMin   : REAL := 0.0;          // 输入量程下限 [raw] / Input range low [raw]
    fInMax   : REAL := 27648.0;      // 输入量程上限 [raw] / Input range high [raw]
    fOutMin  : REAL := 0.0;          // 工程量下限 [EU] / Engineering range low [EU]
    fOutMax  : REAL := 100.0;        // 工程量上限 [EU] / Engineering range high [EU]
    bClamp   : BOOL := TRUE;         // 是否双侧钳位到工程量程 / Enable two-sided clamping
END_VAR
VAR_OUTPUT
    bValid   : BOOL;                 // 换算有效标志，FALSE 表示量程非法 / Conversion valid flag, FALSE means invalid range
    bClamped : BOOL;                 // 结果被钳位标志 / Result clamped flag
    fPercent : REAL;                 // 输入占量程百分比 [%]，可超 0..100 / Input as percent of span [%], may exceed 0..100
    uErrorId : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fSpanIn  : REAL;                 // 输入量程跨度 [raw]，可为负（反向标定） / Input span [raw], negative for reverse scaling
    fSpanOut : REAL;                 // 输出量程跨度 [EU]，可为负 / Output span [EU], may be negative
    fResult  : REAL;                 // 中间结果 [EU] / Intermediate result [EU]
    fNorm    : REAL;                 // 归一化比值 [0..1 附近]，无量纲 / Normalized ratio, dimensionless
    fOutLo   : REAL;                 // 输出下限，已排序 [EU] / Ordered output low limit [EU]
    fOutHi   : REAL;                 // 输出上限，已排序 [EU] / Ordered output high limit [EU]
    fBefore  : REAL;                 // 钳位前的结果快照，用于判定是否发生钳位 [EU] / Pre-clamp snapshot [EU]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;   // 浮点判零容差 / Float zero tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：任何异常路径下返回值落到工程量下限
 *      Safe preset: on every error path the return value falls back to the output low
 *-----------------------------------------------------------------------------*)
FC_DL_LinearScale := fOutMin;
bValid            := TRUE;
bClamped          := FALSE;
fPercent          := 0.0;
uErrorId          := 16#0000_0000;
fResult           := fOutMin;
fBefore           := fOutMin;

(*------------------------------------------------------------------------------
 * 段 2｜量程跨度计算 + 防除零（边界 B1 / B6）
 *      Span computation and divide-by-zero guard
 *      浮点判零用 ABS(..) <= EPS，禁止 fSpanIn = 0.0
 *      该段必须先于任何除法，fPercent 的计算建立在跨度已校验的前提上
 *-----------------------------------------------------------------------------*)
fSpanIn  := fInMax - fInMin;
fSpanOut := fOutMax - fOutMin;

IF ABS(fSpanIn) <= DL_FLOAT_EPS THEN
    bValid            := FALSE;
    uErrorId          := 16#0001_0002;
    FC_DL_LinearScale := fOutMin;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜归一化与百分比（边界 B2）：反向量程天然支持
 *      Normalization and percentage: reverse ranges are supported by construction
 *      fInMax < fInMin 时 fSpanIn 为负，比值自动反向，0% 落在 fInMax 侧
 *-----------------------------------------------------------------------------*)
fNorm    := (fIn - fInMin) / fSpanIn;
fPercent := fNorm * 100.0;
fResult  := fOutMin + fNorm * fSpanOut;

(*------------------------------------------------------------------------------
 * 段 4｜输出边界排序（边界 B3）：钳位前必须先排序
 *      Output limit ordering before clamping
 *      若输出量程传反而不排序，钳位会把结果压到错误端点，现象是"钳位看似
 *      生效而输出全错"，这是本组件最隐蔽的失效模式
 *-----------------------------------------------------------------------------*)
fOutLo := MIN(fOutMin, fOutMax);
fOutHi := MAX(fOutMin, fOutMax);

(*------------------------------------------------------------------------------
 * 段 5｜双侧钳位（边界 B4/B5）：上下限成对出现，只用一侧是安全红线错误
 *      Two-sided clamping: both limits are mandatory, one-sided is a safety defect
 *      只做上限会让负向冲击直接打穿执行机构；钳位判定用容差而非不等号
 *-----------------------------------------------------------------------------*)
IF bClamp THEN
    fBefore := fResult;

    IF fResult < fOutLo THEN
        fResult := fOutLo;
    ELSIF fResult > fOutHi THEN
        fResult := fOutHi;
    END_IF

    IF ABS(fResult - fBefore) > DL_FLOAT_EPS THEN
        bClamped := TRUE;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜结果回写（边界 B7）：字面量均带小数点，全程 REAL，不混入 LREAL
 *      Result write-back: literals carry decimal points, REAL stays REAL
 *-----------------------------------------------------------------------------*)
FC_DL_LinearScale := fResult;
END_FUNCTION
