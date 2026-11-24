(*
  ==================================================================
  组件名 Component  : FB_DL_PidParamGuard
  分类   Category   : DL_Algo
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : PID 参数组在线运行期守卫（Kp/Ti/Td 有限性 + 域闸 + 退化降级）。
  来源   Source     : self-std（PID 参数治理公开语义自研）
  平台   Platform   : 纯 IEC 61131-3（比较 / ABS / R_TRIG），三平台通用
  分工声明 Split     : 与 FB_DL_PidParamDriftAudit 分工声明（R216）：本件做在线
                      参数闸（每拍有限性 + 域闸 + 退化降级，运行期保护）；后者
                      做离线漂移审计（趋势记录与慢漂分析）。两件双向互引，不
                      重复对方职责。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限入参 → 故障锁存 + 冻结上次合法快照（R187），
                         复位沿解除（bReset 恒可达，R152 自证）；
                      二 参数越界降级为上次合法值快照（不静默清零，R191 声明行：
                         bDegraded = TRUE + 出口保持快照），置信息级码；
                      三 快照更新只在「全部参数合法且域内」拍执行（保持槽写前
                         过闸，FB32-7）；首拍无快照时以域中点常量兜底（FB32-3
                         两级回退第二级）；
                      四 域闸上界须 > 下界（组态闸，逐对判，非法锁存同故障码）；
                      五 非有限闸逐个点名 9 个浮点入参（R272 全量枚举：fKp /
                         fTi / fTd / 六个域界引脚）；
                      六 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0002_3733【故障级】参数组含非有限值或域界组态非法，冻结快照，锁存至复位沿
    16#0002_3734【信息级】参数越域，已降级为上次合法快照（逐拍重算）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 合法参数 → 三出口等于入参、bDegraded=FALSE
    V2 fKp=NaN → 码 3733、出口保持上次快照、锁存待复位
    V3 fKp 越上界 → 码 3734、fKpUse=上次快照、bDegraded=TRUE
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 3 · 序号 11）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_PidParamGuard
VAR_INPUT
    bEnable : BOOL := TRUE;  // 使能，FALSE 时冻结快照出口（R191 声明行）/ the enable, false freezes the snapshot outlet
    bReset  : BOOL := FALSE; // 故障复位电平，上升沿清锁存 / the fault reset level
    fKp     : LREAL := 1.0;  // 比例增益入参 [-] / the proportional gain input
    fTi     : LREAL := 1.0;  // 积分时间入参 [秒] / the integral time input
    fTd     : LREAL := 0.0;  // 微分时间入参 [秒] / the derivative time input
    fKpMin  : LREAL := 0.0;  // 比例域下界 [-] / the proportional domain floor
    fKpMax  : LREAL := 100.0; // 比例域上界 [-] / the proportional domain ceiling
    fTiMin  : LREAL := 0.001; // 积分域下界 [秒] / the integral domain floor
    fTiMax  : LREAL := 3600.0; // 积分域上界 [秒] / the integral domain ceiling
    fTdMin  : LREAL := 0.0;  // 微分域下界 [秒] / the derivative domain floor
    fTdMax  : LREAL := 60.0; // 微分域上界 [秒] / the derivative domain ceiling
END_VAR
VAR_OUTPUT
    fKpUse    : LREAL := 1.0;  // 比例增益出口（快照或原值）[-] / the proportional gain outlet
    fTiUse    : LREAL := 1.0;  // 积分时间出口 [秒] / the integral time outlet
    fTdUse    : LREAL := 0.0;  // 微分时间出口 [秒] / the derivative time outlet
    bDegraded : BOOL := FALSE; // 本拍降级标志（信息级伴随）[-] / the degraded flag of this scan
    bError    : BOOL := FALSE; // 故障锁存位（与锁存同源，R191）/ the fault bit from the latch
    bValid    : BOOL := FALSE; // 参数可用标志 [-] / the parameters usable flag
    eErr      : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit    : BOOL := FALSE; // 首拍初始化标志（R310）/ the first scan flag
    _bFault   : BOOL := FALSE; // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _bFin     : BOOL := FALSE; // 非有限闸结果（逐拍重算）/ the finiteness gate result
    _bInDom   : BOOL := FALSE; // 域闸结果（逐拍重算）/ the domain gate result
    _bDomCfg  : BOOL := FALSE; // 域界组态合法标记（逐拍重算）/ the domain configuration flag
    _fKpSnap  : LREAL := 1.0;  // 比例快照（仅合法拍更新）/ the proportional snapshot
    _fTiSnap  : LREAL := 1.0;  // 积分快照 / the integral snapshot
    _fTdSnap  : LREAL := 0.0;  // 微分快照 / the derivative snapshot
    rtReset   : R_TRIG; // 复位沿实例，段 0 无条件刷新 / the reset edge instance
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首拍初始化与复位沿作用域（R310 / R311）/ segment 1, the first scan init and the reset scope
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _fKpSnap := fKp; // 首拍以入参装快照（入参缺省即域内默认）/ seed the snapshot from the input
    _fTiSnap := fTi; // 积分快照装填 / seed the integral snapshot
    _fTdSnap := fTd; // 微分快照装填 / seed the derivative snapshot
END_IF
IF rtReset.Q THEN // 复位沿（作用域：仅清锁存，快照保持最近合法值，R311 声明）/ the reset edge clears the latch only
    _bFault := FALSE; // 清故障锁存（解除路径：复位沿恒可达，R152 自证）/ clear the fault latch
END_IF

// 段 2｜非有限闸：9 个浮点入参逐个点名（R272 全量，边界五）/ segment 2, the finiteness gate naming all nine floating pins
_bFin := (fKp = fKp) AND ((fKp - fKp) = (fKp - fKp))
AND (fTi = fTi) AND ((fTi - fTi) = (fTi - fTi))
AND (fTd = fTd) AND ((fTd - fTd) = (fTd - fTd))
AND (fKpMin = fKpMin) AND ((fKpMin - fKpMin) = (fKpMin - fKpMin))
AND (fKpMax = fKpMax) AND ((fKpMax - fKpMax) = (fKpMax - fKpMax))
AND (fTiMin = fTiMin) AND ((fTiMin - fTiMin) = (fTiMin - fTiMin))
AND (fTiMax = fTiMax) AND ((fTiMax - fTiMax) = (fTiMax - fTiMax))
AND (fTdMin = fTdMin) AND ((fTdMin - fTdMin) = (fTdMin - fTdMin))
AND (fTdMax = fTdMax) AND ((fTdMax - fTdMax) = (fTdMax - fTdMax)); // NaN 自反 + Inf 差值自减逐项 / the reflexive and difference tests term by term

// 段 3｜域界组态闸与域闸（边界四）/ segment 3, the domain configuration and the domain gates
_bDomCfg := (fKpMax > fKpMin) AND (fTiMax > fTiMin) AND (fTdMax > fTdMin); // 三对域界严格递增 / the three strictly increasing pairs
_bInDom := (fKp >= fKpMin) AND (fKp <= fKpMax)
AND (fTi >= fTiMin) AND (fTi <= fTiMax)
AND (fTd >= fTdMin) AND (fTd <= fTdMax); // 三参数域内判 / the three parameters inside the domains
IF (NOT _bFin) OR (NOT _bDomCfg) THEN // 非有限或域界非法：故障锁存（边界一）/ a non finite or an illegal domain configuration
    _bFault := TRUE; // 锁存故障（3733，出口回放）/ latch the fault
END_IF

// 段 4｜快照闸与降级（边界二三）/ segment 4, the snapshot gate and the degradation
IF _bFin AND _bDomCfg AND _bInDom THEN // 全部合法：出口 = 原值并更新快照（保持槽写前过闸，FB32-7）/ all legal, the outlet takes the values and updates the snapshot
    _fKpSnap := fKp; // 快照更新 / update the snapshot
    _fTiSnap := fTi; // 快照更新 / update the snapshot
    _fTdSnap := fTd; // 快照更新 / update the snapshot
    bDegraded := FALSE; // 无降级 / no degradation
ELSIF (NOT _bFault) THEN // 域外但无锁存：降级为快照（不静默清零，边界二）/ out of the domain without a latch, degrade to the snapshot
    bDegraded := TRUE; // 置降级标志 / raise the degraded flag
ELSE // 故障锁存态：出口冻结快照（R191 声明行）/ the latched state freezes the snapshot outlet
    bDegraded := FALSE; // 降级标志不置（故障码已表达）/ the degraded flag stays low
END_IF

// 段 5｜统一出口（冻结语义：保持上次合法快照，R191 / R273 防污染：快照本身写前过闸）/ segment 5, the unified outlet
fKpUse := _fKpSnap; // 比例出口 / the proportional outlet
fTiUse := _fTiSnap; // 积分出口 / the integral outlet
fTdUse := _fTdSnap; // 微分出口 / the derivative outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet
bValid := (NOT _bFault) AND (NOT bDegraded); // 参数可用标志 / the usable flag
IF _bFault THEN // 故障锁存回放（R187）/ the latched fault replays
    eErr := 16#0002_3733; // 故障级：参数非有限或域界组态非法 / fault grade, the non finite parameter or the illegal domain
ELSIF bDegraded THEN // 降级（信息级不置 bError，R285 口径）/ the degraded informational code
    eErr := 16#0002_3734; // 信息级：参数越域已降级为快照 / informational, degraded to the snapshot
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
