//==============================================================================
// 功能块：FB_DL_FanSurgeMarginCalc ｜ 中文名称：风机喘振裕度在线计算与分级预警
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3 第 3 版，零方言）
// 功能描述：以线性化喘振线 p_surge(Q) = P0 − K·Q（零流量喘振压力 P0、斜率 K
//           引脚注入）在线计算风机工况点裕度：
//           fMarginPct = (p_surge − p_act)/p_surge × 100 [%]，
//           并按两级阈值分级：裕度 ≤ 预警阈 → eWarn（延时确认）；裕度 ≤ 跳机
//           阈或裕度 < 0（工况点越线）→ eTrip（跳机保护，锁存需复位沿解除）。
//           预警/跳机均经 TON 去抖确认，防喘振开环余量监视用途；闭环防喘振
//           放空阀调节不属本件职责。
// 开源溯源 (Origin)：原创实现（风机性能曲线公开口径，自研线，零外部源码行，
//           clean-room 独立编写）
// 公开接口清单：输入 bEn / bReset / fFlowAct / fPressAct / fSurgeP0 / fSurgeK /
//               fWarnMargin / fTripMargin / tWarnDelay / tTripDelay；
//               输出 fMarginPct / eLevel / bWarn / bTrip / uErrCode / bError / bValid
// 错误码表：16#0002_3920 信息级（裕度进入预警带，不置 bError）/
//           16#0002_3921 故障级（喘振线参数非法：P0 <= 0、K < 0 或非有限，
//           置 bError）/
//           16#0002_3922 信息级（工况点输入非有限，保持现状不置 bError）/
//           16#0002_3923 预留禁用（不得挪用）
// 状态机：E_DL_SurgeLevel（本文件唯一定义，全库唯一属主）：
//           eNormal = 0 / eWarn = 1 / eTrip = 2；非法分级兜底归 eTrip（安全侧）
// 边界行为：① P0 <= 0 或 K < 0 → 故障 3921 + bError，裕度输出 0；
//           ② 工况点非有限 → 信息 3922，bValid := FALSE，分级冻结；
//           ③ p_surge(Q) <= 容差（深越线）→ 分母闸钳容差，裕度深度负值照算；
//           ④ bTrip 锁存至 bReset 上升沿或撤使能（R189：锁存码有可达清除沿）；
//           ⑤ TON ×2 / R_TRIG ×1 每拍无条件刷新（不入分支，红线 R7）；
//           ⑥ CASE 带 ELSE，非法值兜底归 eTrip（安全侧）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 1 · 序 3）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_SurgeLevel（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 喘振裕度分级，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SurgeLevel :
(
    eNormal := 0,    // 正常：裕度高于预警阈 / Normal, margin above the warning threshold
    eWarn   := 1,    // 预警：裕度进入预警带（延时确认）/ Warning band, delay confirmed
    eTrip   := 2     // 跳机：裕度越过跳机阈或越线（锁存）/ Trip band or beyond the line, latched
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FanSurgeMarginCalc
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 * 调用示例: surgeWatch(fFlowAct := fFTx, fPressAct := fPTx,
 *                      fSurgeP0 := 12000.0, fSurgeK := 8.0,
 *                      fWarnMargin := 10.0, fTripMargin := 5.0);
 *          bWarn 接声光预警，bTrip 接防喘振放空联锁（开环余量监视）。
 * 组装说明: ① 喘振线参数须由工艺专业给值后引脚注入，禁在调用侧写
 *             魔法数（本件常量区只存防御参数）；
 *           ② bTrip 为锁存量，复位须经操作员确认沿 bReset 或撤使能；
 *           ③ 工况点测量引脚经 PRG_IoMapping 读入注入，本件零物理地址。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_FanSurgeMarginCalc
VAR_INPUT
    bEn         : BOOL := FALSE;      // 使能（FALSE 解除锁存回正常）/ Enable, FALSE releases the latch
    bReset      : BOOL := FALSE;      // 跳机锁存复位输入（上升沿有效）/ Trip latch reset, rising edge active
    fFlowAct    : LREAL := 0.0;       // 实测流量 [m3/h]，工况点横轴 / Measured flow [m3/h], operating point abscissa
    fPressAct   : LREAL := 0.0;       // 实测出口压 [Pa]，工况点纵轴 / Measured outlet pressure [Pa], operating point ordinate
    fSurgeP0    : LREAL := 12000.0;   // 零流量喘振压力 [Pa]，喘振线截距 / Surge line intercept at zero flow [Pa]
    fSurgeK     : LREAL := 8.0;       // 喘振线斜率 [Pa/(m3/h)]，右降为正 / Surge line slope [Pa per m3/h], positive falling
    fWarnMargin : LREAL := 10.0;      // 预警阈值 [百分数] / Warning margin threshold [percent]
    fTripMargin : LREAL := 5.0;       // 跳机阈值 [百分数] / Trip margin threshold [percent]
    tWarnDelay  : TIME := T#500MS;    // 预警去抖确认延时 [ms] / Warning debounce delay [ms]
    tTripDelay  : TIME := T#200MS;    // 跳机去抖确认延时 [ms] / Trip debounce delay [ms]
END_VAR
VAR_OUTPUT
    fMarginPct  : LREAL;              // 喘振裕度 [百分数]，正值安全 / Surge margin [percent], positive is safe
    eLevel      : E_DL_SurgeLevel;    // 分级结论 / Level conclusion
    bWarn       : BOOL;               // 预警声明（延时确认后）/ Warning declared after debounce
    bTrip       : BOOL;               // 跳机声明（锁存至复位沿）/ Trip declared, latched until reset edge
    uErrCode    : UDINT;              // 错误码，0 = 无错 / Error code, 0 = no error
    bError      : BOOL;               // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid      : BOOL;               // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    tonWarn     : TON;                // 预警去抖定时器，每拍无条件刷新 / Warning debounce timer, refreshed every scan
    tonTrip     : TON;                // 跳机去抖定时器，每拍无条件刷新 / Trip debounce timer, refreshed every scan
    trigReset   : R_TRIG;             // 复位沿检测，每拍无条件刷新 / Reset edge detector, refreshed every scan
    fPSurge     : LREAL;              // 当前流量下喘振线压力 [Pa] / Surge line pressure at current flow [Pa]
    bInWarnBand : BOOL;               // 本拍裕度处于预警带（未确认）/ Margin in the warning band this scan, unconfirmed
    bInTripBand : BOOL;               // 本拍裕度处于跳机带或越线（未确认）/ Margin in the trip band or beyond, unconfirmed
END_VAR
VAR CONSTANT
    DL_SG_EPS   : LREAL := 1.0E-9;    // 浮点容差与分母闸 [Pa] / Float tolerance and denominator gate [Pa]
    DL_SG_INF   : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_SG_PCT100: LREAL := 100.0;     // 裕度百分比放大系数 [1] / Margin percentage scale [1]
END_VAR

// ---- 段 1｜定时/沿实例无条件刷新（红线 R7：禁入条件分支）----
tonWarn(IN := bInWarnBand AND NOT bTrip, PT := tWarnDelay);   // 预警去抖按未确认态断输入 / Warning timer input per unconfirmed band
tonTrip(IN := bInTripBand AND NOT bTrip, PT := tTripDelay);   // 跳机去抖按未确认态断输入 / Trip timer input per unconfirmed band
trigReset(CLK := bReset);             // 复位沿每拍刷新 / Reset edge refreshed every scan

// ---- 段 2｜出口默认值：入口即赋确定值 ----
fMarginPct := 0.0;                    // 裕度默认零 / Margin preset zero
bWarn      := FALSE;                  // 预警默认 FALSE / Warning preset FALSE
uErrCode   := 16#0000_0000;           // 错误码先清零（信息级每拍重算）/ Error code cleared, info level recomputed
bError     := FALSE;                  // 故障标志先清零（R45 配对）/ Fault flag cleared first, R45 pairing
bValid     := FALSE;                  // 可用标志先清零 / Usable flag cleared first
bInWarnBand := FALSE;                 // 预警带声明先清零 / Warning band flag cleared first
bInTripBand := FALSE;                 // 跳机带声明先清零 / Trip band flag cleared first

// ---- 段 3｜喘振线参数闸：非法 → 故障 3921（R45 配对置 bError）----
IF (fSurgeP0 <> fSurgeP0) OR (ABS(fSurgeP0) > DL_SG_INF)
   OR (fSurgeK <> fSurgeK) OR (ABS(fSurgeK) > DL_SG_INF)
   OR (fSurgeP0 <= DL_SG_EPS) OR (fSurgeK < 0.0) THEN
    fMarginPct := 0.0;                // 裕度确定值零出口 / Deterministic zero margin
    eLevel     := E_DL_SurgeLevel.eNormal; // 参数不可信分级回正常（联锁侧另判）/ Level back to normal, interlock judged elsewhere
    uErrCode   := 16#0002_3921;       // 故障级：喘振线参数非法 / Fault: illegal surge line parameters
    bError     := TRUE;               // 置故障标志（R45 配对）/ Raise the fault flag, R45 pairing
    bValid     := FALSE;              // 输出不可用 / Outputs unusable
    RETURN;                           // 结构早退 / early exit
END_IF

// ---- 段 4｜工况点输入防御：非有限 → 信息级保持现状（分级冻结）----
IF (fFlowAct <> fFlowAct) OR (ABS(fFlowAct) > DL_SG_INF)
   OR (fPressAct <> fPressAct) OR (ABS(fPressAct) > DL_SG_INF) THEN
    uErrCode := 16#0002_3922;         // 信息级：工况点非有限 / Info: non-finite operating point
    bValid   := FALSE;                // 输出不可用（bTrip 锁存语义不变）/ Outputs unusable, trip latch semantics unchanged
    RETURN;                           // 结构早退（分级冻结不重算）/ early exit, level frozen
END_IF

// ---- 段 5｜裕度主体：线性喘振线取值 → 差值比；分母先过正域闸 ----
fPSurge := fSurgeP0 - fSurgeK * fFlowAct; // 喘振线压力 [Pa] / Surge line pressure [Pa]
IF fPSurge <= DL_SG_EPS THEN
    fPSurge := DL_SG_EPS;             // 深越线分母钳容差（防负/零除）/ Deep-beyond-line denominator clamped
END_IF
fMarginPct := (fPSurge - fPressAct) / fPSurge * DL_SG_PCT100; // 裕度 [百分数] / Margin [percent]

// ---- 段 6｜分级装配：裕度先判跳机带再判预警带（两级次序不可反）----
IF (fMarginPct <= fTripMargin) OR (fMarginPct < 0.0) THEN
    bInTripBand := TRUE;              // 跳机带或越线声明 / Trip band or beyond the line
ELSIF fMarginPct <= fWarnMargin THEN
    bInWarnBand := TRUE;              // 预警带声明 / Warning band
END_IF

// ---- 段 7｜锁存与确认：bTrip 锁存至复位沿/撤使能；去抖确认后才置声明 ----
IF trigReset.Q OR (NOT bEn) THEN
    bTrip := FALSE;                   // 锁存解除（复位沿或撤使能，头注释声明的清除沿）/ Latch released on reset edge or disable
END_IF
IF tonTrip.Q THEN
    bTrip := TRUE;                    // 跳机去抖确认置位 / Trip confirmed by debounce
END_IF
bWarn := tonWarn.Q AND NOT bTrip;     // 预警确认（跳机优先压制预警）/ Warning confirmed, suppressed by trip

// ---- 段 8｜分级状态机（CASE 带 ELSE；非法值兜底归 eTrip 安全侧）----
CASE eLevel OF
    E_DL_SurgeLevel.eNormal:          // 正常相：可升预警或跳机
        IF bTrip THEN
            eLevel := E_DL_SurgeLevel.eTrip;  // 升跳机 / Rise to trip
        ELSIF bWarn THEN
            eLevel := E_DL_SurgeLevel.eWarn;  // 升预警 / Rise to warning
            uErrCode := 16#0002_3920;         // 信息级：裕度进入预警带 / Info: margin in the warning band
        END_IF

    E_DL_SurgeLevel.eWarn:            // 预警相：可升跳机或降正常
        IF bTrip THEN
            eLevel := E_DL_SurgeLevel.eTrip;  // 升跳机 / Rise to trip
        ELSIF NOT bWarn THEN
            eLevel := E_DL_SurgeLevel.eNormal; // 降正常 / Fall back to normal
        ELSE
            uErrCode := 16#0002_3920;         // 预警保持期内信息级重算 / Info code recomputed while warning holds
        END_IF

    E_DL_SurgeLevel.eTrip:            // 跳机相：锁存，仅锁存解除后可降级
        IF NOT bTrip THEN             // 锁存已解除（复位沿/撤使能）
            IF bWarn THEN
                eLevel := E_DL_SurgeLevel.eWarn;  // 降预警 / Fall to warning
            ELSE
                eLevel := E_DL_SurgeLevel.eNormal; // 降正常 / Fall to normal
            END_IF
        END_IF

    ELSE                              // 非法分级兜底（R21：CASE 必带 ELSE）
        eLevel := E_DL_SurgeLevel.eTrip; // 拦截非法值归跳机（安全侧）/ Catch illegal value to trip, safe side
END_CASE

bValid := TRUE;                       // 全部防御通过：输出可用 / Outputs usable
END_FUNCTION_BLOCK