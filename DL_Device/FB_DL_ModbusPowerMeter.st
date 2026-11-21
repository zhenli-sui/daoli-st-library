(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ModbusPowerMeter
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / TON / SQRT）
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 电表全量数据模型 + 电能质量分级
 * 功能描述 (Function)   : 把轮询主站**已读入的原始寄存器**拼装成电表数据模型：
 *                         三相电压/电流标定、有功/无功/视在换算、功率因数复算与
 *                         交叉校验、三相不平衡度、频率、THD、电能 32 位拼装与
 *                         单调性、需量窗口、缺相与反送电识别，最终输出 NE107
 *                         四态健康 + 单一诊断码。
 * 实现契约 (Implements): I_DL_PowerMeter（DL_Device）。契约内 12 条量以
 *                         PROPERTY GET 出口且类型逐字对齐接口；契约外的扩展量
 *                         （bValid / bError / uErrorId / 分相电压 / 视在功率 /
 *                         净电能 / THD / 平均需量 / 缺相 / 反送 / 换表次数）
 *                         以 VAR_OUTPUT 出口。两类**不同名，无遮蔽**：不得给同一
 *                         个量同时声明 VAR_OUTPUT 与 PROPERTY，那会在编译期报
 *                         「重复声明」或「属性遮蔽」，是接口实现的常见坑。
 * 分层声明 (Layering)   :
 *   ① **不做通信调度**：何时读寄存器由轮询主站件决定，本件按「冻结值更新节拍」
 *      被调用——调用方须保证同一批寄存器在本拍内是同一时刻的快照，否则电压取自
 *      上一拍、电流取自本拍，功率因数会算出物理上不存在的值。
 *   ② **不做费率/分时**：峰谷平与需量窗口写入属配置层，另件承担。
 *   ③ **与 FB_DL_EnergyMeterAccum 分层**：后者是 NE43 口径的「累计与需量」专用件，
 *      本件是「全量数据模型 + 质量分级」件。两者是**两套诊断语言**（NE43 面向
 *      原始值域，NE107 面向设备健康），码位各自独立，严禁互相复制码位；本件的
 *      累计算法可直接沿用其口径（32 位拼装 + 单调性），但**不得**引用其码位。
 *   ④ **不做 CT/PT 变比**：变比属配置，本件只接受最终标定系数。
 *   ⑤ **32 位电能回绕按换表处理**：UDINT 拼装值在 16#FFFF_FFFF 处回绕时，
 *      换算值会出现大幅回退，本件与「换表/清零」走同一路径（重载基准 + 计次 +
 *      置 0318 维护码），因为二者在本件可观测的信息里不可区分。按默认标定
 *      0.1 kWh/LSB，回绕点约为 4.29 亿 kWh，正常工况不会触及；若现场确有
 *      低位表，应在上层按费率窗另行归档。
 * 段序 (Cycle order)   : 本件实际拍序（与公约段号的对应关系已注明）：
 *                         段 1 默认值/单拍标志预清零（公约段 1）
 *                         段 2 首扫初始化（R19）
 *                         段 3 参数闸门与标定校验（公约段 1 的实质内容）
 *                         段 4 定时器与边沿无条件刷新（公约段 2，R40）
 *                         段 5 工程量换算（公约段 5 前半）
 *                         段 6 有效性与数据质量判定（公约段 3）
 *                         段 7 复位通道 + 故障锁存（公约段 8，**置于 CASE 之前**）
 *                         段 8 计量状态机（公约段 4）
 *                         段 9 电能累计与需量结算（公约段 5 后半）
 *                         段 10 等级仲裁与保持重写（公约段 6 + 段 10，R27）
 *                         段 11 出口钳位（公约段 7，R43）
 *                         段 12 码位单一优先级链（公约段 9）
 * 复位通道 (Reset)      : 段 7 的复位动作**只清与状态无关的量**（锁存、窗口、
 *                         峰值、累计基准），**不做任何状态变量赋值**；状态迁移
 *                         只在段 8 的 eFault 分支内发生，且以 `_bExitFault`
 *                         单拍标志驱动。这样从结构上排除「掉使能冻结分支吞掉复位
 *                         沿」的可能（R39 合法写法之二：把复位通道提到冻结分支
 *                         之前，且状态赋值全部收敛到分支内）。
 * 健康出口 (Health)     : 全部出口量以 E_DL_Ne107Status 统一表达（类型引用自
 *                         I_DL_DeviceHealth.st，本文件**不重复声明枚举体**）。
 *                         eDegraded 与 eFault 的分界写死为：**越规不改数据可信度
 *                         → Degraded（eOutOfSpec）；数据不可信（陈旧/自相矛盾/
 *                         标定非法）→ Fault（eFailure）**。这是 NE107 的 S 与 F
 *                         之别，现场误判率最高的一处。
 * 码位表 (Error codes)  : 信息级 6 个（16#0003_0156~015B）/ 故障级 6 个（16#0003_0316~031B）
 *                         0156 三相电压不平衡度 >2% 但未越限  eOk
 *                         0157 需量窗口 <1 s 已按 1 s 兜底  eOk
 *                         0158 字序参数改变，首拍重载累计基准  eOk
 *                         0159 轻载下 PF/THD 越限被抑制  eOk
 *                         015A 复算功率因数与表值偏差 >3%  eOutOfSpec
 *                         015B 频率越限（±0.5 Hz 带）  eOutOfSpec
 *                         0316 电压/电流/电能标定非正  eFailure
 *                         0317 原始寄存器全零且超陈旧超时  eFailure
 *                         0318 电能累计回退（换表或清零）  eMaintenanceReq
 *                         0319 非法状态兜底  eFailure
 *                         031A 三相电流全零而有功非零  eFailure
 *                         031B 有功功率拼装结果非有限  eFailure
 * 码位级裁定 (Slot rule): 0318 落在故障带但语义为「维护请求」，**不置 bError**。
 *                         理由与 A5 的 0323 同源：bError 表示「不可继续运行」，
 *                         而换表/清零后基准已重载、数据继续可用，属可继续运行。
 *                         为与之配套，本件用 `_bMaintLatch` 单独记录该类事件，
 *                         `bError` 只由真正的失效级锁存驱动（R21）。
 * 定时器清单 (Timers)   : 实例名 / IN 表达式 / 断输入拍标志 / 自清位置
 *                         fbStaleWatch  / bEnable AND _bAllZero AND NOT _bStaleWatchBreak
 *                                       / _bStaleWatchBreak / 段 4 调用后自清
 *                         fbDemandWatch / bEnable AND NOT _bDemandWatchBreak
 *                                       / _bDemandWatchBreak / 段 4 调用后自清
 *                         断输入拍置位点：进采样态、复位、窗口结算后、字序变更后。
 * 单拍标志清单 (One-shot): `_bResetPulse` 预清 段 1 / 置位 段 7 / 消费 段 7；
 *                         `_bExitFault`  预清 段 1 / 置位 段 7 / 消费 段 8；
 *                         `_bCode0158`   预清 段 1 / 置位 段 3 / 消费 段 12。
 * 保持位清单 (Hold)     : `_fDemandPeak` 每拍由段 10 重写出口（不在窗口切换清）；
 *                         `_fImportAcc` / `_fExportAcc` 跨周期保持，段 9 单点写；
 *                         `_bMaintLatch` 段 7 清除、段 6 置位，段 10 每拍派生出口。
 * 比较基准清单 (Baselines): `_eOrderAbcd` / `_eOrderCdab` —— 字序枚举的比较基准，
 *                         在**声明区**取值、在段 9 只读引用。跨文件枚举一律以
 *                         「声明区基准量」参与比较，使语句段不出现裸类型名（本库
 *                         既有范式，同 FB_DL_EnergyMeterAccum 的 eOrderAbcd）；
 *                         枚举成员语义由此集中在声明区可审查，语句段只比变量。
 * 三元一致表 (R35)      : 量 / 守卫封顶 / 判据运算符
 *                         fVoltTolRatio / 钳到 0.5 / 越规判据用 > 与 < 对称
 *                         fPfLimit      / 钳到 1.0 / 判据 ABS(PF) < 限值
 *                         fThdLimit     / 钳到 50.0 / 判据 > 限值
 *                         需量窗口      / 钳到 ≥1 s / 除零守卫用 > 容差
 * 验收向量 (Acceptance) :
 *   V1 基本换算：三相 2200 LSB（0.1 V/LSB）→ 平均 220.0 V；三相 1000 LSB
 *      （0.01 A/LSB）→ 10.0 A；有功 50000 LSB（0.001 kW/LSB）→ 50.0 kW
 *   V2 需量：15 min 窗、50 kW 恒定、满窗 → 平均 50.0、峰值 50.0
 *   V3（V-C 跨相时序）：使能中摘掉原始值（全零）→ 4 s 仍 eDegraded；5 s 后
 *      转 eFault + 0317；恢复供数后必须 bReset 才回 eSampling（锁存语义）
 *   V4（V-D 首拍）：上电首拍 fEnergyImport 为 0、bValid=FALSE、eHealth=eUnknown，
 *      且首拍只装累计基准，不判回退
 *   V5（V-A 域外）：fKwhPerLsb 为 0 → 0316 锁存，fEnergyImport 保持上次值且仍在
 *      有效域内（R43 钳位）；fVoltPerLsb 填 NaN 同路径（有限性检查先于大小比较）
 * 规格偏离 (Deviation)  :
 *   ① 规格 VAR_INPUT 表未给「额定相电流」，但 fLightLoadRatio 的判据「电流低于
 *      额定的比例」必须有一个基准量，否则该判据无定义。本件补 fCurrentNominal
 *      引脚（默认 100 A），非法值（≤0 或非有限）按标定非正同族处理（0316）。
 *   ② 规格码表要求 015A「复算功率因数与表值偏差」，但引脚表未给表值来源。本件
 *      补 iPfRaw 引脚（表内功率因数寄存器，0.001/LSB，有符号）；填 0 视为表未
 *      提供该寄存器，不做交叉校验（不误报）。
 *   ③ 规格正文提及状态机枚举名 E_DL_PowerMeterPhase；本工程已在 I_DL_PowerMeter
 *      发布成员完全同构的 E_DL_PowerMeterState（0/10/20/99）。再声明一个同构
 *      枚举会让 eState 属性类型二选一、并诱导 CASE 混用两个枚举，故本件直接复用
 *      E_DL_PowerMeterState，不另立枚举（与规格的差异仅此一处，语义零偏差）。
 *   ④ 规格只对「频率越限 ±0.5 Hz 内」分配了 015B，±0.5 Hz 之外无独立码位。
 *      为守住「不得自行新造码位」，本件对越限一律用 015B 表达并统一判 Degraded，
 *      不擅自升级为 Failure；若现场需要更严等级，须下轮申请码位后再拆。
 *   ⑤ 0318 不置 bError（见「码位级裁定」），与规格表中「故障级」三字存在口径
 *      差异，按 NE107 语义与 A5 的 0323 裁定统一。
 * 开源溯源 (Origin)     : 来源标签 namur-ne107 / modbus-meter / meter-contract。
 *                         原创 clean-room 实现。仅借鉴：① NAMUR NE107（公开推荐
 *                         规范，非代码）的健康分级语义；② Modbus 电表的公开寄存器
 *                         惯例（三相量 + 32 位电能高低字 + 功率因数寄存器），
 *                         属行业通行事实，不构成版权标的。标定、拼装、交叉校验、
 *                         需量口径、状态机与全部码位 100% 本库独立设计，未复制
 *                         任何源码行，无许可证传染风险。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R13 · 泳道 A · Phase 1 电表件收口）
 *   2026-11-16  v1.0.1  终审修复两处：① `_bPfMismatch` 补每拍预清零（原实现
 *                       无清零点，一次 015A 即永久 eDegraded，eDegraded→eSampling
 *                       不可达，违 R34/R44）；② 字序枚举比较改为声明区基准量
 *                       `_eOrderAbcd` / `_eOrderCdab`（原语句段直写裸类型名，
 *                       子集机检 undefined_identifier 报 FAIL 2，且与本库既有
 *                       FB_DL_EnergyMeterAccum 范式不一致）。接口与码位零变化。
 *============================================================================*)

FUNCTION_BLOCK FB_DL_ModbusPowerMeter IMPLEMENTS I_DL_PowerMeter
VAR_INPUT
    bEnable          : BOOL;                          // 使能，FALSE 冻结计量与窗口 [-] / Enable, freezes metering and the window
    bReset           : BOOL;                          // 复位窗口/峰值/锁存，上升沿有效 [-] / Rising edge resets window, peak and latch
    auVoltageRaw     : ARRAY[1..3] OF UINT;           // 三相相电压原始值 [LSB]，0.1 V/LSB / Raw phase voltages in LSB
    auCurrentRaw     : ARRAY[1..3] OF UINT;           // 三相电流原始值 [LSB]，0.01 A/LSB / Raw phase currents in LSB
    iActivePowerRaw  : DINT;                          // 总有功原始值 [LSB]，0.001 kW/LSB，有符号 / Raw total active power, signed
    uReactivePowerRaw: UINT;                          // 总无功原始值 [LSB]，0.001 kvar/LSB / Raw total reactive power
    uEnergyImportHi  : UINT;                          // 正向电能高字 [LSB] / Import energy high word
    uEnergyImportLo  : UINT;                          // 正向电能低字 [LSB] / Import energy low word
    uEnergyExportHi  : UINT;                          // 反向电能高字 [LSB] / Export energy high word
    uEnergyExportLo  : UINT;                          // 反向电能低字 [LSB] / Export energy low word
    uFreqRaw         : UINT;                          // 频率原始值 [LSB]，0.01 Hz/LSB / Raw frequency in LSB
    uThdVoltRaw      : UINT;                          // 电压总谐波畸变原始值 [LSB]，0.1 %/LSB / Raw voltage THD
    uThdCurrRaw      : UINT;                          // 电流总谐波畸变原始值 [LSB]，0.1 %/LSB / Raw current THD
    iPfRaw           : INT := 0;                      // 表内功率因数原始值 [LSB]，0.001/LSB，0=表未提供 / Raw meter power factor, zero means absent
    eWordOrder       : E_DL_ByteOrder := E_DL_ByteOrder.eAbcd; // 32 位电能字序约定，默认大字序 [-] / Word order for 32-bit energy
    fVoltPerLsb      : REAL := 0.1;                   // 电压标定 [V/LSB]，域大于 0 且有限 / Voltage scale, positive and finite
    fCurrPerLsb      : REAL := 0.01;                  // 电流标定 [A/LSB]，域大于 0 且有限 / Current scale, positive and finite
    fKwhPerLsb       : REAL := 0.1;                   // 电能标定 [kWh/LSB]，域大于 0 且有限 / Energy scale, positive and finite
    fVoltNominal     : REAL := 220.0;                 // 额定相电压 [V]，范围 100~400 / Nominal phase voltage
    fCurrentNominal  : REAL := 100.0;                 // 额定相电流 [A]，范围 1~10000，轻载判据基准 / Nominal phase current, light-load base
    fVoltTolRatio    : REAL := 0.10;                  // 电压允许偏差比 [-]，范围 0~0.5，默认 ±10% / Voltage tolerance ratio
    fPfLimit         : REAL := 0.85;                  // 功率因数下限 [-]（取绝对值比较），范围 0.5~1.0 / Power factor lower limit
    fThdLimit        : REAL := 5.0;                   // 谐波上限 [%]，范围 1.0~50.0 / Total harmonic distortion limit
    fLightLoadRatio  : REAL := 0.02;                  // 轻载判据比例 [-]（电流低于额定此比例即轻载），范围 0~0.5 / Light-load ratio
    tDemandWindow    : TIME := T#15M;                 // 需量窗口 [毫秒]，域不小于 1 秒 / Demand window, at least one second
    tStaleTimeout    : TIME := T#5S;                  // 数据陈旧超时 [毫秒]，超时判 Failure / Stale-data timeout in milliseconds
END_VAR
VAR_OUTPUT
    bValid           : BOOL;                          // 数据模型本拍有效 [-] / Model valid this scan
    bError           : BOOL;                          // 故障锁存，仅失效级码置位，0318 不置位 / Fault latch, failure codes only
    uErrorId         : UDINT;                         // 末次故障码，0 表示无故障 [代码] / Last fault code, zero means none
    afVoltagePhase   : ARRAY[1..3] OF REAL;           // 分相电压 [V]，范围 0~400 / Per-phase voltages
    fApparentPower   : REAL;                          // 视在功率 [kVA]，等于有功无功的平方和开方 / Apparent power
    fEnergyNet       : LREAL;                         // 净电能，正向减反向 [kWh] / Net energy, import minus export
    fThdVoltageMax   : REAL;                          // 三相电压 THD 最大值 [%] / Maximum voltage THD
    fThdCurrentMax   : REAL;                          // 三相电流 THD 最大值 [%] / Maximum current THD
    fDemandAvg       : REAL;                          // 本窗口平均需量 [kW] / Average demand of the window
    bPhaseLoss       : BOOL;                          // 缺相：一相低于 20% 额定且另两相正常 [-] / Phase loss flag
    bReversePower    : BOOL;                          // 反送电：有功为负且绝对值超 5% 额定 [-] / Reverse power flag
    uMeterSwapCount  : UDINT;                         // 换表或清零识别次数 [次] / Meter swap and clear counter
END_VAR
VAR
    fbTrigReset        : R_TRIG;                      // 复位沿检测，段 4 无条件刷新 [-] / Reset edge detector, refreshed in section 4
    fbStaleWatch       : TON;                         // 陈旧监视，段 4 无条件刷新 [毫秒] / Stale watchdog, refreshed in section 4
    fbDemandWatch      : TON;                         // 需量窗口计时，段 4 无条件刷新 [毫秒] / Demand window timer, refreshed in section 4
    _ePhase            : E_DL_PowerMeterState := E_DL_PowerMeterState.eIdle; // 计量相位（私有），经属性 eState 出口 [-] / Private metering phase
    _bInit             : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据取非 [-] / First-scan flag initialised FALSE
    _bFaultLatch       : BOOL;                        // 失效级锁存，仅复位清 [-] / Failure latch, cleared by reset only
    _bMaintLatch       : BOOL;                        // 维护级锁存（0318），复位或应答清 [-] / Maintenance latch, cleared by reset or ack
    _bEverValid        : BOOL;                        // 曾取得有效数据标志，首拍为 FALSE [-] / Ever-valid flag, FALSE on the first scan
    _uErrFault         : UDINT;                       // 首出故障码寄存 [代码] / First-out fault code register
    _uDiagCode         : UDINT;                       // 当前诊断码（单一优先级链产出）[代码] / Active diagnostic code
    _bPendReset        : BOOL;                        // 方法登记的复位请求 [-] / Reset request registered by the method
    _bPendResetEnergy  : BOOL;                        // 方法登记的清电能请求 [-] / Energy clear request registered by the method
    _bPendAck          : BOOL;                        // 方法登记的应答请求 [-] / Acknowledge request registered by the method
    _bResetPulse       : BOOL;                        // 复位单拍（沿或方法合成）[-] / One-shot reset pulse
    _bExitFault        : BOOL;                        // 退出故障态单拍，仅故障分支消费 [-] / One-shot fault exit request
    _bStaleWatchBreak  : BOOL;                        // 陈旧定时器断输入一拍 [-] / One-scan break of the stale watchdog
    _bDemandWatchBreak : BOOL;                        // 窗口定时器断输入一拍 [-] / One-scan break of the demand timer
    _bWinEnd           : BOOL;                        // 窗口到点标志 [-] / Window boundary flag
    _tStaleUse         : TIME := T#5S;                // 生效陈旧超时 [毫秒]，钳位后 / Effective stale timeout
    _tWinUse           : TIME := T#15M;               // 生效需量窗口 [毫秒]，钳位后 / Effective demand window
    _fVoltLsbUse       : REAL := 0.1;                 // 生效电压标定 [V/LSB] / Effective voltage scale
    _fCurrLsbUse       : REAL := 0.01;                // 生效电流标定 [A/LSB] / Effective current scale
    _fKwhLsbUse        : REAL := 0.1;                 // 生效电能标定 [kWh/LSB] / Effective energy scale
    _fKwhLsbL          : LREAL := 0.1;                // 生效电能标定的长实数副本 [kWh/LSB] / Long real copy of the energy scale
    _fVoltNomUse       : REAL := 220.0;               // 生效额定相电压 [V] / Effective nominal phase voltage
    _fCurrNomUse       : REAL := 100.0;               // 生效额定相电流 [A] / Effective nominal phase current
    _fTolUse           : REAL := 0.10;                // 生效电压偏差比 [-] / Effective voltage tolerance ratio
    _fPfLimitUse       : REAL := 0.85;                // 生效功率因数下限 [-] / Effective power factor limit
    _fThdLimitUse      : REAL := 5.0;                 // 生效谐波上限 [%] / Effective THD limit
    _fLightUse         : REAL := 0.02;                // 生效轻载比例 [-] / Effective light-load ratio
    _fRatedPower       : REAL := 66.0;                // 额定视在功率 [kW]，反送与矛盾判据基准 / Rated apparent power
    _afVolt            : ARRAY[1..3] OF REAL;         // 分相电压换算中间量 [V] / Per-phase voltage working copy
    _afCurr            : ARRAY[1..3] OF REAL;         // 分相电流换算中间量 [A] / Per-phase current working copy
    _fVoltAvg          : REAL;                        // 三相平均相电压 [V] / Average phase voltage
    _fCurrAvg          : REAL;                        // 三相平均电流 [A] / Average phase current
    _fP                : REAL;                        // 总有功 [kW]，有符号 / Total active power, signed
    _fQ                : REAL;                        // 总无功 [kvar] / Total reactive power
    _fS                : REAL;                        // 视在功率 [kVA] / Apparent power
    _fPf               : REAL;                        // 复算功率因数 [-] / Recomputed power factor
    _fPfTable          : REAL;                        // 表内功率因数 [-] / Meter power factor
    _fFreq             : REAL;                        // 电网频率 [Hz] / Grid frequency
    _fThdVmax          : REAL;                        // 电压 THD 最大值 [%] / Maximum voltage THD
    _fThdCmax          : REAL;                        // 电流 THD 最大值 [%] / Maximum current THD
    _uImportRaw        : UDINT;                       // 正向电能 32 位拼装值 [LSB] / Stitched import raw value
    _uExportRaw        : UDINT;                       // 反向电能 32 位拼装值 [LSB] / Stitched export raw value
    _fImportNow        : LREAL;                       // 本拍正向电能换算值 [kWh] / Import energy of this scan
    _fExportNow        : LREAL;                       // 本拍反向电能换算值 [kWh] / Export energy of this scan
    _fImportAcc        : LREAL;                       // 正向累计电能 [kWh] / Accumulated import energy
    _fExportAcc        : LREAL;                       // 反向累计电能 [kWh] / Accumulated export energy
    _bEnergyBase       : BOOL;                        // 正反向累计基准已装载标志 [-] / Energy baseline loaded flag
    _fRegressThr       : LREAL;                       // 本拍回退判定阈值 [kWh] / Regression threshold of this scan
    _fWinPSum          : REAL;                        // 本窗口功率采样累加 [kW] / Power sample sum of the window
    _nWinCount         : UDINT;                       // 本窗口功率采样拍数 [拍] / Sample count of the window
    _fDemandAvg        : REAL;                        // 本窗口平均需量 [kW] / Average demand of the window
    _fDemandPeak       : REAL;                        // 历史峰值需量 [kW] / Peak demand
    _fUnbalance        : REAL;                        // 三相电压不平衡度 [比值] / Voltage unbalance ratio
    _fDevMax           : REAL;                        // 单相偏离平均值的最大绝对值 [V] / Maximum deviation from the average
    _fThrLow           : REAL;                        // 欠压阈值 [V] / Under-voltage threshold
    _fThrHigh          : REAL;                        // 过压阈值 [V] / Over-voltage threshold
    _fThrPhaseLoss     : REAL;                        // 缺相判据阈值 [V] / Phase-loss threshold
    _fThrPhaseOk       : REAL;                        // 正常相判据阈值 [V] / Healthy-phase threshold
    _nPhaseLow         : INT;                         // 低压相计数 [相] / Count of low-voltage phases
    _nPhaseOk          : INT;                         // 正常相计数 [相] / Count of healthy phases
    _nIdx              : DINT;                        // 相序循环索引 [1~3] / Phase loop index
    _bAllZero          : BOOL;                        // 原始寄存器全零标志 [-] / All-zero raw registers flag
    _bStale            : BOOL;                        // 陈旧超时标志 [-] / Stale timeout flag
    _bCalBad           : BOOL;                        // 标定非法标志 [-] / Illegal calibration flag
    _bFiniteP          : BOOL;                        // 有功功率有限标志 [-] / Finite active power flag
    _bValidInt         : BOOL;                        // 数据本拍有效（内部定义）[-] / Data valid this scan, internal
    _bPhaseLossInt     : BOOL;                        // 缺相（内部定义）[-] / Phase loss, internal
    _bReverseInt       : BOOL;                        // 反送电（内部定义）[-] / Reverse power, internal
    _bUnbalance        : BOOL;                        // 不平衡度超 2% [-] / Unbalance above two percent
    _bOverVolt         : BOOL;                        // 过压 [-] / Over voltage
    _bUnderVolt        : BOOL;                        // 欠压 [-] / Under voltage
    _bThdHigh          : BOOL;                        // 谐波越限（抑制后）[-] / THD above limit after suppression
    _bPfLow            : BOOL;                        // 功率因数越限（抑制后）[-] / PF below limit after suppression
    _bThdHighRaw       : BOOL;                        // 谐波越限原始判据 [-] / Raw THD criterion
    _bPfLowRaw         : BOOL;                        // 功率因数越限原始判据 [-] / Raw PF criterion
    _bFreqOut          : BOOL;                        // 频率越限 [-] / Frequency out of window
    _bLightLoad        : BOOL;                        // 轻载 [-] / Light load
    _bPfTableOk        : BOOL;                        // 表内功率因数可用 [-] / Meter power factor usable
    _bPfMismatch       : BOOL;                        // 复算与表值偏差超 3% [-] / Recomputed PF differs from the meter
    _bContra           : BOOL;                        // 电流全零而有功非零 [-] / Zero current with non-zero power
    _bCode0156         : BOOL;                        // 信息码 0156 候选 [-] / Info code 0156 candidate
    _bCode0157         : BOOL;                        // 信息码 0157 候选 [-] / Info code 0157 candidate
    _bCode0158         : BOOL;                        // 信息码 0158 候选 [-] / Info code 0158 candidate
    _bCode0159         : BOOL;                        // 信息码 0159 候选 [-] / Info code 0159 candidate
    _bCode015A         : BOOL;                        // 信息码 015A 候选 [-] / Info code 015A candidate
    _bCode015B         : BOOL;                        // 信息码 015B 候选 [-] / Info code 015B candidate
    _uSwapCount        : UDINT;                       // 换表累计次数 [次] / Swap counter
    _eOrderPrev        : E_DL_ByteOrder := E_DL_ByteOrder.eAbcd; // 上一拍字序（变化检测唯一消费点）[-] / Previous word order
    _eOrderAbcd        : E_DL_ByteOrder := E_DL_ByteOrder.eAbcd; // 字序比较基准：大字序口径 [-] / Word order baseline, big word first
    _eOrderCdab        : E_DL_ByteOrder := E_DL_ByteOrder.eCdab; // 字序比较基准：低字在前口径 [-] / Word order baseline, low word first
    _eHealthInt        : E_DL_Ne107Status := E_DL_Ne107Status.eUnknown; // 健康态内部量，经属性出口 [-] / Internal health state
    _bDegradedNow      : BOOL;                        // 本拍越规标志 [-] / Out-of-spec flag of this scan
END_VAR
VAR CONSTANT
    DL_KW_PER_LSB      : REAL := 0.001;               // 有功每 LSB [kW/LSB] / Kilowatts per LSB
    DL_VAR_PER_LSB     : REAL := 0.001;               // 无功每 LSB [kvar/LSB] / Kilovars per LSB
    DL_HZ_PER_LSB      : REAL := 0.01;                // 频率每 LSB [Hz/LSB] / Hertz per LSB
    DL_PCT_PER_LSB     : REAL := 0.1;                 // 谐波每 LSB [%/LSB] / Percent per LSB
    DL_PF_PER_LSB      : REAL := 0.001;               // 功率因数每 LSB [-/LSB] / Power factor per LSB
    DL_EPS             : REAL := 1.0E-6;              // 浮点比较容差 [-] / Float comparison tolerance
    DL_VOLT_LSB_FB     : REAL := 0.1;                 // 电压标定非法时的兜底 [V/LSB] / Voltage scale fallback
    DL_CURR_LSB_FB     : REAL := 0.01;                // 电流标定非法时的兜底 [A/LSB] / Current scale fallback
    DL_KWH_LSB_FB      : REAL := 0.1;                 // 电能标定非法时的兜底 [kWh/LSB] / Energy scale fallback
    DL_VOLT_MAX        : REAL := 1.0E6;               // 电气量合理上限，超出视为非有限 [V] / Voltage sanity limit
    DL_POWER_MAX       : REAL := 1.0E6;               // 功率合理上限，超出视为非有限 [kW] / Power sanity limit
    DL_WIN_MIN         : TIME := T#1S;                // 需量窗口下限 [毫秒] / Minimum demand window
    DL_STALE_MIN       : TIME := T#1S;                // 陈旧超时下限 [毫秒] / Minimum stale timeout
    DL_REGRESS_RATIO   : LREAL := 0.01;               // 判为换表的回退比例 [-] / Regression ratio for a meter swap
    DL_PF_MISMATCH     : REAL := 0.03;                // 复算与表值允许偏差 [-] / Allowed power factor mismatch
    DL_UNBALANCE_LIM   : REAL := 0.02;                // 不平衡度提示阈 [-] / Unbalance advisory limit
    DL_FREQ_LOW        : REAL := 45.0;                // 频率下限 [Hz] / Lower frequency limit
    DL_FREQ_HIGH       : REAL := 65.0;                // 频率上限 [Hz] / Upper frequency limit
    DL_FREQ_BAND       : REAL := 0.5;                 // 频率判降级的边带 [Hz] / Frequency downgrade band
    DL_REVERSE_RATIO   : REAL := 0.05;                // 反送电判据比例 [-] / Reverse power ratio
    DL_PHASE_LOSS_R    : REAL := 0.20;                // 缺相判据：低于额定的比例 [-] / Phase-loss ratio
    DL_PHASE_OK_R      : REAL := 0.80;                // 正常相判据：高于额定的比例 [-] / Healthy-phase ratio
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜确定性默认值与单拍标志预清零（R25 第一律：预清零）
 *      Deterministic defaults and one-shot flags pre-cleared every scan
 *-----------------------------------------------------------------------------*)
bValid           := FALSE;                          // 有效位先按无效处理，段 6 判定后重写（Presumed invalid until section 6）
_bResetPulse     := FALSE;                          // 复位单拍预清零（Reset pulse pre-cleared）
_bExitFault      := FALSE;                          // 退出故障单拍预清零（Fault exit pre-cleared）
_bCode0156       := FALSE;                          // 0156 候选预清零（0156 candidate cleared）
_bCode0157       := FALSE;                          // 0157 候选预清零（0157 candidate cleared）
_bCode0158       := FALSE;                          // 0158 候选预清零（0158 candidate cleared）
_bCode0159       := FALSE;                          // 0159 候选预清零（0159 candidate cleared）
_bCode015A       := FALSE;                          // 015A 候选预清零（015A candidate cleared）
_bCode015B       := FALSE;                          // 015B 候选预清零（015B candidate cleared）
_bCalBad         := FALSE;                          // 标定非法预清零（Calibration fault pre-cleared）
_bFiniteP        := FALSE;                          // 功率有限标志预清零（Finite power pre-cleared）
_bContra         := FALSE;                          // 矛盾判据预清零（Contradiction pre-cleared）
_bPfMismatch     := FALSE;                          // 15A 交叉校验判据预清零，绝不可跨拍残留（PF mismatch pre-cleared every scan）
_bDegradedNow    := FALSE;                          // 越规标志预清零（Out-of-spec pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19：bInit 初值 FALSE，判据一律取非；首拍只装基准）
 *      First-scan initialisation, baseline only, no judgement on the first scan
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _fImportAcc    := 0.0;                          // 正向累计清零（Import accumulation cleared）
    _fExportAcc    := 0.0;                          // 反向累计清零（Export accumulation cleared）
    _fWinPSum      := 0.0;                          // 窗口功率累加清零（Window power sum cleared）
    _nWinCount     := 0;                            // 窗口拍数清零（Window count cleared）
    _fDemandAvg    := 0.0;                          // 平均需量清零（Average demand cleared）
    _fDemandPeak   := 0.0;                          // 峰值需量清零（Peak demand cleared）
    _uSwapCount    := 0;                            // 换表次数清零（Swap counter cleared）
    _bEnergyBase   := FALSE;                        // 累计基准待装载，首拍不判回退（Baseline pending, no regression on the first scan）
    _bEverValid    := FALSE;                        // 尚未取得有效数据（No valid data yet）
    _bFaultLatch   := FALSE;                        // 失效锁存清零（Failure latch cleared）
    _bMaintLatch   := FALSE;                        // 维护锁存清零（Maintenance latch cleared）
    _uErrFault     := 16#0000_0000;                 // 首出码清零（First-out code cleared）
    _ePhase        := E_DL_PowerMeterState.eIdle;   // 相位复位为待机（Phase reset to idle）
    _eOrderPrev    := eWordOrder;                   // 首拍记录字序基准（Order baseline recorded）
    _bPendReset    := FALSE;                        // 方法请求清零（Method request cleared）
    _bPendResetEnergy := FALSE;                     // 方法请求清零（Method request cleared）
    _bPendAck      := FALSE;                        // 方法请求清零（Method request cleared）
    _bInit         := TRUE;                         // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门与标定校验（非正/非有限即失效级；越界只钳位不停机）
 *      Parameter gate: non-positive or non-finite scales latch a failure,
 *      out-of-range tuning values are merely clamped
 *-----------------------------------------------------------------------------*)
(* 电压标定：NaN 会让两侧比较同时为假，故用「区间内」写法做有限性判定，不写浮点判等 *)
IF (fVoltPerLsb > DL_EPS) AND (fVoltPerLsb <= DL_VOLT_MAX) THEN
    _fVoltLsbUse := fVoltPerLsb;                    // 合法标定直通（Valid scale passed through）
ELSE
    _fVoltLsbUse := DL_VOLT_LSB_FB;                 // 兜底标定，防零乘与 NaN 扩散（Fallback scale avoids NaN spread）
    _bCalBad     := TRUE;                           // 标定非法（Illegal calibration）
END_IF

IF (fCurrPerLsb > DL_EPS) AND (fCurrPerLsb <= DL_VOLT_MAX) THEN
    _fCurrLsbUse := fCurrPerLsb;                    // 合法标定直通（Valid scale passed through）
ELSE
    _fCurrLsbUse := DL_CURR_LSB_FB;                 // 兜底标定（Fallback scale）
    _bCalBad     := TRUE;                           // 标定非法（Illegal calibration）
END_IF

IF (fKwhPerLsb > DL_EPS) AND (fKwhPerLsb <= DL_VOLT_MAX) THEN
    _fKwhLsbUse := fKwhPerLsb;                      // 合法标定直通（Valid scale passed through）
ELSE
    _fKwhLsbUse := DL_KWH_LSB_FB;                   // 兜底标定（Fallback scale）
    _bCalBad    := TRUE;                            // 标定非法（Illegal calibration）
END_IF
_fKwhLsbL := REAL_TO_LREAL(_fKwhLsbUse);            // 长实数副本：累计量精度保护（Long real copy for accuracy）

IF (fVoltNominal >= 100.0) AND (fVoltNominal <= 400.0) THEN
    _fVoltNomUse := fVoltNominal;                   // 额定电压直通（Nominal voltage passed through）
ELSE
    _fVoltNomUse := 220.0;                          // 越界按 220 V 兜底（Clamped to the default nominal）
    _bCalBad     := TRUE;                           // 基准非法同族处理（Illegal base treated as a calibration fault）
END_IF

IF (fCurrentNominal >= 1.0) AND (fCurrentNominal <= 10000.0) THEN
    _fCurrNomUse := fCurrentNominal;                // 额定电流直通（Nominal current passed through）
ELSE
    _fCurrNomUse := 100.0;                          // 越界按 100 A 兜底（Clamped to the default nominal）
    _bCalBad     := TRUE;                           // 基准非法同族处理（Illegal base treated as a calibration fault）
END_IF

IF fVoltTolRatio < 0.0 THEN
    _fTolUse := 0.0;                                // 负偏差比无意义，钳到 0（Negative tolerance clamped）
ELSIF fVoltTolRatio > 0.5 THEN
    _fTolUse := 0.5;                                // 超 0.5 钳到 0.5（Tolerance above half clamped）
ELSE
    _fTolUse := fVoltTolRatio;                      // 合法值直通（Valid tolerance passed through）
END_IF

IF fPfLimit < 0.5 THEN
    _fPfLimitUse := 0.5;                            // 下限钳位，防恒真判据（Clamped to avoid an always-true test）
ELSIF fPfLimit > 1.0 THEN
    _fPfLimitUse := 1.0;                            // 上限钳位（Clamped to one）
ELSE
    _fPfLimitUse := fPfLimit;                       // 合法值直通（Valid limit passed through）
END_IF

IF fThdLimit < 1.0 THEN
    _fThdLimitUse := 1.0;                           // 下限钳位（Lower clamp）
ELSIF fThdLimit > 50.0 THEN
    _fThdLimitUse := 50.0;                          // 上限钳位（Upper clamp）
ELSE
    _fThdLimitUse := fThdLimit;                     // 合法值直通（Valid limit passed through）
END_IF

IF fLightLoadRatio < 0.0 THEN
    _fLightUse := 0.0;                              // 负比例钳到 0（Negative ratio clamped）
ELSIF fLightLoadRatio > 0.5 THEN
    _fLightUse := 0.5;                              // 超 0.5 钳到 0.5（Ratio above half clamped）
ELSE
    _fLightUse := fLightLoadRatio;                  // 合法值直通（Valid ratio passed through）
END_IF

IF tDemandWindow < DL_WIN_MIN THEN
    _tWinUse   := DL_WIN_MIN;                       // 小于 1 秒按 1 秒兜底，防需量除零（Clamped to avoid a zero divisor）
    _bCode0157 := TRUE;                             // 0157 窗口过短已兜底（Window clamped）
ELSE
    _tWinUse := tDemandWindow;                      // 合法窗口直通（Valid window passed through）
END_IF

IF tStaleTimeout < DL_STALE_MIN THEN
    _tStaleUse := DL_STALE_MIN;                     // 小于 1 秒按 1 秒兜底，防恒定陈旧（Clamped to avoid permanent staleness）
ELSE
    _tStaleUse := tStaleTimeout;                    // 合法超时直通（Valid timeout passed through）
END_IF

(* 额定视在功率：三相之和，反送与矛盾判据的基准量（防除零由额定电流闸门保证） *)
_fRatedPower := _fVoltNomUse * _fCurrNomUse * 3.0 * DL_KW_PER_LSB;

(* 字序变化检测：只做不等比较，唯一消费点在本段（R38 合规） *)
IF eWordOrder <> _eOrderPrev THEN
    _bCode0158     := TRUE;                         // 0158 字序变更（Order changed）
    _bEnergyBase   := FALSE;                        // 重载累计基准，避免把字序切换误判为换表（Reload the baseline）
    _bStaleWatchBreak := TRUE;                      // 陈旧监视重启，避免跨字序累加（Restart the watchdog）
    _eOrderPrev    := eWordOrder;                   // 记录新字序（Record the new order）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜定时器与边沿实例无条件刷新（红线：实例一律在 CASE 之外每拍必调）
 *      Timers and edge detectors refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
(* 全零判据为纯组合量，先算再喂定时器（不设镜像量，避免双源，R38） *)
_bAllZero := (auVoltageRaw[1] = 0) AND (auVoltageRaw[2] = 0) AND (auVoltageRaw[3] = 0)
          AND (auCurrentRaw[1] = 0) AND (auCurrentRaw[2] = 0) AND (auCurrentRaw[3] = 0)
          AND (iActivePowerRaw = 0) AND (uFreqRaw = 0); // 全零：表掉线或未上电（All zero, the meter is offline）

fbTrigReset(CLK := bReset);                         // 复位沿检测无条件刷新（Reset edge refreshed）

fbStaleWatch(IN := bEnable AND _bAllZero AND (NOT _bStaleWatchBreak), PT := _tStaleUse); // 陈旧监视：全零持续计时
_bStaleWatchBreak := FALSE;                         // 断输入拍在实例调用后自清（Break pulse self-cleared）
_bStale := fbStaleWatch.Q;                          // 陈旧标志在实例调用后取用（Stale flag read after the call）

fbDemandWatch(IN := bEnable AND (NOT _bDemandWatchBreak), PT := _tWinUse); // 需量窗口无条件刷新
_bDemandWatchBreak := FALSE;                        // 断输入拍自清（Break pulse self-cleared）
_bWinEnd := fbDemandWatch.Q;                        // 到点标志在实例调用后取用（Boundary flag read after the call）

(*------------------------------------------------------------------------------
 * 段 5｜工程量换算（标定后的三相量、功率、功率因数、频率、谐波）
 *      Engineering conversion after scaling
 *-----------------------------------------------------------------------------*)
FOR _nIdx := 1 TO 3 DO
    (* 数组访问前强制校验上下界，三平台下界均为 1 但不得假定（Bound check before indexing） *)
    IF (_nIdx >= LOWER_BOUND(auVoltageRaw, 1)) AND (_nIdx <= UPPER_BOUND(auVoltageRaw, 1)) THEN
        _afVolt[_nIdx] := UINT_TO_REAL(auVoltageRaw[_nIdx]) * _fVoltLsbUse; // 分相电压换算（Per-phase voltage）
    ELSE
        _afVolt[_nIdx] := 0.0;                      // 越界置 0，绝不越界写（Out of range writes zero）
    END_IF
    IF (_nIdx >= LOWER_BOUND(auCurrentRaw, 1)) AND (_nIdx <= UPPER_BOUND(auCurrentRaw, 1)) THEN
        _afCurr[_nIdx] := UINT_TO_REAL(auCurrentRaw[_nIdx]) * _fCurrLsbUse; // 分相电流换算（Per-phase current）
    ELSE
        _afCurr[_nIdx] := 0.0;                      // 越界置 0（Out of range writes zero）
    END_IF
END_FOR

_fVoltAvg := (_afVolt[1] + _afVolt[2] + _afVolt[3]) / 3.0; // 平均相电压，除数恒为 3（Average phase voltage）
_fCurrAvg := (_afCurr[1] + _afCurr[2] + _afCurr[3]) / 3.0; // 平均相电流（Average phase current）
_fP       := DINT_TO_REAL(iActivePowerRaw) * DL_KW_PER_LSB; // 总有功，保留符号（Total active power, signed）
_fQ       := UINT_TO_REAL(uReactivePowerRaw) * DL_VAR_PER_LSB; // 总无功（Total reactive power）
_fFreq    := UINT_TO_REAL(uFreqRaw) * DL_HZ_PER_LSB;       // 电网频率（Grid frequency）
_fThdVmax := UINT_TO_REAL(uThdVoltRaw) * DL_PCT_PER_LSB;   // 电压谐波（取三相最大值口径）
_fThdCmax := UINT_TO_REAL(uThdCurrRaw) * DL_PCT_PER_LSB;   // 电流谐波（取三相最大值口径）

(* 视在功率与功率因数复算：先判分母再除，绝不裸除（Guard the divisor before dividing） *)
IF (_fP >= -DL_POWER_MAX) AND (_fP <= DL_POWER_MAX) AND (_fQ >= -DL_POWER_MAX) AND (_fQ <= DL_POWER_MAX) THEN
    _bFiniteP := TRUE;                              // 有功无功均在合理域内（Both within the sanity band）
    _fS       := SQRT(_fP * _fP + _fQ * _fQ);       // 视在功率（Apparent power）
ELSE
    _bFiniteP := FALSE;                             // 非有限：本拍不做功率派生计算（Non-finite, skip derived values）
    _fS       := 0.0;                               // 视在功率置 0，防 NaN 扩散（Zero avoids NaN spread）
END_IF

IF _fS > DL_EPS THEN
    _fPf := _fP / _fS;                              // 复算功率因数，含符号（Recomputed power factor, signed）
    _fPf := LIMIT(-1.0, _fPf, 1.0);                 // 钳进物理域，防除零放大（Clamped into the physical band）
ELSE
    _fPf := 0.0;                                    // 空载：功率因数无定义，输出 0（No load, undefined PF reported as zero）
END_IF

(* 表内功率因数：0 视为表未提供，不做交叉校验（A zero raw value means the register is absent） *)
IF iPfRaw <> 0 THEN
    _fPfTable   := INT_TO_REAL(iPfRaw) * DL_PF_PER_LSB; // 表值换算（Meter value conversion）
    _bPfTableOk := TRUE;                            // 表值可用（Meter value usable）
ELSE
    _fPfTable   := 0.0;                             // 表值缺省（Meter value absent）
    _bPfTableOk := FALSE;                           // 不做交叉校验（No cross check）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜有效性与数据质量判定（越规族与失效族在此分流）
 *      Validity and data-quality decisions, splitting spec violations from
 *      trustworthy-data loss
 *-----------------------------------------------------------------------------*)
_bLightLoad := _fCurrAvg < (_fCurrNomUse * _fLightUse); // 轻载判据（Light-load test）

_fThrLow       := _fVoltNomUse * (1.0 - _fTolUse);      // 欠压阈值（Under-voltage threshold）
_fThrHigh      := _fVoltNomUse * (1.0 + _fTolUse);      // 过压阈值（Over-voltage threshold）
_fThrPhaseLoss := _fVoltNomUse * DL_PHASE_LOSS_R;       // 缺相阈值（Phase-loss threshold）
_fThrPhaseOk   := _fVoltNomUse * DL_PHASE_OK_R;         // 正常相阈值（Healthy-phase threshold）

_bOverVolt  := _fVoltAvg > _fThrHigh;                   // 过压（Over voltage）
_bUnderVolt := _fVoltAvg < _fThrLow;                    // 欠压（Under voltage）

(* 缺相：恰好一相低于 20% 额定，另两相均高于 80% 额定；三相全低不算缺相 *)
_nPhaseLow := 0;                                        // 低压相计数清零（Low-phase count cleared）
_nPhaseOk  := 0;                                        // 正常相计数清零（Healthy-phase count cleared）
FOR _nIdx := 1 TO 3 DO
    IF (_nIdx >= LOWER_BOUND(_afVolt, 1)) AND (_nIdx <= UPPER_BOUND(_afVolt, 1)) THEN
        IF _afVolt[_nIdx] < _fThrPhaseLoss THEN
            _nPhaseLow := _nPhaseLow + 1;           // 记一相低压（Count one low phase）
        ELSIF _afVolt[_nIdx] >= _fThrPhaseOk THEN
            _nPhaseOk := _nPhaseOk + 1;             // 记一相正常（Count one healthy phase）
        END_IF
    END_IF
END_FOR
_bPhaseLossInt := (_nPhaseLow = 1) AND (_nPhaseOk = 2);  // 一低两正常才判缺相（Exactly one low with two healthy）

(* 三相不平衡度：最大偏离平均值的绝对值除以平均值，分母前置守卫 *)
_fDevMax := 0.0;                                        // 最大偏离清零（Maximum deviation cleared）
FOR _nIdx := 1 TO 3 DO
    IF (_nIdx >= LOWER_BOUND(_afVolt, 1)) AND (_nIdx <= UPPER_BOUND(_afVolt, 1)) THEN
        IF ABS(_afVolt[_nIdx] - _fVoltAvg) > _fDevMax THEN
            _fDevMax := ABS(_afVolt[_nIdx] - _fVoltAvg); // 取最大偏离（Keep the largest deviation）
        END_IF
    END_IF
END_FOR
IF _fVoltAvg > DL_EPS THEN
    _fUnbalance := _fDevMax / _fVoltAvg;                // 不平衡度，防除零（Unbalance ratio, divisor guarded）
ELSE
    _fUnbalance := 0.0;                                 // 无压时不判不平衡（No voltage, no unbalance verdict）
END_IF
_bUnbalance := _fUnbalance > DL_UNBALANCE_LIM;          // 超 2% 提示（Above two percent, advisory）
IF _bUnbalance AND (NOT _bOverVolt) AND (NOT _bUnderVolt) THEN
    _bCode0156 := TRUE;                                 // 0156 不平衡但未越压限，只提示不降级（Advisory only）
END_IF

(* 谐波与功率因数：先算原始判据，轻载下抑制，避免小电流把比值放大成误报 *)
_bThdHighRaw := (_fThdVmax > _fThdLimitUse) OR (_fThdCmax > _fThdLimitUse); // 谐波越限原始判据（Raw THD criterion）
_bPfLowRaw   := ABS(_fPf) < _fPfLimitUse;           // 功率因数越限原始判据，取绝对值（Raw PF criterion）
IF _bLightLoad THEN
    _bThdHigh := FALSE;                             // 轻载抑制谐波判据（THD suppressed at light load）
    _bPfLow   := FALSE;                             // 轻载抑制功率因数判据（PF suppressed at light load）
    IF _bThdHighRaw OR _bPfLowRaw THEN
        _bCode0159 := TRUE;                         // 0159 确有越限被抑制，才置提示码（Set only when a criterion was really suppressed）
    END_IF
ELSE
    _bThdHigh := _bThdHighRaw;                      // 非轻载：判据直通（Criteria passed through）
    _bPfLow   := _bPfLowRaw;                        // 非轻载：判据直通（Criteria passed through）
END_IF

(* 频率越限：45~65 Hz 为合规带，带外统一判降级（无独立码位，见偏离留档 ⑤） *)
_bFreqOut := (_fFreq < (DL_FREQ_LOW - DL_FREQ_BAND)) OR (_fFreq > (DL_FREQ_HIGH + DL_FREQ_BAND));
IF _bFreqOut THEN
    _bCode015B := TRUE;                                 // 015B 频率越限（Frequency out of window）
END_IF

(* 复算与表值交叉校验：轻载不判，表未提供不判（Avoid false mismatches） *)
IF _bPfTableOk AND (NOT _bLightLoad) THEN
    IF ABS(_fPf - _fPfTable) > DL_PF_MISMATCH THEN
        _bPfMismatch := TRUE;                           // 偏差超 3%（Difference above three percent）
        _bCode015A   := TRUE;                           // 015A 复算与表值不符（Recomputed PF differs）
    END_IF
END_IF

(* 数据自相矛盾：电流全零而有功非零（Zero current with non-zero power） *)
_bContra := bEnable AND (_fCurrAvg < DL_EPS) AND (ABS(_fP) > (_fRatedPower * DL_REVERSE_RATIO));

(* 反送电：有功为负且绝对值超 5% 额定（Reverse power above five percent） *)
_bReverseInt := (_fP < 0.0) AND (ABS(_fP) > (_fRatedPower * DL_REVERSE_RATIO));

(* 数据本拍有效：使能、标定合法、非陈旧、功率有限、且曾取得过有效数据 *)
IF bEnable AND (NOT _bCalBad) AND (NOT _bStale) AND _bFiniteP THEN
    IF (NOT _bAllZero) OR _bEverValid THEN
        _bValidInt := TRUE;                             // 数据可用（Data usable）
    ELSE
        _bValidInt := FALSE;                            // 首拍全零：只装基准，不判有效（First scan all zero）
    END_IF
ELSE
    _bValidInt := FALSE;                                // 任一前置条件不满足即无效（Any precondition fails）
END_IF

IF _bValidInt AND (NOT _bEverValid) THEN
    _bEverValid := TRUE;                                // 首次取得有效数据（First valid sample seen）
END_IF

(* 越规族汇总：越规不改数据可信度，只降级（Spec violations degrade, never invalidate）
 * 注：不平衡（0156）与轻载抑制（0159）属提示级，不进降级汇总 *)
_bDegradedNow := (_bOverVolt OR _bUnderVolt OR _bPhaseLossInt OR _bThdHigh OR _bPfLow OR _bFreqOut OR _bPfMismatch) AND (NOT _bCalBad);

(*------------------------------------------------------------------------------
 * 段 7｜复位通道 + 故障锁存（CASE 前置；**不做任何状态变量赋值**，R39）
 *      Reset channel and fault latching before the CASE, without any state
 *      assignment, so a frozen enable branch can never swallow the reset edge
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q OR _bPendReset THEN
    _bResetPulse := TRUE;                               // 合成复位单拍（Compose the one-shot reset pulse）
    _bPendReset  := FALSE;                              // 方法请求消费后自清（Request consumed and cleared）
END_IF

(* 清电能与复位锁存是两条通道：前者只清窗口/峰值/基准，**绝不清锁存、不改状态**，
 * 否则 CmdResetEnergy 就成了绕开失效锁存的旁路，违背受理契约 *)
IF _bPendResetEnergy AND (NOT _bFaultLatch) THEN
    _fWinPSum    := 0.0;                                // 清窗口累加（Window sum cleared）
    _nWinCount   := 0;                                  // 清窗口拍数（Window count cleared）
    _fDemandAvg  := 0.0;                                // 清平均需量（Average demand cleared）
    _fDemandPeak := 0.0;                                // 清峰值需量（Peak demand cleared）
    _bEnergyBase := FALSE;                              // 重载累计基准（Baseline reloaded）
    _bDemandWatchBreak := TRUE;                         // 窗口计时重启（Window timer restarted）
    _bPendResetEnergy  := FALSE;                        // 请求消费后自清（Request consumed and cleared）
END_IF

IF _bResetPulse THEN
    _bFaultLatch := FALSE;                              // 清失效锁存（Failure latch cleared）
    _bMaintLatch := FALSE;                              // 清维护锁存（Maintenance latch cleared）
    _uErrFault   := 16#0000_0000;                       // 清首出码（First-out code cleared）
    _fWinPSum    := 0.0;                                // 清窗口累加（Window sum cleared）
    _nWinCount   := 0;                                  // 清窗口拍数（Window count cleared）
    _fDemandAvg  := 0.0;                                // 清平均需量（Average demand cleared）
    _fDemandPeak := 0.0;                                // 清峰值需量（Peak demand cleared）
    _bEnergyBase := FALSE;                              // 重装累计基准，复位后首拍不判回退（Baseline reloaded）
    _bStaleWatchBreak  := TRUE;                         // 陈旧监视重启（Watchdog restarted）
    _bDemandWatchBreak := TRUE;                         // 窗口计时重启（Window timer restarted）
    IF _ePhase = E_DL_PowerMeterState.eFault THEN
        _bExitFault := TRUE;                            // 显式排除：仅故障态才登记出口请求（Explicit fault-only exit）
    END_IF
END_IF

IF _bPendAck THEN
    _bMaintLatch := FALSE;                              // 应答清维护锁存（Ack clears the maintenance latch）
    _bPendAck    := FALSE;                              // 请求消费后自清（Request consumed and cleared）
END_IF

(* 失效级锁存：首出码只在首次锁存时写入，唯一置位点（First-out code written once） *)
IF _bCalBad AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_0316;                       // 0316 标定非正或非有限（Illegal calibration）
    _bFaultLatch := TRUE;                               // 锁存（Latched）
ELSIF _bStale AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_0317;                       // 0317 全零且超陈旧超时（Stale all-zero registers）
    _bFaultLatch := TRUE;                               // 锁存（Latched）
ELSIF _bContra AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_031A;                       // 031A 电流全零而有功非零（Contradiction）
    _bFaultLatch := TRUE;                               // 锁存（Latched）
ELSIF (NOT _bFiniteP) AND bEnable AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_031B;                       // 031B 功率非有限（Non-finite power）
    _bFaultLatch := TRUE;                               // 锁存（Latched）
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜计量状态机（4 个成员各一标签 + ELSE 兜底；枚举来自接口文件，不重复声明）
 *      Metering state machine, one label per member plus a trailing fallback
 *      eIdle(0) / eSampling(10) / eDegraded(20) / eFault(99)
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF

    E_DL_PowerMeterState.eIdle: // 待机：参数可用且使能后进入采样
        IF _bFaultLatch THEN
            _ePhase := E_DL_PowerMeterState.eFault;     // 已有锁存：直接进故障（Latched, enter the fault state）
        ELSIF bEnable AND (NOT _bCalBad) THEN
            _bStaleWatchBreak  := TRUE;                 // 进采样：陈旧监视从 0 起算（Watchdog restarts on entry）
            _bDemandWatchBreak := TRUE;                 // 进采样：窗口从 0 起算（Window restarts on entry）
            _ePhase := E_DL_PowerMeterState.eSampling;  // 进采样（Enter sampling）
        END_IF

    E_DL_PowerMeterState.eSampling: // 采样：全量换算与判据
        IF _bFaultLatch THEN
            _ePhase := E_DL_PowerMeterState.eFault;     // 数据不可信：进故障（Untrustworthy data, enter the fault state）
        ELSIF NOT bEnable THEN
            _ePhase := E_DL_PowerMeterState.eIdle;      // 掉使能：冻结回待机，出口保持（Disabled, freeze back to idle）
        ELSIF _bDegradedNow THEN
            _ePhase := E_DL_PowerMeterState.eDegraded;  // 越规但可信：降级（Out of spec yet trustworthy, degrade）
        END_IF

    E_DL_PowerMeterState.eDegraded: // 降级：继续计量，恢复即回采样
        IF _bFaultLatch THEN
            _ePhase := E_DL_PowerMeterState.eFault;     // 转故障（Enter the fault state）
        ELSIF NOT bEnable THEN
            _ePhase := E_DL_PowerMeterState.eIdle;      // 掉使能冻结（Disabled, freeze）
        ELSIF NOT _bDegradedNow THEN
            _ePhase := E_DL_PowerMeterState.eSampling;  // 恢复正常：回采样（Recovered, back to sampling）
        END_IF

    E_DL_PowerMeterState.eFault: // 故障：停止计量，等复位沿且原因消失
        IF _bExitFault AND (NOT _bCalBad) AND (NOT _bStale) THEN
            _ePhase := E_DL_PowerMeterState.eIdle;      // 复位受理：回待机（Reset accepted, back to idle）
        END_IF

    ELSE
        _uErrFault   := 16#0003_0319;                   // 0319 非法状态兜底（Illegal state fallback）
        _bFaultLatch := TRUE;                           // 兜底锁存（Fallback latched）
        _ePhase      := E_DL_PowerMeterState.eFault;    // 进终端安全态（Enter the terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜电能累计与需量结算（业务运算；只在采样与降级两态推进）
 *      Energy accumulation and demand settlement, only while metering
 *-----------------------------------------------------------------------------*)
IF (_ePhase = E_DL_PowerMeterState.eSampling) OR (_ePhase = E_DL_PowerMeterState.eDegraded) THEN

    (* 32 位电能拼装：四种字序各一分支，避免把字节内序与字间序混为一谈
     * 枚举比较一律对「声明区基准量」做，语句段不出现裸类型名（与库内既有范式一致） *)
    IF eWordOrder = _eOrderAbcd THEN
        _uImportRaw := SHL(UINT_TO_UDINT(uEnergyImportHi), 16) OR UINT_TO_UDINT(uEnergyImportLo); // 高字在前（High word first）
        _uExportRaw := SHL(UINT_TO_UDINT(uEnergyExportHi), 16) OR UINT_TO_UDINT(uEnergyExportLo); // 高字在前（High word first）
    ELSIF eWordOrder = _eOrderCdab THEN
        _uImportRaw := SHL(UINT_TO_UDINT(uEnergyImportLo), 16) OR UINT_TO_UDINT(uEnergyImportHi); // 低字在前（Low word first）
        _uExportRaw := SHL(UINT_TO_UDINT(uEnergyExportLo), 16) OR UINT_TO_UDINT(uEnergyExportHi); // 低字在前（Low word first）
    ELSE
        (* 字节内序（eDcba / eBadc）在本件不改变字间排布，按高字在前处理并在头注释声明边界 *)
        _uImportRaw := SHL(UINT_TO_UDINT(uEnergyImportHi), 16) OR UINT_TO_UDINT(uEnergyImportLo); // 字间仍高字在前（Word order unchanged）
        _uExportRaw := SHL(UINT_TO_UDINT(uEnergyExportHi), 16) OR UINT_TO_UDINT(uEnergyExportLo); // 字间仍高字在前（Word order unchanged）
    END_IF

    _fImportNow := UDINT_TO_LREAL(_uImportRaw) * _fKwhLsbL;  // 正向工程量换算（Import conversion）
    _fExportNow := UDINT_TO_LREAL(_uExportRaw) * _fKwhLsbL;  // 反向工程量换算（Export conversion）

    IF NOT _bEnergyBase THEN
        _fImportAcc  := _fImportNow;                        // 首拍只装基准，不产生增量（Baseline only）
        _fExportAcc  := _fExportNow;                        // 首拍只装基准（Baseline only）
        _bEnergyBase := TRUE;                               // 基准装载完成（Baseline loaded）
    ELSE
        IF _fImportNow < (_fImportAcc - REAL_TO_LREAL(DL_EPS)) THEN
            _fRegressThr := _fImportAcc * (1.0 - DL_REGRESS_RATIO); // 回退阈值按累计值比例（Threshold from the accumulation）
            IF _fImportNow < _fRegressThr THEN
                IF _uSwapCount < 16#FFFF_FFFF THEN
                    _uSwapCount := _uSwapCount + 1;         // 大幅回退：判换表或清零，次数累加（Large regression, counter incremented）
                END_IF
                _bMaintLatch := TRUE;                       // 维护级锁存（Maintenance latch）
                _fImportAcc := _fImportNow;                 // 基准重载，不回填负增量（Baseline reloaded）
            END_IF
        ELSIF _fImportNow > _fImportAcc THEN
            _fImportAcc := _fImportNow;                     // 正常递推（Normal accumulation）
        END_IF
        IF _fExportNow < (_fExportAcc - REAL_TO_LREAL(DL_EPS)) THEN
            _fExportAcc := _fExportNow;                     // 反向换表：基准重载，不重复计次（Export baseline reloaded）
        ELSIF _fExportNow > _fExportAcc THEN
            _fExportAcc := _fExportNow;                     // 正常递推（Normal accumulation）
        END_IF
    END_IF

    (* 需量：窗口内功率算术平均，拍数分母前置守卫（Arithmetic mean with a guarded divisor） *)
    IF _bFiniteP THEN
        _fWinPSum  := _fWinPSum + _fP;                      // 功率采样累加（Power sample accumulated）
        _nWinCount := _nWinCount + 1;                       // 采样拍数累加（Sample count incremented）
    END_IF

    IF _bWinEnd THEN
        IF _nWinCount > 0 THEN
            _fDemandAvg := _fWinPSum / UDINT_TO_REAL(_nWinCount); // 窗内平均需量（Average demand of the window）
        END_IF
        IF _fDemandAvg > _fDemandPeak THEN
            _fDemandPeak := _fDemandAvg;                    // 峰值取大（Peak keeps the larger value）
        END_IF
        _fWinPSum          := 0.0;                          // 窗口累加清零（Window sum cleared）
        _nWinCount         := 0;                            // 窗口拍数清零（Window count cleared）
        _bDemandWatchBreak := TRUE;                         // 定时器断输入一拍后重启（One-scan break restarts the timer）
    END_IF

ELSE
    (* 非计量态：累计与窗口冻结，不做任何积分（Frozen outside the metering states） *)
    _bDemandWatchBreak := TRUE;                             // 停表期间定时器不推进（Timer held during the freeze）
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜等级仲裁与保持语义重写（R27：保持位逐拍重写，不靠进入那拍的脉冲）
 *      Health arbitration and hold semantics rewritten every scan
 *-----------------------------------------------------------------------------*)
IF _ePhase = E_DL_PowerMeterState.eFault THEN
    _bValidInt := FALSE;                                    // 故障态一律不认数据（No valid data in the fault state）
END_IF

IF _bFaultLatch THEN
    _eHealthInt := E_DL_Ne107Status.eFailure;               // 失效（Failure）
ELSIF NOT _bEverValid THEN
    _eHealthInt := E_DL_Ne107Status.eUnknown;               // 未取得有效数据（No valid data yet）
ELSIF NOT bEnable THEN
    _eHealthInt := E_DL_Ne107Status.eUnknown;               // 未使能（Disabled）
ELSIF _bMaintLatch THEN
    _eHealthInt := E_DL_Ne107Status.eMaintenanceReq;        // 维护请求（Maintenance required）
ELSIF _ePhase = E_DL_PowerMeterState.eDegraded THEN
    _eHealthInt := E_DL_Ne107Status.eOutOfSpec;             // 超出规格（Out of specification）
ELSIF _bValidInt THEN
    _eHealthInt := E_DL_Ne107Status.eOk;                    // 正常（OK）
ELSE
    _eHealthInt := E_DL_Ne107Status.eUnknown;               // 其余（数据不可用）归未知（Otherwise unknown）
END_IF

bValid := _bValidInt;                                       // 有效位出口（Validity outlet）
bError := _bFaultLatch;                                     // 故障位只反映失效级锁存，0318 不置位（Failure latch only, R21）

(*------------------------------------------------------------------------------
 * 段 11｜出口钳位（R43：每条输出赋值路径都能追到一次钳位）
 *      Outlet clamping, every assignment reaches exactly one clamp
 *-----------------------------------------------------------------------------*)
afVoltagePhase[1] := LIMIT(0.0, _afVolt[1], 400.0);         // 分相电压钳进 0~400 V（Clamped）
afVoltagePhase[2] := LIMIT(0.0, _afVolt[2], 400.0);         // 分相电压钳进 0~400 V（Clamped）
afVoltagePhase[3] := LIMIT(0.0, _afVolt[3], 400.0);         // 分相电压钳进 0~400 V（Clamped）
fApparentPower   := LIMIT(0.0, _fS, DL_POWER_MAX);          // 视在功率钳进 0~上限（Clamped）
fEnergyNet       := _fImportAcc - _fExportAcc;              // 净电能（Net energy）
fThdVoltageMax   := LIMIT(0.0, _fThdVmax, 100.0);           // 电压谐波钳进 0~100 %（Clamped）
fThdCurrentMax   := LIMIT(0.0, _fThdCmax, 100.0);           // 电流谐波钳进 0~100 %（Clamped）
fDemandAvg       := _fDemandAvg;                            // 平均需量出口（Average demand outlet）
bPhaseLoss       := _bPhaseLossInt;                         // 缺相出口（Phase loss outlet）
bReversePower    := _bReverseInt;                           // 反送出口（Reverse power outlet）
uMeterSwapCount  := _uSwapCount;                            // 换表次数出口（Swap counter outlet）

(*------------------------------------------------------------------------------
 * 段 12｜码位单一优先级链（全拍只写一次 uDiagCode；F 优先，其次维护、越规、提示）
 *      Single priority chain, the diagnostic code is written exactly once
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    _uDiagCode := _uErrFault;                               // 故障级优先，保留首出码（Fault level with the first-out code）
ELSIF _bMaintLatch THEN
    _uDiagCode := 16#0003_0318;                             // 0318 换表或清零（Swap or clear, maintenance level）
ELSIF _bCode015A THEN
    _uDiagCode := 16#0003_015A;                             // 015A 复算与表值不符（PF mismatch）
ELSIF _bCode015B THEN
    _uDiagCode := 16#0003_015B;                             // 015B 频率越限（Frequency out of window）
ELSIF _bCode0159 THEN
    _uDiagCode := 16#0003_0159;                             // 0159 轻载抑制（Suppressed at light load）
ELSIF _bCode0157 THEN
    _uDiagCode := 16#0003_0157;                             // 0157 窗口兜底（Window clamped）
ELSIF _bCode0158 THEN
    _uDiagCode := 16#0003_0158;                             // 0158 字序变更（Word order changed）
ELSIF _bCode0156 THEN
    _uDiagCode := 16#0003_0156;                             // 0156 不平衡提示（Unbalance advisory）
ELSE
    _uDiagCode := 16#0000_0000;                             // 无码（No code）
END_IF

uErrorId := _uErrFault;                                     // 末次故障码出口，信息码不进本引脚（Info codes never reach this pin）

(*------------------------------------------------------------------------------
 * 方法: CmdResetEnergy —— 清零累计电能。故障锁存期一律拒绝。
 *      Method CmdResetEnergy - rejected while a failure latch exists.
 *-----------------------------------------------------------------------------*)
METHOD CmdResetEnergy : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch THEN
    CmdResetEnergy := FALSE;                                // 故障期清零会抹掉追溯依据（Rejected, the audit trail would be lost）
ELSE
    _bPendResetEnergy := TRUE;                              // 登记请求，由段 7 消费（Registered, consumed in section 7）
    CmdResetEnergy    := TRUE;                              // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位锁存。仅存在锁存时受理。
 *      Method CmdReset - accepted only when a latch exists.
 *-----------------------------------------------------------------------------*)
METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR _bMaintLatch THEN
    _bPendReset := TRUE;                                    // 登记请求，由段 7 消费（Registered, consumed in section 7）
    CmdReset    := TRUE;                                    // 受理成功（Accepted）
ELSE
    CmdReset    := FALSE;                                   // 无锁存可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdAck —— 应答维护与越规。失效级不可应答。
 *      Method CmdAck - acknowledges maintenance and out-of-spec only.
 *-----------------------------------------------------------------------------*)
METHOD CmdAck : BOOL
VAR_INPUT
END_VAR
IF _bMaintLatch AND (NOT _bFaultLatch) THEN
    _bPendAck := TRUE;                                      // 登记请求，由段 7 消费（Registered, consumed in section 7）
    CmdAck    := TRUE;                                      // 受理成功（Accepted）
ELSE
    CmdAck    := FALSE;                                     // 失效不可被应答掉（A failure cannot be acknowledged away）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 计量状态只读视图。
 *      Property eState (GET) - read-only metering state.
 *-----------------------------------------------------------------------------*)
PROPERTY eState : E_DL_PowerMeterState
eState := _ePhase;                                          // 返回计量相位（Return the metering phase）

(*------------------------------------------------------------------------------
 * 属性: eHealth（GET）—— NE107 健康态只读视图。
 *      Property eHealth (GET) - read-only NE107 health state.
 *-----------------------------------------------------------------------------*)
PROPERTY eHealth : E_DL_Ne107Status
eHealth := _eHealthInt;                                     // 返回健康态（Return the health state）

(*------------------------------------------------------------------------------
 * 属性: uDiagCode（GET）—— 当前诊断码（单一优先级链产物）。
 *      Property uDiagCode (GET) - active diagnostic code.
 *-----------------------------------------------------------------------------*)
PROPERTY uDiagCode : UDINT
uDiagCode := _uDiagCode;                                    // 返回诊断码（Return the diagnostic code）

(*------------------------------------------------------------------------------
 * 属性: fVoltageAvg（GET）—— 三相平均相电压。
 *      Property fVoltageAvg (GET) - average phase voltage.
 *-----------------------------------------------------------------------------*)
PROPERTY fVoltageAvg : REAL
fVoltageAvg := LIMIT(0.0, _fVoltAvg, 400.0);                // 钳进 0~400 V（Clamped）

(*------------------------------------------------------------------------------
 * 属性: fCurrentAvg（GET）—— 三相平均电流。
 *      Property fCurrentAvg (GET) - average phase current.
 *-----------------------------------------------------------------------------*)
PROPERTY fCurrentAvg : REAL
fCurrentAvg := LIMIT(0.0, _fCurrAvg, 10000.0);              // 钳进 0~10000 A（Clamped）

(*------------------------------------------------------------------------------
 * 属性: fActivePowerTotal（GET）—— 三相总有功，有符号，保留反送。
 *      Property fActivePowerTotal (GET) - signed total active power.
 *-----------------------------------------------------------------------------*)
PROPERTY fActivePowerTotal : REAL
fActivePowerTotal := LIMIT(-DL_POWER_MAX, _fP, DL_POWER_MAX); // 双向钳位，保留符号（Clamped both ways, sign kept）

(*------------------------------------------------------------------------------
 * 属性: fReactivePowerTotal（GET）—— 三相总无功。
 *      Property fReactivePowerTotal (GET) - total reactive power.
 *-----------------------------------------------------------------------------*)
PROPERTY fReactivePowerTotal : REAL
fReactivePowerTotal := LIMIT(0.0, _fQ, DL_POWER_MAX);       // 钳进 0~上限（Clamped）

(*------------------------------------------------------------------------------
 * 属性: fPowerFactorTotal（GET）—— 复算功率因数（不取表值）。
 *      Property fPowerFactorTotal (GET) - recomputed power factor.
 *-----------------------------------------------------------------------------*)
PROPERTY fPowerFactorTotal : REAL
fPowerFactorTotal := LIMIT(-1.0, _fPf, 1.0);                // 钳进 -1~1（Clamped）

(*------------------------------------------------------------------------------
 * 属性: fFrequency（GET）—— 电网频率。
 *      Property fFrequency (GET) - grid frequency.
 *-----------------------------------------------------------------------------*)
PROPERTY fFrequency : REAL
fFrequency := LIMIT(0.0, _fFreq, 100.0);                    // 钳进 0~100 Hz，防寄存器噪声（Clamped）

(*------------------------------------------------------------------------------
 * 属性: fEnergyImport（GET）—— 正向累计电能。
 *      Property fEnergyImport (GET) - accumulated import energy.
 *-----------------------------------------------------------------------------*)
PROPERTY fEnergyImport : LREAL
IF _fImportAcc < 0.0 THEN
    fEnergyImport := 0.0;                                   // 负累计不可能，钳到 0（Negative accumulation clamped）
ELSE
    fEnergyImport := _fImportAcc;                           // 正常出口（Normal outlet）
END_IF

(*------------------------------------------------------------------------------
 * 属性: fEnergyExport（GET）—— 反向累计电能。
 *      Property fEnergyExport (GET) - accumulated export energy.
 *-----------------------------------------------------------------------------*)
PROPERTY fEnergyExport : LREAL
IF _fExportAcc < 0.0 THEN
    fEnergyExport := 0.0;                                   // 负累计不可能，钳到 0（Negative accumulation clamped）
ELSE
    fEnergyExport := _fExportAcc;                           // 正常出口（Normal outlet）
END_IF

(*------------------------------------------------------------------------------
 * 属性: fDemandPeak（GET）—— 历史峰值需量，仅复位可清。
 *      Property fDemandPeak (GET) - peak demand, cleared by reset only.
 *-----------------------------------------------------------------------------*)
PROPERTY fDemandPeak : REAL
fDemandPeak := LIMIT(0.0, _fDemandPeak, DL_POWER_MAX);      // 钳进 0~上限（Clamped）

END_FUNCTION_BLOCK
