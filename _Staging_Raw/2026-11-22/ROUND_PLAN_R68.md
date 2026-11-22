# ROUND_PLAN_R68 — 构建轮规划（2026-11-22，规划线主控直跑 R335）

> 阶段：R68 构建轮规划。配额 **16**（挂账点修已于 R67 清零，按 R328 判据从 12 回调至 16）。
> 选题策略（R67 收尾既定）：ROADMAP 行业池 + 未注册/漂移待办为主力，源矩阵 ◐ 行待挖子项为辅；每件过「全库同名 + 同义邻件 + 文件树」撞名三查（R327：对 registry v2.59.0 实时精确匹配留痕，见 §4），宁缺毋滥，规划期共拒绝 20 条候选（拒单留痕见 §5）。
> 硬约束：R195 编译债闸未开（连欠 4 轮）→ **本轮不立项编解码/数学/转换类高复杂度件**（纯函数件限低复杂度）；T0 组零检索（无 iec-std-wrapper 件本轮取用）；全文零 WebSearch（0/3，零检索轮）。

## 1. 看板统计

| 指标 | 值 |
|---|---|
| 总库 | **1,163 / 10,000（11.63%）**（registry total_components=1163，v2.59.0，last_updated 2026-11-22T06:12） |
| counts | Base **145** / MathData **278** / Algo **134** / Device **207** / Motion **121** / Process **278**（sum=1163 断言通过） |
| 今日 11-22 新增 | registry `registered_at` 实测 **28** 件；战报口径 31 = 28 注册 + 3 点修返修重注入（口径差如实注明） |
| 距 1,200 差额 | **37**（本轮 16 件达成后余 21） |
| ROADMAP 未勾待办 | 47 条（全部为点修/技术债/手册补录类，**行业池 356 条组件条目已全数勾选清零**——R24 起各轮持续认领所致） |
| 行业池与未注册待办核对 | 全池 [x]；registry 漂移实测 1 件真缺口：`FB_DL_FlowMeterKFactorDrift`（§19.6 已勾但未注册，本轮重建并注册，见目标 6）；其余 10 项漂移为枚举共声明件与命名口径差（E_DL_* 同文件枚举 / FB↔FC 命名漂移），不做新件 |
| 源矩阵覆盖率 | 27 行台账（T0 ×8 / T1 ×9 / T2 ×9 / NE43 ×1）：✔ 收口 **9 行**、◐ 已开组 **18 行**、☐ 待挖 **0 行**——开组覆盖率 100%，收口率 33% |
| 游标 | R328 |

## 2. 16 目标总表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_InterlockBypassAudit | DL_Base | FB_DL_ | 联锁旁路全生命周期审计（申请→时限→到期自动恢复 + 旁路计数台账） | t2-8-isa182 | 中 | 1 |
| 2 | FB_DL_ClockDriftMonitor | DL_Base | FB_DL_ | 本地 RTC vs 外部标准钟漂移率监视（漂移率 ms/h + 超限告警） | self-std | 低中 | 1 |
| 3 | FB_DL_DiagTextLookup | DL_Base | FB_DL_ | 诊断码→HMI 文本查表（双语文本数组 + 越界默认行 + 文本长度 255 防御） | self-std | 低中 | 1 |
| 4 | FC_DL_WordFromBytes | DL_MathData | FC_DL_ | BYTE 数组按字节序组装 WORD/DWORD（ABCD/CDAB/BADC/DCBA 四序） | t2-1-lgf-converter | 低中 | 1 |
| 5 | FC_DL_WordToBytes | DL_MathData | FC_DL_ | WORD/DWORD 按字节序拆解为 BYTE 数组（与目标 4 构成 round-trip 双向对） | t2-1-lgf-converter | 低中 | 1 |
| 6 | FB_DL_FlowMeterKFactorDrift | DL_Device | FB_DL_ | 流量计 K 系数漂移核对（累计总量比对 + 漂移折算 + NE107 降级出口；**§19.6 已勾未注册漂移件重建**） | roadmap-industry-pool-19.6 | 中 | 2 |
| 7 | FB_DL_CameraHealthWatch | DL_Device | FB_DL_ | 视觉相机设备健康看门狗（触发超时 + 心跳丢失 + NG 率趋势三判据） | t1-5-tcopen | 中 | 2 |
| 8 | FB_DL_VisionLightBank | DL_Device | FB_DL_ | 视觉光源组多通道切换（环形/背光/同轴光通道互斥 + 亮度保持 + 通道故障掩码） | t1-5-tcopen | 低中 | 2 |
| 9 | FB_DL_RotaryAirlockCtrl | DL_Device | FB_DL_ | 星型卸料器（旋转气密阀）转速-料位联动驱动（卡料判据 + 失速保护） | roadmap-industry-pool（粉体新方向） | 中 | 2 |
| 10 | FB_DL_TwoSpeedMotor | DL_Device | FB_DL_ | 变极双速电机驱动（绕组切换死区互锁 + 高速禁止位 + 切换反馈校验） | t2-2-lbp（电机族） | 中 | 2 |
| 11 | FB_DL_CabinetCoolingWatch | DL_Device | FB_DL_ | 控制柜热管理监视（柜内-环境温差 + 风扇转速/反馈双判据 + 滤网阻塞趋势） | self-std | 低中 | 2 |
| 12 | FB_DL_StretchWrapSeq | DL_Process | FB_DL_ | 缠绕膜包装机顺控（转盘圈数配方 + 顶/底圈分段 + 膜架张力与切膜联锁） | t2-7-packml（工站最小子集范式） | 中 | 3 |
| 13 | FB_DL_OutdoorTempReset | DL_Process | FB_DL_ | 室外气温重置热工供水设定（OAT 线性重置曲线 + 上下限夹持 + 最小水温联锁） | t1-2-oscat-building | 中 | 3 |
| 14 | FB_DL_KilnPressureCtrl | DL_Process | FB_DL_ | 窑炉窑压定值控制（窑压闭环 + 烟囱抽力执行器 + 窑门开扰动前馈） | self-std | 中 | 3 |
| 15 | FB_DL_TruckScaleSeq | DL_Process | FB_DL_ | 车辆过磅称重流程（上磅到位-稳定窗-读数锁存-下磅 + 皮重/毛重配对台账） | self-std | 中 | 3 |
| 16 | FB_DL_AxisPowerOnSelfTest | DL_Motion | FB_DL_ | 轴上电自检序列（编码器回读-限位状态-驱动就绪序检 + 自检失败禁使能） | t2-4-s7motion | 中 | 3 |

来源配额核对：T2 非 ST 源 8 件（t2-8-isa182 ×1 / t2-1-lgf-converter ×2 / t2-2-lbp ×1 / t2-7-packml ×1 / t2-4-s7motion ×1 / 行业池 ×2）+ T1 ST 原生源 3 件（t1-5-tcopen ×2 / t1-2-oscat-building ×1）+ self-std 5 件 → **满足「≥1 个 T2 组件族 + ≥1 个 T1 组」**；T0 组零检索、本轮零 iec-std-wrapper 件；无凑数变体（WordFromBytes/WordToBytes 为字节序组装族双向对，沿用 BcdToWord/WordToBcd 配对先例，round-trip 验收）。

## 3. 每目标规格要点与边界/安全条件

### 3.1 FB_DL_InterlockBypassAudit（批 1，DL_Base）
- **规格**：旁路申请沿 → 记录申请源/目标联锁号 → 进入旁路态（时限窗 TON 断输入）→ 到期自动恢复并置信息码；旁路期间目标联锁位仍照常计算，仅放行判定被旁路；恢复沿/解除沿/超时三类事件入 8 条深度环形台账（复用 RingBufferLReal 思想、自建定长数组）；旁路计数饱和守卫。
- **边界/安全**：时限 ≤0 置组态码并拒绝进入旁路态；台账写指针越界钳位；同拍「申请 + 解除」时解除优先（安全侧）；旁路态不锁存故障（是审计不是联锁本体）；与 `FB_DL_InterlockMatrix` / `FB_DL_SafetyDoorAuditBank` 头注互引分工（联锁本体 / 旁路审计）。
- **验收向量**：时限 T#30S、第 31 拍未恢复即置码；旁路计数 255+1 饱和不回绕。

### 3.2 FB_DL_ClockDriftMonitor（批 1，DL_Base）
- **规格**：外部标准钟（引脚注入 DT）与本地 RTC 差值每采样窗计算漂移率（ms/h，LREAL 承载防溢出）；滑动窗中位滤波；漂移率超限告警 + 累计漂移超同步阈值置「需校钟」标志；只监视不写钟（写钟归系统层）。
- **边界/安全**：两钟非有限 / 未初始化（DT 零值）闸；采样窗 ≤0 拒绝；回拨（差值负跳）单列「校钟事件」不计漂移；漂移率分母时间窗饱和守卫。
- **验收向量**：正向漂 500 ms/24 h → 漂移率 ≈ 20.8 ms/h；钟回拨拍不置告警只置事件。

### 3.3 FB_DL_DiagTextLookup（批 1，DL_Base）
- **规格**：`uErrorId` → 定长文本数组下标查表（数组由 VAR_IN_OUT 注入，零全局耦合）；命中返回文本 + 语言选择位（中文/英文双数组）；未命中返回默认占位行并置 `bNotFound`；文本按 255 上限 R37 四步截断样板。
- **边界/安全**：数组长度 ≤0 或文本引用越界钳位；码位高段掩码路由（支持 0001/0003 等分段）；空串默认行；每拍重算不锁存（纯查表语义）。
- **验收向量**：越界码 0xFFFF → 默认行 + bNotFound；命中行长度恰 255 → 截断标志先于写入（R49）。

### 3.4 / 3.5 FC_DL_WordFromBytes / FC_DL_WordToBytes（批 1，DL_MathData）
- **规格**：按 `E_DL_ByteOrder` 既有枚举语义（复用不重声明，属主 `FC_DL_SwapBytes16`）做字节-字双向组装/拆解；支持 WORD/DWORD 两种目标（长度分支）；组装时字节数不足按高段补零 + 信息级；round-trip 验收（A→B→A 逐字节相等）。
- **边界/安全**：字节指针 NIL/长度 0 早退零写入；目标数组长度不足钳位 + 置码；字节序枚举越界回默认大端 + 0142 风格码（对齐 Crc8 非法变体先例）；全程无移位超宽（nShift MOD 口径 R48）。
- **验收向量**：CDAB 序 `{0x34,0x12}` → WORD 0x1234；反向拆解逐字节相等；长度 1 组装 WORD → 高段补零信息级。

### 3.6 FB_DL_FlowMeterKFactorDrift（批 2，DL_Device，**未注册漂移件重建**）
- **规格**：§19.6 原规格执行——K 系数回读比对（复用 `FB_DL_DeviceParamVerify` 读-比-判）、批次总量比对（复用 `FB_DL_FlowTotalizer`）、漂移折算（复用 `FC_DL_LinearScale`）；漂移分级 → NE107 `eMaintenanceReq/eOutOfSpec`（引用唯一属主 `E_DL_Ne107Status`，六态仲裁对齐 `I_DL_DeviceHealth`）。
- **边界/安全**：K=0 / 基线总量=0 除零双闸；批次窗口未关闭（结算标志沿）才采样；漂移率非有限拦截；采样周期 ≤0 拒绝；**收口时同步补 registry 注册行（本件为漂移修复件，头注注明 §19.6 溯源）**。
- **验收向量**：漂移 +2.5% 且阈值 2% → eMaintenanceReq；K=0 组态 → 组态级故障不采样。

### 3.7 FB_DL_CameraHealthWatch（批 2，DL_Device）
- **规格**：触发发出后结果返回超时（TON 逐段断输入 R40 家族口径）+ 结果心跳丢失（周期窗内无任何返回）+ NG 率滑动窗趋势（复用 `FB_DL_SignalStatistics` 统计语义次源）三判据；健康出口引用 `E_DL_Ne107Status`（eCheckFunction/eMaintenanceReq 分级）。
- **边界/安全**：三判据各带独立确认窗（R13 `AhuDamperStuckDiag` 三分类确认窗范式）；NG 分母 0 时判据挂起不发布（挂起同步挂起累计载体 R307）；使能撤销不置故障只复位统计。
- **验收向量**：触发后 T#5S 无返回 ×3 连续 → eCheckFunction；NG 率窗内样本 <5 → 判据挂起不发布。

### 3.8 FB_DL_VisionLightBank（批 2，DL_Device）
- **规格**：2~8 通道光源组（通道数引脚钳位）：通道选择互斥仲裁（后到优先可组态）+ 亮度值保持 + 通道切换稳定延时（光强建立时间）+ 通道故障反馈掩码只读出口。
- **边界/安全**：通道号越界钳 1..8 + 信息码；亮度域 0..100% 钳位；同拍多通道请求取最高优先仲裁（与 `FB_DL_RedundantSwitch` 仲裁风格互引但不共享实现）；稳定延时期间输出冻结不闪烁。
- **验收向量**：通道 3 请求 → 通道 2 熄灭延时后通道 3 亮；亮度 150 → 钳 100 + 信息级。

### 3.9 FB_DL_RotaryAirlockCtrl（批 2，DL_Device）
- **规格**：星型卸料器驱动（复用 `I_DL_MotorDriver` 命令-反馈范式次源）：料位联锁（高料位禁启/低料位允许）+ 运行频率/转速给定 + 电流失速判据（电流高 + 转速低同拍持续确认）+ 卡料停机与反转点动解卡出口（点动互斥串 `bEnable AND NOT _bFaultLatch`）。
- **边界/安全**：反转点动仅限停机态且与正转互斥（两状态机高危区 R31 声明）；失速确认窗独立 TON 断输入；料位信号非有限/失效按禁启（安全侧）；启停频次守卫（防频繁启停复用 DolMotor 判据口径）。
- **验收向量**：料位高 + 启动请求 → 拒绝 + 信息码；失速窗满 → 停机 + 锁存，点动解卡受锁存闸拦截。

### 3.10 FB_DL_TwoSpeedMotor（批 2，DL_Device）
- **规格**：双绕组变极调速驱动（复用 `I_DL_MotorDriver` 接口次源）：低速/高速选择 + 切换死区时间互锁（低速断电→延时→高速投入）+ 高速禁止位（工艺联锁）+ 两方向接触器反馈校验（对齐 StarDeltaMotor 星角切换安全死区范式，但不复用其实现）。
- **边界/安全**：切换死区 ≤0 组态码；高速禁止位优先于一切运行请求；反馈校验失败锁存 + 安全侧断高速；切换期间两绕组互斥硬闸（同拍不得双投）。
- **验收向量**：低速运行中切高速 → 低速断电、死区窗内双绕组均断、窗满高速投入；死区窗内高速反馈已出现 → 判为绕组粘连故障。

### 3.11 FB_DL_CabinetCoolingWatch（批 2，DL_Device）
- **规格**：柜内温度 vs 环境温度差值监视（温差超限 = 柜内热交换失效判据）+ 柜内风扇转速/运行反馈双判据 + 长期趋势（滤网阻塞：同环境温度下温差缓升速率）→ NE107 降级出口。
- **边界/安全**：两温度非有限闸；环境温度高于柜内时判据挂起（自然温差为负非故障）；趋势窗样本数下限挂起（R307）；只告警不控风扇（执行归调用方，本件不写输出——「算一个值/做一件事」边界）。
- **验收向量**：温差 25 K 持续确认窗 → eMaintenanceReq；环境 35 ℃ 柜内 33 ℃ → 判据挂起。

### 3.12 FB_DL_StretchWrapSeq（批 3，DL_Process）
- **规格**：缠绕工站 7 态最小子集（对齐 `FB_DL_PickAndPlaceStation` 范式，**刻意不做 17 态全集**——全集属主 `FB_DL_PackMlStateMachine`）：预压→底圈→顶圈（圈数配方：底/顶/总圈数三数组）→切膜→保持；转盘旋转反馈 + 圈数计数（R_TRIG 沿计数 + 计数饱和）；膜断检测联锁暂停。
- **边界/安全**：圈数配方 ≤0 或 >255 组态码拒绝启动；转盘反馈丢失超时锁存；切膜失败重试计数饱和；eIdle 相执行输出清零（R57 LWF 家族扫描范式前置合规）；暂停在圈数边界生效（ISA-88 相语义次源）。
- **验收向量**：底 2 + 顶 3 圈配方 → R_TRIG 计数到 5 即切膜；膜断在顶圈第 2 圈 → 暂停在圈边界、恢复不重头。

### 3.13 FB_DL_OutdoorTempReset（批 3，DL_Process）
- **规格**：室外气温 → 热工供水设定线性重置（OAT 高→水温低两点式曲线，复用 `FC_DL_LinearScale` 计算核）+ 重置输出上下限夹持 + 最小水温防结露/防冻硬下限 + 重置斜坡限速（复用 `FB_DL_RateLimiter` 组合调用不内联——「可依赖低层但不复制低层」R13 范式）。
- **边界/安全**：OAT 非有限 / 传感器失效 → 保持上次有效设定 + 陈旧计时超限置码（NE43 域外行为显式化）；曲线两点重合（斜率除零）→ 冻结输出 + 组态码；水温下限 > 上限倒置自动换位（对齐 RollerGapAdjust 先例）；与 `FB_DL_AhuSupplyAirReset` / `FB_DL_ChillerCondReset` 头注互引分工（热工供水 / 送风 / 冷凝三源）。
- **验收向量**：OAT 10 ℃ → 供水 45 ℃（两点 20 ℃→40 ℃ / 0 ℃→50 ℃ 插值）；OAT 传感器断线 5 min → 保持 + 置码。

### 3.14 FB_DL_KilnPressureCtrl（批 3，DL_Process）
- **规格**：窑压定值闭环（复用 `FB_DL_PidController`，PID 引脚注入不内联）+ 烟囱抽力执行器出口限幅 + 窑门开扰动前馈（复用 `FB_DL_FeedforwardComp` 组合调用）+ 窑压负压上限联锁（负压超限禁升温指令放行——只拦不放，执行归温区件）。
- **边界/安全**：窑压测点双表冗余可选（复用 `FB_DL_ToleranceWindow` 偏差窗）；前馈增益域闸；PID 失能时输出安全侧回挡板位；负压联锁不锁存（是放行闸不是故障锁存——与 `FB_DL_InterlockMatrix` 分工互引）。
- **验收向量**：窑门开 50% → 前馈预置抽力增量；窑压双表偏差 > 窗 → 按 NE43 保持主表 + 置码。

### 3.15 FB_DL_TruckScaleSeq（批 3，DL_Process）
- **规格**：过磅流程七态（空载等待→车辆上磅（到位开关）→稳定窗（称重稳定判据，复用 `FB_DL_SignalStatistics` 稳态窗口径次源）→读数锁存（皮重/毛重配对）→下磅→台账推进）；超时未稳定置码重测；防作弊窗（读数期间磅台扰动检测）。
- **边界/安全**：稳定判据窗长/阈值 ≤0 组态码；读数未锁存前下磅 → 流程作废 + 台账不写入；毛重 < 皮重（亏吨）显式码不静默取负净重；台账定长环形 + 写指针饱和。
- **验收向量**：稳定窗 T#10S 内波动 <50 kg → 锁存；毛重 30 t、皮重 32 t → 亏吨码、净重置 0 不出负值。

### 3.16 FB_DL_AxisPowerOnSelfTest（批 3，DL_Motion）
- **规格**：轴上电自检五步序（驱动就绪 → 编码器回读（位置有效性 + 速率合理性）→ 限位状态巡检（常开/常闭组态域闸）→ 驱动故障字扫描 → 结论锁存）；任一步失败即中止并禁使能放行（`bTestOk` 出口供 `FB_DL_SingleAxis` 使能链消费）。
- **边界/安全**：不自造轴状态枚举（R31 家族纪律——只消费快照与反馈，轴状态归运动层接口）；步序超时逐段 TON 断输入（R40）；结论锁存解除须经显式复位沿且驱动就绪在位（终审两式：解除式可达）；测试未通过时 `bTestOk` 恒 FALSE 无恒假锁存。
- **验收向量**：编码器回读 NaN → 步 2 中止、bTestOk=FALSE、置码；复位沿 + 驱动就绪 → 可重测。

## 4. 撞名三查记录（R327 留痕，registry v2.59.0 实测）

- **查一（registry 精确名）**：16 目标逐一 `name` 集合精确匹配 → **0 命中**。
- **查二（同义邻件）**：每件按词干扫描 1,163 件（kfactor/alarm/vav/outdoor/backlash/bypass/lookup/bytes/camera/airlock/pulse/blowdown/recon/wrap/oat/autoclave/twospeed/errorid/selftest/teach/soften/kiln/restart/seal/light/lub/clock/truck/standby/freezer/cabinet/cooling 等约 40 组词干）→ 命中件全部逐一裁定（见 §5 拒单）。
- **查三（文件树）**：`Glob DL_*\*.st` 全量 1,163 文件名精确匹配 → **0 命中**。
- **后缀正交扫描（R1100）**：16 词干无 `Ex/Sat/StringXxx` 后缀冲突；`*Watch` 后缀件 13 件均语义异域（每件边界段声明与最近邻件互引）。
- 规划期曾拟定后经三查拒绝的候选共 20 条（含 3 条精确同名命中：AxisTorqueRippleWatch / AxisTeachOffset / BoilerBlowdownSeq），全部留痕 §5。

## 5. 拒单留痕（件名 + 拒绝理由）

| # | 拒绝候选 | 拒绝理由 |
|---|---|---|
| R-1 | FC_DL_Affine2DTriDecomp | T2-1 LGF Math「三角方向待挖」为真缺口，但属高复杂度数学件——R195 编译债闸未开（连欠 4 轮）禁新增，转 ROADMAP 挂账不本轮立项 |
| R-2 | FB_DL_AlarmRateMonitor | 同义邻件 `FB_DL_AlarmFloodLimiter` 已有属主（报警泛滥管理族） |
| R-3 | FB_DL_VavCouplingFf | 与已注册 `FB_DL_VavCouplingFeedforward` 语义/命名双重同义 |
| R-4 | FB_DL_ButtonHoldRepeat | `FB_DL_HoldRepeatButton` / `FB_DL_LongPressButton` 已有属主 |
| R-5 | FB_DL_DowntimeParetoStat | `FB_DL_DowntimeClassifier` 已有属主 |
| R-6 | FB_DL_AirLeakAudit | `FB_DL_AirLeakDecayTest` 已有属主 |
| R-7 | FB_DL_LoadShareProportional | `FB_DL_LoadShareDroop` 已有属主（负荷分配族） |
| R-8 | FB_DL_ThermalOvershootDamp | `FB_DL_ThermalRampPredict` 已有属主（热工预判族） |
| R-9 | FB_DL_AxisEndstopHealth | `FB_DL_AxisLimitSwitchBank` 已有属主（限位巡检族） |
| R-10 | FB_DL_HeaterElementHealth | `FB_DL_HeaterBreakDetect` 已有属主（加热元件健康族） |
| R-11 | FC_DL_TableLookupInv | `FC_DL_MultiPointLinear` 前向属主 + `FC_DL_ValveCharacteristic` 反解职责重叠，判凑数变体 |
| R-12 | FC_DL_LinearScaleInv | 同 R-11（标度逆映射与既有反解件职责重叠） |
| R-13 | FB_DL_BoilerBlowdownSeq | **registry 精确同名命中**（已注册件） |
| R-14 | FB_DL_BaghousePulseClean | `FB_DL_DustCollectorPulse` 已有属主（除尘脉冲族） |
| R-15 | FB_DL_AutoclaveF0Seq | `FB_DL_AutoclaveSterilSeq` 已有属主（灭菌顺控族） |
| R-16 | FB_DL_BatchMassRecon | `FB_DL_FlowBalanceCheck` 已有属主（平衡对账族） |
| R-17 | FB_DL_FanVibrationWatch | `FB_DL_RobotArmVibrationWatch` 振动监视属主，风机侧判同族变体（R267 族避让） |
| R-18 | FB_DL_AxisTeachOffset | **registry 精确同名命中**（已注册件） |
| R-19 | FB_DL_WaterSoftenerRegen | `FB_DL_DesiccantRegenSeq` 已有属主（再生顺控族） |
| R-20 | FB_DL_LubricationCycle / FB_DL_StandbyTestRunCtrl / FB_DL_FreezerPulldownCtrl / FB_DL_AgitatorSealWatch / FB_DL_AxisTorqueRippleWatch | 分别与 `FB_DL_GreaseLubeTimer`+`FB_DL_AxisLubeDistTrig` / `FB_DL_ProofTestSeq`+`FB_DL_ValvePartialStrokeTest` / 冷机群控族密集 / 密封族密集+词干歧义 / `FB_DL_AxisTorqueWatch`（精确同名）冲突 |

> 拒单合计 20 条（含精确同名 3 条）。规划数量 16 已足额，无少报。

## 6. 批次划分（依赖与复杂度）

- **批 1（Level 0/1 低中复杂度 ×5）**：目标 1/2/3/4/5 —— Base 三件 + MathData 双向对，互相无依赖，先行收口。
- **批 2（DL_Device 族 ×6）**：目标 6/7/8/9/10/11 —— 目标 6 为漂移件重建（收口时补 registry 注册行），其余五件独立。
- **批 3（Process/Motion 中复杂度 ×5）**：目标 12/13/14/15/16 —— 目标 13 组合调用 RateLimiter（批 2 无依赖，库内既有件）；目标 16 依赖运动层快照引脚注入。

## 7. 预算执行声明

- 规划阶段 WebSearch **0/3（零检索轮）**：全部目标复用源矩阵既有 ◐ 组待挖粒度、ROADMAP §19.6 漂移件与规划新增线，未开新源。
- 读盘范围：INDEX_REGISTRY.json（python 统计 4 次）、ROADMAP.md（§7/§19/§22~§24/R24~R66 增补节选）、SOURCE_HUNTING_MATRIX.md（§0~§5 全文）、AGENT_EVOLUTION_LOG.md 尾部、ROUND_PLAN/BATTLE_R67 全文。
- 未动：INDEX_REGISTRY.json / 任何 .st / JSONL / README / CHANGELOG / VERSION / MANUAL（红线全过）。

## 8. 文件动作清单（本规划轮）

| 动作 | 文件 |
|---|---|
| 新建 | `_Staging_Raw\2026-11-22\ROUND_PLAN_R68.md`（本文件） |
| 新建 | `_Staging_Raw\2026-11-22\RAW_NOTES_R68.md`（来源留痕，零检索声明） |

*R68 规划线 ｜ 2026-11-22 ｜ 道莅工控代码库产品总监（主控直跑 R335，游标 R328）*
