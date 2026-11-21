(*
  FC_DL_PidLambdaTune  —  IMC/λ 整定纯换算（FOPDT 三参数）/ IMC lambda tuning calculator
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_83
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-math — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，SIMC/IMC 公开整定公式，未复制任何源码行
                  （与 FB_DL_AutoTuneRelay 严格分工：本件只做纯换算不产生激励；在线辨识由 FB_DL_AutoTuneRelay 承载）
  功能 Function : 1) 由 FOPDT 三参数（K/T/τ）与闭环目标时间常数 λ 直接算 PID 系数：Kc = T/(K·(λ+τ))、Ti = MIN(T, 4·(λ+τ))；
                  2) 一阶对象默认不投微分（Td = 0）；bDerivativeOn 且 λ < τ 时按变体投 Td = τ/2；
                  3) 反向作用（K < 0）按 ABS(K) 计算并置信息码（符号语义由上层承接）；
                  4) 引脚命名对齐既有件 FB_DL_PidController（仅体例，不实例化）。
  边界 Boundary : ① fProcGain = 0 / fLambdaS <= 0 / fTimeConstS <= 0 / fDeadTimeS < 0 / fKcMax <= 0 均判组态错置码
                     且不输出系数（防除零与负增益误导，系数出口维持 0）；
                  ② λ < τ/2 判「整定过激」：bFeasible := FALSE 但仍给系数并置告警（是否采纳由工艺决定）；
                  ③ fKc 输出上限取 VAR_INPUT fKcMax（禁魔法数），越限钳制；
                  ④ K < 0 按 ABS(K) 计算并置「反向作用」信息码；
                  ⑤ 解除式自证：bFeasible 每调用重算，下一调用 λ 回到 >= τ/2 即自动解除（无锁存）；
                  ⑥ 本件为纯函数：无 VAR 记忆量、无定时器、无激励输出。
  依赖 Depends  : 仅 Standard.library（ABS/MIN）；引脚命名对齐 FB_DL_PidController（已注册）
  码表 Error codes（本件格 02_3_83，子码步进 +0x100）:
    16#0002_0183 信息级：反向作用（K < 0），已按 ABS(K) 计算
    16#0002_0283 故障级：组态非法（K = 0 / λ <= 0 / T <= 0 / τ < 0 / fKcMax <= 0），不输出系数
    16#0002_0383 告警级：λ < τ/2 整定过激（bFeasible = FALSE，系数仍给出）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

FUNCTION FC_DL_PidLambdaTune : BOOL
VAR_INPUT
    fProcGain    : REAL;              // 过程增益 K [无量纲]，域 <> 0 / Process gain, nonzero
    fTimeConstS  : REAL;              // 过程时间常数 T [s]，域 > 0 / Process time constant
    fDeadTimeS   : REAL;              // 纯滞后 τ [s]，域 >= 0 / Dead time
    fLambdaS     : REAL;              // 闭环目标时间常数 λ [s]，域 > 0 / Desired closed-loop time constant
    bDerivativeOn: BOOL := FALSE;     // 微分投用开关（λ < τ 时投 Td = τ/2 变体）/ Derivative enable variant
    fKcMax       : REAL;              // Kc 输出上限 [无量纲]，域 > 0（禁魔法数）/ Kc ceiling from configuration
END_VAR
VAR_OUTPUT
    fKc          : REAL;              // 比例增益 Kc [无量纲] / Proportional gain
    fTiS         : REAL;              // 积分时间 Ti [s] / Integral time
    fTdS         : REAL;              // 微分时间 Td [s] / Derivative time
    bFeasible    : BOOL;              // 整定可行标志（λ < τ/2 置 FALSE）/ Feasible flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code, 0 = none
    fMsgCode     : REAL;              // 事件码 REAL 镜像（与 nErrId 同值，规格契约项）/ REAL mirror of the event code
END_VAR
VAR
    rKabs, rLam, rTau : LREAL;        // |K|/λ/τ 宽域暂存 / Wide-domain scratch of K, lambda, tau
    rSum              : LREAL;        // (λ + τ) 暂存 / Lambda plus tau
END_VAR

(* —— 段 1：输出缺省与组态闸（纯函数，每调用重算） —— *)
fKc := 0.0;  fTiS := 0.0;  fTdS := 0.0;    // 系数出口缺省 0（组态错不输出系数，规格强制）
bFeasible := TRUE;                          // 缺省可行
nErrId := 16#0000_0000;                     // 事件码缺省无事件
fMsgCode := 0.0;                            // REAL 镜像缺省 0
FC_DL_PidLambdaTune := FALSE;               // 返回值缺省失败

rKabs := LREAL(ABS(fProcGain));             // 按 |K| 计算（符号语义见段 4）
rLam  := LREAL(fLambdaS);
rTau  := LREAL(fDeadTimeS);

IF (rKabs < 1.0E-12) OR (rLam <= 0.0) OR (LREAL(fTimeConstS) <= 0.0)
   OR (rTau < 0.0) OR (LREAL(fKcMax) <= 0.0) THEN
    nErrId  := 16#0002_0283;                // 故障级：组态非法
    fMsgCode := 283.0;                      // REAL 镜像同步
    RETURN;                                 // 不输出系数（出口维持 0）
END_IF

(* —— 段 2：SIMC/λ 整定式（分母 rSum = λ + τ 已闸 > 0，无除零） —— *)
rSum := rLam + rTau;
fKc  := REAL(LREAL(fTimeConstS) / (rKabs * rSum));          // Kc = T / (|K|·(λ+τ))
fTiS := REAL(MIN(LREAL(fTimeConstS), 4.0 * rSum));          // Ti = MIN(T, 4·(λ+τ))
fTdS := 0.0;                                                // 一阶对象默认不投 D
IF bDerivativeOn AND (rLam < rTau) THEN
    fTdS := REAL(rTau / 2.0);                               // 微分变体：λ < τ 时投 Td = τ/2
END_IF

(* —— 段 3：Kc 上限钳制（上限来自 VAR_INPUT，禁魔法数） —— *)
IF LREAL(fKc) > LREAL(fKcMax) THEN
    fKc := fKcMax;                                          // 越上限钳制
END_IF

(* —— 段 4：符号与可行性判据（先信息码后告警码，互不覆盖故障） —— *)
IF fProcGain < 0.0 THEN
    nErrId := 16#0002_0183;                                 // 信息级：反向作用，已按 |K| 计算
END_IF
IF rLam < (rTau / 2.0) THEN
    bFeasible := FALSE;                                     // 整定过激：λ < τ/2
    nErrId := 16#0002_0383;                                 // 告警级：过激告警（系数仍给出，采纳由工艺决定）
END_IF

(* —— 段 5：出口与返回值 —— *)
fMsgCode := DINT_TO_REAL(DINT(nErrId));                     // REAL 镜像单点同步
FC_DL_PidLambdaTune := TRUE;                                // 换算已执行

END_FUNCTION
