(*
  FB_DL_SignalQualify  —  模拟量信号有效性三态联合判定 / Analog signal qualification: over-range, frozen, wire-break
  分类 Category : DL_Base
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-measurement — 信号质量判定族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 对 fRaw 做三态联合判定：超量程（量程域外）/ 断线（低于传感器零点域）/
                  卡死（相邻拍差值持续小于卡死带超过 tFrozenTo），输出 eQual 四态枚举 + bValid；
                  2) 断线判据：fRaw < fScaleLo - fWireMargin（传感器零点域以下）→ eWireBreak；
                  3) 卡死判据：ABS(fRaw - 上拍采样) < fFrozenBand 持续 tFrozenTo → 故障级 03DC；
                  4) bReset 上升沿清全部故障锁存；判定恢复 eOk 沿置信息级码 049E。
  边界 Boundary : ① 组态闸：fScaleLo < fScaleHi 必须成立，违例置故障级 03DB，bValid 强制 FALSE；
                  ② 域判据全部使用当拍量（fRaw 与组态引脚），无锁存量自指；
                  ③ 判定派生链 IF/ELSIF/ELSE 全覆盖，枚举域防御守卫落 03DD 故障锁存；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG）
  码表 Error codes（段 0001，窗口 03DB~03DD / 049E~04A0）:
    16#0001_03DB 故障级：量程组态非法（fScaleLo >= fScaleHi 或卡死带 <= 0），锁存至 bReset
    16#0001_03DC 故障级：信号卡死超时（冻结判据持续 tFrozenTo），锁存至 bReset
    16#0001_03DD 故障级：判定结果落枚举域外（防御守卫兜底），锁存至 bReset
    16#0001_049E 信息级：信号判定恢复正常（eQual 回 eOk 沿）
    16#0001_049F 信息级：超量程检出（伴随态）
    16#0001_04A0 信息级：断线域命中（伴随态）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 1 · 序号 1）
*)

TYPE E_DL_SigQual :
(
    eOk        := 0,    // 信号有效，量程域内且动态正常 / Signal valid, in range and dynamic
    eOverRange := 10,   // 超量程：超出组态量程域 / Over range, outside the configured span
    eFrozen    := 20,   // 卡死：变化量持续小于卡死带 / Frozen, change stays below the deadband
    eWireBreak := 30    // 断线：低于传感器零点域 / Wire break, below the sensor zero span
);
END_TYPE

FUNCTION_BLOCK FB_DL_SignalQualify
VAR_INPUT
    fRaw         : LREAL := 0.0;      // 原始采样值 [EU] / Raw sampled value
    fScaleLo     : LREAL := 0.0;      // 量程下限 [EU]，必须 < fScaleHi / Span lower bound
    fScaleHi     : LREAL := 100.0;    // 量程上限 [EU]，必须 > fScaleLo / Span upper bound
    fWireMargin  : LREAL := 1.0;      // 断线判据裕度 [EU]，域 >= 0 / Wire-break margin below span low
    fFrozenBand  : LREAL := 0.01;     // 卡死判定带 [EU]，域 > 0 / Frozen deadband
    tFrozenTo    : TIME := T#5S;      // 卡死确认超时 [ms]，域 > 0 / Frozen confirm timeout
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latches
END_VAR
VAR_OUTPUT
    eQual        : E_DL_SigQual;      // 判定结果出口 / Qualification result
    bValid       : BOOL;              // 判定有效（eOk 且无故障）/ Result usable flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件（故障锁存回放优先）/ Event code
END_VAR
VAR
    tonFrozen    : TON;               // 卡死确认定时器，无条件周期刷新 / Frozen confirm timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件周期刷新 / Reset edge instance
    _fLastRaw    : LREAL := 0.0;      // 上拍采样快照 [EU] / Previous scan sample snapshot
    _fDelta      : LREAL;             // 相邻拍差值绝对值 [EU] / Absolute inter-scan delta
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bOkPrev     : BOOL;              // 上拍判定有效镜像（恢复沿判据）/ Previous eOk mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_fDelta := ABS(fRaw - _fLastRaw);                                       // 相邻拍差值（当拍量）
tonFrozen(IN := (_fDelta < fFrozenBand), PT := tFrozenTo);              // 卡死确认（每拍必调）
rtReset(CLK := bReset);                                                 // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bValid := FALSE;                    // 有效出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件
eQual := E_DL_SigQual.eOk;          // 判定缺省有效（派生链覆盖改写）

(* —— 段 2：复位沿（唯一故障解除路径，全当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF

(* —— 段 3：组态域闸（覆盖参与判据换算的全部组态引脚） —— *)
IF (fScaleLo >= fScaleHi) OR (fFrozenBand <= 0.0) OR (TIME_TO_DINT(tFrozenTo) <= 0) THEN
    _uFault := 16#0001_03DB;        // 故障级：量程组态非法
    _bFault := TRUE;
END_IF

(* —— 段 4：三态联合判定（全当拍量判据；派生链 ELSE 兜底 + 枚举域守卫） —— *)
IF NOT _bFault THEN
    IF fRaw < (fScaleLo - ABS(fWireMargin)) THEN
        eQual := E_DL_SigQual.eWireBreak;   // 断线：低于传感器零点域
        _uInfo := 16#0001_04A0;             // 信息级：断线域命中
    ELSIF (fRaw > fScaleHi) OR (fRaw < fScaleLo) THEN
        eQual := E_DL_SigQual.eOverRange;   // 超量程
        _uInfo := 16#0001_049F;             // 信息级：超量程检出
    ELSIF tonFrozen.Q THEN
        eQual := E_DL_SigQual.eFrozen;      // 卡死确认
        _uFault := 16#0001_03DC;            // 故障级：卡死超时
        _bFault := TRUE;
    ELSE
        eQual := E_DL_SigQual.eOk;          // 判定有效
        IF NOT _bOkPrev THEN
            _uInfo := 16#0001_049E;         // 信息级：判定恢复有效沿
        END_IF
    END_IF
    (* 枚举域防御守卫（等价 CASE ELSE 兜底）：判定结果必须落已知枚举域 *)
    IF (eQual <> E_DL_SigQual.eOk) AND (eQual <> E_DL_SigQual.eOverRange)
       AND (eQual <> E_DL_SigQual.eFrozen) AND (eQual <> E_DL_SigQual.eWireBreak) THEN
        _uFault := 16#0001_03DD;            // 故障级：判定态落域外
        _bFault := TRUE;
        eQual := E_DL_SigQual.eOk;          // 强制回已知态
    END_IF
END_IF

(* —— 段 5：出口单点映射（名实同源；故障锁存码回放，禁同拍抹除） —— *)
bValid := (eQual = E_DL_SigQual.eOk) AND (NOT _bFault);   // 有效出口（信息级不置故障）
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
_bOkPrev := (eQual = E_DL_SigQual.eOk);   // 恢复沿判据快照（当拍量快照）
_fLastRaw := fRaw;                  // 上拍采样快照更新（段末统一写）

END_FUNCTION_BLOCK
