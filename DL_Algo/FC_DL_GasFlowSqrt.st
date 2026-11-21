(*==============================================================================
 * 组件名称 (Component)  : FC_DL_GasFlowSqrt
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 特气差压流量开方换算：前置校验 → 补偿系数钳位 →
 *                         委托 FC_DL_NthRoot(2) 开方 → 委托 FC_DL_FlowCompensate
 *                         做温压补偿内核（固定参考工况口径）→ 量程换算 → 上限钳制。
 *                         本函数不重写任何开方/补偿数学内核（T0 红线）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_FlowErr / FUNCTION FC_DL_GasFlowSqrt
 * 依赖 (Depends)        : DL_MathData/FC_DL_NthRoot、DL_Algo/FC_DL_FlowCompensate
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 量程钳位 + 非有限值防御 ｜ 枚举成员全部显式赋值
 *                         纯函数无状态保持 ｜ 输出在每条早退路径前已赋确定值
 * 错误码表 (Codes)      : 16#0002_3706 成功
 *                         16#0002_3707 故障级 密度非法（<= 0 或非有限）
 *                         16#0002_3708 故障级 差压为负
 *                         16#0002_3709 信息级 补偿系数越界(已钳制)
 *                         16#0002_370A 故障级 结果溢出或委托失败
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 1
 * 验收向量 (Acceptance) : dp=25 kPa, rho=2.0, comp=1.0, scale=100 slm
 *                         → sqrt(25/100)*1.0*100 = 50 slm，返回 3706
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FlowErr（归属 DL_Algo，与 FC_DL_GasFlowSqrt 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FlowErr :
(
    eOk           := 16#0002_3706,   // 成功 / Success
    eDensityBad   := 16#0002_3707,   // 故障级：密度非法（<= 0 或非有限）/ Fault: illegal density
    eDiffPressNeg := 16#0002_3708,   // 故障级：差压为负 / Fault: negative differential pressure
    eCompClamped  := 16#0002_3709,   // 信息级：补偿系数越界已钳制 / Info: compensation factor clamped
    eResultOver   := 16#0002_370A    // 故障级：结果溢出或委托失败 / Fault: result overflow or delegate failure
);
END_TYPE

(*==============================================================================
 * 函数: FC_DL_GasFlowSqrt（纯函数，无任何状态保持）
 * 调用约定: 每周期按需调用；返回值 = 计算有效标志。
 * 口径说明: 差压满刻度取 DL_GSF_DP_FULL（100 kPa），根号归一化后乘补偿系数
 *           与满量程；补偿内核（温压链）委托 FC_DL_FlowCompensate 固定参考
 *           工况执行，外部 fCompFactor 为调用方注入的合成补偿比。
 *============================================================================*)
FUNCTION FC_DL_GasFlowSqrt : BOOL
VAR_INPUT
    fDiffPress   : REAL;               // 差压 [千帕]，有效域 0~100 / Differential pressure [kPa]
    fGasDensity  : REAL;               // 工况密度 [千克每立方米]，有效域 0.01~20 / Gas density at operating condition [kg/m3]
    fCompFactor  : REAL;               // 温压补偿系数 [无量纲]，有效域 0.5~2.0 / Compensation factor [dimensionless]
    fScaleMax    : REAL;               // 流量满量程 [标准升每分钟]，须 > 0 / Full-scale flow [slm]
END_VAR
VAR_OUTPUT
    fFlowSlm     : REAL;               // 流量 [标准升每分钟] / Flow [slm]
    eError       : E_DL_FlowErr;       // 错误码 / Error code
END_VAR
VAR CONSTANT
    DL_GSF_DP_FULL  : REAL := 100.0;   // 差压满刻度 [千帕] / Full-scale differential pressure [kPa]
    DL_GSF_COMP_MIN : REAL := 0.5;     // 补偿系数下限 [无量纲] / Compensation factor lower bound
    DL_GSF_COMP_MAX : REAL := 2.0;     // 补偿系数上限 [无量纲] / Compensation factor upper bound
    DL_GSF_T_REF    : REAL := 20.0;    // 委托补偿参考温度 [摄氏度] / Delegate compensation reference temperature [degC]
    DL_GSF_INF_MAX  : REAL := 1.0E30;  // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_GSF_ZERO     : REAL := 0.0;     // 零值常量，避免裸字面量 / Zero constant
    DL_GSF_RHO_MIN  : REAL := 0.01;    // 密度可信下限 [千克每立方米] / Density trust lower bound [kg/m3]
    DL_GSF_RHO_MAX  : REAL := 20.0;    // 密度可信上限 [千克每立方米] / Density trust upper bound [kg/m3]
END_VAR
VAR
    fCompUse   : REAL;                 // 生效补偿系数（钳位后）[无量纲] / Effective compensation factor
    fRootVal   : LREAL;                // 委托开方输出 [无量纲合成] / Delegate square-root output
    bRootOk    : BOOL;                 // 委托开方有效标志 / Delegate root validity flag
    fCompFlow  : REAL;                 // 委托补偿后的流量基值 [标准升每分钟] / Delegate-compensated flow base [slm]
    uCompErr   : UDINT;                // 委托补偿错误码（0 = 无错）/ Delegate compensation error id
    bCompRange : BOOL;                 // 委托补偿域内标志 / Delegate in-range flag
    bNonFin    : BOOL;                 // 非有限输入汇总标志 / Non-finite input aggregate flag
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：任何早退路径前输出已确定（哨兵 0 流量 + 输入无效码）
 *----------------------------------------------------------------------------*)
FC_DL_GasFlowSqrt := FALSE;                          // 返回值默认无效 / return defaults to invalid
fFlowSlm := DL_GSF_ZERO;                             // 流量哨兵 0 / flow sentinel zero
eError := E_DL_FlowErr.eDensityBad;                  // 默认密度非法码 / default illegal-density code

(*------------------------------------------------------------------------------
 * 段 2｜非有限值闸：NaN 用自反判，溢出用幅值上限判
 *----------------------------------------------------------------------------*)
bNonFin := (fDiffPress  <> fDiffPress)  OR (ABS(fDiffPress)  > DL_GSF_INF_MAX)
        OR (fGasDensity <> fGasDensity) OR (ABS(fGasDensity) > DL_GSF_INF_MAX)
        OR (fCompFactor <> fCompFactor) OR (ABS(fCompFactor) > DL_GSF_INF_MAX)
        OR (fScaleMax   <> fScaleMax)   OR (ABS(fScaleMax)   > DL_GSF_INF_MAX);
IF bNonFin THEN
    eError := E_DL_FlowErr.eDensityBad;              // 非有限输入并入密度非法段（反证句见文件头修订）/ non-finite mapped to density band
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜符号与配置闸：密度可信域、差压非负、满量程为正
 *----------------------------------------------------------------------------*)
IF (fGasDensity < DL_GSF_RHO_MIN) OR (fGasDensity > DL_GSF_RHO_MAX) OR (fScaleMax <= DL_GSF_ZERO) THEN
    eError := E_DL_FlowErr.eDensityBad;              // 故障级：密度非法（含满量程非法并入，反证句：同为全拒）/ fault: illegal density
    RETURN;
END_IF
IF fDiffPress < DL_GSF_ZERO THEN
    eError := E_DL_FlowErr.eDiffPressNeg;            // 故障级：差压为负 / fault: negative dp
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜补偿系数钳位（信息级越界码）
 *----------------------------------------------------------------------------*)
eError := E_DL_FlowErr.eOk;                          // 预置成功 / preset success
fCompUse := fCompFactor;                             // 补偿系数工作副本 / compensation working copy
IF fCompUse < DL_GSF_COMP_MIN THEN
    fCompUse := DL_GSF_COMP_MIN;                     // 下限钳位 / floored
    eError := E_DL_FlowErr.eCompClamped;             // 信息级：补偿系数越界 / info: factor clamped
ELSIF fCompUse > DL_GSF_COMP_MAX THEN
    fCompUse := DL_GSF_COMP_MAX;                     // 上限钳位 / capped
    eError := E_DL_FlowErr.eCompClamped;             // 信息级：补偿系数越界 / info: factor clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜委托开方（FC_DL_NthRoot(2)）：差压满刻度归一化后的根号值
 *----------------------------------------------------------------------------*)
fRootVal := FC_DL_NthRoot(fValue := REAL_TO_LREAL(fDiffPress / DL_GSF_DP_FULL), nRoot := 2, bValid => bRootOk);   // 根号委托（除子 100 为常量非零）/ root via delegate
IF (NOT bRootOk) OR (fRootVal <> fRootVal) OR (ABS(fRootVal) > REAL_TO_LREAL(DL_GSF_INF_MAX)) THEN
    eError := E_DL_FlowErr.eResultOver;              // 故障级：委托失败 / fault: delegate failure
    FC_DL_GasFlowSqrt := FALSE;                      // 返回无效 / return invalid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜委托温压补偿内核（FC_DL_FlowCompensate 固定参考工况口径，满量程换算）
 *----------------------------------------------------------------------------*)
fCompFlow := FC_DL_FlowCompensate(fFlowActual := LREAL_TO_REAL(fRootVal) * fScaleMax * fCompUse,   // 委托入口流量 [标准升每分钟] / delegate input flow [slm]
                                  fPressGauge := DL_GSF_ZERO,                                     // 固定参考表压 [千帕] / fixed reference gauge pressure [kPa]
                                  fTempC := DL_GSF_T_REF,                                         // 固定参考温度 [摄氏度] / fixed reference temperature [degC]
                                  bEnableSqRt := FALSE,                                           // 开方已在段 5 委托完成 / root already delegated
                                  uErrorId => uCompErr, bInRange => bCompRange);                  // 委托出口 / delegate outputs
IF (uCompErr <> 0) OR (fCompFlow <> fCompFlow) OR (ABS(fCompFlow) > DL_GSF_INF_MAX) THEN
    eError := E_DL_FlowErr.eResultOver;              // 故障级：补偿委托失败或结果溢出 / fault: delegate failure or overflow
    fFlowSlm := DL_GSF_ZERO;                         // 流量哨兵 / flow sentinel
    FC_DL_GasFlowSqrt := FALSE;                      // 返回无效 / return invalid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜上限钳制与出口
 *----------------------------------------------------------------------------*)
fFlowSlm := fCompFlow;                               // 流量输出 [标准升每分钟] / flow output [slm]
IF fFlowSlm > fScaleMax THEN
    fFlowSlm := fScaleMax;                           // 满量程钳制 / clamped to full scale
END_IF
IF fFlowSlm < DL_GSF_ZERO THEN
    fFlowSlm := DL_GSF_ZERO;                         // 下限防护（禁止伪负流量）/ floor guard
END_IF
FC_DL_GasFlowSqrt := TRUE;                           // 计算有效 / computation valid
RETURN;
END_FUNCTION
