## R86 审校结论
审校件数=40（全量，非抽样） PASS=30 BLOCK=1 MAJOR=1 MINOR=10（缺陷条目 12，涉 10 件）

## 12 项扫查证据表
| 项 | 命中缺陷数 | 代表件 + 行号证据 |
|---|---|---|
| 1 除零防护 | 0 | Trapezoid:109/112/115/158（fDt/fVelMax/fAccMax/fVp 四闸）；Level:56；Piecewise3:54+78（跨度已证>EPS 才除）；Deadband:70+81；Q15DivSafe:33 |
| 2 数组越界 | 0 | SensorConsensus:87（nCnt 仅 k<5 递增，上界 4）；Piecewise3:45/53/59-64（0..3 断点遍历 + k:75-77 上界兜底）；Q15Biquad:58-61/66（0..4 常量索引）；SatSumArrayDint:40-45（nCnt 双向截断） |
| 3 浮点容差 | 0 | Trapezoid:118/121/124/207/220 全用 DL_EPS；Piecewise3:54 用 DL_MW_EPS；HystSwitch:45 用 DL_MH_EPS |
| 4 非有限值拦截 | 3 | Trapezoid:100-129 无 NaN/Inf 闸 → 216 `fPosCmd := fSgn * fS;` 输出 NaN（MAJOR）；MapRangeClamped:38+80 哨兵取 fOutMin；SatClampLrealBand:31 返回 fMin 哨兵（MINOR） |
| 5 整数溢出先判界 | 0 | SatAddDint:26/29 双侧直比；SatSubDint:25/28；SatMulDint:50/57（DINT_MIN 单独分支 + MAX/ABS 整除判据）；SatSumArrayDint:49/53 |
| 6 CASE ELSE 兜底 | 0 | Trapezoid:249-254；AxisProbe:204-208；SensorConsensus:170-175；9 件单位换算件 ELSE 均归零哨兵 + 返回 FALSE |
| 7 TON/R_TRIG 无条件刷新 | 0 | AxisProbe:84 `tonTimeout(...)`、85 `tonDwell(...)` 均在 CASE（line 91）之外 |
| 8 复位态输出确定性 | 1 | AxisProbe:134 `fVelCmd := fFastVel;`（撤使能后仍输出速度指令，见 BLOCK） |
| 9 死代码/不可达 | 2 | Q15Biquad:125-126 arrHist[2]/[3] 只写不读；Q15MulSat:35/38 反算分支恒假（diProd∈[-1.074e9,1.074e9]） |
| 10 自赋值/无效语句 | 1 | SensorConsensus:83/85 `fTmp := DL_CM_R0;` 赋值后即丢弃（fTmp 于 97 重写） |
| 11 注释双语 + 分号 | 0 | 40/40 件变量均带中英双注；语句分号齐（L2 编译闸 40/40 佐证） |
| 12 魔数常量化 | 2 | Trapezoid:194/203 `0.5` 字面量；SensorConsensus:114/120/136 `2.0`、Deadband:82-83 `1.0` 字面量 |

## 缺陷清单（按严重度）
### BLOCK（必须拒收/回派）
- **FB_DL_AxisProbeTouchOffSeq** ｜ 头注 line 36 契约「FALSE 时任意相立即回空闲」 vs 实现｜**安全侧**：全件仅 eIdle:94 判 `xEnable`，eFastApproach/eSlowApproach/eRetract/eDwell 均无使能闸，撤使能后仍持续下发速度。证据原文：
  - L36 `xEnable : BOOL := TRUE;   // 使能，FALSE 时任意相立即回空闲 [—] / Enable, false resets to idle from any phase`
  - L134 `fVelCmd := fFastVel;                              // 快进速度指令 [mm/s] / the fast approach velocity command`
  - L176 `fVelCmd := -fSlowVel;                             // 反向回退速度指令 [mm/s] / the negative retract velocity command`
  - 对照 Trapezoid:186 有 `IF NOT xEnable THEN ... fVelCmd := DL_ZERO;` 正确写法。修法：四个运动相各补 `IF NOT xEnable THEN eState := eIdle; fVelCmd := 0;`（行为变更，故不就地修）。

### MAJOR（挂账，不阻塞入库）
- **FB_DL_TrapezoidProfilePlanner** ｜ 无 NaN/Inf 闸 → 假有效 + NaN 指令外发：fDist=NaN 时 118/121/127/133/140/164 全部比较为假，xParamBad 保持 FALSE，L176 `xValid := TRUE;` 成立，L216-217 输出 NaN 位移/速度指令给轴（历史 PmvComfortIndex 同型）。若总监将运动指令 NaN 纳入安全侧口径，应升 BLOCK。建议下轮加 `IF (fDist<>fDist) OR (ABS(fDist)>1.0E30) THEN xParamBad := TRUE;` 一组入口闸。

### MINOR
- Q15BiquadFilter:125-126｜arrHist[2]/[3]（上拍输入/输出）写后无任何读取，死状态（项 9）。
- Q15MulSat:35/38｜反算溢出分支恒假，且 `DL_QM_LO := -2147483647` 非 DINT 真下界（顶注已称"近似"），属无效防御（项 9）。
- SensorConsensusSelector:83/85｜`fTmp := DL_CM_R0;` 无效赋值（项 10）。
- MapRangeBipolar:63-68｜反向量程（fInMin>fInMax）未判非法，钳位方向按正向假设，越界输入钳到错误端点且 xBad=FALSE（兄弟件 Clamped:69-76 已正确处理，口径不一致）。
- MapRangeClamped:38+80｜非有限输入时哨兵取 fOutMin，若该端点本身非有限则输出 NaN（项 4 残余）。
- MapRangeDeadband:44+93｜同上，哨兵取 fOutMin。
- SatClampLrealBand:31｜非有限输入返回 fMin 哨兵而非零（同族其他件归零，口径不一）。
- SatSumArrayDint:41/44｜就地改写 VAR_INPUT `nCnt`（跨方言风险，建议改局部副本）。
- TrapezoidProfilePlanner:194/203｜`0.5` 未进 VAR CONSTANT（项 12）。
- SensorConsensusSelector:114/120/136、MapRangeDeadband:82-83｜`2.0`/`1.0` 字面量未常量化（项 12）。

## 三道去重（脚本真跑，registry=1686）
- **名称道**：规范化（去 FB_/FC_/DL_ 前缀）后**精确撞名 0 件**；近义邻件命中 6 组：SatAddDint↔FC_DL_SaturateAdd、**SatSubDint↔FC_DL_SaturateSub（真重复）**、SatMulDint↔FC_DL_SaturateMul、Q15DivSafe↔FC_DL_SaturateDiv、Lerp↔FC_DL_LerpClamped、AbsSat↔FC_DL_AbsEx、ClampLrealBand↔FC_DL_ClampDintChk。
- **签名道**：40 件指纹已落 `dedup_report.json`；同指纹组 3 组（Q15 二元算术组、MapRange 双端量程组、Sat-LREAL 组），均因**函数体语义不同**判假阳性（例：Q15AddSat 为 INT 域 Q15 定标，SaturateAdd 为 DINT 组态界 + BOOL 状态出口），未凭指纹拒收。
- **语义道**：存疑 2 件，逐条结论：
  1. `FB_DL_Q15BiquadFilter` vs 在册 `FB_DL_SecondOrderFilter`/`FB_DL_BiquadFilter`：**有效变体，放行**。已核实真定点化——系数 `ARRAY[0..4] OF INT`（L22）、中间 `DINT`（L66-68 乘积 Q30）、移位用 `(diAcc±16384)/32768`（L70/72）、输出 Q15 饱和（L74-82）、DF2T 两段式状态提交（L124-128）。无浮点、无库依赖，与浮点 Butterworth 件非同一物。
  2. `FC_DL_MapRange*` 族 vs 在册 `FC_DL_LinearScale`：**Clamped 一件存疑放行**（差异=LREAL 精度变体 + 反向量程 + 非有限闸，命中防误杀红线）；SatOut 因 fSatMin/fSatMax 为**独立于输出量程的第二个饱和域**（L88-97），LinearScale 无此语义，明确非重复。Bipolar/Percent/InverseSolve/Piecewise3/Deadband/HystSwitch/IntQuant 语义各自独立（对称映射/方向枚举/反解/折线/死区/滞环/量化），全部放行。
  另外核实 `FC_DL_TempDiffUnitConvert` vs 在册 `FC_DL_TempUnitConvert`（后者含 -273.15 偏移、32/9/5 温标换算）：**有效变体，放行**——本件 L33-34/L49/L52 全为纯比例无偏移，温差语义正确（C→K ×1、F→K ×5/9）。

## 拒收判定
拒收 **1 件**：`FC_DL_SatSubDint` —— 与在册 `FC_DL_SaturateSub` 真重复：返回类型同为 `DINT`、入参同形（两个 DINT）、饱和域同为 DINT 域（`DL_SBS_MIN := DINT#16#80000000` / `DL_SBS_MAX := 2147483647`）、语义同为"减法越界钳到 DINT 上下界"，差异仅为命名与 `xSat` 输出位；无法说出新增工程价值。建议回派改为"补 `bError` 族级口径"或直接并入 SaturateSub。
（同族 SatAddDint / SatMulDint **不拒收**：接口形态与在册件不同（2 入参→直接返回值 vs 4 入参/状态位出口），列入存疑放行。）

**存疑放行清单（供总监复议）**：FC_DL_SatAddDint、FC_DL_SatMulDint、FC_DL_MapRangeClamped。

## 一句话结论
40 件全量扫查：编译与除零/溢出/数组三类硬闸已全面达标，唯一安全侧硬缺陷是探针状态机撤离使能不停机（BLOCK，1 件）；另 1 件运动规划器缺非有限闸会假报 xValid 并外发 NaN 指令（MAJOR）；去重侧仅 SatSubDint 与在册 SaturateSub 真重复，应拒收 1 件，Q15 定点滤波与温差换算两处边界经源文核实为有效变体，未误杀。
