# R16 轮次规划（ROUND PLAN R16）—— T0 快车道：IEC 标准语义防御包装 20 件

> 规划人：工控代码库产品总监 ｜ 日期：2026-11-16 ｜ 轮次：R16（阶段一+二，只规划不编码）
> 性质：**T0 = IEC 61131-3 标准函数/功能块的防御性包装**，内部委托平台内建函数/运算符，外围统一错误码、钳位、双语注释，**严禁重实现数学内核**。
> 文件头溯源统一标注「IEC 61131-3 标准语义的道莅防御性实现」；function_tags 必含 `iec-std-wrapper`。**T0 组零 WebSearch**。
> 码位游标：R15 止于信息级 01BF / 故障级 028D；本轮分配 **信息级 01C0~01E7、故障级 028E~02C9**，R17 顺延 01E8 / 02CA。
> 待办池状态：ROADMAP 行业池未勾选 326 条 ≥30，本轮不补写待办。

## 立项取舍说明（否决与调整记录）

1. **16 位 BCD 双向件否决重复**：`FC_DL_BcdToWord` / `FC_DL_WordToBcd` 已于 R9 入库（LGF Converter 组），本轮不重做 16 位 BCD；改立 **32 位 BCD 双向件**（8 位十进制，99999999 域），工程语义不重叠。
2. **`IntToBcd`（有符号 BCD）否决**：有符号 BCD 符号位约定各平台分歧（符号半字节位置/极性不一），防御包装无法给出统一语义，不做无意义重载。
3. **TIME 算术防御族补位（4 件）**：TIME 的 +/−/×/÷ 在溢出与负值行为上各平台不一致（与 TON 负 PT 同类问题），属有工程意义的 T0 防御域。
4. 全部 20 件为纯函数（无状态），统一用 **FC_** 前缀，全部落 **DL_MathData**（数值转换/选择/极值/TIME 算术均属 Level 0 纯数值计算）。

## 20 件派单总表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_LrealToRealSat | DL_MathData/Convert | FC_DL_ | LREAL→REAL 幅值域饱和（防 ±Inf） | iec-std-wrapper, sat-convert | 低 | 1 |
| 2 | FC_DL_LrealToDintSat | DL_MathData/Convert | FC_DL_ | LREAL→DINT 域外饱和不回绕 | iec-std-wrapper, sat-convert | 低 | 1 |
| 3 | FC_DL_RealToUdintSat | DL_MathData/Convert | FC_DL_ | REAL→UDINT 负值钳 0 + 上溢饱和 | iec-std-wrapper, sat-convert | 低 | 1 |
| 4 | FC_DL_RealToUintSat | DL_MathData/Convert | FC_DL_ | REAL→UINT 0~65535 饱和 | iec-std-wrapper, sat-convert | 低 | 1 |
| 5 | FC_DL_RealToByteSat | DL_MathData/Convert | FC_DL_ | REAL→BYTE 0~255 饱和（串口/PWM 字节域） | iec-std-wrapper, sat-convert | 低 | 1 |
| 6 | FC_DL_DintToUintSat | DL_MathData/Convert | FC_DL_ | DINT→UINT 负值钳 0 + 上溢饱和 | iec-std-wrapper, sat-convert | 低 | 2 |
| 7 | FC_DL_UdintToDintChk | DL_MathData/Convert | FC_DL_ | UDINT→DINT 超 2147483647 饱和 | iec-std-wrapper, sat-convert | 低 | 2 |
| 8 | FC_DL_LintToLrealChk | DL_MathData/Convert | FC_DL_ | LINT→LREAL 超 2^53 精度丢失信息码（值照转） | iec-std-wrapper, sat-convert | 低 | 2 |
| 9 | FC_DL_BcdToUdint | DL_MathData/Convert | FC_DL_ | 8 位 BCD→UDINT，非法半字节检测 | iec-std-wrapper, bcd-convert | 中 | 2 |
| 10 | FC_DL_UdintToBcd | DL_MathData/Convert | FC_DL_ | UDINT→8 位 BCD，>99999999 饱和 | iec-std-wrapper, bcd-convert | 中 | 2 |
| 11 | FC_DL_SelEx | DL_MathData/Sel | FC_DL_ | IEC SEL 防御包装：二选一 + 通道有限性检查 | iec-std-wrapper, sel-mux | 低 | 3 |
| 12 | FC_DL_Mux2Ex | DL_MathData/Sel | FC_DL_ | IEC MUX 防御包装：2 通道 + 选择子钳位 | iec-std-wrapper, sel-mux | 低 | 3 |
| 13 | FC_DL_Mux4Ex | DL_MathData/Sel | FC_DL_ | IEC MUX 防御包装：4 通道 + 选择子钳位 | iec-std-wrapper, sel-mux | 低 | 3 |
| 14 | FC_DL_MinEx | DL_MathData/MinMax | FC_DL_ | IEC MIN 防御包装：双值取小 + 非有限拦截 | iec-std-wrapper, minmax-limit | 低 | 3 |
| 15 | FC_DL_MaxEx | DL_MathData/MinMax | FC_DL_ | IEC MAX 防御包装：双值取大 + 非有限拦截 | iec-std-wrapper, minmax-limit | 低 | 3 |
| 16 | FC_DL_LimitEx | DL_MathData/MinMax | FC_DL_ | IEC LIMIT 防御包装：限幅 + 上下限倒置自动交换 | iec-std-wrapper, minmax-limit | 低 | 4 |
| 17 | FC_DL_TimeAddSat | DL_MathData/TimeArith | FC_DL_ | TIME+TIME 溢出饱和至 TIME 上限 | iec-std-wrapper, time-arith | 中 | 4 |
| 18 | FC_DL_TimeSubSat | DL_MathData/TimeArith | FC_DL_ | TIME−TIME 负差钳 T#0s | iec-std-wrapper, time-arith | 低 | 4 |
| 19 | FC_DL_TimeScaleSat | DL_MathData/TimeArith | FC_DL_ | TIME×INT 乘积溢出饱和 + 负乘子钳 0 | iec-std-wrapper, time-arith | 中 | 4 |
| 20 | FC_DL_TimeDivChk | DL_MathData/TimeArith | FC_DL_ | TIME÷INT 除零守卫 + 负除子取模长记录 | iec-std-wrapper, time-arith | 低 | 4 |

## 批次依赖说明

四批均为 Level 0 纯函数，**批间无编译依赖**，按批切分仅为并行派单与验收节奏；批内同族同模板，批 1/2（转换族）、批 3（选择/极值族）、批 4（LIMIT+TIME 算术族）。每件 5 个码位槽（信息级 2 + 故障级 3，含预留槽），逐件码值见派单规格。
