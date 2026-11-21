(*
    FB_DL_ChangeoverSequence —— 换型换产五步顺控
    ------------------------------------------------------------------
    分类      : DL_Process / Sequence
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : T2-7 PackML（只借「最小子集 + 明确终止态」的态组织纪律，不做 17 态全集）；
                T2-8 ISA-88（只借公开条款的「配方切换需前置确认」相语义，不复制条款文本）；
                五步划分、超时策略、码位 100% 自有；clean-room 重写，未复制任何
                闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 把换产拆成五步可确认顺控：停机确认 → 排空清洁确认 → 配方装载确认 →
                参数下发确认 → 首件确认放行；每步独立超时，任一步确认不满足即停在该步
                等人工确认，绝不自动跳过（自动跳过是换产事故的头号成因）；
                最高危点：单步超时必须是「步内计时」，进入新步时把定时器重新装载，
                绝不能让超时沿相内累计（R40 教训复核项，本件用单拍 bStepEnter 重装）；
                超时只置信息码并记录阻塞步号，不置故障——人等确认是正常生产行为；
                放行标志只在完成态置位，失能即清零（安全侧）。
    错误码    : 16#0005_01D4 单步超时后等待人工确认（阻塞步号已记录，未置故障）——信息级，不置故障
                16#0005_01D5 预留禁用（信息级，不得挪用）
                16#0005_0302 单步超时参数非法（超时保护失效）——故障级，进故障态
                16#0005_0303 前置条件不满足（目标配方号未指定 / 确认信号缺失）——故障级，进故障态
                16#0005_0304 状态机落 ELSE 兜底（非法状态，回空闲）——用途固定，不得改作他用
    码位总账  : 16#0005_01D4 用 / 16#0005_01D5 预留 ｜ 16#0005_0302 用 / 16#0005_0303 用 / 16#0005_0304 用
    状态机    : E_DL_ChangeoverState（eIdle / eStep1 / eStep2 / eStep3 / eStep4 / eStep5 / eDone / eFault），
                CASE 含 ELSE 兜底，兜底固定置 eFault、步号 99 与 0304
    采样约定  : 三个 R_TRIG 与 fbStep 在本体首部无条件调用；bStepEnter 为单拍重装标志，
                在本体前部用后即清，进入新步时由状态迁移置位，下一拍定时器从 0 重计。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
                2026-11-16 v1.0.1 R18 终审修复：失能闸路径只清了内部 bReady，未清对外镜像
                bReadyForProduction，输出引脚会保留上一拍的 TRUE，违反「失能即清零」安全约定；
                已在 RETURN 前补当拍清零。对外引脚与状态机零变更。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ChangeoverState（归属本功能块，与其同文件发布）
 * 含义: 五步换产状态机离散态，步号与状态值一一对应便于 HMI 直读
 *----------------------------------------------------------------------------*)
TYPE E_DL_ChangeoverState :
(
    eIdle   := 0,      // 空闲：未启动换产 / Idle, no changeover started
    eStep1  := 10,     // 步骤一：停机确认 / Step one, machine stopped confirmation
    eStep2  := 20,     // 步骤二：排空清洁确认 / Step two, line purged and cleaned confirmation
    eStep3  := 30,     // 步骤三：配方装载确认 / Step three, recipe loaded confirmation
    eStep4  := 40,     // 步骤四：参数下发确认 / Step four, parameters applied confirmation
    eStep5  := 50,     // 步骤五：首件确认放行 / Step five, first piece released confirmation
    eDone   := 60,     // 完成：放行生产，保持到复位或中止 / Done, production released until reset or abort
    eFault  := 99      // 故障：超时参数非法 / 前置条件缺失 / 非法状态 / Fault, illegal timeout, missing precondition or an illegal state
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ChangeoverSequence
VAR_INPUT
    bEnable         : BOOL;                    // 使能，FALSE 回空闲并清放行 / enable, FALSE returns to idle and clears the release
    bReset          : BOOL;                    // 上升沿清故障与步序 / rising edge clears the fault and the step sequence
    bStart          : BOOL;                    // 上升沿启动换产，非空闲时忽略 / rising edge starts the changeover, ignored when not idle
    bAbort          : BOOL;                    // 上升沿中止，回空闲且不置故障 / rising edge aborts to idle without raising a fault
    uTargetRecipe   : UINT := 0;               // 目标配方号，0 表示未指定 / target recipe number, 0 means unspecified
    bMachineStopped : BOOL := FALSE;           // 步骤一确认：设备已停 / step one confirmation, the machine is stopped
    bLinePurged     : BOOL := FALSE;           // 步骤二确认：物料已排空或已清洁 / step two confirmation, the line is purged or cleaned
    bRecipeLoaded   : BOOL := FALSE;           // 步骤三确认：配方已装载且校验通过 / step three confirmation, the recipe is loaded and verified
    bParamsApplied  : BOOL := FALSE;           // 步骤四确认：参数已下发到设备层 / step four confirmation, the parameters reached the device layer
    bFirstPieceOk   : BOOL := FALSE;           // 步骤五确认：首件检验合格 / step five confirmation, the first piece passed inspection
    tStepTimeout    : TIME := T#5MIN;          // 单步超时 [ms]，范围 10 s~1 h / per step timeout [ms], range 10 s to 1 h
END_VAR
VAR_OUTPUT
    uStep              : UINT;                 // 当前步号 0 空闲 / 1~5 步 / 99 故障 / current step, 0 idle, 1~5 steps, 99 fault
    bBusy              : BOOL;                 // 换产进行中 / changeover in progress
    bDone              : BOOL;                 // 全部完成单周期脉冲 / all steps completed, single-cycle pulse
    bReadyForProduction: BOOL;                 // 放行生产，完成后保持到复位或中止 / production released, held until reset or abort
    uBlockedStep       : UINT;                 // 因超时被阻塞的步号，0 = 无 / step blocked by a timeout, 0 = none
    tStepElapsed       : TIME;                 // 当前步已耗时 [ms] / elapsed time in the current step [ms]
    eErr               : UDINT;                // 错误码，0=正常 / error id, 0=ok
    bError             : BOOL;                 // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigStart : R_TRIG;                      // 启动沿检测实例，本体首部无条件刷新 / start edge instance, refreshed unconditionally
    fbTrigReset : R_TRIG;                      // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbTrigAbort : R_TRIG;                      // 中止沿检测实例，本体首部无条件刷新 / abort edge instance, refreshed unconditionally
    fbStep      : TON;                         // 单步超时定时器，本体首部无条件刷新 / per step timeout timer, refreshed unconditionally
    eState      : E_DL_ChangeoverState := E_DL_ChangeoverState.eIdle; // 内部状态机步序 / internal state machine step
    bStepEnter  : BOOL;                        // 进入新步单拍标志，本体前部用后即清并触发定时器重装 / new step single cycle flag, consumed at the body top and triggers a timer reload
    bInStep     : BOOL;                        // 处于步一至步五之中 / inside one of the five steps
    bReady      : BOOL;                        // 放行内部保持位 / internal release holding bit
    bStepOk     : BOOL;                        // 本步确认信号成立 / the confirmation of the current step holds
    uStepInt    : UINT;                        // 内部步号寄存，对外镜像 / internal step number, mirrored to the output
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
END_VAR
VAR CONSTANT
    DL_CO_STEP_MAX     : UINT := 5;            // 步数上限 [步] / step count upper bound [step]
    DL_CO_TIMEOUT_MIN  : TIME := T#10S;        // 单步超时下限 [ms] / per step timeout lower bound [ms]
    DL_CO_TIMEOUT_MAX  : TIME := T#1H;         // 单步超时上限 [ms] / per step timeout upper bound [ms]
    DL_CO_STEP_FAULT   : UINT := 99;           // 故障步号 / fault step number
    DL_CO_STEP_NONE    : UINT := 0;            // 无阻塞步 / no blocked step
    DL_CO_RECIPE_NONE  : UINT := 0;            // 未指定配方号的哨兵值 / sentinel of an unspecified recipe
END_VAR

// 段 0｜输出与错误状态预置 / segment 0, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bDone := FALSE;                                // 完成脉冲先清 / clear the done pulse first
bBusy := FALSE;                                // 预置不忙 / preset not busy

// 段 1｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 1, first-scan initialisation
IF NOT bInit THEN
    bReady := FALSE;                           // 首扫不放行 / never release on the first scan
    uBlockedStep := DL_CO_STEP_NONE;           // 无阻塞步 / no blocked step
    uStepInt := 0;                             // 步号从 0 起 / the step starts at zero
    eState := E_DL_ChangeoverState.eIdle;      // 首扫落空闲态 / start in the idle state
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 2｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 2, unconditional edge refresh
fbTrigStart(CLK := bStart);
fbTrigReset(CLK := bReset);
fbTrigAbort(CLK := bAbort);

// 段 3｜单步超时定时器无条件调用，随后用后即清单拍重装标志 / segment 3, unconditional timer call then consume the reload flag
bInStep := (eState = E_DL_ChangeoverState.eStep1) OR (eState = E_DL_ChangeoverState.eStep2)
        OR (eState = E_DL_ChangeoverState.eStep3) OR (eState = E_DL_ChangeoverState.eStep4)
        OR (eState = E_DL_ChangeoverState.eStep5); // 处于步一至步五 / inside one of the five steps
fbStep(IN := bInStep AND (NOT bStepEnter), PT := tStepTimeout); // 重装拍掉 IN 使 ET 归零 / the reload cycle drops the input so ET returns to zero
bStepEnter := FALSE;                           // 用后即清，绝不跨拍残留 / consumed and cleared, never leaks to the next cycle
tStepElapsed := fbStep.ET;                     // 当前步已耗时 / elapsed time in the current step

// 段 4｜超时参数闸：超时保护失效不可接受 / segment 4, timeout parameter gate
IF (tStepTimeout < DL_CO_TIMEOUT_MIN) OR (tStepTimeout > DL_CO_TIMEOUT_MAX) THEN
    eErr := 16#0005_0302;                      // 超时参数非法故障码 / illegal timeout fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := E_DL_ChangeoverState.eFault;     // 进故障态 / enter the fault state
END_IF

// 段 5｜复位与中止沿：两者都回空闲，中止不置故障（人为操作合法）/ segment 5, reset and abort return to idle, abort raises no fault
IF fbTrigReset.Q THEN
    eState := E_DL_ChangeoverState.eIdle;      // 回空闲态 / back to idle
    bReady := FALSE;                           // 撤放行 / drop the release
    uBlockedStep := DL_CO_STEP_NONE;           // 清阻塞步 / clear the blocked step
    uStepInt := 0;                             // 步号归零 / step number to zero
    bStepEnter := TRUE;                        // 定时器重装 / reload the timer
END_IF
IF fbTrigAbort.Q THEN
    eState := E_DL_ChangeoverState.eIdle;      // 中止回空闲 / abort returns to idle
    bReady := FALSE;                           // 撤放行 / drop the release
    uBlockedStep := DL_CO_STEP_NONE;           // 清阻塞步 / clear the blocked step
    uStepInt := 0;                             // 步号归零 / step number to zero
    bStepEnter := TRUE;                        // 定时器重装 / reload the timer
END_IF

// 段 6｜使能闸：失能即回空闲并撤放行（安全侧）/ segment 6, enable gate drops the release
IF NOT bEnable THEN
    eState := E_DL_ChangeoverState.eIdle;      // 回空闲态 / back to idle
    bReady := FALSE;                           // 撤放行 / drop the release
    bBusy := FALSE;                            // 不忙 / not busy
    uStep := 0;                                // 步号归零 / step number to zero
    bReadyForProduction := FALSE;              // 放行镜像当拍清零，绝不留上一拍 TRUE / clear the release mirror in the same cycle, never leak a stale TRUE
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 7｜启动沿：仅空闲态受理 / segment 7, start edge accepted only in idle
IF fbTrigStart.Q AND (eState = E_DL_ChangeoverState.eIdle) THEN
    eState := E_DL_ChangeoverState.eStep1;     // 进第一步 / enter the first step
    uBlockedStep := DL_CO_STEP_NONE;           // 清阻塞步 / clear the blocked step
    bStepEnter := TRUE;                        // 定时器重装 / reload the timer
END_IF

// 段 8｜状态机主体（CASE 必含 ELSE 兜底，红线）/ segment 8, state machine body
CASE eState OF
    E_DL_ChangeoverState.eIdle :
        uStepInt := 0;                         // 空闲步号 0 / idle step number zero
        bBusy := FALSE;                        // 不忙 / not busy
    E_DL_ChangeoverState.eStep1 :
        uStepInt := 1;                         // 步号一 / step number one
        bBusy := TRUE;                         // 换产进行中 / changeover in progress
        IF fbStep.Q THEN
            uBlockedStep := 1;                 // 记录阻塞步 / record the blocked step
            eErr := 16#0005_01D4;              // 等待人工确认（信息级不置故障）/ waiting for manual confirmation, info level never raises a fault
        END_IF
        bStepOk := bMachineStopped;            // 本步确认 / the step confirmation
        IF bStepOk THEN
            eState := E_DL_ChangeoverState.eStep2; // 推进到下一步 / advance to the next step
            bStepEnter := TRUE;                // 定时器重装，绝不相内累计 / reload the timer, never accumulate across steps
        END_IF
    E_DL_ChangeoverState.eStep2 :
        uStepInt := 2;                         // 步号二 / step number two
        bBusy := TRUE;                         // 换产进行中 / changeover in progress
        IF fbStep.Q THEN
            uBlockedStep := 2;                 // 记录阻塞步 / record the blocked step
            eErr := 16#0005_01D4;              // 等待人工确认（信息级不置故障）/ waiting for manual confirmation, info level never raises a fault
        END_IF
        bStepOk := bMachineStopped AND bLinePurged; // 上一步完成且本步确认同时成立 / the previous step holds and this step confirms
        IF bStepOk THEN
            eState := E_DL_ChangeoverState.eStep3; // 推进到下一步 / advance to the next step
            bStepEnter := TRUE;                // 定时器重装 / reload the timer
        END_IF
    E_DL_ChangeoverState.eStep3 :
        uStepInt := 3;                         // 步号三 / step number three
        bBusy := TRUE;                         // 换产进行中 / changeover in progress
        IF uTargetRecipe = DL_CO_RECIPE_NONE THEN
            eErr := 16#0005_0303;              // 配方号未指定故障码 / unspecified recipe fault id
            bError := TRUE;                    // 置故障标志 / raise the error flag
            eState := E_DL_ChangeoverState.eFault; // 进故障态 / enter the fault state
        ELSE
            IF fbStep.Q THEN
                uBlockedStep := 3;             // 记录阻塞步 / record the blocked step
                eErr := 16#0005_01D4;          // 等待人工确认（信息级不置故障）/ waiting for manual confirmation, info level never raises a fault
            END_IF
            bStepOk := bMachineStopped AND bLinePurged AND bRecipeLoaded; // 前两步完成且配方装载确认 / the first two steps hold and the recipe is loaded
            IF bStepOk THEN
                eState := E_DL_ChangeoverState.eStep4; // 推进到下一步 / advance to the next step
                bStepEnter := TRUE;            // 定时器重装 / reload the timer
            END_IF
        END_IF
    E_DL_ChangeoverState.eStep4 :
        uStepInt := 4;                         // 步号四 / step number four
        bBusy := TRUE;                         // 换产进行中 / changeover in progress
        IF fbStep.Q THEN
            uBlockedStep := 4;                 // 记录阻塞步 / record the blocked step
            eErr := 16#0005_01D4;              // 等待人工确认（信息级不置故障）/ waiting for manual confirmation, info level never raises a fault
        END_IF
        bStepOk := bRecipeLoaded AND bParamsApplied; // 配方已装载且参数已下发 / the recipe is loaded and the parameters are applied
        IF bStepOk THEN
            eState := E_DL_ChangeoverState.eStep5; // 推进到下一步 / advance to the next step
            bStepEnter := TRUE;                // 定时器重装 / reload the timer
        END_IF
    E_DL_ChangeoverState.eStep5 :
        uStepInt := 5;                         // 步号五 / step number five
        bBusy := TRUE;                         // 换产进行中 / changeover in progress
        IF fbStep.Q THEN
            uBlockedStep := 5;                 // 记录阻塞步 / record the blocked step
            eErr := 16#0005_01D4;              // 等待人工确认（信息级不置故障）/ waiting for manual confirmation, info level never raises a fault
        END_IF
        bStepOk := bParamsApplied AND bFirstPieceOk; // 参数已下发且首件合格 / the parameters are applied and the first piece passed
        IF bStepOk THEN
            eState := E_DL_ChangeoverState.eDone; // 全部完成 / all steps completed
            bReady := TRUE;                    // 放行生产 / release production
            bDone := TRUE;                     // 完成单拍脉冲 / the single-cycle done pulse
            bBusy := FALSE;                    // 不再忙 / no longer busy
            uBlockedStep := DL_CO_STEP_NONE;   // 清阻塞步 / clear the blocked step
        END_IF
    E_DL_ChangeoverState.eDone :
        uStepInt := 6;                         // 完成步号对外按 6 表示 / the done state reports step six
        bBusy := FALSE;                        // 不忙 / not busy
        bReady := TRUE;                        // 完成态保持放行 / the done state holds the release
    E_DL_ChangeoverState.eFault :
        uStepInt := DL_CO_STEP_FAULT;          // 故障步号 99 / fault step number ninety nine
        bBusy := FALSE;                        // 不忙 / not busy
        bReady := FALSE;                       // 故障态绝不放行 / the fault state never releases production
ELSE
    eState := E_DL_ChangeoverState.eFault;     // 非法状态一律回安全故障态 / any illegal state falls back to the safe fault state
    uStepInt := DL_CO_STEP_FAULT;              // 故障步号 / the fault step number
    eErr := 16#0005_0304;                       // 本件专用兜底码，用途固定不得改作他用 / the dedicated fallback code, its purpose is fixed
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bBusy := FALSE;                            // 不忙 / not busy
    bReady := FALSE;                           // 撤放行 / drop the release
END_CASE

// 段 9｜对外镜像 / segment 9, publish the mirrors
uStep := uStepInt;                             // 步号镜像 / step number mirror
bReadyForProduction := bReady;                 // 放行镜像，失能已在上方清零 / release mirror, the enable gate already cleared it above
END_FUNCTION_BLOCK
