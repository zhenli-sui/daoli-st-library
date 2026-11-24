(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EnthalpyCompareCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 焓差经济器比较控制 ·
 *                         Level 2 行业池 9.5 节 P0 链路闭环示范
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library 与本库已入库
 *                         算法函数，零厂商方言
 * 功能描述 (Function)   : 焓差比较控制执行块。新风/回风温湿度 4 输入 → 每拍
 *                         两次调用 FC_DL_HumidAirEnthalpy 计算双侧比焓 →
 *                         差分焓值判据（施密特迟滞防临界抖动）→ 新风阀位指令
 *                         输出；含最小新风位硬下限（卫生通风底线）与 ASHRAE
 *                         90.1 新风焓值高限停机语义（回差=死区防振荡）。
 *
 * 【干球温度判据陷阱警示 / Dry-bulb trap warning】
 *   本块判据【只允许使用焓差】，严禁以干球温差（fOaTempC 与 fRaTempC 比较）
 *   代替焓差判据：湿工况下新风干球温度可以低于回风，但其潜热（含湿量）更高，
 *   总焓反而高于回风——若按干球降温直觉开大新风阀，会引入高焓湿空气增加表冷
 *   负荷（验收向量 V1 复现此陷阱）。任何把本块改为干球比较的改动均视为破坏
 *   焓差经济器物理语义。
 *
 * 设计要点 (Key notes)  : ① 连续量组件 → 设 bInit 首扫（R19 唯一合法范式
 *                           IF bTrack OR (NOT bInit)），首扫输出最小新风位
 *                           安全值并重建迟滞态，运行中途 bTrack 一拍即重同步；
 *                         ② 迟滞状态机：开侧 fOaEnth < fRaEnth − 死区、关侧
 *                           fOaEnth > fRaEnth + 死区，死区区间内保持原态
 *                           （传感器漂移防线）；CASE + ELSE 非法态兜底；
 *                         ③ 高限停机：fEnthalpyHighLimit > 0 使能，fOaEnth
 *                           ≥ 高限 → 停机锁 bHighLimitTrip，回落至
 *                           高限 − 死区 以下才解除（瞬时型每拍重算，R15）；
 *                         ④ 失效语义（R11 裁定 D2）：任一温湿度/大气压非有
 *                           限值或越出引脚域 → 阀位指令输出最小新风位（安全
 *                           侧兜底），fOaEnthalpy/fRaEnthalpy/bHighLimitTrip
 *                           冻结保持末次有效值（诊断量冻结），故障码锁存，
 *                           仅「输入恢复 + bReset 上升沿」解除（R15）；
 *                         ⑤ 时间/温湿度全部引脚注入，禁读 CPU 本地钟；
 *                         ⑥ 限幅域对调自修复：fMinOaPos > fFreeCoolOaPos
 *                           时对调继续计算（公约 0.6），量纲注释与限幅域一致。
 * 枚举归属 (Enum note)  : E_DL_EnthalpyHyst（迟滞双侧态）随本块同文件发布；
 *                         本块不重复声明任何既有枚举。
 * 依赖     (Depends)    : FC_DL_HumidAirEnthalpy（DL_Algo，公开接口直接调用，
 *                         不内联重实现其焓值公式）；Standard.library
 *                         （R_TRIG / ABS / MIN / MAX / LIMIT）。
 * 开源溯源 (Origin)     : 原创实现（参考 ASHRAE 90.1 economizer 高限判据与
 *                         OSCAT Building 焓差经济器行为定义，clean-room）。
 *                         仅借鉴公开判据语义（差分焓值切换、最小新风位底线、
 *                         高限停机），未读取、未复制任何源码行；迟滞状态机、
 *                         失效冻结语义与码表为本库独立设计。
 * 故障码表 (Error codes):
 *   16#0005_0202【故障级】焓值计算输入失效（非有限值/越引脚域，锁存，
 *                 解除条件：输入恢复 AND bReset 上升沿）
 *   16#0005_0201【故障级】非法状态兜底（CASE ELSE，复用本库既有同义码，
 *                 与 FB_DL_PackMlStateMachine 同语义，公共码先例
 *                 DL_Algo 16#0002_0004）
 *   16#0005_0103【信息级】下游算法函数钳位码透传归并（温度/湿度/大气压
 *                 越界已钳位照算）/ 限幅域对调自修复（公约 0.6，本块唯一
 *                 分配信息级码复用，见 R11 D3）
 * 【规格偏离留档 / R11 Deviation register】
 *   D1 规格分配故障码 0005_0201（输入失效）与子库既有台账冲突（0201 已被
 *      R5 PackML 非法状态兜底占用）：按公约 0.7 冲突顺延，输入失效改用
 *      0005_0202；非法状态兜底与规格 0005_0202 分配冲突 → 复用既有同义码
 *      0005_0201。语义不变，仅码位重排。
 *   D2 规格失效语义同时出现「冻结保持末次有效阀位」与「输出 fMinOaPos 兜
 *      底值」：裁定为阀位指令输出 fMinOaPos（安全侧），焓值诊断输出与高限
 *      锁存位冻结末次有效值。
 *   D3 限幅域对调自修复（公约 0.6）码位：本块仅分配信息级 0005_0103，对调
 *      事件与下游钳位透传共用该码（当拍 uErrorId 择一呈现，均为信息级）。
 *   D4 新风干球负温域（-30..0 摄氏度）超出下游焓值函数计算域（0..100）：
 *      负干球工况下游返回 0 摄氏度钳位焓值（对新风焓偏高估计 → 判据偏保守
 *      安全侧），钳位信息经 0005_0103 当拍呈现；是否放行负干球工况由调用方
 *      按 D4 取舍（本块按引脚域 -30..60 验收输入，不自行拒绝）。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限值防御（fX<>fX 先检再比较）
 *                             +迟滞判据浮点禁判等+本块无除法运算
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 迟滞状态机 ENUM+CASE
 *                             且 CASE-ELSE 兜底（码 0005_0201）
 *                         R7 ✓ R_TRIG 实例主体无条件周期刷新（严禁入分支）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 06 · 泳道 C · 契约出处 ROUND_PLAN_R6 §3.14
 *   2026-11-15  v1.0.1  终审修复【工程语义级】参数 REAL 输入非数防御缺口：
 *                       原实现仅防御 5 个过程输入，fMinOaPos/fFreeCoolOaPos
 *                       非数经 LIMIT 直透生效域并输出 NaN 阀位指令（无故障
 *                       码伴随）；fEnthalpyDeadband 非数使迟滞判据恒 FALSE
 *                       冻结；fEnthalpyHighLimit 补显式自比检测。另阀位对
 *                       调改为经中间变量交换已防御生效值（防原始引脚穿透，
 *                       与 FB_DL_AnalogValve 终审修复同型）。修法遵循 R4
 *                       #15 沉淀范式：全部 REAL 输入（含参数）非数先检。
 *                       引脚契约零变更。
 * 验收向量 (Acceptance) :
 *   V1 干球陷阱：Oa=20.0 摄氏度/90.0%（焓≈53.6）vs Ra=26.0 摄氏度/40.0%
 *      （焓≈47.5）——新风干球低 6 摄氏度但焓高 6.1，判据不开经济器
 *      （bEconomizerActive=FALSE，阀位=最小新风位）；若按干球比较将错误开阀
 *   V2 迟滞往返：Oa=18.0/50.0（焓≈34.3）vs Ra=26.0/40.0（焓≈47.5），差
 *      −13.2 < −死区 2.0 → 开侧；Oa 渐升至 21.0/70.0（焓≈48.8），差 +1.0
 *      落在 ±2.0 死区内 → 保持开侧不抖动；Oa=22.0/75.0（焓≈53.7），差
 *      +5.9 > +2.0 → 关侧
 *   V3 高限停机：fEnthalpyHighLimit=60.0，Oa 焓 63.0 → bHighLimitTrip=TRUE
 *      强制最小新风位；Oa 焓回落至 58.0（< 60−2）才解除（回差防振荡）
 *   V4 硬下限：fMinOaPos=30.0 / fFreeCoolOaPos=100.0，任意路径断言
 *      fOaDamperCmd ≥ 30.0（激活 100.0 / 非激活 30.0）
 *   V5 非有限值冻结：fOaTempC 注入 NaN → 0005_0202 锁存、阀位回 fMinOaPos、
 *      焓值输出冻结末次有效值；输入恢复 + bReset 沿 → 清码恢复计算
 *   V6 中途 bTrack：运行中（开侧）注入 bTrack 一拍 → 迟滞重建为关侧、
 *      阀位回 fMinOaPos（R19 必测，不锁死）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbEco.fOaTempC := stMet.fTemp;          // 新风温湿度（滤波后信号）
 *   fbEco.fOaRelHum := stMet.fRh;
 *   fbEco.fRaTempC := stZone.fTemp;         // 回风/室内温湿度
 *   fbEco.fRaRelHum := stZone.fRh;
 *   fbEco.fEnthalpyHighLimit := 60.0;       // 0 = 禁用高限停机
 *   fbEco(bEnableCooling := bChwDemand,     // 周期调用
 *         bTrack := bHmiResync, bReset := bFaultReset);
 *   阀执行层（调用方职责）：fOaDamperCmd 直驱新风阀，下限保证亦由执行层
 *   复核；bHighLimitTrip 可联动压缩机保护。bTrack 用于 HMI 强制重同步。
 *----------------------------------------------------------------------------*)

{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_DL_EnthalpyHyst :
(
    eClosed := 0,   // 迟滞关侧：经济器停用，阀位=最小新风位（Closed side: economizer off, damper at minimum position）
    eOpened := 10   // 迟滞开侧：经济器激活，阀位=经济器全开位（Opened side: economizer active, damper at free-cooling position）
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_EnthalpyCompareCtrl
VAR_INPUT
    fOaTempC           : REAL;             // 新风干球温度（Outdoor air dry-bulb temp）[摄氏度] 有效域 -30..60，越域按输入失效处理
    fOaRelHum          : REAL;             // 新风相对湿度（Outdoor air relative humidity）[百分数] 有效域 1..100，越域按输入失效处理
    fRaTempC           : REAL;             // 回风干球温度（Return air dry-bulb temp）[摄氏度] 有效域 0..100（与焓值 FC 计算域一致），越域按输入失效处理
    fRaRelHum          : REAL;             // 回风相对湿度（Return air relative humidity）[百分数] 有效域 1..100
    fAtmPress          : REAL := 101.325;  // 大气压（Atmospheric pressure）[kPa] 默认标准大气，透传焓值 FC，非有限值按输入失效处理
    fEnthalpyDeadband  : REAL := 2.0;      // 焓差切换死区（Enthalpy changeover deadband）[kJ/kg] 施密特迟滞半宽，默认 2.0，负值防御钳位为 0
    fMinOaPos          : REAL := 30.0;     // 最小新风阀位（Minimum outdoor air damper position）[百分数] 卫生通风硬下限，默认 30.0，域 0..100
    fFreeCoolOaPos     : REAL := 100.0;    // 经济器全开阀位（Free-cooling damper position）[百分数] 默认 100.0，域 0..100
    fEnthalpyHighLimit : REAL := 0.0;      // 新风焓值高限停机门限（Enthalpy high-limit trip）[kJ/kg] 默认 0=禁用（ASHRAE 90.1 高限语义）
    bEnableCooling     : BOOL := FALSE;    // 供冷需求使能（Cooling demand enable）[1] FALSE 时阀位恒回最小新风位
    bReset             : BOOL := FALSE;    // 复位（Reset）[1] 上升沿：输入失效锁存码仅在输入已恢复且本沿到达时清除
    bTrack             : BOOL := FALSE;    // 跟踪重同步（Track resync）[1] TRUE 时阀位回最小新风位并重建迟滞态（R19 必测）
END_VAR
VAR_OUTPUT
    fOaEnthalpy        : REAL;             // 新风比焓（Outdoor air enthalpy）[kJ/kg 干空气] 供 HMI/诊断；输入失效拍冻结末次有效值
    fRaEnthalpy        : REAL;             // 回风比焓（Return air enthalpy）[kJ/kg 干空气] 输入失效拍冻结末次有效值
    bEconomizerActive  : BOOL;             // 经济器激活（Economizer active）[1] 差分焓值判据通过且迟滞态为开侧
    fOaDamperCmd       : REAL;             // 新风阀位指令（Outdoor air damper command）[百分数] 量纲=阀位域 0..100，硬下限恒 ≥ fMinOaPos
    bHighLimitTrip     : BOOL;             // 焓值高限停机（Enthalpy high-limit trip）[1] 激活中；失效拍冻结末次有效值
    uErrorId           : UDINT;            // 事件码（Error code）16#0005_0202 输入失效（锁存）/ 16#0005_0201 非法态兜底 / 16#0005_0103 信息级；0 = 无
END_VAR
VAR
    bInit              : BOOL := FALSE;    // 首扫标志（First-scan flag，R19 范式配套）
    _eHyst             : E_DL_EnthalpyHyst := E_DL_EnthalpyHyst.eClosed;  // 迟滞状态机内部态（Internal hysteresis state）
    _bFailLatch        : BOOL := FALSE;    // 输入失效锁存（Input-failure latch，仅解除路径清码 R15）
    _bInFailNow        : BOOL;             // 本拍输入失效判定（Input failure this scan，瞬时条件）
    _bOaTOk            : BOOL;             // 新风温度有效（OA temp valid）
    _bOaROk            : BOOL;             // 新风湿度有效（OA humidity valid）
    _bRaTOk            : BOOL;             // 回风温度有效（RA temp valid）
    _bRaROk            : BOOL;             // 回风湿度有效（RA humidity valid）
    _bPOk              : BOOL;             // 大气压有限（Pressure finite）
    _bClampInfo        : BOOL;             // 下游钳位信息标志（Downstream clamp info flag，当拍）
    _bSwapInfo         : BOOL;             // 限幅域对调标志（Span-swap repair flag，公约 0.6，当拍）
    _bElseHit          : BOOL;             // 非法态兜底命中标志（Illegal-state fallback hit，当拍）
    fDbC               : REAL;             // 生效死区（Effective deadband）[kJ/kg] 负值钳位为 0 后
    fMinPosC           : REAL;             // 生效最小新风位（Effective min position）[百分数] 钳位域 0..100
    fCoolPosC          : REAL;             // 生效全开阀位（Effective free-cool position）[百分数] 钳位域 0..100
    fPosTmp            : REAL;             // 阀位对调交换中间变量（Damper swap temp carrier）[百分数]，生效域已防御值
    uErrOa             : UDINT;            // 新风焓值 FC 返回码（OA enthalpy FC code）
    uErrRa             : UDINT;            // 回风焓值 FC 返回码（RA enthalpy FC code）
    fbTrigReset        : R_TRIG;           // 复位信号上升沿检测实例（Reset edge detector）
END_VAR
VAR CONSTANT
    DL_ENT_INF_MAX     : REAL := 1.0E30;   // 有限值判定幅值上限（Magnitude bound for finite-value check）
    DL_ENT_OA_T_MIN    : REAL := -30.0;    // 新风温度验收域下限（OA temp domain floor）[摄氏度]
    DL_ENT_OA_T_MAX    : REAL := 60.0;     // 新风温度验收域上限（OA temp domain ceiling）[摄氏度]
    DL_ENT_RA_T_MIN    : REAL := 0.0;      // 回风温度验收域下限=焓值 FC 计算域下限（RA temp domain floor）[摄氏度]
    DL_ENT_RA_T_MAX    : REAL := 100.0;    // 回风温度验收域上限=焓值 FC 计算域上限（RA temp domain ceiling）[摄氏度]
    DL_ENT_RH_MIN      : REAL := 1.0;      // 湿度验收域下限（Humidity domain floor）[百分数]
    DL_ENT_RH_MAX      : REAL := 100.0;    // 湿度验收域上限（Humidity domain ceiling）[百分数]
    DL_ENT_POS_MIN     : REAL := 0.0;      // 阀位域下限（Damper domain floor）[百分数]
    DL_ENT_POS_MAX     : REAL := 100.0;    // 阀位域上限（Damper domain ceiling）[百分数]
END_VAR

// -----------------------------------------------------------------------------
// 段 1｜复位沿实例无条件周期刷新（R7 红线：严禁移入 IF/CASE 分支）
// -----------------------------------------------------------------------------
fbTrigReset(CLK := bReset);                 // 复位沿检测

// -----------------------------------------------------------------------------
// 段 2｜出口默认值与参数防御准备（公约 0.8：默认值先于防御路径；0.6 对调自修复）
// -----------------------------------------------------------------------------
uErrorId := 16#0000_0000;                   // 事件码先清零（后续按优先级覆盖）
_bClampInfo := FALSE;                       // 钳位信息标志每拍重算
_bSwapInfo := FALSE;                        // 对调标志每拍重算
_bElseHit := FALSE;                         // 兜底命中标志每拍重算
bEconomizerActive := FALSE;                 // 经济器指示默认停用（迟滞段重判）

fDbC := fEnthalpyDeadband;                  // 死区原值生效
IF fDbC <> fDbC THEN
    fDbC := 2.0;                            // 非数防御（公约 0.8 参数全覆盖，终审修复）：回落默认死区
END_IF
IF fDbC < 0.0 THEN
    fDbC := 0.0;                            // 防御钳位：负死区无物理意义，按 0（无迟滞）处理
END_IF

fMinPosC := fMinOaPos;                      // 最小新风位先做非数防御再钳位（终审修复）
IF fMinPosC <> fMinPosC THEN
    fMinPosC := 30.0;                       // 非数回落默认最小新风位 [百分数]
END_IF
fMinPosC := LIMIT(DL_ENT_POS_MIN, fMinPosC, DL_ENT_POS_MAX);      // 最小新风位钳位 [百分数]
fCoolPosC := fFreeCoolOaPos;                // 全开阀位先做非数防御再钳位（终审修复）
IF fCoolPosC <> fCoolPosC THEN
    fCoolPosC := 100.0;                     // 非数回落默认全开阀位 [百分数]
END_IF
fCoolPosC := LIMIT(DL_ENT_POS_MIN, fCoolPosC, DL_ENT_POS_MAX);    // 全开阀位钳位 [百分数]
IF fMinPosC > fCoolPosC THEN
    fPosTmp   := fMinPosC;                  // 对调经已防御生效值交换（中间变量，防原始引脚
    fMinPosC  := fCoolPosC;                 // 非有限值穿透回生效域，终审修复）
    fCoolPosC := fPosTmp;                   // 对调后半程
    _bSwapInfo := TRUE;                     // 对调事件置信息级标志（码 0005_0103，R11 D3）
END_IF

// -----------------------------------------------------------------------------
// 段 3｜R19 首扫/跟踪同步：判据唯一合法范式 IF bTrack OR (NOT bInit)
//       首扫输出最小新风位安全值；运行中途跟踪脉冲重建迟滞态不锁死（验收 V6）
// -----------------------------------------------------------------------------
IF bTrack OR (NOT bInit) THEN
    _eHyst := E_DL_EnthalpyHyst.eClosed;    // 迟滞态重建为关侧
    bEconomizerActive := FALSE;             // 经济器指示停用
    bHighLimitTrip := FALSE;                // 高限锁存重建
    fOaDamperCmd := fMinPosC;               // 首扫/跟踪安全值：最小新风位 [百分数]
    bInit := TRUE;                          // 首扫完成
END_IF

// -----------------------------------------------------------------------------
// 段 4｜输入有效性防御（公约 0.8：全部 REAL 输入先做 fX<>fX 检测再比较）
// -----------------------------------------------------------------------------
_bOaTOk := (NOT (fOaTempC <> fOaTempC)) AND (ABS(fOaTempC) <= DL_ENT_INF_MAX)
       AND (fOaTempC >= DL_ENT_OA_T_MIN) AND (fOaTempC <= DL_ENT_OA_T_MAX);      // 新风温度：非有限值 + 引脚域
_bOaROk := (NOT (fOaRelHum <> fOaRelHum)) AND (ABS(fOaRelHum) <= DL_ENT_INF_MAX)
       AND (fOaRelHum >= DL_ENT_RH_MIN) AND (fOaRelHum <= DL_ENT_RH_MAX);        // 新风湿度：非有限值 + 域
_bRaTOk := (NOT (fRaTempC <> fRaTempC)) AND (ABS(fRaTempC) <= DL_ENT_INF_MAX)
       AND (fRaTempC >= DL_ENT_RA_T_MIN) AND (fRaTempC <= DL_ENT_RA_T_MAX);      // 回风温度：非有限值 + 域
_bRaROk := (NOT (fRaRelHum <> fRaRelHum)) AND (ABS(fRaRelHum) <= DL_ENT_INF_MAX)
       AND (fRaRelHum >= DL_ENT_RH_MIN) AND (fRaRelHum <= DL_ENT_RH_MAX);        // 回风湿度：非有限值 + 域
_bPOk := (NOT (fAtmPress <> fAtmPress)) AND (ABS(fAtmPress) <= DL_ENT_INF_MAX);   // 大气压：仅非有限值防御（域由下游钳位）
_bInFailNow := NOT (_bOaTOk AND _bOaROk AND _bRaTOk AND _bRaROk AND _bPOk);       // 任一失效即本拍失效

// -----------------------------------------------------------------------------
// 段 5｜失效锁存（R15：锁存型只在解除路径清码——输入恢复 AND 复位沿）
// -----------------------------------------------------------------------------
IF _bInFailNow THEN
    _bFailLatch := TRUE;                    // 失效条件置位锁存
END_IF
IF fbTrigReset.Q AND (NOT _bInFailNow) THEN
    _bFailLatch := FALSE;                   // 解除路径：输入已恢复 + 复位沿
END_IF

// -----------------------------------------------------------------------------
// 段 6｜失效路径：安全侧兜底输出 + 诊断量冻结（R11 D2 裁定语义）
//       阀位指令回最小新风位；焓值/高限位保持末次有效值（FB 输出静态保持，
//       非未初始化路径，出口确定）
// -----------------------------------------------------------------------------
IF _bFailLatch THEN
    uErrorId := 16#0005_0202;               // 输入失效【故障级】（顺延码位，R11 D1）
    bEconomizerActive := FALSE;             // 安全侧：经济器停用
    _eHyst := E_DL_EnthalpyHyst.eClosed;    // 恢复后迟滞从关侧重建
    fOaDamperCmd := fMinPosC;               // 阀位兜底：最小新风位 [百分数]
    // fOaEnthalpy / fRaEnthalpy / bHighLimitTrip 不赋值 = 冻结末次有效值
ELSE

    // -------------------------------------------------------------------------
    // 段 7｜焓值计算：每拍两次调用 FC_DL_HumidAirEnthalpy（公开接口直接调用，
    //       禁止内联重实现其公式链）
    // -------------------------------------------------------------------------
    uErrOa := 16#0000_0000;                 // 返回码先清零
    uErrRa := 16#0000_0000;                 // 返回码先清零
    fOaEnthalpy := FC_DL_HumidAirEnthalpy(fTempC := fOaTempC, fRelHum := fOaRelHum,
                                          fAtmPress := fAtmPress, uErrorId => uErrOa);  // 新风比焓 [kJ/kg 干空气]
    fRaEnthalpy := FC_DL_HumidAirEnthalpy(fTempC := fRaTempC, fRelHum := fRaRelHum,
                                          fAtmPress := fAtmPress, uErrorId => uErrRa);  // 回风比焓 [kJ/kg 干空气]

    // 双调用返回码并集归并（0.8 防御兜底：下游拒绝码理论上段 4 已拦截）
    IF (uErrOa = 16#0002_0004) OR (uErrRa = 16#0002_0004) THEN
        _bFailLatch := TRUE;                // 下游拒绝 → 转入失效锁存（下一拍走段 6）
        uErrorId := 16#0005_0202;           // 输入失效【故障级】
        bEconomizerActive := FALSE;         // 安全侧停用
        fOaDamperCmd := fMinPosC;           // 阀位兜底 [百分数]
    ELSE
        _bClampInfo := (uErrOa <> 16#0000_0000) OR (uErrRa <> 16#0000_0000);
                                            // 任一钳位码（1701/1702/1703）→ 信息级透传归并（R11 D4）

        // ---------------------------------------------------------------------
        // 段 8｜高限停机（ASHRAE 90.1 语义）：瞬时型每拍重算 + 死区回差防振荡
        //       （R15：非锁存位，激活条件存在即呈现，回差内保持）
        // ---------------------------------------------------------------------
        IF (fEnthalpyHighLimit = fEnthalpyHighLimit) AND (fEnthalpyHighLimit > 0.0) THEN
            // 非数门限按禁用处理（公约 0.8 显式检测，终审修复：NaN 比较恒 FALSE
            // 虽天然落入禁用分支，仍显式自比检测防方言差异）
            IF fOaEnthalpy >= fEnthalpyHighLimit THEN
                bHighLimitTrip := TRUE;     // 新风焓达高限 → 停机锁激活
            ELSIF fOaEnthalpy < (fEnthalpyHighLimit - fDbC) THEN
                bHighLimitTrip := FALSE;    // 回落至回差下界之下才解除
            END_IF                          // 回差区间内保持原态（防临界振荡）
        ELSE
            bHighLimitTrip := FALSE;        // 门限 0 = 高限停机禁用
        END_IF

        // ---------------------------------------------------------------------
        // 段 9｜差分焓值迟滞状态机（ENUM + CASE + ELSE 兜底，红线 R6）
        //       【干球陷阱警示】此处只允许焓差比较，严禁改为干球温差判据
        // ---------------------------------------------------------------------
        CASE _eHyst OF

            E_DL_EnthalpyHyst.eClosed:      // 关侧：等待开侧判据
                IF bEnableCooling AND (NOT bHighLimitTrip)
                   AND (fOaEnthalpy < fRaEnthalpy - fDbC) THEN
                    _eHyst := E_DL_EnthalpyHyst.eOpened;   // 新风焓显著低于回风 → 开侧
                END_IF

            E_DL_EnthalpyHyst.eOpened:      // 开侧：等待关侧判据或退出条件
                IF (NOT bEnableCooling) OR bHighLimitTrip
                   OR (fOaEnthalpy > fRaEnthalpy + fDbC) THEN
                    _eHyst := E_DL_EnthalpyHyst.eClosed;   // 退出条件任一 → 关侧
                END_IF

            ELSE                            // 非法状态兜底（故障级 0005_0201）
                _bElseHit := TRUE;          // 当拍呈现码
                _eHyst := E_DL_EnthalpyHyst.eClosed;       // 回关侧安全态
        END_CASE

        // ---------------------------------------------------------------------
        // 段 10｜输出合成：经济器指示 + 阀位指令（最小新风硬下限双保险）
        // ---------------------------------------------------------------------
        bEconomizerActive := (_eHyst = E_DL_EnthalpyHyst.eOpened);  // 判据通过且迟滞态为开侧
        IF bEconomizerActive THEN
            fOaDamperCmd := fCoolPosC;      // 激活：经济器全开位 [百分数]
        ELSE
            fOaDamperCmd := fMinPosC;       // 非激活：最小新风位 [百分数]
        END_IF
        fOaDamperCmd := MAX(fOaDamperCmd, fMinPosC);   // 硬下限出口断言（对调后恒真，双保险）

        // ---------------------------------------------------------------------
        // 段 11｜事件码优先级合成（R21：信息级只进 uErrorId）：兜底 > 信息级 > 无
        // ---------------------------------------------------------------------
        IF _bElseHit THEN
            uErrorId := 16#0005_0201;       // 非法状态兜底【故障级】（复用同义码，R11 D1）
        ELSIF _bClampInfo OR _bSwapInfo THEN
            uErrorId := 16#0005_0103;       // 下游钳位透传 / 限幅域对调【信息级】
        END_IF                              // 否则保持段 2 清零值
    END_IF
END_IF

END_FUNCTION_BLOCK
