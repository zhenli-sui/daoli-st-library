(*
    FB_DL_AnalogDriftWatch —— 模拟量双通道冗余漂移监测
    ------------------------------------------------------------------
    分类      : DL_Device / AnalogHealth
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : clean-room 自有实现；仅借鉴「双通道偏差指数遗忘累积」的公开
                滤波/监测常识语义，未复制任何闭源厂商源码，码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R76 冲刺批 C3 · #4）
    ------------------------------------------------------------------
    功能说明  : 双通道模拟量 fValA/fValB 冗余漂移监测：偏差 |fValA - fValB| 按指数
                遗忘累积为漂移估计 fDrift（α = fDtSec / (fTauSec + fDtSec)，分母
                门禁防除零，α 天然落在 (0,1] 无需再钳位）。漂移超 fWarnTh 报预警
                （bWarn，信息/预警级，不置 bError）；超 fFaultTh 报故障并判主通道
                失可信（bATrust = FALSE），锁存至 bReset 复位沿。任一通道非有限值
                （NaN f<>f、±Inf (f-f)<>(f-f)）按「单边失可信」处理：该通道信任
                标志置 FALSE、漂移估计冻结不更新、条件级故障码每拍重发布，
                不误报漂移，条件消失自动恢复。
                边界：只产出漂移估计与信任判定，不做通道切换、不修正采样值。
    错误码    : 16#0005_2000 参数非法（时间常数/周期非正或非有限 / 阈值非正 /
                             fFaultTh <= fWarnTh）——故障级，锁存至复位沿
                16#0005_2001 漂移估计超故障阈值，主通道 A 判失可信——故障级，
                             锁存至 bReset 复位沿
                16#0005_2002 通道 A 非有限，单边失可信，估计冻结——条件级故障，
                             条件存在每拍重发布、条件消失自动恢复，不锁存
                16#0005_2003 通道 B 非有限，单边失可信，估计冻结——条件级故障，
                             同 2002 口径
                16#0005_2004 漂移估计超预警阈值——预警级，超阈期间持续发布，不置 bError
                16#0005_2005 CASE 落 ELSE 兜底——故障级，锁存至复位沿
    码位总账  : 16#0005_2000..2005 全部定义并使用，无空悬码位
    状态机    : E_DL_DriftState（eIdle / eRun / eFault），CASE 含 ELSE 兜底：落 ELSE
                置 16#0005_2005 并回 eFault。eIdle 时不背书：bATrust/bBTrust 置
                FALSE（监测未运行不给可信结论）；eFault 锁存码回放，bReset 上升沿
                且参数已合法时清零漂移估计回 eIdle。
    定时器    : 本件无 TON；仅一只 R_TRIG 在本体段 1 无条件周期刷新（R7）。
    防御口径  : α 分母 (fTauSec + fDtSec) 强制 > 0 且两参非有限门禁后才做除法，
                绝无除零；阈值比较用严格大于（禁 =/<>）；漂移估计仅当双通道
                均有限时更新，冻结路径不触碰累计量。
    修订记录  : 2026-11-23 v1.0.0 首次入库（R76 冲刺批 C3 · #4）
*)
TYPE E_DL_DriftState :
(
    eIdle  := 0,   // 待机，监测未投运，不背书信任标志 / idle, monitoring off, trust flags not endorsed
    eRun   := 10,  // 运行，每拍更新漂移估计并判阈 / running, drift estimate updated and thresholds judged every scan
    eFault := 20   // 故障，锁存码回放，主通道判失可信 / fault, latch replayed, the main channel is distrusted
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnalogDriftWatch
VAR_INPUT
    fValA    : LREAL;                  // 主通道 A 采样值 [工程单位] / main channel A sample [engineering unit]
    fValB    : LREAL;                  // 备通道 B 采样值 [工程单位] / redundant channel B sample [engineering unit]
    fWarnTh  : LREAL := 1.0;           // 漂移预警阈值 [工程单位]，必须大于 0 / drift warning threshold [engineering unit], must exceed zero
    fFaultTh : LREAL := 2.0;           // 漂移故障阈值 [工程单位]，必须大于 fWarnTh / drift fault threshold, must exceed fWarnTh
    fTauSec  : LREAL := 5.0;           // 指数遗忘时间常数 [s]，必须大于 0 / exponential forgetting time constant [s], must exceed zero
    fDtSec   : LREAL := 0.1;           // 采样周期 [s]，必须大于 0 / sampling period [s], must exceed zero
    bMonEn   : BOOL := TRUE;           // 监测投运命令 / monitoring enable command
    bReset   : BOOL;                   // 故障复位请求，上升沿生效 / fault reset request, edge-active
END_VAR
VAR_OUTPUT
    fDrift   : LREAL;                  // 漂移估计 [工程单位]，仅双通道有限时更新 / drift estimate [engineering unit], updated only when both channels are finite
    bWarn    : BOOL;                   // 预警标志，超 fWarnTh 置位 / warning flag, raised above fWarnTh
    bATrust  : BOOL;                   // 主通道 A 可信标志，非有限或漂移故障置 FALSE / main channel trust flag, FALSE when non-finite or on a drift fault
    bBTrust  : BOOL;                   // 备通道 B 可信标志，非有限置 FALSE / redundant channel trust flag, FALSE when non-finite
    eState   : E_DL_DriftState;        // 当前状态镜像输出 / current state mirror output
    nErrCode : UDINT;                  // 错误码，0 = 无错；锁存级回放、条件级随条件发布 / error code, 0 = none; latched codes replayed, conditional codes per condition
    bError   : BOOL;                   // 故障级标志，仅故障级码置位 / fault-class flag, raised only by fault-class codes
    bValid   : BOOL;                   // 输出可用标志，= NOT bError / outputs valid flag, equals NOT bError
END_VAR
VAR
    _eState    : E_DL_DriftState;      // 当前状态 / current state
    _uErrLatch : UDINT;                // 锁存故障码副本（2000/2001/2005），故障态每拍回放 / latched fault code replayed inside the fault state
    rtReset    : R_TRIG;               // 复位上升沿检测 / reset rising-edge detector
    _fAlpha    : LREAL;                // 遗忘系数 α = fDtSec/(fTauSec+fDtSec)，(0,1] / forgetting factor within (0,1]
    _fDiff     : LREAL;                // 本拍双通道偏差绝对值 [工程单位] / absolute inter-channel deviation this scan
    _bAOk      : BOOL;                 // 通道 A 有限标志 / channel A finite flag
    _bBOk      : BOOL;                 // 通道 B 有限标志 / channel B finite flag
    _bParOk    : BOOL;                 // 参数门禁结果 / parameter gate result
END_VAR
VAR CONSTANT
    DL_ADW_ONE  : LREAL := 1.0;        // 遗忘权重基值 [无量纲] / forgetting weight base [dimensionless]
    DL_ADW_ZERO : LREAL := 0.0;        // 零值常量，避免裸字面量 [工程单位] / zero constant avoiding a bare literal [engineering unit]
END_VAR

// 段 1｜边缘检测无条件周期刷新（R7：严禁放入 IF / CASE；本件无 TON）
// segment 1, edge detector refreshed unconditionally, never inside IF/CASE; no TON in this FB
rtReset(CLK := bReset);

// 段 2｜输出与错误状态预置；锁存级故障态从锁存副本回放（R45 配对）
// segment 2, preset outputs and error status; latched fault states replay from the latch
bWarn := FALSE;                        // 预置无预警 / preset no warning
bATrust := TRUE;                       // 预置主通道可信 / preset main channel trusted
bBTrust := TRUE;                       // 预装备通道可信 / preset redundant channel trusted
nErrCode := 0;                         // 预置无错误码 / preset no error code
bError := FALSE;                       // 预置无故障标志 / preset no fault flag
bValid := TRUE;                        // 预置输出可用 / preset outputs valid
IF _eState = E_DL_DriftState.eFault THEN
    nErrCode := _uErrLatch;            // 重发布锁存故障码，HMI 不会看到码位闪断 / republish the latched fault code
    bError := TRUE;                    // 故障态恒置故障标志 / fault flag stays raised in the fault state
    bValid := FALSE;                   // 故障态输出不可信 / outputs not valid in the fault state
    IF _uErrLatch = 16#0005_2001 THEN
        bATrust := FALSE;              // 漂移故障回放期主通道持续失可信 / main channel stays distrusted while the drift fault replays
    END_IF
END_IF

// 段 3｜通道有限判定 + α 防除零计算：非有限按单边失可信口径，α 仅在门禁通过后计算
// segment 3, per-channel finite test and the divide-guarded alpha; non-finite follows the single-side distrust policy
_bAOk := NOT ((fValA <> fValA) OR ((fValA - fValA) <> (fValA - fValA)));  // A 非有限判定（NaN 自不等 / Inf 自差不等）/ A NaN via self-inequality, Inf via self-difference
_bBOk := NOT ((fValB <> fValB) OR ((fValB - fValB) <> (fValB - fValB)));  // B 非有限判定，口径同 A / channel B tested the same way
_bParOk := (fTauSec > DL_ADW_ZERO) AND (fDtSec > DL_ADW_ZERO)
       AND (fWarnTh > DL_ADW_ZERO) AND (fFaultTh > fWarnTh)
       AND NOT ((fTauSec <> fTauSec) OR ((fTauSec - fTauSec) <> (fTauSec - fTauSec)))
       AND NOT ((fDtSec <> fDtSec) OR ((fDtSec - fDtSec) <> (fDtSec - fDtSec)))
       AND NOT ((fWarnTh <> fWarnTh) OR ((fWarnTh - fWarnTh) <> (fWarnTh - fWarnTh)))
       AND NOT ((fFaultTh <> fFaultTh) OR ((fFaultTh - fFaultTh) <> (fFaultTh - fFaultTh)));
IF _bParOk THEN
    _fAlpha := fDtSec / (fTauSec + fDtSec); // 分母 = fTauSec + fDtSec > fDtSec > 0，绝无除零；α 天然 (0,1] / denominator exceeds fDtSec, no zero division, alpha within (0,1]
END_IF
IF (NOT _bParOk) AND (_eState <> E_DL_DriftState.eFault) THEN
    _uErrLatch := 16#0005_2000;        // 锁存参数非法码 / latch the illegal parameter code
    nErrCode := 16#0005_2000;          // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
    bError := TRUE;
    bValid := FALSE;
    _eState := E_DL_DriftState.eFault; // 参数不可信直接转故障 / untrusted parameters jump to fault
END_IF

// 段 4｜主状态机：CASE + ELSE 兜底（R6）；漂移更新仅在 eRun 且双通道有限时执行
// segment 4, main state machine, CASE with ELSE fallback; the drift update runs only in eRun with both channels finite
CASE _eState OF
E_DL_DriftState.eIdle:
    // 拍 N 进入：复位后或未投运；本拍行为：不背书信任标志、估计保持清零；拍 N+1 转出：投运且参数合法 → eRun
    // entered after reset or when disabled; no trust endorsement and the estimate stays cleared; exits to eRun on enable with legal parameters
    bATrust := FALSE;                  // 监测未运行不给可信结论 / no trust verdict while monitoring is off
    bBTrust := FALSE;                  // 备通道同样不背书 / the redundant channel is not endorsed either
    fDrift := DL_ADW_ZERO;             // 估计清零，防旧值带病入运行 / clear the estimate so no stale value carries over
    IF bMonEn AND _bParOk THEN
        _eState := E_DL_DriftState.eRun; // 进运行相 / enter the run phase
    END_IF

E_DL_DriftState.eRun:
    // 拍 N 进入：投运且参数合法；本拍行为：双通道有限则更新估计并判阈，单边非有限则
    // 冻结估计、发布条件级码；拍 N+1 转出：超故障阈 → eFault（2001）；参数门禁 → eFault（段 3）
    // entered on enable with legal parameters; the estimate updates and thresholds are judged when both channels
    // are finite, otherwise it freezes with a conditional code; exits to eFault above the fault threshold (2001)
    IF (NOT _bAOk) OR (NOT _bBOk) THEN
        // 单边失可信：估计冻结不更新，杜绝非有限值污染累计量（不误报漂移）
        // single-side distrust: freeze the estimate so non-finite values can never pollute the accumulator
        IF NOT _bAOk THEN
            bATrust := FALSE;              // 主通道失可信 / main channel distrusted
            nErrCode := 16#0005_2002;      // 条件级故障：条件存在每拍重发布、消失自动恢复 / conditional fault republished per scan
            bError := TRUE;                // 故障级码赋值 3 行内置 bError（条件级不锁存）/ fault-class trio, conditional not latched
            bValid := FALSE;
        END_IF
        IF NOT _bBOk THEN
            bBTrust := FALSE;              // 备通道失可信 / redundant channel distrusted
            nErrCode := 16#0005_2003;      // 双通道同拍非有限时 B 后赋值可见 / assigned after A so B wins when both fail together
            bError := TRUE;                // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
            bValid := FALSE;
        END_IF
    ELSE
        _fDiff := ABS(fValA - fValB);      // 本拍偏差绝对值 [工程单位] / absolute deviation this scan
        fDrift := fDrift * (DL_ADW_ONE - _fAlpha) + _fDiff * _fAlpha; // 指数遗忘累积 / exponential forgetting accumulation
        IF fDrift > fFaultTh THEN
            _uErrLatch := 16#0005_2001;    // 锁存漂移故障码 / latch the drift fault code
            nErrCode := 16#0005_2001;      // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
            bError := TRUE;
            bValid := FALSE;
            bATrust := FALSE;              // 主通道判失可信 / main channel distrusted
            _eState := E_DL_DriftState.eFault; // 转故障锁存 / go to fault and latch
        ELSIF fDrift > fWarnTh THEN
            bWarn := TRUE;                 // 预警置位 / raise the warning
            nErrCode := 16#0005_2004;      // 预警级：超阈期间持续发布，不置 bError / warning class, no fault flag
        END_IF
    END_IF

E_DL_DriftState.eFault:
    // 拍 N 进入：参数非法或漂移超故障阈；本拍行为：锁存码回放、信任标志按码维持；
    // 拍 N+1 转出：bReset 上升沿且参数已合法 → eIdle（估计清零重新起算）
    // entered on illegal parameters or a drift fault; the latch replays and trust follows the code;
    // exits to eIdle on a reset edge with legal parameters, the estimate restarts from zero
    IF rtReset.Q AND _bParOk THEN
        _uErrLatch := 0;                   // 清锁存码 / clear the latched code
        fDrift := DL_ADW_ZERO;             // 估计清零重新起算 / restart the estimate from zero
        _eState := E_DL_DriftState.eIdle;  // 回待机等投运 / back to idle awaiting enable
    END_IF

ELSE
    // 非法状态拦截：任何未定义枚举值一律锁存兜底码并转故障（R6）
    // illegal-state interception, any undefined enum value latches the fallback code and goes to fault
    _uErrLatch := 16#0005_2005;            // 锁存兜底码 / latch the fallback code
    nErrCode := 16#0005_2005;              // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
    bError := TRUE;
    bValid := FALSE;
    _eState := E_DL_DriftState.eFault;
END_CASE

// 段 5｜状态镜像输出
// segment 5, state mirror output
eState := _eState;                     // 状态镜像输出 / state mirror output

END_FUNCTION_BLOCK
