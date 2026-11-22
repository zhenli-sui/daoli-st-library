# -*- coding: utf-8 -*-
"""R68 收口脚本：registry 注册（16 新件）+ JSONL 追加（16 新语料）+ 断言"""
import io, json, os, shutil, datetime

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JSL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
BAK = os.path.join(LIB, "_archive", "registry_backups", "INDEX_REGISTRY.json.bak_r68")

def st_read(cat, name):
    p = os.path.join(LIB, cat, name + ".st")
    src = io.open(p, encoding="utf-8").read()
    return p, src

# (name, cat, ty, cx, srcdesc, om, tag, tags, (instruction, architecture_thought))
NEW = [
 ("FB_DL_InterlockBypassAudit","DL_Base","FB",4,"ISA-18.2 旁路管理语义借鉴，clean-room 重写","classification","t2-8-isa182",["interlock","bypass","audit","timeout-restore","ring-ledger","isa182","cleanroom","r68-new"],
  ("联锁旁路全生命周期审计：维修人员申请临时旁路某路联锁（带时限窗），到期自动恢复并留痕，旁路期间联锁照常计算仅放行判定被旁路，申请/解除/超时三类事件入 8 条环形台账供追溯。边界：时限<=0 组态码拒绝进入旁路态；同拍申请+解除时解除优先（安全侧）；旁路计数 255 饱和不回绕；台账写指针显式回卷。","审计与本体分离架构：本件只做旁路状态机 + 事件台账，联锁本体计算不受影响（与 FB_DL_InterlockMatrix 分工互引）；TON 时限窗段 0 无条件刷新且断输入；环形台账 WriteLedger 私有方法统一记账（指针/序号/计数三账）；旁路态不锁存故障（审计不是联锁本体）。")),
 ("FB_DL_ClockDriftMonitor","DL_Base","FB",3,"道莅原创 self-std","classification","self-std",["clock","drift","rtc","median-filter","sync-alarm","self-std","r68-new"],
  ("本地 RTC 与外部标准钟漂移监视：每采样窗计算两钟差值的漂移率（ms/h，LREAL 承载防溢出），滑动窗中位滤波后超限告警，累计漂移超同步阈值置「需校钟」标志。边界：两钟非有限/零值未初始化闸；采样窗<=0 拒绝；钟回拨单列校钟事件不计漂移（负跳不告警只置事件）；只监视不写钟。","监视与执行分离：本件只算漂移率与告警，写钟归系统层；5 样本中位滤波（排序插入法，无 MOD 方言）；回拨检测先行分流（差值负跳→事件通道）；漂移率分母时间窗饱和守卫防除零；与 FB_DL_NtpSyncMonitor（若有）或时钟族件分工互引。")),
 ("FB_DL_DiagTextLookup","DL_Base","FB",3,"道莅原创 self-std","classification","self-std",["diag","text-lookup","hmi","bilingual","default-row","self-std","r68-new"],
  ("诊断码到 HMI 文本查表：uErrorId 经高段掩码路由到定长文本数组下标，命中返回双语文本（中/英选择位），未命中返回默认占位行并置 bNotFound，供 HMI 报警列表与日志系统统一取文。边界：数组长度<=0 或越界钳位；文本 255 上限截断（R49 四步样板：判超限置码→钳长→写入→REPLACE 显式终结）；空串默认行；每拍重算不锁存。","零耦合查表架构：文本数组由 VAR_IN_OUT 注入（零全局耦合）；掩码路由（取码位高段）支持 0001/0003 等分段码表；纯查表语义每拍重算无状态驻留；截断标志先于写入（R49）；与 FB_DL_AlarmTextRouter 等文本族件分工互引。")),
 ("FC_DL_WordFromBytes","DL_MathData","FC",3,"西门子 LGF Converter 分类语义借鉴，clean-room 重写","classification","t2-1-lgf-converter",["word","bytes","byte-order","assembly","round-trip","lgf-converter","cleanroom","r68-new"],
  ("BYTE 数组按字节序组装 WORD/DWORD：通讯报文或寄存器原始字节按 ABCD/CDAB/BADC/DCBA 四种字节序组装成字/双字，用于 Modbus 寄存器拼接、协议桥接、字节序差异设备对接。边界：字节指针 NIL/长度 0 早退零写入；长度不足按高段补零 + 信息级；字节序枚举越界回默认大端 + 非法变体码（对齐 Crc8 先例）；移位量 MOD 口径合规（R48）。","复用既有 E_DL_ByteOrder 枚举（属主 FC_DL_SwapBytes32，不重声明）；SHL 半字组装 + 前缀判别单遍架构（不 switch 四份代码）；round-trip 与 FC_DL_WordToBytes 互为逆操作验收（A→B→A 逐字节相等）；纯函数无状态。")),
 ("FC_DL_WordToBytes","DL_MathData","FC",3,"西门子 LGF Converter 分类语义借鉴，clean-room 重写","classification","t2-1-lgf-converter",["word","bytes","byte-order","disassembly","round-trip","lgf-converter","cleanroom","r68-new"],
  ("WORD/DWORD 按字节序拆解为 BYTE 数组：把字/双字按 ABCD/CDAB/BADC/DCBA 四种字节序拆成字节串写入发送缓冲，用于 Modbus 下发、协议组包、跨字节序设备通讯。边界：目标数组指针 NIL/长度 0 早退零写入；容量不足钳位 + 置码；字节序枚举越界回默认大端 + 非法变体码；与 FC_DL_WordFromBytes round-trip 双向对。","与组装件同构镜像架构（SHR 提取 + 下标写入）；复用 E_DL_ByteOrder 既有枚举语义；容量闸先行防越界；round-trip 验收为出厂标准向量；纯函数无状态；沿用 BcdToWord/WordToBcd 配对先例（双向对非凑数变体）。")),
 ("FB_DL_FlowMeterKFactorDrift","DL_Device","FB",4,"ROADMAP §19.6 漂移件重建（已勾未注册缺口）","classification","roadmap-industry-pool-19.6",["flowmeter","kfactor","drift","ne107","totalizer","roadmap-industry-pool","cleanroom","r68-new"],
  ("流量计 K 系数漂移核对：以独立参考总量（如罐区检定总量/上游总表）与本表累计量比对，折算 K 系数漂移百分比并分级——超维护阈值降级 NE107 eMaintenanceReq、超报废阈值 eOutOfSpec，用于贸易结算流量计周期核查与失准预警。边界：K=0/基线总量=0 除零双闸；批次结算沿才采样；漂移率非有限拦截；采样周期<=0 拒绝。","读-比-判架构：DeviceParamVerify 读 K 系数 + FlowTotalizer 累计量 + LinearScale 折算三委托组合；漂移分级映射唯一属主 E_DL_Ne107Status（六态仲裁对齐 I_DL_DeviceHealth）；结算沿触发采样（窗口未关不采）；本件为 §19.6 已勾未注册漂移件重建，头注注明溯源。")),
 ("FB_DL_CameraHealthWatch","DL_Device","FB",4,"TcOpen 视觉健康语义借鉴，clean-room 重写","classification","t1-5-tcopen",["camera","vision","health-watchdog","heartbeat","ng-rate","tcopen","cleanroom","r68-new"],
  ("视觉相机设备健康看门狗：触发发出后结果返回超时、结果心跳丢失（周期窗内无任何返回）、NG 率滑动窗趋势异常三判据综合裁决，健康出口按 NE107 分级（eCheckFunction 降级/eMaintenanceReq 维护），供产线在相机劣化期提前干预而非停线后发现。边界：三判据各带独立确认窗；NG 分母 0 判据挂起不发布（挂起同步挂起累计载体）；使能撤销只复位统计不置故障。","三判据并联 + 独立确认窗架构（R13 三分类确认窗范式）：超时 TON 逐段断输入（R40 家族口径）、心跳窗 TON、NG 率统计次源委托 SignalStatistics；结果沿与触发沿同拍竞态用快照先消化本拍结果沿（R275 同族）；分级出口引用唯一属主 E_DL_Ne107Status。")),
 ("FB_DL_VisionLightBank","DL_Device","FB",3,"TcOpen 光源控制语义借鉴，clean-room 重写","classification","t1-5-tcopen",["vision","light","channel-mux","brightness-hold","fault-mask","tcopen","cleanroom","r68-new"],
  ("视觉光源组多通道切换：2~8 通道环形光/背光/同轴光互斥选择，后到优先可组态，通道切换带光强建立稳定延时（期间输出冻结防闪烁），亮度值保持与通道故障反馈掩码只读出口，供拍照工位光源时序联锁。边界：通道号越界钳 1..8 + 信息码；亮度域 0..100% 钳位；同拍多通道请求最高优先仲裁；稳定延时期间冻结输出。","互斥仲裁 + 稳定延时两段架构：请求仲裁（后到优先组态位）→ 提交新通道并刷新亮度槽位 → 稳定延时窗冻结旧通道熄灭与新通道点亮时序；DOWNTO 改升序覆盖（编码期自纠：高位优先语义）；故障反馈掩码只读不出使能；与 FB_DL_RedundantSwitch 仲裁风格互引不共享实现。")),
 ("FB_DL_RotaryAirlockCtrl","DL_Device","FB",4,"ROADMAP 行业池粉体方向 + I_DL_MotorDriver 范式次源","classification","roadmap-industry-pool",["airlock","rotary-valve","interlock","stall-detect","jog-reverse","roadmap-industry-pool","cleanroom","r68-new"],
  ("星型卸料器（旋转气密阀）驱动：料位联锁（高料位禁启/低料位允许）+ 运行频率给定 + 电流失速判据（电流高且转速低同拍持续确认）→ 卡料停机锁存，并提供反转点动解卡出口（仅停机态且受故障锁存闸拦截），用于粉体/颗粒料气密卸料环节。边界：反转点动仅限停机态且与正转互斥（双状态机高危区 R31 声明）；失速确认窗 TON 独立断输入；料位信号非有限/失效按禁启（安全侧）；启停频次守卫。","命令-反馈范式复用 I_DL_MotorDriver 接口；联锁与驱动一体但锁存出口独立（卡料锁存须显式复位沿）；失速判据双信号同拍与门 + 确认窗（单拍不误跳）；点动互斥串 bEnable AND NOT _bFaultLatch（锁存期硬闸）；堵转/信号失效迁移 eFault 不回 eIdle（R152 不可达规避）。")),
 ("FB_DL_TwoSpeedMotor","DL_Device","FB",4,"西门子 LBP 电机族语义借鉴，clean-room 重写","classification","t2-2-lbp",["motor","two-speed","pole-change","dead-time","interlock","lbp","cleanroom","r68-new"],
  ("变极双速电机驱动：低速/高速绕组选择切换，切换经断电死区延时（低速断→延时→高速投），高速禁止位（工艺联锁）优先于一切运行请求，两绕组接触器反馈校验——死区窗内高速反馈已出现判绕组粘连故障。边界：死区<=0 组态码；切换期间两绕组互斥硬闸（同拍不得双投）；反馈校验失败锁存 + 安全侧断高速。","星角切换安全死区范式（对齐 StarDeltaMotor 但不复用实现）：三段时序（低速运行→双断死区→高速投入）；高速禁止位最高优先级串入两状态机；反馈窗口校验（死区窗内任何对侧反馈=粘连锁存）；绕组互斥由状态机单态保证 + 输出级二次与门硬闸。")),
 ("FB_DL_CabinetCoolingWatch","DL_Device","FB",3,"道莅原创 self-std","classification","self-std",["cabinet","cooling","thermal-watch","filter-trend","ne107","self-std","r68-new"],
  ("控制柜热管理监视：柜内-环境温差超限判热交换失效，风扇转速/运行反馈双判据，长期趋势监视滤网阻塞（同环境温度下温差缓升速率），出口按 NE107 降级分级，供控制柜在风扇劣化/滤网堵塞早期维护。边界：两温度非有限闸；环境高于柜内判据挂起（负温差非故障）；趋势窗样本数下限挂起；只告警不控风扇（执行归调用方）。","三判据分工架构：温差即时判据 + 风扇反馈双判据 + 缓升趋势判据（窗口斜率）；趋势采样带样本数下限（R307 挂起同步挂起载体）；环境反向差分流挂起通道（不污染故障计数）；只算不发（「算一个值/做一件事」边界），执行出口由调用方消费 NE107 状态。")),
 ("FB_DL_StretchWrapSeq","DL_Process","FB",4,"PackML 工站最小子集范式借鉴，clean-room 重写","classification","t2-7-packml",["stretch-wrap","sequence","recipe-counts","film-break","interlock","packml","cleanroom","r68-new"],
  ("缠绕膜包装机顺控：七态最小子集（预压→底圈→顶圈→切膜→保持），圈数配方（底/顶/总圈数）由转盘 R_TRIG 沿计数推进，膜架张力与切膜联锁，膜断检测暂停在圈数边界（恢复不重头），用于托盘缠绕包装工站。边界：圈数配方<=0 或>255 组态码拒绝启动；转盘反馈丢失超时锁存；切膜重试计数饱和；eIdle 相执行输出清零；暂停只在圈边界生效（ISA-88 相语义次源）。","刻意最小子集架构（全集属主 FB_DL_PackMlStateMachine，本件为单工站瘦封装）：圈数三数组配方 + 沿计数饱和守卫；膜断暂停在圈边界挂起（相位保持不重头）；切膜失败重试双窗节流（tonCutTo AND tonCutDwell 防每扫描累计，编码期自纠）；eIdle 相输出清零（R57 LWF 家族安全侧范式前置）。")),
 ("FB_DL_OutdoorTempReset","DL_Process","FB",4,"OSCAT Building 暖通重置语义借鉴，clean-room 重写","classification","t1-2-oscat-building",["outdoor-reset","hvac","supply-temp","stale-hold","rate-limit","oscat-building","cleanroom","r68-new"],
  ("室外气温重置热工供水设定：OAT 高水温低两点式线性重置曲线插值供水设定值，输出上下限夹持，最小水温防结露/防冻硬下限，重置斜坡限速；OAT 传感器失效保持上次有效设定并陈旧计时超限置码，用于锅炉/换热机组气候补偿。边界：OAT 非有限/失效保持 + 陈旧置码（NE43 域外显式化）；曲线两点重合（斜率除零）冻结输出 + 组态码；下限>上限自动换位。","委托组合架构（不复制低层）：LinearScale 算曲线核 + RateLimiter 限斜坡 + 陈旧保持轨（锁存副本与实时镜像二选一输出）；两点重合结构性早退（除子组态非法 RETURN，R62 族范式）；换位自愈（下限>上限自动交换，RollerGapAdjust 先例）；与 AhuSupplyAirReset/ChillerCondReset 三源分工互引。")),
 ("FB_DL_KilnPressureCtrl","DL_Process","FB",4,"道莅原创 self-std（窑炉行业）","classification","self-std",["kiln","pressure-control","pid","feedforward","draft-interlock","self-std","cleanroom","r68-new"],
  ("窑炉窑压定值控制：窑压闭环 PID 调烟囱抽力执行器，窑门开度扰动前馈预置抽力增量，窑压双表冗余偏差窗可选，负压超限联锁禁升温指令放行（只拦不放，执行归温区件），用于隧道窑/辊道窑压力制度稳定。边界：前馈增益域闸；PID 失能输出安全侧回挡板位；负压联锁不锁存（放行闸非故障锁存）；双表偏差超窗保持主表 + 置码（NE43 口径）。","委托组合架构：PidController 引脚注入不内联 + FeedforwardComp 前馈组合 + ToleranceWindow 双表冗余；前馈与反馈求和单出口；负压闸为放行型联锁（与 InterlockMatrix 分工互引——闸不放行不锁存）；失能安全位（挡板回安全开度）。")),
 ("FB_DL_TruckScaleSeq","DL_Process","FB",4,"道莅原创 self-std（称重行业）","classification","self-std",["truck-scale","weighing","stability-window","tare-gross-pair","ledger","self-std","cleanroom","r68-new"],
  ("车辆过磅称重流程七态：空载等待→上磅到位→稳定窗（峰峰值<容差判稳）→读数锁存（皮/毛配对）→下磅→台账推进（8 条环形）；超时未稳定清窗重测；防作弊窗（稳定相内磅台到位闪断视为扰动回测）；毛重<皮重亏吨显式码、净重置 0 不出负值。边界：稳定判据窗长/阈值<=0 组态码；未锁存先下磅流程作废台账不写入；配对完成双槽清零迎下一车。","统计件组合架构：SignalStatistics 委托算峰峰值（稳态窗口径次源）；锁存与下磅沿竞态先消化本拍锁存（R275 同族）；皮/毛双槽配对制（0=未锁存哨兵）；亏吨分支净重钳 0 + 显式码（绝不静默取负，R81 口径）；台账 WriteLedger 私有方法统一记账 + 写指针饱和；槽值段 7 镜像输出（收口就地修：fTareLatched/fGrossLatched）。")),
 ("FB_DL_AxisPowerOnSelfTest","DL_Motion","FB",4,"西门子 S7 Motion 自检语义借鉴，clean-room 重写","classification","t2-4-s7motion",["axis","self-test","power-on","encoder-check","enable-gate","s7motion","cleanroom","r68-new"],
  ("轴上电自检五步序列：驱动就绪→编码器回读（位置有效性+速率合理性）→限位状态巡检（常开/常闭组态域闸）→驱动故障字扫描→结论锁存；任一步失败中止并禁使能（bTestOk 出口供单轴使能链消费），用于产线上电批量轴就绪核验。边界：步序超时逐段 TON 断输入（R40）；不自造轴状态枚举（只消费快照反馈，R31 家族纪律）；结论锁存解除须显式复位沿且驱动就绪在位（解除路径可达 R152）；未通过时 bTestOk 恒 FALSE 无恒假锁存。","五步序检架构：每步独立超时 TON 段 0 无条件刷新；编码器非有限/速率越域双面校验；限位组态域闸（常开/常闭引脚组态非法=码）；结论锁存器（bTestOk 置位须全步通过，复位沿+就绪双条件解除）；不自造轴枚举、只镜像快照（运动层接口边界）。")),
]

now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
shutil.copy2(REG, BAK)
reg = json.load(io.open(REG, encoding="utf-8"))
comps = reg["components"]
by_name = {c["name"]: c for c in comps}

n_new = 0
for (n, cat, ty, cx, srcdesc, om, tag, tags, spec) in NEW:
    assert n not in by_name, "撞名: " + n
    p, src = st_read(cat, n)
    comps.append({
        "name": n, "category": cat, "type": ty, "file_path": p,
        "function_tags": tags, "complexity": cx, "version": "1.0.0",
        "registered_at": now, "line_count": src.count("\n") + 1,
        "code_segment": "", "source": "r68-plan",
        "origin": {"mode": om, "source": srcdesc, "license": "cleanroom-ref",
                   "ref_tag": tag},
    })
    by_name[n] = comps[-1]
    n_new += 1

cnt = {}
for c in comps:
    cnt[c["category"]] = cnt.get(c["category"], 0) + 1
reg["counts"] = cnt
reg["total_components"] = len(comps)
reg["version"] = "2.60.0"
reg["last_updated"] = now
assert sum(cnt.values()) == len(comps), "counts sum mismatch"
json.dump(reg, io.open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

def jsl_line(instr, at, src):
    return json.dumps({"instruction": instr, "architecture_thought": at, "output": src},
                      ensure_ascii=False, separators=(",", ":"))

added = 0
with io.open(JSL, "a", encoding="utf-8", newline="\n") as f:
    for (n, cat, ty, cx, srcdesc, om, tag, tags, spec) in NEW:
        instr, at = spec
        _, src = st_read(cat, n)
        f.write(jsl_line(instr, at, src) + "\n")
        added += 1

bad = tot = 0
for ln in io.open(JSL, encoding="utf-8"):
    ln = ln.strip()
    if not ln:
        continue
    tot += 1
    try:
        d = json.loads(ln)
        assert d.get("instruction") and d.get("architecture_thought") and d.get("output")
    except Exception:
        bad += 1
print("R68 closeout OK: new=%d registry=%d counts=%s lib=v2.60.0 jsonl_total=%d bad=%d"
      % (n_new, len(comps), json.dumps(cnt, ensure_ascii=False), tot, bad))
