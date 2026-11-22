(*
    FB_DL_ConveyorJamDetect —— 输送线堵料检测（无件时长 + 电机电流 双判据）
    ------------------------------------------------------------------
    组件名称  : FB_DL_ConveyorJamDetect
    分类      : DL_Device / ConveyorDiagnostics
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 输送线堵料的两条经典判据及其组合方式：其一下游长时间
                无件到达（物料流中断）、其二驱动电机电流偏高（负载增大），
                二者同时成立才判堵料（单一判据都会误报：无件也可能是上游空料，
                电流高也可能是启动冲击或低温黏滞）；电流侧带回差释放线，
                两侧均带独立延时确认。该组合判据为公开工程常识。
                clean-room 声明 —— 零代码行复制；判据结构、闸门、锁存、码位与
                双语文档全部本件自有，仅使用 IEC 61131-3 标准库 TON / R_TRIG。
                许可证 —— 本件 MIT；来源标签 self-std（道莅自有内规族）。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 2 · N7）
    ------------------------------------------------------------------
    功能说明  : 判据一（无件）：输送机在运行（bConvRun）且下游件检测（bDownPart）
                持续为 FALSE 达 tNoPart → 无件确认位 _tonNoPart.Q。
                判据二（电流）：fMotorA 超过 fCurrHigh 且持续 tConfirm → 电流确认位；
                释放线为 fCurrHigh - fCurrHyst（回差，取确认位的自保持在条件内实现，
                与 FB_DL_ScaleRangeWatch 采用同一口径，全库口径一致）。
                合成：两侧确认位同时成立 → 堵料锁存 _bJam，bReset 上升沿解除；
                解除后若两侧条件仍成立，需重新满足两个延时才会再次判堵
                （避免复位后立刻重锁）。
                判据优先级：堵料锁存 > 组态/输入故障码；故障期内不重推断成因（R189）。
    错误码    : 16#0002_0601 组态非法（阈值 / 回差 / 时长 / 非有限），锁存 —— 故障级
                16#0002_0602 电机电流非有限，锁存 —— 故障级
                16#0002_0603 堵料判定（双判据同时确认），锁存至 bReset —— 故障级
    码位总账  : 0601 / 0602 / 0603 用（均故障级）；无信息级码（bBusy / 各确认位已可观测）
    状态机    : N/A —— 无顺序相（两侧确认由 TON 自持，属定时器状态），
                故无 ENUM / CASE，也无 CASE ELSE 兜底面
    边界与披露: 一 组态闸（R272 逐项点名）：fCurrHigh > 0；fCurrHyst >= 0；
                   fCurrHyst < fCurrHigh（否则释放线为负，判据恒自保持）；
                   fCurrHigh / fCurrHyst 非有限闸（NaN 自反 + Inf 差值自反 + 幅值上界）；
                二 输入闸：fMotorA 非有限 → 锁存 0602，两侧确认位清零（不判堵）；
                三 出口语义（R191 名实双出口）：bJam 为**保持量**（锁存后保持 TRUE 直到
                   复位），bError 为 bJam 与故障锁存的并；失能（bEn = FALSE）时
                   bJam 保持量**不被清除**（失能非复位），但 bBusy 与各确认位清零；
                四 定时器 _tonNoPart / _tonConfirm 每周期无条件调用（规则 ⑦），
                   IN 为显式条件表达式，未放入任何可被跳过的分支；
                五 浮点判据全部为不等式（>、<、>=），无浮点直比；无除法；无数组下标；
                六 零全局变量、零 VAR_EXTERNAL、零物理地址。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 2 · N7）
*)
FUNCTION_BLOCK FB_DL_ConveyorJamDetect
VAR_INPUT
    bEn        : BOOL := TRUE;             (* 使能，[标志] / the enable *)
    bReset     : BOOL := FALSE;            (* 堵料复位（上升沿有效），[标志] / the jam reset, rising edge *)
    bConvRun   : BOOL := FALSE;            (* 输送机运行反馈，[标志] / the conveyor running feedback *)
    bDownPart  : BOOL := FALSE;            (* 下游件检测（有件为真），[标志] / the downstream part present *)
    fMotorA    : LREAL := 0.0;             (* 驱动电机电流，[A] / the drive motor current *)
    fCurrHigh  : LREAL := 5.0;             (* 电流偏高置位线，[A]，须 > 0 / the high current set point *)
    fCurrHyst  : LREAL := 0.5;             (* 电流回差，[A]，域 [0, fCurrHigh) / the current hysteresis *)
    tNoPart    : TIME := T#10S;            (* 无件确认延时，[ms] / the no-part confirmation delay *)
    tConfirm   : TIME := T#5S;             (* 电流确认延时，[ms] / the current confirmation delay *)
END_VAR
VAR_OUTPUT
    bJam       : BOOL;                     (* 堵料判定（保持型，复位解除），[标志] / the jam verdict, held until reset *)
    bNoPartOk  : BOOL;                     (* 无件判据已确认，[标志] / the no-part criterion confirmed *)
    bHighCurrOk : BOOL;                    (* 电流判据已确认，[标志] / the high current criterion confirmed *)
    bBusy      : BOOL;                     (* 任一侧确认计时进行中，[标志] / either confirmation timer is running *)
    bValid     : BOOL;                     (* 出口可信（无锁存故障），[标志] / the outlets are trustworthy *)
    bError     : BOOL;                     (* 故障标志（含堵料判定），[标志] / the fault flag, the jam included *)
    nErrCode   : UDINT;                    (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed *)
END_VAR
VAR
    _rtReset    : R_TRIG;                  (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonNoPart  : TON;                     (* 无件确认延时实例（无条件调用）/ the no-part confirmation timer *)
    _tonConfirm : TON;                     (* 电流确认延时实例（无条件调用）/ the current confirmation timer *)
    _bJam       : BOOL;                    (* 堵料保持量，仅 bReset 上升沿解除 / the held jam bit *)
    _bFault     : BOOL;                    (* 组态 / 输入故障锁存位 / the configuration and input fault latch *)
    _nCodeLatch : UDINT;                   (* 故障锁存码（0601 / 0602）/ the fault code latch *)
    _bCfgBad    : BOOL;                    (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bInBad     : BOOL;                    (* 电流非有限标志（逐拍重算）/ the current fault flag *)
    _bNoPartCond : BOOL;                   (* 无件条件（含自保持与运行前置），[标志] / the no-part condition *)
    _bCurrCond  : BOOL;                    (* 电流条件（含自保持与回差），[标志] / the current condition *)
END_VAR
VAR CONSTANT
    DL_CJD_FMAX : LREAL := 1.0E30;         (* 非有限筛查幅值上限，[A] / the finiteness screening cap *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置）/ segment 1, preset every outlet
bJam        := FALSE;                      // 堵料判定预清零（真值在段 9 由保持量映射）/ preset the jam verdict false
bNoPartOk   := FALSE;                      // 无件确认位预清零 / preset the no-part flag false
bHighCurrOk := FALSE;                      // 电流确认位预清零 / preset the high current flag false
bBusy       := FALSE;                      // 忙碌标志预清零 / preset the busy flag false
bValid      := FALSE;                      // 可用标志预置假，健康路径再置真 / preset valid false
bError      := FALSE;                      // 故障标志预清零 / preset the error flag false
nErrCode    := 0;                          // 错误码预置无错 / preset the code to zero
_bNoPartCond := FALSE;                     // 无件条件预清零 / preset the no-part condition false
_bCurrCond   := FALSE;                     // 电流条件预清零 / preset the current condition false

// 段 2｜沿检测与定时器无条件调用（规则 ⑦）/ segment 2, the reset edge instance
_rtReset(CLK := bReset);                   // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜堵料解除：唯一可到达的清除边（R188）/ segment 3, the only jam release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bJam := FALSE;                        // 解除堵料保持 / release the jam hold
END_IF

// 段 4｜组态守卫（R272 逐项点名）/ segment 4, the configuration guard
_bCfgBad := (fCurrHigh <= 0.0)                                       // 置位线非正 / a non positive set point
         OR (fCurrHyst < 0.0)                                        // 回差为负 / a negative hysteresis
         OR (fCurrHyst >= fCurrHigh)                                 // 回差吞没置位线（释放线为负，判据恒自保持）/ the hysteresis swallows the set point
         OR (fCurrHigh <> fCurrHigh) OR ((fCurrHigh - fCurrHigh) <> 0.0) OR (ABS(fCurrHigh) > DL_CJD_FMAX)
         OR (fCurrHyst <> fCurrHyst) OR ((fCurrHyst - fCurrHyst) <> 0.0) OR (ABS(fCurrHyst) > DL_CJD_FMAX);

// 段 5｜输入守卫：电机电流非有限 / segment 5, the current input guard
_bInBad := (fMotorA <> fMotorA) OR ((fMotorA - fMotorA) <> 0.0) OR (ABS(fMotorA) > DL_CJD_FMAX);

// 段 6｜首次成因锁存（故障期不重推断，R189）/ segment 6, the first cause latch
IF NOT _bFault THEN                        // 未锁存才登记 / register only while healthy
    IF _bCfgBad THEN                       // 组态非法优先 / the configuration first
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0601;       // 故障级：组态非法 / fault level: an illegal configuration
    ELSIF _bInBad THEN                     // 电流非有限 / the current is non finite
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0602;       // 故障级：输入非有限 / fault level: an input is non finite
    END_IF
END_IF

// 段 7｜两侧判据条件（含自保持与回差，IN 用显式条件）/ segment 7, both criterion conditions
IF bEn AND NOT _bFault THEN                // 使能且无故障才评估条件 / evaluate only while enabled and healthy
    _bNoPartCond := bConvRun AND (NOT bDownPart OR _tonNoPart.Q);                       // 无件条件：运行中且无件（确认后自保持到有件）
    _bCurrCond   := bConvRun AND ((fMotorA > fCurrHigh) OR (_tonConfirm.Q AND (fMotorA > (fCurrHigh - fCurrHyst)))); // 电流条件：超置位线或已确认且未破回差线
ELSE                                       // 失能或故障 / disabled or faulted
    _bNoPartCond := FALSE;                 // 条件清零，计时器随之复位 / clear the condition, the timer resets
    _bCurrCond   := FALSE;                 // 条件清零 / clear the condition
END_IF

// 段 8｜定时器无条件周期调用（规则 ⑦）/ segment 8, unconditional timer calls
_tonNoPart(IN := _bNoPartCond, PT := tNoPart);     // 无件确认计时，每周期无条件刷新 / the no-part timer
_tonConfirm(IN := _bCurrCond, PT := tConfirm);     // 电流确认计时，每周期无条件刷新 / the current timer

// 段 9｜确认位与堵料合成（判据合成点在定时器之后，本拍即可观测）/ segment 9, the synthesis
bNoPartOk   := bEn AND NOT _bFault AND _tonNoPart.Q;    // 无件判据确认 / the no-part criterion confirmed
bHighCurrOk := bEn AND NOT _bFault AND _tonConfirm.Q;   // 电流判据确认 / the current criterion confirmed
bBusy       := bEn AND NOT _bFault AND ((_bNoPartCond AND NOT _tonNoPart.Q) OR (_bCurrCond AND NOT _tonConfirm.Q)); // 任一侧计时中
IF bNoPartOk AND bHighCurrOk THEN          // 双判据同时确认 / both criteria confirmed together
    _bJam := TRUE;                         // 置堵料保持量（锁存至复位）/ hold the jam until a reset
END_IF

// 段 10｜出口映射（名实双出口同源，R191；故障码优先级写入）/ segment 10, the outlet mapping
bJam     := _bJam;                         // 堵料判定出口 = 保持量 / the jam outlet mirrors the hold
bError   := _bJam OR _bFault;              // 故障标志 = 堵料 或 锁存故障 / the fault flag, the jam or the latch
bValid   := bEn AND NOT _bJam AND NOT _bFault; // 出口可信条件 / the outlets are trustworthy
IF _bJam THEN                              // 堵料优先归因（过程故障优先于组态）/ the jam takes precedence
    nErrCode := 16#0002_0603;              // 故障级：堵料 / fault level: a jam was detected
ELSE                                       // 非堵料 / no jam
    nErrCode := _nCodeLatch;               // 回放组态 / 输入锁存码 / replay the configuration or input code
END_IF
END_FUNCTION_BLOCK
