(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MeasureInputLatch
 * 所属子库 (Sublibrary) : DL_Motion ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-24
 * 码位     (Code Segment): 16#0005_21C0（DL_Motion 段内 21xx 子带）
 * 复杂度   (Complexity) : C3
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / ABS / REAL_TO_LREAL /
 *                         LREAL_TO_REAL），零厂商私有库
 * 开源溯源 (Provenance) : ThorstenBrach/SRCI_CLIENT_PLC / MC_MeasuringInputFB / MIT /
 *                         借鉴点：测量输入「布防—触发—锁存—读取」的相序与布防窗口超时语义
 *                         （未复制任何实现行，按 IEC 61131-3 重写为五相状态机 + 软件边沿锁存）
 * 功能描述 (Function)   : 探针测量输入锁存。收到布防命令（bArm 上升沿）后进入 eArmed，等探针原始
 *                         信号上升沿：若该沿落在有效窗口 [rWindowStartMm, rWindowEndMm] 内，
 *                         把当时的 rAxisPosMm 锁存为 rLatchPosMm 并置 bLatched；窗口外触发只
 *                         累加 iOutsideCnt 并继续等待（不清布防，避免一个毛刺废掉整次测量）。
 *                         锁存后经 tLatchHold 保持相把结果留在出口供上层读取，然后自动解除布防
 *                         回 eIdle，等下一轮 bArm 沿。
 *                         **边沿纪律（R79 教训）**：bArm 与 bProbeRaw 一律 R_TRIG 取上升沿。
 *                         电平布防会在同一 bArm 电平内反复重新布防，把后续毛刺重复锁存；电平
 *                         探针同理。两者都在 CASE 外无条件刷新（R7），CASE 内只读 .Q。
 *                         **布防超时兜底（R448/R449）**：eArmed 是唯一的外部事件等待相，若一直
 *                         无触发则相驻留无界，故用 tonArm（PT := tArmTimeout）兜底 → 故障级 51。
 *                         **bEnable = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         布防与锁存位撤销、bDone 归假、相位回 eIdle；rLatchPosMm 与两计数保留
 *                         （已发生的测量事实不撤回，仅由 bReset 沿清计数器）。
 * 接口     (Interface)  : 输入 bEnable / bReset（上升沿）/ bArm（上升沿有效）/ bProbeRaw（上升沿
 *                         有效）/ rAxisPosMm / rWindowStartMm / rWindowEndMm / tArmTimeout /
 *                         tLatchHold；输出 eState（E_DL_MeasureInputLatch_State）/ bArmed /
 *                         bLatched / bDone（锁存单拍）/ bError / iErrCode / rLatchPosMm /
 *                         iOutsideCnt / iEdgeCnt。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eArmed：bEnable 且 rtArm.Q（布防上升沿）且窗口合法且无锁存；拍 N 进入 /
 *      本拍行为：拒绝锁存与完成位，保留上次 rLatchPosMm 供读取 / 拍 N+1 转出至 eArmed。
 *   ② eArmed → eArmed（驻留）：rtProbe.Q 且该沿落在窗口外；拍 N 进入 / 本拍行为：iEdgeCnt+1、
 *      iOutsideCnt+1，拒绝锁存（毛刺不废测量）/ 拍 N+1 驻留继续等待。
 *   ③ eArmed → eLatched：rtProbe.Q 且 rAxisPosMm 落在 [窗口起点 − 容差, 窗口终点 + 容差]；
 *      拍 N 进入 / 本拍行为：iEdgeCnt+1、rLatchPosMm 写入本拍轴位置（本拍合法事件优先于超时，
 *      R275）/ 拍 N+1 转出至 eLatched。
 *   ④ eArmed → eIdle：bEnable = FALSE（进相前置条件消失，第二出口，R98）。
 *   ⑤ eArmed → eFault：tonArm.Q（布防窗口内无触发，故障级 51）。
 *   ⑥ eLatched → eHold：单拍置位；拍 N 进入 / 本拍行为：bLatched 与 bDone 置单拍、布防解除、
 *      拒收新沿 / 拍 N+1 转出至 eHold。
 *   ⑦ eHold → eIdle：tonHold.Q（保持到期，自动解除布防）；拍 N 进入 / 本拍行为：bLatched 归假、
 *      拒绝新锁存（须重新布防）/ 拍 N+1 转出至 eIdle。
 *   ⑧ eHold → eIdle：bEnable = FALSE（第二出口）。
 *   ⑨ 任意相 → eFault：窗口参数非法或非有限（52）；轴位置非有限（53）；非法枚举（99）。
 *      锁存后由段 7 段尾迁移闸迁相。
 *   ⑩ eFault → eIdle：bReset 上升沿；拍 N 进入 / 本拍行为：清锁存、错误码、布防与锁存位与
 *      两计数，**保留** rLatchPosMm / 拍 N+1 转出至 eIdle。出口穷举、不滞留故障态。
 * 边界     (Boundary)   : ① 两个 TON 与两个 R_TRIG 全部在 CASE 外无条件调用（R7）；TON 的 IN 均含
 *                            NOT .Q 自复位项（R188），禁靠外部沿清零。
 *                         ② 同拍双窗配比约束（R100）：tonArm（PT := _tArm）覆盖 eArmed 相，
 *                            tonHold（PT := _tHold）覆盖 eHold 相，两使能域互斥不相交，无竞态；
 *                            配置建议 tLatchHold ≤ tArmTimeout（读取保持不得长于布防等待，
 *                            否则上层会同时看到上一轮保持与本轮布防）。
 *                         ③ 组态域闸全覆盖（FB51-2）：三个浮点入参 rAxisPosMm / rWindowStartMm /
 *                            rWindowEndMm 全部逐项枚举；非有限判定用自反 x <> x 与差值自减
 *                            (x−x) <> (x−x) 双判，禁用近似阈值与 ABS(x−x) 形态（R4 / R79）。
 *                         ④ 窗口判据带容差：下沿 `_fPos >= (_fWinStart - 1.0E-6)`、上沿
 *                            `_fPos <= (_fWinEnd + 1.0E-6)`，禁 `=` / `<>` 判等（R4）。
 *                         ⑤ 窗口合法性闸（终点 > 起点）与轴位置非有限闸在整个运行期每拍生效，
 *                            不只在布防拍判定——运行中把窗口改反同样立即锁存（域闸不偷工）。
 *                         ⑥ 时间参数两级回退（FB32-3）：越域回默认常量（各自在有效域内），
 *                            故无需二级钳定；回退不置故障（不新增码位）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件按派单指定使用小整数码。信息级（永不置 bError）：无。
 *                         故障级（置 bError，锁存至 bReset 沿）：
 *                         51 = 布防窗口内无触发超时；反证：该场景下 bArmed 恒真、bLatched 恒假、
 *                              两计数不变，与「正在等探针」的输出组合完全同形，只能靠码区分。
 *                         52 = 窗口参数非法（终点 ≤ 起点，或窗口端点非有限）；反证：该场景
 *                              窗口判据退化为空集或全域，锁存位行为与「探针一直不来」同形，
 *                              且补救动作是改参数而非查探针，必须独立成码。
 *                         53 = 轴位置非有限（编码器失效或位置回读断链）；反证：与 52 的区别是
 *                              参数正确而回读崩塌，补救动作是查反馈而非改参数，须独立成码。
 *                         99 = 非法状态枚举值（ELSE 兜底）。
 * 分工声明 (Scope)      : 轴的实际位置回读与编码器健康监测归 DL_Motion 轴类件（本件只消费
 *                         rAxisPosMm）；探针硬件滤波（去抖 / 脉宽门限）归输入模块组态或硬件
 *                         滤波层（本件只做软件上升沿与窗口裁决）；采点数据的工艺解释与补偿
 *                         计算归上层测量应用件。本件只做**一次测量的布防—锁存—读取时序**。
 * 归属     (Ownership)  : E_DL_MeasureInputLatch_State 归属本文件（全库唯一定义，R264）。
 * 命名偏离 (Naming Ex.) : 本件按派单原文保留 r 前缀表示 REAL（rAxisPosMm / rWindowStartMm /
 *                         rWindowEndMm / rLatchPosMm），i 前缀表示 INT（iErrCode / iOutsideCnt /
 *                         iEdgeCnt）；内部计算升位为 LREAL 的 f 前缀。与规范 1.2 节 n 前缀存在
 *                         登记偏离，接口契约优先不改名。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q（探针为普通引脚，非物理
 *                         地址）｜ R3 ✓ 纯 IEC 61131-3（TON / R_TRIG / ABS / REAL_TO_LREAL /
 *                         LREAL_TO_REAL）｜ R4 ✓ 无除法 + 窗口判据带容差 + 自反/差值双判非有限
 *                         ｜ R5 ✓ 逐行同行中英双语注释 ｜ R6 ✓ 五态 ENUM + CASE + ELSE 兜底
 *                         ｜ R7 ✓ TON / R_TRIG 全在 CASE 外无条件调用 ｜ R8 ✓ 无 METHOD（全内联）
 *                         ｜ R10 ✓ 无构造式转换（仅标准转换函数）｜ R11 ✓ 声明全分号结尾
 *                         ｜ R12 ✓ ENUM 成员用 := ｜ R14 ✓ 无 PROPERTY ｜ R16 ✓ 不引用任何外部 FB/FC。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R81-B 首版
 * 验收向量 (Acceptance) :
 *   V1 窗口内正常锁存：rWindowStartMm=10.0、rWindowEndMm=20.0、tArmTimeout=T#2S、
 *      tLatchHold=T#200MS；bEnable=TRUE 后 bArm 起一沿 → eState=eArmed、bArmed=TRUE；
 *      轴到 15.0 时探针起沿 → rLatchPosMm=15.0、bLatched=TRUE、bDone 单拍、iEdgeCnt=1、
 *      iOutsideCnt=0；保持 200ms 后 eState=eIdle、bArmed=FALSE、bLatched=FALSE。
 *   V2 窗口外触发不废测量：轴到 5.0 时探针起沿 → iEdgeCnt=1、iOutsideCnt=1、eState 仍 eArmed、
 *      bLatched=FALSE；随后轴到 18.0 再起沿 → rLatchPosMm=18.0、iEdgeCnt=2、iOutsideCnt=1。
 *   V3 布防超时：bArm 起沿后探针永不来、tArmTimeout=T#1S → 1s 后 eState=eFault、iErrCode=51、
 *      bError=TRUE、bArmed=FALSE；bReset 上升沿 → eState=eIdle、bError=FALSE、iEdgeCnt 归零、
 *      rLatchPosMm 保持 18.0（不清）。
 *   V4 窗口倒置：rWindowStartMm=20.0、rWindowEndMm=10.0 → eState=eFault、iErrCode=52、
 *      bError=TRUE（无需等布防沿，运行期每拍生效）。
 *   V5 边沿纪律：bArm 保持 TRUE 电平不动、探针抖动三次 → 只锁存第一次有效沿（iEdgeCnt 按实际
 *      上升沿计），bDone 仅一拍；撤 bArm 再起才进入下一轮。
 *   V6 撤使能：eArmed 中 bEnable=FALSE → eState=eIdle、bArmed=FALSE、bError=FALSE、
 *      iEdgeCnt / iOutsideCnt 保持。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MeasureInputLatch_State（探针测量输入锁存相位；eFault 为安全相）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MeasureInputLatch_State :
(
    eIdle   := 0,     // 空闲：等布防命令上升沿 / Idle: waiting for the arm command rising edge
    eArmed  := 10,    // 布防相：等探针上升沿，窗口内锁存、窗口外继续等 / Armed: waiting for the probe edge, latch inside the window
    eLatched := 20,   // 锁存相：单拍置锁存与完成 / Latched: one-scan latch and completion
    eHold   := 30,    // 保持相：把结果留在出口，到期自动解除布防 / Hold: keeping the result readable until the hold expires
    eFault  := 90     // 故障安全相：锁存成因，布防与锁存全撤 / Fault safe phase: latched cause, arm and latch withdrawn
);
END_TYPE

FUNCTION_BLOCK FB_DL_MeasureInputLatch
VAR_INPUT
    bEnable       : BOOL := FALSE;      // 使能：FALSE 撤销布防与锁存并回空闲 / Enable, FALSE withdraws arm and latch and returns to idle
    bReset        : BOOL := FALSE;      // 复位（上升沿；清锁存/布防/两计数，不清上次锁存位置）/ Reset rising edge clearing latch, arm and counters but not the last latched position
    bArm          : BOOL := FALSE;      // 布防命令（上升沿有效）/ Arm command, rising edge only
    bProbeRaw     : BOOL := FALSE;      // 探针原始信号（上升沿有效）/ Raw probe signal, rising edge only
    rAxisPosMm    : REAL := 0.0;        // 轴当前位置回读 [mm] / Current axis position feedback
    rWindowStartMm : REAL := 0.0;       // 有效窗口起点，须 < 终点 [mm] / Valid window start, strictly below the end
    rWindowEndMm  : REAL := 100.0;      // 有效窗口终点，须 > 起点 [mm] / Valid window end, strictly above the start
    tArmTimeout   : TIME := T#5S;       // 布防等待上限，有效域 10ms..10min [s] / Arming wait limit, valid domain 10 ms through 10 min
    tLatchHold    : TIME := T#200MS;    // 锁存结果保持时长，有效域 10ms..10min [s] / Latch hold duration, valid domain 10 ms through 10 min
END_VAR
VAR_OUTPUT
    eState        : E_DL_MeasureInputLatch_State;   // 当前相位出口（段 8 单点映射）/ Current phase outlet mapped once at segment 8
    bArmed        : BOOL;               // 布防中（仅 eArmed 相为真）/ Armed, true only inside the eArmed phase
    bLatched      : BOOL;               // 锁存有效（eLatched 起至保持到期）/ Latch valid from eLatched until the hold expires
    bDone         : BOOL;               // 锁存完成单拍脉冲 / One-scan latch completion pulse
    bError        : BOOL;               // 故障锁存标志 / Fault latch flag
    iErrCode      : INT := 0;           // 错误码（故障期锁存回放，其余拍为 0）/ Error code, latched code replayed while in fault
    rLatchPosMm   : REAL := 0.0;        // 锁存位置（保留至下一次锁存，复位不清）[mm] / Latched position kept until the next latch and across resets
    iOutsideCnt   : INT := 0;           // 窗口外触发累计 [次] / Cumulative out-of-window trigger count
    iEdgeCnt      : INT := 0;           // 探针上升沿累计（含窗口外）[次] / Cumulative probe rising edges including out-of-window ones
END_VAR
VAR
    _eState       : E_DL_MeasureInputLatch_State := E_DL_MeasureInputLatch_State.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch  : BOOL := FALSE;      // 故障锁存位（仅 bReset 上升沿清除）/ Fault latch bit, cleared only by the bReset rising edge
    _iErrLatch    : INT := 0;           // 锁存故障码（故障期唯一回放源，FB33-1）/ Latched fault code, the only replay source during fault
    _iErrTmp      : INT := 0;           // 当拍故障首因中间量 / First fault cause of this scan
    _bFaultReq    : BOOL := FALSE;      // 当拍故障请求标志（段 7 统一锁存）/ Fault request of this scan latched at segment 7
    _bCfgOk       : BOOL := TRUE;       // 窗口与位置闸通过标志 / Window and position gate flag
    _bLatchedLatch : BOOL := FALSE;     // 锁存保持量（eLatched 置位，eHold 到期清）/ Latch holding bit set in eLatched and cleared when the hold expires
    _bDonePulse   : BOOL := FALSE;      // 完成内部单拍位（段 1 预置，段 8 映射）/ Internal one-scan done bit preset at segment 1
    _fPos         : LREAL := 0.0;       // 轴位置升位副本 [mm] / Promoted copy of the axis position
    _fWinStart    : LREAL := 0.0;       // 窗口起点升位副本 [mm] / Promoted copy of the window start
    _fWinEnd      : LREAL := 0.0;       // 窗口终点升位副本 [mm] / Promoted copy of the window end
    _fLatchPos    : LREAL := 0.0;       // 锁存位置保持量（升位）[mm] / Holding value of the latched position, promoted
    _iOutsideCnt  : INT := 0;           // 内部窗口外触发累计 [次] / Internal out-of-window trigger counter
    _iEdgeCnt     : INT := 0;           // 内部探针上升沿累计 [次] / Internal probe rising-edge counter
    _tArm         : TIME := T#5S;       // 布防等待上限钳定值（两级回退结果）[s] / Clamped arming limit after the two-level fallback
    _tHold        : TIME := T#200MS;    // 保持时长钳定值（两级回退结果）[s] / Clamped hold duration after the two-level fallback
    rtReset       : R_TRIG;             // bReset 边沿实例（段 5 无条件调用，R18）/ bReset edge instance called unconditionally
    rtArm         : R_TRIG;             // 布防命令边沿实例（段 5 无条件调用，防电平重复布防，R79）/ Arm edge instance preventing level re-arming
    rtProbe       : R_TRIG;             // 探针边沿实例（段 5 无条件调用，防毛刺电平抖动）/ Probe edge instance suppressing level chatter
    tonArm        : TON;                // 布防等待超时计时器（段 5 无条件调用）/ Arming timeout timer called unconditionally
    tonHold       : TON;                // 锁存结果保持计时器（段 5 无条件调用）/ Latch hold timer called unconditionally
END_VAR
VAR CONSTANT
    DL_MIL_ZERO      : LREAL := 0.0;                // 浮点零基准（作有限性判据的对照量）[-] / Float zero used as the finiteness reference
    DL_MIL_EPS       : LREAL := 1.0E-6;             // 位置比较容差，微米级 [mm] / Position comparison tolerance at the micrometre level
    DL_MIL_T_MIN     : TIME := T#10MS;              // 时间参数下限 [s] / Time parameter lower bound
    DL_MIL_T_MAX     : TIME := T#10M;               // 时间参数上限 [s] / Time parameter upper bound
    DL_MIL_ARM_DEF   : TIME := T#5S;                // 布防等待上限默认回退值（本身在域内）[s] / Default fallback arming limit, already inside the domain
    DL_MIL_HOLD_DEF  : TIME := T#200MS;             // 保持时长默认回退值（本身在域内）[s] / Default fallback hold duration, already inside the domain
    DL_MIL_ONE       : INT := 1;                    // 计数步进一 [次] / Counter step of one
END_VAR

(* —— 段 1：中间量预置（只清单拍标志与扫描量，不清锁存位 / 保持位置 / 两计数，FB32-1） —— *)
_iErrTmp    := 0;                          // 当拍故障首因复位 / Scan first fault cause reset
_bFaultReq  := FALSE;                      // 当拍故障请求复位 / Scan fault request reset
_bCfgOk     := TRUE;                       // 闸标志复位 / Gate flag reset
_bDonePulse := FALSE;                      // 完成单拍位预置（单拍路径唯一预置点，FB51-8）/ Done pulse preset, the single preset point

(* —— 段 2：REAL 入参升位（R10 标准转换，内部一律 LREAL 运算） —— *)
_fPos      := REAL_TO_LREAL(rAxisPosMm);        // 位置升位 / Position promoted
_fWinStart := REAL_TO_LREAL(rWindowStartMm);    // 窗口起点升位 / Window start promoted
_fWinEnd   := REAL_TO_LREAL(rWindowEndMm);      // 窗口终点升位 / Window end promoted

(* —— 段 3：时间参数两级回退（越域回默认常量，默认常量在域内故无需二级钳定，FB32-3） —— *)
IF (tArmTimeout < DL_MIL_T_MIN) OR (tArmTimeout > DL_MIL_T_MAX) THEN
    _tArm := DL_MIL_ARM_DEF;               // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tArm := tArmTimeout;                  // 域内：原值采用 / Inside the domain: take the value as given
END_IF
IF (tLatchHold < DL_MIL_T_MIN) OR (tLatchHold > DL_MIL_T_MAX) THEN
    _tHold := DL_MIL_HOLD_DEF;             // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tHold := tLatchHold;                  // 域内：原值采用 / Inside the domain: take the value as given
END_IF

(* —— 段 4：组态域闸全覆盖（三个浮点入参逐项枚举，FB51-2；非有限双判，R4 / R79） —— *)
IF (_fWinStart <> _fWinStart) OR ((_fWinStart - _fWinStart) <> (_fWinStart - _fWinStart)) THEN
    _bCfgOk  := FALSE;                     // 窗口起点非有限 / Window start is not finite
    _iErrTmp := 52;                        // 故障级：窗口参数非法 / Fault: illegal window parameter
END_IF
IF _bCfgOk THEN
    IF (_fWinEnd <> _fWinEnd) OR ((_fWinEnd - _fWinEnd) <> (_fWinEnd - _fWinEnd)) THEN
        _bCfgOk  := FALSE;                 // 窗口终点非有限 / Window end is not finite
        _iErrTmp := 52;                    // 故障级：窗口参数非法 / Fault: illegal window parameter
    END_IF
END_IF
IF _bCfgOk THEN
    IF (_fWinEnd - _fWinStart) <= DL_MIL_EPS THEN
        _bCfgOk  := FALSE;                 // 窗口倒置或退化（终点须严格大于起点）/ Inverted or degenerate window, the end must exceed the start
        _iErrTmp := 52;                    // 故障级：窗口参数非法 / Fault: illegal window parameter
    END_IF
END_IF
IF _bCfgOk THEN
    IF (_fPos <> _fPos) OR ((_fPos - _fPos) <> (_fPos - _fPos)) THEN
        _bCfgOk  := FALSE;                 // 轴位置非有限（编码器失效）/ Axis position is not finite
        _iErrTmp := 53;                    // 故障级：轴位置非有限 / Fault: non-finite axis position
    END_IF
END_IF

(* —— 段 5：边沿与定时器（CASE 外无条件调用，R7；TON 的 IN 含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                    // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
rtArm(CLK := bArm);                        // 布防命令边沿无条件刷新（防电平重复布防，R79）/ Arm edge refreshed unconditionally
rtProbe(CLK := bProbeRaw);                 // 探针边沿无条件刷新（防电平抖动重复计数）/ Probe edge refreshed unconditionally
tonArm(IN := (_eState = E_DL_MeasureInputLatch_State.eArmed) AND (NOT tonArm.Q) AND (NOT _bFaultLatch),
       PT := _tArm);                       // 布防等待超时（自复位后逐轮再起）/ Arming timeout retriggered each round
tonHold(IN := (_eState = E_DL_MeasureInputLatch_State.eHold) AND (NOT tonHold.Q) AND (NOT _bFaultLatch),
        PT := _tHold);                     // 锁存结果保持计时 / Latch hold timer

(* —— 段 6：状态机主体（唯一相位写入点；故障只置请求，锁存与迁相由段 7 执行，R21） —— *)
CASE _eState OF
    E_DL_MeasureInputLatch_State.eIdle :
        (* 迁移①：布防沿 + 窗口与位置闸通过 → 布防相；保留上次锁存位置供上层读取 *)
        IF bEnable AND rtArm.Q AND _bCfgOk AND (NOT _bFaultLatch) THEN
            _eState := E_DL_MeasureInputLatch_State.eArmed;        // 进布防相 / Move to the armed phase
        END_IF

    E_DL_MeasureInputLatch_State.eArmed :
        (* 同拍竞态处理：本拍探针沿优先于超时迁移（R275），超时判定列最后 *)
        IF rtProbe.Q THEN
            _iEdgeCnt := _iEdgeCnt + DL_MIL_ONE;                   // 沿计数（含窗口外）/ Edge counted including out-of-window events
            IF (_fPos >= (_fWinStart - DL_MIL_EPS)) AND (_fPos <= (_fWinEnd + DL_MIL_EPS)) THEN
                _fLatchPos := _fPos;                               // 窗口内：锁存本拍轴位置（唯一写入点）/ Inside the window: latch the position, the single write point
                _eState    := E_DL_MeasureInputLatch_State.eLatched;   // 迁移③：进锁存相 / Move to latched
            ELSE
                _iOutsideCnt := _iOutsideCnt + DL_MIL_ONE;          // 窗口外：只计数，继续等待（毛刺不废测量）/ Out of window: count only and keep waiting
            END_IF
        ELSIF tonArm.Q THEN
            _iErrTmp   := 51;                                      // 故障级：布防窗口内无触发 / Fault: no trigger inside the arming window
            _bFaultReq := TRUE;                                    // 请求段 7 锁存 / Request the latch at segment 7
        ELSIF NOT bEnable THEN
            _eState := E_DL_MeasureInputLatch_State.eIdle;          // 迁移④：前置条件消失回空闲 / Precondition gone, back to idle
        END_IF

    E_DL_MeasureInputLatch_State.eLatched :
        (* 迁移⑥：单拍置位；拍 N 进入 / 本拍行为：bLatched 与 bDone 各置一次、布防解除 / 拍 N+1 转出至 eHold *)
        _bLatchedLatch := TRUE;                                        // 锁存保持量置位（段 8 映射）/ Latch holding bit raised and mapped at segment 8
        _bDonePulse    := TRUE;                                        // 完成内部单拍置位（段 8 映射）/ Internal done pulse raised and mapped at segment 8
        _eState        := E_DL_MeasureInputLatch_State.eHold;           // 迁移⑥：进保持相 / Move to hold

    E_DL_MeasureInputLatch_State.eHold :
        (* 迁移⑦/⑧：保持到期自动解除布防，或失能立即解除 *)
        IF tonHold.Q THEN
            _bLatchedLatch := FALSE;                                   // 保持到期：锁存位归假（须重新布防）/ Hold expired: latch cleared, re-arming required
            _eState        := E_DL_MeasureInputLatch_State.eIdle;       // 迁移⑦：回空闲相 / Back to idle
        ELSIF NOT bEnable THEN
            _bLatchedLatch := FALSE;                                   // 失能：锁存位归假 / Disabled: latch cleared
            _eState        := E_DL_MeasureInputLatch_State.eIdle;       // 迁移⑧：回空闲相 / Back to idle
        END_IF

    E_DL_MeasureInputLatch_State.eFault :
        (* 迁移⑩：复位沿出口（唯一出口，穷举可达）；锁存位置保留
           拍 N 进入 / 本拍行为：清锁存、错误码、布防位与两计数 / 拍 N+1 转出至 eIdle *)
        IF rtReset.Q THEN
            _bFaultLatch   := FALSE;                                   // 清故障锁存 / Clear the fault latch
            _iErrLatch     := 0;                                       // 清锁存故障码 / Clear the latched fault code
            _bLatchedLatch := FALSE;                                   // 清锁存保持量 / Clear the latch holding bit
            _iEdgeCnt      := 0;                                       // 清探针沿计数 / Probe edge counter cleared
            _iOutsideCnt   := 0;                                       // 清窗口外计数 / Out-of-window counter cleared
            _eState        := E_DL_MeasureInputLatch_State.eIdle;       // 回空闲相，不滞留故障态 / Back to idle, never parked in fault
        END_IF

ELSE
    (* 迁移⑨（枚举兜底）：非法枚举值 → 故障级 99（R6） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                    // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                  // 置故障锁存（码位赋值 3 行内配对，R45）/ Latch the fault within three lines
    END_IF
END_CASE

(* —— 段 7：当拍故障请求锁存（域闸）+ 段尾迁移闸 + 撤使能降级（R191 已声明为降级+置标志） —— *)
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                  // 锁存域闸首因 / Latch the gate first cause
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF _bFaultReq AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                  // 锁存布防超时首因 / Latch the arming timeout cause
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_MeasureInputLatch_State.eFault) THEN
    _eState := E_DL_MeasureInputLatch_State.eFault;   // 锁存即迁相（段尾统一执行，FB50-1④）/ Latch forces the fault phase at the tail
END_IF
IF (NOT bEnable) AND (NOT _bFaultLatch) AND (_eState <> E_DL_MeasureInputLatch_State.eIdle) THEN
    _bLatchedLatch := FALSE;                   // 撤使能：锁存位撤销（保留上次锁存位置事实）/ Disable: latch cleared, the last position fact is kept
    _eState        := E_DL_MeasureInputLatch_State.eIdle;   // 撤使能：回空闲相 / Disable: back to idle
END_IF

(* —— 段 8：统一出口（单点映射；连续量出口做非有限防护，FB51-3 / R273） —— *)
eState  := _eState;                            // 相位映射 / Phase mapping
bArmed  := (_eState = E_DL_MeasureInputLatch_State.eArmed);   // 布防中（仅布防相为真）/ Armed, true only inside the armed phase
bLatched := _bLatchedLatch AND (NOT _bFaultLatch);            // 锁存有效（故障期强制撤销）/ Latch valid, forced off during fault
bDone   := _bDonePulse AND (NOT _bFaultLatch);                // 完成单拍（故障期强制撤销）/ Completion pulse forced off during fault
bError  := _bFaultLatch;                       // 故障标志取锁存位 / Fault flag taken from the latch
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                    // 故障期回放锁存码（FB33-1）/ Replay the latched code during fault
ELSE
    iErrCode := 0;                             // 非故障拍错误码归零 / Error code zeroed outside fault
END_IF
IF (_fLatchPos <> _fLatchPos) OR ((_fLatchPos - _fLatchPos) <> (_fLatchPos - _fLatchPos)) THEN
    rLatchPosMm := 0.0;                        // 保持槽污染兜底：归零（连续量安全侧）/ Contaminated holding value forced to zero
ELSE
    rLatchPosMm := LREAL_TO_REAL(_fLatchPos);  // 锁存位置出口（降位为 REAL）/ Latched position outlet demoted to REAL
END_IF
iOutsideCnt := _iOutsideCnt;                   // 窗口外计数映射 / Out-of-window counter mapping
iEdgeCnt    := _iEdgeCnt;                      // 探针沿计数映射 / Probe edge counter mapping
END_FUNCTION_BLOCK
