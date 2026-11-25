(*
  Name: FB_DL_RoPermeateQualityWatch
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 产水电导率超限监视：越过上限后先经 tDebounceS 去抖（TON），去抖确认才置报警，
           避免单点尖峰造成误报警与误切段。
        2) 回差释放：报警锁存后必须回落到「上限 − 回差带宽」以下才解除，回差带宽由 fHystUsCm 给出，
           防止电导率在上限附近抖振导致报警继电器反复翻转。
        3) 连续超限计数 iOverCnt 记录本次越限持续的扫描拍数，作为劣化速率的粗观测量；
           趋势方向 xRising 由本次采样与上一拍快照的差值给出，差值超过 DL_TREND_EPS 才判上升，
           防止末位噪声被当作趋势。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf；命中时报警与趋势均强制 FALSE 并回待机相。原因是 NaN 与任何数比较
           均为假，会让回差释放判据静默失效（报警永不释放），故必须前置拦截（R19）。
        2) 组态零闸：fLimitUsCm 必须 > DL_EPS、fHystUsCm 必须 >= 0 且 <= fLimitUsCm，
           否则回差下沿会落到负值，释放判据永不成立（死锁），故判组态无效并暂停监视。
        3) 回差下沿钳制：fLimitUsCm − fHystUsCm 结果再钳到 >= 0，防组态越界后下沿为负。
        4) 时间零闸：tDebounceS <= T#0S 时 TON 立即置 Q，等价于「无去抖、即时报警」；
           这是合法组态，不判无效，但语义在此声明，禁止下游按「必有延时」假设时序。
        5) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相；故障解除路径为 xEn 下降沿（可达）。
        6) FB 主体不使用 RETURN（跨平台可移植性考虑，统一单出口）。
  量纲自证：fCondUsCm、fLimitUsCm、fHystUsCm 三者同为电导率 [uS/cm]，比较与相减量纲一致；
           回差下沿 = (uS/cm) − (uS/cm) = uS/cm；tDebounceS 为 [TIME]，与 TON 的 PT 同量纲；
           趋势差值 = (uS/cm) − (uS/cm) = uS/cm，与 DL_TREND_EPS 同量纲，未跨量纲相加。
  码表 Error codes（本件格 0090_02xx）:
    16#0090_0201 信息级：输入非有限或组态越界，监视暂停（不置故障位，不阻止恢复）
    16#0090_0202 故障级：状态机落 ELSE 兜底（非法相位 ID），锁存至 xEn 下降沿解除
*)

TYPE E_DL_RpqwState :
(
    eRpqwIdle     := 0,    // 待机：未使能或输入无效 / Idle: disabled or invalid input
    eRpqwNormal   := 10,   // 正常：电导率在限值以下 / Normal: below limit
    eRpqwDebounce := 20,   // 去抖中：已越限，等待延时确认 / Debouncing: over limit, awaiting confirmation
    eRpqwAlarm    := 30,   // 报警：去抖确认后保持 / Alarm: confirmed and held
    eRpqwFault    := 90    // 故障：非法相位兜底 / Fault: illegal-phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_RoPermeateQualityWatch
VAR_INPUT
    xEn          : BOOL;    // 监视使能 [bool] / Monitoring enable [bool]
    fCondUsCm    : REAL;    // 产水电导率实测值 [uS/cm] / Permeate conductivity [uS/cm]
    fLimitUsCm   : REAL;    // 电导率报警上限 [uS/cm] / Conductivity alarm limit [uS/cm]
    fHystUsCm    : REAL;    // 报警释放回差带宽 [uS/cm] / Alarm release hysteresis band [uS/cm]
    tDebounceS   : TIME;    // 超限去抖延时 [TIME] / Over-limit debounce time [TIME]
END_VAR
VAR_OUTPUT
    xAlarm       : BOOL;    // 超限报警（带回差释放）[bool] / Over-limit alarm with hysteresis [bool]
    xRising      : BOOL;    // 电导率趋势上升标志 [bool] / Rising conductivity trend flag [bool]
    xValid       : BOOL;    // 输入有效标志 [bool] / Input valid flag [bool]
    iOverCnt     : INT;     // 连续超限扫描拍计数 [-] / Consecutive over-limit cycle count [-]
    eState       : E_DL_RpqwState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId       : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonDeb       : TON;     // 超限去抖定时器，每拍无条件调用 / Debounce timer, unconditional call
    _eState      : E_DL_RpqwState := E_DL_RpqwState.eRpqwIdle;   // 内部相位（CASE 唯一写入目标）
    _fHystLoUsCm : REAL;    // 回差释放下沿 [uS/cm] / Hysteresis release low edge [uS/cm]
    _fCondPrev   : REAL;    // 上一拍电导率快照 [uS/cm] / Previous-cycle conductivity snapshot [uS/cm]
    _bOverUp     : BOOL;    // 越过上限（含触点）[bool] / Above upper limit, contact inclusive [bool]
    _bUnderDn    : BOOL;    // 回落到回差下沿以下 [bool] / Below hysteresis low edge [bool]
    _bCfgOk      : BOOL;    // 组态合法性聚合 [bool] / Configuration validity aggregate [bool]
    _bFault      : BOOL;    // 非法相位锁存位 [bool] / Illegal-phase latched flag [bool]
    _uInfo       : UDINT;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault      : UDINT;   // 故障码锁存 / Latched fault code
    _iOverCnt    : INT;     // 连续超限计数内部量 [-] / Consecutive over-limit internal counter [-]
END_VAR
VAR CONSTANT
    DL_EPS       : REAL := 1.0E-9;    // 组态零闸阈值 [-] / Configuration zero gate threshold [-]
    DL_BIG       : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_TREND_EPS : REAL := 0.05;      // 趋势判定的最小差值 [uS/cm] / Minimum delta for trend [uS/cm]
    DL_CNT_MAX   : INT  := 30000;     // 连续超限计数饱和上限 [-] / Over-limit counter saturation [-]
END_VAR

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_iOverCnt/_fCondPrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                             // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                             // 事件码缺省无事件 / Event code defaults to none

(* —— 段 2：非有限值闸（R19：闸断比较通路，NaN 会让回差释放判据静默失效） —— *)
xValid := (fCondUsCm > -DL_BIG AND fCondUsCm < DL_BIG)          // 实测值有限
          AND (fLimitUsCm > -DL_BIG AND fLimitUsCm < DL_BIG)    // 限值有限
          AND (fHystUsCm > -DL_BIG AND fHystUsCm < DL_BIG);     // 回差带宽有限

(* —— 段 3：组态零闸与判据量（R4：回差下沿为负会使释放判据永不成立） —— *)
_bCfgOk := (fLimitUsCm > DL_EPS) AND (fHystUsCm >= 0.0) AND (fHystUsCm <= fLimitUsCm);
_fHystLoUsCm := MAX(0.0, fLimitUsCm - fHystUsCm);               // 回差下沿钳 >= 0 [uS/cm]
_bOverUp := _bCfgOk AND (fCondUsCm >= fLimitUsCm);              // 越过上限（含触点）
_bUnderDn := (NOT _bCfgOk) OR (fCondUsCm <= _fHystLoUsCm);      // 回落到下沿以下（组态坏视为释放）

(* —— 段 4：定时器无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
tonDeb(IN := xEn AND _bOverUp, PT := tDebounceS);   // 去抖窗，表达式入参，每拍必调

(* —— 段 5：相位机（只做迁移，出口在段 7 单点映射） —— *)
IF xValid THEN
    CASE _eState OF

    E_DL_RpqwState.eRpqwIdle:
        IF NOT xEn THEN
            ;                                       // 保持待机 / Stay idle
        ELSIF NOT _bCfgOk THEN
            _uInfo := 16#0090_0201;                 // 信息级：组态越界，暂停监视
        ELSIF _bOverUp AND tonDeb.Q THEN
            _eState := E_DL_RpqwState.eRpqwAlarm;   // 冷启动即在限上且已确认：直接报警
        ELSIF _bOverUp THEN
            _eState := E_DL_RpqwState.eRpqwDebounce;   // 越限但未确认：进去抖相
        ELSE
            _eState := E_DL_RpqwState.eRpqwNormal;  // 限下：进正常相
        END_IF

    E_DL_RpqwState.eRpqwNormal:
        IF (NOT xEn) OR (NOT _bCfgOk) THEN
            _eState := E_DL_RpqwState.eRpqwIdle;    // 失能或组态坏：退待机重判
        ELSIF _bOverUp THEN
            _eState := E_DL_RpqwState.eRpqwDebounce;   // 越过上限：进去抖相
        END_IF

    E_DL_RpqwState.eRpqwDebounce:
        IF NOT xEn THEN
            _eState := E_DL_RpqwState.eRpqwIdle;    // 失能即回待机
        ELSIF NOT _bOverUp THEN
            _eState := E_DL_RpqwState.eRpqwNormal;  // 去抖期间回落：撤销，回正常相
        ELSIF tonDeb.Q THEN
            _eState := E_DL_RpqwState.eRpqwAlarm;   // 去抖确认：报警锁存
        END_IF

    E_DL_RpqwState.eRpqwAlarm:
        IF NOT xEn THEN
            _eState := E_DL_RpqwState.eRpqwIdle;    // 失能清除报警
        ELSIF _bUnderDn THEN
            _eState := E_DL_RpqwState.eRpqwNormal;  // 回差释放：回正常相
        END_IF

    E_DL_RpqwState.eRpqwFault:
        IF NOT xEn THEN
            _bFault := FALSE;                       // 解除路径：xEn 下降沿（可达）
            _uFault := 16#0000_0000;
            _eState := E_DL_RpqwState.eRpqwIdle;
        END_IF

    ELSE
        _uFault := 16#0090_0202;                    // 故障级：非法相位 ID 兜底
        _bFault := TRUE;                            // 锁存（3 行内置，R45 配对）
        _eState := E_DL_RpqwState.eRpqwFault;       // 强制回故障相

    END_CASE

    (* —— 段 6：后置段（R23：计数一律在迁移判断之后处理） —— *)
    IF (_eState = E_DL_RpqwState.eRpqwNormal) OR (_eState = E_DL_RpqwState.eRpqwDebounce)
       OR (_eState = E_DL_RpqwState.eRpqwAlarm) THEN
        IF _bOverUp THEN
            _iOverCnt := MIN(DL_CNT_MAX, _iOverCnt + 1);   // 超限拍数累加（饱和）
        ELSE
            _iOverCnt := 0;                                 // 回落即清零
        END_IF
    ELSE
        _iOverCnt := 0;                                     // 非监视相一律清零
    END_IF
ELSE
    xAlarm := FALSE;                                // 报警强制 FALSE，无效数据不报警
    xRising := FALSE;                               // 趋势强制 FALSE
    _uInfo := 16#0090_0201;                         // 信息级：监视暂停
    _eState := E_DL_RpqwState.eRpqwIdle;            // 回待机相，等输入恢复
    _iOverCnt := 0;                                 // 计数清零（无效数据不累积）
END_IF

(* —— 段 7：出口单点映射（名实同源；报警由状态导出，不在多分支各写一遍） —— *)
xAlarm := (_eState = E_DL_RpqwState.eRpqwAlarm) AND (NOT _bFault);          // 报警出口
xRising := ((fCondUsCm - _fCondPrev) > DL_TREND_EPS) AND xValid AND (NOT _bFault);   // 趋势出口
iOverCnt := _iOverCnt;                              // 连续超限拍数出口
eState := _eState;                                  // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                              // 故障锁存码回放（禁同拍抹除）
ELSE
    nErrId := _uInfo;                               // 信息码
END_IF
_fCondPrev := fCondUsCm;                            // 快照统一在周期末尾更新（R23）

END_FUNCTION_BLOCK
