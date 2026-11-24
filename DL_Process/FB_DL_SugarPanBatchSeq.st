(*==============================================================================
  Component : FB_DL_SugarPanBatchSeq
  Category  : DL_Process
  Type      : FB
  Complexity: C4
  VERSION   : v1.0.0
  功能      : 煮糖罐批次时序（抽真空→进糖浆→浓缩→投晶种→助晶→终浓缩→破真空→放糖→洗罐）
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 相迁移主判据为过饱和度 S（本件内联调用 CalcSupersaturation 计算）：
                 S = (Bx / (100 − Bx)) / (BxSat / (100 − BxSat))，BxSat = fSolA + fSolB × 温度；
                 该式为工程线性溶解度近似，精度受 fSolA / fSolB 标定限，不适用于高纯度精糖结晶建模。
              ② 真空与温度双联锁：真空丧失（fVacKpa 高于 fVacGoodKpa）或温度超上限 -> E3 立即断能；
                 温度低于下限 -> E2 停机待复位（糖液过冷会在罐内结块，属可恢复但需人工确认）。
              ③ 黄级语义：助晶相过饱和度超 fSWarn 只记录分级、不迁移、不置 bError（红/黑才动作）。
              ④ 过饱和度计算为「正解方向」：域外输入返回哨兵 0.0 并由调用方升 E2 上报（不静默钳位）。
                 S 物理上恒 > 1（过饱和），故 0.0 与任何合法值不重叠（R81 哨兵口径）。
                 传感器域判只在批次运行相生效——空闲相罐内空载（锤度 0、常压）属正常读数，不得误锁故障。
              ⑤ 默认引脚组合自证（R114）：握手类（bSyrupReady / bSeedAdded / bDischargeDone / bWashDone）
                 默认 FALSE，默认组合无法越过进料与放料握手直达完成相；使能类（bEStopHealthy）默认 TRUE
                 与 bEnable 同族，断线由硬件安全回路保证。
              ⑥ 复位作用域（R311）：bReset 沿清 E2/E3 锁存 + 批次计数 + 曲线锁存；bStop 只清 E2 与相位。
  状态机    : eIdle 待机 / eVacuum 抽真空 / eFillSyrup 进糖浆 / eConcentrate 浓缩到过饱和 /
              eSeed 投晶种 / eGrow 助晶养晶 / eFinalBoil 终浓缩到放糖锤度 / eBreakVac 破真空 /
              eDischarge 放糖 / eWash 洗罐 / eDone 结算拍 / eFault 停机待复位(E2) / eSafeStop 安全断能(E3)
  自检      : R1 零 GVL ｜ R2 零物理地址 ｜ R3 纯 IEC 61131-3 ｜ R4 除零先判 + 非有限自反判 ｜
              R6 CASE 含 ELSE ｜ R7 九 TON 两沿段 0 无条件刷新 ｜ R10 仅标准转换函数 ｜ R14 无属性件
==============================================================================*)
TYPE E_DL_SpbPhase :
(
    eIdle        := 0,  (* 待机：等启动沿 / Idle, waiting for start edge *)
    eVacuum      := 10, (* 抽真空相：真空度达标 / Pulling vacuum *)
    eFillSyrup   := 20, (* 进糖浆相：进料到量 / Filling syrup *)
    eConcentrate := 30, (* 浓缩相：S 到投晶目标 / Concentrating to seeding S *)
    eSeed        := 40, (* 投晶种相：晶种加入完成 / Seeding *)
    eGrow        := 50, (* 助晶相：养晶至目标 S / Crystal growing *)
    eFinalBoil   := 60, (* 终浓缩相：锤度到放糖点 / Final boil to discharge Brix *)
    eBreakVac    := 70, (* 破真空相：破真空到位 / Breaking vacuum *)
    eDischarge   := 80, (* 放糖相：放料完成 / Discharging *)
    eWash        := 90, (* 洗罐相：洗罐完成 / Pan washing *)
    eDone        := 100,(* 结算拍：批次与节拍统计 / Settlement, one-scan *)
    eFault       := 110,(* 停机待复位（E2）/ Stop awaiting reset, E2 *)
    eSafeStop    := 120 (* 安全侧断能（E3）/ Safety energy cut, E3 *)
);
END_TYPE
TYPE E_DL_SpbCause :
(
    eNone       := 0,   (* 无异常 / No anomaly *)
    eVacLost    := 1,   (* 真空度丧失（E3）/ Vacuum lost, E3 *)
    eTempHigh   := 2,   (* 罐温超上限（E3）/ Over-temperature, E3 *)
    eTempLow    := 3,   (* 罐温低于下限（E2，过冷结块）/ Under-temperature, E2 *)
    eSigBad     := 4,   (* 传感器非有限或 S 计算域外（E2）/ Non-finite signal or S out of domain, E2 *)
    eEStopOpen  := 5,   (* 急停回路断开（E3）/ E-stop open, E3 *)
    eVacTmo     := 6,   (* 抽真空超时（E2）/ Vacuum timeout, E2 *)
    eFillTmo    := 7,   (* 进糖浆超时（E2）/ Fill timeout, E2 *)
    eConcTmo    := 8,   (* 浓缩超时（E2）/ Concentrate timeout, E2 *)
    eSeedTmo    := 9,   (* 投晶种超时（E2）/ Seeding timeout, E2 *)
    eGrowTmo    := 10,  (* 助晶超时（E2）/ Growing timeout, E2 *)
    eFinalTmo   := 11,  (* 终浓缩超时（E2）/ Final boil timeout, E2 *)
    eBreakTmo   := 12,  (* 破真空超时（E2）/ Break-vacuum timeout, E2 *)
    eDischTmo   := 13,  (* 放糖超时（E2）/ Discharge timeout, E2 *)
    eWashTmo    := 14,  (* 洗罐超时（E2）/ Wash timeout, E2 *)
    eCfgBad     := 15,  (* 组态非法（E2）/ Illegal configuration, E2 *)
    ePhaseBad   := 16   (* 非法相位兜底（E2）/ Illegal phase fallback, E2 *)
);
END_TYPE
TYPE E_DL_SpbGrade :
(
    eOk     := 0,       (* 无异常 / No anomaly *)
    eYellow := 1,       (* 黄：记录并继续（S 偏离不升故障）/ Yellow, recorded only *)
    eRed    := 2,       (* 红：本批次降级（可继续至放糖）/ Red, batch degraded *)
    eBlack  := 3        (* 黑：立即断能 / Black, immediate energy cut *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SugarPanBatchSeq
VAR_INPUT
    bStart          : BOOL := FALSE;    (* 启动沿（eIdle 入 eVacuum） [-] / Start rising edge *)
    bStop           : BOOL := FALSE;    (* 中止：回 eIdle 并清 E2 锁存 [-] / Abort, clears E2 only *)
    bReset          : BOOL := FALSE;    (* 复位沿：清全部锁存 + 批次计数（R311） [-] / Reset edge *)
    bSyrupReady     : BOOL := FALSE;    (* 进糖浆到位（默认 FALSE 禁跳步） [-] / Syrup fill in position *)
    bSeedAdded      : BOOL := FALSE;    (* 晶种已加入（默认 FALSE 禁跳步） [-] / Seed added *)
    bDischargeDone  : BOOL := FALSE;    (* 放糖完成（默认 FALSE 禁跳步） [-] / Discharge done *)
    bWashDone       : BOOL := FALSE;    (* 洗罐完成（默认 FALSE 禁跳步） [-] / Wash done *)
    bEStopHealthy   : BOOL := TRUE;     (* 急停回路正常（使能类引脚，默认 TRUE） [-] / E-stop healthy *)
    fVacKpa         : LREAL := 101.3;   (* 罐内绝对压力实测（真空好 = 值低） [kPa] / Pan absolute pressure [kPa] *)
    fTempC          : LREAL := 20.0;    (* 糖液温度实测 [℃] / Syrup temperature [degC] *)
    fBrix           : LREAL := 65.0;    (* 糖液锤度实测，域 0..100 [°Bx] / Brix [degBx] *)
    fVacGoodKpa     : LREAL := 30.0;    (* 真空良好门限，域 > 0（实测 <= 该值即真空有效） [kPa] / Vacuum good limit [kPa] *)
    fTempMinC       : LREAL := 60.0;    (* 罐温下限，域 > 0（低于则 E2） [℃] / Temperature floor [degC] *)
    fTempMaxC       : LREAL := 80.0;    (* 罐温上限，域 > fTempMinC（高于则 E3） [℃] / Temperature ceiling [degC] *)
    fSolA           : LREAL := 60.0;    (* 溶解度线性式截距（标定值），域 > 0 [°Bx] / Solubility intercept [degBx] *)
    fSolB           : LREAL := 0.25;    (* 溶解度线性式斜率（标定值），域 > 0 [°Bx/℃] / Solubility slope [degBx/degC] *)
    fSSeed          : LREAL := 1.20;    (* 投晶目标过饱和度，域 > 1.0 [-] / Seeding supersaturation *)
    fSGrow          : LREAL := 1.35;    (* 助晶终点过饱和度，域 > fSSeed [-] / Growing end supersaturation *)
    fSWarn          : LREAL := 1.45;    (* 过饱和预警上界，域 > fSGrow（黄级记录） [-] / Supersaturation warn limit *)
    fBrixDischarge  : LREAL := 92.0;    (* 放糖锤度，域 0..100（且 > fBrix） [°Bx] / Discharge Brix [degBx] *)
    atPhaseTmo      : ARRAY[0..8] OF TIME := [T#20M, T#30M, T#120M, T#10M, T#240M, T#120M, T#10M, T#20M, T#30M];   (* 超时窗 [ms]，下标 0..8 = 抽真空/进料/浓缩/投晶/助晶/终浓/破真空/放糖/洗罐 / Phase windows [ms] *)
    fCycleSec       : LREAL := 0.0;     (* 扫描周期（<=0 用缺省 0.01s） [s] / Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    eState          : E_DL_SpbPhase;    (* 当前相（HMI 诊断） [-] / Present phase *)
    eCause          : E_DL_SpbCause;    (* 成因（锁存回放，R189） [-] / Latched cause playback *)
    eGrade          : E_DL_SpbGrade;    (* 分级出口 [-] / Grade outlet *)
    bError          : BOOL;             (* 故障标志（E2/E3 为 TRUE） [-] / Error flag *)
    bSafeCut        : BOOL;             (* 安全侧断能指令（E3 常 TRUE 至复位） [-] / Safety energy cut *)
    bDone           : BOOL;             (* 单拍结算脉冲 [-] / One-scan done pulse *)
    bBoilActive     : BOOL;             (* 浓缩段指示（供 IO 层驱动蒸汽阀） [-] / Boiling indicator *)
    nBatchCount     : UDINT;            (* 累计批次数（饱和） [批] / Batch count, saturating *)
    fSLast          : LREAL;            (* 最近过饱和度（0 = 无效）/ 哨兵值与合法域不重叠 [-] / Last supersaturation *)
    fBrixLast       : LREAL;            (* 最近锤度 [°Bx] / Last Brix [degBx] *)
    tBatchLast      : TIME;             (* 最近一批总时长 [ms] / Last batch duration [ms] *)
END_VAR
VAR
    _ePhase      : E_DL_SpbPhase := E_DL_SpbPhase.eIdle;     (* 内部相（CASE 唯一写入目标） [-] / Internal phase *)
    _eCause      : E_DL_SpbCause := E_DL_SpbCause.eNone;     (* 成因锁存量 [-] / Latched cause *)
    _eGrade      : E_DL_SpbGrade := E_DL_SpbGrade.eOk;       (* 分级锁存量 [-] / Latched grade *)
    _bFault      : BOOL := FALSE;       (* E2 锁存位（解除 = bReset 沿或 bStop） [-] / E2 latch *)
    _bSafeLatch  : BOOL := FALSE;       (* E3 锁存位（解除 = bReset 沿且安全恢复） [-] / E3 latch *)
    _bFaultReq   : BOOL := FALSE;       (* 单拍 E2 请求（段 1 预清，段 6 落地） [-] / One-scan E2 request *)
    _bSafeReq    : BOOL := FALSE;       (* 单拍 E3 请求（段 1 预清，段 6 落地） [-] / One-scan E3 request *)
    _bDonePulse  : BOOL := FALSE;       (* 单拍结算标志（段 1 预清） [-] / One-scan done flag *)
    _bVacOk      : BOOL := FALSE;       (* 真空有效判据 [-] / Vacuum valid *)
    _bTempHigh   : BOOL := FALSE;       (* 罐温超上限当拍量 [-] / Over-temperature this scan *)
    _bTempLow    : BOOL := FALSE;       (* 罐温低于下限当拍量 [-] / Under-temperature this scan *)
    _bVacBad     : BOOL := FALSE;       (* 真空传感器非有限当拍量 [-] / Vacuum non-finite *)
    _bTempBad    : BOOL := FALSE;       (* 温度传感器非有限当拍量 [-] / Temperature non-finite *)
    _bBrixBad    : BOOL := FALSE;       (* 锤度非有限或域外当拍量 [-] / Brix non-finite or out of domain *)
    _bCfgBad     : BOOL := FALSE;       (* 组态非法当拍量 [-] / Configuration bad *)
    _fS          : LREAL := 0.0;        (* 当拍过饱和度（0 = 计算无效哨兵） [-] / Supersaturation this scan *)
    _fMsTmp      : LREAL := 0.0;        (* 批次时长毫秒暂存（转换前钳位） [ms] / Batch milliseconds scratch *)
    _bVacRequired: BOOL := FALSE;       (* 本相要求真空有效（进料至终浓缩）/ Vacuum required in phase *)
    _bBatchActive: BOOL := FALSE;       (* 批次运行相（空闲与故障相不计信号域判）/ Batch active phase *)
    _bSafeOk     : BOOL := FALSE;       (* 安全条件已恢复（E3 解除判据）/ Safety conditions recovered *)
    _fBrixLatch  : LREAL := 0.0;        (* 锤度锁存（出口留影） [°Bx] / Brix latch *)
    _fBatchAccS  : LREAL := 0.0;        (* 本批时长累加 [s] / Batch time accumulator *)
    _tBatchLast  : TIME := T#0S;        (* 最近批时长锁存 [ms] / Last batch duration latch *)
    _fCy         : LREAL := 0.0;        (* 当拍有效周期 [s] / Effective cycle *)
    _nBatch      : UDINT := 0;          (* 批次累计锁存（饱和） [批] / Batch count latch *)
    _nIdxChk     : INT := 0;            (* 相窗遍历索引（循环变量） [-] / Loop index *)
    tonVacuum    : TON;                 (* 抽真空超时（段 0 无条件调用） / Vacuum timeout *)
    tonFill      : TON;                 (* 进糖浆超时 / Fill timeout *)
    tonConcentrate: TON;                (* 浓缩超时 / Concentrate timeout *)
    tonSeed      : TON;                 (* 投晶种超时 / Seeding timeout *)
    tonGrow      : TON;                 (* 助晶超时 / Growing timeout *)
    tonFinalBoil : TON;                 (* 终浓缩超时 / Final boil timeout *)
    tonBreakVac  : TON;                 (* 破真空超时 / Break-vacuum timeout *)
    tonDischarge : TON;                 (* 放糖超时 / Discharge timeout *)
    tonWash      : TON;                 (* 洗罐超时 / Wash timeout *)
    rtStart      : R_TRIG;              (* 启动沿（段 0 无条件调用） / Start edge *)
    rtReset      : R_TRIG;              (* 复位沿（段 0 无条件调用） / Reset edge *)
END_VAR
VAR CONSTANT
    DL_SPB_CYDEF   : LREAL := 0.01;         (* 缺省扫描周期 [s] / Default scan cycle [s] *)
    DL_SPB_BRIXTOP : LREAL := 100.0;        (* 锤度与溶解度共用上界 [°Bx] / Brix and solubility ceiling *)
    DL_SPB_DENMIN  : LREAL := 1.0E-6;       (* 除法分母下限（判零） [-] / Divisor floor *)
    DL_SPB_BATMAX  : UDINT := 4294967295;   (* 批次计数饱和上限 [批] / Batch count ceiling *)
END_VAR

(*-----------------------------------------------------------------------------
  方法 CalcSupersaturation：过饱和度计算（正解方向，域闸四段式）
  四段：① 返回值预置哨兵 0.0 ② 域闸命中直接 RETURN（非有限 / 锤度域外 / 溶解度域外）
        ③ 域内才做两次除法（分母均已证明 > DL_SPB_DENMIN） ④ 结果非有限复检兜底
  契约：返回 0.0 = 计算无效（哨兵），S 物理恒 > 1，调用方据 0.0 升 E2 上报（禁静默钳位）。
-----------------------------------------------------------------------------*)
METHOD PUBLIC CalcSupersaturation : LREAL
VAR_INPUT
    fBrixIn  : LREAL := 0.0;    (* 锤度输入，域 (0, 100) [°Bx] / Brix input *)
    fTempIn  : LREAL := 0.0;    (* 温度输入 [℃] / Temperature input *)
    fSolAIn  : LREAL := 0.0;    (* 溶解度截距，域 > 0 [°Bx] / Solubility intercept *)
    fSolBIn  : LREAL := 0.0;    (* 溶解度斜率，域 > 0 [°Bx/℃] / Solubility slope *)
END_VAR
VAR
    fBxSat : LREAL := 0.0;      (* 该温度下饱和锤度 [°Bx] / Saturated Brix at temperature *)
    fNum   : LREAL := 0.0;      (* 分子 Bx / (100 − Bx) [-] / Numerator *)
    fDen   : LREAL := 0.0;      (* 分母 BxSat / (100 − BxSat) [-] / Denominator *)
    fS     : LREAL := 0.0;      (* 过饱和度暂存 [-] / Supersaturation scratch *)
END_VAR

CalcSupersaturation := 0.0;     (* ① 预置哨兵 / Preset sentinel *)
IF (fBrixIn <> fBrixIn) OR ((fBrixIn - fBrixIn) <> (fBrixIn - fBrixIn)) THEN
    CalcSupersaturation := 0.0; (* ② 锤度非有限 / Brix non-finite *)
    RETURN;
END_IF
IF (fTempIn <> fTempIn) OR ((fTempIn - fTempIn) <> (fTempIn - fTempIn)) THEN
    CalcSupersaturation := 0.0; (* ② 温度非有限 / Temperature non-finite *)
    RETURN;
END_IF
IF (fSolAIn <= 0.0) OR (fSolBIn <= 0.0) THEN
    CalcSupersaturation := 0.0; (* ② 溶解度系数域外 / Solubility coefficient out of domain *)
    RETURN;
END_IF
IF (fBrixIn <= 0.0) OR (fBrixIn >= DL_SPB_BRIXTOP) THEN
    CalcSupersaturation := 0.0; (* ② 锤度域外（分母 100 − Bx 失效保护）/ Brix out of domain *)
    RETURN;
END_IF
fBxSat := fSolAIn + fSolBIn * fTempIn;                         (* 线性溶解度式 [°Bx] / Linear solubility *)
IF (fBxSat <= 0.0) OR (fBxSat >= DL_SPB_BRIXTOP) THEN
    CalcSupersaturation := 0.0; (* ② 饱和锤度域外 / Saturated Brix out of domain *)
    RETURN;
END_IF
fNum := fBrixIn / (DL_SPB_BRIXTOP - fBrixIn);                   (* ③ 分母 > 0 已证 / Denominator proven positive *)
fDen := fBxSat / (DL_SPB_BRIXTOP - fBxSat);                     (* ③ 分母 > 0 已证 / Denominator proven positive *)
IF fDen < DL_SPB_DENMIN THEN
    CalcSupersaturation := 0.0; (* ③ 分母判零（防御式，域闸后不可达）/ Divisor guard *)
    RETURN;
END_IF
fS := fNum / fDen;                                             (* 过饱和度 [-] / Supersaturation *)
IF (fS <> fS) OR ((fS - fS) <> (fS - fS)) THEN
    CalcSupersaturation := 0.0; (* ④ 结果非有限兜底 / Result non-finite fallback *)
    RETURN;
END_IF
CalcSupersaturation := fS;                                     (* 合法结果输出 / Valid result *)
END_METHOD

(*-----------------------------------------------------------------------------
  方法 ResetBatch：批次锁存复位（不清累计批次数，累计量只能由 bReset 沿清除）
  契约：返回 TRUE 表示复位执行；作用于分级、成因、过饱和度锁存与批次时长累加。
-----------------------------------------------------------------------------*)
METHOD PUBLIC ResetBatch : BOOL
ResetBatch := FALSE;                            (* 预置 / Preset *)
_eGrade := E_DL_SpbGrade.eOk;                   (* 清分级 / Clear grade *)
_eCause := E_DL_SpbCause.eNone;                 (* 清成因 / Clear cause *)
_fS := 0.0;                                     (* 清过饱和度哨兵 / Clear supersaturation *)
_fBrixLatch := 0.0;                             (* 清锤度锁存 / Clear Brix latch *)
_fBatchAccS := 0.0;                             (* 清批次时长累加 / Clear batch accumulator *)
ResetBatch := TRUE;                             (* 复位已执行 / Reset performed *)
END_METHOD

(* —— 段 0：传感器非有限与域判 + 过饱和度计算 + 组态闸 + 周期 + 九 TON 两沿无条件刷新（R7） —— *)
_bVacBad := (fVacKpa <> fVacKpa) OR ((fVacKpa - fVacKpa) <> (fVacKpa - fVacKpa));      (* NaN 自反 + Inf 差值 / NaN and Inf *)
_bTempBad := (fTempC <> fTempC) OR ((fTempC - fTempC) <> (fTempC - fTempC));
_bBrixBad := (fBrix <> fBrix) OR ((fBrix - fBrix) <> (fBrix - fBrix))
          OR (fBrix <= 0.0) OR (fBrix >= DL_SPB_BRIXTOP);                             (* 锤度域外并入信号级 / Brix domain *)
_bVacOk := (NOT _bVacBad) AND (fVacKpa <= fVacGoodKpa);                                (* 真空有效（值低为好）/ Vacuum valid *)
_bTempHigh := (NOT _bTempBad) AND (fTempC > fTempMaxC);                                (* 超上限（E3）/ Over-temperature *)
_bTempLow := (NOT _bTempBad) AND (fTempC < fTempMinC);                                 (* 低于下限（E2）/ Under-temperature *)
_fS := CalcSupersaturation(fBrix, fTempC, fSolA, fSolB);                               (* 过饱和度内联计算 / Supersaturation *)
_bCfgBad := (fVacGoodKpa <= 0.0) OR (fTempMinC <= 0.0) OR (fTempMaxC <= fTempMinC)
         OR (fSolA <= 0.0) OR (fSolB <= 0.0) OR (fBrixDischarge <= 0.0)
         OR (fBrixDischarge >= DL_SPB_BRIXTOP) OR (fSSeed <= 1.0)
         OR (fSGrow <= fSSeed) OR (fSWarn <= fSGrow);                                 (* 组态域闸与配比 / Config gate *)
FOR _nIdxChk := 0 TO 8 DO
    IF atPhaseTmo[_nIdxChk] <= T#0S THEN
        _bCfgBad := TRUE;                                                             (* 任一相窗非正 -> 组态非法 / Non-positive window *)
    END_IF
END_FOR
IF fCycleSec > 0.0 THEN
    _fCy := fCycleSec;                                                                (* 组态周期有效 / Configured cycle *)
ELSE
    _fCy := DL_SPB_CYDEF;                                                             (* 周期缺省兜底 / Default cycle *)
END_IF
rtStart(CLK := bStart);                                                               (* 启动沿，每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                                                               (* 复位沿，每拍必调 / Reset edge every scan *)
tonVacuum(IN := (_ePhase = E_DL_SpbPhase.eVacuum), PT := atPhaseTmo[0]);              (* 抽真空窗 / Vacuum window *)
tonFill(IN := (_ePhase = E_DL_SpbPhase.eFillSyrup), PT := atPhaseTmo[1]);             (* 进料窗 / Fill window *)
tonConcentrate(IN := (_ePhase = E_DL_SpbPhase.eConcentrate), PT := atPhaseTmo[2]);    (* 浓缩窗 / Concentrate window *)
tonSeed(IN := (_ePhase = E_DL_SpbPhase.eSeed), PT := atPhaseTmo[3]);                  (* 投晶窗 / Seeding window *)
tonGrow(IN := (_ePhase = E_DL_SpbPhase.eGrow), PT := atPhaseTmo[4]);                  (* 助晶窗 / Growing window *)
tonFinalBoil(IN := (_ePhase = E_DL_SpbPhase.eFinalBoil), PT := atPhaseTmo[5]);        (* 终浓窗 / Final boil window *)
tonBreakVac(IN := (_ePhase = E_DL_SpbPhase.eBreakVac), PT := atPhaseTmo[6]);          (* 破真空窗 / Break vacuum window *)
tonDischarge(IN := (_ePhase = E_DL_SpbPhase.eDischarge), PT := atPhaseTmo[7]);        (* 放糖窗 / Discharge window *)
tonWash(IN := (_ePhase = E_DL_SpbPhase.eWash), PT := atPhaseTmo[8]);                  (* 洗罐窗 / Wash window *)

(* —— 段 1：单拍量预清零（不含锁存/累加/计数，R107）+ 批次时长累加 —— *)
_bFaultReq := FALSE;                                                                  (* E2 请求预清 / E2 request preset *)
_bSafeReq := FALSE;                                                                   (* E3 请求预清 / E3 request preset *)
_bDonePulse := FALSE;                                                                 (* 结算标志预清 / Done preset *)
bError := FALSE;                                                                      (* 故障标志预清（出口汇总）/ Error preset *)
IF (_ePhase <> E_DL_SpbPhase.eIdle) AND (_ePhase <> E_DL_SpbPhase.eFault)
   AND (_ePhase <> E_DL_SpbPhase.eSafeStop) THEN
    _fBatchAccS := _fBatchAccS + _fCy;                                                (* 批次时长累加（仅工作相）/ Batch time, working phases only *)
END_IF
_bVacRequired := (_ePhase = E_DL_SpbPhase.eFillSyrup) OR (_ePhase = E_DL_SpbPhase.eConcentrate)
              OR (_ePhase = E_DL_SpbPhase.eSeed) OR (_ePhase = E_DL_SpbPhase.eGrow)
              OR (_ePhase = E_DL_SpbPhase.eFinalBoil);                                (* 真空维持段（放糖与洗罐不要求）/ Vacuum-required phases *)
_bBatchActive := (_ePhase <> E_DL_SpbPhase.eIdle) AND (_ePhase <> E_DL_SpbPhase.eDone)
                   AND (_ePhase <> E_DL_SpbPhase.eVacuum) AND (_ePhase <> E_DL_SpbPhase.eFillSyrup)   (* 空罐与进料相锤度天然为 0，不计入信号域判 / Exclude vacuum & fill phases: brix is naturally 0 *)
              AND (_ePhase <> E_DL_SpbPhase.eFault) AND (_ePhase <> E_DL_SpbPhase.eSafeStop);   (* 批次运行相判据 / Batch-active judge *)
_bSafeOk := bEStopHealthy AND (NOT _bTempHigh) AND (NOT _bTempBad);                   (* 安全恢复基础判据 / Base safety recovery *)
IF _eCause = E_DL_SpbCause.eVacLost THEN
    _bSafeOk := _bSafeOk AND _bVacOk;                                                 (* 真空成因须真空恢复（R152 可达性）/ Vacuum cause needs vacuum back *)
END_IF

(* —— 段 2：E3 安全侧（急停 / 真空丧失 / 罐温超上限）——最高优先级 —— *)
IF NOT bEStopHealthy THEN
    IF NOT _bSafeLatch THEN
        _bSafeReq := TRUE;                                                            (* 落地于段 6 / Landed in segment 6 *)
        _eCause := E_DL_SpbCause.eEStopOpen;                                          (* 归因：急停断开 / Cause: E-stop *)
    END_IF
ELSIF _bTempHigh THEN
    IF NOT _bSafeLatch THEN
        _bSafeReq := TRUE;
        _eCause := E_DL_SpbCause.eTempHigh;                                           (* 归因：超温 / Cause: over-temperature *)
    END_IF
ELSIF _bVacRequired AND (NOT _bVacBad) AND (NOT _bVacOk) THEN
    IF NOT _bSafeLatch THEN
        _bSafeReq := TRUE;                                                            (* 真空在非抽真空相丧失：立即断能 / Vacuum lost mid-batch *)
        _eCause := E_DL_SpbCause.eVacLost;                                            (* 归因：真空丧失 / Cause: vacuum lost *)
    END_IF
END_IF

(* —— 段 3：信号域闸与组态闸入 E2（E3 优先，安全相内不重复置因） —— *)
IF _bCfgBad AND (NOT _bSafeLatch) AND (NOT _bFault) THEN
    _bFaultReq := TRUE;                                                               (* 落地于段 6 / Landed in segment 6 *)
    _eCause := E_DL_SpbCause.eCfgBad;                                                 (* 归因：组态非法 / Cause: config *)
ELSIF _bBatchActive AND (_bVacBad OR _bBrixBad) THEN
    IF NOT _bSafeLatch AND NOT _bFault THEN
        _bFaultReq := TRUE;
        _eCause := E_DL_SpbCause.eSigBad;                                             (* 归因：传感器非有限 / Cause: non-finite *)
    END_IF
ELSIF _bBatchActive AND _bTempLow THEN
    IF NOT _bSafeLatch AND NOT _bFault THEN
        _bFaultReq := TRUE;
        _eCause := E_DL_SpbCause.eTempLow;                                            (* 归因：过冷 / Cause: under-temperature *)
    END_IF
ELSIF _bBatchActive AND (_fS <= 0.0) AND (NOT _bFault) THEN
    IF NOT _bSafeLatch THEN
        _bFaultReq := TRUE;                                                           (* S 计算域外（哨兵 0.0）/ S sentinel zero *)
        _eCause := E_DL_SpbCause.eSigBad;                                             (* 归因：S 计算域外 / Cause: S out of domain *)
    END_IF
END_IF

(* —— 段 4：迁出链（复位沿 > 中止；作用域逐项声明 R311） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                                 (* 作用域①：清 E2 锁存 / Clear E2 *)
    IF _bSafeOk THEN
        _bSafeLatch := FALSE;                                                         (* 作用域②：安全恢复才清 E3（成因相关判据）/ Clear E3 only if safe *)
    END_IF
    _eCause := E_DL_SpbCause.eNone;                                                   (* 作用域③：清成因分级 / Clear cause and grade *)
    _eGrade := E_DL_SpbGrade.eOk;
    _fS := 0.0;                                                                       (* 作用域④：清过饱和度锁存 / Clear supersaturation *)
    _fBrixLatch := 0.0;
    _fBatchAccS := 0.0;                                                               (* 作用域⑤：清批次时长 / Clear batch time *)
    _nBatch := 0;                                                                     (* 作用域⑥：清批次计数（生产资料复位）/ Clear batch count *)
    IF NOT _bSafeLatch THEN
        IF (_ePhase = E_DL_SpbPhase.eFault) OR (_ePhase = E_DL_SpbPhase.eSafeStop) THEN
            _ePhase := E_DL_SpbPhase.eIdle;                                           (* 作用域⑦：故障相迁回待机 / Back to idle *)
        END_IF
    END_IF
ELSIF bStop AND (_ePhase <> E_DL_SpbPhase.eIdle) AND (_ePhase <> E_DL_SpbPhase.eSafeStop) THEN
    IF _ePhase = E_DL_SpbPhase.eFault THEN
        _bFault := FALSE;                                                             (* 中止清 E2（E3 只由复位清）/ Abort clears E2 only *)
        _eCause := E_DL_SpbCause.eNone;
        _eGrade := E_DL_SpbGrade.eOk;
    END_IF
    _fBatchAccS := 0.0;                                                               (* 批次时长作废 / Batch time void *)
    _ePhase := E_DL_SpbPhase.eIdle;                                                   (* 回待机 / Back to idle *)
END_IF

(* —— 段 5：主状态机（过饱和度 / 锤度为相迁移主判据，超时为保护） —— *)
CASE _ePhase OF
E_DL_SpbPhase.eIdle:
    IF rtStart.Q AND (NOT _bFault) AND (NOT _bSafeLatch) THEN
        _eGrade := E_DL_SpbGrade.eOk;                                                 (* 新批起算 / New batch *)
        _eCause := E_DL_SpbCause.eNone;
        _fBatchAccS := 0.0;
        _ePhase := E_DL_SpbPhase.eVacuum;                                             (* 入抽真空相 / To vacuum *)
    END_IF
E_DL_SpbPhase.eVacuum:
    IF _bVacOk THEN
        _ePhase := E_DL_SpbPhase.eFillSyrup;                                          (* 真空达标 -> 进糖浆 / Vacuum OK, fill *)
    ELSIF tonVacuum.Q THEN
        _eCause := E_DL_SpbCause.eVacTmo;                                             (* 归因：抽真空超时 / Cause: vacuum timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eFillSyrup:
    IF bSyrupReady THEN
        _ePhase := E_DL_SpbPhase.eConcentrate;                                        (* 进料到量 -> 浓缩 / Filled, concentrate *)
    ELSIF tonFill.Q THEN
        _eCause := E_DL_SpbCause.eFillTmo;                                            (* 归因：进料超时 / Cause: fill timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eConcentrate:
    IF (_fS > 0.0) AND (_fS >= fSSeed) THEN
        _ePhase := E_DL_SpbPhase.eSeed;                                               (* S 到投晶目标 -> 投晶 / S reached, seed *)
    ELSIF tonConcentrate.Q THEN
        _eCause := E_DL_SpbCause.eConcTmo;                                            (* 归因：浓缩超时（S 未达）/ Cause: concentrate timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eSeed:
    IF bSeedAdded THEN
        _ePhase := E_DL_SpbPhase.eGrow;                                               (* 晶种加入 -> 助晶 / Seeded, grow *)
    ELSIF tonSeed.Q THEN
        _eCause := E_DL_SpbCause.eSeedTmo;                                            (* 归因：投晶超时 / Cause: seeding timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eGrow:
    IF (_fS > 0.0) AND (_fS > fSWarn) THEN
        _eGrade := E_DL_SpbGrade.eYellow;                                             (* 过饱和偏高预警（黄，只记录不迁移）/ High-S warning, recorded only *)
    END_IF
    IF (_fS > 0.0) AND (_fS >= fSGrow) THEN
        _ePhase := E_DL_SpbPhase.eFinalBoil;                                          (* 养晶到位 -> 终浓 / Grown, final boil *)
    ELSIF tonGrow.Q THEN
        _eCause := E_DL_SpbCause.eGrowTmo;                                            (* 归因：助晶超时 / Cause: growing timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eFinalBoil:
    IF (NOT _bBrixBad) AND (fBrix >= fBrixDischarge) THEN
        _fBrixLatch := fBrix;                                                         (* 放糖锤度锁存 / Latch discharge Brix *)
        _ePhase := E_DL_SpbPhase.eBreakVac;                                           (* 锤度到量 -> 破真空 / Brix reached, break vacuum *)
    ELSIF tonFinalBoil.Q THEN
        _eCause := E_DL_SpbCause.eFinalTmo;                                           (* 归因：终浓超时（锤度未达）/ Cause: final boil timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eBreakVac:
    IF (NOT _bVacBad) AND (fVacKpa >= fVacGoodKpa) THEN
        _ePhase := E_DL_SpbPhase.eDischarge;                                          (* 真空破除到位 -> 放糖（本拍事件优先，R275）/ Vacuum broken, discharge *)
    ELSIF tonBreakVac.Q THEN
        _eCause := E_DL_SpbCause.eBreakTmo;                                           (* 归因：破真空超时 / Cause: break-vacuum timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eDischarge:
    IF bDischargeDone THEN
        _ePhase := E_DL_SpbPhase.eWash;                                               (* 放糖完成 -> 洗罐 / Discharged, wash *)
    ELSIF tonDischarge.Q THEN
        _eCause := E_DL_SpbCause.eDischTmo;                                           (* 归因：放糖超时 / Cause: discharge timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eWash:
    IF bWashDone THEN
        _ePhase := E_DL_SpbPhase.eDone;                                               (* 洗罐完成 -> 结算 / Washed, settle *)
    ELSIF tonWash.Q THEN
        _eCause := E_DL_SpbCause.eWashTmo;                                            (* 归因：洗罐超时 / Cause: wash timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_SpbPhase.eDone:
    _bDonePulse := TRUE;                                                              (* 单拍结算（段 1 预清）/ One-scan done *)
    _fMsTmp := _fBatchAccS * 1000.0;                                                  (* 秒 -> 毫秒 [ms] / Second to millisecond *)
    IF _fMsTmp > 2147483647.0 THEN
        _fMsTmp := 2147483647.0;                                                      (* 取整前实数上限兜底（R153）/ Real ceiling before truncation *)
    END_IF
    _tBatchLast := DINT_TO_TIME(LREAL_TO_DINT(_fMsTmp));                              (* 批次时长换算 / Batch duration *)
    _fBatchAccS := 0.0;                                                               (* 累加清零 / Clear accumulator *)
    IF _nBatch < DL_SPB_BATMAX THEN
        _nBatch := _nBatch + 1;                                                       (* 批次推进（容量载体判上限）/ Saturating batch count *)
    END_IF
    _ePhase := E_DL_SpbPhase.eIdle;                                                   (* 回待机 / Back to idle *)
E_DL_SpbPhase.eFault:
    bError := TRUE;                                                                   (* 故障相驻留（锁存回放）/ Fault residency *)
E_DL_SpbPhase.eSafeStop:
    bError := TRUE;                                                                   (* 安全相驻留（锁存回放）/ Safety residency *)
ELSE
    _eCause := E_DL_SpbCause.ePhaseBad;                                               (* 非法相位兜底 / Illegal phase fallback *)
    _bFaultReq := TRUE;                                                               (* 由段 6 落地 / Landed in segment 6 *)
END_CASE

(* —— 段 6：E2/E3 请求统一落地（分支内只写成因与请求，落地仅此一处，R187/R252） —— *)
IF _bSafeReq AND (NOT _bSafeLatch) THEN
    _bSafeLatch := TRUE;                                                              (* E3 锁存 / Latch E3 *)
    _eGrade := E_DL_SpbGrade.eBlack;                                                  (* 分级黑 / Grade black *)
    _ePhase := E_DL_SpbPhase.eSafeStop;                                               (* 同步迁相 / Migrate *)
    bError := TRUE;                                                                   (* 故障标志同段置位（R45 配对）/ Error pairing *)
ELSIF _bFaultReq AND (NOT _bSafeLatch) THEN
    _bFault := TRUE;                                                                  (* E2 锁存 / Latch E2 *)
    _eGrade := E_DL_SpbGrade.eRed;                                                    (* 分级红（批次降级）/ Grade red *)
    _ePhase := E_DL_SpbPhase.eFault;                                                  (* 同步迁相（R252）/ Migrate *)
    bError := TRUE;                                                                   (* 故障标志同段置位（R45 配对）/ Error pairing *)
END_IF

(* —— 段 7：统一出口（电平量由 _ePhase 派生，连续量做有限性防护 R273） —— *)
eState := _ePhase;                                                                    (* 相出口 / Phase outlet *)
eCause := _eCause;                                                                    (* 成因回放 / Cause playback *)
eGrade := _eGrade;                                                                    (* 分级出口 / Grade outlet *)
bError := bError OR _bFault OR _bSafeLatch;                                           (* 故障标志汇总 / Error summary *)
bSafeCut := _bSafeLatch;                                                              (* 安全断能指令 / Safety energy cut *)
bDone := _bDonePulse;                                                                 (* 单拍结算脉冲 / One-scan done *)
bBoilActive := (_ePhase = E_DL_SpbPhase.eConcentrate) OR (_ePhase = E_DL_SpbPhase.eGrow)
            OR (_ePhase = E_DL_SpbPhase.eFinalBoil);                                  (* 浓缩段指示 / Boiling indicator *)
nBatchCount := _nBatch;                                                               (* 批次计数出口 / Batch count outlet *)
IF (_fS <> _fS) OR ((_fS - _fS) <> (_fS - _fS)) THEN
    fSLast := 0.0;                                                                    (* 非有限不出口（保持哨兵）/ Non-finite not exported *)
ELSE
    fSLast := _fS;                                                                    (* 过饱和度出口 / Supersaturation outlet *)
END_IF
IF (_fBrixLatch <> _fBrixLatch) OR ((_fBrixLatch - _fBrixLatch) <> (_fBrixLatch - _fBrixLatch)) THEN
    fBrixLast := 0.0;                                                                 (* 非有限不出口 / Non-finite not exported *)
ELSE
    fBrixLast := _fBrixLatch;                                                         (* 锤度出口 / Brix outlet *)
END_IF
tBatchLast := _tBatchLast;                                                            (* 批次时长出口 [ms] / Batch duration outlet *)
END_FUNCTION_BLOCK
