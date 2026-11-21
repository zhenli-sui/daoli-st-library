(*
  ==================================================================
  组件名 Component  : FC_DL_GcdUdintCalc
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0663（信息级）｜ 16#0001_0664（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : UDINT 最大公约数（欧几里得迭代 + WHILE 守卫计数），供
                      电子齿轮比约分、脉冲当量配比、采样周期同步等调用方；
                      返回 GCD(nA, nB)，双零入参返回 0 哨兵 + 信息级。
  开源溯源 Origin    : T0 数论原子补口（内部来源，零检索）；欧几里得算法为
                      公共领域数学事实；WHILE 守卫计数为道莅防御性范式。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.4 WHILE / MOD 语义；欧几里得
                      算法（公共领域数学事实）
  平台   Platform   : 纯 IEC 61131-3（WHILE / MOD / 比较），三平台通用
  依赖   Depends    : 无（零委托、零库件）
  分工声明 Split     : FC_DL_LcmUdintCalc（最小公倍数，委托本件 GCD 作除子）
                      为互补件（互引）；本件只算 GCD，不做 LCM（LCM 含
                      乘法溢出域，职责分离，R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 双零哨兵（nA = 0 且 nB = 0）：GCD 数学上无定义，
                         返回 0 哨兵 + 信息级 0663 + bValid = TRUE（调用方
                         以 0 值即可甄别，不置 bError——组态缺省不是运行
                         故障）；单零入参按 GCD(x, 0) = x 口径返回非零方；
                      二 MOD 除零防：循环条件 nY <> 0 已证除子非零，除法段
                         不可达（R1 教训出厂即正确）；
                      三 WHILE 守卫计数（DL_GCD_GUARDMAX = 64）：纯 IEC 语义
                         下欧几里得迭代余量单调递减、必在极小步数内终止，
                         守卫理论不可达；触发路径仅为平台 UDINT MOD 异常
                         回绕类非标行为（安全断言反例声明）；守卫命中 →
                         故障级 0664 + 返回 0 哨兵 + bValid = FALSE；
                      四 迭代计数 nIter 外显 [次]，供调用方审计收敛步数；
                      五 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      六 无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0001_0663【信息级】双零入参（GCD 无定义，返回 0 哨兵，不置 bError）
    16#0001_0664【故障级】WHILE 守卫计数越限（平台异常回绕类，理论不可达防御）
  码位反证 Note     :
    0663 与 0664 不可合并：0663 出口 bValid = TRUE（哨兵 0 是合法甄别结果），
    0664 出口 bValid = FALSE（结果不可用），bValid 可唯一区分两场景，按 R90
    分立；单零入参（GCD(x, 0) = x）为正常数学口径，无码。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 GCD(48, 36) = 12；V2 GCD(17, 5) = 1（互质）
    V3 GCD(7, 0) = 7 / GCD(0, 7) = 7（单零口径）
    V4 GCD(0, 0) → 0 哨兵 + 信息级 0663（bError = FALSE）
    V5 nIter 审计：V1 场景 nIter = 2（48,36 → 36,12 → 12,0）
    V6 守卫命中（强改平台异常注入）→ 码 0664 + bValid = FALSE + 返回 0
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 1 · 序号 3，T0 数论原子补口）
  ==================================================================
*)
FUNCTION FC_DL_GcdUdintCalc : UDINT
VAR_INPUT
    nA : UDINT := 0; // 左操作数 [脉冲 / 计数]，无符号 / the left operand, unsigned
    nB : UDINT := 0; // 右操作数 [脉冲 / 计数]，无符号 / the right operand, unsigned
END_VAR
VAR_OUTPUT
    nIter  : DINT;  // 迭代计数 [次]，供收敛审计 / the iteration count for the convergence audit
    bValid : BOOL;  // 结果可用 [-]（双零哨兵也是可用结果）/ the result usable, the zero sentinel is still usable
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    nX   : UDINT := 0; // 迭代被除数工作副本 [脉冲 / 计数] / the dividend working copy of the iteration
    nY   : UDINT := 0; // 迭代除数工作副本 [脉冲 / 计数] / the divisor working copy of the iteration
    nRem : UDINT := 0; // 余数承接量 [脉冲 / 计数] / the remainder holder
VAR CONSTANT
    DL_GCD_ZERO    : UDINT := 0;  // 无符号零常量 [脉冲 / 计数] / the unsigned zero constant
    DL_GCD_GUARDMAX: DINT   := 64; // WHILE 守卫计数上界 [次]（欧几里得迭代理论步数远小于此）/ the while guard ceiling, the euclid iteration converges far earlier
    DL_GCD_ZEROI   : DINT   := 0;  // 整型零常量 [次] / the integer zero constant
    DL_GCD_ONEI    : DINT   := 1;  // 整型一常量 [次] / the integer one constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_GcdUdintCalc := DL_GCD_ZERO; // 返回值预置 0 哨兵 / preset the return to the zero sentinel
nIter := DL_GCD_ZEROI; // 迭代计数预置零 [次] / preset the iteration count zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
nX := DL_GCD_ZERO; // 被除数副本预置零 / preset the dividend copy zero
nY := DL_GCD_ZERO; // 除数副本预置零 / preset the divisor copy zero
nRem := DL_GCD_ZERO; // 余数承接量预置零 / preset the remainder holder zero

// 段 2｜双零哨兵（边界一：GCD(0,0) 无定义，信息级不置 bError）/ segment 2, the double zero sentinel
IF (nA = DL_GCD_ZERO) AND (nB = DL_GCD_ZERO) THEN // 双零入参 / both operands are zero
    eErr := 16#0001_0663; // 信息级：双零哨兵（R285）/ informational, the double zero sentinel
    bError := FALSE; // 信息级不置故障标志 / keep the fault flag false, this is informational
    bValid := TRUE; // 哨兵 0 是合法甄别结果 / the sentinel zero is a legit discernible result
    RETURN; // 早退，返回 0 / early return with zero
END_IF

// 段 3｜欧几里得迭代（边界二：MOD 除子 nY 由循环条件证明非零；边界三：守卫计数）/ segment 3, the euclid iteration with the proven divisor and the guard
nX := nA; // 被除数接管 [脉冲 / 计数] / take the dividend
nY := nB; // 除数接管 [脉冲 / 计数] / take the divisor
WHILE (nY <> DL_GCD_ZERO) AND (nIter < DL_GCD_GUARDMAX) DO // 除子非零且守卫未越限 / the divisor is nonzero and the guard is not exceeded
    nRem := nX MOD nY; // 余量（除子 nY 已由循环条件证明非零，除零不可达）/ the remainder, the divisor proven nonzero by the loop condition
    nX := nY; // 欧几里得步进：被除数取旧除数 / the euclid step, the dividend takes the old divisor
    nY := nRem; // 除数取余量 / the divisor takes the remainder
    nIter := nIter + DL_GCD_ONEI; // 迭代计数推进 [次] / advance the iteration count
END_WHILE

// 段 4｜守卫命中闸与统一出口（边界三）/ segment 4, the guard hit gate and the unified outlet
IF nY <> DL_GCD_ZERO THEN // 迭代因守卫越限退出（余量未收敛，平台异常路径）/ the loop exited by the guard with a nonzero remainder
    eErr := 16#0001_0664; // 故障级：守卫计数越限 / fault grade, the guard count exceeded
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    FC_DL_GcdUdintCalc := DL_GCD_ZERO; // 返回 0 哨兵（禁输出未收敛残值）/ return the zero sentinel, no unconverged residue
    RETURN; // 早退 / early return
END_IF
FC_DL_GcdUdintCalc := nX; // GCD 结果出口 [脉冲 / 计数]（nY 已收敛为 0，nX 即最大公约数）/ the gcd outlet with the converged value
bValid := TRUE; // 结果可用 / the result is usable
END_FUNCTION
