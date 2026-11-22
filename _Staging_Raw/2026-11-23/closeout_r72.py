# -*- coding: utf-8 -*-
"""R72 closeout: registry update (12 new + 1 点修) + JSONL append (13 件)."""
import json, os, shutil, datetime

TS = datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S+08:00")
LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
VER = "2.64.0"

# name, category, kind, complexity, tags, ref_tag, origin_desc, code_segment, instruction, arch
NEW = [
 ("FC_DL_IntModChk", "DL_MathData", "FC", 1,
  ["integer", "modulo", "div-zero", "overflow-guard", "iec-std-wrapper", "r72-new"],
  "iec-std-wrapper",
  "IEC 61131-3 标准语义的道莅防御性实现（DINT 整数取模防御包装，T0-4 数学域闸样板族补口）；与 FC_DL_ModLrealSafe（LREAL 域属主）分工互引，本件只做整数域",
  "段 1 返回值与状态预置｜段 2 除零闸｜段 3 DINT_MIN 溢出面闸｜段 4 升位与余数恒等式｜段 5 降位可表性防线｜段 6 正常出口",
  "齿轮箱传动比约分前要算余数校验齿数配比，卷绕机按圈数余量判断换卷时机。现场组态误下装会把除子写成 0（整除崩溃）；极端工况被除数恰为 DINT 最小值 −2147483648 且除子为 −1 时，商溢出 DINT，三平台 MOD 实现内溢行为不一致，余数结果不可信。",
  "纯函数六段架构：段 1 返回值/状态统一预置；段 2 除零闸（nDivisor=0 故障级早退输出 0，先判后除纪律）；段 3 DINT_MIN/−1 溢出面闸（该组合显式拦截出信息级，不依赖平台内溢行为）；段 4 升位与余数恒等式复验（商×除子+余数=被除数整数恒等自校验）；段 5 降位可表性防线（结果符号随被除数的 IEC MOD 主流口径以注释双口径写死，禁依赖平台默认）；段 6 正常出口。零浮点面、零除零面（除零已前置拦截），整数域跨平台一致。"),
 ("FC_DL_FiniteClassify", "DL_MathData", "FC", 1,
  ["float", "finiteness", "nan", "infinity", "classification", "iec-std-wrapper", "r79-atomic", "r72-new"],
  "iec-std-wrapper",
  "IEC 61131-3/IEEE-754 标准语义的道莅防御性实现（LREAL 非有限四态分类原子，R79 判据原子化，全库首个分类属主；存量内联判据不强制回改，挂账 R333）",
  "段 1 返回值与状态预置｜段 2 NaN 自反判｜段 3 Inf 差值自反判｜段 4 有限值正常出口",
  "产线计量通道断线时模拟量读数变成 NaN、放大器饱和读数变 ±Inf，上位机诊断页需要把它们分桶显示成「断线/正满量程/负满量程/正常」。各组件此前各自内联非有限判据，口径漂移：有的用幅值上界近似筛查，把合法大值误判成异常。",
  "纯函数四段架构：段 1 返回值与枚举预置；段 2 NaN 自反判（x<>x，IEEE 语义唯一可靠口径，禁近似阈值）；段 3 Inf 差值自反判（(x−x)<>0 即非有限，再按符号二分 ePosInf/eNegInf，1.79E308 幅值兜底只作旁证注释不作判据）；段 4 有限值正常出口。零除法、零循环，纯 IEEE 语义四态，不做幅值上界筛查（上界属调用方业务语义），原子件可被全库组合调用。"),
 ("FC_DL_ArrayCumSumLreal", "DL_MathData", "FC", 2,
  ["array", "cumulative-sum", "statistics", "prefix-sum", "lgf-math", "r72-new"],
  "lgf-math",
  "LGF Math 组「统计线」方向借鉴（前缀累计序列），clean-room 重写；与 FC_DL_ArraySumLreal 分工互引——后者只出总和，本件输出完整前缀序列",
  "段 1 返回值与状态预置｜段 2 nCount 域闸｜段 3 第一遍：逐元素非有限扫描｜段 4 第二遍：前缀累计与写出口｜段 5 正常出口",
  "能耗统计要把每小时电表读数数组算成累计曲线供 OEE 页面画图；某小时传感器掉线读数变 NaN 时，部分累计会把污染值带进后续每一点，下游余量推演全线失真。调用方还可能误传 nCount 超出数组上界。",
  "纯函数五段架构：段 1 返回值/状态预置；段 2 nCount 域闸（0 → 信息级空出口 fTotal=0；> 上界 → 钳位照算信息级）；段 3 第一遍逐元素非有限扫描（遇非有限样本整体拒绝出故障级——保守口径，防污染下游）；段 4 第二遍前缀累计写 VAR_IN_OUT 数组（两遍扫描均挂 DL_CUM_GUARD 防死锁计数器、写前下标双检防越界，累计 >1E30 置 bTruncated 中断）；段 5 正常出口。浮点判等全容差口径，无变量除法面。"),
 ("FC_DL_CharCodeConvert", "DL_MathData", "FC", 2,
  ["string", "char-code", "ascii", "conversion", "iec-std-wrapper", "r72-new"],
  "iec-std-wrapper",
  "IEC 61131-3 标准语义的道莅防御性实现（单字符↔字符码双向原子，T0-6 字符串族补口）；与 FC_DL_HexStringToBytes / FC_DL_DwordToHexString 分工互引（那些是文本↔字节块，本件是单字符↔码值）",
  "段 1 返回值与双出口预置｜段 2 选向分发（枚举 CASE + ELSE 兜底）｜段 3 统一出口",
  "标签打印机协议要求把 HMI 键盘输入的单字符转义成码值组装帧，反向要把协议码值还原成字符供人读。现场把码值组态到 256 以上（误填十六进制 0x1FF）会导致越界写；扩展 ASCII 128~255 区间三平台渲染字体不一致。",
  "纯函数三段架构：段 1 返回值与双出口统一预置（未选向出口确定值空串/0）；段 2 选向分发（E_DL_CharCodeMode 枚举 CASE + ELSE 兜底）：eCodeToChar 向码域闸 >255 故障级早退（0~255 端点全过），扩展 ASCII 渲染差异头注释披露只保码值回执；eCharToCode 向串长闸（空串/多字符拒收信息级）；段 3 统一出口。全回执纪律：bValid/nInfoCode 双出，无隐式省略（R381）。"),
 ("FC_DL_WordToBinString", "DL_MathData", "FC", 2,
  ["word", "binary-string", "bit-display", "diagnostics", "iec-std-wrapper", "r72-new"],
  "iec-std-wrapper",
  "IEC 61131-3 标准语义的道莅防御性实现（WORD→16 字符定长二进制文本，MSB-first；与 FC_DL_DwordToHexString 同族反向补口，与 ReverseBitsWord/FirstSetBit 分工互引）",
  "段 1 返回值与状态预置｜段 2 逐位提取拼接（SHL 掩码法）｜段 3 统一出口",
  "调试面板要把协议帧状态字直接显示成 16 位二进制人读文本（如 '1011000100000000'），现场对照位定义表排障。用移位拼接实现时若移位量超界或依赖 64 位语义会跨平台翻车。",
  "纯函数三段架构：段 1 返回值/状态预置；段 2 逐位提取拼接（位 15→位 0 MSB-first，SHL 掩码法，移位量全程 ≤15 无 64 位移位依赖，CONCAT 拼接定长 16 无截断可能）；段 3 统一出口。bValid 恒 TRUE 仅保留契约一致性（无域外可能，头注释声明与可截断族口径差异），端点向量 0→全 0 串、16#FFFF→全 1 串。"),
 ("FC_DL_HmsToTodChk", "DL_MathData", "FC", 2,
  ["time", "tod", "hmi-config", "clamp", "iec-std-wrapper", "r72-new"],
  "iec-std-wrapper",
  "IEC 61131-3 标准语义的道莅防御性实现（时/分/秒三分量合成 TOD，T0-2/T0-5 TIME 族组态入口补口）；与 TodToDintMs/DintMsToTod（毫秒计数口径）、TimeToHmsString（文本化）分工互引",
  "段 1 返回值与状态预置｜段 2 分量非负闸｜段 3 组合域闸：UDINT 域内先钳位后降位｜段 4 降位与毫秒合成｜段 5 委托属主件合成 TOD｜段 6 正常出口",
  "HMI 班次时刻设定页有三个独立数字输入框（时/分/秒），操作工误输 25 时或 70 分很常见；组态值要合成 TOD 交给时间窗口联锁件。直接合成若不钳位，越界值会让班次窗口整体漂移且无提示。",
  "纯函数六段架构：段 1 返回值/状态预置；段 2 分量非负闸（UDINT 天然非负，声明口径）；段 3 组合域闸（时>23/分>59/秒>59 先钳位照算置信息级 bClamped 口径，与 DurationFormat 域外钳位对齐）；段 4 降位与毫秒合成（最大 86399999<2^31 乘法无溢出面，头注释留推演）；段 5 委托属主件合成 TOD（毫秒→TOD 换算单源不内联，委托调用全 4 出参回执）；段 6 正常出口。编码期自纠：属主返回值不得错接 BOOL 局部（TOD→BOOL 类型错接，R387）。"),
 ("FC_DL_DaysInMonthChk", "DL_Base", "FC", 2,
  ["calendar", "days-in-month", "leap-year", "date", "roadmap-t02-calendar", "r72-new"],
  "roadmap-t02-calendar",
  "T0-2 日历变体线遗留补口（R14 零检索变体三判据准入）：年月→当月天数；闰年律复用唯一属主 FC_DL_LeapYearChk 常量单源不内联；与 FB_DL_MonthWindowCheck 分工互引",
  "段 1 返回值与状态预置｜段 2 年份承诺段闸：域外拒绝不钳位｜段 3 月域闸：1~12 外故障级早退｜段 4 大小月静态表 + 二月闰年分支｜段 5 正常出口",
  "月度报表要推当月最后一天做切账界；计量系统按月切账日生成日报表。年份组态若落在属主闰年件窗口之外（如 2120 年），钳位照算会把 2104 这类真闰年误报成 28 天——伪造事实比拒绝更危险。",
  "纯函数五段架构：段 1 返回值/状态预置；段 2 年份承诺段闸（编码期实测属主 LeapYearChk 窗口仅至 2099，承诺段由计划的 1998~2117 收窄为 [1998,2099]，域外故障级拒绝不钳位——R391 承诺段与属主窗口求交，事实类禁钳位）；段 3 月域闸（1~12 外故障级早退输出 0）；段 4 大小月静态表 + 二月分支组合调用 FC_DL_LeapYearChk（全回执，不内联 4/100/400 三级判定）；段 5 正常出口。验收向量：2024 闰 / 2100 世纪非闰 / 2000 闰三组。"),
 ("FB_DL_BlinkOutput", "DL_Base", "FB", 2,
  ["blink", "square-wave", "lamp", "hmi", "oscat", "t1-1-oscat-basic", "r72-new"],
  "t1-1-oscat-basic",
  "OSCAT Basic「BLINK 行为定义」借鉴（tOn/tOff 独立交替两相 + 失能冻结相位，OSCAT 许可免费需致谢，零代码行复制），clean-room 重写；与 FB_DL_PulseGenerator（触发式单脉冲）/ FB_DL_PwmDutyController（高频占空比）分工互引，本件只做秒级闪烁",
  "段 0 复位沿无条件调用｜段 1 锁存解除与首次成因登记｜段 2 运行许可与双 TON 无条件调用｜段 3 两相交替推进｜段 4 统一出口",
  "报警塔灯辅闪与待机呼吸灯要求亮 tOn、灭 tOff 独立可调；现场把 tOn 组态成 0（复制粘贴漏改）会让灯全灭或全亮且无任何提示，报警闪烁静默失效——与 ScaleRangeWatch 增益零域同型的「保护静默失效」教训。",
  "FB 五段架构（两相交替判据链，无 CASE 状态机）：段 0 复位沿无条件调用；段 1 锁存解除唯一解除边 + 首次成因登记；段 2 运行许可与双 TON 无条件周期调用（规则⑦，IN 取显式相条件，编码期自纠段序：锁存先于定时器调用，消灭零组态拍伪切换）；段 3 两相交替推进（tOn/tOff=0 组态锁存码防全灭/全亮静默；bEn=FALSE 冻结输出与相位计数不清零，恢复续走）；段 4 统一出口单点写入。TON IN 极性按 R319 复核（IN=相内剩余条件非被监视电平，头注声明）。"),
 ("FB_DL_OilLevelWatch", "DL_Device", "FB", 2,
  ["oil-level", "lubrication", "level-monitor", "hysteresis", "ne107", "t2-6-rockwell-aoi", "r72-new"],
  "t2-6-rockwell-aoi",
  "Rockwell AOI「设备健康前置预警」封装组织借鉴（次源 NE107 诊断分级），clean-room 重写；判据/阈值/码位 100% 自有；与 FB_DL_SiloLevelInterlock（联锁）/ FB_DL_LevelSwitchVib（开关量）/ FB_DL_HydrostaticLevelComp（换算）分工互引，本件只做模拟量油位趋势监视",
  "段 1 出口预置｜段 2 复位沿无条件调用｜段 3 锁存解除：复位沿唯一人工解除｜段 4 组态域闸｜段 5 输入守卫：液位非有限即危险｜段 6 首次成因锁存｜段 7 运行许可与迟滞条件｜段 8 确认定时器无条件调用｜段 9 出口映射",
  "齿轮箱/液压单元油位靠模拟量液位计监视（mm），欠油要提前预警补油防干磨烧轴；探头断线读数变 NaN 时「测不到」比「欠油」更危险——状态不明必须直接停机级，不能当成正常也不能只报预警。",
  "FB 九段架构（单相监视判据链，无 CASE）：段 1 出口统一预置；段 2 复位沿无条件调用；段 3 锁存解除双路（bReset 上升沿唯一人工解除 + 条件恢复自动降级，电平式 R321 禁恢复沿作唯一载体）；段 4 组态域闸（阈值倒置/回差为负锁存出码——零值组态不静默，R386 教训同型）；段 5 输入守卫安全侧收紧（液位非有限即直接故障锁存 eFailure，不进延时确认；量程上界越界为满油合法工况只出信息级）；段 6 首次成因锁存（R189）；段 7 迟滞双阈值条件计算；段 8 确认 TON 无条件调用（规则⑦）；段 9 出口映射（欠油 → eMaintenanceReq，名实双出口同源）。"),
 ("FB_DL_ToolChangerSeq", "DL_Motion", "FB", 3,
  ["tool-changer", "atc", "machine-tool", "sequence", "interlock", "t2-6-rockwell-aoi", "t1-9-cn-machine-tool", "r72-new"],
  "t2-6-rockwell-aoi",
  "T2-6 设备级 AOI「伺服外围件」方向 + t1-9 国产机床 FB 手册公开功能清单（换刀必有反馈对与互锁为公开工程惯例），状态机/码位/时序 100% clean-room；与 FB_DL_TurretToolSelect（刀塔分度选刀，无机械手取放）/ FB_DL_ToolLifeBudget（寿命记账）分工互引，本件只管换刀机构「命令-反馈-确认」编排",
  "段 0 沿检测与看门狗无条件周期调用｜段 1 首拍初始化与单拍位预清｜段 2 复位沿｜段 3 组态闸：容量为 0 或超时非正 → 锁存｜段 4 主状态机（eIdle/eSelect/ePick/eSwap/eReturn/eDone/eFault，CASE+ELSE 兜底）｜段 5 执行相超时判定｜段 6 失能路径：停机相输出清零 + 回 eIdle｜段 7 统一出口｜段 8 请求值上一拍快照",
  "加工中心换刀：NC 发目标刀位号，机械手要先到刀库取新刀、主轴必须处于可换刀互锁位才能交换、旧刀回库后确认到位。任一相反馈超时必须落码停机；换刀中途主轴互锁突然撤销时若继续换刀会半程掉刀砸工件。",
  "FB 八段架构（ENUM 相状态机）：段 0 沿检测与看门狗无条件周期调用（规则⑦）；段 1 首拍初始化与单拍位预清；段 2 复位沿；段 3 组态闸（容量 0/超时非正锁存；uToolReq=0 或 >容量拒收信息级不发指令；nToolCount=1 单刀库退化信息级直通）；段 4 主状态机 eIdle→eSelect→ePick→eSwap（bSpindleFree 才迁入，中途撤销保持相提示不中断不回退防半程掉刀）→eReturn→eDone（bToolDone 单拍 R24）→eIdle，ELSE 兜底 eFault；段 5 执行相超时判定（每相独立 TON，超时 eFault 锁存）；段 6 失能路径停机相输出清零回 eIdle（R57）；段 7 统一出口；段 8 请求值上一拍快照（受理只看迁入沿锁存副本，禁跨拍双判，R279 同拍竞态闸）。编码期自纠：拒收信息标志改保持域（初版单拍即逝，R389）。"),
 ("FB_DL_RejectBlowCtrl", "DL_Process", "FB", 2,
  ["reject", "blow-off", "air-blast", "conveyor", "oee", "s9-conv", "r72-new"],
  "s9-conv",
  "自研输送线工程惯例 clean-room（R7 先例族）：剔除气吹「预告→延时→气吹→对账」执行时序域；与 FB_DL_VisionResultGate / FB_DL_WeightCheckReject / FB_DL_ConveyorJamDetect（判定域）分工互引",
  "段 0 沿检测无条件周期调用｜段 1 首拍初始化｜段 2 域闸｜段 3 复位沿与首次成因锁存｜段 4 布防延时换算｜段 5 主状态机（eIdle/eArm/eBlow/eConfirm/eFault，CASE+ELSE 兜底）｜段 6 逐相 PT 预置与相计时无条件调用｜段 7 统一出口",
  "灌装线视觉判定 NG 后要等瓶子从检测位走到气吹位（间距 ÷ 带速的延时）再吹除，吹完要在确认窗内复验 NG 是否真离线：漏剔（NG 仍流到下道）和误剔（好瓶被吹）都要记账进 OEE 质量因子。带速信号断线变 0 或 NaN 时绝不能静默放行 NG 瓶。",
  "FB 七段架构（ENUM 相状态机）：段 0 沿检测无条件周期调用（规则⑦）；段 1 首拍初始化；段 2 域闸（fBeltVel 非有限/≤0 拒收 + NG 漏剔计数——速度不明即不剔除宁可人工清台，防静默放行；除法面已前置保证）；段 3 复位沿与首次成因锁存；段 4 布防延时换算（fDistNgToGate/fBeltVel 先判后除）；段 5 主状态机（bNgFlag 上升沿布防→eArm 延时→eBlow 定宽气吹→eConfirm 窗满拍复验 NG 离线一次，R41/R42 同拍竞态口径：漏剔=窗满 NG 仍在位，误剔=无 NG 确认却吹 → uFalseCount）；段 6 逐相 PT 预置 + 相计时单点无条件调用（编码期自纠：初版 TON 写进相分支违反红线 5，R388）；段 7 统一出口。锁存期 NG 漏剔计数补齐对齐头注声明（R390）。"),
 ("FB_DL_SipLineSterilSeq", "DL_Process", "FB", 2,
  ["sip", "sterilization", "steam", "pharma", "sequence", "t2-2-lbp", "t2-8-isa88", "r72-new"],
  "t2-2-lbp",
  "T2-2 LBP「命令→监视→判定」三段分层骨架借鉴（次源 T2-8 ISA-88 相语义公开条款），clean-room 重写；保温窗断点重计与冷点判据 100% 自有；与 FB_DL_CipCleaningSeq / FB_DL_AutoclaveSterilSeq / FB_DL_TunnelPasteurizerSeq 分工互引，本件专管管路蒸汽 SIP 连续工艺段",
  "段 0 复位沿无条件调用｜段 1 首拍初始化与出口内部位预清｜段 2 域闸｜段 3 本拍实时温度判据｜段 4 复位沿与首次成因锁存｜段 5 主状态机（eIdle/eDrain/eHeatUp/eHold/eCooldown/eDone/eFault，CASE+ELSE 兜底）｜段 6 双定时器无条件调用｜段 7 保温剩余倒计时｜段 8 统一出口",
  "制药管路 SIP 蒸汽灭菌：先排凝水，升温到保温设定（公开工程惯例最低承诺 121 ℃），保温窗内温度一旦跌破设定，无菌保证即被破坏——保温计时必须回升温相从零重计，绝不许断点续计。温度探头断线变 NaN 时绝不能放行，否则整批产品报废风险。",
  "FB 八段架构（ENUM 相状态机）：段 0 复位沿无条件调用；段 1 首拍初始化与出口内部位预清；段 2 域闸（fHoldTempSet < SIP 下界组态锁存，下界为常量输入可调；探头非有限故障锁存）；段 3 本拍实时温度判据（迁入拍与每拍判温均取本拍实时值，R42 同拍口径）；段 4 复位沿与首次成因锁存；段 5 主状态机（eDrain 超时故障→eHeatUp 达温迁入→eHold 保温窗 TON，跌破设定计时中止回 eHeatUp + 扰动计数从零重计→eCooldown 关汽回落确认→eDone 置 bSterilized→eIdle，ELSE 兜底 eFault）；段 6 双定时器无条件调用（规则⑦）；段 7 保温剩余倒计时（HMI）；段 8 统一出口。失能双输出清零 + bSterilized 撤销。单探头承诺段声明（多点冷点归上位编排，数组版不立防拆件凑数）。"),
]

FIX = ("FC_DL_AirSpecificVolume", "v1.0.1", "无新码位（契约级修复，不改行为不动既有码位）")


def main():
    reg = json.load(open(REG, encoding="utf-8"))
    bak = REG + ".bak_r72"
    shutil.copy2(REG, bak)
    names = {c["name"] for c in reg["components"]}

    added = []
    for (name, cat, kind, cx, tags, ref, origin, seg, instr, arch) in NEW:
        assert name not in names, "撞名: " + name
        fp = os.path.join(LIB, cat, name + ".st")
        assert os.path.exists(fp), "缺文件: " + fp
        src = open(fp, encoding="utf-8").read()
        lines = src.count("\n") + (0 if src.endswith("\n") else 1)
        reg["components"].append({
            "name": name, "category": cat, "type": kind,
            "file_path": fp, "function_tags": tags, "complexity": cx,
            "version": "1.0.0", "registered_at": TS, "line_count": lines,
            "code_segment": seg, "source": "r72-plan",
            "origin": {"mode": "classification", "source": origin,
                       "license": "iec-std-wrapper" if ref.startswith("iec") else ref,
                       "ref_tag": ref},
        })
        added.append((name, cat, fp, lines, instr, arch))

    fixed = None
    for c in reg["components"]:
        if c["name"] == FIX[0]:
            c["version"] = FIX[1]
            c["registered_at"] = TS
            fp = c["file_path"]
            src = open(fp, encoding="utf-8").read()
            c["line_count"] = src.count("\n") + (0 if src.endswith("\n") else 1)
            c["function_tags"] = [t for t in c.get("function_tags", []) if t != "r71-new"] + ["r72-fix", "e032-full-receipt"]
            fixed = (c["name"], c["category"], fp, c["line_count"])
            break
    assert fixed, "未找到点修件"

    counts = {}
    for c in reg["components"]:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["total_components"] = len(reg["components"])
    reg["counts"] = counts
    reg["version"] = VER
    reg["last_updated"] = TS
    assert sum(counts.values()) == reg["total_components"]
    json.dump(reg, open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("registry ->", reg["total_components"], counts, VER)

    with open(JL, "a", encoding="utf-8") as f:
        for (name, cat, fp, lines, instr, arch) in added:
            rec = {"instruction": instr, "architecture_thought": arch,
                   "output": open(fp, encoding="utf-8").read()}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        rec = {"instruction": "湿空气比容计算组件（FC_DL_AirSpecificVolume）调用饱和水汽压属主件 FC_DL_VaporPressureSat 时沿用了全库惯用的省略式调用（只接 5 个形参，漏掉第 6 个输出形参 bValid）。CODESYS/TwinCAT 允许省略输出形参，但 RuSTy 报 E032「takes 6 arguments but 5 supplied」编译失败，且省略式调用会静默丢弃 bValid 这类有效性回执，存在跨编译器可移植性隐性风险（R381 新规首用轮）。",
               "architecture_thought": "FC 点修 v1.0.1（E032 契约级修复）：段 5 属主件调用补第 6 形参回执 `bValid => _bPwsVld`，局部变量区新增 _bPwsVld : BOOL（_bPws 前缀族第 5 员，同行双语注释，R395 命名纪律——挂账原名 _bAsvOk 与既有 _bPwsOk/_bPwsErr 前缀族冲突，按族改名）；早退判据扩为 (NOT _bPwsOk) OR _bPwsErr OR (NOT _bPwsVld)（属主侧 bValid 在全部非早退路径恒 TRUE，行为零变更，已在头注释披露区声明）；头注释版本行 1.0.0→1.0.1、修订记录登记 R386 对账 + R381 首用。引脚/码位/其他段零改动。同族复核另报 8 处省略式调用点挂账（R333 只挂账不改码）。",
               "output": open(fixed[2], encoding="utf-8").read()}
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    n = sum(1 for _ in open(JL, encoding="utf-8"))
    bad = 0
    for i, line in enumerate(open(JL, encoding="utf-8"), 1):
        try:
            json.loads(line)
        except Exception:
            bad += 1
            print("BAD line", i)
    print("jsonl lines", n, "bad", bad)
    print("added", [a[0] for a in added])
    print("fixed", fixed[0], fixed[1])


if __name__ == "__main__":
    main()
