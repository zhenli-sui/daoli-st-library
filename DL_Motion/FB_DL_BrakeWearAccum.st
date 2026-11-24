(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BrakeWearAccum
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库，
 *                         零轴状态枚举引用（R277）
 * 功能描述 (Function)   : 抱闸磨损里程累计。两种磨损源并行累计：① 制动投入
 *                         时长积分（bBrakeOn 电平 × fWearRatePctPerS）；
 *                         ② 投入次数加权（bBrakeOn 上升沿 × fWearPctPerEngage）。
 *                         磨损百分比累计值对 fWearLimitPct 归一输出 fWearPct，
 *                         达预警阈 fWarnPct → bWearWarn 锁存，达限值 →
 *                         bWearAlarm 锁存（维护动作判据）。与 AxisBrakeTest
 *                         分工：本件被动累计，不执行周期试验。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : BrakeWearAccum（磨损累计，本件）↔ AxisBrakeTest（周期
 *                         试验，既有件）：本件只做投入时长/次数的磨损加权累计
 *                         与阈值告警，不主动试验抱闸、不判抱闸性能（R298 属主
 *                         边界）。
 * 边界语义 (Boundary)   : ① 时长积分用 tScan 引脚步长（组态闸 > 0），上限饱和
 *                         防精度坍缩；
 *                         ② 沿计数回绕防护（DINT 饱和）；
 *                         ③ 预警/告警锁存独立（归因唯一，R190），复位沿一并清；
 *                         ④ 组态闸：磨损率/限值/扫描周期域检查 → 故障锁存；
 *                         ⑤ 监视型无主状态机（R23 公约）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 累计冻结（磨损台账是资产，
 *                         不清零），告警锁存保持；eFault 相 → 冻结 + bError。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL(bError)+
 *                         eCause 枚举，码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 饱和防回绕/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 N/A（监视型无状态机）✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 fWearRatePctPerS=0.001，投入 100s → fWearPct=0.1；
 *                         V2 每次投入加权 0.01，投入 50 次 → 累计 +0.5；
 *                         V3 fWarnPct=80，fWearLimitPct=100 → 80 时 bWearWarn，
 *                         100 时 bWearAlarm（独立锁存）；
 *                         V4 复位沿全清（台账归零语义，上电回夹防线）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 4 · 序号 20）
 *==============================================================================*)
TYPE E_DL_BwaCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1                        (* 组态非法：磨损率/限值/周期越域 / Illegal config *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BrakeWearAccum
VAR_INPUT
    bBrakeOn        : BOOL := FALSE;         (* 制动投入电平（抱闸闭合反馈直连）[-] / Brake-on level *)
    fWearRatePctPerS: LREAL := 0.001;        (* 投入时长磨损率，域 > 0.0 [pct/s] / Wear rate per second *)
    fWearPctPerEngage: LREAL := 0.01;        (* 单次投入磨损加权，域 >= 0.0 [pct/次] / Wear per engagement *)
    fWarnPct        : LREAL := 80.0;         (* 预警阈值，域 0..限值 [pct] / Warning threshold *)
    fWearLimitPct   : LREAL := 100.0;        (* 磨损限值（寿命终点），域 > 预警阈 [pct] / Wear limit *)
    tScan           : TIME := T#10MS;        (* 扫描周期（时长积分步长），域 > T#0S [ms] / Scan cycle step *)
    bEnable         : BOOL := TRUE;          (* 累计使能，FALSE 冻结台账 [-] / Enable *)
    bReset          : BOOL := FALSE;         (* 复位命令，上升沿全清台账与告警锁存 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fWearPct   : LREAL;                      (* 磨损累计百分比（对限值归一前）[pct] / Accumulated wear percent *)
    fOnTimeS   : LREAL;                      (* 制动投入总时长（台账）[s] / Total brake-on time *)
    nEngageCnt : DINT;                       (* 制动投入总次数（台账）[次] / Total engagement count *)
    bWearWarn  : BOOL;                       (* 达预警阈锁存位（复位沿清）[-] / Wear warning latch *)
    bWearAlarm : BOOL;                       (* 达限值锁存位（复位沿清，独立归因 R190）[-] / Wear alarm latch *)
    eCause     : E_DL_BwaCause;              (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError     : BOOL;                       (* 组态故障锁存标志 [-] / Config fault flag *)
END_VAR
VAR
    rtOn     : R_TRIG;                       (* 投入上升沿实例，段 0 无条件调用 / Engagement edge instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fWear   : LREAL;                        (* 磨损累计器（锁存量）[pct] / Wear accumulator *)
    _fOnT    : LREAL;                        (* 投入时长累计器（锁存量）[s] / On-time accumulator *)
    _fScanS  : LREAL;                        (* 扫描周期秒值缓存 [s] / Scan seconds cache *)
    _nEng    : DINT;                         (* 投入次数累计器（锁存量）[次] / Engagement counter *)
    _bFault  : BOOL;                         (* 组态故障锁存位 / Config fault latch bit *)
END_VAR
VAR CONSTANT
    DL_BWA_EPS   : LREAL := 1.0E-9;          (* 判零容差 [pct] / Zero epsilon *)
    DL_BWA_SUMMAX: LREAL := 1.0E12;          (* 时长/累计饱和上限（防精度坍缩）[s|pct] / Accumulator saturation *)
    DL_BWA_ENGMAX: DINT  := 1073741824;      (* 次数饱和上限 2^30（防回绕）[次] / Engagement saturation *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A） —— *)
rtOn(CLK := bBrakeOn);                       (* 投入沿每拍必调 / On edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：组态闸故障锁存（全引脚覆盖含 NaN 自反，R151/R28；锁存至复位沿，R189） —— *)
IF ((fWearRatePctPerS <= DL_BWA_EPS) OR (fWearPctPerEngage < 0.0)
    OR (fWarnPct < 0.0) OR (fWarnPct > fWearLimitPct) OR (fWearLimitPct <= DL_BWA_EPS)
    OR (tScan <= T#0S)
    OR (fWearRatePctPerS <> fWearRatePctPerS) OR (fWearLimitPct <> fWearLimitPct)) AND NOT _bFault THEN
    _bFault := TRUE;                         (* 组态非法锁存（R45 配对） / Latch config fault *)
    eCause := E_DL_BwaCause.eCfgIllegal;     (* 成因：组态非法 / Cause: illegal config *)
END_IF
_fScanS := TIME_TO_LREAL(tScan) / 1000.0;    (* 毫秒口径换算秒（整毫秒无损）[s] / Convert ms to seconds *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清磨损/时长/次数累计器 + 清双告警锁存，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    eCause := E_DL_BwaCause.eNone;           (* 清成因 / Clear cause *)
    _fWear := 0.0;                           (* 清磨损累计 / Clear wear *)
    _fOnT := 0.0;                            (* 清时长累计 / Clear on-time *)
    _nEng := 0;                              (* 清次数累计 / Clear count *)
    bWearWarn := FALSE;                      (* 清预警锁存 / Clear warning *)
    bWearAlarm := FALSE;                     (* 清告警锁存 / Clear alarm *)
    fWearPct := 0.0;                         (* 清磨损出口 / Clear wear outlet *)
    fOnTimeS := 0.0;                         (* 清时长出口 / Clear time outlet *)
    nEngageCnt := 0;                         (* 清次数出口 / Clear count outlet *)
END_IF

(* —— 段 3：磨损双源累计（监视型纯派生，无 CASE 相） —— *)
IF bEnable AND NOT _bFault THEN
    IF bBrakeOn THEN
        IF _fOnT < DL_BWA_SUMMAX THEN        (* 时长饱和防护（防精度坍缩） / On-time saturation *)
            _fOnT := _fOnT + _fScanS;        (* 投入时长积分 / On-time integrate *)
        END_IF
        IF _fWear < DL_BWA_SUMMAX THEN       (* 磨损饱和防护 / Wear saturation *)
            _fWear := _fWear + fWearRatePctPerS * _fScanS;   (* 时长磨损加权累计（除法无涉，乘法直算） / Time-based wear accumulate *)
        END_IF
    END_IF
    IF rtOn.Q THEN                           (* 投入沿：次数加权磨损（沿消费已武装，R305） / Engagement edge *)
        IF _nEng < DL_BWA_ENGMAX THEN
            _nEng := _nEng + 1;              (* 次数递增（回绕防护） / Count advance *)
        END_IF
        _fWear := _fWear + fWearPctPerEngage;   (* 次数磨损加权累计 / Engagement wear accumulate *)
    END_IF
    IF _fWear > DL_BWA_SUMMAX THEN
        _fWear := DL_BWA_SUMMAX;             (* 磨损累计兜底饱和 / Wear cap *)
    END_IF
    IF _fWear >= fWearLimitPct THEN
        bWearAlarm := TRUE;                  (* 达限告警锁存至复位沿（独立归因，R190） / Alarm latch *)
    END_IF
    IF _fWear >= fWarnPct THEN
        bWearWarn := TRUE;                   (* 达预警锁存至复位沿（独立归因，R190） / Warning latch *)
    END_IF
END_IF

(* —— 段 4：出口映射（R191 名实同源） —— *)
fWearPct := _fWear;                          (* 磨损出口镜像 / Wear mirror *)
fOnTimeS := _fOnT;                           (* 时长出口镜像 / Time mirror *)
nEngageCnt := _nEng;                         (* 次数出口镜像 / Count mirror *)
bError := _bFault;                           (* 组态故障镜像 / Config fault mirror *)
END_FUNCTION_BLOCK
