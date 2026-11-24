# RAW_NOTES_R68 — 来源留痕（2026-11-22，R68 构建轮规划线）

> 本轮性质：**零检索轮（WebSearch 0/3）**。复用既有 RAW_NOTES / 源矩阵台账 / registry 实测 / ROADMAP 池核对，**无新增检索、无新增外部仓库抓取、零代码行复制**。

## 1. 取用源清单（全部为源矩阵既有已开组行，逐件提取点）

| 来源标签 | 矩阵行 / 状态 | 提取点 | 本轮消费件 |
|---|---|---|---|
| t2-8-isa182 | T2-8 ISA-18.2 ◐ | 报警/旁路管理公开条款（旁路须有时限与自动恢复、旁路事件留痕——只借条款语义，分级判据自有） | FB_DL_InterlockBypassAudit（批 1） |
| t2-1-lgf-converter | T2-1 LGF Converter ◐（R22 定宽字段子族 ✔ 后剩余面） | 「字节序/码制组装-拆解在 Converter 组独立成族」分类事实；`E_DL_ByteOrder` 枚举属主 `FC_DL_SwapBytes16` 复用不重声明 | FC_DL_WordFromBytes / FC_DL_WordToBytes（批 1，round-trip 双向对，沿用 R16 BcdToWord/WordToBcd 配对先例） |
| roadmap-industry-pool-19.6 | ROADMAP §19.6（已勾条目，registry 漂移未注册） | 原规格三段（K 系数回读 / 批次总量比对 / 漂移折算）+ NE107 降级出口；重建并补注册 | FB_DL_FlowMeterKFactorDrift（批 2，漂移修复件） |
| t1-5-tcopen | T1-5 TcOpen ◐（R7 开组，契约/实现分离范式） | 相机类设备「命令-应答握手 + 健康出口 + 只读诊断属性」组织方式；光源组通道互斥仲裁范式；枚举编号/状态机/码位 100% 自有 clean-room | FB_DL_CameraHealthWatch / FB_DL_VisionLightBank（批 2） |
| roadmap-industry-pool（粉体新方向） | 规划新增线（R30/R32 先例：行业池空位直接立项） | 星型卸料器「转速-料位联动 + 卡料失速」工程惯例；驱动壳复用 I_DL_MotorDriver 范式次源 | FB_DL_RotaryAirlockCtrl（批 2） |
| t2-2-lbp | T2-2 LBP ◐（「命令-监视-判定」三段分层） | 双速电机「切换死区互锁 + 反馈校验」对齐 StarDeltaMotor 组内安全死区范式（不复用实现） | FB_DL_TwoSpeedMotor（批 2） |
| self-std | 自研线（工程惯例，无单一外部源） | 控制柜热管理（温差+风扇双判据）/ 窑压控制（PID+前馈+联锁放行）/ 过磅流程（稳定窗+皮毛配对）/ RTC 漂移率 / 诊断码文本查表 —— 全部为通用 OEM 刚需，判据与状态机自有 | FB_DL_CabinetCoolingWatch / FB_DL_KilnPressureCtrl / FB_DL_TruckScaleSeq / FB_DL_ClockDriftMonitor / FB_DL_DiagTextLookup（批 1/2/3） |
| t2-7-packml | T2-7 PackML ◐ | 工站「7 态最小子集 + 明确终止态」范式（PickAndPlaceStation 先例）；17 态全集属主 PackMlStateMachine 不触碰；暂停在边界生效借 ISA-88 公开条款（次源记 T2-8） | FB_DL_StretchWrapSeq（批 3） |
| t1-2-oscat-building | T1-2 OSCAT Building ◐（ROOM_CONTROL 子族未挖尽） | 室外气温重置供水设定（OAT reset curve）行为定义——供热类 HVAC 公开语义；线性核复用库内 FC_DL_LinearScale | FB_DL_OutdoorTempReset（批 3） |
| t2-4-s7motion | T2-4 S7 Motion ◐ | 轴工艺对象上电使能时序纪律（对齐 AxisBrakeSeq 使能时序先例）；不自造轴状态枚举（R31 纪律） | FB_DL_AxisPowerOnSelfTest（批 3） |

## 2. 配额结论（源矩阵 §4 硬性要求）

- ≥1 个 T2 非 ST 源：t2-8-isa182 / t2-1-lgf-converter / t2-2-lbp / t2-7-packml / t2-4-s7motion / 行业池 ×2，共 8 件 ✔
- ≥1 个 T1 ST 原生源：t1-5-tcopen ×2 / t1-2-oscat-building ×1，共 3 件 ✔
- T0 组零检索 ✔（本轮零 iec-std-wrapper 件；T0 七行 ✔ 收口状态不变，ShlDwordEx/ShrDwordEx 维持 R63 拒立项定案）
- 状态列：本轮全部为既有 ◐ 行深化 + 规划新增线，**无 ☐→◐ 开组、无 ◐→✔ 收口**；状态列回写待编码收口后由 closeout 执行（R219 文档脚本化）。

## 3. 本轮核对留痕（规划依据，非检索）

1. `INDEX_REGISTRY.json` 实测（python ×4）：total=1163 / v2.59.0 / counts 145/278/134/207/121/278 / 11-22 注册 28 件 / 漂移比对（ROADMAP 提及 vs registry）：真缺口 1 件（FB_DL_FlowMeterKFactorDrift），其余 10 项为 E_DL_* 共声明件与 FB↔FC 命名口径差，不立新件。
2. `ROADMAP.md` 池核对：行业池 356 条全数勾选；未勾 47 条均为点修/技术债类 → 本轮选题主力转为「源矩阵 ◐ 待挖粒度 + 漂移件 + 规划新增线」，与 R30/R32 零检索轮先例一致。
3. `SOURCE_HUNTING_MATRIX.md` 全文复核：27 行台账 9 ✔ / 18 ◐ / 0 ☐；三条铁律全文对本轮 16 件逐条核对（无闭源代码行、无 GPL 源、逐件溯源已列 §1）。
4. 撞名三查：registry 精确名 0 命中 / 同义邻件 ~40 组词干扫描（命中全部裁定，拒单 20 条见 ROUND_PLAN §5）/ 文件树 0 命中 / R1100 后缀正交扫描通过。

## 4. 规划期规则引用备忘（编码轮须继承）

- R195：编译债连欠 4 轮 → 本轮禁高复杂度编解码/数学/转换件（FC 件限低复杂度；Affine2DTriDecomp 已拒 R-1 转挂账）。
- R327：三查必须对 registry 实时精确匹配留痕（已完成，编码轮入库前须对增量 registry 复跑一遍精确名查）。
- R40 / R307 / R31 / R57：TON 逐段断输入 / 判据挂起同步挂起累计载体 / 不自造轴状态 / eIdle 相输出清零——编码自检清单沿用 §5.4 十项。
- 编码轮收口动作预告：FB_DL_FlowMeterKFactorDrift 除正常入库外须补 registry 注册行（漂移修复件）+ ROADMAP §19.6 行加「R68 重建注册」注记。

*R68 规划线 ｜ 2026-11-22 ｜ 道莅工控代码库产品总监（零检索轮，无新增外部源）*
