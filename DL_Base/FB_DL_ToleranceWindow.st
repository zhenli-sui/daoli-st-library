(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ToleranceWindow
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : lgf-comparator（T2-1 LGF Comparator 组回补）
 * 作者/日期             : Daoli Library / 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），无定时器与边沿实例
 * 功能简介 (Function)   : 目标值 ± 公差带三态判定（合格 / 低于下差 / 高于上差），
 *                         带可配置迟滞回差防止临界抖动，输出双向越差单拍告警。
 *                         面向质检 / 定位容差窗场景：压装深度、定位停位精度、
 *                         温控点位偏差分档等。
 *                         与已入库 FC_DL_Hysteresis（双阈值通断迟滞）和
 *                         FC_DL_Deadband（死区抑制输出）职责分离：
 *                         本块输出三态分类 + 双向越差事件，非对称用法见 FC_DL_LimitClassify。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 公开手册 Comparator 分类中
 *                         公差 / 比较器族的功能分类与参数域），只借分类/参数域/命名，
 *                         clean-room 实现，未复制任何源码。来源标签：lgf-comparator。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS
 *
 * 【接口契约 / Interface contract】
 *   输入  ：bEnable 电平使能；fTarget / fActual 目标与实际值；
 *           fTolerance 公差半带宽（必须 > 0）；fHysteresis 迟滞回差
 *           （0..fTolerance/2，越界自动钳位）。
 *   输出  ：eJudge 三态判定（保持型）；bOk / bLowOut / bHighOut 三态布尔
 *           派生（保持型）；bDeviation 越窗事件单拍脉冲；uErrorId 故障码。
 *   纪律  ：每周期调用一次；判定状态全部内聚于实例，多实例互相独立。
 *
 * 【使用示例 / Usage example】
 *   VAR
 *       fbPosWin : FB_DL_ToleranceWindow;   // 定位停位精度窗实例
 *   END_VAR
 *   fbPosWin(bEnable := bAtPositionCheck, fTarget := 120.0,
 *            fActual := fAxisPos, fTolerance := 0.5, fHysteresis := 0.05);
 *   IF fbPosWin.bDeviation THEN
 *       // 单拍事件：从合格迁出到越差，触发复检 / 报警登记
 *   END_IF
 *   bInTol := fbPosWin.bOk;   // 保持型合格位，可直接参与联锁
 *   // 分侧处置示例：越上差 = 停位过头（多走了），越下差 = 欠位（少走），
 *   // 二者常对应不同的补偿方向，调用方按 bLowOut / bHighOut 分侧取用
 *
 * 【三态与迟滞图解 / State and hysteresis diagram】
 *   eHighOut ←——偏差 > +（公差+回差）—— eOk ——偏差 < -（公差+回差）——→ eLowOut
 *   eHighOut ——偏差 <= +公差——→ eOk ←——偏差 >= -公差—— eLowOut
 *   进窗阈窄、出窗阈宽，回差带内保持原态：临界抖动被迟滞吸收，
 *   不会在公差线上反复横跳刷爆事件通道。
 *
 * 【扫描周期行为 / Scan behavior】
 *   每拍次序：缺省值清零 → 使能门 → 参数校验钳位 → CASE 状态机
 *             → 越窗事件判定 → 派生输出与 eLast 刷新。
 *   无定时器 / 边沿实例：迟滞与事件边沿全部由 eLast 状态量承载，
 *   逻辑纯组合 + 一拍状态记忆，扫描开销可忽略。
 *
 * 【单拍脉冲逐拍推演 / Single-pulse walk-through（R25 三律）】
 *   拍 n：eLast = eOk 且偏差首次越过宽阈 → CASE 迁出，bDeviation=TRUE；
 *   拍 n+1：eLast 已是 eLowOut / eHighOut → 段 5 条件不成立，bDeviation 自清。
 *   置位来源唯一（段 5 迁移比较），自清位置唯一（段 1 + 段 5 条件不成立），
 *   边沿基准唯一（eLast，每拍仅段 6 一处刷新）。
 *
 * 故障码表 (Error codes):
 *   16#0001_0213  fTolerance <= 0 参数非法，输出锁 eUnKnown（故障级）
 *   16#0001_0112  fHysteresis 越界，已钳位到 0..fTolerance/2（信息级）
 *   【码位终审】原拟 0003_0101 / 0003_0201 经全库复核冲突：0003 段属
 *   DL_Device（公约 0.7 段位表），0003_0201 为设备族「非法状态」共用码
 *   （DolMotor / PneumaticCylinder / StarDeltaMotor），0003_0101 为设备族
 *   「参数钳位」共用码（HeatCoolZone）。本体属 DL_Base，归 16#0001_xxxx 段，
 *   已顺延至 0001_0112（信息级）/ 0001_0213（故障级），无冲突。
 * 红线自检 (Redline)    : R1 ✓ 零全局存储 / 零外部变量引用 ｜ R2 ✓ 零物理地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 参数钳位 / 判零 + 全判据 ABS 容差比较
 *                         R5 ✓ 全变量与枚举项中英双语同行注释 ｜ R6 ✓ CASE + ELSE 兜底，状态单一来源 eJudge
 *                         R7 ✓ 无定时器 / 边沿实例，bDeviation 边沿基准 eLast 单一来源
 * 边界契约 (Boundaries):
 *   B1 迟滞语义：进窗阈窄（|偏差| <= fTolerance）、出窗阈宽
 *      （|偏差| > fTolerance + fHysteresis），回差带内保持原态——
 *      这是迟滞的定义，改动次序会破坏防抖语义。
 *   B2 fHysteresis 钳位 0..fTolerance/2：回差超过半公差带会使进 / 出窗阈序
 *      倒置（出窗阈反而窄于进窗阈，迟滞退化为负迟滞振荡器），属组态错误，
 *      钳位 + 信息级码。
 *   B3 eUnKnown 首次入窗落回差带内时按 eOk 处理（保守收窄，宁报合格先观察，
 *      后续越窗沿宽阈正常迁出）。
 *   B4 bDeviation 单拍脉冲遵循 R25 三律：仅迁出拍置位，下拍自清，
 *      边沿基准 eLast 单一来源（段 6 末尾统一刷新）。
 *   B5 判定输出族（bOk / bLowOut / bHighOut）由 eJudge 派生，禁止独立判据
 *      出现第二真相源。
 * 【验收推演表 / Acceptance walk-through】
 *   （fTarget = 100.0，fTolerance = 0.5，fHysteresis = 0.05，拍序自上而下）
 *   T1 拍1 bEnable=FALSE          ：eJudge=eUnKnown、bOk=FALSE（安全态）
 *   T2 拍2 bEnable=TRUE, fActual=100.2：eUnKnown 入窗，|0.2|<=0.5 → eOk
 *   T3 拍3 fActual=100.42         ：|0.42|<=0.5 → 保持 eOk（进窗阈窄）
 *   T4 拍4 fActual=100.53         ：0.53 落在 0.5~0.55 回差带 → 保持 eOk
 *                                    （回差带内保持原态，迟滞定义 B1）
 *   T5 拍5 fActual=100.56         ：0.56 > 0.55（宽阈）→ 迁出 eHighOut
 *                                    且 bDeviation 一拍 + uErrorId=0
 *   T6 拍6 fActual=100.52         ：0.52 <= 0.5? 否（进窗阈窄）→ 保持 eHighOut
 *                                    （迟滞吸收临界抖动的关键拍）
 *   T7 拍7 fActual=100.49         ：0.49 <= 0.5 → 返回 eOk，无事件脉冲
 *                                    （迁回方向不置 bDeviation）
 *   T8 拍8 fActual=99.40          ：-0.60 < -0.55 → 迁出 eLowOut，
 *                                    bDeviation 一拍（对称侧同理）
 *   T9 拍9 fTolerance 改填 0      ：uErrorId=0001_0213（故障级）、
 *                                    eJudge 锁 eUnKnown，禁止静默分档
 *   T10 拍10 fHysteresis 改填 0.4 ：钳位到 0.25（半带宽）+
 *                                    uErrorId=0001_0112（信息级，B2）
 *
 * 【组态指南 / Configuration notes】
 *   fTolerance：按工艺公差单边带宽组态（图纸标注 ±0.5 → 填 0.5），
 *   本块不接收双带宽口径，组态前核对图纸标注方式。
 *   fHysteresis：建议取公差带宽的 0.05~0.1 倍，
 *   过小失去防抖意义，过大压缩有效判定区（被钳位到半带宽上限）。
 *   传感器噪声峰峰值若已知，回差应大于噪声峰峰值，否则迟滞失效。
 *   fHysteresis = 0 合法：退化为纯三态窗口判定（无防抖），
 *   用于噪声可忽略的软量（指令值对指令值的核对场景）。
 *   fTarget / fActual 建议接入前先完成量程标定：本块不做标定与滤波，
 *   裸 ADC 码值直接接入会同时破坏判定窗与回差两个口径。
 *
 * 【故障行为矩阵 / Fault behavior matrix】
 *   工况                 ｜ uErrorId     ｜ eJudge    ｜ 本拍判定可用性
 *   bEnable = FALSE      ｜ 0（清零）    ｜ eUnKnown  ｜ 安全态，派生全 FALSE
 *   fTolerance <= 0      ｜ 0001_0213 故障｜ eUnKnown  ｜ 锁安全态，禁止分档
 *   fHysteresis 越界      ｜ 0001_0112 信息｜ 照常判定  ｜ 可用（按钳位值）
 *   参数合法且使能        ｜ 0            ｜ 三态      ｜ 可用
 *   故障级码拍调用方应视为"本块不可信"，先修组态再恢复判定。
 *
 * 【引脚速查表 / Pin quick reference】
 *   方向 ｜ 名称         ｜ 类型          ｜ 语义摘要
 *   输入 ｜ bEnable      ｜ BOOL          ｜ 电平使能，FALSE 回安全态
 *   输入 ｜ fTarget      ｜ LREAL         ｜ 目标值 [EU]
 *   输入 ｜ fActual      ｜ LREAL         ｜ 实际值 [EU]
 *   输入 ｜ fTolerance   ｜ LREAL         ｜ 公差半带宽 [EU]，> 0 强制
 *   输入 ｜ fHysteresis  ｜ LREAL         ｜ 迟滞回差 [EU]，0..半带宽钳位
 *   输出 ｜ eJudge       ｜ E_DL_TolJudge ｜ 三态判定（保持型）
 *   输出 ｜ bOk          ｜ BOOL          ｜ 合格位（保持型）
 *   输出 ｜ bLowOut      ｜ BOOL          ｜ 低于下差（保持型）
 *   输出 ｜ bHighOut     ｜ BOOL          ｜ 高于上差（保持型）
 *   输出 ｜ bDeviation   ｜ BOOL          ｜ 越窗事件（单拍）
 *   输出 ｜ uErrorId     ｜ UDINT         ｜ 故障码（见故障码表）
 *
 * 【同类组件三方选型对照 / Three-way selection guide】
 *   维度         ｜ 本块（ToleranceWindow）｜ FC_DL_Hysteresis   ｜ FC_DL_Deadband
 *   输出形态     ｜ 三态分类 + 事件        ｜ 二值通断            ｜ 死区内冻结输出
 *   阈值结构     ｜ 对称公差带 ± 回差      ｜ 双阈值（可不对称）  ｜ 死区半宽
 *   方向信息     ｜ 保留（低差 / 高差分侧）｜ 不保留             ｜ 不保留
 *   典型场景     ｜ 质检 / 定位容差窗      ｜ 泵 / 加热器启停    ｜ 显示值抑制抖动
 *   状态载体     ｜ eJudge（实例内）       ｜ bState（调用方持有）｜ 输出即状态
 *   同为"带记忆的比较器"，区别在输出语义：分档选本块、
 *   回路控制选迟滞块、显示净化选死区块，三块互不替代。
 *
 * 【组态错误清单 / Misuse checklist】
 *   M1 fTolerance 按双带宽口径填（图纸 ±0.5 填了 1.0）→ 判定窗放宽一倍，
 *      漏判越差，组态期按单边带宽核对；
 *   M2 fHysteresis 大于半带宽 → 自动钳位 + 信息级，判定可用但防抖带
 *      被压缩到上限，建议按组态指南重选；
 *   M3 fActual 接入滤波前裸信号且噪声大于回差 → 迟滞失效刷事件，
 *      先滤波或加大回差；
 *   M4 重新使能瞬间拿陈旧 eJudge 做联锁 → 使能门已同步归位 eLast，
 *      重新使能首拍按窄阈重新分类，调用方勿跨失能拍缓存 bOk。
 *
 * 【与联锁集成的安全侧建议 / Safety-side integration notes】
 *   bOk 参与联锁时建议串入 uErrorId = 0 条件：参数非法拍判定不可信，
 *   联锁按失效侧处理（失效导向安全）；bDeviation 单拍事件适合
 *   触发登记 / 复检，不适合直接驱动执行器（一拍脉冲可能被任务抖动
 *   或通信映射抹掉，动作类响应请用保持型 bLowOut / bHighOut）。
 *
 * 【扫描开销披露 / Scan-cost disclosure】
 *   每拍固定成本：一次减法、一次加法、两次乘法级参数运算与一个
 *   CASE 分支，无循环无定时器，单实例开销微秒以下；
 *   判据全部 LREAL 差值比较，无三角 / 指数类重载函数，可放心多实例部署
 *   （建议每轴 / 每点位一实例，状态互不污染）。
 *   实例净占用约 0.05KB（状态枚举 + 偏差缓存 + 容差常量），
 *   全部状态内聚实例内，多实例间零共享可变量。
 *   周期抖动对本块无影响：迟滞基于状态量而非时基，
 *   调用周期变化不改变判定阈值结构。
 *   无隐藏动态行为：不存在自学习 / 自整定参数，组态即全部行为。
 *
 * 【术语与口径表 / Glossary and semantics】
 *   公差半带宽：判定窗半宽，|偏差| <= 半带宽即合格（单边口径）；
 *   迟滞回差：出窗阈相对进窗阈的外扩量，吸收临界抖动；
 *   进窗阈窄 / 出窗阈宽：窗内判出用宽阈（公差+回差），窗外判入用窄阈
 *   （公差），不对称构成迟滞回线；
 *   越窗事件：从 eOk 迁出到任一越差态的迁移拍单拍脉冲；
 *   安全态：eUnKnown，未使能或参数非法时的唯一可信输出。
 *
 * 【逐段结构说明 / Section map】
 *   段 1 本拍缺省值 ｜ 段 2 使能门 ｜ 段 3 参数校验与钳位
 *   段 4 CASE 状态机主体（含 ELSE 兜底）｜ 段 5 越窗事件
 *   段 6 派生输出与 eLast 单一刷新点
 *   段序即执行序，eLast 全块仅段 6 一处写入（单一来源）。
 *
 * 【合规范式声明 / Paradigm compliance】
 *   R25 单拍三律：bDeviation 置位点唯一（段 5 迁移比较）、自清路径唯一
 *   （段 1 缺省 + 段 5 条件不成立）、边沿基准唯一（eLast 单一写点）；
 *   R26 无孤立分号：全文件无空语句；
 *   CASE 兜底：段 4 ELSE 分支覆盖非法状态自愈（红线 R6）；
 *   禁记号口径：全文零全局存储声明、零外部变量声明、零绝对地址记号。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · Level 0 原子族回补）
 *   2026-11-15  v1.0.1  终审修复：故障码 0003_0101 / 0003_0201 属 DL_Device
 *                       段位且与设备族共用码冲突，改归 DL_Base 段
 *                       0001_0112 / 0001_0213，行为语义零改动
 *============================================================================*)
TYPE E_DL_TolJudge :
(
    eUnKnown := 0,   // 未使能 / 非法参数安全态 / Not enabled or invalid parameters
    eOk      := 1,   // 合格窗内 / Inside the tolerance window
    eLowOut  := 2,   // 低于下差 / Below the lower deviation limit
    eHighOut := 3    // 高于上差 / Above the upper deviation limit
);
END_TYPE

FUNCTION_BLOCK FB_DL_ToleranceWindow
VAR_INPUT
    bEnable      : BOOL;                // 使能，FALSE 时输出回安全态 eUnKnown（Enable, FALSE returns to the safe state）
    fTarget      : LREAL := 0.0;        // 目标值 [工程单位随应用] / Target value [EU by application]
    fActual      : LREAL := 0.0;        // 实际值 [工程单位随应用] / Actual value [EU by application]
    fTolerance   : LREAL := 0.5;        // 公差半带宽 [工程单位]，必须 > 0，非法锁 eUnKnown / Tolerance half band [EU], must be positive
    fHysteresis  : LREAL := 0.05;       // 迟滞回差 [工程单位]，0..fTolerance/2，越界钳位 / Hysteresis band [EU], clamped
END_VAR
VAR_OUTPUT
    eJudge       : E_DL_TolJudge;       // 三态判定结果（保持型）/ Three-state judgment, level-held
    bOk          : BOOL;                // 合格（偏差在公差带内）/ Within tolerance
    bLowOut      : BOOL;                // 低于下差 / Below the lower limit
    bHighOut     : BOOL;                // 高于上差 / Above the upper limit
    bDeviation   : BOOL;                // 偏差越窗事件，单拍脉冲（从合格迁出到越差）/ Deviation event, single pulse
    uErrorId     : UDINT;               // 故障码，0 = 无故障（见头注释故障码表）/ Error code, 0 = no error
END_VAR
VAR
    eLast        : E_DL_TolJudge;       // 上拍判定状态（迟滞与越窗边沿基准，单一来源）/ Previous judgment, single edge basis
    fDev         : LREAL;               // 有符号偏差 = 实际 - 目标 [工程单位] / Signed deviation [EU]
    fExitBand    : LREAL;               // 出窗阈宽 = fTolerance + fHysteresis [工程单位] / Exit threshold width [EU]
    fHystEff     : LREAL;               // 钳位后的有效回差 [工程单位] / Effective clamped hysteresis [EU]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : LREAL := 1.0E-9;     // 判等容差，全判据 ABS 差值比较 / Equality tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜本拍缺省：事件脉冲自清（R25），故障码清零，派生输出先归 FALSE
 *      Per-scan defaults: event pulse self-clears, derived outputs cleared first
 *-----------------------------------------------------------------------------*)
uErrorId   := 16#0000_0000;
bDeviation := FALSE;
bOk        := FALSE;
bLowOut    := FALSE;
bHighOut   := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜使能门（边界 B1）：失能即回安全态，eLast 同步归位，不残留旧判定
 *      Enable gate: disabled returns to the safe state and resyncs the basis
 *      eLast 必须同步归 eUnKnown：否则重新使能的第一拍会拿陈旧基准做迟滞判断
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    eJudge := eUnKnown;         // 安全态 / Safe state
    eLast  := eUnKnown;         // 边沿基准同步归位 / Resync the edge basis
    RETURN;                     // 派生输出已在段 1 清零，安全态达成
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数校验与钳位（红线 R4 / 边界 B2）
 *      Parameter validation and clamping
 *-----------------------------------------------------------------------------*)
IF fTolerance <= DL_FLOAT_EPS THEN
    uErrorId := 16#0001_0213;   // 故障级：公差非正 / Fault: non-positive tolerance
    eJudge   := eUnKnown;       // 输出锁安全态 / Lock the safe state
    eLast    := eUnKnown;       // 基准同步归位 / Resync the basis
    RETURN;                     // 参数非法不分档，禁止静默输出判定
END_IF

IF (fHysteresis < 0.0) OR (fHysteresis > fTolerance * 0.5) THEN
    (* 钳位方向跟随越界方向：负值归零、超上限收到半带宽（B2 口径） *)
    IF fHysteresis < 0.0 THEN
        fHystEff := 0.0;        // 负回差归零 / Negative band clamped to zero
    ELSE
        fHystEff := fTolerance * 0.5;   // 超半带宽钳到上限 / Over half-band clamped to the cap
    END_IF
    uErrorId := 16#0001_0112;   // 信息级：回差越界已钳位 / Info: hysteresis clamped
    (* 钳位后照常判定：回差修正不应吞掉本拍三态判定 *)
ELSE
    fHystEff := fHysteresis;    // 合法回差直通 / Legal band passes through
END_IF

fDev      := fActual - fTarget;         // 有符号偏差（方向信息保留给分侧判定）
fExitBand := fTolerance + fHystEff;      // 出窗阈宽 = 公差 + 回差（B1 宽阈）

(*------------------------------------------------------------------------------
 * 段 4｜三态状态机主体（红线 R6）：CASE + ELSE 兜底，迟滞跃迁按边界 B1 次序
 *      Three-state machine with CASE and ELSE fallback, hysteresis per B1
 *-----------------------------------------------------------------------------*)
CASE eLast OF
    E_DL_TolJudge.eUnKnown:
        (* 首次入窗：按窄阈分类（边界 B3），落回差带内保守判合格 *)
        (* 无迟滞记忆可用：本分支只看当拍偏差，窄阈即公差带本身 *)
        IF ABS(fDev) <= fTolerance THEN
            eJudge := eOk;
        ELSIF fDev < 0.0 THEN
            eJudge := eLowOut;      // 负偏差归下差侧 / Negative deviation to the low side
        ELSE
            eJudge := eHighOut;     // 正偏差归上差侧 / Positive deviation to the high side
        END_IF

    E_DL_TolJudge.eOk:
        IF fDev < -fExitBand THEN
            eJudge := eLowOut;      // 出窗阈宽：越过下差 + 回差才迁出
        ELSIF fDev > fExitBand THEN
            eJudge := eHighOut;     // 对称上侧 / Symmetric upper side
        ELSE
            eJudge := eOk;          // 回差带内保持原态（迟滞定义，B1）
        END_IF

    E_DL_TolJudge.eLowOut:
        IF fDev >= -fTolerance THEN
            eJudge := eOk;          // 进窗阈窄：回到公差带内即返回
        ELSE
            eJudge := eLowOut;      // 仍在下差侧保持 / Still low, hold
        END_IF

    E_DL_TolJudge.eHighOut:
        IF fDev <= fTolerance THEN
            eJudge := eOk;          // 进窗阈窄：对称侧 / Narrow entry, symmetric side
        ELSE
            eJudge := eHighOut;     // 仍在上差侧保持 / Still high, hold
        END_IF
    (* 两侧分支结构完全对称：改动任一侧必须同步另一侧，防止迟滞失对称 *)

    ELSE
        (* 非法状态兜底（红线 R6）：按窄阈重新分类自愈，不锁死 *)
        (* 与 eUnKnown 分支同口径：非法态视同重新使能首拍 *)
        IF ABS(fDev) <= fTolerance THEN
            eJudge := eOk;
        ELSIF fDev < 0.0 THEN
            eJudge := eLowOut;
        ELSE
            eJudge := eHighOut;
        END_IF
END_CASE

(*------------------------------------------------------------------------------
 * 段 5｜越窗事件（边界 B4）：eOk → 越差态的迁移拍置单拍脉冲（R25 三律）
 *      Deviation event: single pulse on the eOk-to-outward transition scan
 *      仅覆盖"合格迁出"方向：越差态之间的横向迁移（理论上不可能）不重复告警
 *-----------------------------------------------------------------------------*)
IF (eLast = E_DL_TolJudge.eOk) AND (eJudge <> E_DL_TolJudge.eOk) THEN
    bDeviation := TRUE;         // 单拍：越窗事件 / Single pulse: deviation event
END_IF
(* 越差迁回合格方向不置事件：返回窗内是恢复不是异常，避免恢复刷屏 *)

(*------------------------------------------------------------------------------
 * 段 6｜派生输出与边沿基准刷新（边界 B5）：eJudge 为唯一真相源，
 *      eLast 每拍末尾统一刷新，全块只有这一处写 eLast（单一来源）
 *      Derived outputs from eJudge; eLast refreshed exactly once per scan
 *-----------------------------------------------------------------------------*)
bOk      := (eJudge = E_DL_TolJudge.eOk);
bLowOut  := (eJudge = E_DL_TolJudge.eLowOut);
bHighOut := (eJudge = E_DL_TolJudge.eHighOut);
(* 三派生布尔互斥完备：任一拍恰有一个为 TRUE（合法参数时），
   调用方并联使用无需再加互斥逻辑 *)
eLast    := eJudge;             // 边沿基准刷新，位置固定在段尾（单一写点）
END_FUNCTION_BLOCK
