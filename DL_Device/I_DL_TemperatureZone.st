(*==============================================================================
 * 组件名称 (Component)  : I_DL_TemperatureZone
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第 3 版）OOP 接口契约，零厂商方言
 * 分类     (Category)   : 接口（INTERFACE）· 温控区执行抽象 · Level 1 DL_Device 开库件
 * 功能描述 (Function)   : 加热/冷却温控区标准抽象契约。上层工艺层（炉区、恒温室、
 *                         模温机、老化房）只依赖本接口编程，与具体温控实现
 *                         （FB_DL_HeatCoolZone 等）彻底解耦（依赖倒置）。
 *                         契约按接口三段式公约（0.11）组织：状态枚举 + 只读属性
 *                         （实测温度 / 输出功率 / 状态 / 故障 / 故障码）+ 方法
 *                         （设定值 / 投退 / 复位）；方法共 3 个（红线 ≤6）。
 *                         实现块必须以 IMPLEMENTS 挂接本接口并逐成员兑现。
 * 开源溯源 (Origin)     : 原创设计。状态集合惯例与断偶安全方向语义参考 NAMUR
 *                         NE43 公开标准与温控器行业公知行为（来源标签
 *                         lbp-device / namur-ne43），未参考、未复制任何厂商源码。
 * 本文件内含       : TYPE      E_DL_TempZoneState（状态枚举，归属 DL_Device，
 *                              随本接口同文件发布）
 *                    INTERFACE I_DL_TemperatureZone
 * 依赖     (Depends)    : 无（纯契约文件，零外部引用，可单独编译）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 契约级不适用（无算法分支）
 *                         R5 ✓ 全成员中英双语同行注释 ｜ R6 ✓ 契约级不适用（由实现块承担）
 *                         R7 不适用（无定时器/边沿实例，纯契约）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 05 · 泳道 B · 契约出处 ROUND_PLAN_R5 §1.7
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TempZoneState（归属 DL_Device，随 I_DL_TemperatureZone 同文件）
 * 含义: 温控区离散状态机。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_DL_TempZoneState :
(
    eIdle        := 0,   // 空闲：未投运，双通道切断 / Idle: not commissioned, both channels cut off
    eHeating     := 10,  // 加热中：加热通道输出功率大于热平衡容差 / Heating: heater duty above thermal-balance tolerance
    eCooling     := 20,  // 冷却中：冷却通道输出功率大于热平衡容差 / Cooling: cooler duty above thermal-balance tolerance
    eHolding     := 30,  // 保温中：双通道均处于热平衡容差带内 / Holding: both channels inside thermal-balance tolerance band
    eSensorBreak := 40,  // 断偶锁存：传感器断线/开路，双通道切断待复位 / Sensor break latched: sensor break, channels cut pending reset
    eFault       := 99   // 故障兜底：非法状态或接口引用无效，切断待复位 / Fault fallback: illegal state or invalid interface reference, cut pending reset
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_TemperatureZone
 * 契约说明:
 *   - 属性全部为只读 GET 语义，实现块不得提供 SET 通道（状态只读外泄）。
 *   - 方法均为非阻塞单发语义：方法内只置请求标志，动作由实现块主体状态机
 *     在扫描周期内执行（跨周期动作禁止驻留在方法内部）。
 *   - SetSetpoint 返回值 = 设定值合法性（非有限值一律拒绝并返回 FALSE）。
 *   - CmdReset 返回值 = 当前是否可复位（断偶态要求信号质量恢复后方可成功）。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_TemperatureZone

// ---- 只读属性段（PROPERTY GET）----------------------------------------------
PROPERTY fTempActual : REAL                 // 实测温度（Actual temperature）[°C]，取自注入的传感器接口
PROPERTY fPowerOut   : REAL                 // 输出功率（Power output）[-100..100 %]，正=加热 / 负=冷却
PROPERTY eState      : E_DL_TempZoneState   // 当前状态机状态（Current zone state）
PROPERTY bFault      : BOOL                 // 故障锁存中（Fault latched），仅故障级状态置位，信息级不置位
PROPERTY uErrorId    : UDINT                // 末次故障/信息码（Last error/info code），0 = 无

// ---- 方法段（METHOD，共 3 个，红线 ≤6）--------------------------------------
METHOD SetSetpoint : BOOL
VAR_INPUT
    fTemp : REAL;                           // 目标温度（Target temperature）[°C]，越界由实现块钳位，非有限值拒绝
END_VAR

METHOD CmdEnable
VAR_INPUT
    bOn : BOOL;                             // TRUE=投运（Commission on），FALSE=退出并切断双通道
END_VAR

METHOD CmdReset : BOOL                      // 复位故障（Reset fault），返回当前是否可复位
VAR_INPUT
END_VAR

END_INTERFACE
