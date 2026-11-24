//==============================================================================
// 功能块：FB_DL_ConveyorAccumGateSeq ｜ 中文名称：输送线积放闸门三态序列编排
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3 第 3 版，零方言）
// 功能描述：积放/释放/满流三态编排：积放相闸门关闭、物料在积放位堆积；
//           积放位满且下游可收 → 释放相（闸门开，按 tKick 节拍向下游发
//           bDownKick 联动脉冲）；积放位满且下游不可收 → 满流相（闸门关 +
//           bUpstreamStop 请求上游节拍停止，信息级留痕）。闸门开启设最小
//           开门时长防阀/闸颤振；释放完成回积放或待机。下游节拍联动由
//           自复位周期窗 TON 生成（IN := NOT tonXxx.Q，R188 口径）。
// 开源溯源 (Origin)：原创实现（s9-conv 输送工程惯例深化，零外部源码行，
//           clean-room 独立编写）
// 公开接口清单：输入 bEn / bUpstreamRun / bFullSens / bDownReady /
//               tMinGate / tKick；
//               输出 bGateOpen / bUpstreamStop / bDownKick / eState /
//               uErrCode / bValid
// 单位表：tMinGate[ms] / tKick[ms]，其余 BOOL 引脚无量纲
// 输入契约：bFullSens 为积放位满传感，bDownReady 为下游可收声明，均经
//           IO 映射层注入；tMinGate 防闸门颤振下限；tKick 节拍周期。
// 输出契约：bGateOpen 请求级闸门开指令（执行器驱动须上层联锁）；
//           bDownKick 单拍节拍脉冲；uErrCode 信息级不锁存；
//           bValid 恒 TRUE（本件无故障级条件）。
// 错误码表：16#0005_3050 信息级（满流节拍停止请求激活，不置 bError）/
//           16#0005_3051 信息级（非法状态兜底入安全侧待机，不置 bError）/
//           16#0005_3052 预留禁用（不得挪用）
// 状态机：E_DL_AccumGateState（本文件唯一定义，全库唯一属主）：
//           eIdle = 0 / eAccumulating = 10 / eFullStop = 20 / eReleasing = 30
// 边界行为：① 闸门默认关（所有相默认值安全侧），开门仅释放相声明；
//           ② 最小开门时长未满不关门（防颤振）；
//           ③ 节拍脉冲 TON 自复位（IN := NOT tonKick.Q），每拍无条件刷新；
//           ④ 撤使能任意相回待机且闸门关（门控挂状态量）；
//           ⑤ CASE 带 ELSE 非法态兜底回 eIdle（信息级留痕）；
//           ⑥ 本件无故障级条件，不设 bError（码表与实现对齐，不虚声明）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 2 · 序 6）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_AccumGateState（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 积放闸门序列相位，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_AccumGateState :
(
    eIdle         := 0,   // 待机：闸门关，等使能与上游 / Idle, gate closed
    eAccumulating := 10,  // 积放中：闸门关，物料堆积 / Accumulating, gate closed, stock piling
    eFullStop     := 20,  // 满流：闸门关 + 上游节拍停止请求 / Full, gate closed and upstream stop requested
    eReleasing    := 30   // 释放中：闸门开 + 下游节拍联动脉冲 / Releasing, gate open with downstream kick pulses
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ConveyorAccumGateSeq
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 * 调用示例: accumGate(bEn := bLineEn, bUpstreamRun := bConvUpRun,
 *                     bFullSens := bAccumFull, bDownReady := bDownCS,
 *                     tMinGate := T#2S, tKick := T#1S);
 *          bGateOpen 驱动闸门电磁阀（经输出映射层），bDownKick 作下游
 *          节拍联动脉冲接入下游段使能合取。
 * 组装说明: ① 闸门驱动输出须在上层输出映射层复加机械限位联锁，本件
 *             bGateOpen 属请求级信号（红线 R2：零物理地址）；
 *           ② bFullSens / bDownReady 传感引脚经 PRG_IoMapping 读入注入；
 *           ③ tKick 节拍脉冲为单拍有效量，上层沿检测可省（直接作使能
 *             窗合取），如需展宽请串 FB_DL_PulseStretch；
 *           ④ 多级积放串联时，本级 bDownReady 取下级 accumGate.bGateOpen
 *             的取反（下级开门期间本级视为不可收）。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ConveyorAccumGateSeq
VAR_INPUT
    bEn          : BOOL := FALSE;     // 使能（FALSE 任意相回待机）/ Enable, FALSE returns to idle from any phase
    bUpstreamRun : BOOL := FALSE;     // 上游段运行中 / Upstream section running
    bFullSens    : BOOL := FALSE;     // 积放位满传感器 / Accumulation zone full sensor
    bDownReady   : BOOL := FALSE;     // 下游可接收声明 / Downstream ready to receive
    tMinGate     : TIME := T#2S;      // 最小开门时长 [ms]，防闸门颤振 / Minimum gate-open duration [ms], anti-chatter
    tKick        : TIME := T#1S;      // 下游节拍联动脉冲周期 [ms] / Downstream kick pulse period [ms]
END_VAR
VAR_OUTPUT
    bGateOpen    : BOOL;              // 闸门开指令（仅释放相）/ Gate open command, releasing phase only
    bUpstreamStop: BOOL;              // 上游节拍停止请求（满流相）/ Upstream stop request, full phase
    bDownKick    : BOOL;              // 下游节拍联动脉冲（单拍有效）/ Downstream kick pulse, single-scan
    eState       : E_DL_AccumGateState; // 序列当前相位 / Current sequence phase
    uErrCode     : UDINT;             // 信息级码，0 = 无信息 / Info-level code, 0 = none
    bValid       : BOOL;              // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    tonMinGate   : TON;               // 最小开门时长定时器，每拍无条件刷新 / Minimum gate-open timer, refreshed every scan
    tonKick      : TON;               // 节拍脉冲自复位定时器，每拍无条件刷新 / Kick pulse self-reset timer, refreshed every scan
END_VAR
VAR CONSTANT
    DL_CG_CODE_FULL : UDINT := 16#0005_3050; // 信息级：满流停止请求码 / Info code: full-flow stop request
    DL_CG_CODE_ILL  : UDINT := 16#0005_3051; // 信息级：非法状态兜底码 / Info code: illegal state fallback
END_VAR

// ---- 段 1｜定时器无条件刷新（红线 R7：禁入条件分支；tonKick 自复位 R188）----
tonMinGate(IN := (eState = E_DL_AccumGateState.eReleasing), PT := tMinGate); // 开门计时按相断输入 / Gate timer input per phase
tonKick(IN := (eState = E_DL_AccumGateState.eReleasing)
        AND bDownReady AND NOT tonKick.Q, PT := tKick); // 周期窗自复位（R188 口径）/ Self-resetting window per R188

// ---- 段 2｜出口默认值：入口即赋安全侧确定值 ----
bGateOpen     := FALSE;             // 闸门默认关（安全侧）/ Gate preset closed, safe side
bUpstreamStop := FALSE;             // 上游停止请求默认 FALSE / Upstream stop preset FALSE
bDownKick     := FALSE;             // 节拍脉冲默认 FALSE（相内重映射）/ Kick pulse preset FALSE
uErrCode      := 16#0000_0000;      // 信息码每拍重算（信息级不锁存）/ Info code recomputed, never latched
bValid        := TRUE;              // 可用标志默认 TRUE / Usable flag preset TRUE

// ---- 段 3｜序列状态机（CASE 带 ELSE；满流先于释放判决防抢跑）----
CASE eState OF
    E_DL_AccumGateState.eIdle:        // 待机相：闸门关，等使能
        IF bEn AND bUpstreamRun THEN
            eState := E_DL_AccumGateState.eAccumulating; // 进入积放相 / Enter accumulating
        END_IF

    E_DL_AccumGateState.eAccumulating:// 积放相：闸门关，堆积至满
        IF NOT (bEn AND bUpstreamRun) THEN
            eState := E_DL_AccumGateState.eIdle; // 撤条件回待机 / Conditions lost, back to idle
        ELSIF bFullSens THEN
            IF bDownReady THEN        // 满且下游可收 → 释放（满流先判下游）/ Full and downstream ready, release first
                eState := E_DL_AccumGateState.eReleasing;
            ELSE                      // 满且下游不可收 → 满流停止请求 / Full and not ready, full-stop
                eState := E_DL_AccumGateState.eFullStop;
            END_IF
        END_IF

    E_DL_AccumGateState.eFullStop:    // 满流相：闸门关 + 上游停止请求（信息级）
        bUpstreamStop := TRUE;        // 上游节拍停止请求 / Upstream stop request
        uErrCode := DL_CG_CODE_FULL;  // 信息级留痕（每拍重算，不置 bError）/ Info trace, no fault flag
        IF bDownReady THEN            // 下游恢复可收 → 转释放 / Downstream ready, go release
            eState := E_DL_AccumGateState.eReleasing;
        ELSIF NOT bFullSens THEN      // 积放位已不满（上游停后消化）→ 回积放 / Zone drained, back to accumulating
            eState := E_DL_AccumGateState.eAccumulating;
        END_IF

    E_DL_AccumGateState.eReleasing:   // 释放相：闸门开 + 节拍联动脉冲
        bGateOpen := TRUE;            // 闸门开声明 / Gate open declared
        bDownKick := tonKick.Q AND bDownReady; // 节拍联动脉冲（单拍有效）/ Kick pulse, single-scan
        IF NOT bEn THEN
            eState := E_DL_AccumGateState.eIdle; // 撤使能回待机 / Disable, back to idle
        ELSIF tonMinGate.Q AND (NOT bFullSens) THEN
            IF bUpstreamRun THEN
                eState := E_DL_AccumGateState.eAccumulating; // 释放完回积放 / Done, back to accumulating
            ELSE
                eState := E_DL_AccumGateState.eIdle; // 释放完且上游停回待机 / Done and upstream stopped, back to idle
            END_IF
        ELSIF (NOT bDownReady) AND tonMinGate.Q THEN
            eState := E_DL_AccumGateState.eFullStop; // 下游中途不可收 → 满流 / Downstream lost, go full-stop
        END_IF

    ELSE                              // 非法状态兜底（R21：CASE 必带 ELSE）
        eState   := E_DL_AccumGateState.eIdle; // 拦截非法值回待机（安全侧闸门关）/ Catch illegal value to idle, gate closed
        uErrCode := DL_CG_CODE_ILL;   // 信息级兜底留痕（不置 bError）/ Info-level fallback trace
END_CASE

// ---- 段 4｜统一出口：撤使能兜底（门控挂状态量）----
IF NOT bEn THEN
    IF eState <> E_DL_AccumGateState.eIdle THEN
        eState := E_DL_AccumGateState.eIdle; // 回待机 / Back to idle
    END_IF
    bGateOpen := FALSE;               // 闸门强制关 / Gate forced closed
    bUpstreamStop := FALSE;           // 停止请求撤除 / Stop request withdrawn
END_IF
END_FUNCTION_BLOCK