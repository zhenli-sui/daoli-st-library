(*==============================================================================
 * 组件名称 (Component)  : I_DL_LevelSwitch
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 料位开关标准抽象契约（振动叉/阻旋/电容等点式料位
 *                         开关通用）。高点溢流与低点干转联锁的统一契约；定
 *                         义有料判定/高/低联锁输出属性组（GET）与复位/测试
 *                         方法组；检测本体在传感器内部，接口层不做检测算法。
 * 契约结构 (Structure)  : 公约 0.11 接口三段式——状态枚举 + 失效安全模式枚
 *                         举（均本文件承载）+ 属性（PROPERTY GET）+ 方法
 *                         （METHOD）；方法共 2 个（≤6 红线内）。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / level-switch-failsafe
 *                         （RAW_NOTES_R7 S-2/S-7：TcOpen 组件接口分层思想与
 *                         料位开关失效安全公开语义域——fail-safe HIGH/LOW
 *                         方向约定、双联锁输出，公开资料，仅借鉴语义域；接
 *                         口命名、枚举编号、方法签名 100% 本库独立设计，
 *                         clean-room 未复制源码）。
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_LevelState 与 E_DL_FailSafeMode
 *                         两个枚举定义，均归属接口 I_DL_LevelSwitch，与其同
 *                         文件发布（公约 0.11；禁止异文件同名异型重复定义）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 N/A（契约件无运算）
 *                         R5 全成员中英双语同行注释 ✓｜R6 N/A（接口无状态机）
 *                         R7 N/A（无实例调用）｜R18 INTERFACE/END_INTERFACE
 *                         成对终结 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 料位开关族接口件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LevelState（归属接口 I_DL_LevelSwitch，与其同文件）
 * 含义: 料位开关诊断状态。编号步长 10 留空位，eFault 取 99 保证排序末位
 *       （全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_LevelState :
(
    eNoMaterial := 0,   // 无料：裸露确认态 / No material, bare confirmed
    eMaterial   := 10,  // 有料：覆盖确认态 / Material present, covered confirmed
    eSensorLoss := 20,  // 传感器失效态：按失效安全方向归一后的诊断镜像（本轮预留，检测算法后续轮次落地）/ Sensor loss, fail-safe normalized mirror (reserved this round)
    eFault      := 99   // 故障锁存：模式枚举越界等 / Latched fault
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FailSafeMode（归属接口 I_DL_LevelSwitch，与其同文件）
 * 含义: 失效安全方向模式。决定传感器失效/使能切断时输出强制镜像的安全侧：
 *       eHigh=失效报有料（防溢流）；eLow=失效报无料（防干转）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_FailSafeMode :
(
    eHigh := 0,   // 失效安全 HIGH：失效报有料，防溢流方向 / Fail-safe HIGH: failure reads covered, overflow protection
    eLow  := 1    // 失效安全 LOW：失效报无料，防干转方向 / Fail-safe LOW: failure reads bare, dry-run protection
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_LevelSwitch
 * 边界防错: 故障态一律拒绝方法并返回 FALSE；接口层不做检测算法（检测本体
 *           在传感器内部）。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_LevelSwitch

// ---- 属性段（全部只读 GET，实现块一一落地）----------------------------------

PROPERTY eState    : E_DL_LevelState // 当前诊断状态（Current diagnostic state），枚举见 E_DL_LevelState
PROPERTY bMaterial : BOOL            // 有料判定输出（Material present），已按失效安全方向归一，TRUE=有料 / Fail-safe normalized material, TRUE = covered
PROPERTY bHighAlarm: BOOL            // 高点溢流联锁输出（High-level interlock），fail-safe HIGH 语义：归一有料即报警 / High alarm, fail-safe HIGH semantics
PROPERTY bLowAlarm : BOOL            // 低点干转联锁输出（Low-level interlock），fail-safe LOW 语义：归一无料即报警 / Low alarm, fail-safe LOW semantics
PROPERTY bFault    : BOOL            // 故障锁存中（Fault latched），显式排除信息级码（R21）/ TRUE = latched fault, info codes excluded
PROPERTY uErrorId  : UDINT           // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理/合法性结果）----------------------------------

METHOD CmdReset : BOOL // 复位故障（Reset fault），仅故障态受理 / Reset accepted only in fault state
VAR_INPUT
END_VAR

METHOD CmdTest : BOOL // 传感器功能测试请求（Sensor function test request），输出镜像进入测试态一拍 / Test request, test mirror asserted one scan
VAR_INPUT
END_VAR

END_INTERFACE
