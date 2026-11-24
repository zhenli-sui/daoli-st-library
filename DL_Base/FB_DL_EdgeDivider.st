(*
    FB_DL_EdgeDivider —— 输入沿 1/N 分频
    ------------------------------------------------------------------
    分类      : DL_Base / Signal
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T0-1 双稳态 / 边沿族变体（源矩阵明列「主从沿 / 分频变体」为未挖扩产点）；
                只借「分频属边沿处理族」的分类事实，分频结构、钳位与回绕纪律
                100% 自有；clean-room 重写，未复制任何闭源厂商源码，
                参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 输入每 N 个上升沿输出一个单周期脉冲，用于「双作用气缸交替动作」
                「分料器奇偶道切换」「主轴每 N 转喷一次油」等现场语义；
                bDutyHalf 为 TRUE 且 N 为偶数时输出方波（N/2 拍高 / N/2 拍低），
                N 为奇数时退化为单拍脉冲并置信息码，绝不报故障；
                计数回绕用「比较 + 赋值」，禁用取余（三平台对负数取余不一致）；
                uPulseCnt 饱和不回绕，长期运行不会翻转。
    错误码    : 16#0001_0239 分频比超上限已钳位，或奇数 N 请求方波已退化单拍——信息级，正常防御
                16#0001_023A 预留禁用（信息级，不得挪用）
                16#0001_030C uDivide = 0，输出强制 FALSE——故障级，不做取余
                16#0001_030D 预留禁用（故障级，不得挪用）
                16#0001_030E 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0239 用 / 16#0001_023A 预留 ｜ 16#0001_030C 用 / 16#0001_030D 预留 / 16#0001_030E 预留
    状态机    : 无 CASE，相位由 uCntInt 一个整数承载，非法状态不可能出现
    采样约定  : fbTrigIn / fbTrigPhase 在本体首部无条件刷新；输入脉宽小于一个扫描
                周期不可见，高频输入须先由硬件计数模块预处理。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_EdgeDivider
VAR_INPUT
    bEnable     : BOOL;                        // 使能，FALSE 计数冻结并清输出 / enable, FALSE freezes the count and clears the output
    bIn         : BOOL;                        // 待分频信号，上升沿有效 / signal to divide, rising edge effective
    uDivide     : UINT := 2;                   // 分频比 N [倍]，范围 1~1000，1 = 直通 / division ratio N [x], range 1~1000, 1 = pass-through
    bPhaseReset : BOOL;                        // 相位复位，上升沿把计数与输出相位归零 / phase reset, rising edge zeroes the count and the output phase
    bDutyHalf   : BOOL := FALSE;               // TRUE 且 N 为偶数时输出方波 / FALSE 输出单拍脉冲 / TRUE gives a square wave on even N, FALSE gives a one-cycle pulse
END_VAR
VAR_OUTPUT
    bOut      : BOOL;                          // 分频输出 / divided output
    uCounter  : UINT;                          // 当前计数 0~N-1 [拍] / current counter 0~N-1 [cycle]
    uPulseCnt : UDINT;                         // 累计输出脉冲数，饱和计数 [次] / accumulated output pulses, saturating [times]
    eErr      : UDINT;                         // 错误码，0=正常 / error id, 0=ok
    bError    : BOOL;                          // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigIn    : R_TRIG;                      // 输入沿检测实例，本体首部无条件刷新 / input edge instance, refreshed unconditionally
    fbTrigPhase : R_TRIG;                      // 相位复位沿检测实例，本体首部无条件刷新 / phase reset edge instance, refreshed unconditionally
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    uCntInt     : UINT;                        // 内部相位计数 0~N-1 [拍] / internal phase counter 0~N-1 [cycle]
    uDivEff     : UINT;                        // 生效分频比，钳位后使用 [倍] / effective ratio after clamping [x]
    bHalfMode   : BOOL;                        // 方波模式有效标志（N 为偶数时成立）/ square wave mode valid flag, only on even N
    bPulseOne   : BOOL;                        // 单拍脉冲标志，用后即清 / one-cycle pulse flag, cleared after use
END_VAR
VAR CONSTANT
    DL_DIV_MAX     : UINT := 1000;             // 分频比上限 [倍] / division ratio upper bound [x]
    DL_DIV_CNT_MAX : UDINT := 16#FFFF_FFFE;    // 脉冲计数饱和值，防回绕 [次] / pulse counter saturation value, no wrap-around [times]
    DL_DIV_HALF    : UINT := 2;                // 偶数判定与半相位除数 [无量纲] / divisor for the even check and the half phase [dimensionless]
END_VAR

// 段 1｜输出与错误状态预置 / segment 1, preset outputs and error status
bOut := FALSE;                                 // 输出先清零 / clear the output first
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault

// 段 2｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 2, unconditional edge refresh
fbTrigIn(CLK := bIn);                          // 输入沿 / input edge
fbTrigPhase(CLK := bPhaseReset);               // 相位复位沿 / phase reset edge

// 段 3｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    uCntInt := 0;                              // 相位从 0 起 / phase starts at zero
    bPulseOne := FALSE;                        // 单拍标志清零 / clear the one-cycle flag
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：冻结计数并清输出 / segment 4, enable gate freezes the counter
IF NOT bEnable THEN
    uCntInt := 0;                              // 相位归零 / phase to zero
    bPulseOne := FALSE;                        // 清单拍标志 / clear the one-cycle flag
    uCounter := 0;                             // 对外计数清零 / clear the published counter
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 5｜分频比闸：0 为故障（不做取余），超上限先钳位 / segment 5, division ratio gate
IF uDivide < 1 THEN
    eErr := 16#0001_030C;                      // 分频比为 0 故障码 / zero ratio fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    uCounter := 0;                             // 计数回安全值 / counter to the safe value
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF
uDivEff := uDivide;                            // 默认沿用输入值 / default to the input value
IF uDivide > DL_DIV_MAX THEN
    uDivEff := DL_DIV_MAX;                     // 超上限钳位 / clamp to the upper bound
    eErr := 16#0001_0239;                      // 钳位提示（信息级不置故障）/ clamp hint, info level never raises a fault
END_IF

// 段 6｜方波可用性判定：偶数用「半值乘二回比」，全程不用取余 / segment 6, square wave availability without any modulo
bHalfMode := FALSE;                            // 先按单拍脉冲模式 / assume the one-cycle pulse mode
IF bDutyHalf AND (uDivEff > 1) THEN
    IF ((uDivEff / DL_DIV_HALF) * DL_DIV_HALF) = uDivEff THEN
        bHalfMode := TRUE;                     // 偶数成立，方波可用 / even ratio, square wave is available
    ELSE
        eErr := 16#0001_0239;                  // 奇数 N 请求方波，退化单拍（信息级）/ odd ratio asked for a square wave, degraded to a pulse (info level)
    END_IF
END_IF

// 段 7｜相位复位（优先于计数）/ segment 7, phase reset has priority over counting
IF fbTrigPhase.Q THEN
    uCntInt := 0;                              // 相位归零 / phase to zero
    bPulseOne := FALSE;                        // 复位拍不出脉冲，防自杀 / no pulse on the reset cycle, prevents self-kill
END_IF

// 段 8｜N = 1 直通模式 / segment 8, pass-through mode when N equals 1
IF uDivEff <= 1 THEN
    bOut := bIn;                               // 直通输出 / pass the input straight through
    uCntInt := 0;                              // 直通不累计相位 / no phase accumulation in pass-through
    uCounter := 0;                             // 对外计数归零 / publish a zero counter
    RETURN;                                    // 直通即出口 / pass-through is the exit
END_IF

// 段 9｜计数与回绕（比较 + 赋值，禁用取余）/ segment 9, counting and wrap-around by compare-and-assign
IF fbTrigIn.Q THEN
    uCntInt := uCntInt + 1;                    // 每个输入沿相位加一 / one phase step per input edge
    IF uCntInt >= uDivEff THEN
        uCntInt := 0;                          // 到达 N 即回零 / wrap to zero when reaching N
        bPulseOne := TRUE;                     // 跳变拍产生单拍脉冲 / the wrap cycle produces a one-cycle pulse
        IF uPulseCnt < DL_DIV_CNT_MAX THEN
            uPulseCnt := uPulseCnt + 1;        // 饱和加一，绝不回绕 / saturating increment, never wraps
        END_IF
    END_IF
END_IF

// 段 10｜输出形态：方波由相位直接派生，单拍脉冲用后即清（保持量另立变量）/ segment 10, output shape
IF bHalfMode THEN
    IF uCntInt >= (uDivEff / DL_DIV_HALF) THEN
        bOut := TRUE;                          // 后半相位为高 / high during the second half of the phase
    ELSE
        bOut := FALSE;                         // 前半相位为低 / low during the first half of the phase
    END_IF
ELSE
    bOut := bPulseOne;                         // 单拍模式直接镜像脉冲标志 / mirror the one-cycle flag
END_IF
bPulseOne := FALSE;                            // 用后即清，绝不跨拍残留 / consumed and cleared, never leaks to the next cycle
uCounter := uCntInt;                           // 对外镜像相位计数 / publish the phase counter
END_FUNCTION_BLOCK
