(*==============================================================================
 * 组件名称 (Component)  : FC_DL_DtAddSecondsSat
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 日期时间饱和加法
 *                         iec-std-wrapper / datetime / r81-forward-saturate
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 IEC 标准 DT/TIME 语义与 ABS/TRUNC
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : 日期时间加秒增量，越域按方向饱和到纪元上下限并报
 *                         故障级（R81 正解方向可饱和），非有限增量提前拦截。
 *
 * 本件存在的意义 (Why this unit exists)：
 *   DT 域加法在跨越纪元上限（库内 DtToDintEpoch 属主的 2038 口径）或下限时，
 *   各平台行为从静默回卷到异常停机不一。本件把「越域」变成显式故障码加饱和值：
 *   正向越界钳到上限、负向越界钳到下限，保守失败方向恒定，调用方看码即知发生了什么。
 *
 * 功能描述 (Function)   : 先对 LREAL 秒增量做非有限双闸（x <> x 判 NaN、
 *                         ABS > 1E308 判 Inf）；零秒恒等返回；增量绝对值超过
 *                         单次 TIME 可表达上限（DL_MAXSEC）时按方向直接饱和；
 *                         合法增量转 TIME 后执行 DT + TIME，结果越上/下限
 *                         同样按方向饱和并报故障码。秒增量按整秒域截断。
 * 与既有件边界 (Boundary): 纪元口径沿用库内 FC_DL_DtToDintEpoch 属主
 *                         （1970-01-01 起、2038-01-19 止的 DINT 秒域）；
 *                         本件只做加法正解方向，不做反解（反解方向按 R81 不饱和）。
 * 码位说明 (Codes)      : 信息 16#0002_3048 零秒增量恒等返回
 *                         故障 16#0002_3049 增量非有限（NaN 或 Inf）
 *                         故障 16#0002_304A 正向越界已饱和到纪元上限
 *                         故障 16#0002_304B 负向越界已饱和到纪元下限
 *                         段 16#02_3_48~4B 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 IEC 标准 DT/TIME/ABS/TRUNC 语义。
 * 偏离留档 (Deviation)  : 增量绝对值大于 DL_MAXSEC（24 小时）时不再做精确加法，
 *                         按增量方向直接饱和。理由：单次 TIME 只能表达约 24.8 天，
 *                         且超一天的时间修正必属越域操作，保守方向饱和比跨平台
 *                         回卷行为更安全，此偏离已在头注释与实现双处留档。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         NaN 用 x <> x、Inf 用 ABS > 1.0E308 精确判据
 *                         全变量双语同行注释 ｜ 无定时器实例 ｜ 无状态机
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 2）
 *============================================================================*)

FUNCTION FC_DL_DtAddSecondsSat : BOOL
VAR_INPUT
    dtIn     : DT;                       // 基准时刻 [日期时间] / Base date-time
    fSecDelta: LREAL;                    // 秒增量 [s]，整秒域，可为负 / Seconds delta, whole-second domain, may be negative
END_VAR
VAR_OUTPUT
    dtOut    : DT;                       // 结果时刻 [日期时间]，越域时为饱和值 / Result, saturated when out of domain
    bSat     : BOOL;                     // 饱和标志，任一方向越域时为真 / TRUE when saturation happened
    uErrorId : UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    tDelta : TIME;    // 整秒增量转出的时长 [s] / Whole-second delta as a TIME duration
    iSec   : DINT;    // 截断后的整秒增量 [s] / Truncated whole-second delta
    uCode  : UDINT;   // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_DAS_MAXSEC  : DINT := 86400;                   // 单次增量上限 [s]，24 小时 / Single delta limit, 24 hours
    DL_DAS_DTMAX   : DT   := DT#2038-01-19-03:14:07;  // 纪元上限，沿用库内 2038 口径 / Epoch upper bound, 2038 convention
    DL_DAS_DTMIN   : DT   := DT#1970-01-01-00:00:00;  // 纪元下限 / Epoch lower bound
END_VAR

(* 段 1｜输出预置 / Pre-set *)
FC_DL_DtAddSecondsSat := FALSE;
dtOut    := dtIn;
bSat     := FALSE;
uErrorId := 16#0000_0000;
uCode    := 16#0000_0000;

(* 段 2｜非有限双闸：NaN 用自反判据，Inf 用实数上限精确判据 / Non-finite gates: NaN by reflexivity, Inf by the real limit *)
IF (fSecDelta <> fSecDelta) OR (ABS(fSecDelta) > 1.0E308) THEN
    uErrorId := 16#0002_3049;    // 故障级：增量非有限，结果保持基准时刻 / Fault: non-finite delta, result stays at base
    RETURN;
END_IF

(* 段 3｜整秒截断：秒域契约，负向同样向零截断 / Whole-second truncation, toward zero in both directions *)
iSec := LREAL_TO_DINT(fSecDelta); // 标准显式转换，向零截断 / Standard explicit conversion, truncates toward zero

(* 段 4｜零秒恒等：信息级告知 / Zero delta identity *)
IF iSec = 0 THEN
    uErrorId := 16#0002_3048;    // 信息级：恒等返回 / Info: identity return
    FC_DL_DtAddSecondsSat := TRUE;
    RETURN;
END_IF

(* 段 5｜越域增量按方向饱和（偏离留档见头注释）/ Oversized delta saturates by direction, see the deviation note *)
IF iSec > DL_DAS_MAXSEC THEN
    dtOut := DL_DAS_DTMAX;       // 正向大步进：饱和到上限 / Positive big step: saturate to the max
    bSat  := TRUE;
    uErrorId := 16#0002_304A;    // 故障级：正向饱和 / Fault: saturated upward
    FC_DL_DtAddSecondsSat := TRUE;
    RETURN;
END_IF
IF iSec < -DL_DAS_MAXSEC THEN
    dtOut := DL_DAS_DTMIN;       // 负向大步进：饱和到下限 / Negative big step: saturate to the min
    bSat  := TRUE;
    uErrorId := 16#0002_304B;    // 故障级：负向饱和 / Fault: saturated downward
    FC_DL_DtAddSecondsSat := TRUE;
    RETURN;
END_IF

(* 段 6｜合法增量：DINT 秒转 TIME 后执行标准 DT 加法 / Legal delta: convert to TIME and add *)
tDelta := DINT_TO_TIME(iSec * 1000);             // 秒转毫秒再转 TIME，乘后仍在 TIME 域内 / Seconds to ms to TIME, in range
dtOut  := dtIn + tDelta;                         // 标准 DT + TIME 语义 / Standard DT plus TIME

(* 段 7｜越界检测与方向饱和 / Bound check and directional saturation *)
IF dtOut > DL_DAS_DTMAX THEN
    dtOut := DL_DAS_DTMAX;       // 正向越界：钳上限 / Upward out of bounds: clamp to the max
    bSat  := TRUE;
    uErrorId := 16#0002_304A;    // 故障级：正向饱和 / Fault: saturated upward
ELSIF dtOut < DL_DAS_DTMIN THEN
    dtOut := DL_DAS_DTMIN;       // 负向越界：钳下限 / Downward out of bounds: clamp to the min
    bSat  := TRUE;
    uErrorId := 16#0002_304B;    // 故障级：负向饱和 / Fault: saturated downward
END_IF
FC_DL_DtAddSecondsSat := TRUE;
END_FUNCTION
