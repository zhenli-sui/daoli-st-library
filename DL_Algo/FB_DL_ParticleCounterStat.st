//==============================================================================
// 功能块：FB_DL_ParticleCounterStat ｜ 中文名称：尘埃粒子计数器统计与等级判定
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：6 路粒径计数（0.1/0.2/0.3/0.5/1.0/5.0 微米）→ 浓度（颗每
//           立方米）→ ISO 14644-1:2015 Table 1 等级判定（生成式 Cn =
//           10^N 乘 (0.1/D)^2.08，N 允许 0.5 步进）→ 连续 N 个采样超限
//           才报警 → 失采检测。等级判定采用 Table 1 常量表锚定 + 档内
//           LOG 对数插值：** 幂运算符跨平台不可用，改用「整数档查表
//           + LOG 对数插值」，由生成式恒等式 conc/L_N = 10^(level-N)
//           保证档内插值与公式严格一致，不引入近似误差。表内「—」
//           （无限制）格跳过不参与判定。只统计与判定，不控净化设备
//           （FFU/风淋室由上位调度，本件零执行输出）。
// 开源溯源 (Origin)：道莅原创实现（参考 ISO 14644-1:2015 Table 1 公开分级口径 分类与参数域）
// 单位表：粒子计数[颗] / 采样体积[L] / 浓度[颗/m³] / 等级[—] / 采样周期[min] / 确认数[个]
// 错误码表：16#0002_3301 信息级（采样失采，等级不可判，等级清零不沿用，
//           不置 bError）/ 16#0002_3302 信息级（等级超 9 钳 9.0，或通道
//           浓度超最深有表值档且更高档无限制被表驱动跳过，不置 bError）/
//           16#0002_3305 预留禁用（不得挪用）/ 16#0002_3310 故障级（采样
//           体积小于等于 0 或组态非法，置 bError）/ 16#0002_3311 故障级
//           （浮点输入非有限，置 bError）/ 16#0002_3312 预留禁用（不得挪用）
// 状态机：E_DL_ParticleStatState（eIdle=0 / eSampling=10 / eLost=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 复用 3311（§3 未为本件
//           单列兜底槽，非法状态按「数据不可信」同语义处置，不得越段
//           加码）并回 eFault、等级清零（安全侧 = 不给达标假象）
// 边界行为：① 浮点输入非有限（NaN 自反判 + Inf 幅值上限判）→ 故障 3311，
//           等级清零；② fSampleVolL 小于等于防除零下限、fClassTarget 超
//           1.0~9.0 域、nConfirmSamples 超 1~10 域、tSampleTime 非正 →
//           故障 3310，先判后除防除零；③ 全通道计数为 0 且脉冲到达 =
//           合法 0 浓度，不判失采（失采只由失采定时器时间判据裁决）；
//           ④ 失采（间隔超 2 倍采样周期）→ 信息 3301 + 等级清零 +
//           bValid := FALSE，禁止沿用旧等级（旧等级会让洁净室误报达标）；
//           bOverLimit 报警锁存保持（已确认的超限事实不因失采被掩盖，
//           恢复采样后由新数据重新裁决）；⑤ 等级超 9 → 判 9.0 并信息
//           3302；⑥ 通道浓度超该通道最深有表值档且更高档为「—」→ 该
//           通道表驱动跳过不参与判定并信息 3302（披露：跳过通道的更高
//           污染贡献不参与最严等级裁决，靠 3302 可观测提示，若全通道
//           均被跳过则等级判不可用）；⑦ 上电首拍 bValid := FALSE；
//           ⑧ 失能 → eIdle、等级清零、报警清除；⑨ 失采定时器经脉冲沿
//           「断输入一拍」重启计时，失采门槛严格等于 2 倍采样周期
//           （R40 家族）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.2）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_ParticleStatState（归属 DL_Algo，与 FB_DL_ParticleCounterStat 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ParticleStatState :
(
    eIdle     := 0,    // 失能/待机：等级输出 0，报警清零 / Idle: class zeroed, alarm cleared
    eSampling := 10,   // 采样有效：最近一次脉冲已判定，等级可用 / Sampling: last pulse judged, class usable
    eLost     := 20,   // 失采：超 2 倍采样周期无脉冲，等级不可判 / Lost: no pulse within twice the sample period
    eFault    := 99    // 故障兜底态：组态非法或非有限，等级清零 / Fault fallback: config invalid or non-finite, class zeroed
);
END_TYPE
FUNCTION_BLOCK FB_DL_ParticleCounterStat
VAR_INPUT
    auCounts        : ARRAY[0..5] OF UDINT;    // 本采样周期各粒径计数 [颗]，通道序 0.1/0.2/0.3/0.5/1.0/5.0 微米 / counts per channel [particles], channels 0.1/0.2/0.3/0.5/1.0/5.0 um
    fSampleVolL     : LREAL := 1.0;            // 采样体积 [L]，域大于 0 / Sample volume [L], domain > 0
    bSamplePulse    : BOOL;                    // 采样周期完成脉冲，上升沿取数 / Sample-complete pulse, latched on rising edge
    fClassTarget    : LREAL := 7.0;            // 目标等级 [—]，1.0~9.0，0.5 步进 / Target class, 1.0~9.0, 0.5 steps
    nConfirmSamples : INT := 3;                // 连续超限确认数 [个]，1~10 / Consecutive over-limit confirmations, 1~10
    tSampleTime     : TIME := T#1M;            // 采样周期 [min]，用于失采判定 / Sample period [min], loss detection basis
    bEnable         : BOOL;                    // 总使能 / Master enable
    bReset          : BOOL;                    // 复位，上升沿清状态与计数 / Reset, rising edge clears state and counters
END_VAR
VAR_OUTPUT
    afConcM3        : ARRAY[0..5] OF LREAL;    // 各粒径浓度 [颗/m³] / Concentration per channel [particles/m3]
    fClassMeasured  : LREAL;                   // 实测等级 [—]，0.0 = 不可判 / Measured class, 0.0 = not judgeable
    bClassOk        : BOOL;                    // 实测等级不超过目标等级 / Measured class within target
    bOverLimit      : BOOL;                    // 连续确认后的超限报警锁存 / Confirmed over-limit alarm latch
    bSampleLost     : BOOL;                    // 失采标志 / Sample-loss flag
    tSinceSample    : TIME;                    // 距上次成功采样耗时 [min] / Time since last accepted sample [min]
    uSampleCount    : UDINT;                   // 累计采样次数 [次]，饱和计数 / Cumulative sample count, saturated
    uOverCount      : UDINT;                   // 累计超限报警次数 [次]，饱和计数 / Cumulative over-limit alarm count, saturated
    eErr            : UDINT;                   // 错误码，0 = 无错，码位 16#0002_3301 起信息级、16#0002_3310 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError          : BOOL;                    // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                    // 等级数据可用标志，失能/失采/故障闸显式 FALSE / Class data usable flag, explicit FALSE on disable/lost/fault gates
    eState          : E_DL_ParticleStatState;  // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbPulse         : R_TRIG;                  // 采样脉冲上升沿检测实例 / Sample pulse rising edge detector
    fbReset         : R_TRIG;                  // 复位上升沿检测实例 / Reset rising edge detector
    fbLostTimer     : TON;                     // 失采定时器：脉冲沿断输入一拍重启计时 / Loss timer: input broken one scan per pulse edge
    bTimerKick      : BOOL;                    // 定时器断输入一拍标志（重启计时，R40 家族）/ One-scan timer kick flag, restarts timing
    auLatch         : ARRAY[0..5] OF UDINT;    // 脉冲沿锁存的计数副本 [颗] / Latched counts copy [particles]
    fVolM3          : LREAL;                   // 采样体积换算 [m³] / Sample volume converted [m3]
    uCh             : INT;                     // 通道循环索引 [—] / Channel loop index
    nClass          : INT;                     // 等级档循环索引 [—] / Class row loop index
    fLimit          : LREAL;                   // 当前档表值 [颗/m³]，负数 = 无限制 / Table limit at current class [particles/m3], negative = no limit
    fLimitFloor     : LREAL;                   // 该通道最深有表值 [颗/m³] / Deepest limited table value of the channel
    nClassFloor     : INT;                     // 该通道最深有表值档号 [—] / Deepest limited class number of the channel
    fChLevel        : LREAL;                   // 通道判定等级 [—] / Per-channel judged class
    bAnyJudged      : BOOL;                    // 本采样是否存在参与判定的通道 / Whether any channel was judged this sample
    bClampHigh      : BOOL;                    // 本采样发生等级钳 9 或表驱动跳过 / Clamp-to-9 or table-skip occurred this sample
    nConsec         : INT;                     // 连续超限计数 [个] / Consecutive over-limit counter
END_VAR
VAR CONSTANT
    DL_PC_ZERO      : LREAL := 0.0;            // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_PC_INF       : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_PC_VOL_MIN   : LREAL := 1.0E-9;         // 体积防除零下限 [L]，低于判组态非法 / Volume floor for zero-division guard [L]
    DL_PC_LITRE_M3  : LREAL := 1000.0;         // 升转立方米系数 [L/m³] / Litre-to-m3 factor
    DL_PC_CLASS_MAX : LREAL := 9.0;            // ISO 等级上限 [—] / ISO class ceiling
    DL_PC_CLASS_MIN : LREAL := 1.0;            // ISO 等级下限 [—] / ISO class floor
    DL_PC_TOL       : LREAL := 1.0E-6;         // 浮点比较容差 [—] / Float comparison tolerance
    DL_PC_CNT_MAX   : UDINT := 16#FFFF_FFFE;   // 饱和计数上限 [次] / Saturating counter ceiling
    DL_PC_LOSS_MULT : INT := 2;                // 失采判据倍率 [倍]，超 2 倍采样周期 / Loss multiplier, twice the sample period
    DL_PC_TIME_ZERO : TIME := T#0S;            // 时间零值基准 [s] / Time zero reference
END_VAR

(*------------------------------------------------------------------------------
 * ISO 14644-1:2015 Table 1 常量上限表：行 = 等级 1..9，列 = 通道
 * 0.1/0.2/0.3/0.5/1.0/5.0 微米；-1.0 = 「—」（无限制），该格跳过不参与
 * 判定。公共领域常量表，数值为标准原文（颗/m³）。
 *----------------------------------------------------------------------------*)
VAR CONSTANT
    DL_PCNT_CODE_INFO_1 : UDINT := 16#0002_3301;   // 信息级槽 1（采样失采） / info slot 1
    DL_PCNT_CODE_INFO_2 : UDINT := 16#0002_3302;   // 信息级槽 2（等级钳 9 或表驱动跳过） / info slot 2
    DL_PCNT_CODE_RSV_1  : UDINT := 16#0002_3305;   // 预留禁用（不得挪用） / reserved, do not use
    DL_PCNT_CODE_FLT_1  : UDINT := 16#0002_3310;   // 故障级槽 1（体积非正或组态非法） / fault slot 1
    DL_PCNT_CODE_FLT_2  : UDINT := 16#0002_3311;   // 故障级槽 2（输入非有限） / fault slot 2
    DL_PCNT_CODE_RSV_2  : UDINT := 16#0002_3312;   // 预留禁用（不得挪用） / reserved, do not use
    DL_PCNT_ISO_LIM : ARRAY[1..9, 0..5] OF LREAL := [
        10.0,      2.0,      -1.0,     -1.0,     -1.0,     -1.0,       // 等级 1 行 / class 1 row
        100.0,     24.0,     10.0,     4.0,      -1.0,     -1.0,       // 等级 2 行 / class 2 row
        1000.0,    237.0,    102.0,    35.0,     8.0,      -1.0,       // 等级 3 行 / class 3 row
        10000.0,   2370.0,   1020.0,   352.0,    83.0,     -1.0,       // 等级 4 行 / class 4 row
        100000.0,  23700.0,  10200.0,  3520.0,   832.0,    29.0,       // 等级 5 行 / class 5 row
        1000000.0, 237000.0, 102000.0, 35200.0,  8320.0,   293.0,      // 等级 6 行 / class 6 row
        -1.0,      2370000.0, 1020000.0, 352000.0, 83200.0, 2930.0,   // 等级 7 行，0.1 微米无限制 / class 7 row, 0.1 um unlimited
        -1.0,      23700000.0, 10200000.0, 3520000.0, 832000.0, 29300.0, // 等级 8 行，0.1 微米无限制 / class 8 row, 0.1 um unlimited
        -1.0,      -1.0,     -1.0,     35200000.0, 8320000.0, 293000.0  // 等级 9 行，0.1/0.2/0.3 微米无限制 / class 9 row, 0.1/0.2/0.3 um unlimited
    ];
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：三实例在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbPulse(CLK := bSamplePulse);                  // 采样沿检测无条件刷新 / sample edge refreshed unconditionally
bTimerKick := fbPulse.Q;                       // 本拍有脉冲则断定时器输入一拍 / break the loss timer input on pulse edge
fbLostTimer(IN := bEnable AND NOT bTimerKick,  // 断输入一拍重启计时（R40 家族）/ break input one scan to restart timing
            PT := tSampleTime * DL_PC_LOSS_MULT);  // 失采门槛 = 2 倍采样周期 / loss threshold = twice the sample period
tSinceSample := fbLostTimer.ET;                // 距上次采样耗时出口 / elapsed since last sample

(*------------------------------------------------------------------------------
 * 段 2｜复位沿：状态回 eIdle、计数清零、报警清除（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState      := E_DL_ParticleStatState.eIdle;
    eErr        := 16#0000_0000;               // 复位清码 / reset clears code
    bError      := FALSE;                      // 复位清故障 / reset clears fault
    fClassMeasured := DL_PC_ZERO;              // 等级清零 / class zeroed
    bClassOk    := FALSE;                      // 达标标志清除 / pass flag cleared
    bOverLimit  := FALSE;                      // 报警锁存清除 / alarm latch cleared
    bSampleLost := FALSE;                      // 失采标志清除 / loss flag cleared
    nConsec     := 0;                          // 连续超限计数清零 / consecutive counter zeroed
    uSampleCount := 0;                         // 采样计数清零 / sample count zeroed
    uOverCount  := 0;                          // 报警计数清零 / alarm count zeroed
    FOR uCh := 0 TO 5 DO
        afConcM3[uCh] := DL_PC_ZERO;           // 浓度出口清零 / concentration outputs zeroed
    END_FOR
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（浮点引脚逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *----------------------------------------------------------------------------*)
IF (fSampleVolL <> fSampleVolL) OR (ABS(fSampleVolL) >= DL_PC_INF)
   OR (fClassTarget <> fClassTarget) OR (ABS(fClassTarget) >= DL_PC_INF) THEN
    eState  := E_DL_ParticleStatState.eFault;
    eErr    := DL_PCNT_CODE_FLT_2;                 // 故障级：浮点输入非有限 / fault: non-finite float input
    bError  := TRUE;                           // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid  := FALSE;                          // 输出不可用 / outputs unusable
    fClassMeasured := DL_PC_ZERO;              // 等级清零安全侧 / class zeroed, safe side
    bClassOk := FALSE;                         // 达标标志清除 / pass flag cleared
    bSampleLost := FALSE;                      // 故障态下失采语义让位非有限故障 / loss flag yields to non-finite fault
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸（体积先判后除、目标域、确认数域、采样周期域）
 *----------------------------------------------------------------------------*)
IF (fSampleVolL <= DL_PC_VOL_MIN)
   OR (fClassTarget < DL_PC_CLASS_MIN - DL_PC_TOL) OR (fClassTarget > DL_PC_CLASS_MAX + DL_PC_TOL)
   OR (nConfirmSamples < 1) OR (nConfirmSamples > 10)
   OR (tSampleTime <= DL_PC_TIME_ZERO) THEN
    eState  := E_DL_ParticleStatState.eFault;
    eErr    := DL_PCNT_CODE_FLT_1;                 // 故障级：体积小于等于 0 或组态非法 / fault: volume non-positive or config invalid
    bError  := TRUE;                           // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid  := FALSE;                          // 输出不可用 / outputs unusable
    fClassMeasured := DL_PC_ZERO;              // 等级清零，不给达标假象 / class zeroed
    bClassOk := FALSE;                         // 达标标志清除 / pass flag cleared
    bSampleLost := FALSE;                      // 故障态下失采语义让位组态故障 / loss flag yields to config fault
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜状态机：CASE 含 ELSE 兜底（非法状态 → 复用 3311 兜底 + 等级清零）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_ParticleStatState.eIdle:
        fClassMeasured := DL_PC_ZERO;          // 待机等级清零 / class zeroed in idle
        bClassOk := FALSE;                     // 达标标志清除 / pass flag cleared
        bOverLimit := FALSE;                   // 报警清除 / alarm cleared
        bSampleLost := FALSE;                  // 失采标志清除 / loss flag cleared
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_ParticleStatState.eSampling;  // 使能即进采样态，等首个脉冲 / enable enters sampling
        END_IF

    E_DL_ParticleStatState.eSampling:
        bValid := FALSE;                       // 默认不可用，脉冲判定通过才置位 / default unusable until judged
        bSampleLost := FALSE;                  // 采样态失采标志复位 / loss flag reset in sampling state
        IF fbLostTimer.Q THEN
            eState      := E_DL_ParticleStatState.eLost;   // 失采转出 / enter lost state
            bSampleLost := TRUE;               // 失采标志置位 / loss flag set
        ELSIF fbPulse.Q THEN
            uSampleCount := uSampleCount + 1;  // 采样计数递增 / increment sample count
            IF uSampleCount >= DL_PC_CNT_MAX THEN
                uSampleCount := DL_PC_CNT_MAX; // 饱和防回绕 / saturate to avoid wrap
            END_IF
            fVolM3 := fSampleVolL / DL_PC_LITRE_M3;  // 升转立方米，fSampleVolL 已闸大于 0 / litre to m3, divisor gated
            FOR uCh := 0 TO 5 DO
                auLatch[uCh]  := auCounts[uCh];                // 锁存计数副本 / latch counts
                afConcM3[uCh] := UDINT_TO_LREAL(auLatch[uCh]) / fVolM3;  // 浓度 = 计数/体积，除子已闸 / concentration, divisor gated
            END_FOR
            fClassMeasured := DL_PC_ZERO;      // 等级初始化，各通道最严（小数值优先）/ class init, strictest channel wins
            bAnyJudged     := FALSE;           // 参与判定通道存在标志复位 / any-judged flag reset
            bClampHigh     := FALSE;           // 本采样钳位/跳过标志复位 / clamp-or-skip flag reset
            FOR uCh := 0 TO 5 DO
                nClassFloor := 0;              // 最深有表值档复位 / deepest limited class reset
                fLimitFloor := DL_PC_ZERO;     // 最深有表值复位 / deepest limited value reset
                FOR nClass := 1 TO 9 DO
                    fLimit := DL_PCNT_ISO_LIM[nClass, uCh];  // 查表取当前档上限 / table lookup
                    IF fLimit >= DL_PC_ZERO THEN
                        nClassFloor := nClass; // 记录最深有表值档 / track deepest limited class
                        fLimitFloor := fLimit; // 记录最深有表值 / track deepest limited value
                    END_IF
                END_FOR
                IF afConcM3[uCh] > fLimitFloor THEN
                    bClampHigh := TRUE;        // 超最深有表值档 → 表驱动跳过或钳 9 / beyond deepest limited row
                    IF nClassFloor >= 9 THEN
                        IF fClassMeasured < DL_PC_CLASS_MAX THEN
                            fClassMeasured := DL_PC_CLASS_MAX;  // 等级超 9 → 钳 9.0 / beyond class 9, clamp
                        END_IF
                        bAnyJudged := TRUE;    // 钳 9 视为参与判定 / clamp counts as judged
                    END_IF
                    // 更高档无表值（nClassFloor < 9）→ 本通道跳过不参与判定，仅提示（边界行为⑥）
                ELSIF afConcM3[uCh] > DL_PC_TOL THEN
                    fChLevel := LREAL(nClassFloor) + LOG(afConcM3[uCh] / fLimitFloor);  // 档内/档下对数插值，生成式恒等口径 / in-row log interpolation, exact per the generation formula
                    IF fChLevel > fClassMeasured THEN
                        fClassMeasured := fChLevel;  // 取最严（小数值等级更严）/ strictest (smallest number) wins
                    END_IF
                    bAnyJudged := TRUE;        // 存在参与判定通道 / a channel was judged
                END_IF
                // 浓度为 0 → 合法零浓度，等级 0，不参与拉高最严值 / zero concentration is legal
            END_FOR
            bClassOk := bAnyJudged AND (fClassMeasured <= fClassTarget + DL_PC_TOL);  // 达标判定（容差比较，禁浮点判等），全通道跳过时不可判 / pass judgement with tolerance, not judgeable when all channels skipped
            IF NOT bAnyJudged THEN
                bClassOk := FALSE;             // 全通道跳过 → 等级不可判 / all channels skipped, class not judgeable
                bValid := FALSE;               // 输出不可用 / outputs unusable
            ELSE
                bValid := TRUE;                // 等级数据可用 / class data usable
            END_IF
            IF bClassOk THEN
                nConsec := 0;                  // 达标清连续计数 / pass resets consecutive counter
            ELSE
                nConsec := nConsec + 1;        // 超限连续计数递增 / over-limit increments counter
                IF nConsec >= nConfirmSamples THEN
                    IF NOT bOverLimit THEN
                        uOverCount := uOverCount + 1;  // 新报警事件计数 / new alarm event counted
                        IF uOverCount >= DL_PC_CNT_MAX THEN
                            uOverCount := DL_PC_CNT_MAX;  // 饱和防回绕 / saturate to avoid wrap
                        END_IF
                    END_IF
                    bOverLimit := TRUE;        // 连续确认后置报警锁存 / alarm latch after confirmation
                END_IF
            END_IF
            eErr   := 16#0000_0000;            // 采样有效，先清码 / valid sample clears code first
            IF bClampHigh THEN
                eErr := DL_PCNT_CODE_INFO_2;   // 信息级：等级钳 9 或表驱动跳过 / info: clamped or table-skipped
            END_IF
            bError := FALSE;                   // 信息级不置 bError / info never raises bError
        END_IF

    E_DL_ParticleStatState.eLost:
        bValid := FALSE;                       // 失采闸显式不可用（R72）/ explicit FALSE on lost gate
        fClassMeasured := DL_PC_ZERO;          // 禁止沿用旧等级，等级清零 / never keep old class, zeroed
        bClassOk := FALSE;                     // 达标标志清除 / pass flag cleared
        eErr   := DL_PCNT_CODE_INFO_1;             // 信息级：采样失采 / info: sample lost
        bError := FALSE;                       // 信息级不置 bError / info never raises bError
        bSampleLost := TRUE;                   // 失采态期间标志保持 / loss flag held in lost state
        IF fbPulse.Q THEN
            eState := E_DL_ParticleStatState.eSampling;  // 事件沿退出 / exit on pulse edge
            bSampleLost := FALSE;              // 前置（失采定时器 Q）随断输入一拍消失 / precondition clears with the timer kick
            eErr := 16#0000_0000;              // 恢复清码 / clear code on recovery
        END_IF

    ELSE
        eState := E_DL_ParticleStatState.eFault;  // 非法状态兜底 / illegal-state fallback
        eErr   := DL_PCNT_CODE_FLT_2;              // 兜底复用故障级槽 2（数据不可信同语义，§3 未单列兜底槽，不得越段加码）/ fallback reuses fault slot 2, no out-of-band code
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        fClassMeasured := DL_PC_ZERO;          // 等级清零安全侧 / class zeroed, safe side
        bClassOk := FALSE;                     // 达标标志清除 / pass flag cleared
END_CASE
END_FUNCTION_BLOCK
