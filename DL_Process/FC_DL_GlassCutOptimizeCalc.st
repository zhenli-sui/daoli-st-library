(*
  Name: FC_DL_GlassCutOptimizeCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 两种订单长度的最优切裁组合求解。枚举法而非贪心：把 A 规格的切裁数量从 0 穷举到
           订单需求上限，对每个 A 数量在剩余原板长度内按整除算出 B 规格的最大可切数量
           （再受 B 订单需求上限约束），得到该组合的实际用料长度；取全部组合中用料最长者。
           对两种规格的原板一维下料问题，穷举 A 数量 + 每档取最大 B 即为严格最优
           （每档内 B 取最大不会减少用料，且全部 A 档位已覆盖）。
        2) 余料率与利用率：利用率 fUtilPct = 最优用料 / 原板长度 × 100，
           余料 fScrapM = 原板长度 − 最优用料。余料必然 >= 0（穷举解保证不超原板）。
        3) 循环上界由订单需求与 DL_MAX_CNT 双重钳制，避免运行时无界循环拖垮扫描周期。
  边界条件：1) 非有限值闸：五个实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：原板长度与两种订单长度都必须 ABS > DL_EPS（任为 0 则整除与利用率无定义）。
        3) 负值闸：原板长度、两种订单长度为负，或两种数量为负均判无效
           （负数量无物理意义，取绝对值会虚增切裁方案）。
        4) 钳制：订单数量先钳到 0 ~ DL_MAX_CNT(200)，原板长度钳 0 ~ DL_LEN_MAX(100000 m)；
           数量被钳或原板越域时置 xValid=FALSE，避免把截断后的方案当作真实方案下发。
        5) 循环规范（R18）：只使用 FOR i := a TO b DO 的递增形式，禁用 DOWNTO。
  量纲自证：用料 = 段 × m + 段 × m = m；余料 = m − m = m；
           利用率 = m / m × 100 = 无因次 [%]，分子分母同量纲；
           整除式 _fRemain / fOrderLenB 得「段数」（无因次个数），再取整后乘回长度得 m。
*)

FUNCTION FC_DL_GlassCutOptimizeCalc : BOOL
VAR_INPUT
    fRibbonLenM   : REAL;   // 原板（玻璃带）可用长度 [m] / Available ribbon length [m]
    fOrderLenA    : REAL;   // A 规格订单长度 [m] / Order length A [m]
    fOrderLenB    : REAL;   // B 规格订单长度 [m] / Order length B [m]
    iQtyA         : INT;    // A 规格需求数量 [段] / Order quantity A [pcs]
    iQtyB         : INT;    // B 规格需求数量 [段] / Order quantity B [pcs]
END_VAR
VAR_OUTPUT
    fUtilPct      : REAL;   // 最优利用率 [%] / Optimal utilization ratio [%]
    fScrapM       : REAL;   // 余料长度 [m] / Scrap length [m]
    iBestA        : INT;    // 最优方案中的 A 数量 [段] / Quantity A in optimal plan [pcs]
    iBestB        : INT;    // 最优方案中的 B 数量 [段] / Quantity B in optimal plan [pcs]
    xValid        : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _i                : INT;    // 枚举循环变量（A 规格数量）[段] / Enumeration index for A [pcs]
    _iQtyAClamp       : INT;    // 钳制后的 A 需求数量 [段] / Clamped quantity A [pcs]
    _iQtyBClamp       : INT;    // 钳制后的 B 需求数量 [段] / Clamped quantity B [pcs]
    _iBestACalc       : INT;    // 计算过程中的最优 A 数量 [段] / Best A during search [pcs]
    _iBestBCalc       : INT;    // 计算过程中的最优 B 数量 [段] / Best B during search [pcs]
    _iBMax            : INT;    // 当前 A 档位下 B 的可切数量 [段] / Max B at current A [pcs]
    _fRemainM         : REAL;   // 切完 A 后的剩余长度 [m] / Remaining length after A [m]
    _fUsedM           : REAL;   // 当前组合的实际用料 [m] / Used length of current plan [m]
    _fBestUsedM       : REAL;   // 已找到的最优用料 [m] / Best used length found [m]
    _fRibbonClamp     : REAL;   // 钳制后的原板长度 [m] / Clamped ribbon length [m]
    _fUtilRawPct      : REAL;   // 未饱和的利用率 [%] / Raw utilization ratio [%]
    _iQtyAMax         : INT;    // A 需求上限（钳制用）[段] / Quantity A ceiling [pcs]
    _iQtyBMax         : INT;    // B 需求上限（钳制用）[段] / Quantity B ceiling [pcs]
    _fQtyMaxReal      : REAL;   // 数量上限的实数形态 [段] / Quantity ceiling as real [pcs]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT        : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_MAX_CNT    : INT  := 200;       // 枚举与数量的钳制上限 [段] / Enumeration and quantity ceiling [pcs]
    DL_LEN_MAX    : REAL := 100000.0;  // 原板长度饱和上限 [m] / Ribbon length saturation ceiling [m]
END_VAR

(* —— 段 1：非有限值闸（R19：五路实值入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fRibbonLenM > -DL_BIG AND fRibbonLenM < DL_BIG)
   OR NOT (fOrderLenA > -DL_BIG AND fOrderLenA < DL_BIG)
   OR NOT (fOrderLenB > -DL_BIG AND fOrderLenB < DL_BIG) THEN
    fUtilPct := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fScrapM := 0.0;                         // 余料强制 0.0 / Scrap forced to zero
    iBestA := 0;                            // 最优 A 数量清零 / Best A cleared
    iBestB := 0;                            // 最优 B 数量清零 / Best B cleared
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GlassCutOptimizeCalc := FALSE;    // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：原板长度与两种订单长度都是整除/归一的分母） —— *)
IF (ABS(fRibbonLenM) <= DL_EPS) OR (ABS(fOrderLenA) <= DL_EPS) OR (ABS(fOrderLenB) <= DL_EPS) THEN
    fUtilPct := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fScrapM := 0.0;                         // 余料强制 0.0 / Scrap forced to zero
    iBestA := 0;                            // 最优 A 数量清零 / Best A cleared
    iBestB := 0;                            // 最优 B 数量清零 / Best B cleared
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GlassCutOptimizeCalc := FALSE;    // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（长度与数量均不可为负） —— *)
IF (fRibbonLenM < 0.0) OR (fOrderLenA < 0.0) OR (fOrderLenB < 0.0)
   OR (iQtyA < 0) OR (iQtyB < 0) THEN
    fUtilPct := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fScrapM := 0.0;                         // 余料强制 0.0 / Scrap forced to zero
    iBestA := 0;                            // 最优 A 数量清零 / Best A cleared
    iBestB := 0;                            // 最优 B 数量清零 / Best B cleared
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GlassCutOptimizeCalc := FALSE;    // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：数量与长度钳制（枚举上界必须是有界常量，禁止运行期无界循环） —— *)
_iQtyAMax := DL_MAX_CNT;                                          // A 需求上限 [段]
_iQtyBMax := DL_MAX_CNT;                                          // B 需求上限 [段]
_iQtyAClamp := MAX(0, MIN(iQtyA, _iQtyAMax));                     // 钳制后的 A 数量 [段]
_iQtyBClamp := MAX(0, MIN(iQtyB, _iQtyBMax));                     // 钳制后的 B 数量 [段]
_fRibbonClamp := LIMIT(0.0, fRibbonLenM, DL_LEN_MAX);             // 原板长度钳制 [m]
_fQtyMaxReal := INT_TO_REAL(DL_MAX_CNT);                          // 数量上限实数形态 [段]

(* —— 段 5：枚举最优切裁（R18：仅递增 FOR；A 档位穷举，每档 B 取最大） —— *)
_fBestUsedM := 0.0;                                               // 最优用料初值 [m]
_iBestACalc := 0;                                                 // 最优 A 初值 [段]
_iBestBCalc := 0;                                                 // 最优 B 初值 [段]
FOR _i := 0 TO _iQtyAClamp DO
    _fRemainM := _fRibbonClamp - INT_TO_REAL(_i) * fOrderLenA;    // 切 A 后的剩余长度 [m]
    IF _fRemainM >= 0.0 THEN
        _iBMax := REAL_TO_INT(LIMIT(0.0, _fRemainM / fOrderLenB, _fQtyMaxReal));   // B 可切数 [段]
        _iBMax := MIN(_iBMax, _iQtyBClamp);                       // 再受 B 需求上限约束
        _fUsedM := INT_TO_REAL(_i) * fOrderLenA + INT_TO_REAL(_iBMax) * fOrderLenB;   // 实际用料 [m]
        IF _fUsedM > _fBestUsedM THEN
            _fBestUsedM := _fUsedM;                               // 刷新最优用料
            _iBestACalc := _i;                                    // 记录最优 A 数量
            _iBestBCalc := _iBMax;                                // 记录最优 B 数量
        END_IF
    END_IF
END_FOR

(* —— 段 6：输出单点写盘（利用率与余料同源于 _fBestUsedM，保证两值自洽） —— *)
_fUtilRawPct := _fBestUsedM / _fRibbonClamp * DL_PCT;             // 利用率 [%]
fUtilPct := LIMIT(0.0, _fUtilRawPct, DL_PCT);                     // 利用率钳 0..100 [%]
fScrapM := LIMIT(0.0, _fRibbonClamp - _fBestUsedM, DL_LEN_MAX);   // 余料 [m]
iBestA := _iBestACalc;                                            // 最优 A 数量出口 [段]
iBestB := _iBestBCalc;                                            // 最优 B 数量出口 [段]

(* —— 段 7：有效位单点聚合（数量未被截断、原板长度未越域） —— *)
xValid := (iQtyA <= _iQtyAMax) AND (iQtyB <= _iQtyBMax)           // 数量未被钳制截断
          AND (fRibbonLenM <= DL_LEN_MAX)                         // 原板长度未越域
          AND (fOrderLenA > DL_EPS) AND (fOrderLenB > DL_EPS);    // 两种长度均可用
FC_DL_GlassCutOptimizeCalc := xValid;                             // 返回码：TRUE = 计算可信

END_FUNCTION
