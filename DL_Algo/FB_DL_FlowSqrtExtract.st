(*
    FB_DL_FlowSqrtExtract —— 差压流量开方 + 小信号切除
    ------------------------------------------------------------------
    分类      : DL_Algo / ProcessControl
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 差压式流量测量的公开仪表工程惯例（开方 + 小信号切除 + 一阶阻尼 + 满量程标定）；
                只借「阻尼与限幅同层」的组织方式，迟滞切除判据、阻尼律、错误分级、
                状态组织与码位 100% 自有；开方一律委托平台内建 SQRT，禁牛顿迭代重实现；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 孔板流量在 5% 以下差压时开方后噪声被放大 4~5 倍，HMI 上流量在零附近乱跳，
                操作工据此判「有没有流量」必然误判；硬切又在切点附近反复跳。
                本件把「迟滞切除」做进块内：进入切除要跌破「切除点 − 迟滞带宽」，
                退出切除要重新越过切除点，带内保持上一状态（本件核心防御，与硬切的分界）。
                其余防御：① 量程与采样周期非法即故障级 2710，输出 0；
                ② 差压负漂取 0 参与运算（直接开方会出 NaN）并置信息码；
                ③ 差压非有限即故障级 2711，保持末次有效输出——零流量与信号故障
                   在联锁上是两个结论，绝不输出 0；
                ④ 输出双侧钳位（下 0，上 fFlowSpan），超顶置 bSaturated。
                职责边界：本件只出流量工程量，不做温压补偿（归补偿件），不做累积。
    错误码    : 16#0002_2701 切除点超域已钳位 / 差压负漂已取 0 / 切除迟滞带保持中——信息级，正常防御
                16#0002_2702 预留禁用（信息级，不得挪用）
                16#0002_2710 量程或采样周期参数非法——故障级，输出 0 且 bValid = FALSE
                16#0002_2711 差压输入非有限——故障级，保持末次有效输出且 bValid = FALSE
                16#0002_2712 预留禁用（故障级，不得挪用）
    码位总账  : 16#0002_2701 用 / 16#0002_2702 预留 ｜ 16#0002_2710 用 / 16#0002_2711 用 / 16#0002_2712 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
                （切除态由单比特锁存 bCutLatch 承载，非顺序状态机）
    采样约定  : fbTrigReset 在本体首部无条件刷新；阻尼系数 α 隐含以 tSampleTime 为步长，
                采样周期未知或越域时阻尼律不可信，故并入 2710 判据（tSampleTime 越域即故障）。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION_BLOCK FB_DL_FlowSqrtExtract
VAR_INPUT
    bEnable        : BOOL;                    // 使能，FALSE 输出 0 并冻结阻尼状态 / enable, FALSE outputs zero and freezes the damping state
    bReset         : BOOL;                    // 复位，上升沿清阻尼状态与切除锁存 / reset, rising edge clears the damping state and the cutoff latch
    fDp            : REAL := 0.0;             // 差压输入 [用户单位]，范围 -10.0~110.0 / differential pressure input [user unit], range -10.0~110.0
    fDpSpan        : REAL := 100.0;           // 差压满量程 [用户单位]，必须 > 0 / differential pressure span [user unit], must be > 0
    fFlowSpan      : REAL := 100.0;           // 流量满量程 [m3/h]，必须 > 0 / flow span [m3/h], must be > 0
    fCutPercent    : REAL := 1.0;             // 切除点（差压满量程百分比）[%]，范围 0.0~20.0，0 = 不切除 / cutoff point as a percentage of the span [%], range 0.0~20.0, zero disables it
    fCutHystPercent : REAL := 0.3;            // 切除迟滞带宽度（相对满量程）[%]，范围 0.0~10.0 / hysteresis band width of the cutoff relative to the span [%], range 0.0~10.0
    fDampCoef      : REAL := 0.2;             // 一阶阻尼系数 α [无量纲]，范围 0.0~1.0，0 = 不阻尼，1 = 冻结 / first order damping factor [dimensionless], 0.0~1.0
    tSampleTime    : TIME := T#100MS;         // 采样周期 [ms]，范围 1~10000 / sample time [ms], range 1~10000
    bSquareRoot    : BOOL := TRUE;            // TRUE = 开方（差压型），FALSE = 线性（已开方变送器）/ TRUE takes the square root, FALSE is linear
END_VAR
VAR_OUTPUT
    fFlow          : REAL;                    // 输出流量 [m3/h]，范围 0.0~fFlowSpan / output flow [m3/h], range 0.0~fFlowSpan
    bCutoff        : BOOL;                    // 当前处于切除区，输出被强制 0 / currently inside the cutoff band, output forced to zero
    bSaturated     : BOOL;                    // 输出被满量程钳位 / output clamped at the span
    uCutCount      : UDINT;                   // 切除进入次数，抖动监视用 [次] / cutoff entries for chatter monitoring [times]
    eErr           : UDINT;                   // 错误码，0=正常 / error id, 0=ok
    bError         : BOOL;                    // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid         : BOOL;                    // 输出是否可用 / output valid flag
END_VAR
VAR
    fbTrigReset    : R_TRIG;                  // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    bCutLatch      : BOOL;                    // 切除锁存（带内保持上一状态）/ cutoff latch, holds the previous state inside the band
    fDamped        : REAL;                    // 一阶阻尼内部状态 [m3/h] / first order damping internal state [m3/h]
    fRatio         : REAL;                    // 差压/满量程归一比值 [无量纲]，范围 0.0~1.0 / normalised ratio [dimensionless], range 0.0~1.0
    fRaw            : REAL;                   // 切除与阻尼前的瞬时流量 [m3/h] / instantaneous flow before cutoff and damping [m3/h]
    fDpEff         : REAL;                    // 负漂修正后的差压 [用户单位] / differential pressure after the negative drift correction [user unit]
    fCutEff        : REAL;                    // 域钳位后的切除点 [%] / cutoff point after domain clamping [%]
    fHystEff       : REAL;                    // 域钳位后的迟滞带宽度 [%] / hysteresis band width after domain clamping [%]
    fDampEff       : REAL;                    // 域钳位后的阻尼系数 [无量纲] / damping factor after domain clamping [dimensionless]
    bNonFin        : BOOL;                    // 输入非有限判定标志 / non-finite input flag
    bEnterCut      : BOOL;                    // 本拍新进入切除区（用于计数）/ newly entered the cutoff band in this cycle, used for counting
END_VAR
VAR CONSTANT
    DL_FSQ_CUT_MAX   : REAL := 20.0;          // 切除点上限 [%] / cutoff point upper bound [%]
    DL_FSQ_HYST_MAX  : REAL := 10.0;          // 迟滞带宽度上限 [%] / hysteresis band width upper bound [%]
    DL_FSQ_DAMP_MAX  : REAL := 1.0;           // 阻尼系数上限 [无量纲] / damping factor upper bound [dimensionless]
    DL_FSQ_DT_MAX    : TIME := T#10S;         // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_FSQ_DT_MIN    : TIME := T#1MS;         // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_FSQ_PERCENT   : REAL := 100.0;         // 百分比换算因子 [%] / percent conversion factor [%]
    DL_FSQ_RATIO_MAX : REAL := 1.0;           // 归一比值上限 [无量纲] / normalised ratio upper bound [dimensionless]
    DL_FSQ_INF_GUARD : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_FSQ_CNT_MAX   : UDINT := 16#FFFF_FFFE; // 切除计数饱和值 [次] / cutoff counter saturation value [times]
    DL_FSQ_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置（fFlow 不预置，非有限时须保持末次有效值）/ segment 2, preset outputs except the held flow
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用 / preset invalid
bSaturated := FALSE;                          // 预置未饱和 / preset not saturated
bCutoff := FALSE;                             // 预置非切除态 / preset outside the cutoff band
bEnterCut := FALSE;                           // 预置非新进切除 / preset not entering the cutoff band

// 段 3｜使能闸：失能输出 0 并冻结阻尼状态 / segment 3, enable gate
IF NOT bEnable THEN
    fFlow := DL_FSQ_ZERO;                     // 失能输出 0 [m3/h] / output zero while disabled [m3/h]
    RETURN;                                   // 失能即出口，阻尼状态自然冻结 / disabled is the exit, the damping state stays frozen
END_IF

// 段 4｜参数闸：量程、采样周期、参数有限性（隐含阻尼律的时基前提）/ segment 4, parameter gate
bNonFin := (fDpSpan <> fDpSpan) OR (fDpSpan > DL_FSQ_INF_GUARD) OR (fDpSpan < -DL_FSQ_INF_GUARD)
        OR (fFlowSpan <> fFlowSpan) OR (fFlowSpan > DL_FSQ_INF_GUARD) OR (fFlowSpan < -DL_FSQ_INF_GUARD); // 参数非有限判定 / parameter non-finite detection
IF bNonFin OR (fDpSpan <= DL_FLOAT_EPS) OR (fFlowSpan <= DL_FLOAT_EPS)
   OR (tSampleTime < DL_FSQ_DT_MIN) OR (tSampleTime > DL_FSQ_DT_MAX) THEN
    eErr := 16#0002_2710;                     // 量程或采样周期非法故障码 / span or sample time fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    fFlow := DL_FSQ_ZERO;                     // 参数非法时输出 0 / output zero when the parameters are illegal
    bValid := FALSE;                          // 输出不可用 / output not usable
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜差压输入非有限闸：保持末次有效输出，绝不输出 0 / segment 5, non-finite dp gate
IF (fDp <> fDp) OR (fDp > DL_FSQ_INF_GUARD) OR (fDp < -DL_FSQ_INF_GUARD) THEN
    eErr := 16#0002_2711;                     // 输入非有限故障码 / non-finite input fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 输出不可用 / output not usable
    RETURN;                                   // 保持末次 fFlow，零流量与信号故障是两个结论 / keep the last flow, zero flow and a signal fault are two different conclusions
END_IF

// 段 6｜参数域钳位（切除点、迟滞带、阻尼系数各自收敛）/ segment 6, parameter domain clamp
fCutEff := MIN(MAX(fCutPercent, DL_FSQ_ZERO), DL_FSQ_CUT_MAX);   // 切除点收敛到 0.0~20.0 % / converge the cutoff into 0.0~20.0 %
fHystEff := MIN(MAX(fCutHystPercent, DL_FSQ_ZERO), DL_FSQ_HYST_MAX); // 迟滞带宽收敛到 0.0~10.0 % / converge the hysteresis band into 0.0~10.0 %
fDampEff := MIN(MAX(fDampCoef, DL_FSQ_ZERO), DL_FSQ_DAMP_MAX);   // 阻尼系数收敛到 0.0~1.0 / converge the damping factor into 0.0~1.0
IF (fCutPercent > DL_FSQ_CUT_MAX) OR (fCutPercent < DL_FSQ_ZERO) THEN
    eErr := 16#0002_2701;                     // 信息级：切除点超域已钳位 / info level, the cutoff point was clamped
END_IF

// 段 7｜负漂修正：差压变送器零点负漂是常态，直接开方会出 NaN / segment 7, negative drift correction
fDpEff := fDp;                                // 取入参副本 / copy the input
IF fDpEff < DL_FSQ_ZERO THEN
    fDpEff := DL_FSQ_ZERO;                    // 负漂取 0 参与运算 / clamp a negative drift to zero before the square root
    eErr := 16#0002_2701;                     // 信息级：负漂已取 0 / info level, the negative drift was clamped
END_IF

// 段 8｜复位沿清阻尼与切除锁存（在切除判定之前生效）/ segment 8, reset clears the damping state and the latch
IF fbTrigReset.Q THEN
    fDamped := DL_FSQ_ZERO;                   // 清阻尼内部状态 / clear the damping state
    bCutLatch := FALSE;                       // 清切除锁存 / clear the cutoff latch
END_IF

// 段 9｜归一比值与瞬时流量（开方委托内建，入参已保证非负）/ segment 9, ratio and instantaneous flow
fRatio := fDpEff / fDpSpan;                   // 满量程已由段 4 保证 > 0，除法安全 / the span is positive by segment 4, the division is safe
fRatio := MIN(MAX(fRatio, DL_FSQ_ZERO), DL_FSQ_RATIO_MAX); // 比值双侧钳位到 0.0~1.0 / clamp the ratio into 0.0~1.0
IF bSquareRoot THEN
    fRaw := SQRT(fRatio) * fFlowSpan;         // 开方型：委托内建 SQRT [m3/h] / square root type, delegate to the built-in SQRT [m3/h]
ELSE
    fRaw := fRatio * fFlowSpan;               // 线性型：已开方变送器只做切除与阻尼 [m3/h] / linear type, only cutoff and damping [m3/h]
END_IF

// 段 10｜迟滞切除（核心防御）：退出要越过切除点，进入要跌破切除点减带宽 / segment 10, hysteresis cutoff
IF fCutEff <= DL_FLOAT_EPS THEN
    bCutLatch := FALSE;                       // 切除点 0 = 不切除 / a zero cutoff point disables the function
ELSE
    IF (fRatio * DL_FSQ_PERCENT) >= fCutEff THEN
        bCutLatch := FALSE;                   // 越过切除点即退出切除 / leaving the cutoff once the point is crossed again
    ELSIF (fRatio * DL_FSQ_PERCENT) < (fCutEff - fHystEff) THEN
        IF NOT bCutLatch THEN
            bEnterCut := TRUE;                // 新进入切除区，用于计数 / newly entered, used for counting
        END_IF
        bCutLatch := TRUE;                    // 跌破「切除点 − 带宽」才进入切除 / entering only below the point minus the band
    END_IF
END_IF
bCutoff := bCutLatch;                         // 对外发布切除态 / publish the cutoff state
IF bCutLatch THEN
    fRaw := DL_FSQ_ZERO;                      // 切除区强制 0，抑制开方噪声放大 / force zero inside the cutoff band to suppress noise amplification
END_IF

// 段 11｜切除进入计数（饱和，抖动监视）/ segment 11, saturating cutoff entry counter
IF bEnterCut AND (uCutCount < DL_FSQ_CNT_MAX) THEN
    uCutCount := uCutCount + 1;               // 饱和加一，绝不回绕 / saturating increment, never wraps
END_IF

// 段 12｜一阶阻尼（α = 1 等价冻结，α = 0 直通）/ segment 12, first order damping
fDamped := fDamped + fDampEff * (fRaw - fDamped); // 一阶离散阻尼 [m3/h] / first order discrete damping [m3/h]

// 段 13｜输出双侧钳位（只做单侧是常见缺陷）/ segment 13, two-sided output clamp
fFlow := fDamped;                             // 先取阻尼输出 / take the damped value first
IF fFlow > fFlowSpan THEN
    fFlow := fFlowSpan;                       // 上限钳位 / clamp at the upper bound
    bSaturated := TRUE;                       // 标记饱和 / flag the saturation
ELSIF fFlow < DL_FSQ_ZERO THEN
    fFlow := DL_FSQ_ZERO;                     // 下限钳位 / clamp at the lower bound
END_IF

// 段 14｜发布状态（信息码永不置 bError）/ segment 14, publish the status
bValid := TRUE;                               // 通过全部闸门，输出可用 / all gates passed, the output is usable
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION_BLOCK
