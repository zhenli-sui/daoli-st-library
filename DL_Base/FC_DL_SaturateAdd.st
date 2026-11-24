(*
  FC_DL_SaturateAdd  —  饱和加减运算 / Saturating add and subtract
  分类 Category : DL_Base
  码位 Code     : 16#01_0_00
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-math — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，通用饱和算术语义，未复制任何源码行
  功能 Function : 1) 以 LINT 宽域中间量计算 nInA ± nInB（Add/Sub 两模式），杜绝 DINT 先加后判的回绕静默翻号；
                  2) 结果先与 [nLimitLo, nLimitHi] 组态区间钳制，再与 DINT 可表达域钳制，输出最终 nOut；
                  3) bClamped 指示本调用发生了钳制（每调用无条件重算，无锁存）。
  边界 Boundary : ① nLimitLo > nLimitHi 判组态错置码，输出 nLimitLo（安全侧下界）且 bClamped := TRUE；
                  ② 结果超出 DINT 可表达域时饱和到对应 DINT 极限并 bClamped := TRUE（DINT ± DINT 在 LINT 内必不溢出，此分支为防御性兜底）；
                  ③ eOp 落入未知值由 CASE ELSE 拦截：置码、输出 0、bClamped := TRUE（不猜运算方向）；
                  ④ 解除式自证：bClamped 为每调用重算量，下一调用结果重新落入区间即自动解除（无 bReset、无锁存）；
                  ⑤ 本件为纯函数：无 VAR 记忆量、无定时器、无边沿实例，可离平台编译。
  依赖 Depends  : 仅 Standard.library（无库调用）；枚举 E_DL_SatOp 随本件发布
  码表 Error codes（本件格 01_0_00，子码步进 +0x100）:
    16#0001_0100 信息级：结果被钳制（bClamped = TRUE，不置故障）
    16#0001_0200 故障级：组态非法 nLimitLo > nLimitHi，输出安全侧下界
    16#0001_0300 故障级：运算模式 eOp 非法（CASE ELSE 兜底）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_SatOp :
(
    eAdd := 0,   // 加法模式 / Addition mode
    eSub := 1    // 减法模式 / Subtraction mode
);
END_TYPE

FUNCTION FC_DL_SaturateAdd : BOOL
VAR_INPUT
    nInA     : DINT;                 // 操作数 A / Operand A
    nInB     : DINT;                 // 操作数 B / Operand B
    eOp      : E_DL_SatOp;           // 运算模式（Add/Sub）/ Operation mode, Add or Sub
    nLimitHi : DINT;                 // 组态上限 [DINT] / Configured upper limit
    nLimitLo : DINT;                 // 组态下限 [DINT] / Configured lower limit
END_VAR
VAR_OUTPUT
    nOut     : DINT;                 // 钳制后结果 / Saturated result
    bClamped : BOOL;                 // 本调用发生钳制 / Clamped on this call, recomputed per call
    nErrId   : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    liWork : LINT;                  // 宽域中间量（FC 局部临时量，每调用重算，非记忆量）/ Wide scratch, temp per call
END_VAR
VAR CONSTANT
    DL_DINT_HI : LINT := 2147483647;   // DINT 可表达上界 / Expressible DINT upper bound
    DL_DINT_LO : LINT := -2147483648;  // DINT 可表达下界 / Expressible DINT lower bound
END_VAR

(* —— 段 1：单拍量缺省与组态闸（纯函数，每调用重算） —— *)
nOut     := 0;                        // 输出缺省 0
bClamped := FALSE;                    // 钳制标志每调用重算（无锁存，解除式自证）
nErrId   := 16#0000_0000;             // 事件码缺省无事件

IF nLimitLo > nLimitHi THEN
    nOut     := nLimitLo;             // 组态错：输出安全侧下界（规格强制）
    bClamped := TRUE;                 // 组态错视为钳制
    nErrId   := 16#0001_0200;         // 故障级：组态非法
    FC_DL_SaturateAdd := FALSE;       // 返回值：运算未受理
    RETURN;                            // 组态非法不进入运算
END_IF

(* —— 段 2：LINT 宽域运算（禁先 DINT 相加再判溢出） —— *)
CASE eOp OF

E_DL_SatOp.eAdd:
    liWork := LINT(nInA) + LINT(nInB);   // 宽域加法，DINT±DINT 必不溢出 LINT
    FC_DL_SaturateAdd := TRUE;           // 运算已受理

E_DL_SatOp.eSub:
    liWork := LINT(nInA) - LINT(nInB);   // 宽域减法
    FC_DL_SaturateAdd := TRUE;           // 运算已受理

ELSE
    nOut   := 0;                    // 未知模式：输出 0（不猜方向）
    bClamped := TRUE;               // 视为异常钳制
    nErrId := 16#0001_0300;         // 故障级：运算模式非法
    FC_DL_SaturateAdd := FALSE;     // 运算未受理
    RETURN;

END_CASE

(* —— 段 3：先 DINT 可表达域钳制，再组态区间钳制（顺序不可倒置） —— *)
IF liWork > DL_DINT_HI THEN
    liWork   := DL_DINT_HI;         // 超上界：饱和到 DINT 上限
    bClamped := TRUE;               // 钳制标志
    nErrId   := 16#0001_0100;       // 信息级：结果被钳制
ELSIF liWork < DL_DINT_LO THEN
    liWork   := DL_DINT_LO;         // 超下界：饱和到 DINT 下限
    bClamped := TRUE;
    nErrId   := 16#0001_0100;       // 信息级：结果被钳制
END_IF

IF liWork > LINT(nLimitHi) THEN
    liWork   := LINT(nLimitHi);     // 超组态上限：钳到上限
    bClamped := TRUE;
    nErrId   := 16#0001_0100;       // 信息级：结果被钳制
ELSIF liWork < LINT(nLimitLo) THEN
    liWork   := LINT(nLimitLo);     // 低于组态下限：钳到下限
    bClamped := TRUE;
    nErrId   := 16#0001_0100;       // 信息级：结果被钳制
END_IF

(* —— 段 4：出口单点映射 —— *)
nOut := DINT(liWork);               // 宽域结果回落 DINT（已经两段钳制，必在表达域内）

END_FUNCTION
