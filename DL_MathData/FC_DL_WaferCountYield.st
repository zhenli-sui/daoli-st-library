(*==============================================================================
 * 组件名称 (Component)  : FC_DL_WaferCountYield
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 晶圆投入/产出/返工三计数 → 良率百分数与损失分档。
 *                         良率 = 良品/投入 x 100；分档：A 级 >= 99、B 级 >= 95、
 *                         C 级 >= 90、D 级 < 90。纯函数无状态保持。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_YieldGrade / TYPE E_DL_WaferErr /
 *                         FUNCTION FC_DL_WaferCountYield
 * 依赖 (Depends)        : 无 DL_ 内部依赖；仅 IEC 61131-3 标准元素
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 无符号减法先验下界防下溢 ｜ 枚举成员全部显式赋值
 *                         纯函数无状态保持 ｜ 输出在每条早退路径前已赋确定值
 * 错误码表 (Codes)      : 16#0001_0476 故障级(否) 成功
 *                         16#0001_0477 故障级 投入计数为 0（防除零拒绝）
 *                         16#0001_0478 故障级 良品计数大于投入计数（计数矛盾）
 *                         16#0001_0479 故障级 良品+返工大于投入（计数矛盾/下溢风险）
 *                         16#0001_047A 信息级 成功但落入 D 档（不置故障标志）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 1
 * 验收向量 (Acceptance) : input=1000, good=995, rework=3 → 良率 99.5% → A 档 0476
 *                         input=0 → 0477；good=1001>input=1000 → 0478；
 *                         good=990+rework=20>input=1000 → 0479；input=100,good=80 → D 档 047A
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_YieldGrade（归属 DL_MathData，损失分档结果）
 *----------------------------------------------------------------------------*)
TYPE E_DL_YieldGrade :
(
    eGradeA := 0,    // A 档：良率 >= 99% / Grade A: yield at least 99 percent
    eGradeB := 1,    // B 档：良率 >= 95% 且 < 99% / Grade B: 95 to below 99 percent
    eGradeC := 2,    // C 档：良率 >= 90% 且 < 95% / Grade C: 90 to below 95 percent
    eGradeD := 3     // D 档：良率 < 90% / Grade D: below 90 percent
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_WaferErr（归属 DL_MathData，与 FC_DL_WaferCountYield 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_WaferErr :
(
    eOk           := 16#0001_0476,   // 成功 / Success
    eInputZero    := 16#0001_0477,   // 故障级：投入为 0，防除零拒绝 / Fault: zero input rejected
    eGoodOverIn   := 16#0001_0478,   // 故障级：良品大于投入 / Fault: good count exceeds input
    eCountContrad := 16#0001_0479,   // 故障级：良品+返工大于投入 / Fault: good plus rework exceeds input
    eGradeDNote   := 16#0001_047A    // 信息级：成功但 D 档 / Info: success but grade D
);
END_TYPE

(*==============================================================================
 * 函数: FC_DL_WaferCountYield（纯函数，无任何状态保持）
 * 调用约定: 每周期按需调用；bValid = 计数合法且结果可用。
 *============================================================================*)
FUNCTION FC_DL_WaferCountYield : BOOL
VAR_INPUT
    uInputCnt   : UDINT;               // 投入片数 [片]，有效域 0~1.0E9 / Wafer input count [pcs]
    uOutputGood : UDINT;               // 良品片数 [片] / Good wafer count [pcs]
    uReworkCnt  : UDINT;               // 返工片数 [片] / Rework wafer count [pcs]
END_VAR
VAR_OUTPUT
    fYieldPct   : REAL;                // 良率 [百分数] / Yield [percent]
    eGrade      : E_DL_YieldGrade;     // 损失分档 A~D / Yield grade A to D
    bValid      : BOOL;                // 输入合法且结果可用标志 / Input legal and result usable flag
    eError      : E_DL_WaferErr;       // 错误码 / Error code
END_VAR
VAR CONSTANT
    DL_WFR_INPUT_MAX  : UDINT := 1000000000;  // 投入计数上限 [片] / Input count upper bound [pcs]
    DL_WFR_GRADE_A    : REAL := 99.0;         // A 档门限 [百分数] / Grade A threshold [percent]
    DL_WFR_GRADE_B    : REAL := 95.0;         // B 档门限 [百分数] / Grade B threshold [percent]
    DL_WFR_GRADE_C    : REAL := 90.0;         // C 档门限 [百分数] / Grade C threshold [percent]
    DL_WFR_PCT        : REAL := 100.0;        // 百分数系数 [百分数] / Percent factor [percent]
    DL_WFR_ZERO       : REAL := 0.0;          // 零值常量，避免裸字面量 / Zero constant
END_VAR
VAR
    fYieldCalc : REAL;                 // 良率中间量 [百分数] / Yield intermediate [percent]
    uLossCnt   : UDINT;                // 损失片数 = 投入-良品-返工（校验后计算）[片] / Loss count [pcs]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：任何早退路径前输出已确定（哨兵 0 良率 + D 档 + 无效）
 *----------------------------------------------------------------------------*)
FC_DL_WaferCountYield := FALSE;                     // 返回值默认无效 / return defaults to invalid
fYieldPct := DL_WFR_ZERO;                           // 良率哨兵 0（防除零语义：保持 0）/ yield sentinel zero
eGrade := E_DL_YieldGrade.eGradeD;                  // 分档哨兵 D 档 / grade sentinel D
bValid := FALSE;                                    // 合法标志默认 FALSE / validity defaults FALSE
eError := E_DL_WaferErr.eInputZero;                 // 默认投入为 0 码 / default zero-input code

(*------------------------------------------------------------------------------
 * 段 2｜投入为 0 闸：防除零拒绝（良率保持哨兵 0）
 *----------------------------------------------------------------------------*)
IF (uInputCnt = 0) OR (uInputCnt > DL_WFR_INPUT_MAX) THEN
    eError := E_DL_WaferErr.eInputZero;             // 故障级：投入为 0 或越上限 / fault: zero or out-of-range input
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜计数矛盾闸：良品不得大于投入；良品+返工不得大于投入（先验下界防下溢）
 *----------------------------------------------------------------------------*)
IF uOutputGood > uInputCnt THEN
    eError := E_DL_WaferErr.eGoodOverIn;            // 故障级：良品 > 投入 / fault: good exceeds input
    RETURN;
END_IF
IF uReworkCnt > (uInputCnt - uOutputGood) THEN      // 减法前已证 input >= good，无下溢 / no underflow, proven
    eError := E_DL_WaferErr.eCountContrad;          // 故障级：良品+返工 > 投入 / fault: count contradiction
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜良率计算与分档：fYield = good/input x 100（除子已证非零）
 *----------------------------------------------------------------------------*)
fYieldCalc := UDINT_TO_REAL(uOutputGood) / UDINT_TO_REAL(uInputCnt) * DL_WFR_PCT;   // 良率 [百分数] / yield [percent]
IF fYieldCalc > DL_WFR_PCT THEN
    fYieldCalc := DL_WFR_PCT;                       // 上限防护（计数矛盾已拦，兜底）/ ceiling guard
END_IF
fYieldPct := fYieldCalc;                            // 输出良率 / yield output
uLossCnt := uInputCnt - uOutputGood - uReworkCnt;   // 损失片数 [片]（两条矛盾闸已保证非负）/ loss count, proven non-negative
IF fYieldPct >= DL_WFR_GRADE_A THEN
    eGrade := E_DL_YieldGrade.eGradeA;              // A 档 / grade A
    eError := E_DL_WaferErr.eOk;                    // 成功码 / success code
ELSIF fYieldPct >= DL_WFR_GRADE_B THEN
    eGrade := E_DL_YieldGrade.eGradeB;              // B 档 / grade B
    eError := E_DL_WaferErr.eOk;                    // 成功码 / success code
ELSIF fYieldPct >= DL_WFR_GRADE_C THEN
    eGrade := E_DL_YieldGrade.eGradeC;              // C 档 / grade C
    eError := E_DL_WaferErr.eOk;                    // 成功码 / success code
ELSE
    eGrade := E_DL_YieldGrade.eGradeD;              // D 档 / grade D
    eError := E_DL_WaferErr.eGradeDNote;            // 信息级：成功但 D 档（损失片数佐证）/ info: grade D note
END_IF
bValid := TRUE;                                     // 输入合法，结果可用 / input legal, result usable
FC_DL_WaferCountYield := TRUE;                      // 返回有效 / return valid
RETURN;
END_FUNCTION
