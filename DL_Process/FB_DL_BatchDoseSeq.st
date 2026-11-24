(*
    FB_DL_BatchDoseSeq —— 批次定量给料顺控（预给/快给/慢给/落料/校验 五相）
    ------------------------------------------------------------------
    组件名称  : FB_DL_BatchDoseSeq
    分类      : DL_Process / Batching
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— ISA-88（ANSI/ISA-88.00.01）批次控制模型的
                「单元配方 / 相逻辑 / 相超时 / 批次判定」分层思想，以及定量给料
                行业通行的三段给料法（快给料逼近 + 慢给料精给 + 落料补偿）。
                本件只借鉴**相划分与判定顺序**这两项公开语义。
                clean-room 声明 —— 零代码行复制；状态机为本件自有 ENUM + CASE，
                定时仅用 IEC 61131-3 标准库 TON，沿检测仅用标准库 R_TRIG。
                许可证 —— 本件 MIT；来源标签 isa88 指标准术语与模型，
                标准文本不属代码，无许可继承关系。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 1 · N4）
    ------------------------------------------------------------------
    功能说明  : 单批次定量给料顺控。相序：
                eIdle 待机 → ePreDose 预给料（预给料阀开，到 fPreW 止）
                → eFastDose 快给料（快给料阀开，到 fFastW 止）
                → eSlowDose 慢给料（慢给料阀开，到 fTarget - fFreeFall 止）
                → eSettle 落料（全阀关，等 tSettle 让空中料落下）
                → eCheck 校验（净重对 fTarget ± 公差带判定）
                → eComplete 完成（保持，等下一次 bStart）。
                超时归因唯一（R190）：预给 / 快给 / 慢给 / 落料四相各持独立码
                0303 / 0304 / 0305 / 0306，绝不共用同一枚举或同一码值。
                定时器设计：单实例 _tonPhase，PT 由当前相在段 4 以 IF/ELSIF 链
                逐相选择（含 ELSE 缺省），**每周期无条件调用**（规则 ⑦），
                故选相不依赖任何可能被跳过的分支；落料相的正常出口也复用该
                实例的 Q（PT = tSettle），故落料相不存在「正常完成」与「超时」
                两种语义，只有「到时间进入校验」一种。
                相内比较全部用 >= 的闭区间口径，不用浮点相等（规则 ④）。
    错误码    : 16#0002_0301 组态非法（阈值不单调 / 负公差 / 非有限），清锁存后回 eIdle —— 故障级
                16#0002_0302 称重值非有限，锁存并停料 —— 故障级
                16#0002_0303 预给料相超时 —— 故障级
                16#0002_0304 快给料相超时 —— 故障级
                16#0002_0305 慢给料相超时 —— 故障级
                16#0002_0306 落料相超时 —— 故障级
                16#0002_0307 欠重（净重低于 fTarget - fTolNeg）—— 故障级
                16#0002_0308 超重（净重高于 fTarget + fTolPos）—— 故障级
                16#0002_0309 非法相枚举值（CASE ELSE 兜底）—— 故障级
                16#0002_0310 启动被拒（称斗未回零，fWeight 超过 fZeroTol）—— 信息级，不置 bError
    码位总账  : 0301 / 0302 / 0303 / 0304 / 0305 / 0306 / 0307 / 0308 / 0309 用（均故障级）
                0310 用（信息级，bError 恒 FALSE）
    状态机    : ENUM E_DL_BdsPhase 八态，CASE 全覆盖 + ELSE 兜底（回 eFault 并置 0309）。
                迁移表见功能说明；bAbort 任意相 → eIdle（操作态，不发码）；
                bReset 上升沿：解锁存 → eIdle（仅此一条可到达的解除边，R188）。
    边界与披露: 一 组态判据逐项点名（R272）：fTarget / fPreW / fFastW / fFreeFall /
                   fTolNeg / fTolPos 全部纳入非有限闸，并校验单调链
                   0 < fPreW < fFastW < (fTarget - fFreeFall) 与 fFreeFall < fTarget、
                   两侧公差 >= 0；任一不满足即 0301 并锁存，**不落任何阈值比较**；
                二 称重输入非有限即锁存 0302，全部给料出口立即关断（失效安全方向）；
                三 失能语义：本件无 bEn 引脚，停机由 bAbort 承担 —— bAbort 为电平
                   有效，任意拍为 TRUE 即回 eIdle 且输出全清零，不发码（操作态）；
                四 出口语义（R191 名实双出口）：bUnder / bOver 为校验相判定结果位，
                   同时映射到故障码 0307 / 0308 并锁存；eComplete 为完成相标志，
                   完成不算故障，bError 恒 FALSE；
                五 bBusy 定义：给料 / 落料 / 校验三区间（真正占用设备的时间窗）；
                   bValid 定义：出口可信（未处在锁存故障相）；
                六 定时器 _tonPhase 与沿实例 _rtStart / _rtReset 均无条件周期调用；
                七 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标、无除法。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 1 · N4）
*)
TYPE E_DL_BdsPhase :
(
    eIdle     := 0,   (* 待机，等待启动 / idle, waiting for a start *)
    ePreDose  := 10,  (* 预给料相（大流量阀开）/ the pre-dose phase, the coarse valve open *)
    eFastDose := 20,  (* 快给料相（快给料阀开）/ the fast-dose phase, the fast valve open *)
    eSlowDose := 30,  (* 慢给料相（慢给料阀开）/ the slow-dose phase, the fine valve open *)
    eSettle   := 40,  (* 落料相（全阀关，等空中料落下）/ the settling phase, all valves closed *)
    eCheck    := 50,  (* 校验相（净重对公差带判定）/ the check phase, the net weight against the tolerance *)
    eComplete := 60,  (* 完成相（保持到下次启动）/ the complete phase, held until the next start *)
    eFault    := 70   (* 故障相（锁存待复位）/ the fault phase, latched for a reset *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BatchDoseSeq
VAR_INPUT
    bStart    : BOOL := FALSE;             (* 启动命令（上升沿有效），[标志] / the start command, rising edge effective *)
    bAbort    : BOOL := FALSE;             (* 中止命令（电平有效），[标志] / the abort command, level effective *)
    bReset    : BOOL := FALSE;             (* 故障复位（上升沿有效），[标志] / the fault reset, rising edge effective *)
    fWeight   : LREAL := 0.0;              (* 称斗净重实时值，[kg] / the live net weight of the weigh hopper *)
    fTarget   : LREAL := 25.0;             (* 批次目标净重，[kg]，须 > 0 / the batch target weight, must be positive *)
    fPreW     : LREAL := 5.0;              (* 预给料结束重量点，[kg]，须 < fFastW / the pre-dose hand-over weight *)
    fFastW    : LREAL := 20.0;             (* 快给料结束重量点，[kg]，须 < fTarget - fFreeFall / the fast-dose hand-over weight *)
    fFreeFall : LREAL := 1.0;              (* 慢给料提前关断量（空中落差），[kg]，须 < fTarget / the in-flight cut-off weight *)
    fTolNeg   : LREAL := 0.2;              (* 允许负偏差，[kg]，须 >= 0 / the permitted negative deviation *)
    fTolPos   : LREAL := 0.2;              (* 允许正偏差，[kg]，须 >= 0 / the permitted positive deviation *)
    fZeroTol  : LREAL := 0.1;              (* 称斗空判定容差，[kg]，须 >= 0 / the empty-hopper tolerance *)
    tPre      : TIME := T#20S;             (* 预给料相超时，[ms] / the pre-dose phase timeout *)
    tFast     : TIME := T#30S;             (* 快给料相超时，[ms] / the fast-dose phase timeout *)
    tSlow     : TIME := T#30S;             (* 慢给料相超时，[ms] / the slow-dose phase timeout *)
    tSettle   : TIME := T#3S;              (* 落料稳定时间，[ms] / the settling duration *)
END_VAR
VAR_OUTPUT
    ePhase     : E_DL_BdsPhase := E_DL_BdsPhase.eIdle; (* 相状态出口，[相] / the phase outlet *)
    bPreOutlet : BOOL;                     (* 预给料阀 / 大流量出口命令，[标志] / the pre-dose outlet command *)
    bFastOutlet: BOOL;                     (* 快给料阀出口命令，[标志] / the fast-dose outlet command *)
    bSlowOutlet: BOOL;                     (* 慢给料阀出口命令，[标志] / the slow-dose outlet command *)
    bRunning   : BOOL;                     (* 批次进行中，[标志] / the batch is in progress *)
    bComplete  : BOOL;                     (* 批次完成（校验相通过后置位），[标志] / the batch completed *)
    bUnder     : BOOL;                     (* 欠重判定结果位，[标志] / the underweight verdict *)
    bOver      : BOOL;                     (* 超重判定结果位，[标志] / the overweight verdict *)
    fDeviation : LREAL;                    (* 实际偏差 fWeight - fTarget，[kg] / the actual deviation *)
    bBusy      : BOOL;                     (* 设备占用中（给料 / 落料 / 校验），[标志] / the equipment is occupied *)
    bValid     : BOOL;                     (* 出口可信（非锁存故障相），[标志] / the outlets are trustworthy *)
    bError     : BOOL;                     (* 故障标志，锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode   : UDINT;                    (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed from the latch *)
END_VAR
VAR
    _rtStart     : R_TRIG;                 (* 启动上升沿实例（无条件调用）/ the start rising edge instance *)
    _rtReset     : R_TRIG;                 (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonPhase    : TON;                    (* 相计时 / 落料计时实例（无条件调用）/ the phase and settle timer *)
    _ePhase      : E_DL_BdsPhase := E_DL_BdsPhase.eIdle; (* 相状态寄存器，[相] / the internal phase register *)
    _bFault      : BOOL;                   (* 故障锁存位，仅 bReset 上升沿解除 / the latched fault bit *)
    _nCodeLatch  : UDINT;                  (* 锁存成因码，故障期回放 / the latched cause code, replayed *)
    _bCfgBad     : BOOL;                   (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bInBad      : BOOL;                   (* 称重非有限标志（逐拍重算）/ the weight fault flag *)
    _bTimerIn    : BOOL;                   (* 相计时器 IN 条件（显式条件，段 4 计算）/ the timer IN condition *)
    _tPhasePt    : TIME;                   (* 相计时器 PT 当前值（逐相选择）/ the timer PT for the current phase *)
    _bStartOk    : BOOL;                   (* 启动前置条件成立（称斗已空）/ the start precondition holds *)
    _fSlowCut    : LREAL;                  (* 慢给料关断重量点 = fTarget - fFreeFall，[kg] / the slow-dose cut-off weight *)
    _fDev        : LREAL;                  (* 偏差中间量，[kg] / the deviation temporary *)
END_VAR
VAR CONSTANT
    DL_BDS_FMAX  : LREAL := 1.0E30;        (* 非有限筛查幅值上限，[kg] / the finiteness screening cap *)
    DL_BDS_UNDER : UDINT := 16#0002_0307;  (* 欠重码字面量（CASE 内引用，避免魔数）/ the underweight literal *)
    DL_BDS_OVER  : UDINT := 16#0002_0308;  (* 超重码字面量 / the overweight literal *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置 + 单拍位两段式的第一段）/ segment 1, preset every outlet
ePhase      := _ePhase;                    // 相出口先镜像寄存器 / mirror the phase register first
bPreOutlet  := FALSE;                      // 预给料出口预清零 / preset the pre-dose outlet false
bFastOutlet := FALSE;                      // 快给料出口预清零 / preset the fast-dose outlet false
bSlowOutlet := FALSE;                      // 慢给料出口预清零 / preset the slow-dose outlet false
bRunning    := FALSE;                      // 运行标志预清零 / preset the running flag false
bComplete   := FALSE;                      // 完成标志预清零 / preset the complete flag false
bUnder      := FALSE;                      // 欠重结果预清零 / preset the underweight verdict false
bOver       := FALSE;                      // 超重结果预清零 / preset the overweight verdict false
fDeviation  := 0.0;                        // 偏差预置零 / preset the deviation to zero
bBusy       := FALSE;                      // 占用标志预清零 / preset the busy flag false
bValid      := TRUE;                       // 可用标志预置真（故障相再清）/ preset valid true, cleared in the fault phase
bError      := FALSE;                      // 故障标志预清零 / preset the error flag false
nErrCode    := 0;                          // 错误码预置无错 / preset the code to zero
_bTimerIn   := FALSE;                      // 计时条件预清零 / preset the timer condition false
_tPhasePt   := tPre;                       // 计时 PT 预置缺省值 / preset the timer PT to the default

// 段 2｜沿检测实例无条件调用（规则 ⑦）/ segment 2, the edge instances, called unconditionally
_rtStart(CLK := bStart);                   // 启动沿，每周期无条件刷新 / the start edge, refreshed every scan
_rtReset(CLK := bReset);                   // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜复位解除：唯一可到达的锁存解除边（R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除故障锁存 / release the fault latch
    _nCodeLatch := 0;                      // 清锁存码 / clear the latched code
    _ePhase     := E_DL_BdsPhase.eIdle;    // 回待机相（安全相）/ back to the safe idle phase
END_IF

// 段 4｜组态守卫（阈值单调链 + 公差非负 + 全量非有限闸，R272）/ segment 4, the configuration guard
_fSlowCut := fTarget - fFreeFall;          // 慢给料关断点，供单调链复检 / the slow-dose cut-off point
_bCfgBad := (fTarget <= 0.0)                                             // 目标非正 / a non positive target
         OR (fFreeFall < 0.0)                                            // 落差为负 / a negative in-flight weight
         OR (fFreeFall >= fTarget)                                       // 落差吞没目标 / the in-flight swallows the target
         OR (fPreW <= 0.0)                                               // 预给料点非正 / a non positive pre-dose point
         OR (fFastW <= fPreW)                                            // 快给料点未高于预给料点 / the fast point not above the pre point
         OR (fFastW >= _fSlowCut)                                        // 快给料点越过慢给料关断点 / the fast point over the slow cut-off
         OR (fTolNeg < 0.0)                                              // 负公差为负 / a negative tolerance
         OR (fTolPos < 0.0)                                              // 正公差为负 / a negative tolerance
         OR (fZeroTol < 0.0)                                             // 空斗容差为负 / a negative empty tolerance
         OR (fTarget <> fTarget) OR ((fTarget - fTarget) <> 0.0) OR (ABS(fTarget) > DL_BDS_FMAX)
         OR (fPreW <> fPreW) OR ((fPreW - fPreW) <> 0.0) OR (ABS(fPreW) > DL_BDS_FMAX)
         OR (fFastW <> fFastW) OR ((fFastW - fFastW) <> 0.0) OR (ABS(fFastW) > DL_BDS_FMAX)
         OR (fFreeFall <> fFreeFall) OR ((fFreeFall - fFreeFall) <> 0.0) OR (ABS(fFreeFall) > DL_BDS_FMAX)
         OR (fTolNeg <> fTolNeg) OR ((fTolNeg - fTolNeg) <> 0.0) OR (ABS(fTolNeg) > DL_BDS_FMAX)
         OR (fTolPos <> fTolPos) OR ((fTolPos - fTolPos) <> 0.0) OR (ABS(fTolPos) > DL_BDS_FMAX)
         OR (fZeroTol <> fZeroTol) OR ((fZeroTol - fZeroTol) <> 0.0) OR (ABS(fZeroTol) > DL_BDS_FMAX);

// 段 5｜输入守卫：称重非有限 / segment 5, the weight input guard
_bInBad := (fWeight <> fWeight) OR ((fWeight - fWeight) <> 0.0) OR (ABS(fWeight) > DL_BDS_FMAX);

// 段 6｜首次成因锁存（故障期不重推断，回放锁存码，R189）/ segment 6, the first-cause latch
IF NOT _bFault THEN                        // 未锁存才登记成因 / a cause is registered only while not latched
    IF _bCfgBad THEN                       // 组态非法优先归因（根因）/ the configuration first, it is the root cause
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0301;       // 故障级：组态非法 / fault level: an illegal configuration
        _ePhase     := E_DL_BdsPhase.eFault; // 迁入故障相 / enter the fault phase
    ELSIF _bInBad THEN                     // 称重非有限 / the weight is non finite
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0302;       // 故障级：输入非有限 / fault level: the input is non finite
        _ePhase     := E_DL_BdsPhase.eFault; // 迁入故障相 / enter the fault phase
    END_IF
END_IF

// 段 7｜中止命令（操作态，不发码）：任意相回待机 / segment 7, the abort command, an operator state
IF bAbort AND NOT _bFault THEN             // 中止有效且无锁存故障 / an abort without a latched fault
    _ePhase := E_DL_BdsPhase.eIdle;        // 回待机（安全相）/ back to the safe idle phase
END_IF

// 段 8｜相计时器 PT 选择与无条件调用（规则 ⑦，选相不依赖可跳过分支）/ segment 8, the timer PT selection and the unconditional call
IF _ePhase = E_DL_BdsPhase.ePreDose THEN       // 预给料相 / the pre-dose phase
    _tPhasePt := tPre;                         // 预给料超时值 / the pre-dose timeout
    _bTimerIn := TRUE;                         // 相内计时有效 / the timer runs inside the phase
ELSIF _ePhase = E_DL_BdsPhase.eFastDose THEN   // 快给料相 / the fast-dose phase
    _tPhasePt := tFast;                        // 快给料超时值 / the fast-dose timeout
    _bTimerIn := TRUE;                         // 相内计时有效 / the timer runs
ELSIF _ePhase = E_DL_BdsPhase.eSlowDose THEN   // 慢给料相 / the slow-dose phase
    _tPhasePt := tSlow;                        // 慢给料超时值 / the slow-dose timeout
    _bTimerIn := TRUE;                         // 相内计时有效 / the timer runs
ELSIF _ePhase = E_DL_BdsPhase.eSettle THEN     // 落料相 / the settling phase
    _tPhasePt := tSettle;                      // 落料时长即其正常出口 / the settling duration is its normal exit
    _bTimerIn := TRUE;                         // 落料计时有效 / the timer runs
ELSE                                           // 其余相不参与计时（缺省分支，非状态机的 ELSE）/ the other phases do not time
    _tPhasePt := tPre;                         // 缺省 PT，保证 PT 恒有定义 / a default PT, always defined
    _bTimerIn := FALSE;                        // 计时条件清零 / the timer condition cleared
END_IF
_tonPhase(IN := _bTimerIn, PT := _tPhasePt);   // 每周期无条件调用 / called every scan without exception

// 段 9｜相状态机（ENUM + CASE + ELSE 兜底）/ segment 9, the phase machine
CASE _ePhase OF
    E_DL_BdsPhase.eIdle:                        // 待机相 / the idle phase
        bValid := TRUE;                         // 待机出口可信 / the idle outlets are trustworthy
        IF _rtStart.Q AND NOT _bFault THEN      // 启动沿且无锁存故障 / a start edge without a latched fault
            _bStartOk := (fWeight <= fZeroTol); // 前置条件：称斗已空 / the precondition, an empty hopper
            IF _bStartOk THEN                   // 前置成立 / the precondition holds
                _ePhase := E_DL_BdsPhase.ePreDose; // 进入预给料相 / enter the pre-dose phase
            ELSE                                // 称斗有残料 / the hopper is not empty
                nErrCode := 16#0002_0310;       // 信息级：启动被拒（不置 bError，R45）/ info level: the start is refused
                _ePhase  := E_DL_BdsPhase.eIdle; // 保持待机 / stay idle
            END_IF
        END_IF
    E_DL_BdsPhase.ePreDose:                     // 预给料相 / the pre-dose phase
        bRunning   := TRUE;                     // 批次进行中 / the batch runs
        bBusy      := TRUE;                     // 设备占用 / the equipment is occupied
        bPreOutlet := TRUE;                     // 预给料阀开 / open the pre-dose outlet
        IF fWeight >= fPreW THEN                // 到达预给料结束重量 / the pre-dose hand-over weight reached
            _ePhase := E_DL_BdsPhase.eFastDose; // 进入快给料相 / enter the fast-dose phase
        ELSIF _tonPhase.Q THEN                  // 相超时（归因唯一 0303）/ the phase timed out
            _bFault     := TRUE;                // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_0303;        // 故障级：预给料超时 / fault level: the pre-dose timed out
            _ePhase     := E_DL_BdsPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_BdsPhase.eFastDose:                    // 快给料相 / the fast-dose phase
        bRunning    := TRUE;                    // 批次进行中 / the batch runs
        bBusy       := TRUE;                    // 设备占用 / occupied
        bFastOutlet := TRUE;                    // 快给料阀开 / open the fast-dose outlet
        IF fWeight >= fFastW THEN               // 到达快给料结束重量 / the fast-dose hand-over weight reached
            _ePhase := E_DL_BdsPhase.eSlowDose; // 进入慢给料相 / enter the slow-dose phase
        ELSIF _tonPhase.Q THEN                  // 相超时（归因唯一 0304）/ the phase timed out
            _bFault     := TRUE;                // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_0304;        // 故障级：快给料超时 / fault level: the fast-dose timed out
            _ePhase     := E_DL_BdsPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_BdsPhase.eSlowDose:                    // 慢给料相 / the slow-dose phase
        bRunning    := TRUE;                    // 批次进行中 / the batch runs
        bBusy       := TRUE;                    // 设备占用 / occupied
        bSlowOutlet := TRUE;                    // 慢给料阀开 / open the slow-dose outlet
        IF fWeight >= _fSlowCut THEN            // 到达提前关断点（含空落差补偿）/ the cut-off point reached
            _ePhase := E_DL_BdsPhase.eSettle;   // 进入落料相 / enter the settling phase
        ELSIF _tonPhase.Q THEN                  // 相超时（归因唯一 0305）/ the phase timed out
            _bFault     := TRUE;                // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_0305;        // 故障级：慢给料超时 / fault level: the slow-dose timed out
            _ePhase     := E_DL_BdsPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_BdsPhase.eSettle:                      // 落料相（全阀关）/ the settling phase, all outlets closed
        bRunning := TRUE;                       // 批次进行中 / the batch runs
        bBusy    := TRUE;                       // 设备占用 / occupied
        IF _tonPhase.Q THEN                     // 落料时长到（正常出口，非超时）/ the settling done, the normal exit
            _ePhase := E_DL_BdsPhase.eCheck;    // 进入校验相 / enter the check phase
        END_IF
    E_DL_BdsPhase.eCheck:                       // 校验相 / the check phase
        bRunning   := TRUE;                     // 批次进行中 / the batch runs
        bBusy      := TRUE;                     // 设备占用 / occupied
        _fDev      := fWeight - fTarget;        // 实际偏差 / the actual deviation
        fDeviation := _fDev;                    // 偏差出口 / the deviation outlet
        IF _fDev < (0.0 - fTolNeg) THEN         // 欠重（低于负公差）/ underweight
            bUnder      := TRUE;                // 欠重结果位 / the underweight verdict
            _bFault     := TRUE;                // 锁存故障 / latch the fault
            _nCodeLatch := DL_BDS_UNDER;        // 故障级：欠重 / fault level: underweight
            _ePhase     := E_DL_BdsPhase.eFault; // 迁入故障相 / enter the fault phase
        ELSIF _fDev > fTolPos THEN              // 超重（高于正公差）/ overweight
            bOver       := TRUE;                // 超重结果位 / the overweight verdict
            _bFault     := TRUE;                // 锁存故障 / latch the fault
            _nCodeLatch := DL_BDS_OVER;         // 故障级：超重 / fault level: overweight
            _ePhase     := E_DL_BdsPhase.eFault; // 迁入故障相 / enter the fault phase
        ELSE                                    // 落在公差带内 / inside the tolerance band
            _ePhase := E_DL_BdsPhase.eComplete; // 进入完成相 / enter the complete phase
        END_IF
    E_DL_BdsPhase.eComplete:                    // 完成相（保持）/ the complete phase, held
        bComplete := TRUE;                      // 完成标志 / the complete flag
        bValid    := TRUE;                      // 完成相出口可信 / the complete outlets are trustworthy
        IF _rtStart.Q AND (fWeight <= fZeroTol) THEN // 称斗已卸空且再次启动 / the hopper emptied and a start arrived
            _ePhase := E_DL_BdsPhase.ePreDose;  // 直接进入下一批预给料 / start the next batch
        END_IF
    E_DL_BdsPhase.eFault:                       // 故障相（锁存保持）/ the fault phase, latched
        bValid   := FALSE;                      // 出口不可信 / the outlets are not trustworthy
        bError   := TRUE;                       // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;                // 回放锁存码（不按当下输入重推断）/ replay the latched code
    ELSE                                        // 非法枚举兜底（回安全相 + 置码，规则 ⑥）/ the illegal enumeration guard
        _bFault     := TRUE;                    // 置锁存 / latch it
        _nCodeLatch := 16#0002_0309;            // 故障级：非法相枚举 / fault level: an illegal phase value
        _ePhase     := E_DL_BdsPhase.eFault;    // 回安全相（故障相）/ force the safe fault phase
        bValid      := FALSE;                   // 出口不可信 / the outlets are not trustworthy
        bError      := TRUE;                    // 故障标志置位（禁静默）/ raise the fault flag
        nErrCode    := _nCodeLatch;             // 回放锁存码 / replay the latched code
END_CASE

// 段 10｜相出口映射（名实双出口同源，R191）/ segment 10, the phase outlet mapping
ePhase := _ePhase;                          // 相出口 = 寄存器（单点写入，段 9 之后不再触碰）/ the phase outlet mirrors the register
END_FUNCTION_BLOCK
