(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CylStrokeTimeBank
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 气缸行程时间分档趋势库。多缸（1..8）各自的行程完成
 *                         事件（bStrokeDone 沿 + nCylId + fStrokeTimeS）逐拍
 *                         建档：每缸记录 count/last/avg/min/max，并与基准时间
 *                         fBaseTimeS 比对输出劣化分档 eClass（0 正常 / 1 关注
 *                         / 2 预警 / 3 劣化），分档按最近耗时相对基准的劣化比
 *                         r = last/base 判定。维护性预测、气缸寿命台账场景。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 边界语义 (Boundary)   : ① 缸号闸：nCylId 落于 1..8 域外 → 本拍拒收建档并
 *                         nWarnCnt 递增（信息级，不置故障级）；
 *                         ② 行程时间闸：fStrokeTimeS <= eps 或 NaN → 拒收
 *                         （传感器坏值不污染台账）；
 *                         ③ 劣化比除零防御：fBaseTimeS <= eps → 组态故障锁存
 *                         （分档判据整体失效必须可观测，R28 组态域闸覆盖）；
 *                         ④ 监视型事件建档，无主状态机（R23 公约）。
 * 输出语义 (Fallback)   : 【R191】bError = TRUE（组态故障）时全部建档动作冻结，
 *                         既有台账保持（不清零——台账是资产）；分档输出保持末值。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL(bError)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（基准 eps 闸）/下标钳位/NaN 拒收 ✓
 *                         R5 双语同行注释 ✓｜R6 N/A（监视型无状态机）✓
 *                         R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 基准 1.0s，缸 3 上报 1.0s → r=1.0 → eClass[3]=0 正常；
 *                         V2 缸 3 上报 1.35s → r=1.35 → eClass[3]=1 关注；
 *                         V3 缸 3 上报 1.8s → eClass[3]=2 预警；2.6s → 3 劣化；
 *                         V4 缸号 0/9 → 拒收且 nWarnCnt 递增。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 2 · 序号 9）
 *==============================================================================*)
TYPE E_DL_CstClass :
(
    eNormal   := 0,                          (* 正常：劣化比 < 1.2 / Normal: ratio < 1.2 *)
    eWatch    := 1,                          (* 关注：1.2 <= r < 1.5 / Watch band *)
    eWarning  := 2,                          (* 预警：1.5 <= r < 2.5 / Warning band *)
    eDegraded := 3                           (* 劣化：r >= 2.5 / Degraded band *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CylStrokeTimeBank
VAR_INPUT
    bStrokeDone : BOOL := FALSE;             (* 行程完成事件电平（内部取沿）[-] / Stroke-done event level *)
    nCylId      : INT := 1;                  (* 气缸编号，域 1..8，域外拒收 [缸] / Cylinder id, domain 1..8 *)
    fStrokeTimeS: LREAL := 0.0;              (* 本次行程耗时 [s] / Stroke time this event *)
    fBaseTimeS  : LREAL := 1.0;              (* 基准行程时间（分档分母），域 > eps [s] / Baseline stroke time *)
    bEnable     : BOOL := TRUE;              (* 建档使能，FALSE 时冻结不动台账 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清全部台账与告警 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    aCnt    : ARRAY[1..8] OF DINT;           (* 各缸建档样本数 [个] / Sample count per cylinder *)
    aLast   : ARRAY[1..8] OF LREAL;          (* 各缸最近行程耗时 [s] / Last stroke time per cylinder *)
    aAvg    : ARRAY[1..8] OF LREAL;          (* 各缸平均行程耗时 [s] / Average per cylinder *)
    aMin    : ARRAY[1..8] OF LREAL;          (* 各缸最小行程耗时 [s] / Minimum per cylinder *)
    aMax    : ARRAY[1..8] OF LREAL;          (* 各缸最大行程耗时 [s] / Maximum per cylinder *)
    aeClass : ARRAY[1..8] OF E_DL_CstClass; (* 各缸劣化分档（按最近耗时相对基准）[-] / Class per cylinder *)
    bBanked : BOOL;                          (* 本拍完成一次建档的单拍脉冲 [-] / Bank-update single-scan pulse *)
    nWarnCnt: UDINT;                         (* 非法缸号/坏值拒收累计（信息级台账）[次] / Rejection counter *)
    bError  : BOOL;                          (* 组态故障锁存标志（基准时间非法）[-] / Config fault flag *)
END_VAR
VAR
    rtDone   : R_TRIG;                       (* 行程完成沿实例，段 0 无条件调用 / Stroke-done edge instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _nId     : INT;                          (* 防御后生效缸号 [缸] / Sanitized cylinder id *)
    _bReject : BOOL;                         (* 本拍拒收当拍量（坏值/非法号）[-] / Reject this scan *)
    _fRatio  : LREAL;                        (* 劣化比 = last/base [-] / Degradation ratio *)
    _bFault  : BOOL;                         (* 组态故障锁存位 / Config fault latch bit *)
    _i       : INT;                          (* 复位清档游标 [-] / Reset clear cursor *)
END_VAR
VAR CONSTANT
    DL_CST_EPS   : LREAL := 1.0E-6;          (* 行程时间判零容差 [s] / Stroke time epsilon *)
    DL_CST_NMAX  : INT   := 8;               (* 缸容量上限 [缸] / Cylinder capacity limit *)
    DL_CST_DMAX  : DINT  := 1073741824;      (* 计数饱和上限 2^30（防回绕）[个] / Count saturation limit *)
    DL_CST_SUMMAX: LREAL := 1.0E15;          (* 均值递推饱和上限（防精度坍缩）[s] / Mean recursion saturation *)
    DL_R_WATCH   : LREAL := 1.2;             (* 关注档劣化比门限 [-] / Watch band ratio *)
    DL_R_WARNING : LREAL := 1.5;             (* 预警档劣化比门限 [-] / Warning band ratio *)
    DL_R_DEGRADE : LREAL := 2.5;             (* 劣化档劣化比门限 [-] / Degraded band ratio *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A） —— *)
rtDone(CLK := bStrokeDone);                  (* 行程完成沿每拍必调 / Stroke edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
bBanked := FALSE;                            (* 建档单拍位预清，唯一分支置位 / Bank pulse preset *)
_bReject := FALSE;                           (* 拒收当拍量预清 / Reject preset *)

(* —— 段 2：组态闸故障锁存（分档分母失效必须可观测，R28 组态域闸；锁存至复位沿，R189） —— *)
IF (fBaseTimeS <= DL_CST_EPS) OR (fBaseTimeS <> fBaseTimeS) OR ((fBaseTimeS - fBaseTimeS) <> (fBaseTimeS - fBaseTimeS)) THEN
    _bFault := TRUE;                         (* 基准时间非法/非有限 → 锁存 / Illegal baseline, latch *)
END_IF

(* —— 段 3：复位沿处理（作用域：清故障 + 清全部缸档位 + 清告警台账，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    nWarnCnt := 0;                           (* 清拒收台账 / Clear counter *)
    _i := 1;                                 (* 游标起头重置（R227） / Cursor reset *)
    WHILE _i <= DL_CST_NMAX DO               (* 全缸档位清零（上电回夹防线） / Clear all banks *)
        aCnt[_i] := 0;                       (* 清计数 / Clear count *)
        aLast[_i] := 0.0;                    (* 清最近值 / Clear last *)
        aAvg[_i] := 0.0;                     (* 清均值 / Clear avg *)
        aMin[_i] := 0.0;                     (* 清最小值 / Clear min *)
        aMax[_i] := 0.0;                     (* 清最大值 / Clear max *)
        aeClass[_i] := E_DL_CstClass.eNormal;   (* 分档回归正常 / Class back to normal *)
        _i := _i + 1;                        (* 游标递进 / Cursor advance *)
    END_WHILE
END_IF

(* —— 段 4：建档事件处理（监视型纯派生，无 CASE 相；使能与组态双闸） —— *)
IF rtDone.Q AND bEnable AND NOT _bFault THEN
    _nId := nCylId;                          (* 生效缸号初值 / Id init *)
    IF (_nId < 1) OR (_nId > DL_CST_NMAX) THEN
        _bReject := TRUE;                    (* 非法缸号拒收 / Illegal id reject *)
    END_IF
    IF (fStrokeTimeS <= DL_CST_EPS) OR (fStrokeTimeS <> fStrokeTimeS) OR ((fStrokeTimeS - fStrokeTimeS) <> (fStrokeTimeS - fStrokeTimeS)) THEN
        _bReject := TRUE;                    (* 坏值/NaN 拒收（不污染台账） / Bad value reject *)
    END_IF
    IF _bReject THEN
        nWarnCnt := nWarnCnt + 1;            (* 信息级台账递增（不置 bError，R90 口径） / Info counter, not fault *)
    ELSE
        aLast[_nId] := fStrokeTimeS;         (* 记最近耗时 / Store last *)
        IF aCnt[_nId] < DL_CST_DMAX THEN
            aAvg[_nId] := (aAvg[_nId] * DINT_TO_LREAL(aCnt[_nId]) + fStrokeTimeS) / DINT_TO_LREAL(aCnt[_nId] + 1);   (* 增量均值，除子恒 >= 1 / Incremental mean, divisor >= 1 *)
            aCnt[_nId] := aCnt[_nId] + 1;    (* 计数递增（回绕防护） / Count advance *)
        END_IF
        IF (aMin[_nId] <= 0.0) OR (fStrokeTimeS < aMin[_nId]) THEN
            aMin[_nId] := fStrokeTimeS;      (* 最小值更新 / Min update *)
        END_IF
        IF fStrokeTimeS > aMax[_nId] THEN
            aMax[_nId] := fStrokeTimeS;      (* 最大值更新 / Max update *)
        END_IF
        _fRatio := fStrokeTimeS / fBaseTimeS;   (* 劣化比：分母已过组态闸，无除零 / Ratio, baseline gated *)
        IF _fRatio >= DL_R_DEGRADE THEN
            aeClass[_nId] := E_DL_CstClass.eDegraded;   (* 劣化档 / Degraded *)
        ELSIF _fRatio >= DL_R_WARNING THEN
            aeClass[_nId] := E_DL_CstClass.eWarning;    (* 预警档 / Warning *)
        ELSIF _fRatio >= DL_R_WATCH THEN
            aeClass[_nId] := E_DL_CstClass.eWatch;      (* 关注档 / Watch *)
        ELSE
            aeClass[_nId] := E_DL_CstClass.eNormal;     (* 正常档（IF 链带 ELSE 兜底，R285） / Normal *)
        END_IF
        bBanked := TRUE;                     (* 建档单拍脉冲 / Bank pulse *)
    END_IF
END_IF

(* —— 段 5：出口映射（R191 名实同源） —— *)
bError := _bFault;                           (* 组态故障镜像 / Config fault mirror *)
END_FUNCTION_BLOCK
