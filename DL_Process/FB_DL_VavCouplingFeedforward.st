(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VavCouplingFeedforward
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 暖通前馈 · 变风量耦合
 *                         industry-pool / hvac / vav / feedforward
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 ABS
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 送风温度偏离设计值时按显热守恒比例前馈修正风量
 *                         给定，替代反馈环慢慢追赶，防送风温度-风量耦合振荡。
 *
 * 功能描述 (Function)   : 显热守恒：风量与（室温设定 − 送风温度）成反比，
 *                         前馈量 = 设计风量 × 设计温差 ÷ 当前温差；当前温差
 *                         绝对值小于容差时视为近设计工况，恒等输出设计风量
 *                         并报信息级；输入非有限冻结输出（故障级）；送风
 *                         过热（温差反号）按最小风量保守输出；结果钳位到
 *                         风量上下限并报钳位码。内部状态与输出模式分离，
 *                         输出预置不触碰状态驻留量（R19）。
 * 与既有件边界 (Boundary): 本件只做静态前馈，不含反馈环与执行器控制；
 *                         VAV 盒反馈控制归 FB_DL_VavBoxCtrl，二者级联使用。
 * 码位说明 (Codes)      : 信息 16#0006_300A 近设计工况恒等输出设计风量
 *                         故障 16#0006_300B 输入非有限，输出冻结
 *                         故障 16#0006_300C 送风过热（温差反号），按最小风量保守
 *                         故障 16#0006_300D 结果越限已钳位到风量上下限
 *                         段 16#06_0_0A~0E 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 ABS。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         除法前强制判零（温差容差闸）｜ 浮点比较带 fEps 容差
 *                         NaN/Inf 精确判据拦截 ｜ ENUM 配 CASE 且 ELSE 兜底
 *                         全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 3）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_VavCouplingFeedforward
VAR_INPUT
    bRun        : BOOL;                     // 前馈使能，假则输出设计风量并停算 / Enable, FALSE outputs the design flow
    fTsaC       : LREAL;                    // 送风温度 [degC] / Supply air temperature
    fTsaDesignC : LREAL := 13.0;            // 设计送风温度 [degC] / Design supply air temperature
    fRoomSetC   : LREAL := 24.0;            // 室温设定 [degC] / Room setpoint
    fQDesign    : LREAL := 500.0;           // 设计风量 [m3/h] / Design airflow
    fQMin       : LREAL := 100.0;           // 最小风量 [m3/h] / Minimum airflow
    fQMax       : LREAL := 1200.0;          // 最大风量 [m3/h] / Maximum airflow
    fDtEps      : LREAL := 0.5;             // 温差容差 [K]，低于此视为近设计 / Delta-T tolerance
    fEps        : LREAL := 1.0E-6;          // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    eMode   : (eBypass := 0, eAuto := 1);       // 模式枚举输出：旁路/自动 / Mode output enum
    fQFf    : LREAL;                    // 前馈风量给定 [m3/h] / Feedforward airflow setpoint
    bClamp  : BOOL;                     // 钳位标志，结果被上下限裁剪时为真 / TRUE when the result was clamped
    bValid  : BOOL;                     // 前馈有效标志，冻结期间为假 / TRUE when the output is valid
    bError  : BOOL;                     // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId: UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    _eState   : (eStBypass := 0, eStAuto := 1);     // 内部状态机：旁路/自动，输出预置不触碰 / Internal state, never pre-set
    fDtDesign : LREAL;  // 设计温差 [K]，室温设定减设计送风温度 / Design delta-T
    fDtNow    : LREAL;  // 当前温差 [K] / Current delta-T
    fRatio    : LREAL;  // 温差比 [比值]，设计温差除当前温差 / Delta-T ratio
    fQCalc    : LREAL;  // 计算风量 [m3/h] / Calculated airflow
    bSigOk    : BOOL;   // 输入有效标志 / Input validity flag
    uCode     : UDINT;  // 码位暂存，出口单点写入 [码] / Code staging
END_VAR

(* 段 1｜输出预置（不触碰 _eState 状态驻留量，R19 预清零清单纪律）/ Pre-set outputs, the state stays resident *)
fQFf    := fQDesign;                // 默认输出设计风量 / Default output is the design flow
bClamp  := FALSE;
bValid  := FALSE;
bError  := FALSE;
uErrorId := 16#0000_0000;
uCode   := 16#0000_0000;
eMode   := eBypass;                 // 模式输出随内部状态在出口刷新 / Mode output refreshed at the exit

(* 段 2｜温差导出与输入有效性（NaN 自反、Inf 上限、风量域正）/ Delta-T and validity *)
fDtDesign := fRoomSetC - fTsaDesignC;   // 设计温差导出 / Design delta-T
fDtNow    := fRoomSetC - fTsaC;         // 当前温差导出 / Current delta-T
bSigOk := (fTsaC = fTsaC) AND (fQDesign = fQDesign)             // NaN 自反判据 / NaN reflexivity
          AND (ABS(fTsaC) < 1.0E308) AND (ABS(fQDesign) < 1.0E308)   // Inf 上限判据 / Inf limit
          AND (fQDesign > fEps) AND (fQMin > 0.0) AND (fQMax > fQMin);   // 风量域约束 / Flow domain

(* 段 3｜状态机主分派（ENUM 配 CASE，ELSE 兜底）/ State dispatch with ELSE interception *)
CASE _eState OF

    eStBypass:
        (* 本拍行为：旁路保持设计风量；使能且数据有效拍 N+1 进自动 / Hold design flow; arm when enabled *)
        IF bRun AND bSigOk THEN
            _eState := eStAuto;         // 拍 N 旁路相满足条件，拍 N+1 转自动 / To auto next scan
        END_IF

    eStAuto:
        (* 本拍行为：按显热守恒算前馈；撤使能回旁路，数据无效冻结输出 / Compute feedforward; freeze on bad data *)
        IF NOT bRun THEN
            _eState := eStBypass;       // 拍 N+1 回旁路 / Back to bypass next scan
            fQFf := fQDesign;           // 旁路输出设计风量 / Bypass outputs design flow
        ELSIF NOT bSigOk THEN
            fQFf := fQDesign;           // 冻结：保持设计风量，不发异常值 / Freeze at design flow
            bValid := FALSE;            // 有效标志撤 / Withdraw validity
            uCode := 16#0006_300B;      // 故障级：输入非有限 / Fault: non-finite input
        ELSIF fDtNow < -fDtEps THEN
            fQFf := fQMin;              // 送风过热：保守最小风量 / Overheated supply: conservative minimum
            bValid := TRUE;
            uCode := 16#0006_300C;      // 故障级：温差反号 / Fault: reversed delta-T
        ELSE
            IF ABS(fDtNow) < fDtEps THEN
                fQFf := fQDesign;       // 近设计工况：恒等输出 / Near design: identity output
                bValid := TRUE;
                uCode := 16#0006_300A;  // 信息级：近设计恒等 / Info: near-design identity
            ELSE
                (* 除零前置闸：温差已过容差闸，此处防御复检再除 / Defensive recheck before the division *)
                IF ABS(fDtNow) > fEps THEN
                    fRatio := fDtDesign / fDtNow;   // 温差比 / Delta-T ratio
                    fQCalc := fQDesign * fRatio;    // 前馈风量 / Feedforward flow
                    IF fQCalc < fQMin THEN
                        fQCalc := fQMin;            // 钳下限 / Clamp to minimum
                        bClamp := TRUE;
                    ELSIF fQCalc > fQMax THEN
                        fQCalc := fQMax;            // 钳上限 / Clamp to maximum
                        bClamp := TRUE;
                    END_IF
                    fQFf := fQCalc;     // 前馈输出 / Feedforward output
                    bValid := TRUE;
                    IF bClamp THEN
                        uCode := 16#0006_300D;      // 故障级：结果已钳位 / Fault: clamped
                    END_IF
                ELSE
                    fQFf := fQMax;      // 防御路：温差趋零按最大风量 / Defensive: max flow as delta-T vanishes
                    bValid := TRUE;
                    uCode := 16#0006_300D;
                END_IF
            END_IF
        END_IF

ELSE
    _eState := eStBypass;               // 非法状态拦截回旁路 / Illegal state to bypass
    fQFf := fQDesign;                   // 保守输出设计风量 / Conservative design flow
    uCode := 16#0006_300B;              // 故障级：状态越界 / Fault: state out of range
END_CASE

(* 段 4｜出口装配 / Exit assembly *)
eMode := eBypass;                       // 出口刷新模式输出 / Refresh the mode output at the exit
IF _eState = eStAuto THEN
    eMode := eAuto;                     // 自动相映射 / Auto mapping
END_IF
bError := (uCode >= 16#0006_300B) AND (uCode <= 16#0006_300D);  // 故障级码段判定 / Fault band check
uErrorId := uCode;                      // 码位单点写入 / Single write point
END_FUNCTION_BLOCK
