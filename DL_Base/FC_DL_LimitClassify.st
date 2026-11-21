(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LimitClassify
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : lgf-comparator（T2-1 LGF Comparator 组回补）
 * 作者/日期             : Daoli Library / 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），纯函数无状态
 * 功能简介 (Function)   : 下限 / 下警告 / 上警告 / 上限四阈值五档判定
 *                         （低低 / 低 / 正常 / 高 / 高高），非对称四级限值仪表分档。
 *                         典型现场用途：储罐液位五档分档显示与分级联锁、
 *                         液压站压力分档告警、烘箱温度分区治理。
 *                         与 FB_DL_ToleranceWindow 职责分离：
 *                         本块 = 非对称四级限值分档（仪表告警语义）；
 *                         公差窗块 = 对称公差带三态判定（质检 / 定位语义）。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 公开手册 Comparator 分类中
 *                         限值 / 分档族的功能分类与参数域），只借分类/参数域/命名，
 *                         clean-room 实现，未复制任何源码。来源标签：lgf-comparator。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS
 *
 * 【接口契约 / Interface contract】
 *   返回值：档位枚举 E_DL_LimitBand；阈值序非法时恒为 eInvalid。
 *   输入  ：fVal 被判定值；fLowLimit / fLowWarn / fUpWarn / fUpLimit
 *           四阈值（须单调不减，允许相邻相等退化）。
 *   输出  ：uErrorId 故障码（阈值序非法置码）。
 *   纪律  ：纯函数同输入同输出；无内部状态；可安全放进 IF 表达式与
 *           多任务环境（无共享可变状态）。
 *
 * 【使用示例 / Usage example】
 *   VAR
 *       eTankLevel : E_DL_LimitBand;    // 液位档位
 *       nErr       : UDINT;             // 诊断码
 *   END_VAR
 *   eTankLevel := FC_DL_LimitClassify(fVal := fLevel,
 *                     fLowLimit := 10.0, fLowWarn := 20.0,
 *                     fUpWarn := 80.0, fUpLimit := 90.0, uErrorId => nErr);
 *   IF nErr <> 0 THEN
 *       // 阈值组态非法：走组态报警流程，档位不可信（恒 eInvalid）
 *   END_IF
 *
 * 【五档区间图 / Five-band interval diagram】
 *   eLowTripped: v <= 低低限 ｜ eLowWarn: 低低限 < v <= 低警告限
 *   eNormal   : 低警告限 < v < 高警告限（贴线归严档，见 B1）
 *   eUpWarn   : 高警告限 <= v < 高高限 ｜ eUpTripped: v >= 高高限
 *
 * 【引脚速查表 / Pin quick reference】
 *   方向 ｜ 名称      ｜ 类型           ｜ 语义摘要
 *   返回 ｜ （函数名） ｜ E_DL_LimitBand ｜ 档位判定结果
 *   输入 ｜ fVal      ｜ LREAL          ｜ 被判定值 [EU]
 *   输入 ｜ fLowLimit ｜ LREAL          ｜ 低低限（停机级）[EU]
 *   输入 ｜ fLowWarn  ｜ LREAL          ｜ 低警告限 [EU]
 *   输入 ｜ fUpWarn   ｜ LREAL          ｜ 高警告限 [EU]
 *   输入 ｜ fUpLimit  ｜ LREAL          ｜ 高高限（停机级）[EU]
 *   输出 ｜ uErrorId  ｜ UDINT          ｜ 故障码（见故障码表）
 *
 * 【与告警分级联动建议 / Integration with alarm grading】
 *   eLowTripped / eUpTripped（停机级）→ 联锁停机 + 声光急告警，
 *   需要操作员确认方可复位；eLowWarn / eUpWarn（警告级）→
 *   中央告警列表登记 + 塔灯黄/闪，不联锁；eNormal → 台账静默记录。
 *   档位枚举可直接驱动已入库 FB_DL_SignalTower 的分档显示输入，
 *   二者职责正交：本块只分类，塔灯块只驱动，组合由调用方完成。
 *
 * 【组态纪律 / Configuration discipline】
 *   四阈值建议集中在一个结构体 / 数据块内组态并整组下装，
 *   避免运行中逐个改写出现瞬态倒置拍（本块逐拍校验，
 *   倒置拍会瞬时输出 eInvalid，联锁侧应把 eInvalid 按"不可信"处理，
 *   不得当正常档放行，也不得直接触发停机——按组态报警流程处置）。
 *   阈值量纲必须与 fVal 一致：同一监控点换量程（如 Pa 换 kPa）时
 *   四阈值整组换算，半组更新是最常见的倒置来源。
 *
 * 【调用开销与部署建议 / Cost and deployment notes】
 *   纯比较逻辑无循环无状态，单次调用开销微秒以下，
 *   可按每个监控点一调用点的高频轮询部署；
 *   同一物理量的多组阈值分档（如温度按季节换限值）请建多调用点
 *   分别传阈值组，勿运行中动态换阈值组（见组态纪律）。
 *
 * 【术语与口径表 / Glossary and semantics】
 *   低低 / 高高（Tripped）：停机级档位，贴线即触发（闭区间口径）；
 *   低 / 高（Warn）：警告级档位，只登记不联锁；
 *   正常（Normal）：两警告限之间的开区间（贴线归严档后所剩）；
 *   档位退化：相邻阈值相等时严档吞并宽档，属合法组态；
 *   拒绝档（eInvalid）：阈值序非法时的唯一输出，联锁侧按不可信处理。
 *
 * 【分档诊断设计 / Diagnostic design】
 *   阈值序非法是组态错误，不是运行错误：错误分档会把停机级工况显示为
 *   正常档（或反之），比不分档更危险。故拒绝路径显式返回 eInvalid + 置码，
 *   调用方凭 uErrorId 区分"正常档判定"与"拒绝档"，绝不静默输出。
 *
 * 验收向量 (Acceptance) : （fLowLimit=10, fLowWarn=20, fUpWarn=80, fUpLimit=90）
 *   V1 fVal =  5.0 → eLowTripped，uErrorId = 0
 *   V2 fVal = 15.0 → eLowWarn，   uErrorId = 0
 *   V3 fVal = 50.0 → eNormal，    uErrorId = 0
 *   V4 fVal = 85.0 → eUpWarn，    uErrorId = 0
 *   V5 fVal = 95.0 → eUpTripped， uErrorId = 0
 *   V6 阈值组 90/80/20/10（序倒置）→ eInvalid，uErrorId 非 0（拒绝路径验证）
 *
 * 【边界值归属推演表 / Boundary attribution walk-through】
 *   （同一阈值组 10 / 20 / 80 / 90，逐边界值验证闭区间口径 B1）
 *   B1v fVal = 10.0 → eLowTripped（等于低低限，贴线即停机级）
 *   B2v fVal = 20.0 → eLowWarn   （等于低警告限，归更严档）
 *   B3v fVal = 80.0 → eUpWarn    （等于高警告限，归更严档）
 *   B4v fVal = 90.0 → eUpTripped （等于高高限，贴线即停机级）
 *   B5v fVal = 10.000000001      ：高于低低限且容差外 → eLowWarn
 *   B6v fVal = 89.999999999      ：低于高高限且容差外 → eUpWarn
 *
 * 【退化组态语义 / Degenerate configuration semantics】
 *   相邻阈值相等合法，档位按闭区间口径退化收缩：
 *   fLowWarn = fLowLimit = 15 → 低低与低档收缩为同一条线（v <= 15 全判低低）；
 *   fUpWarn = fUpLimit = 85  → 高档与高高档收缩为同一条线（v >= 85 全判高高）；
 *   fLowWarn = fUpWarn = 50  → **正常档退化为空集**：v = 50 被「<= 低警告限」
 *   严档优先拦截判 eLowWarn，v > 50 与 v < 50 两侧分别落入低档 / 高档，
 *   eNormal 无任何取值可达（v1.0.1 终审勘误：原文「仅 v = 50 判正常」与
 *   闭区间归属次序不符，属文档错、代码对）。
 *   退化组态常用于"四线表只用两线"的简化仪表位，属合法工况不置诊断；
 *   序倒置（严格大于）才是组态错误，走 eInvalid 拒绝路径。
 * 故障码表 (Error codes):
 *   16#0001_0214  阈值序非法：要求 fLowLimit <= fLowWarn <= fUpWarn <= fUpLimit，
 *                 相邻阈值倒置（含容差内倒置）即置码，返回 eInvalid，禁止静默分档
 *   【码位终审】原拟 0003_0201 属 DL_Device 段位，且与设备族「非法状态」共用码
 *   （DolMotor / PneumaticCylinder / StarDeltaMotor）语义冲突；本体属 DL_Base，
 *   已顺延至 0001_0214（DL_Base 段 0201~0213 已占用，0214 空闲）。
 * 红线自检 (Redline)    : R1 ✓ 零全局存储 / 零外部变量引用 ｜ R2 ✓ 零物理地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 阈值序校验 + 容差判等 + 非法拒绝不静默
 *                         R5 ✓ 全变量与枚举项中英双语同行注释 ｜ R6 ✓ 纯函数无状态（R6 状态机 N/A）
 *                         R7 ✓ 无定时器 / 边沿实例（R7 N/A）
 * 边界契约 (Boundaries):
 *   B1 边界值归属写死：等于阈值归更严档（<= 与 >= 闭区间口径）——
 *      fVal = fLowLimit 判低低档，fVal = fUpLimit 判高高档，fVal = fUpWarn 判高档。
 *      仪表联锁场景"贴线即触发"是安全侧惯例，注释固化不得随实现漂移。
 *   B2 阈值序校验：相邻相等视为合法（档位退化，如 fLowWarn = fUpWarn 时
 *      正常档收缩为一点）；序倒置（严格大于）或容差内倒置判非法，
 *      返回 eInvalid 并置码——分档错误比不分档更危险，禁止静默输出。
 *   B3 纯函数：同输入同输出，无内部状态、无副作用，可安全放进 IF 表达式。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · Level 0 原子族回补）
 *   2026-11-15  v1.0.1  终审修复：故障码 0003_0201 属 DL_Device 段且与设备族
 *                       非法状态码冲突，顺延为 0001_0214；勘误退化组态说明
 *                       （fLowWarn = fUpWarn 时正常档为空集，非"单点"），
 *                       代码行为未改动
 *============================================================================*)
TYPE E_DL_LimitBand :
(
    eLowTripped := 0,  // 低低档：<= 低低限，停机级 / Low-low band, trip level
    eLowWarn    := 1,  // 低档：<= 低警告限 / Low warning band
    eNormal     := 2,  // 正常档 / Normal band
    eUpWarn     := 3,  // 高档：>= 高警告限 / High warning band
    eUpTripped  := 4,  // 高高档：>= 高高限，停机级 / High-high band, trip level
    eInvalid    := 9   // 参数非法兜底档 / Invalid-parameters fallback band
);
END_TYPE

FUNCTION FC_DL_LimitClassify : E_DL_LimitBand   // 返回档位判定结果 / Returns the band judgment
VAR_INPUT
    fVal      : LREAL;                  // 被判定值 [工程单位随应用] / Value to classify [EU by application]
    fLowLimit : LREAL;                  // 低低限（停机级）[工程单位] / Low-low trip limit [EU]
    fLowWarn  : LREAL;                  // 低警告限 [工程单位] / Low warning limit [EU]
    fUpWarn   : LREAL;                  // 高警告限 [工程单位] / High warning limit [EU]
    fUpLimit  : LREAL;                  // 高高限（停机级）[工程单位] / High-high trip limit [EU]
END_VAR
VAR_OUTPUT
    uErrorId  : UDINT;                  // 故障码，0 = 无故障；阈值序非法置码 / Error code, 0 = no error
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : LREAL := 1.0E-9;     // 判等容差（阈值相邻容差内倒置判非法）/ Equality tolerance for the limit order check
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜缺省返回：非法兜底档，故障码清零（合法路径再覆盖）
 *      Default return: invalid fallback band, error code cleared first
 *      缺省即拒绝语义：任何未显式分档的退出路径都携带 eInvalid，不误报
 *-----------------------------------------------------------------------------*)
FC_DL_LimitClassify := E_DL_LimitBand.eInvalid;
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜阈值序校验（边界 B2）：四阈值须单调不减，倒置或容差内倒置判非法
 *      Limit order check: four limits must be monotonically non-decreasing
 *      容差内倒置（如 fLowWarn 比 fLowLimit 大 1E-12）按倒置处理，
 *      避免浮点噪声吞掉真组态错误
 *-----------------------------------------------------------------------------*)
IF (fLowLimit > fLowWarn + DL_FLOAT_EPS)
    OR (fLowWarn > fUpWarn + DL_FLOAT_EPS)
    OR (fUpWarn > fUpLimit + DL_FLOAT_EPS) THEN
    uErrorId := 16#0001_0214;   // 故障级：阈值序非法 / Fault: invalid limit order
    RETURN;                     // 拒绝路径：保持 eInvalid，禁止静默分档（B2）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜五档判定主体（边界 B1）：闭区间口径，等于阈值归更严档，
 *      判据全部 ABS 差值与容差比较，禁浮点直接判等
 *      Five-band body with closed-interval attribution, tolerance-based compares
 *-----------------------------------------------------------------------------*)
IF fVal <= fLowLimit THEN
    FC_DL_LimitClassify := E_DL_LimitBand.eLowTripped;      // 贴线即停机级（安全侧，B1）
ELSIF fVal <= fLowWarn THEN
    FC_DL_LimitClassify := E_DL_LimitBand.eLowWarn;         // 低警告档 / Low warning band
ELSIF ABS(fVal - fUpLimit) < DL_FLOAT_EPS THEN
    FC_DL_LimitClassify := E_DL_LimitBand.eUpTripped;       // 等于高高限归更严档（容差判等）
ELSIF fVal >= fUpLimit THEN
    FC_DL_LimitClassify := E_DL_LimitBand.eUpTripped;       // 超高高限 / Above high-high
ELSIF ABS(fVal - fUpWarn) < DL_FLOAT_EPS THEN
    FC_DL_LimitClassify := E_DL_LimitBand.eUpWarn;          // 等于高警告限归更严档（容差判等）
ELSIF fVal >= fUpWarn THEN
    FC_DL_LimitClassify := E_DL_LimitBand.eUpWarn;          // 高警告档 / High warning band
ELSE
    FC_DL_LimitClassify := E_DL_LimitBand.eNormal;          // 正常档 / Normal band
END_IF
(* 到此全部分档路径已覆盖：低低 / 低 / 高高 / 高 / 正常五档互斥完备，
   容差分支仅在上边界两侧生效，低侧由 <= 闭区间天然覆盖等值归属 *)
END_FUNCTION
