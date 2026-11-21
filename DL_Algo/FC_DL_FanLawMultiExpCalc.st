(*==============================================================================
 * 组件名称 (Component)  : FC_DL_FanLawMultiExpCalc
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 命名说明 (Naming)     : 本件与既有 DL_MathData/FC_DL_FanLawRootCalc（固定 1/2/3 指数）同名会
 *                         构成全库同 POU 重名（CODESYS 编译期重复标识符），且本件口径是
 *                         「指数三量各自可组态」，故按多指数语义另立本名，旧件保持不动。
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 风机相似定律三量换算件。以转速比为唯一自变量，按可组态
 *                         指数分别换算流量、压升与轴功率；只做前域校验与换算，不做
 *                         转速闭环、不做喘振/失速判定、不做单位制换算、不做多机并联
 *                         分配。返回 TRUE 表示本拍三输出已更新且可表，返回 FALSE 表示
 *                         本拍未产生有效换算（引脚保持上次值，绝不写 0 冒充工况）。
 * 溯源 (Origin)         : IEC 61131-3 标准语义的道莅防御性实现
 * 本文件内含 (Contains) : FUNCTION FC_DL_FanLawMultiExpCalc（码表以 VAR CONSTANT 同文件声明）
 * 依赖 (Depends)        : 无（仅 Standard.library 的 EXPT / ABS）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         参考量判零防除零 ｜ 指数与比值双向钳位 ｜ 输出非有限与 1e12 溢出
 *                         双重复检 ｜ 本件为纯算术件、无状态机，故无 CASE 分支（不设
 *                         ELSE 兜底项的说明在此登记）｜ 无定时器与沿实例，无周期刷新项
 * 错误码表 (Codes)      : 16#0002_3715 就绪/成功（三输出已按本拍输入更新）
 *                         16#0002_3716 故障级 组态/输入非法（参考量判零、指数出域、比值上限
 *                                    出域）。反证句：指数出域的钳制事实无法由 3717 观测
 *                                    （3717 只表达比值钳制），故必须独立成码
 *                         16#0002_3717 信息级 转速比越上限已钳制（输出仍有效，不置故障级）
 *                         16#0002_3718 故障级 换算结果非有限或超 1e12 不可表。反证句：
 *                                    「输出不更新」这一事实可由调用方比对上一拍快照观测，
 *                                    但原因（溢出/非有限）不可观测，故独立成码
 *                         16#0002_3719 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 1
 * 验收向量 (Acceptance) : 正向 1450 rpm 参考 / 1200 rpm 当前（比 0.8276）+ 参考
 *                         10000 m³/h / 800 Pa / 15 kW + 指数 1/2/3 → 8276 m³/h /
 *                         547.7 Pa / 8.50 kW + 16#0002_3715，返回 TRUE
 *                         反向 参考转速改 0 → 16#0002_3716、返回 FALSE、三输出保持上次
 *                         有效值（非 0）；参考转速给 NaN → 同 3716；比值请求 2.5 超上限
 *                         1.5 → 比值钳 1.5 + 16#0002_3717 且返回 TRUE
 *============================================================================*)

FUNCTION FC_DL_FanLawMultiExpCalc : BOOL
VAR_INPUT
    bEnable       : BOOL := TRUE;         // 使能，FALSE 冻结三输出并只回就绪码 / Enable, FALSE freezes the outputs and reports ready only
    fSpeedRef_rpm : REAL := 1450.0;       // 参考转速 [rpm]，域 1~20000 / Reference speed in rpm, domain 1 to 20000
    fSpeedNow_rpm : REAL := 0.0;          // 当前转速 [rpm]，域 0~30000 / Present speed in rpm, domain 0 to 30000
    fFlowRef_m3h  : REAL := 10000.0;      // 参考流量 [m³/h]，须 >0 / Reference flow in cubic metres per hour, must be positive
    fPressRef_Pa  : REAL := 800.0;        // 参考压升 [Pa]，须 >0 / Reference pressure rise in pascal, must be positive
    fPowerRef_kW  : REAL := 15.0;         // 参考轴功率 [kW]，须 >0 / Reference shaft power in kilowatt, must be positive
    fExpFlow      : REAL := 1.0;          // 流量指数 [—]，域 0.5~4.0 / Flow exponent, domain 0.5 to 4.0
    fExpPress     : REAL := 2.0;          // 压升指数 [—]，域 0.5~4.0 / Pressure exponent, domain 0.5 to 4.0
    fExpPower     : REAL := 3.0;          // 功率指数 [—]，域 0.5~4.0 / Power exponent, domain 0.5 to 4.0
    fRatioMax     : REAL := 1.5;          // 转速比上限 [—]，域 0.5~3.0 / Speed ratio upper limit, domain 0.5 to 3.0
END_VAR
VAR_OUTPUT
    fFlowOut_m3h  : REAL;                 // 换算流量 [m³/h]，故障拍不写即保持 / Converted flow in cubic metres per hour, held on fault scans
    fPressOut_Pa  : REAL;                 // 换算压升 [Pa]，故障拍不写即保持 / Converted pressure rise in pascal, held on fault scans
    fPowerOut_kW  : REAL;                 // 换算轴功率 [kW]，故障拍不写即保持 / Converted shaft power in kilowatt, held on fault scans
    fSpeedRatio   : REAL;                 // 实际采用转速比（已钳制）[—] / Effective speed ratio after clamping
    eErr          : UDINT;                // 错误码，段位 16#0002_xxxx / Error code in segment 16#0002_xxxx
END_VAR
VAR
    fRatio        : REAL;                 // 未钳制转速比 [—] / Unclamped speed ratio
    fRatioLim     : REAL;                 // 生效转速比上限 [—] / Effective speed ratio limit
    fExpQ         : REAL;                 // 生效流量指数 [—] / Effective flow exponent
    fExpP         : REAL;                 // 生效压升指数 [—] / Effective pressure exponent
    fExpW         : REAL;                 // 生效功率指数 [—] / Effective power exponent
    fFlowC        : REAL;                 // 流量换算中间值 [m³/h] / Intermediate flow value in cubic metres per hour
    fPressC       : REAL;                 // 压升换算中间值 [Pa] / Intermediate pressure value in pascal
    fPowerC       : REAL;                 // 功率换算中间值 [kW] / Intermediate power value in kilowatt
    bCfgOk        : BOOL;                 // 组态与输入域合法标志 / Configuration and input domain flag
    bClamp        : BOOL;                 // 比值钳制发生标志 / Ratio clamped flag
    bOutOk        : BOOL;                 // 三输出可表性复检标志 / Output representability flag
END_VAR
VAR CONSTANT
    DL_FAN_READY   : UDINT := 16#0002_3715;  // 就绪/成功码 / Ready or success code
    DL_FAN_CFG_BAD : UDINT := 16#0002_3716;  // 故障级组态/输入非法码 / Fault code for bad configuration or input
    DL_FAN_CLAMP   : UDINT := 16#0002_3717;  // 信息级比值钳制码 / Info code for clamped ratio
    DL_FAN_OVER    : UDINT := 16#0002_3718;  // 故障级输出不可表码 / Fault code for unrepresentable output
    DL_FAN_EXP_MIN : REAL := 0.5;            // 指数下限 [—] / Exponent lower bound
    DL_FAN_EXP_MAX : REAL := 4.0;            // 指数上限 [—] / Exponent upper bound
    DL_FAN_RATIO_LO : REAL := 0.5;           // 比值上限下限 [—] / Lower bound of the ratio limit parameter
    DL_FAN_RATIO_HI : REAL := 3.0;           // 比值上限上限 [—] / Upper bound of the ratio limit parameter
    DL_FAN_RATIO_DEF : REAL := 1.5;          // 比值上限缺省值 [—] / Default ratio limit
    DL_FAN_MAG_MAX : REAL := 1.0E12;         // 输出可表幅值上限 [m³/h 或 Pa 或 kW] / Output magnitude bound
END_VAR

// 段 1｜返回值与码位预置（不触碰三输出引脚：不写即保持上次有效值，禁写 0）
FC_DL_FanLawMultiExpCalc := FALSE;                          // 返回值预置为「本拍无有效换算」 / Pre-set to "no valid conversion this scan"
eErr := DL_FAN_READY;                                   // 码位预置为就绪 / Code pre-set to ready

// 段 2｜使能闸：禁用期冻结三输出，只回就绪码（上层读旧值不被污染）
IF NOT bEnable THEN
    RETURN;                                             // 引脚保持上次有效值 / The pins keep their last valid values
END_IF

// 段 3｜非有限闸：NaN 用自反比较判、Inf 用差值自反判，禁近似阈值
IF (fSpeedRef_rpm <> fSpeedRef_rpm) OR ((fSpeedRef_rpm - fSpeedRef_rpm) <> (fSpeedRef_rpm - fSpeedRef_rpm)) THEN
    eErr := DL_FAN_CFG_BAD;                             // 参考转速非有限 / Reference speed not finite
    RETURN;
END_IF
IF (fSpeedNow_rpm <> fSpeedNow_rpm) OR ((fSpeedNow_rpm - fSpeedNow_rpm) <> (fSpeedNow_rpm - fSpeedNow_rpm)) THEN
    eErr := DL_FAN_CFG_BAD;                             // 当前转速非有限 / Present speed not finite
    RETURN;
END_IF
IF (fFlowRef_m3h <> fFlowRef_m3h) OR ((fFlowRef_m3h - fFlowRef_m3h) <> (fFlowRef_m3h - fFlowRef_m3h)) THEN
    eErr := DL_FAN_CFG_BAD;                             // 参考流量非有限 / Reference flow not finite
    RETURN;
END_IF
IF (fPressRef_Pa <> fPressRef_Pa) OR ((fPressRef_Pa - fPressRef_Pa) <> (fPressRef_Pa - fPressRef_Pa)) THEN
    eErr := DL_FAN_CFG_BAD;                             // 参考压升非有限 / Reference pressure not finite
    RETURN;
END_IF
IF (fPowerRef_kW <> fPowerRef_kW) OR ((fPowerRef_kW - fPowerRef_kW) <> (fPowerRef_kW - fPowerRef_kW)) THEN
    eErr := DL_FAN_CFG_BAD;                             // 参考功率非有限 / Reference power not finite
    RETURN;
END_IF
IF (fRatioMax <> fRatioMax) OR ((fRatioMax - fRatioMax) <> (fRatioMax - fRatioMax)) THEN
    eErr := DL_FAN_CFG_BAD;                             // 比值上限非有限 / Ratio limit not finite
    RETURN;
END_IF

// 段 4｜参考量判零闸（防除零；0 参考量换算出的 0 会被上位当真实工况）
IF (fSpeedRef_rpm <= 0.0) OR (fFlowRef_m3h <= 0.0) OR (fPressRef_Pa <= 0.0) OR (fPowerRef_kW <= 0.0) THEN
    eErr := DL_FAN_CFG_BAD;                             // 参考量判零拒绝 / Reference quantity rejected at zero or negative
    RETURN;
END_IF

// 段 5｜指数域钳制（出域即钳制并显式报组态错，不静默沿用非法指数）
bCfgOk := TRUE;                                         // 组态合法假设成立 / Assume configuration is valid
fExpQ := fExpFlow;                                      // 流量指数取输入值 / Take the flow exponent from the input
IF (fExpQ <> fExpQ) OR ((fExpQ - fExpQ) <> (fExpQ - fExpQ)) THEN
    fExpQ := 1.0;                                       // 非有限按缺省指数 / Non-finite falls back to the default exponent
    bCfgOk := FALSE;
ELSE
    IF fExpQ < DL_FAN_EXP_MIN THEN
        fExpQ := DL_FAN_EXP_MIN;                        // 下限钳制 / Clamp to the lower bound
        bCfgOk := FALSE;
    END_IF
    IF fExpQ > DL_FAN_EXP_MAX THEN
        fExpQ := DL_FAN_EXP_MAX;                        // 上限钳制 / Clamp to the upper bound
        bCfgOk := FALSE;
    END_IF
END_IF
fExpP := fExpPress;                                     // 压升指数取输入值 / Take the pressure exponent from the input
IF (fExpP <> fExpP) OR ((fExpP - fExpP) <> (fExpP - fExpP)) THEN
    fExpP := 2.0;                                       // 非有限按缺省指数 / Non-finite falls back to the default exponent
    bCfgOk := FALSE;
ELSE
    IF fExpP < DL_FAN_EXP_MIN THEN
        fExpP := DL_FAN_EXP_MIN;                        // 下限钳制 / Clamp to the lower bound
        bCfgOk := FALSE;
    END_IF
    IF fExpP > DL_FAN_EXP_MAX THEN
        fExpP := DL_FAN_EXP_MAX;                        // 上限钳制 / Clamp to the upper bound
        bCfgOk := FALSE;
    END_IF
END_IF
fExpW := fExpPower;                                     // 功率指数取输入值 / Take the power exponent from the input
IF (fExpW <> fExpW) OR ((fExpW - fExpW) <> (fExpW - fExpW)) THEN
    fExpW := 3.0;                                       // 非有限按缺省指数 / Non-finite falls back to the default exponent
    bCfgOk := FALSE;
ELSE
    IF fExpW < DL_FAN_EXP_MIN THEN
        fExpW := DL_FAN_EXP_MIN;                        // 下限钳制 / Clamp to the lower bound
        bCfgOk := FALSE;
    END_IF
    IF fExpW > DL_FAN_EXP_MAX THEN
        fExpW := DL_FAN_EXP_MAX;                        // 上限钳制 / Clamp to the upper bound
        bCfgOk := FALSE;
    END_IF
END_IF

// 段 6｜比值上限合法域校验（出域回缺省，避免 0 上限把全部工况钳成静止）
fRatioLim := fRatioMax;                                 // 比值上限取输入值 / Take the ratio limit from the input
IF (fRatioLim < DL_FAN_RATIO_LO) OR (fRatioLim > DL_FAN_RATIO_HI) THEN
    fRatioLim := DL_FAN_RATIO_DEF;                      // 出域回缺省 1.5 / Out of domain falls back to 1.5
    bCfgOk := FALSE;
END_IF

// 段 7｜转速比求取与双向钳制（除数已在段 4 判零，此处除零不可达）
fRatio := (fSpeedNow_rpm / fSpeedRef_rpm);              // 转速比 = 当前 / 参考 [—] / Speed ratio, present over reference
bClamp := FALSE;                                        // 钳制标志预清 / Clamp flag pre-cleared
IF fRatio < 0.0 THEN
    fRatio := 0.0;                                      // 反转工况钳 0，不参与负指数运算 / Reverse rotation clamped to zero
    bClamp := TRUE;
END_IF
IF fRatio > fRatioLim THEN
    fRatio := fRatioLim;                                // 超上限钳制（超速区相似定律失效） / Clamp above the limit, similarity law invalid in the overspeed region
    bClamp := TRUE;
END_IF

// 段 8｜三量换算（相似定律：流量比 ^ 流量指数、压升比 ^ 压升指数、功率比 ^ 功率指数）
fFlowC := fFlowRef_m3h * EXPT(fRatio, fExpQ);           // 流量换算 [m³/h] / Flow conversion in cubic metres per hour
fPressC := fPressRef_Pa * EXPT(fRatio, fExpP);          // 压升换算 [Pa] / Pressure conversion in pascal
fPowerC := fPowerRef_kW * EXPT(fRatio, fExpW);          // 功率换算 [kW] / Power conversion in kilowatt

// 段 9｜输出复检（非有限或超 1e12 不可表 → 不写引脚，保持上次有效值）
bOutOk := TRUE;                                         // 可表性假设成立 / Assume the outputs are representable
IF (fFlowC <> fFlowC) OR ((fFlowC - fFlowC) <> (fFlowC - fFlowC)) OR (ABS(fFlowC) > DL_FAN_MAG_MAX) THEN
    bOutOk := FALSE;                                    // 流量不可表 / Flow not representable
END_IF
IF (fPressC <> fPressC) OR ((fPressC - fPressC) <> (fPressC - fPressC)) OR (ABS(fPressC) > DL_FAN_MAG_MAX) THEN
    bOutOk := FALSE;                                    // 压升不可表 / Pressure not representable
END_IF
IF (fPowerC <> fPowerC) OR ((fPowerC - fPowerC) <> (fPowerC - fPowerC)) OR (ABS(fPowerC) > DL_FAN_MAG_MAX) THEN
    bOutOk := FALSE;                                    // 功率不可表 / Power not representable
END_IF
IF NOT bOutOk THEN
    eErr := DL_FAN_OVER;                                // 故障级：输出不可表 / Fault, output not representable
    RETURN;                                             // 三输出引脚保持上次有效值 / Keep the last valid output values
END_IF

// 段 10｜输出落定与码位定稿（本拍换算有效）
fFlowOut_m3h := fFlowC;                                 // 落定流量 [m³/h] / Latch the converted flow
fPressOut_Pa := fPressC;                                // 落定压升 [Pa] / Latch the converted pressure
fPowerOut_kW := fPowerC;                                // 落定功率 [kW] / Latch the converted power
fSpeedRatio := fRatio;                                  // 落定实际采用比值 [—] / Latch the effective ratio
IF bClamp THEN
    eErr := DL_FAN_CLAMP;                               // 信息级：比值已钳制 / Info, ratio clamped
ELSE
    eErr := DL_FAN_READY;                               // 就绪/成功 / Ready or success
END_IF
IF NOT bCfgOk THEN
    eErr := DL_FAN_CFG_BAD;                             // 组态错显式上报（输出已按钳制指数更新） / Configuration error reported explicitly, outputs updated with the clamped exponents
    RETURN;                                             // 返回 FALSE：组态待整改 / Return FALSE, the configuration needs correction
END_IF

FC_DL_FanLawMultiExpCalc := TRUE;                           // 本拍换算有效且可表 / A valid and representable conversion was produced
END_FUNCTION
