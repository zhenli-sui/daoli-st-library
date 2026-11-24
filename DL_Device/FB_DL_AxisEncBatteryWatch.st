(*
    FB_DL_AxisEncBatteryWatch —— 绝对值编码器备用电池欠压监视与预警
    ------------------------------------------------------------------
    组件名称  : FB_DL_AxisEncBatteryWatch
    分类      : DL_Device / AxisHealth
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 设备级粗粒度监视（AOI 粒度族）的「双阈值分型 +
                确认延时 + 锁存预警」组织方式，以及 NE107 健康分级公开条款
                （fault → eMaintenanceReq，warn → eOutOfSpec）。
                本件只借鉴**组织方式与分级语义**，判据 / 阈值 / 码位 100% 自有。
                clean-room 声明 —— 零代码行复制（来源闭源，按最严口径零接触）；
                定时与沿检测仅用 IEC 61131-3 标准库 TON / R_TRIG。
                许可证 —— 本件 MIT；来源标签 t2-6-rockwell-aoi（次源
                t2-8-ne107）仅作语义参考，不包含其任何受版权保护的实现。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R71 构建轮 · 批 1 · 序号 3）
    ------------------------------------------------------------------
    功能说明  : 监视绝对值编码器备用电池电压 fBattV，双阈值迟滞判定：
                故障线 fFaultV（低于即电池将尽，断电将丢参考点）与预警线
                fWarnV（低于即建议更换），两线各带独立回差 fHystV 防临界抖振；
                越线须持续 tConfirm 才确认，确认后：
                预警线 → bWarn（实时位）+ bReplaceSoon（**锁存**建议更换位，
                电压回升不清除，必须 bReset 上升沿才解除 —— 电池已劣化属
                事实性结论，瞬时恢复不改判）；
                故障线 → bFault（锁存）+ 故障码。
                非有限电压（断线 / ADC 故障）→ **直接置 bFault 并锁存**
                （电池状态不明比欠压更危险，安全侧收紧，不等确认延时）。
                依赖声明：TYPE E_DL_Ne107Status（属主 I_DL_DeviceHealth.st，
                只引用不重声明，枚举全库唯一定义）；仅 Standard.library
                （TON / R_TRIG / ABS），零厂商方言。
                确认定时器 _tonWarn / _tonFault 每周期无条件调用（规则 ⑦），
                IN 为显式条件（含已确认自保持与回差释放线）。
    错误码    : 16#0002_3770 组态非法（阈值倒置 fWarnV <= fFaultV / 回差为负 /
                            回差吞没线间距 / 阈值非有限 / 幅值超域），锁存 —— 故障级
                16#0002_3771 电池电压非有限（断线 / ADC 故障），直接锁存 —— 故障级
                16#0002_3772 电池欠压越过故障线并经确认（断电将丢参考点），锁存
                            —— 故障级
                16#0002_3773 电池欠压越过预警线并经确认（建议更换）—— 信息级，
                            不置 bError（R45：预警不算故障）
                16#0002_3774 电压越出典型域 [0, 5] V（编码器电池典型域），趋势
                            参考 —— 信息级，不置 bError；不拦截照判（负电压亦
                            必然低于故障线，判定方向天然安全）
    码位总账  : 16#0002_3770 用 ｜ 16#0002_3771 用 ｜ 16#0002_3772 用 ｜
                16#0002_3773 用 ｜ 16#0002_3774 用
    状态机    : N/A —— 单相监视，无顺序状态机，无自有 ENUM / CASE 可写；
                两路确认计时由 TON 实例自持，属定时器状态而非顺序状态；
                健康出口复用既有枚举 E_DL_Ne107Status（只引用）
    边界与披露: 一 组态判据逐项点名（R272）：fWarnV / fFaultV / fHystV 全部
                   纳入非有限闸；阈值倒置（fWarnV <= fFaultV）拦截；
                   fHystV < 0 拦截；fHystV >= (fWarnV - fFaultV) 拦截（回差
                   吞没线间距时两线无迟滞带，判据恒真）；
                二 输入非有限 → 直接故障锁存（不走过闸判定集合，安全侧赋值
                   不引用本闸判定内的量，防自证循环）；
                三 失能（bEn = FALSE）语义写死（R303）：bWarn / bReplaceSoon /
                   bFault 输出全清零、bError 清零、码清零，但 _bFault /
                   _bWarnLatch 锁存位**不被失能清除**（失能是操作态，不是
                   复位），必须 bReset 上升沿才解除 —— 两者语义分离；
                四 定时器 _tonWarn / _tonFault 无论失能 / 故障 / 正常均在段 8
                   无条件调用，IN 为段 7 计算出的显式条件；
                五 阈值默认域标注：编码器备用电池典型域 0~5 V，fWarnV 默认
                   3.0 V / fFaultV 默认 2.7 V 仅为锂-二氧化锰扣式电池组的
                   常见参考值，**不构成工程承诺**，实际阈值以编码器手册为准；
                六 电压越域（0~5 V 外）只报信息级不拦截：判定方向与电压
                   单调性一致（越低越险），越域照判不产生危险侧偏差；
                七 锁存解除路径唯一：bReset 上升沿（R188，可到达、引脚可满足）；
                八 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标、无除法。
    分工声明  : FB_DL_BrakeWearAccum（磨损累计）、FB_DL_SpindleWarmupSeq（热机
                顺控）等运动健康件互不相干；本件只做编码器备用电池电压域，
                不消费轴状态、不下发轴指令（R31 运动家族高危区纪律）。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R71 构建轮 · 批 1 · 序号 3）
*)
FUNCTION_BLOCK FB_DL_AxisEncBatteryWatch
VAR_INPUT
    fBattV    : LREAL;                     (* 编码器备用电池电压，[V]，典型域 0..5 / the encoder backup battery voltage *)
    fWarnV    : LREAL := 3.0;              (* 预警阈值，[V]，须 > fFaultV（默认值为参考非承诺）/ the warn threshold, must exceed fFaultV *)
    fFaultV   : LREAL := 2.7;              (* 故障阈值，[V]，须 < fWarnV（默认值为参考非承诺）/ the fault threshold, must be under fWarnV *)
    fHystV    : LREAL := 0.1;              (* 迟滞回差带宽（两线共用独立回差量），[V]，域 [0, fWarnV - fFaultV) / the hysteresis band *)
    tConfirm  : TIME := T#2S;              (* 欠压确认延时，[ms]，须 >= T#0S / the undervoltage confirmation delay *)
    bEn       : BOOL := TRUE;              (* 使能，[标志]，FALSE 时出口清零（R303）/ the enable, FALSE clears the outlets *)
    bReset    : BOOL := FALSE;             (* 故障 / 预警复位，[标志]，上升沿唯一解除 / the reset, its rising edge is the only release *)
END_VAR
VAR_OUTPUT
    bWarn        : BOOL;                   (* 预警实时位（确认成立且未破回差线），[标志] / the live warn flag, confirmed and not released *)
    bFault       : BOOL;                   (* 故障锁存位（故障线确认或电压非有限），[标志] / the latched fault flag *)
    bReplaceSoon : BOOL;                   (* 建议更换锁存位（预警确认后保持至复位），[标志] / the latched replace-soon flag, held until reset *)
    eHealth      : E_DL_Ne107Status;       (* NE107 健康出口（fault → eMaintenanceReq，warn → eOutOfSpec）/ the NE 107 health outlet *)
    bValid       : BOOL;                   (* 出口可用，失能或锁存故障为 FALSE / the outlets usable *)
    bError       : BOOL;                   (* 故障标志，存在锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode     : UDINT;                  (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed from the latch *)
END_VAR
VAR
    _rtReset    : R_TRIG;                  (* 复位上升沿检测实例（无条件调用）/ the reset rising edge instance *)
    _tonWarn    : TON;                     (* 预警线确认延时实例（无条件调用）/ the warn line confirmation timer *)
    _tonFault   : TON;                     (* 故障线确认延时实例（无条件调用）/ the fault line confirmation timer *)
    _bFault     : BOOL;                    (* 故障锁存位，仅 bReset 上升沿解除 / the internal latched fault bit *)
    _bWarnLatch : BOOL;                    (* 建议更换锁存位，仅 bReset 上升沿解除 / the internal latched warn bit *)
    _nCodeLatch : UDINT;                   (* 锁存成因码，故障期回放 / the latched cause code, replayed while faulted *)
    _bCfgBad    : BOOL;                    (* 组态非法标志（逐拍重算，仅用于首次锁存）/ the configuration fault flag *)
    _bInBad     : BOOL;                    (* 电压非有限标志（逐拍重算）/ the input fault flag *)
    _bOutDom    : BOOL;                    (* 电压越典型域标志（逐拍重算，仅报信息级）/ the out-of-typical-domain flag *)
    _bRun       : BOOL;                    (* 运行许可 = 使能 且 无锁存故障 / the run permit *)
    _bWarnCond  : BOOL;                    (* 预警确认条件（含自保持与回差，送 TON）/ the warn confirmation condition *)
    _bFaultCond : BOOL;                    (* 故障确认条件（含自保持与回差，送 TON）/ the fault confirmation condition *)
END_VAR

// 段 1｜出口预置（统一出口预置，R256）/ segment 1, preset every outlet
bWarn        := FALSE;                     // 预警实时位预清零 / preset the live warn flag false
bFault       := FALSE;                     // 故障出口预清零 / preset the fault outlet false
bReplaceSoon := FALSE;                     // 建议更换出口预清零 / preset the replace-soon outlet false
eHealth      := E_DL_Ne107Status.eUnknown; // 健康出口预置未知（首拍语义）/ preset the health outlet to unknown
bValid       := FALSE;                     // 可用标志预清零 / preset the valid flag false
bError       := FALSE;                     // 故障标志预清零 / preset the error flag false
nErrCode     := 0;                         // 错误码预置无错 / preset the code to zero
_bWarnCond   := FALSE;                     // 预警条件预清零 / preset the warn condition false
_bFaultCond  := FALSE;                     // 故障条件预清零 / preset the fault condition false

// 段 2｜复位沿检测（无条件调用，规则 ⑦）/ segment 2, the reset edge instance, called unconditionally
_rtReset(CLK := bReset);                   // 每周期无条件刷新 / refreshed every scan without exception

// 段 3｜锁存解除：仅 bReset 上升沿，锁存码同步清零（唯一解除边，R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除故障锁存 / release the fault latch
    _bWarnLatch := FALSE;                  // 解除建议更换锁存 / release the replace-soon latch
    _nCodeLatch := 0;                      // 清锁存码（可到达的清除边）/ clear the latched code, a reachable clearing edge
END_IF

// 段 4｜组态守卫（边界一逐项点名，R272）/ segment 4, the configuration guard
_bCfgBad := (fWarnV <= fFaultV)                                          // 阈值倒置或重合（预警线必须高于故障线）/ the thresholds reversed or coincident
         OR (fHystV < 0.0)                                               // 回差为负 / a negative hysteresis
         OR (fHystV >= (fWarnV - fFaultV))                               // 回差吞没线间距 / the hysteresis swallows the line gap
         OR (fWarnV <> fWarnV) OR ((fWarnV - fWarnV) <> 0.0)             // 预警阈值非有限 / the warn threshold non finite
         OR (fFaultV <> fFaultV) OR ((fFaultV - fFaultV) <> 0.0)         // 故障阈值非有限 / the fault threshold non finite
         OR (fHystV <> fHystV) OR ((fHystV - fHystV) <> 0.0);            // 回差非有限 / the hysteresis non finite

// 段 5｜输入守卫：电压非有限即危险（状态不明 > 欠压，安全侧收紧）/ segment 5, the input guard
_bInBad := (fBattV <> fBattV) OR ((fBattV - fBattV) <> 0.0); // 电压非有限（NaN 自反判 + Inf 差值自反判，R79）/ the voltage non finite
_bOutDom := (fBattV < 0.0) OR (fBattV > 5.0);               // 电压越典型域 [0,5] V（信息级，不拦截照判）/ the voltage out of the typical domain

// 段 6｜首次成因锁存（故障期内不重推断，回放锁存码，R189）/ segment 6, the first-cause latch
IF NOT _bFault THEN                        // 未锁存时才有资格登记成因 / a cause is registered only while not latched
    IF _bCfgBad THEN                       // 组态非法（优先归因，组态是根因）/ an illegal configuration, the root cause first
        _bFault     := TRUE;               // 置故障锁存 / latch the fault
        _nCodeLatch := 16#0002_3770;       // 故障级：组态非法 / fault level: an illegal configuration
    ELSIF _bInBad THEN                     // 电压非有限（状态不明，直接锁存不等延时）/ the voltage non finite, latch at once
        _bFault     := TRUE;               // 置故障锁存 / latch the fault
        _nCodeLatch := 16#0002_3771;       // 故障级：电压非有限 / fault level: a non finite voltage
    END_IF
END_IF

// 段 7｜运行许可与确认条件计算（分支内不调用任何定时器）/ segment 7, the run permit and the conditions
_bRun := bEn AND NOT _bFault;              // 使能且无锁存故障 / enabled and not latched
IF _bRun THEN                              // 运行许可成立 / the run permit holds
    _bWarnCond  := (fBattV < fWarnV) OR (_tonWarn.Q AND NOT (fBattV > (fWarnV + fHystV)));  // 预警条件：破预警线，或已确认且未回升破回差线
    _bFaultCond := (fBattV < fFaultV) OR (_tonFault.Q AND NOT (fBattV > (fFaultV + fHystV))); // 故障条件：破故障线，或已确认且未回升破回差线
    IF _bFaultCond THEN                    // 故障线条件成立（过确认延时后锁存）/ the fault line condition holds
        IF NOT _bFault THEN                // 未锁存才登记 / register only while not latched
            IF _tonFault.Q THEN            // 故障线经确认延时 / the fault line confirmed
                _bFault     := TRUE;       // 置故障锁存 / latch the fault
                _nCodeLatch := 16#0002_3772; // 故障级：欠压越故障线 / fault level: under the fault line
            END_IF
        END_IF
    END_IF
    IF _bWarnCond AND _tonWarn.Q THEN      // 预警线经确认延时 / the warn line confirmed
        _bWarnLatch := TRUE;               // 建议更换锁存（复位才解除，边界三）/ latch the replace-soon flag
    END_IF
ELSE                                       // 失能或锁存故障 / disabled or latched
    _bWarnCond  := FALSE;                  // 条件清零，计时器随之复位 / clear the condition, the timer resets
    _bFaultCond := FALSE;                  // 条件清零 / clear the condition
END_IF

// 段 8｜定时器无条件周期调用（规则 ⑦，IN 为显式条件）/ segment 8, unconditional timer calls
_tonWarn(IN := _bWarnCond, PT := tConfirm);    // 预警确认计时，每周期无条件刷新 / the warn confirmation timer
_tonFault(IN := _bFaultCond, PT := tConfirm);  // 故障确认计时，每周期无条件刷新 / the fault confirmation timer

// 段 9｜出口映射（名实双出口同源，R191）/ segment 9, the outlet mapping
IF _bRun THEN                              // 运行许可成立（无锁存故障）/ the run permit holds, not latched
    bWarn  := _bWarnCond AND _tonWarn.Q;   // 预警实时位：运行中且确认完成 / the live warn flag, confirmed while running
    bFault := FALSE;                       // 无锁存故障，故障出口为假 / no latched fault, the outlet false
    bReplaceSoon := _bWarnLatch;           // 建议更换出口与锁存同源 / the replace-soon outlet shares its latch
    bValid := TRUE;                        // 出口可用 / the outlets usable
    IF bWarn THEN                          // 预警确认成立 / the warn confirmed
        nErrCode := 16#0002_3773;          // 信息级：建议更换（不置 bError，R45）/ info level: replace soon
        eHealth  := E_DL_Ne107Status.eOutOfSpec;   // 预警 → 超出规格 / warn, out of specification
    ELSE                                   // 无预警 / no warn
        eHealth := E_DL_Ne107Status.eOk;   // 正常 / ok
    END_IF
ELSE                                       // 失能或锁存故障（出口清零相）/ disabled or latched, the clearing phase
    IF NOT bEn THEN                        // 失能优先于故障归因（操作态，边界三）/ a disable takes precedence, an operator state
        bWarn   := FALSE;                  // 失能相出口清零（R303）/ zero the outlets while disabled
        bFault  := FALSE;                  // 出口清零（锁存保留）/ the outlet cleared, the latch kept
        bReplaceSoon := FALSE;             // 出口清零（锁存保留）/ the outlet cleared, the latch kept
        bError  := FALSE;                  // 失能不是故障 / a disabled block is not a fault
        nErrCode := 0;                     // 失能不发码 / no code while disabled
        eHealth := E_DL_Ne107Status.eCheckFunction; // 失能 → 功能检查（信号暂无效）/ disabled, function check
    ELSE                                   // 锁存故障相（失能优先级之上）/ the latched fault phase
        bFault  := TRUE;                   // 故障出口与锁存同源 / the fault outlet shares the latch
        bReplaceSoon := _bWarnLatch;       // 建议更换出口与锁存同源 / the replace-soon outlet shares its latch
        bWarn   := FALSE;                  // 故障相预警实时位清零（归并到故障出口）/ the live warn cleared in the fault phase
        bError  := TRUE;                   // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;           // 回放锁存码 / replay the latched code
        eHealth := E_DL_Ne107Status.eMaintenanceReq; // 故障 → 需要维护 / maintenance required
    END_IF
END_IF
IF _bRun AND (NOT _bFault) AND _bOutDom THEN // 运行中且无锁存故障且越典型域 / running, not latched, out of domain
    IF nErrCode = 0 THEN                   // 不覆盖更高优先级码（信息级让位）/ never overrides a higher priority code
        nErrCode := 16#0002_3774;          // 信息级：电压越典型域 / info level: out of the typical domain
    END_IF
END_IF
END_FUNCTION_BLOCK
