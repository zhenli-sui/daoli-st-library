// FB_DL_DitherSignalGen v1.0.0
// 开源溯源：self-cleanroom / 信号发生族补口
(*
  道莅工业代码库 | DL_MathData | FB_DL_DitherSignalGen
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 抖动信号发生（幅值/更新带宽可设）：LCG 伪随机数经更新节拍刷新，
        输出 ±幅值内均匀抖动，防 ADC 死区与摩擦滞环（dither 配套）
  邻件关系: 信号发生族 SineGenerator / PulseGenerator（确定性周期信号）——
            差异点：本件为伪随机幅值（LCG 32 位递推），非周期波形；
            更新带宽 = 更新节拍周期（1/ton 自复位周期）
  随机性声明: LCG 常数 a=1664525、c=1013904223（Numerical Recipes 公开口径），
            种子零值时自动注入非零初值防全零死锁
*)
FUNCTION_BLOCK FB_DL_DitherSignalGen
VAR_INPUT
    bEnable     : BOOL := FALSE;             // 使能（FALSE 输出回零）/ Enable, output to zero when FALSE
    fAmplitude  : REAL := 1.0;               // 抖动幅值 [工程单位]，域 > 0 / Dither amplitude, domain > 0
    tUpdate     : TIME := T#100MS;           // 更新节拍周期 [ms]，域 > 0 / Update tick period
    uSeed       : UDINT := 16#DEAD_BEEF;     // LCG 种子 [1]，0 时自动注入 / LCG seed, auto-inject when zero
END_VAR
VAR_OUTPUT
    fDitherOut  : REAL;                      // 抖动输出 ∈ [-幅值, +幅值] [工程单位] / Dither output within ±amplitude
    fNormRand   : REAL;                      // 归一随机数 ∈ [0,1] 诊断口 / Normalized random in [0,1]
    bTick       : BOOL;                      // 更新节拍脉冲（当拍到时单拍）/ Update tick pulse, one cycle
    bValid      : BOOL;                      // 组态有效回执 [-] / Config validity receipt
    bError      : BOOL;                      // 故障标志（组态非法）/ Fault flag (invalid config)
    uErrorId    : UDINT;                     // 事件码，0 = 无事件；16#0002_1F01 = 组态非法 / Event code
END_VAR
VAR
    uState      : UDINT;                     // LCG 当前状态 [1] / LCG current state
    bSeeded     : BOOL;                      // 已注入种子标志 [-] / Seeded flag
    tonTick     : TON;                       // 更新节拍定时器（自复位）/ Update tick timer, self-resetting
    fU          : REAL;                      // 归一随机中间量 [1] / Normalized random intermediate
END_VAR
VAR CONSTANT
    DL_DIT_LCG_A : UDINT := 16#0019_660D;    // LCG 乘数 a=1664525 [1] / LCG multiplier
    DL_DIT_LCG_C : UDINT := 16#3C6E_F35F;    // LCG 增量 c=1013904223 [1] / LCG increment
    DL_DIT_SCALE : REAL := 4294967295.0;     // 2^32-1 归一化分母 [1] / Normalization denominator
END_VAR

// —— 段 0：实例无条件刷新（R7：TON 每周期调用，IN := NOT Q 自复位） —— //
tonTick(IN := NOT tonTick.Q, PT := tUpdate);     // 节拍自复位（到时翻转一拍）/ Self-resetting tick timer
bTick := tonTick.Q;                              // 节拍脉冲单拍暴露 / Tick pulse exposed one cycle

// —— 段 1：组态闸 —— //
bValid := (fAmplitude > 0.0) AND (tUpdate > T#0MS) AND (fAmplitude = fAmplitude);   // 幅值正数 + 周期非零 + NaN 闸 / Gate
IF NOT bValid THEN
    bError   := TRUE;                            // 故障级：组态非法 / Fault level: invalid config
    uErrorId := 16#0002_1F01;                    // 故障码（1Fxx 步进）/ Fault code
    fDitherOut := 0.0;                           // 故障侧输出回零（安全位）/ Safe zero output
    fNormRand := 0.0;                            // 诊断口回零 / Diagnostic zero
    RETURN;
END_IF
bError   := FALSE;                               // 组态恢复：故障清零（解除路径）/ Fault cleared on valid config
uErrorId := 16#0000;                             // 事件码清零 / Event code cleared

// —— 段 2：种子注入（首拍或种子零值防死锁） —— //
IF (NOT bSeeded) OR (uState = 16#0000_0000) THEN
    IF uSeed = 16#0000_0000 THEN
        uState := 16#DEAD_BEEF;                  // 种子零值注入非零初值 / Inject nonzero on zero seed
    ELSE
        uState := uSeed;                         // 用户种子 / User seed
    END_IF
    bSeeded := TRUE;                             // 已注入标志 / Seeded flag
END_IF

// —— 段 3：使能与节拍驱动（节拍到时才刷新随机数，带宽即 1/tUpdate） —— //
IF NOT bEnable THEN
    fDitherOut := 0.0;                           // 失能输出回零（安全位）/ Disabled safe zero
    fNormRand := 0.0;                            // 诊断口回零 / Diagnostic zero
    RETURN;
END_IF
IF tonTick.Q THEN                                // 仅节拍拍刷新（拍间保持）/ Refresh only on tick, hold between
    uState := (uState * DL_DIT_LCG_A) + DL_DIT_LCG_C;    // LCG 递推（32 位自然回绕）/ LCG step, natural wrap
    fU := DWORD_TO_REAL(uState) / DL_DIT_SCALE;  // 归一化 ∈ [0,1] / Normalize to [0,1]
    IF fU > 1.0 THEN
        fU := 1.0;                               // 上钳（舍入防御）/ Clamp high
    END_IF
    fNormRand := fU;                             // 归一随机诊断口 / Diagnostic normalized random
    fDitherOut := (2.0 * fU - 1.0) * fAmplitude; // 映射 ±幅值（均匀分布）/ Map to ±amplitude uniform
END_IF
END_FUNCTION_BLOCK
