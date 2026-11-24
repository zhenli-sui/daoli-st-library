(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MinPulseWidthFilter
 * 溯源说明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现（零检索变体线）
 * 所属子库 (Sublibrary) : DL_Base / SignalShape
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON
 * 组件分类 (Category)   : 功能块（TYPE E_DL_MinPulseState :
(
    ePassThrough := 0, // 直通模式：双零参数 / Pass-through: both widths zero
    eStableLow   := 1, // 稳态低：等待有效接通 / Stable low: waiting qualified on
    eStableHigh  := 2  // 稳态高：等待有效断开 / Stable high: waiting qualified off
);
END_TYPE

FUNCTION_BLOCK）· 最小脉宽滤波
 * 功能一句话 (Summary)  : 抑制窄于 tMinOn / tMinOff 的毛刺，达标脉冲 1:1 透传。
 * 边界与安全 (Boundary) : ①两相超时参数为负 → 钳 0 并置故障码 0001_03BF；
 *                         ②两参数同为 0 → 直通模式（边沿即透传）；
 *                         ③上电输出初始化 FALSE，首扫无假触发；
 *                         ④两相定时器无条件周期刷新，不包 IF 跳调。
 * 错误码    : 16#0001_03BF 两相超时参数非法（负值已钳 0）——故障级
 *             16#0001_03C0 保留禁用（不得挪用，本件零赋值）
 * 码位总账  : 16#0001_03BF 用 ｜ 16#0001_03C0 预留
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_MinPulseWidthFilter
VAR_INPUT
    bIn      : BOOL; // 待滤波信号输入 / Signal to be filtered
    tMinOn   : TIME; // 最小接通脉宽 [ms] / Minimum on-pulse width [ms]
    tMinOff  : TIME; // 最小断开脉宽 [ms] / Minimum off-pulse width [ms]
END_VAR
VAR_OUTPUT
    bOut        : BOOL; // 滤波后输出，达标脉冲 1:1 透传 / Filtered output, qualified pulses pass 1:1
    bSuppressed : BOOL; // 本周期有脉冲被抑制标志 / A glitch is being suppressed this cycle
    eErr        : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    eState  : E_DL_MinPulseState; // 两相滤波状态机当前态 / Two-phase filter state machine state
    bOutIni : BOOL; // 输出初始化哨兵，恒 FALSE 保证上电安全侧 / Output init sentinel, stays FALSE for safe power-up
    tonOn   : TON; // 接通保持计时，验证接通脉宽达标 / On-hold timer, validates on-pulse width
    tonOff  : TON; // 断开保持计时，验证断开脉宽达标 / Off-hold timer, validates off-pulse width
    tOnEff  : TIME; // 接通脉宽有效值（钳位后）/ Effective on-width after clamping
    tOffEff : TIME; // 断开脉宽有效值（钳位后）/ Effective off-width after clamping
END_VAR
VAR CONSTANT
    cTZero : TIME := T#0MS; // 零时长基准 / Zero-duration baseline
END_VAR

// ---------- 两相定时器无条件周期刷新（不包 IF，防漏调） ----------
tonOn (IN := (bIn) AND (eState = E_DL_MinPulseState.eStableLow),  PT := tOnEff);
tonOff(IN := (NOT bIn) AND (eState = E_DL_MinPulseState.eStableHigh), PT := tOffEff);

// ---------- 参数防御：负值钳 0 并置码；双零转直通 ----------
eErr := 0;
IF (TIME_TO_DINT(tMinOn) < 0) OR (TIME_TO_DINT(tMinOff) < 0) THEN
    tOnEff  := cTZero;                       // 负值钳 0 / Clamp negative to zero
    tOffEff := cTZero;
    eErr    := 16#0001_03BF;                 // 故障级：参数非法已钳 / fault: illegal params clamped
ELSIF (tMinOn = cTZero) AND (tMinOff = cTZero) THEN
    tOnEff  := cTZero;                       // 直通模式配置 / Pass-through configuration
    tOffEff := cTZero;
ELSE
    tOnEff  := tMinOn;                       // 参数合法原样采用 / Legal params used as-is
    tOffEff := tMinOff;
END_IF

// ---------- 两相状态机：稳态低等待有效接通，稳态高等待有效断开 ----------
CASE eState OF
    E_DL_MinPulseState.ePassThrough:
        bOut := bIn;                          // 双零直通，边沿即透传 / Pass-through, edges pass at once

    E_DL_MinPulseState.eStableLow:            // 拍 N 进入：输出保持低 / Entered: output held low
        bOut := FALSE;                        // 本拍行为：未达标脉冲被吸收 / This cycle: short pulses absorbed
        IF tonOn.Q THEN                       // 接通保持达标（定时器含 bIn 条件，Q 为真即 bIn 持续达标）
            bOut    := TRUE;                  // 转出：输出抬升 / Leaving: output rises
            eState  := E_DL_MinPulseState.eStableHigh;
        END_IF

    E_DL_MinPulseState.eStableHigh:           // 拍 N 进入：输出保持高 / Entered: output held high
        bOut := TRUE;                         // 本拍行为：达标脉冲透传 / This cycle: qualified pulse passes
        IF tonOff.Q THEN                      // 断开保持达标 / Off-hold qualified
            bOut    := FALSE;                 // 转出：输出回落 / Leaving: output falls
            eState  := E_DL_MinPulseState.eStableLow;
        END_IF

    ELSE                                      // 非法状态兜底，归安全态低电平 / Illegal state fallback to safe low
        eState := E_DL_MinPulseState.eStableLow;
        bOut   := FALSE;
END_CASE

// ---------- 抑制标志：输入与输出不一致即处于毛刺吸收期 ----------
IF bIn <> bOut THEN
    bSuppressed := TRUE;                      // 毛刺吸收中 / Glitch being absorbed
ELSE
    bSuppressed := FALSE;                     // 同拍清除，无生命周期残留 / Same-cycle clear, no latch residue
END_IF

END_FUNCTION_BLOCK
