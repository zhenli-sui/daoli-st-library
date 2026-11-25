(*
  Name: FB_DL_CoaterGapTrimSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 涂布间隙—面密度串级微调序：测厚稳定窗 → 算面密度相对偏差 → 点动间隙 → 稳定判定 →
           回到测厚（闭环迭代），偏差收敛到容差内即进换卷相并置完成位。
        2) 点动量算式采用「相对偏差 × 当前间隙」的比例律：面密度与湿膜厚度成正比，
           湿膜厚度与间隙成正比，故面密度相对偏差等于间隙相对偏差，
           修正量 Δgap = (实测 − 目标)/目标 × 当前间隙；该式量纲为 %/% × µm = µm，
           是无因次的相对量乘基准间隙，不需要额外的增益系数（增益已归一在比例律内部）。
        3) 每次点动量钳到 ±DL_JOG_MAX_UM，防止单次超大偏差把间隙一次拉穿；
           连续迭代次数受 DL_MAX_ITER 预算约束，超预算判「不收敛」故障而不是无限重试。
  边界条件：1) 非有限值闸：面密度实测、目标、间隙三路实值入参统一过
           NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；命中即判信号无效（_bMeasOk=FALSE），
           在测厚相升级为「测厚信号丢失」故障，绝不把 NaN 送进偏差除法（R19）。
        2) 分母零闸：ABS(fArealTarget) > DL_EPS 才允许算相对偏差（目标为 0 时相对偏差无定义），
           目标为 0 或非有限在待机相直接判组态非法，禁止进入测量相。
        3) 时间零闸：tSettleS <= T#0S 时稳定窗定时器立即置 Q（等价于不做稳定判定）；
           这是合法组态（调试用），语义在此声明；同时另设 tonSettleOv 监视窗兜底。
        4) 间隙工艺闸：fGapUm 必须为正（间隙为 0 表示辊面接触，属设备危险状态），
           非正判组态非法并禁止启动。
        5) 相超时说明：eCgtMeasure 由 tonMeas 定时（测厚稳定窗）+ 非有限闸双重把关；
           eCgtJog 由 tonJog 定时；eCgtSettle 由 tonSettle 定时，并有 tonSettleOv 越限兜底；
           eCgtRollChange 为稳态持留相（等操作员撤令换卷），不设超时，设了会周期性误报；
           eCgtIdle / eCgtFault 为稳态相，同样不设超时。整序另设 tonSeq 总超时兜底。
        6) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相；故障解除路径为
           (NOT xStart) AND (NOT xFault) AND 组态恢复，可达。
        7) FB 主体不使用 RETURN，统一单出口（跨平台可移植性）。
  量纲自证：fDevPct = (mg/cm2 − mg/cm2) / (mg/cm2) × 100 = 无因次 [%]；
           _fJogUm = ([%] / 100) × µm = µm，相对量乘基准间隙，量纲闭合；
           fGapCmdUm = µm + µm = µm，指令与实测间隙同量纲；tonXxx 的 PT 均为 [TIME]。
  码表 Error codes（本件格 0090_05xx，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0090_0501 故障级：组态非法（目标面密度/间隙/稳定时间越界或非有限）
    16#0090_0502 故障级：测厚信号丢失（面密度实测非有限）
    16#0090_0503 故障级：间隙微调不收敛（迭代次数超预算）
    16#0090_0504 故障级：稳定判定相超时（tonSettleOv 兜底命中）
    16#0090_0505 故障级：整序总超时
    16#0090_0506 故障级：外部故障输入 xFault
    16#0090_0507 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0090_0508 信息级：单次点动量已饱和（达到 DL_JOG_MAX_UM，非故障）

  修订历史 Revision :
    2026-11-25  v1.0.0  R90 首版
*)

TYPE E_DL_CgtState :
(
    eCgtIdle       := 0,    // 待机：等启动上升沿 / Idle, awaiting start edge
    eCgtMeasure    := 10,   // 测厚：等稳定窗 / Measuring, awaiting stability window
    eCgtCalcDev    := 20,   // 算偏差：判收敛与迭代预算 / Deviation evaluation
    eCgtJog        := 30,   // 点动间隙：施加修正量 / Gap jog, applying correction
    eCgtSettle     := 40,   // 稳定判定：等涂层稳定 / Settling, awaiting stabilisation
    eCgtRollChange := 50,   // 换卷：完成保持，等撤令 / Roll change, done held until release
    eCgtFault      := 90    // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoaterGapTrimSeq
VAR_INPUT
    xStart        : BOOL;    // 微调启动指令（上升沿有效）[bool] / Trim start command, edge triggered [bool]
    xFault        : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    fArealMeas    : REAL;    // 面密度实测值 [mg/cm2] / Measured areal loading [mg/cm2]
    fArealTarget  : REAL;    // 面密度目标值 [mg/cm2] / Target areal loading [mg/cm2]
    fGapUm        : REAL;    // 当前涂布间隙实测 [µm] / Current coating gap measurement [µm]
    tSettleS      : TIME;    // 稳定判定时长 [TIME] / Settling duration [TIME]
END_VAR
VAR_OUTPUT
    fGapCmdUm     : REAL;    // 间隙指令 [µm] / Gap command [µm]
    fDevPct       : REAL;    // 面密度相对偏差 [%] / Areal loading relative deviation [%]
    iIter         : INT;     // 已完成点动迭代次数 [-] / Completed jog iterations [-]
    xTrim         : BOOL;    // 正在微调（点动相）[bool] / Trimming active flag [bool]
    xDone         : BOOL;    // 微调完成保持位 [bool] / Trim complete held flag [bool]
    eState        : E_DL_CgtState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId        : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonMeas       : TON;     // 测厚稳定窗定时 [TIME] / Measurement stability timer
    tonJog        : TON;     // 点动执行定时 [TIME] / Jog execution timer
    tonSettle     : TON;     // 稳定判定定时 [TIME] / Settling timer
    tonSettleOv   : TON;     // 稳定相越限兜底定时 [TIME] / Settling overrun watchdog timer
    tonSeq        : TON;     // 整序总超时定时 [TIME] / Whole-sequence timeout timer
    rtStart       : R_TRIG;  // 启动上升沿检测 [bool] / Start rising edge detector
    _eState       : E_DL_CgtState := E_DL_CgtState.eCgtIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev   : E_DL_CgtState := E_DL_CgtState.eCgtIdle;   // 上一拍相位快照（周期末更新）
    _bMeasOk      : BOOL;    // 测量链路有效性聚合 [bool] / Measurement chain validity aggregate
    _bCfgBad      : BOOL;    // 组态非法聚合 [bool] / Configuration invalid aggregate
    _bActive      : BOOL;    // 序激活（中间四相）[bool] / Sequence active flag [bool]
    _fDevRawPct   : REAL;    // 未饱和的相对偏差 [%] / Raw relative deviation [%]
    _fJogRawUm    : REAL;    // 未饱和的点动量 [µm] / Raw jog amount [µm]
    _fJogClampUm  : REAL;    // 饱和钳制后的点动量 [µm] / Clamped jog amount [µm]
    _fGapCmdLat   : REAL := 200.0;    // 间隙指令锁存（跨相保持；上电初值取安全张开位 200 µm，防冷启动输出 0 触发辊面接触）[µm]
    _iIter        : INT;     // 迭代次数内部量 [-] / Iteration counter internal [-]
    _bFault       : BOOL;    // 故障锁存位 [bool] / Latched fault flag [bool]
    _uInfo        : UDINT;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault       : UDINT;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;      // 组态零闸阈值 [-] / Configuration zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT        : REAL := 100.0;       // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_TOL_PCT    : REAL := 1.0;         // 面密度合格容差 [%] / Areal loading tolerance [%]
    DL_JOG_MAX_UM : REAL := 20.0;        // 单次点动饱和上限 [µm] / Single jog saturation limit [µm]
    DL_MAX_ITER   : INT  := 10;          // 迭代次数预算 [-] / Iteration budget [-]
    DL_MEASURE_S  : TIME := T#2S;        // 测厚稳定窗 [TIME] / Measurement stability window [TIME]
    DL_JOG_S      : TIME := T#1S;        // 点动执行时长 [TIME] / Jog execution duration [TIME]
    DL_OVER_MARGIN: TIME := T#10S;       // 稳定相越限兜底裕量 [TIME] / Settling watchdog margin [TIME]
    DL_SEQ_MAX    : TIME := T#10M;       // 整序总超时上限 [TIME] / Whole-sequence timeout [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_iIter/_fGapCmdLat/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸（R19：三路实值入参全覆盖，NaN 不得进入偏差除法） —— *)
_bMeasOk := (fArealMeas > -DL_BIG AND fArealMeas < DL_BIG)
            AND (fArealTarget > -DL_BIG AND fArealTarget < DL_BIG)
            AND (fGapUm > -DL_BIG AND fGapUm < DL_BIG);

(* —— 段 2：组态零闸（R4：目标面密度是偏差分母；间隙必须为正；稳定时长必须为正） —— *)
_bCfgBad := (NOT _bMeasOk)
            OR (ABS(fArealTarget) <= DL_EPS)                // 目标面密度不得为零
            OR (fGapUm <= DL_EPS)                           // 间隙必须为正（零间隙 = 辊面接触）
            OR (tSettleS <= T#0S);                          // 稳定时长必须为正（TIME 无法为 NaN）

(* —— 段 3：偏差与点动量解算（每拍重算，供观测与点动相直接取用） —— *)
IF _bCfgBad THEN
    _fDevRawPct := 0.0;                                 // 组态坏则偏差不计算，置 0
    _fJogRawUm := 0.0;                                  // 点动量置 0
ELSE
    _fDevRawPct := (fArealMeas - fArealTarget) / fArealTarget * DL_PCT;   // 实测 − 目标 [%]
    _fJogRawUm := (_fDevRawPct / DL_PCT) * fGapUm;      // 相对偏差 × 间隙 = 修正量 [µm]
END_IF
_fJogClampUm := LIMIT(-DL_JOG_MAX_UM, _fJogRawUm, DL_JOG_MAX_UM);          // 单次点动钳制 [µm]
IF ABS(_fJogRawUm) > DL_JOG_MAX_UM THEN
    _uInfo := 16#0090_0508;                             // 信息级：点动量已饱和（非故障）
END_IF

(* —— 段 4：激活量与定时器无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
_bActive := (_eState = E_DL_CgtState.eCgtMeasure) OR (_eState = E_DL_CgtState.eCgtCalcDev)
            OR (_eState = E_DL_CgtState.eCgtJog) OR (_eState = E_DL_CgtState.eCgtSettle);
rtStart(CLK := xStart);                                                     // 启动上升沿，每拍必调
tonMeas(IN := (_eState = E_DL_CgtState.eCgtMeasure), PT := DL_MEASURE_S);   // 测厚稳定窗
tonJog(IN := (_eState = E_DL_CgtState.eCgtJog), PT := DL_JOG_S);            // 点动执行时长
tonSettle(IN := (_eState = E_DL_CgtState.eCgtSettle), PT := tSettleS);      // 稳定判定定时
tonSettleOv(IN := (_eState = E_DL_CgtState.eCgtSettle),
            PT := tSettleS + DL_OVER_MARGIN);                               // 稳定相越限兜底
tonSeq(IN := _bActive, PT := DL_SEQ_MAX);                                    // 整序总超时

(* —— 段 5：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0090_0506;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_CgtState.eCgtFault;
END_IF
IF (NOT _bMeasOk) AND (_bActive) AND (NOT _bFault) THEN
    _uFault := 16#0090_0502;                // 故障级：测厚信号丢失
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_CgtState.eCgtFault;
END_IF
IF tonSeq.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0090_0505;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_CgtState.eCgtFault;
END_IF
IF _bCfgBad AND (NOT _bFault) AND (_eState <> E_DL_CgtState.eCgtIdle) THEN
    _uFault := 16#0090_0501;                // 故障级：组态非法
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_CgtState.eCgtFault;
END_IF

(* —— 段 6：相位机（只做迁移；出口在段 8 单点映射） —— *)
CASE _eState OF

E_DL_CgtState.eCgtIdle:
    IF NOT xStart THEN
        ;                                   // 等启动，撤令状态保持 / Waiting for start
    ELSIF _bCfgBad THEN
        _uFault := 16#0090_0501;            // 故障级：组态非法（启动前置校验）
        _bFault := TRUE;
        _eState := E_DL_CgtState.eCgtFault;
    ELSIF rtStart.Q THEN
        _eState := E_DL_CgtState.eCgtMeasure;   // 新序开始：进测厚相（迭代预算在段 7 清零）
    END_IF

E_DL_CgtState.eCgtMeasure:
    IF NOT xStart THEN
        _eState := E_DL_CgtState.eCgtIdle;      // 撤令：回待机
    ELSIF tonMeas.Q THEN
        _eState := E_DL_CgtState.eCgtCalcDev;   // 稳定窗结束：进算偏差相
    END_IF

E_DL_CgtState.eCgtCalcDev:
    IF NOT xStart THEN
        _eState := E_DL_CgtState.eCgtIdle;
    ELSIF ABS(_fDevRawPct) <= DL_TOL_PCT THEN
        _eState := E_DL_CgtState.eCgtRollChange;    // 本拍合法事件（已收敛）优先（R275）
    ELSIF _iIter >= DL_MAX_ITER THEN
        _uFault := 16#0090_0503;            // 故障级：迭代超预算，不收敛
        _bFault := TRUE;
        _eState := E_DL_CgtState.eCgtFault;
    ELSE
        _eState := E_DL_CgtState.eCgtJog;   // 未收敛且预算内：进点动相
    END_IF

E_DL_CgtState.eCgtJog:
    IF NOT xStart THEN
        _eState := E_DL_CgtState.eCgtIdle;
    ELSIF tonJog.Q THEN
        _eState := E_DL_CgtState.eCgtSettle;    // 点动完成：进稳定判定相
    END_IF

E_DL_CgtState.eCgtSettle:
    IF NOT xStart THEN
        _eState := E_DL_CgtState.eCgtIdle;
    ELSIF tonSettle.Q THEN
        _eState := E_DL_CgtState.eCgtMeasure;   // 稳定：回测厚，闭环复测
    ELSIF tonSettleOv.Q THEN
        _uFault := 16#0090_0504;            // 故障级：稳定相越限兜底命中
        _bFault := TRUE;
        _eState := E_DL_CgtState.eCgtFault;
    END_IF

E_DL_CgtState.eCgtRollChange:
    IF xFault THEN
        _uFault := 16#0090_0506;            // 故障级：换卷相外部故障
        _bFault := TRUE;
        _eState := E_DL_CgtState.eCgtFault;
    ELSIF NOT xStart THEN
        _eState := E_DL_CgtState.eCgtIdle;  // 撤令：回待机，完成位在段 7 清
    END_IF

E_DL_CgtState.eCgtFault:
    IF (NOT xStart) AND (NOT xFault) AND (NOT _bCfgBad) THEN
        _bFault := FALSE;                   // 解除路径：撤令 + 外部故障消失 + 组态恢复（可达）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_CgtState.eCgtIdle;  // 回待机
    END_IF

ELSE
    _uFault := 16#0090_0507;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_CgtState.eCgtFault;     // 强制回故障相

END_CASE

(* —— 段 7：后置段（R23：迭代预算、间隙指令锁存、快照统一放在迁移判断之后） —— *)
IF (_eState = E_DL_CgtState.eCgtMeasure) AND (_eStatePrev = E_DL_CgtState.eCgtIdle) THEN
    _iIter := 0;                            // 新序开始：迭代预算清零（禁跨相重试预算不清零）
END_IF
IF (_eState = E_DL_CgtState.eCgtJog) AND (_eStatePrev = E_DL_CgtState.eCgtCalcDev) THEN
    _iIter := _iIter + 1;                   // 进入点动即消耗一次迭代预算
END_IF

IF _eState = E_DL_CgtState.eCgtJog THEN
    _fGapCmdLat := LIMIT(DL_EPS, fGapUm + _fJogClampUm, DL_BIG);   // 点动相：实测间隙 + 修正量
ELSIF (NOT _bActive) AND _bMeasOk AND (NOT _bCfgBad) THEN
    _fGapCmdLat := LIMIT(DL_EPS, fGapUm, DL_BIG);   // 非激活相：指令跟随实测（仅测量有效时）
ELSIF NOT _bActive THEN
    ;                                   // 测量无效/组态非法：保持上拍指令，不复制 NaN 实测值
END_IF

_eStatePrev := _eState;                     // 快照统一在周期末尾更新（R23）

(* —— 段 8：出口单点映射（名实同源；指令/标志由状态与锁存导出，不在多分支各写一遍） —— *)
fGapCmdUm := _fGapCmdLat;                                       // 间隙指令出口 [µm]
fDevPct := LIMIT(-DL_BIG, _fDevRawPct, DL_BIG);                 // 偏差出口（已闸非有限）
iIter := _iIter;                                                // 迭代次数出口
xTrim := (_eState = E_DL_CgtState.eCgtJog) AND (NOT _bFault);   // 微调中出口
xDone := (_eState = E_DL_CgtState.eCgtRollChange) AND (NOT _bFault);   // 完成位出口
eState := _eState;                                              // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
