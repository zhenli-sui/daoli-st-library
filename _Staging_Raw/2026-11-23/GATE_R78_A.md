# GATE_R78_A 裁决报告 ｜ R78 B1 批（30 件简单 FC）

- 裁决席: dlf-compile-verifier ｜ 日期: 2026-11-23 ｜ L2 工具: `_tools/l2_check.py`（串行 jobs=1，逐件默认参数）
- L2 总量: 30 ｜ 初测 PASS 24 / FAIL 6（E073 缺 STRING_GREATER/STRING_LESS 桩）
- **工具链自愈记录**: `stub_fix.py --full` 不生成比较函数桩（仅转换函数）→ 手工区补桩 `_tools/rusty/iec_std_stub.st`（STRING_EQUAL 后追加 `STRING_GREATER` / `STRING_LESS` 两条 `{external}` 空体声明）。补桩位于手工区标记内，`stub_fix.py --full` 不覆盖手工区，再生安全。补桩后 6 件复测全部 PASS。源码用 `sChar >= '0'` 等字符区间比较为合法 IEC 语法，非豁免项，属工具链缺桩，已修复，**本批 EXEMPT = 0**。

## 逐件裁决表

| 文件 | 编译裁决 | 错误码 | L1 逻辑复核 | 建议动作 |
|---|---|---|---|---|
| DL_MathData/FC_DL_CharIsDigit.st | PASS | （初测 E073，补桩后过） | PASS | 入库 |
| DL_MathData/FC_DL_CharIsAlpha.st | PASS | （初测 E073，补桩后过） | PASS | 入库 |
| DL_MathData/FC_DL_CharIsAlnum.st | PASS | （初测 E073，补桩后过） | PASS | 入库 |
| DL_MathData/FC_DL_CharIsUpper.st | PASS | （初测 E073，补桩后过） | PASS | 入库 |
| DL_MathData/FC_DL_CharIsLower.st | PASS | （初测 E073，补桩后过） | PASS | 入库 |
| DL_MathData/FC_DL_CharIsSpace.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_CharIsHexDigit.st | PASS | （初测 E073，补桩后过） | PASS | 入库 |
| DL_MathData/FC_DL_CharToUpper.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_RoundToMultipleInt.st | PASS | — | **FAIL** | **BLOCK，回派编码专家**（见问题清单 Q1） |
| DL_MathData/FC_DL_RoundToMultipleReal.st | PASS | — | WARN | 入库，挂账 W1（REAL_TO_DINT 舍入口径依赖平台） |
| DL_MathData/FC_DL_CeilToMultipleInt.st | PASS | — | PASS（含饱和闸） | 入库 |
| DL_MathData/FC_DL_FloorToMultipleInt.st | PASS | — | PASS（含饱和闸） | 入库 |
| DL_MathData/FC_DL_TruncToMultipleInt.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_QuantizeStepReal.st | PASS | — | WARN | 入库，挂账 W1 |
| DL_MathData/FC_DL_SnapToStepLreal.st | PASS | — | WARN | 入库，挂账 W1 |
| DL_MathData/FC_DL_PressureUnitConvert.st | PASS | — | WARN | 入库，挂账 W2（NaN/Inf 未闸，透传） |
| DL_MathData/FC_DL_ForceUnitConvert.st | PASS | — | WARN | 入库，挂账 W2 |
| DL_MathData/FC_DL_TimeUnitConvert.st | PASS | — | WARN | 入库，挂账 W2 |
| DL_MathData/FC_DL_BcdIsValidByte.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_BcdIsValidWord.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_BcdAddByte.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_BcdSubByte.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_BcdIncrementByte.st | PASS | — | PASS | 入库 |
| DL_MathData/FC_DL_BcdDecrementByte.st | PASS | — | PASS | 入库 |
| DL_Base/FC_DL_ParityEvenByte.st | PASS | — | PASS | 入库 |
| DL_Base/FC_DL_ParityOddByte.st | PASS | — | PASS | 入库 |
| DL_Base/FC_DL_ParityEvenWord.st | PASS | — | PASS | 入库 |
| DL_Base/FC_DL_ParityOddWord.st | PASS | — | PASS | 入库 |
| DL_Base/FC_DL_ParityEvenLword.st | PASS | — | WARN | 入库，挂账 W3（名实不符） |
| DL_Base/FC_DL_ParityOddLword.st | PASS | — | WARN | 入库，挂账 W3 |

## 计数与通过率

- 编译裁决: **PASS 30 / FAIL 0 / EXEMPT 0**，通过率 30/30 = 100%（含工具链补桩自愈）
- L1 逻辑复核: **PASS 21 / WARN 8 / FAIL 1**
- 批次 verdict: **BLOCK**（仅针对 FC_DL_RoundToMultipleInt 一件；其余 29 件放行）

## L1 复核拦下的问题清单

### Q1 ｜ FC_DL_RoundToMultipleInt ｜ 整数溢出 ｜ 严重度 MAJOR（安全侧，阻断入库）

半值进位/退位分支无饱和闸，正负两侧均可 DINT 回绕：

- 正侧最小复现: `nValue=2147483647, nMultiple=2` → `nLo=2147483646, nRem=1, nHalf=1, MOD2=0` → `nLo+nMultiple = 2147483648` 回绕为 `-2147483648`。同型: `nValue=2147483645, nMultiple=10` → `-2147483650`。
- 负侧最小复现: `nValue=-2147483648, nMultiple=3` → `nLo=-2147483646, nRem=-2 > nHalf` → `nLo-nMultiple = -2147483649` 回绕为 `+2147483647`。

对比: 同批 `FC_DL_CeilToMultipleInt` / `FC_DL_FloorToMultipleInt` 均已做上限/下限反算饱和闸，本件漏配。**最小修法建议**（由编码专家执行，裁决席不改业务码）: 进位前仿 Ceil 件加 `IF nLo <= (2147483647 - nMultiple) THEN ... ELSE 饱和 END_IF`；退位前仿 Floor 件加 `IF nLo >= (-2147483648 + nMultiple) THEN ... ELSE 饱和 END_IF`。修毕需补向量用例: `(2147483647,2)`、`(2147483645,10)`、`(-2147483648,3)`、`(-2147483647,2)` 至 `_TESTS/FC_DL_RoundToMultipleInt.json`。

### W1 ｜ RoundToMultipleReal / QuantizeStepReal / SnapToStepLreal ｜ 转换舍入口径 ｜ MINOR

三件头注释与行内注释均声称"IEC 实转整为就近舍入"，但 IEC 61131-3 对 REAL→INT 显式转换的舍入方向在标准与各平台（CODESYS/TwinCAT/MatIEC）间存在口径差异（就近 vs 向零截断）。若目标编译器按截断实现，量化结果将系统性偏向下网格而非"最近格点"，与契约不符。建议编码专家改为显式 `ROUND`（就近）或 `TRUNC`（截断）+ 手动半值进位，使语义自证、平台无关；挂账不改判。

### W2 ｜ PressureUnitConvert / ForceUnitConvert / TimeUnitConvert ｜ NaN/Inf 未闸 ｜ MINOR

三件未做非有限输入闸（同批 Round/Quantize 件均有 `fValue<>fValue` 惯用法），NaN/Inf 算术透传。除数为编译期字面量非零常量，无除零风险，故仅口径不一致，不入库无碍；挂账，建议统一族内口径。

### W3 ｜ ParityEvenLword / ParityOddLword ｜ 名实不符 ｜ MINOR

件名 `Lword` 暗示 LWORD（64 位），实现为 DWORD（32 位，折叠 16→8→4→2→1），头注释已明示"32 位 DWORD 口径"故非缺陷，但与命名族约定冲突。建议改名 `FC_DL_ParityEvenDword/OddDword` 或补真 64 位 LWORD 版（折叠 32→16→…→1）。挂账不改判。

## 复现命令

```bash
# L2 逐件（串行 jobs=1）
python C:\Library\_tools\l2_check.py C:\Library\DL_MathData\<Name>.st
python C:\Library\_tools\l2_check.py C:\Library\DL_Base\<Name>.st
# 工具链自愈（已执行）
python C:\Library\_tools\stub_fix.py --full   # 补桩未由该命令生成，为手工区追加，见上
```

## 附注

- 向量门（L3）: 本批 30 件均无 `_TESTS\<Name>.json`，按"逐步铺开"口径本轮不阻断；Q1 修复件必须随修随补 4 条边界用例（见 Q1）。
- BCD 族复核结论: 加法饱和 99 不回绕、减法借位饱和 0 不回绕、增量 99→0/减量 0→99 为头注释明示的循环计数口径、非法半字节四件均先校验后运算、编码 `SHL(INT_TO_BYTE(nTens),4) OR nOnes` 无越域——全部通过。
- 校验族结论: 折叠错位恒小于位宽（BYTE 4、WORD 8、DWORD 16），WHILE 错位减半必归 0，无死循环、无越位移——全部通过。
