(*
  FB_DL_TriangleGenerator  —  三角波发生（相位连续 + 幅值/频率引脚化）/ Triangle wave generator
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_87
  段位说明      : 86 格由 FB_DL_FrequencyGenerator 启用，本件启用相邻 87 格（一件一码）
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-siggen — 信号发生族第三基本波形（Sine/Sawtooth 同族）
  溯源 Origin   : clean-room 实现，相位累加三角波为公开经典方法，未复制任何源码行
  功能 Function : 1) 三角波发生：相位累加器在 [0,1) 内推进，方向标志交替升/降，
                  归一化输出 fNorm ∈ [0,1]，工程输出 fOut = fOffset + fAmplitude * (2*fNorm − 1)；
                  2) bPhaseReset 上升沿强制相位归零且方向置升（多路同相启动）；
                  3) fFreqHz = 0 时冻结在当前相位值（静止保持，不清输出）；
                  4) 波形形状按矩阵组纪律独立成件，明文禁用 eWaveform 枚举合并
                  （与 FB_DL_SineGenerator / 锯齿族分工，本件只做三角）。
  边界 Boundary : ① 幅值允许负值（输出相位反转语义：负幅值 = 倒相），非有限防御保持上次有效值；
                  ② 偏移 fOffset 非有限防御保持上次有效值；首扫按默认值；
                  ③ 无 TON/边沿实例：相位累加器法，任务周期由调用方经 tSampleTime 注入，
                  < T#10MS 钳位（与 FB_DL_RateLimiter 同口径）；
                  ④ 频率上限钳位（奈奎斯特防御）：高于任务频率一半时波形失真，越限按上限执行并置信息码；
                  ⑤ 方向切换在同一拍完成：fPhase >= 1 时先翻转方向再截去进位，避免相位突变尖峰。
  依赖 Depends  : 仅 Standard.library；与 FB_DL_SineGenerator（已注册）仅引脚口径对齐，不实例化
  码表 Error codes（本件格 02_3_87，子码步进 +0x100）:
    16#0002_0187 信息级：频率越上限已钳位（奈奎斯特防御，输出按钳后频率执行）
    16#0002_0287 信息级：相位复位沿生效（fPhase 归零、方向置升）
    16#0002_0387 信息级：非有限参数防御触发（保持上次有效值继续运行）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 1 · 序号 5）
*)

FUNCTION_BLOCK FB_DL_TriangleGenerator
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能，FALSE 时冻结相位与输出 [-] / Enable, FALSE freezes phase and output
    fFreqHz     : REAL := 1.0;        // 目标频率 [Hz]，域 (0, 上限]，越限钳位 / Target frequency [Hz], clamped
    fAmplitude  : REAL := 100.0;      // 幅值 [EU]，可负（倒相语义），非有限保持 / Amplitude [EU], negative inverts phase
    fOffset     : REAL := 0.0;        // 直流偏移 [EU]，非有限保持 / DC offset [EU]
    bPhaseReset : BOOL := FALSE;      // 相位复位，上升沿相位归零、方向置升 / Phase reset, rising edge zeroes phase
    tSampleTime : TIME := T#100MS;    // 任务周期注入 [ms]，< T#10MS 钳位 / Task cycle time injected by caller
END_VAR
VAR_OUTPUT
    fOut        : REAL;               // 三角波工程输出 [EU] / Triangle engineering output [EU]
    fNormOut    : REAL;               // 归一化输出 [无量纲 0..1]，0 = 谷 / Normalized output, 0 = valley
    bRising     : BOOL;               // 本拍处于上升半周 [-] / Currently in the rising half-cycle
    uCycleCnt   : UDINT;              // 完整周期计数 [次]，降→升切换计一次，饱和 / Full cycle count, saturating
    bError      : BOOL;               // 故障标志，本件全信息级恒 FALSE（R21：信息级码不置故障）[-] / Fault flag, always FALSE, all codes info level
    uErrorId    : UDINT;              // 事件码，0 = 无事件（本件码均瞬时逐拍重算）/ Event code, transient, recomputed each scan
END_VAR
VAR
    rtPhaseReset : R_TRIG;            // 相位复位沿实例，主体首部无条件刷新 / Phase reset edge instance
    _fPhase      : REAL := 0.0;       // 内部相位累加器 [无量纲 0..1) / Internal phase accumulator
    _bUp         : BOOL := TRUE;      // 内部方向标志，TRUE = 升半周 / Internal direction flag, TRUE = rising
    _fFreqEff    : REAL := 1.0;       // 钳位后的生效频率 [Hz] / Clamped effective frequency
    _fAmpEff     : REAL := 100.0;     // 生效幅值 [EU] / Effective amplitude
    _fOffEff     : REAL := 0.0;       // 生效偏移 [EU] / Effective offset
    _fDt         : REAL := 0.1;       // 生效任务周期 [s] / Effective cycle time in seconds
    _fFreqLast   : REAL := 1.0;       // 上次有效频率保持载体 [Hz] / Last valid frequency hold carrier
    _fAmpLast    : REAL := 100.0;     // 上次有效幅值保持载体 [EU] / Last valid amplitude hold carrier
    _fOffLast    : REAL := 0.0;       // 上次有效偏移保持载体 [EU] / Last valid offset hold carrier
    _fNorm       : REAL := 0.0;       // 归一化中间量 [无量纲 0..1] / Normalized working value
    _bDefend     : BOOL;              // 本拍非有限防御触发标志 / Non-finite defense triggered this cycle
END_VAR
VAR CONSTANT
    DL_TG_DT_MIN     : TIME := T#10MS;      // 任务周期下限钳位 [ms] / Cycle time lower clamp
    DL_TG_FREQ_MAX   : REAL := 5.0;         // 频率组态上限（奈奎斯特防御，按 100ms 任务口径）[Hz] / Frequency configuration bound
    DL_TG_INF_CAP    : REAL := 1.0E30;      // 非有限值筛查幅值上限 / Non-finite magnitude screening cap
    DL_TG_CNT_MAX    : UDINT := 16#FFFF_FFFE;  // 周期计数饱和上限 [次] / Cycle count saturation bound
END_VAR

(* —— 段 0：边沿实例无条件周期刷新（R7 红线：严禁置于 IF/CASE 分支内） —— *)
rtPhaseReset(CLK := bPhaseReset);       // 相位复位沿刷新，每拍必调

(* —— 段 1：单拍量预清零 —— *)
uErrorId := 16#0000_0000;               // 事件码每拍重算（本件全信息级）
_bDefend := FALSE;                      // 防御标志预清零

(* —— 段 2：非有限防御与参数钳位（NaN/Inf 保持上次有效值） —— *)
IF (fFreqHz <> fFreqHz) OR (ABS(fFreqHz) > DL_TG_INF_CAP) OR ((fFreqHz - fFreqHz) <> 0.0) THEN
    _fFreqEff := _fFreqLast;            // 频率非有限：保持上次有效
    _bDefend := TRUE;
ELSE
    _fFreqLast := fFreqHz;
    IF fFreqHz < 0.0 THEN
        _fFreqEff := 0.0;               // 负频率钳零（冻结在当前相位值）
    ELSIF fFreqHz > DL_TG_FREQ_MAX THEN
        _fFreqEff := DL_TG_FREQ_MAX;    // 越上限钳位（奈奎斯特防御）
        uErrorId := 16#0002_0187;       // 信息级：频率已钳位
    ELSE
        _fFreqEff := fFreqHz;           // 域内直通
    END_IF
END_IF
IF (fAmplitude <> fAmplitude) OR (ABS(fAmplitude) > DL_TG_INF_CAP) OR ((fAmplitude - fAmplitude) <> 0.0) THEN
    _fAmpEff := _fAmpLast;              // 幅值非有限：保持上次有效
    _bDefend := TRUE;
ELSE
    _fAmpLast := fAmplitude;
    _fAmpEff := fAmplitude;             // 幅值允许负值（倒相语义），不钳位
END_IF
IF (fOffset <> fOffset) OR (ABS(fOffset) > DL_TG_INF_CAP) OR ((fOffset - fOffset) <> 0.0) THEN
    _fOffEff := _fOffLast;              // 偏移非有限：保持上次有效
    _bDefend := TRUE;
ELSE
    _fOffLast := fOffset;
    _fOffEff := fOffset;                // 偏移直通
END_IF
IF _bDefend THEN
    uErrorId := 16#0002_0387;           // 信息级：非有限防御触发（覆盖钳位码，防御码优先）
END_IF

(* —— 段 3：任务周期换算（与 FB_DL_RateLimiter 同口径：< T#10MS 钳位） —— *)
IF tSampleTime < DL_TG_DT_MIN THEN
    _fDt := 0.01;                       // 非法周期钳位 0.01 s
ELSE
    _fDt := TIME_TO_REAL(tSampleTime) / 1000.0;   // TIME 换算秒（显式标准转换）
END_IF

(* —— 段 4：相位复位沿（先于推进处理） —— *)
IF rtPhaseReset.Q THEN
    _fPhase := 0.0;                     // 相位归零
    _bUp := TRUE;                       // 方向置升
    uErrorId := 16#0002_0287;           // 信息级：相位复位生效（覆盖防御码，复位意图优先显式）
END_IF

(* —— 段 5：相位推进与方向翻转（失能冻结；频率 0 冻结在当前值） —— *)
IF bEnable AND (_fFreqEff > 0.0) THEN
    _fPhase := _fPhase + _fFreqEff * _fDt;      // 相位推进 = 频率 × 周期
    IF _fPhase >= 1.0 THEN
        _fPhase := _fPhase - 1.0;               // 截去进位（同拍完成，避免相位突变尖峰）
        IF _bUp THEN
            _bUp := FALSE;                      // 升满翻降（峰点换向）
        ELSE
            _bUp := TRUE;                       // 降满翻升（谷点换向）
            uCycleCnt := uCycleCnt + 1;         // 完整周期计数（降→升切换口径）
            IF uCycleCnt >= DL_TG_CNT_MAX THEN
                uCycleCnt := DL_TG_CNT_MAX;     // 计数饱和防回绕
            END_IF
        END_IF
        IF _fPhase >= 1.0 THEN
            _fPhase := 0.0;                     // 极端钳位兜底（频率越限多周回绕）
        END_IF
    END_IF
END_IF

(* —— 段 6：波形合成（升半周 fNorm = fPhase，降半周 fNorm = 1 − fPhase） —— *)
IF _bUp THEN
    _fNorm := _fPhase;                          // 上升半周：归一化随相位升
ELSE
    _fNorm := 1.0 - _fPhase;                    // 下降半周：归一化随相位降
END_IF
fNormOut := _fNorm;                             // 归一化镜像输出
fOut := _fOffEff + _fAmpEff * (2.0 * _fNorm - 1.0);   // 工程输出 = 偏移 + 幅值 ×（2·归一化 − 1）
bRising := _bUp AND bEnable;                    // 上升半周指示（失能时恒 FALSE）
bError := FALSE;                                // 本件全信息级：故障位恒 FALSE（R21）

END_FUNCTION_BLOCK
