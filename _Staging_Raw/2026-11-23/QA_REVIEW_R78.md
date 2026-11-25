# QA_REVIEW_R78（A 批 30 件，2026-11-23，审校去重席）

对象：DL_MathData 24 件 + DL_Base 6 件（ROUND_PLAN_R78 序号 1~35 中 A 批 30 件；GATE_R78_A.md 不存在，以 ROUND_PLAN_R78.md 为准）。30/30 全文阅读；逐行细读 5 件：RoundToMultipleInt、PressureUnitConvert、BcdAddByte、QuantizeStepReal/SnapToStepLreal、Parity 族。B2 批（RateLimitReal 等 6 件）不在本批。

## 结论总览
PASS 27 / 拒收 3（去重拦截 3）/ MAJOR 1 / MINOR 2 / BLOCK 0。

## 12 项扫查（全 30 件，仅列异常，其余 PASS）
- 头注/溯源：序号 1~8 八件均有 TcDynStringKit + MIT 溯源行（如 CharIsDigit.st:8-10）；self-std 件免溯源行，合规。
- R1/R2：全部零 GVL、零 %I/%Q；VAR_CONSTANT 均为函数内局部常量（DL_Q_SAFE_MAX 三件重名，作用域隔离，不构成 GVL 冲突）。
- 枚举成员 `:=`：E_DL_PressureUnit(:15)/E_DL_ForceUnit(:15)/E_DL_TimeUnit(:15) 首成员显式赋值 ✓。
- CASE ELSE 兜底：三件单位换算均有源/目标双 ELSE 分支 ✓。
- 显式转换：BYTE_TO_INT/INT_TO_BYTE/REAL_TO_DINT/LREAL_TO_LINT/LINT_TO_LREAL 全显式，零 LREAL(x) 构造式 ✓。
- 除零闸：TruncToMultipleInt(:19-22)、RoundToMultipleInt(:24-27) 等全部先闸 nMultiple/fStep<=0 ✓；单位换算分母全为字面常量 ✓。
- 变量声明分号、无 PROPERTY、无 VLA：全 PASS。

## 缺陷清单
- **MAJOR-1** FC_DL_RoundToMultipleInt.st:33（及 :36 镜像）——进位/退位无 DINT 饱和闸：nValue=2147483647, nMultiple=2 时 nRem=1=nHalf 且偶 → nLo+nMultiple=2147483648 回绕为 -2147483648（静默错值）；负向 nValue=-2147483648, nMultiple=3 同理回绕。同族 CeilToMultipleInt(:28-32)/FloorToMultipleInt(:28-32) 均有反算饱和闸，本件模板派生时闸位未随语义继承。挂账下轮（非编译阻断、行为变更非零，不就地修）。
- **MINOR-1** Parity 族 vs 在库 FC_DL_ParityCalc 口径相反：ParityCalc.eEven 在 1 计数为**奇**时返回 TRUE（校验位语义，ParityCalc.st:76-77）；新件 ParityEven* 在 1 计数为**偶**时返回 TRUE（谓词语义，ParityEvenByte.st:29）。同库同词 "Even" 语义相反，混用风险。挂账：六件头注补一行与 ParityCalc 的口径区分声明。
- **MINOR-2** RoundToMultipleReal.st:31-34（QuantizeStepReal 同）——fQ 溢出为 Inf 时 `fQ*fMultiple` 返回 Inf，头注契约"按原值近直返"（:8）与实际不符（在库 QuantizeStep.st:85-90 精确域闸为原值直通）。挂账：契约措辞修正或改原值直通。

## 拒收清单（去重拦截，附最近邻比对）
1. **FC_DL_PressureUnitConvert** ✂ 语义重复于在库 **FC_DL_PressUnitConvert**（R50，DL_MathData:79-165）。两者同为"压力单位枚举源/目标互转"，单位集交集 kPa/Bar/Psi；在库件为严格超集（多 Pa/mmHg、LREAL 精度、非有限双判闸 :109-113、真空下限钳位 :133-136、错误码出口）。新件唯一增量 = MPa 单位 + REAL 精度 + 少量代码行，无新边界/新数据域/新行业约束。名称 Press/Pressure 非精确匹配，绕过了主控的精确名三查——plan:5 "语义邻件避让已核"结论失效。附：其文件内 E_DL_PressureUnit 与在库 E_DL_PressUnit 属同一概念域两套枚举，随件消亡。
2. **FC_DL_SnapToStepLreal** ✂ 语义重复于在库 **FC_DL_QuantizeStep**（R21，DL_MathData:34-121）。两者同为 LREAL 域"吸附到 fStep 步距网格最近格点"（在库 :83-96 商域→取整→回乘，与本件 :32-38 同构）。在库件为超集：舍入模式可选、错误码五枚、残差输出、非法步距**原值直通**（:68-73）；新件非法步距**静默置 0**（:28-30）——比在库件更不防御，无任何新增工程价值。注：用户预案允许的是其 vs QuantizeStepReal 的 REAL/LREAL 变体关系，与在库 QuantizeStep 的同域重复未被预案覆盖。
3. **FC_DL_QuantizeStepReal** ✂ 批内同构重复于本批 **FC_DL_RoundToMultipleReal**：两文件 :24-38 逐行全等（仅形参名 fMultiple↔fStep），"四舍五入到 N 的倍数"与"量化到步距网格"为同一数学运算。保留 RoundToMultipleReal（与族 Round/Ceil/Floor/TruncToMultiple 命名连续，补齐 Int 族的 REAL 位）；**存疑放行复议点**：若总监偏好 Quantize 家族连续性，可反向保留 QuantizeStepReal 拒 RoundToMultipleReal，二者必拒其一，不可双留。

## 有效变体确认（不判重）
- Parity 6 件 vs 在库 FC_DL_ParityCalc（LWORD+nWidth 泛型）：位宽变体（Byte/Word/Dword）+ 极性变体（Even/Odd），用户预案明确允许；类型化固定宽度免去宽度参数误用域。PASS。
- QuantizeStepReal vs SnapToStepLreal：REAL/LREAL 精度变体，预案允许——但两者各自另撞（见拒收 2/3）。
- BcdAddByte/BcdSubByte vs 在库 BcdToByte/ByteToBcd 系列：算术语义 vs 转换语义，不重复。PASS。
- CharIsHexDigit vs CharIsDigit：判定域不同（hex 含 A-F/a-f），非同义。PASS。

## 就地修记录
无（MAJOR-1 涉行为变更，不满足 R333 就地修条件；MINOR 项挂账）。

## 挂账清单（按下轮优先级）
1. [MAJOR] RoundToMultipleInt 补 DINT 饱和闸（对齐 Ceil/Floor 同族写法，含 :33/:36 两分支）。
2. [MINOR] Parity 六件头注补 ParityCalc 口径区分声明。
3. [MINOR] RoundToMultipleReal（及其存留孪生件）Inf 直通契约修正。
4. [流程] 主控"撞名三查"增加同义词根召回（Press/Pressure、Quant/Snap/Round），见 QA_DEDUP_EVOLUTION R462。

## 同族系统性缺陷
未达 ≥3 件同型阈值。最接近者：RoundToMultipleInt 闸位缺失为孤立件（同族另三件闸齐）。
