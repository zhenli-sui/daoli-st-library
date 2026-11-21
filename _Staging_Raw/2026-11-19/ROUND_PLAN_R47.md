# R47 阶段一目标锁定（20 件）

生成：2026-11-19 23:4x ｜ 基线：总库 825 / 10,000 ｜ 今日 155/200 ｜ registry v2.38.0
前置：本线已完成 R46 五抽语义终审（4 件挂 v1.0.1 返修，见本轮战报）与零码位专项（结论：维持零码位）。

## 0. 选题纪律声明

- **零同名反证（R240）**：下列 20 名全部对 `INDEX_REGISTRY.json` components[].name 与 `DL_*\*.st` 文件树做 grep 反证，**20/20 零命中**（2026-11-19 23:4x 实测，alternation 一次扫全库）。反证句逐条附于表内。
- **同义邻件双查（R28）**：候选剔除 1 名——`FB_DL_SteamTrapSurvey`（与既有 `FB_DL_SteamTrapDiagTrend` 语义重叠，以 `FB_DL_TrayerNestingCtrl` 替位）；`FB_DL_ChamberPumpDownSeq` 与 R46 `FB_DL_ModulePottingVac` 边界已声明（腔体抽真空漏率复测 ≠ 灌胶脱泡四相，不同属主）；`FB_DL_EfEmoInterlock` 与 `FB_DL_InterlockMatrix`（通用矩阵）边界：EFEM 域专用条件源，不内嵌通用件判据。
- **品类纠偏**：MathData 1 件（≤2 达标）；Motion 2 件转传动精度族（双反馈族 R46 已收口 3 件，监控/评分/切换序三分属主已定）；Algo 本轮 0 件（R46 已 4 件，配额轮转）；Device 4、Process 11。
- **批次约束**：4 批 × 5，批内零 `.st` 文件级依赖（全部叶子件，仅引用既有存量类型或纯 Standard.library）。

## 1. 20 件目标清单

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 | 码位 |
|---|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_IntFloorDiv` | DL_Base | FC | 整数向下取整除法（与 R46 IntCeilDiv 成对；负数向 −∞ 取整语义显式，零除/同余/边界四向量自证） | T0 防御包装 | 2 | 1 | ZERO-CODE |
| 2 | `FC_DL_ByteArrayXor` | DL_Base | FC | 字节数组异或校验和（BCC，串口协议尾校验；空数组拒算、长度上限防扫爆） | T0 防御包装 | 2 | 1 | ZERO-CODE |
| 3 | `FC_DL_CovarOnline` | DL_MathData | FC | 双信号在线协方差（Welford 协方差增量式，单遍免二次遍历；非有限样本前置剔除） | T2-1 LGF · Measurement ◐ | 4 | 1 | ZERO-CODE |
| 4 | `FB_DL_TrayerNestingCtrl` | DL_Process | FB | 电芯托盘堆叠嵌套调度（层数/列数/NG 通道避让，复用 `FB_DL_LifoStack`） | ROADMAP 空勾真缺口 P2 | 5 | 1 | ZERO-CODE |
| 5 | `FB_DL_OcvTempNormalize` | DL_Process | FB | OCV 测试温度归一判据（复用 `FC_DL_TempUnitConvert` 语义 + 合格带判定） | ROADMAP 空勾真缺口 P1 | 4 | 1 | ZERO-CODE |
| 6 | `FB_DL_ElectrolyteFifoTrace` | DL_Process | FB | 注液批次 FIFO 追溯队列（批次结构体队列 + 条码绑定，防重复入队） | ROADMAP 空勾真缺口 P1 | 5 | 2 | ZERO-CODE |
| 7 | `FB_DL_StringFifoRetry` | DL_Process | FB | 电池串缓存队列重试出站（丢新策略 + 重试计数上限 + 出站握手） | ROADMAP 空勾真缺口 P1 | 5 | 2 | ZERO-CODE |
| 8 | `FB_DL_TempCompClassify` | DL_Process | FB | 组件功率温度补偿分档（温补归一 + 四档分级，档间迟滞防抖） | ROADMAP 空勾真缺口 P1 | 4 | 2 | ZERO-CODE |
| 9 | `FB_DL_TankBlanketPrCtrl` | DL_Device | FB | 储罐氮封压差监测联动（双表冗余判据复用 RedundantSwitch 语义 + 低压联锁） | ROADMAP 空勾真缺口 P2 | 5 | 2 | ZERO-CODE |
| 10 | `FB_DL_IvBcdExport` | DL_Device | FB | IV 测试仪 BCD 拨码设定导出（面板互转语义 + 导出握手与回读校验） | ROADMAP 空勾真缺口 P2 | 3 | 2 | ZERO-CODE |
| 11 | `FB_DL_RfidTrayRoute` | DL_Process | FB | 载具 RFID 身份驱动路径路由（读码 + 段间握手 + 未知载具拒路由） | ROADMAP 空勾真缺口 P1 | 6 | 3 | ZERO-CODE |
| 12 | `FB_DL_FoupRfidCheck` | DL_Process | FB | FOUP 身份校验与配方放行（读码 + 配方校验链 + 校验失败锁存） | ROADMAP 空勾真缺口 P1 | 5 | 3 | ZERO-CODE |
| 13 | `FB_DL_ChuckVacuumSeq` | DL_Process | FB | 卡盘真空吸附/释放序（吸附-确认-加工互锁-释放四段 + 到位判据 + 破空超时） | ROADMAP 空勾真缺口 P1 | 6 | 3 | ZERO-CODE |
| 14 | `FB_DL_ChamberPumpDownSeq` | DL_Process | FB | 腔体抽真空顺控与漏率复测（段时序 + 压降判据 + 放气限速语义；与 ModulePottingVac 分属主） | ROADMAP 空勾真缺口 P1 | 7 | 3 | ZERO-CODE |
| 15 | `FB_DL_EfEmoInterlock` | DL_Process | FB | EFEM 机械手互锁矩阵（门/阀/真空/位置四类条件源 + 首因追踪；与 InterlockMatrix 分工：域专用条件源） | ROADMAP 空勾真缺口 | 5 | 3 | ZERO-CODE |
| 16 | `FB_DL_LaminatorZoneSync` | DL_Process | FB | 层压机多温区联动升温（分级投切语义 + 串级温度闭环 + 区间温差联锁） | ROADMAP 空勾真缺口 P1 | 6 | 4 | ZERO-CODE |
| 17 | `FB_DL_R2rRunLogAudit` | DL_Process | FB | R2R 调参批次审计算账（调参量快照 + 变更留痕 + 可追溯台账） | ROADMAP 空勾真缺口 P1 | 5 | 4 | ZERO-CODE |
| 18 | `FB_DL_CassetteBcdLabel` | DL_Device | FB | 花篮 BCD 拨码标签机联动（拨码生成 + 扫码枪语义 + 打印同步握手） | ROADMAP 空勾真缺口 P2 | 4 | 4 | ZERO-CODE |
| 19 | `FB_DL_AxisBacklashIdent` | DL_Motion | FB | 反向间隙在线辨识（双向换向残差统计 + 中值估计 + 激励不足拒辨识） | 自研线（传动精度族开族） | 6 | 4 | ZERO-CODE |
| 20 | `FB_DL_AxisCoggingFf` | DL_Motion | FB | 齿槽转矩前馈（按角度周期查表注入 + 表学习使能分离 + 注入限幅） | 自研线（与 AxisFrictionFf 成族） | 6 | 4 | ZERO-CODE |

## 2. 零同名反证句（逐条，registry grep + DL_* 文件树 grep 双向零命中）

1. `FC_DL_IntFloorDiv` — registry grep 0 命中，DL_Base 无同名文件；与 `FC_DL_IntCeilDiv`（R46）成对，方向语义互补不重叠。
2. `FC_DL_ByteArrayXor` — registry 0、文件树 0；与 `FC_DL_Crc16Modbus`/`LrcChecksum` 不同（BCC 异或 ≠ CRC/LRC）。
3. `FC_DL_CovarOnline` — registry 0、文件树 0；`FB_DL_SignalStatistics` 为单信号多统计量聚合，本件为双信号协方差原子件。
4. `FB_DL_TrayerNestingCtrl` — registry 0、文件树 0（R46 曾让位配额，非撞名弃选）。
5. `FB_DL_OcvTempNormalize` — registry 0、文件树 0。
6. `FB_DL_ElectrolyteFifoTrace` — registry 0、文件树 0；与 `FB_DL_ElectrolyteDosingTrend`（趋势判据）分工不同。
7. `FB_DL_StringFifoRetry` — registry 0、文件树 0；`FB_DL_FifoBuffer` 为底层数据结构，本件为工艺出站编排件。
8. `FB_DL_TempCompClassify` — registry 0、文件树 0。
9. `FB_DL_TankBlanketPrCtrl` — registry 0、文件树 0；与 `FB_DL_TankLevelCtrl` 等液位族无重叠（氮封压差域）。
10. `FB_DL_IvBcdExport` — registry 0、文件树 0；`FC_DL_WordToBcd` 为纯转换函数，本件为导出联动 FB。
11. `FB_DL_RfidTrayRoute` — registry 0、文件树 0；`FB_DL_RfidTagHandler` 为读码头驱动，本件为路由编排。
12. `FB_DL_FoupRfidCheck` — registry 0、文件树 0；与 RfidTrayRoute 分工：配方放行校验 ≠ 路径路由。
13. `FB_DL_ChuckVacuumSeq` — registry 0、文件树 0；与 `FB_DL_VacCupRingCtrl`/`VacuumChamberSeq` 不同域（卡盘加工互锁）。
14. `FB_DL_ChamberPumpDownSeq` — registry 0、文件树 0；与 R46 `FB_DL_ModulePottingVac` 属主边界已声明。
15. `FB_DL_EfEmoInterlock` — registry 0、文件树 0；与 `FB_DL_InterlockMatrix` 边界：域条件源 ≠ 通用矩阵。
16. `FB_DL_LaminatorZoneSync` — registry 0、文件树 0。
17. `FB_DL_R2rRunLogAudit` — registry 0、文件树 0；`FB_DL_R2rEwmaTuner` 为调参执行件，本件为审计算账件。
18. `FB_DL_CassetteBcdLabel` — registry 0、文件树 0；与 `FB_DL_IvBcdExport` 分工：标签打印联动 ≠ 设定导出。
19. `FB_DL_AxisBacklashIdent` — registry 0、文件树 0（无 `*Backlash*`）。
20. `FB_DL_AxisCoggingFf` — registry 0、文件树 0（无 `*Cogging*`）；与 `FB_DL_AxisFrictionFf`（摩擦前馈）成族分工。

## 3. 每件需求规格（功能 / 边界安全 / 红线要点）

**全局 7 项红线要点（每件必过，不逐条重复）**：① 命名前缀与变量前缀表；② 零 GVL/VAR_EXTERNAL/%I/%Q/%M，外部数据全走引脚；③ 纯 IEC 61131-3 + Standard.library；④ ENUM+CASE 状态机含 ELSE 兜底，TON/R_TRIG/TP 段 0 无条件刷新；⑤ 防除零/数组边界/浮点禁 = 判等（ABS 差容差）/WHILE 计数器；⑥ 100% 中文注释 + 头部七要素 + 单位标注；⑦ 无魔法数（阈值提为带单位输入或 VAR CONSTANT）。
**零码位范式（R46 规则延续）**：编码禁 16# 事件码（通道位掩码类常量除外且须头注释声明非事件码），出口 BOOL+ENUM，码位待收口统一派号。
**属主边界先行**：每件头注释写死「只管 X / 不接管 Y」。

| 序号 | 功能规格要点 | 边界安全条件 |
|---|---|---|
| 1 | IntFloorDiv：nNum/nDen → 向 −∞ 取整商；`nDen=0` 拒算返回 0 并置 bInvalid（当拍）；同余（nDen 整除）不偏移；负数四向量：(+7,+2)=3、(−7,+2)=−4、(+7,−2)=−4、(−7,−2)=3；与 IntCeilDiv 反证向量互检 | 零除闸 `nDen=0`；MIN_INT/-1 溢出钳位返回 MIN_INT 并置溢出位；禁 TRUNC(x)+1 写法（R28 整数进位点） |
| 2 | ByteArrayXor：aBytes 数组逐字节异或出 BYTE；uLen=0 拒算返回 16#00 并置 bInvalid；uLen 上限常量防扫爆 | 数组边界下界钳 0、上界钳 uLen 声明域；uLen>数组实际长度由调用者保证（IN_OUT 语义声明） |
| 3 | CovarOnline：fX/fY 双流窗口协方差；Welford 增量：_fMeanX/_fMeanY/_fC/_nCnt 单遍更新；nCnt<2 不宣称 | 非有限样本当拍剔除不累加；nCnt=0/1 分母闸；输出 fCovar 钳位 ±fCovarMax |
| 4 | TrayerNestingCtrl：层×列网格占位调度，NG 通道跳位，栈满锁存 | 网格越界钳位；LifoStack 满拒入栈；层数/列数=0 组态闸锁存 |
| 5 | OcvTempNormalize：OCV 实测按温度系数归一到基准温度再判合格带；带外分档 | 温度系数除零闸（系数=0 拒归一）；归一值钳位；浮点容差判等 |
| 6 | ElectrolyteFifoTrace：批次号+条码绑定入队，出队按序，重复条码拒入 | 队满锁存拒入；条码空串拒入；出队空队不宣称（R41 式）；WHILE 防死锁计数 |
| 7 | StringFifoRetry：重试出站，nRetries 上限锁存 NG，丢新策略队满保旧 | 重试上限提为输入；握手超时 TON 段 0 刷新；单拍脉冲 R24/R25 三律 |
| 8 | TempCompClassify：功率温补归一 + 四档分级输出 | 档间迟滞带必配（防临界抖动）；温补系数零闸；分档边界浮点容差 |
| 9 | TankBlanketPrCtrl：双表压差冗余判据 + 氮封低压联锁出阀 | 双表偏差超限锁存选单表；压差标定除零闸；阀输出限幅 |
| 10 | IvBcdExport：设定值 BCD 编码导出 + 回读比对 | 非 BCD 半字节拒导出；回读超时 TON；握手单拍脉冲三律 |
| 11 | RfidTrayRoute：读码 → 路由表匹配 → 段间握手放行 | 未知载具拒路由锁存；路由表越界钳位；重复读码防抖 |
| 12 | FoupRfidCheck：身份+配方校验链放行 | 校验失败锁存（R228B 唯一迁出=复位沿）；读码超时 TON 段 0 |
| 13 | ChuckVacuumSeq：吸附→到位→加工互锁→释放四段 | 真空到位确认窗；破空超时判据；加工中禁释放（互锁先于顺控） |
| 14 | ChamberPumpDownSeq：抽气→保压→漏率复测→放气限速四段 | 漏率=Δp/Δt 分母时间零闸；放气限速斜率钳位；属主边界写死（≠ModulePottingVac） |
| 15 | EfEmoInterlock：四类条件源汇总 + 首因编号追踪 | 条件源数组边界；首因锁存唯一（R190）；域边界写死（≠InterlockMatrix） |
| 16 | LaminatorZoneSync：多温区分级投切 + 串级联动 + 区间温差联锁 | 温差联锁阈值带迟滞；分区数=0 组态闸；分级最小驻留 |
| 17 | R2rRunLogAudit：调参量快照 + 变更沿留痕 + 台账计数 | 快照缓冲满锁存；变更沿 R_TRIG 段 0；台账计数饱和 |
| 18 | CassetteBcdLabel：拨码生成 + 打印同步握手 | BCD 半字节校验；打印超时 TON；忙时拒新任务 |
| 19 | AxisBacklashIdent：换向残差统计 → 中值 → 间隙估计 | 速度激励不足拒辨识（迹/样本数双闸）；换向沿 R_TRIG 段 0；估计值钳位；属主：只辨识不注入 |
| 20 | AxisCoggingFf：角度周期查表前馈 + 学习/注入分离 | 相位取模防越界（索引钳 0..N-1）；注入限幅；学习态禁注入（互斥锁存）；与 AxisFrictionFf 边界：齿槽(角度周期) ≠ 摩擦(速度函数) |

## 4. 批次依赖自检与派发顺序

| 批次 | 件数 | 内部依赖 | 结论 |
|---|---|---|---|
| B1 | 5 | 无（IntFloorDiv/ByteArrayXor/CovarOnline 为叶子；Nesting/Ocv 仅语义复用存量件） | 可并行派单，最先派发 |
| B2 | 5 | 无 | 可并行派单 |
| B3 | 5 | 无 | 可并行派单 |
| B4 | 5 | 无（BacklashIdent 与 CoggingFf 并列不互引） | 可并行派单 |

派发顺序：B1 → B2 → B3 → B4（低层先行的全局纪律；B1 内两 Base 件优先）。

## 5. 分布核验

Process 11 / Device 4 / Motion 2 / Base 2 / MathData 1 / Algo 0 = **20**。
约束核验：MathData ≤2 ✓ ｜ Device ≥3 ✓ ｜ Process ✓ ｜ Motion 2（双反馈族 R46 已补 3 件，本轮转传动精度族开族）｜ Algo 0（R46 已 4 件，配额轮转让位，R48 回补观测器/自适应族深化）。

## 6. 零码位决策登记（Task B 结论，主控线核定）

- **维持零码位**：R46 20 件 + 本轮 R47 20 件出口一律 BOOL+ENUM（eState/eCause 归因唯一），不派 16# 事件码。
- 依据：① 五抽实读确认 R46 件出口全为 BOOL+ENUM，唯一 16# 出现在 TabWeldingMonitor 通道位掩码常量（头注释已声明非事件码）；② 全库 grep `16#[0-9A-F]{4}` 确认 DL_Process 存量大量占用（149 件口径吻合），窗口余量紧张，无收益不扩占用；③ 派号收益依赖「全局事件码总线/NE107 汇总层」立项，该层未立项前派号即空转。
- 登记：决策记入本轮战报；`code_segment` 统一回填维持 R46 战报 P2 待办，触发条件 = 事件码总线层立项。
