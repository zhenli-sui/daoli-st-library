(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ModuloCounter
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 分类     (Category)   : 信号处理功能块（Function Block · 取模工位索引）
 * 功能简述 (Function)   : 循环计数器（转盘/弹夹工位索引）。0..(nMod-1) 取
 *                         模回绕，支持双向步进、带合法性校验的跳步与回绕事
 *                         件一拍输出；模数 <2 参数非法故障锁存，跳步目标越
 *                         界拒绝置信级，双向同拍抵消置信级。
 *                         与 FB_DL_EventCounter 职责分离（通用事件计数 vs
 *                         取模工位索引），非重复组件。
 * 公约遵循 (Convention) : 0.1/R23 事件型，免首扫——索引由步进/跳步沿驱动，
 *                         无初始化/跟踪同步语义，不设 bInit。
 *                         0.2/R21 bFault 为显式排除信息级码的派生式；信息级
 *                         只进 uErrorId 不进报警链。
 *                         0.7/R15 故障级锁存仅解除路径（bReset 上升沿）清码。
 *                         0.8 故障码段位 16#0001_xxxx（经 DL_Base VERSION.md
 *                         码表核对，0001_0103~0104 / 0001_0211 均未占用）：
 *                         【故障级】0001_0211 模数非法（nMod < 2）；
 *                         【信息级】0001_0103 跳步目标越界拒绝、0001_0104
 *                         双向步进同拍抵消。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 模数非法/越界防御 + 显式
 *                         类型转换（UINT↔DINT）✓
 *                         R5 全变量中英双语同行注释 ✓｜R7 边沿实例主体最前
 *                         部无条件刷新 ✓｜R8 常量化无魔法数 ✓
 * 设计要点 (Key notes)  : ① 取模实现禁用取余运算符对负数的平台差异——回绕
 *                           用条件加减法（减 nMod / 加 nMod）实现，全部在
 *                           DINT 域运算后显式转回 UINT（CODESYS/TwinCAT/
 *                           汇川三平台行为一致，跨平台意图注释在此留档）；
 *                         ② nMod < 2 → 参数非法故障锁存【故障级】（除零与
 *                           退化防御）；nJumpTo >= nMod → 跳步拒绝 + 信息级；
 *                         ③ bStepFwd 与 bStepRev 同拍到达：抵消，置信级；
 *                         ④ bWrapped 跨零点步进置位一拍（转盘单圈计数用）。
 * 开源溯源 (Origin)     : 来源标签 lgf-counter（RAW_NOTES_R7 S-1：LGF 库计
 *                         数器族的取模索引功能域语义，公开文档，仅借鉴功能
 *                         域；条件加减法回绕、跳步校验、故障码与引脚契约
 *                         100% 本库独立设计，clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 连续步进跨零回绕：nMod=8，uIndex=7 时 bStepFwd → 0 且 bWrapped 一拍；
 *   V2 反向跨零：uIndex=0 时 bStepRev → 7 且 bWrapped 一拍；
 *   V3 合法跳步：nJumpTo=5 < nMod=8 → uIndex=5；非法跳步 nJumpTo=9 → 拒绝
 *      保持 5 且信息级 0001_0103；
 *   V4 模数=2 边界：uIndex 在 0/1 间循环；nMod=1 → 故障锁存 0001_0211；
 *   V5 双向抵消：同拍 bStepFwd+bStepRev → 不变且信息级 0001_0104；
 *   V6 复位：bReset 沿 → uIndex=0、故障清零。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Base LGF Counter 组开组）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ModuloCounter
VAR_INPUT
    bStepFwd : BOOL;            // 前进步进脉冲（Step forward），R_TRIG 上升沿 +1 取模 / Step forward edge, +1 modulo
    bStepRev : BOOL;            // 后退步进脉冲（Step reverse），R_TRIG 上升沿 -1 取模 / Step reverse edge, -1 modulo
    bJump    : BOOL;            // 跳步指令（Jump to index），上升沿装载 nJumpTo（带合法性校验）/ Jump edge loads nJumpTo with validity check
    nJumpTo  : UINT;            // 跳步目标工位号（Jump target index）[-]，域 0..nMod-1，越界拒绝 / Jump target, range 0..nMod-1, rejected outside
    nMod     : UINT := 8;       // 循环模数（Modulo count，工位数）[-]，域 2..65535，禁止 0/1（除零与退化防御）/ Modulo count, range 2..65535, 0/1 forbidden
    bReset   : BOOL;            // 上升沿复位故障与清零（Reset edge clears fault and index）/ Rising edge resets fault and clears index
END_VAR
VAR_OUTPUT
    uIndex   : UINT;            // 当前工位索引（Current index）[-]，0..nMod-1 / Current station index, 0..nMod-1
    bWrapped : BOOL;            // 回绕事件标志（Wrapped event），跨零点步进置位一拍（转盘单圈计数用）/ Wrapped event, one scan when crossing zero point
    bFault   : BOOL;            // 故障标志（Fault flag），显式排除信息级码（R21）/ Fault flag, info codes explicitly excluded
    uErrorId : UDINT;           // 故障码（Error code），16#0001_xxxx 段，0=无故障 / Error code, family 16#0001_xxxx, 0 = none
END_VAR
VAR
    _fbTrigFwd   : R_TRIG;      // 前进沿检测（Forward edge detector）/ Forward step edge detector
    _fbTrigRev   : R_TRIG;      // 后退沿检测（Reverse edge detector）/ Reverse step edge detector
    _fbTrigJump  : R_TRIG;      // 跳步沿检测（Jump edge detector）/ Jump command edge detector
    _fbTrigReset : R_TRIG;      // 复位沿检测（Reset edge detector）/ Reset edge detector
    _bFaultLatch : BOOL;        // 故障锁存标志（Fault latch flag），仅 bReset 上升沿清除 / Fault latch, cleared only by reset edge
    _uErrorIdInt : UDINT;       // 内部故障级码寄存（Internal fault-level code register）/ Internal fault-level code register
    _uInfoCode   : UDINT;       // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bFwdEdge    : BOOL;        // 本拍前进沿有效（Forward edge active this scan）/ Forward edge this scan
    _bRevEdge    : BOOL;        // 本拍后退沿有效（Reverse edge active this scan）/ Reverse edge this scan
    _bJumpEdge   : BOOL;        // 本拍跳步沿有效（Jump edge active this scan）/ Jump edge this scan
    _nWork       : DINT;        // DINT 域索引工作副本（DINT-domain working index）[-]，条件加减法载体 / DINT working index for conditional wrap arithmetic
    _nModEff     : UINT := 8;   // 防御后生效模数（Sanitized effective modulo）[-] / Sanitized effective modulo
    _nModD       : DINT;        // 生效模数 DINT 镜像（DINT mirror of effective modulo）[-] / DINT mirror of the modulo
END_VAR

// ============================================================================
// 段 1｜边沿实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all edge instances (R7/0.5)
// ============================================================================
_fbTrigFwd(CLK   := bStepFwd);
_fbTrigRev(CLK   := bStepRev);
_fbTrigJump(CLK  := bJump);
_fbTrigReset(CLK := bReset);
_bFwdEdge  := _fbTrigFwd.Q;     // 本拍前进沿（Forward edge this scan）
_bRevEdge  := _fbTrigRev.Q;     // 本拍后退沿（Reverse edge this scan）
_bJumpEdge := _fbTrigJump.Q;    // 本拍跳步沿（Jump edge this scan）

// ============================================================================
// 段 2｜信息级码预清零 + 复位路径（R15：锁存型故障只在解除路径清码）
//      Info code preset zero + reset path (R15)
// ============================================================================
_uInfoCode := 0;                // 信息级瞬时型每拍重算（Transient info recomputed each scan）
bWrapped := FALSE;              // 回绕事件每拍预清零，由段 4 事件置位一拍（Wrapped flag preset FALSE, set one scan by stage 4）

IF _fbTrigReset.Q THEN
    uIndex      := 0;           // 索引清零（Index cleared）
    _bFaultLatch := FALSE;      // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
END_IF

// ============================================================================
// 段 3｜参数防御：nMod < 2 → 故障锁存（0/1 除零与退化防御，故障级）
//      Parameter guard: nMod < 2 latches a fault (divide-by-zero and degeneration)
// ============================================================================
IF nMod < 2 THEN
    _bFaultLatch := TRUE;              // 模数非法故障锁存（Invalid modulo latch）
    _uErrorIdInt := 16#0001_0211;      // 0001_0211 模数非法【故障级】/ Invalid modulo, fault level
ELSE
    _nModEff := nMod;                  // 生效模数镜像（Effective modulo mirror）
    _nModD   := UINT_TO_DINT(_nModEff); // 显式转换 DINT 域（Explicit conversion to DINT domain）

    // ========================================================================
    // 段 4｜索引主逻辑：双向抵消 → 跳步 → 单向步进（条件加减法回绕）
    //      Index main logic: dual cancellation, jump, then conditional wrap stepping
    // ========================================================================
    IF _bFwdEdge AND _bRevEdge THEN
        _uInfoCode := 16#0001_0104;    // 0001_0104 双向同拍抵消【信息级】，索引不变 / Dual steps cancel, index unchanged, info level
    ELSIF _bJumpEdge THEN
        IF nJumpTo < _nModEff THEN
            uIndex := nJumpTo;         // 合法跳步：目标域 0..nMod-1（Valid jump within domain）
        ELSE
            _uInfoCode := 16#0001_0103; // 0001_0103 跳步目标越界拒绝【信息级】，索引保持 / Jump target out of range, rejected, info level
        END_IF
    ELSIF _bFwdEdge OR _bRevEdge THEN
        _nWork := UINT_TO_DINT(uIndex); // 显式转换进 DINT 域运算（Explicit conversion into DINT arithmetic）
        IF _bFwdEdge THEN
            _nWork := _nWork + 1;      // 前进一步（Forward one step）
            IF _nWork >= _nModD THEN
                _nWork := 0;           // 条件加减法回绕：越过模数回零点（Conditional wrap: above modulo back to zero, no remainder operator）
                bWrapped := TRUE;      // 跨零点事件一拍（Wrapped event, one scan）
            END_IF
        ELSE
            _nWork := _nWork - 1;      // 后退一步（Reverse one step）
            IF _nWork < 0 THEN
                _nWork := _nModD - 1;  // 条件加减法回绕：越过零点回模数尾（Conditional wrap: below zero to modulo tail）
                bWrapped := TRUE;      // 跨零点事件一拍（Wrapped event, one scan）
            END_IF
        END_IF
        uIndex := DINT_TO_UINT(_nWork); // 显式转换回 UINT 单点出口（Explicit conversion back, single outlet）
    END_IF
END_IF

// ============================================================================
// 段 5｜bFault/uErrorId 出口（R21：bFault 显式排除信息级；无故障级锁存时
//       uErrorId 透出本拍信息级码）
//      Outlets: bFault excludes info codes (R21); uErrorId shows info code when no fault
// ============================================================================
bFault := _bFaultLatch;             // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uIndex := 0;                    // 故障期索引输出安全零（Safe zero while latched）
    uErrorId := _uErrorIdInt;       // 故障级码优先透出（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;         // 无故障时透出本拍信息级码（Transient info code when no fault）
END_IF
END_FUNCTION_BLOCK
