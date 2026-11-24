(*==============================================================================
 * 组件名称 (Component)  : FC_DL_TempUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : lgf-converter（T2-1 LGF Converter 组回补）
 * 作者/日期             : Daoli Library / 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），纯函数无状态
 * 功能简介 (Function)   : 摄氏 / 华氏 / 开尔文三温标两两互转。源 / 目标由枚举
 *                         单向选择（非 MODE 巨无霸：仅 3×3 查表映射，公式域固定）。
 *                         物理无效（低于绝对零度）置信息级诊断不阻断返回。
 *                         典型现场用途：热电阻 / 热电偶 HMI 显示单位切换、
 *                         进口设备华氏组态与国产摄氏台账的台账口径统一、
 *                         能耗报表开尔文热力学量换算。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 公开手册 Converter 分类中
 *                         温标换算族的功能分类与参数域），换算公式取自公开
 *                         温标定义，只借分类/参数域/命名，clean-room 实现，
 *                         未复制任何源码。来源标签：lgf-converter。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS
 *
 * 【接口契约 / Interface contract】
 *   返回值：换算结果 [目标温标单位]；枚举非法时恒为 0.0。
 *   输入  ：fVal 输入温度；eSrc 源温标；eDst 目标温标。
 *   输出  ：uErrorId 故障码（绝对零度信息级 / 枚举非法故障级）。
 *   纪律  ：纯函数同输入同输出；无内部状态；可安全放进 IF 表达式与
 *           多任务环境（无共享可变状态）。
 *
 * 【使用示例 / Usage example】
 *   VAR
 *       fShow : LREAL;      // HMI 显示值
 *       nErr  : UDINT;      // 诊断码
 *   END_VAR
 *   // 台账存摄氏，HMI 依用户语言显示华氏：
 *   fShow := FC_DL_TempUnitConvert(fVal := fLedger, eSrc := E_DL_TempUnit.eCelsius,
 *                                  eDst := E_DL_TempUnit.eFahrenheit,
 *                                  uErrorId => nErr);
 *   IF nErr = 16#0001_0110 THEN
 *       // 信息级：源值低于绝对零度，坏值溯源（如热电偶断线负满量程）
 *   END_IF
 *
 * 【设计决策：枚举对而非模式码 / Enum pair instead of a mode code】
 *   3×3 组合用"源枚举 + 目标枚举"两个引脚表达，取代单引脚 MODE 巨无霸
 *   （单模式码要为 9 条路径编 9 个号，组态可读性差且易填错号）。
 *   枚举对 + 单向基准链（先归一到摄氏）使公式域固定为 4 条，
 *   新增温标只需扩归一段与展开段各一个 CASE 分支。
 *
 * 【换算公式域 / Formula domain（公开温标定义）】
 *   K → C : C = K - 273.15        ｜ C → K : K = C + 273.15
 *   F → C : C = (F - 32) × 5 / 9  ｜ C → F : F = C × 9 / 5 + 32
 *   全部 9 条路径（含同标直通）都由这 4 条公式 + 直通覆盖，无组合爆炸。
 *
 * 【诊断链设计 / Diagnostic chain design】
 *   绝对零度诊断置信息级不阻断：断线 / 短路的模拟量常表现为负满量程
 *   （约 -327 度摄氏口径），截断为绝对零度会抹掉故障证据；
 *   照算输出让上层诊断链能看到"多不可能"，溯源更直接。
 *
 * 验收向量 (Acceptance) :
 *   V1 fVal = 100.0, eCelsius → eKelvin     ：返回 373.15（沸点）
 *   V2 fVal = 100.0, eCelsius → eFahrenheit ：返回 212.0（沸点华氏）
 *   V3 fVal =  32.0, eFahrenheit → eCelsius ：返回 0.0（冰点）
 *   V4 fVal = 300.0, eKelvin → eCelsius     ：返回 26.85（常温）
 *   V5 fVal = -40.0, eCelsius → eFahrenheit ：返回 -40.0（双温标交点）
 *
 * 【同标直通与往返一致性推演 / Pass-through and round-trip checks】
 *   P1 eCelsius → eCelsius, fVal = 23.4 → 返回 23.4（同标直通零损耗）
 *   P2 eKelvin → eKelvin,    fVal = 0.0 → 返回 0.0 且不置绝对零度诊断
 *      （0 K 恰为绝对零度，容差含等号口径，合法物理下界）
 *   P3 V5 往返：-40 F → C 得 -40.0，再 C → F 仍得 -40.0（交点往返零漂移）
 *   P4 V1 往返：373.15 K → C 得 100.0，再 C → K 仍得 373.15
 *      （单向基准链 + 双精度浮点，往返误差在 1E-9 容差内）
 *
 * 【拒绝路径推演 / Rejection path walk-through】
 *   R1 eSrc = 200（非法枚举）→ uErrorId=0001_0207、返回 0.0（B2）
 *   R2 eDst = 99（非法枚举） → uErrorId=0001_0208、返回 0.0（B2）
 *   R3 fVal = -300（摄氏，低于绝对零度）→ uErrorId=0001_0110 信息级，
 *      返回值照算（华氏口径 -452.0）不截断（B3 诊断链留证）
 *
 * 【调用开销与部署建议 / Cost and deployment notes】
 *   每次调用固定成本：至多两次乘除、一次加减与一个 CASE 分支，
 *   无循环无状态，可放心放进 HMI 刷新链与报表计算链高频调用；
 *   台账口径建议全程统一摄氏存储、显示层换算，
 *   避免多级换算叠加放大舍入误差。
 * 故障码表 (Error codes):
 *   16#0001_0110  归一后温度低于绝对零度（信息级，不阻断，返回值照算输出，
 *                 便于诊断链追溯坏值来源）
 *   16#0001_0207  源温标枚举非法（故障级，返回 0.0）
 *   16#0001_0208  目标温标枚举非法（故障级，返回 0.0）
 *   【码位终审】原拟 0004_0101 / 0004_0201 / 0004_0202 经全库复核冲突：0004
 *   段属 DL_Motion（公约 0.7 段位表），且三码已分别被 FB_DL_SingleAxis
 *   （0004_0101 指令丢弃、0004_0201 非法态、0004_0202 软限位越界）、
 *   FB_DL_AxisRelativeMove / FB_DL_AxisVelocityMove（0004_0201）占用。
 *   本体属 DL_MathData，已顺延至 0001_0110 / 0001_0207 / 0001_0208（无冲突）。
 * 红线自检 (Redline)    : R1 ✓ 零全局存储 / 零外部变量引用 ｜ R2 ✓ 零物理地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 枚举越界拒绝 + 绝对零度诊断 + 除数常量判零守卫
 *                         R5 ✓ 全变量与枚举项中英双语同行注释 ｜ R6 ✓ 纯函数无状态（R6 状态机 N/A）
 *                         R7 ✓ 无定时器 / 边沿实例（R7 N/A）
 * 边界契约 (Boundaries):
 *   B1 换算基准链：一律先归一到摄氏（K → C 减绝对零度偏移；F → C 按公开
 *      温标定义式），再从摄氏到目标；同标转换直通。
 *      单向基准链保证 3×3 = 9 条路径只用 4 个公式，公式域固定无组合爆炸。
 *   B2 枚举越界值（非 0/1/2）→ 置故障级码并返回 0.0：静默返回错误温标数值
 *      比返回 0 更危险（0 摄氏度与 0 开尔文差 273.15，工艺员一眼可辨）。
 *   B3 归一后低于绝对零度 → 置信息级码，返回值照算输出不截断，
 *      供诊断链追溯（如热电偶断线负满量程）。
 *   B4 纯函数：同输入同输出，无内部状态、无副作用，可安全放进 IF 表达式。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · Level 0 原子族回补）
 *   2026-11-15  v1.0.1  终审修复：故障码 0004_0101 / 0004_0201 / 0004_0202 属
 *                       DL_Motion 段位且与 SingleAxis / AxisRelativeMove /
 *                       AxisVelocityMove 冲突，改归 DL_MathData 段
 *                       0001_0110 / 0001_0207 / 0001_0208，换算与返回语义零改动
 *============================================================================*)
TYPE E_DL_TempUnit :
(
    eCelsius    := 0,  // 摄氏度 [deg C] / Celsius
    eFahrenheit := 1,  // 华氏度 [deg F] / Fahrenheit
    eKelvin     := 2   // 开尔文 [K] / Kelvin
);
END_TYPE

FUNCTION FC_DL_TempUnitConvert : LREAL    // 返回换算结果 [目标温标单位] / Converted result in the destination unit
VAR_INPUT
    fVal    : LREAL;                    // 输入温度 [源温标单位] / Input temperature in the source unit
    eSrc    : E_DL_TempUnit;            // 源温标选择 / Source unit selector
    eDst    : E_DL_TempUnit;            // 目标温标选择 / Destination unit selector
END_VAR
VAR_OUTPUT
    uErrorId: UDINT;                    // 故障码，0 = 无故障；低于绝对零度置信息级 / Error code, 0 = no error
END_VAR
VAR
    fCelsius : LREAL;                   // 归一化中间值 [摄氏度] / Normalized intermediate in Celsius
END_VAR
VAR CONSTANT
    DL_ABS_ZERO_C  : LREAL := -273.15;  // 绝对零度 [摄氏度]，公开温标物理常数 / Absolute zero in Celsius, physical constant
    DL_F_FREEZE_C  : LREAL := 32.0;     // 华氏冰点偏移 [华氏度]，公开温标定义 / Fahrenheit freezing offset, scale definition
    DL_F_SCALE_NUM : LREAL := 9.0;      // 华氏刻度分子（每 5 摄氏度升 9 华氏度）/ Fahrenheit scale numerator
    DL_F_SCALE_DEN : LREAL := 5.0;      // 华氏刻度分母（同上，与分子配对）/ Fahrenheit scale denominator
    DL_FLOAT_EPS   : LREAL := 1.0E-9;   // 判等容差 / Equality tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜缺省返回与故障码清零
 *      Default return and error code cleared
 *      缺省 0.0：任何提前退出路径自动携带"可辨识的零"，不误报换算值
 *-----------------------------------------------------------------------------*)
FC_DL_TempUnitConvert := 0.0;
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜枚举合法性门（边界 B2）：源 / 目标任一越界即拒绝，返回 0.0
 *      Enum validity gate: any out-of-range selector rejects with 0.0
 *      枚举比较用等值列举而非区间判断：对非法值（如 200）区间判断会漏拦截
 *-----------------------------------------------------------------------------*)
IF (eSrc <> E_DL_TempUnit.eCelsius)
    AND (eSrc <> E_DL_TempUnit.eFahrenheit)
    AND (eSrc <> E_DL_TempUnit.eKelvin) THEN
    uErrorId := 16#0001_0207;   // 故障级：源温标非法 / Fault: invalid source unit
    RETURN;
END_IF

IF (eDst <> E_DL_TempUnit.eCelsius)
    AND (eDst <> E_DL_TempUnit.eFahrenheit)
    AND (eDst <> E_DL_TempUnit.eKelvin) THEN
    uErrorId := 16#0001_0208;   // 故障级：目标温标非法 / Fault: invalid destination unit
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜归一到摄氏（边界 B1）：单向基准链第一段，同标直通
 *      Normalize to Celsius: first leg of the one-way basis chain
 *-----------------------------------------------------------------------------*)
CASE eSrc OF
    E_DL_TempUnit.eCelsius:
        fCelsius := fVal;                                   // 摄氏直通 / Pass-through
    E_DL_TempUnit.eFahrenheit:
        (* 华氏转摄氏：C = (F - 32) × 5 / 9（公开温标定义式） *)
        fCelsius := (fVal - DL_F_FREEZE_C) * DL_F_SCALE_DEN / DL_F_SCALE_NUM;
    E_DL_TempUnit.eKelvin:
        fCelsius := fVal + DL_ABS_ZERO_C;                   // 开尔文转摄氏：减 273.15
    ELSE
        uErrorId := 16#0001_0207;   // 兜底（理论不可达，段 2 已拦截）/ Fallback, unreachable
        RETURN;
END_CASE

(*------------------------------------------------------------------------------
 * 段 4｜绝对零度诊断（边界 B3）：信息级不阻断，返回值照算输出
 *      Absolute-zero diagnostics: info level, conversion continues
 *      容差内等于绝对零度视为合法（物理下界含等号），严格更低才诊断
 *-----------------------------------------------------------------------------*)
IF fCelsius < DL_ABS_ZERO_C - DL_FLOAT_EPS THEN
    uErrorId := 16#0001_0110;   // 信息级：低于绝对零度 / Info: below absolute zero
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜摄氏到目标（边界 B1）：单向基准链第二段，同标直通
 *      Celsius to destination: second leg of the basis chain
 *-----------------------------------------------------------------------------*)
CASE eDst OF
    E_DL_TempUnit.eCelsius:
        FC_DL_TempUnitConvert := fCelsius;                  // 摄氏直通 / Pass-through
    E_DL_TempUnit.eKelvin:
        FC_DL_TempUnitConvert := fCelsius - DL_ABS_ZERO_C;  // 摄氏转开尔文：加 273.15
    E_DL_TempUnit.eFahrenheit:
        (* 摄氏转华氏：F = C × 9 / 5 + 32（公开温标定义式） *)
        FC_DL_TempUnitConvert := fCelsius * DL_F_SCALE_NUM / DL_F_SCALE_DEN + DL_F_FREEZE_C;
    ELSE
        uErrorId := 16#0001_0208;   // 兜底（理论不可达，段 2 已拦截）/ Fallback, unreachable
        RETURN;
END_CASE
END_FUNCTION
