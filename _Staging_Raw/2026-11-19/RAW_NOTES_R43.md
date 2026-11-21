# RAW_NOTES_R43（第 43 轮 · 2026-11-19）

> 本轮 **零检索（WebSearch 0/3）**，无新增外部源抓取。以下为本轮源使用与合规留痕。

## 1 源使用台账

| 序号 | 组件 | 来源标签 | 源类型 | 许可证 / 合规口径 | 提取点 |
|---|---|---|---|---|---|
| 1 | FB_DL_StakingPressCtrl | roadmap-li-p1 | 自研（ROADMAP 行业池） | 无外部源 | 工序四相（对齐-压紧-保压-泄压）产业常识 |
| 2 | FB_DL_PouchVacuumSeal | roadmap-li-p1 | 自研 | 无外部源 | 真空封装双窗（真空度+温度）工艺顺序 |
| 3 | FB_DL_CalenderRollPress | roadmap-li-p1 | 自研 | 无外部源 | 双侧压下 + 测厚反馈微调 |
| 4 | FB_DL_QuarterCellCutSeq | roadmap-li-p2 | 自研 | 无外部源 | 刀轴相位同步起刀 |
| 5 | FB_DL_CellOcvBinSort | roadmap-li-p1 | 自研 | 无外部源 | 档位映射 + 满仓换道 |
| 6 | FB_DL_IvCurveScan | roadmap-pv-p1 | 自研 | 无外部源 | IV 扫描与 Voc/Isc/FF 定义（公开电学定义） |
| 7 | FB_DL_ChillerCondReset | t1-2-oscat-building | T1 ST 原生 | OSCAT（EPL-2.0 只读思想） | 「按室外工况重置设定」行为定义 |
| 8 | FB_DL_SampleLoopPurge | t1-2-oscat-building | T1 | 同上 | 取样回路三段阀序行为定义 |
| 9 | FB_DL_BundleShrinkTemp | roadmap-pkg-p2 | 自研 | 无外部源 | 收缩包装热风温控双判 |
| 10 | FB_DL_DuctLeakRateEst | t1-2-oscat-building | T1 | 同上 | 漏风率 = 差值/总流量（公开工程口径） |
| 11 | FB_DL_VavPressureReset | t1-2-oscat-building | T1 | 同上 | 最不利末端阀位寻优（公开节能惯例） |
| 12 | FB_DL_ChwDifferentialPressureReset | t1-2-oscat-building | T1 | 同上 | 压差重置律（公开 HVAC 惯例） |
| 13 | FB_DL_SelfDischargeScreen | roadmap-li-p2 | 自研 | 无外部源 | 自放电 K 值分级（产业通用判据） |
| 14 | FB_DL_FanPressureTrim | t2-7-packml | T2 非 ST | OMAC/PackML 公开规范（只借分类） | 「设定微调」在 PackML 控制层的位置语义 |
| 15 | FB_DL_CleanRoomRhTrim | t1-2-oscat-building | T1 | EPL-2.0 只读思想 | 脉冲调制加湿行为定义 |
| 16 | FB_DL_BoilerFlueCondenseGuard | t1-2-oscat-building | T1 | 同上 | 排烟低限联锁（公开锅炉防腐惯例） |
| 17 | FB_DL_CellFeederVacuum | t1-5-tcopen | T1 | Apache-2.0（只借分层思想） | 真空吸盘命令-应答握手语义 |
| 18 | FB_DL_AxisBrakeDistPredict | t1-6-plcopen | T1 | PLCopen 公开规范（只借语义） | Safety-limited 停车距离预判语义 |
| 19 | FB_DL_GearInPhaseAlign | t1-6-plcopen | T1 | 同上 | MC_GearIn 相位对齐语义 |
| 20 | FC_DL_TimeToCycleCeil | iec-std-wrapper | T0 防御包装 | IEC 61131-3 标准语义 | 向上取整语义（委托内建判定，不重实现内核） |

## 2 合规声明

- **零代码行复制**：全部 20 件实现、状态机、码位、引脚命名 100% 本库自有；外部源仅提供「行为定义 / 分类事实 / 参数域 / 分层骨架」。
- **GPL/AGPL**：本轮未触及。
- **闭源源**（西门子 LGF / 罗克韦尔 AOI）：本轮仅 T2-7 PackML 一处引用 OMAC 公开规范，未触及闭源实现。
- **T0 件溯源短语**：#20 头注释已含「IEC 61131-3 标准语义的道莅防御性实现」，**内部委托平台内建 TRUNC 判定，未重实现数学内核**。

## 3 本轮口径教训（供下轮机检脚本复用）

1. **枚举「声明 vs 赋值」必须分开判**：`_eState := E_DL_X.eIdle` 是合法限定赋值；只有 `LHS := E_DL_Type;`（RHS 无 `.member`）才是漏单冒号。旧正则把两者混判，19 件假阳性。
2. **IF 计数必须用 `\bIF\b`**：`(?<!END_)IF` 会命中 `ELSIF` 的后半段，导致结构性假失衡。
3. **UNDECL 检查不可直接对 RHS 标识符做**：枚举成员、类型名、内建函数名都会命中，须先剔除已知符号表。
4. **派单前「先看真样再定性」**：三次误报全部由「先 grep 实际代码行」拦下，未走入返工。此纪律须固化为机检脚本的强制前序。

## 4 未完成项（如实留痕，不静默清账）

- `FB_DL_CassetteMapVerify` 轻返修（R42 挂账）：本轮因时长超限弃做，转 R44 首位。
- 编译验证债：连续 39 轮未开闸（R195 触发条件已满足，需明确裁决）。
- code_segment 历史件回填：588 件为空（本轮新件 20/20 已实填）。
- README 第 412 行汇总表陈旧值（204 / 10,000）：历史遗留，待专项一次性修正。
- 总监抽检（终审）：本轮未启用，顺延 R44。
