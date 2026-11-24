(*
  FB_DL_FrequencyGenerator  —  连续频率发生（方波 + 相位复位 + 占空比组态）/ Continuous frequency generator, square wave
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_86
  段位说明      : 02_3 段占至 85，86 格为 R38 预留解除后的空穴，本件启用 86 格
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-siggen — 信号发生族 R22 已明文分工的「生连续波」侧
  溯源 Origin   : clean-room 实现，相位累加方波发生为公开经典方法，未复制任何源码行
  功能 Function : 1) 连续方波发生：相位累加器 fPhase ∈ [0,1) 每拍推进 fFreqHz * fDt，
                  fPhase < fDuty 为高电平，占空比组态域 [0,1]；
                  2) bPhaseReset 上升沿强制相位归零（多发生器同相启动 / 节拍对齐用）；
                  3) fFreqHz = 0 时输出恒电平：fDuty > 0 恒高、fDuty = 0 恒低（组态级停波）；
                  4) bOutTakenQ 输出本拍电平 + uCycleCnt 周期计数 + fPhaseOut 相位镜像。
  边界 Boundary : ① 与 FB_DL_PulseGenerator 分工：那件是单发/脉宽（发单发），本件是连续波（生连续波）；
                  与 FB_DL_FrequencyMeasure（测）构成「测 ≠ 生」两侧，三件不可互相替代；
                  ② 与 FB_DL_SineGenerator 引脚命名对齐（fFreqHz/fAmplitude/tSampleTime 口径一致）；
                  ③ 无 TON/边沿实例：相位累加器法，任务周期由调用方经 tSampleTime 注入，
                  < T#10MS 钳位（与 FB_DL_RateLimiter 同一口径）；
                  ④ 频率上限钳位 fFreqHzMax：奈奎斯特防御，频率高于任务频率一半时方波失真，
                  越限按上限执行并置信息级码；
                  ⑤ 非有限频率/占空比防御：NaN/Inf 按上次有效值保持，首扫按默认值。
  依赖 Depends  : 仅 Standard.library；与 FB_DL_PulseGenerator / FB_DL_FrequencyMeasure /
                  FB_DL_SineGenerator（均已注册）仅引脚口径对齐，不实例化
  码表 Error codes（本件格 02_3_86，子码步进 +0x100）:
    16#0002_0186 信息级：频率越上限已钳位（奈奎斯特防御，输出按钳后频率执行）
    16#0002_0286 故障级：组态非法（tSampleTime 非正被钳位后仍异常 / 占空比非有限），锁存至 bReset
    16#0002_0386 信息级：相位复位沿生效（fPhase 已归零）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 1 · 序号 4）
*)

FUNCTION_BLOCK FB_DL_FrequencyGenerator
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能，FALSE 时输出恒低并冻结相位 [-] / Enable, FALSE drives output low and freezes phase
    fFreqHz     : REAL := 10.0;       // 目标频率 [Hz]，域 (0, fFreqHzMax]，越限钳位 / Target frequency [Hz], clamped to Nyquist bound
    fDuty       : REAL := 0.5;        // 占空比 [无量纲 0..1]，高电平时间占比 / Duty cycle, high-level fraction
    bPhaseReset : BOOL := FALSE;      // 相位复位，上升沿 fPhase 归零（多路同相启动）/ Phase reset, rising edge zeroes the phase
    bReset      : BOOL := FALSE;      // 故障复位，上升沿清锁存 [-] / Fault reset, rising edge clears latch
    tSampleTime : TIME := T#100MS;    // 任务周期注入 [ms]，< T#10MS 钳位 / Task cycle time injected by caller
END_VAR
VAR_OUTPUT
    bOut        : BOOL;               // 方波输出，TRUE = 高电平相 [-] / Square-wave output, TRUE in high phase
    fPhaseOut   : REAL;               // 相位镜像 [无量纲 0..1)，诊断用 / Phase mirror for diagnostics
    uCycleCnt   : UDINT;              // 输出周期完成计数 [次]，相位回绕一次计一次，饱和 / Completed cycle count, saturating
    bError      : BOOL;               // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch, set only by fault-level codes
    uErrorId    : UDINT;              // 事件码，0 = 无事件（故障级锁存回放）/ Event code, fault codes latched
END_VAR
VAR
    rtPhaseReset : R_TRIG;            // 相位复位沿实例，主体首部无条件刷新 / Phase reset edge instance
    rtReset      : R_TRIG;            // 故障复位沿实例，主体首部无条件刷新 / Fault reset edge instance
    _fPhase      : REAL := 0.0;       // 内部相位累加器 [无量纲 0..1) / Internal phase accumulator
    _fFreqEff    : REAL := 10.0;      // 钳位后的生效频率 [Hz] / Clamped effective frequency
    _fDutyEff    : REAL := 0.5;       // 钳位后的生效占空比 [无量纲] / Clamped effective duty
    _fDt         : REAL := 0.1;       // 生效任务周期 [s] / Effective cycle time in seconds
    _fFreqLast   : REAL := 10.0;      // 上次有效频率保持载体 [Hz]（非有限防御）/ Last valid frequency hold carrier
    _fDutyLast   : REAL := 0.5;       // 上次有效占空比保持载体 [无量纲] / Last valid duty hold carrier
    _bFault      : BOOL;              // 故障锁存位 / Latched fault bit
    _uFault      : UDINT;             // 故障码锁存寄存 / Latched fault code register
    _uInfo       : UDINT;             // 本拍信息码，每拍重算 / Transient info code this cycle
    _bCfgBad     : BOOL;              // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_FG_DT_MIN     : TIME := T#10MS;      // 任务周期下限钳位 [ms] / Cycle time lower clamp
    DL_FG_FREQ_MAX   : REAL := 50.0;        // 频率组态上限（奈奎斯特防御，按 100ms 任务口径）[Hz] / Frequency configuration bound for Nyquist defense
    DL_FG_INF_CAP    : REAL := 1.0E30;      // 非有限值筛查幅值上限 / Non-finite magnitude screening cap
    DL_FG_CNT_MAX    : UDINT := 16#FFFF_FFFE;  // 周期计数饱和上限 [次] / Cycle count saturation bound
END_VAR

(* —— 段 0：边沿实例无条件周期刷新（R7 红线：严禁置于 IF/CASE 分支内） —— *)
rtPhaseReset(CLK := bPhaseReset);       // 相位复位沿刷新，每拍必调
rtReset(CLK := bReset);                 // 故障复位沿刷新，每拍必调

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                 // 信息码每拍重算
_bCfgBad := FALSE;                      // 组态非法聚合预清零

(* —— 段 2：非有限防御（NaN/Inf 保持上次有效值，首扫用默认） —— *)
IF (fFreqHz <> fFreqHz) OR (ABS(fFreqHz) > DL_FG_INF_CAP) OR ((fFreqHz - fFreqHz) <> 0.0) THEN
    _fFreqEff := _fFreqLast;            // 频率非有限：保持上次有效
    _bCfgBad := TRUE;
ELSE
    _fFreqLast := fFreqHz;              // 有效值入保持载体
    IF fFreqHz < 0.0 THEN
        _fFreqEff := 0.0;               // 负频率钳零（组态级停波）
    ELSIF fFreqHz > DL_FG_FREQ_MAX THEN
        _fFreqEff := DL_FG_FREQ_MAX;    // 越上限钳位（奈奎斯特防御）
        _uInfo := 16#0002_0186;         // 信息级：频率已钳位
    ELSE
        _fFreqEff := fFreqHz;           // 域内直通
    END_IF
END_IF
IF (fDuty <> fDuty) OR (ABS(fDuty) > DL_FG_INF_CAP) OR ((fDuty - fDuty) <> 0.0) THEN
    _fDutyEff := _fDutyLast;            // 占空比非有限：保持上次有效
    _bCfgBad := TRUE;
ELSE
    _fDutyLast := fDuty;
    _fDutyEff := MAX(0.0, MIN(1.0, fDuty));   // 占空比钳到 [0,1]（越界静默钳位，物理量语义）
END_IF

(* —— 段 3：任务周期换算（与 FB_DL_RateLimiter 同口径：< T#10MS 钳位） —— *)
IF tSampleTime < DL_FG_DT_MIN THEN
    _fDt := 0.01;                       // 非法周期钳位 0.01 s
ELSE
    _fDt := TIME_TO_REAL(tSampleTime) / 1000.0;   // TIME 换算秒（显式标准转换）
END_IF

(* —— 段 4：故障锁存与复位沿 —— *)
IF _bCfgBad THEN
    IF NOT _bFault THEN
        _uFault := 16#0002_0286;        // 故障级：组态非法（占空比/频率非有限），仅首次进入时写入
        _bFault := TRUE;
    END_IF
END_IF
IF rtReset.Q THEN
    _bFault := FALSE;                   // 清故障锁存位（唯一解除路径：bReset 上升沿）
    _uFault := 16#0000_0000;
END_IF

(* —— 段 5：相位复位沿（先于推进处理，保证复位拍相位即零） —— *)
IF rtPhaseReset.Q THEN
    _fPhase := 0.0;                     // 相位归零（多路同相启动）
    IF NOT _bFault THEN
        _uInfo := 16#0002_0386;         // 信息级：相位复位生效
    END_IF
END_IF

(* —— 段 6：相位推进与方波生成（失能冻结；故障相保持冻结） —— *)
IF bEnable AND (NOT _bFault) THEN
    _fPhase := _fPhase + _fFreqEff * _fDt;      // 相位推进 = 频率 × 周期
    IF _fPhase >= 1.0 THEN
        _fPhase := _fPhase - 1.0;               // 回绕进位（频率 < 采样率一半时每拍至多进一位）
        uCycleCnt := uCycleCnt + 1;             // 周期完成计数
        IF uCycleCnt >= DL_FG_CNT_MAX THEN
            uCycleCnt := DL_FG_CNT_MAX;         // 计数饱和防回绕
        END_IF
        IF _fPhase >= 1.0 THEN
            _fPhase := 0.0;                     // 极端钳位兜底（频率越限多周回绕）
        END_IF
    END_IF
    bOut := (_fPhase < _fDutyEff);              // 方波判据：相位落在占空比窗内为高电平
END_IF
IF (NOT bEnable) OR _bFault THEN
    bOut := FALSE;                              // 失能/故障：输出恒低（安全侧）
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
fPhaseOut := _fPhase;                           // 相位镜像
IF _bFault THEN
    uErrorId := _uFault;                        // 故障锁存码回放
    bError := TRUE;
ELSE
    uErrorId := _uInfo;                         // 信息码
    bError := FALSE;
END_IF

END_FUNCTION_BLOCK
