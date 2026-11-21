// ==============================================================================
// 组件名 Component  : FB_DL_HysteresisBandMon
// 分类   Category   : DL_Base
// 前缀   Naming     : FB_DL_ ｜ b/f/e 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 低
// 功能   Purpose    : 区间状态监视（三带迟滞）：fIn 相对 [fLow, fHigh] 判
//                      eBelow / eIn / eAbove 三带，带界切换带 fHyst 迟滞
//                      （防临界抖动）；进 eBelow / eAbove 各发单拍沿脉冲。
// 文件互引声明 Split : FC_DL_Hysteresis（DL_MathData）为点值滞回计算
//                      （布尔输出 + 调用方持有状态），本件为区间状态监视
//                      （三带枚举 + 实例自持状态 + 沿脉冲），语义不同
//                      勿混用（R216 双向互引）。
// 开源溯源 Origin    : 道莅原创（三带迟滞区间监视为公开工程语义，本实现
//                      clean-room，未复制任何源码行）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6 ENUM + CASE 状态机语义
// 平台   Platform   : 纯 IEC 61131-3（ENUM + CASE / LREAL 比较），三平台通用
// 依赖   Depends    : 无（零委托、零库件；无定时器 / 边沿实例）
// 归属 Ownership     : E_DL_HbmZone / E_DL_HbmErr 属主为本文件（全库唯一
//                      定义，R264）；引用件只引用不重声明。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 组态守卫（逐项点名，R272）：fLow >= fHigh、fHyst < 0、fHyst >=
//      (fHigh - fLow)、fLow / fHigh 非有限（NaN 自反判 + 幅值 1e30 上界）
//      任一成立 → eErr = eCfg、bErr = TRUE、eZone 强制安全中位 eIn、
//      沿脉冲清零（本拍重算，非锁存——组态修复下一拍即恢复）；
//   二 输入守卫：fIn 非有限 → eErr = eInput、bErr = TRUE、eZone 强制
//      安全中位 eIn、沿脉冲清零（eCfg 与 eInput 同拍并存时组态优先，
//      归因唯一）；
//   三 切换规则（对称迟滞）：eBelow → eIn 需 fIn > fLow + fHyst；
//      eIn → eBelow 需 fIn < fLow；eIn → eAbove 需 fIn > fHigh；
//      eAbove → eIn 需 fIn < fHigh - fHyst；跨带跳变（eBelow 直接越
//      fHigh）一步直达 eAbove（一步直达比两步过带更早暴露越界）；
//   四 沿脉冲单拍有效：bBelowEdge / bAboveEdge 以本拍前态快照为基准，
//      错误路径在沿计算前早退故恒 FALSE；
//   五 失能（bEn = FALSE）语义写死（R303 离相清零）：eZone 强制安全
//      中位 eIn、沿脉冲清零、bErr / eErr 清零（失能不是故障）；
//   六 CASE 带 ELSE 非法枚举兜底：强制回 eIn + eErr = eCfg（eErr 枚举
//      无非法态成员，按 R90 反证句归并组态族——非法态与组态非法出口
//      组合同为 eIn + bErr，现有输出不可区分，故合并一码）；
//   七 无定时器 / 无边沿实例（周期安全规则 N/A）；无除法；
//      无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0001_0747【信息级】组态非法（eErr = eCfg 通道，bErr 置位，eZone
//                强制安全中位 eIn，不锁存）
//   16#0001_0748【信息级】输入非有限（eErr = eInput 通道，bErr 置位，
//                eZone 强制安全中位 eIn，不锁存）
//   注：本件 eErr 为枚举出口（引脚契约按任务定稿），上述数值码位为
//   文档级对照；两码分立依据：eCfg 组态即刻判（处置人 = 组态工程师），
//   eInput 需运行期输入到达（处置人 = 仪表），R90 分立。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 fLow=0/fHigh=100/fHyst=5：fIn=-1 → eBelow；fIn=50 → eIn（进带脉冲无）
//   V2 eBelow 态 fIn=6（> fLow+fHyst）→ eIn；fIn=3（< fLow+fHyst）→ 保持
//   V3 eIn 态 fIn=99 → eAbove（bAboveEdge 单拍）；fIn=94（< fHigh-fHyst）→ eIn
//   V4 fIn 跳变 -5 → 105：eBelow 一步直达 eAbove（单拍 bAboveEdge）
//   V5 fLow >= fHigh → eCfg + eZone = eIn；fIn = NaN → eInput + eZone = eIn
//   V6 bEn = FALSE → eZone = eIn、全出口清零（R303）
//   V7 非法枚举态（强改 _eZone）→ ELSE 兜底回 eIn + eCfg
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 2 · 序号 6）
// ==============================================================================
TYPE E_DL_HbmZone :
(
    eBelow := 0,  // 下带：fIn 低于下带界 / below, the input under the lower band edge
    eIn    := 10, // 中带：fIn 在带内（安全中位）/ inside, the safe middle zone
    eAbove := 20  // 上带：fIn 高于上带界 / above, the input over the upper band edge
);
END_TYPE

TYPE E_DL_HbmErr :
(
    eNone  := 0,  // 无错 / no error
    eCfg   := 10, // 组态非法（fLow / fHigh / fHyst 域非法）/ an illegal configuration
    eInput := 20  // 输入非有限（fIn 为 NaN / Inf / 超幅值）/ a non finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_HysteresisBandMon
VAR_INPUT
    fIn   : LREAL;               // 监视输入 [工程单位] / the monitored input
    fLow  : LREAL := 0.0;        // 区间下界 [工程单位]，须 < fHigh / the lower band edge
    fHigh : LREAL := 100.0;      // 区间上界 [工程单位]，须 > fLow / the upper band edge
    fHyst : LREAL := 0.0;        // 迟滞半带宽 [工程单位]，须 [0, fHigh - fLow) / the hysteresis half band
    bEn   : BOOL := TRUE;        // 使能 [-]，FALSE 时出口清零回中位（R303）/ the enable
END_VAR
VAR_OUTPUT
    eZone      : E_DL_HbmZone := E_DL_HbmZone.eIn; // 区间状态出口 [状态]（安全中位初值）/ the zone outlet, safe middle initial
    bBelowEdge : BOOL := FALSE;  // 进入下带沿脉冲 [-]，单拍有效 / the below entry edge pulse, single scan
    bAboveEdge : BOOL := FALSE;  // 进入上带沿脉冲 [-]，单拍有效 / the above entry edge pulse, single scan
    bErr       : BOOL := FALSE;  // 错误标志 [-]，eCfg / eInput 置位 / the error flag
    eErr       : E_DL_HbmErr := E_DL_HbmErr.eNone; // 错误码出口 [码] / the error code outlet
END_VAR
VAR
    _eZone     : E_DL_HbmZone := E_DL_HbmZone.eIn; // 内部状态寄存器 [状态] / the internal state register
    _eZonePrev : E_DL_HbmZone := E_DL_HbmZone.eIn; // 本拍前态快照 [状态]（沿判定基准）/ the previous zone snapshot, the edge baseline
    _bCfgBad   : BOOL;           // 组态非法标志（逐拍重算）/ the configuration fault flag
    _bInBad    : BOOL;           // 输入非有限标志（逐拍重算）/ the input fault flag
END_VAR
VAR CONSTANT
    DL_HBM_FMAX : LREAL := 1.0E30; // 非有限筛查幅值上限 [工程单位] / the finiteness screening cap
END_VAR

// 段 1｜单拍沿脉冲与错误出口预清零（R256 统一出口预置）/ segment 1, the single scan preset
bBelowEdge := FALSE;             // 下带沿脉冲预清零 / preset the below edge false
bAboveEdge := FALSE;             // 上带沿脉冲预清零 / preset the above edge false
bErr       := FALSE;             // 错误标志预清零 / preset the error flag false
eErr       := E_DL_HbmErr.eNone; // 错误码预置无错 / preset the code to none

// 段 2｜失能分支：出口清零回安全中位，不置错（R303 离相清零声明行）/ segment 2, the disabled branch
IF NOT bEn THEN                  // 失能 / disabled
    _eZone := E_DL_HbmZone.eIn;  // 强制安全中位 / force the safe middle
    eZone := _eZone;             // 状态出口 / the zone outlet
    bBelowEdge := FALSE;         // 沿脉冲清零 / clear the below edge
    bAboveEdge := FALSE;         // 沿脉冲清零 / clear the above edge
    bErr := FALSE;               // 失能不是故障 / a disabled device is not a fault
    eErr := E_DL_HbmErr.eNone;   // 失能不发码 / no code while disabled
    RETURN;                      // 早退 / early return
END_IF

// 段 3｜组态守卫（边界一：四判据逐项点名，R272）/ segment 3, the configuration guard
_bCfgBad := (fLow >= fHigh)                                  // 下界不低于上界 / the lower edge not under the upper
         OR (fHyst < 0.0)                                    // 迟滞为负 / a negative hysteresis
         OR (fHyst >= (fHigh - fLow))                        // 迟滞吞没整带 / the hysteresis swallowing the whole band
         OR (fLow <> fLow) OR ((fLow - fLow) <> 0.0) OR (ABS(fLow) > DL_HBM_FMAX)      // fLow 非有限 / fLow non finite
         OR (fHigh <> fHigh) OR ((fHigh - fHigh) <> 0.0) OR (ABS(fHigh) > DL_HBM_FMAX) // fHigh 非有限 / fHigh non finite
         OR (fHyst <> fHyst) OR ((fHyst - fHyst) <> 0.0) OR (ABS(fHyst) > DL_HBM_FMAX); // fHyst 非有限 / fHyst non finite
IF _bCfgBad THEN                 // 组态非法 / an illegal configuration
    _eZone := E_DL_HbmZone.eIn;  // 强制安全中位（边界一）/ force the safe middle
    eZone := _eZone;             // 状态出口 / the zone outlet
    bErr := TRUE;                // 错误标志置位 / raise the error flag
    eErr := E_DL_HbmErr.eCfg;    // 信息级 0747：组态非法 / the configuration code
    RETURN;                      // 早退（沿脉冲保持段 1 预清零）/ early return
END_IF

// 段 4｜输入守卫（边界二：NaN 自反判 + Inf 差值自反判 + 幅值上界）/ segment 4, the input guard
_bInBad := (fIn <> fIn) OR ((fIn - fIn) <> 0.0) OR (ABS(fIn) > DL_HBM_FMAX); // 输入非有限 / the input non finite
IF _bInBad THEN                  // 输入无效 / an invalid input
    _eZone := E_DL_HbmZone.eIn;  // 强制安全中位（边界二）/ force the safe middle
    eZone := _eZone;             // 状态出口 / the zone outlet
    bErr := TRUE;                // 错误标志置位 / raise the error flag
    eErr := E_DL_HbmErr.eInput;  // 信息级 0748：输入非有限 / the input code
    RETURN;                      // 早退（沿脉冲保持段 1 预清零）/ early return
END_IF

// 段 5｜三带状态机（ENUM + CASE + ELSE 兜底，边界三 / 六）/ segment 5, the three zone machine
_eZonePrev := _eZone;            // 本拍前态快照（沿判定基准，边界四）/ snapshot the previous zone
CASE _eZone OF
    E_DL_HbmZone.eBelow:         // 下带 / the below zone
        IF fIn > fHigh THEN      // 跨带跳变直达上界之上（边界三一步直达）/ a jump beyond the upper edge
            _eZone := E_DL_HbmZone.eAbove; // 一步迁入上带 / straight to the above zone
        ELSIF fIn > (fLow + fHyst) THEN // 越过下带迟滞恢复线 / over the lower recovery line
            _eZone := E_DL_HbmZone.eIn;    // 迁入中带 / enter the inside zone
        END_IF
    E_DL_HbmZone.eIn:            // 中带 / the inside zone
        IF fIn < fLow THEN       // 跌破下界（严格小于，边界三）/ under the lower edge
            _eZone := E_DL_HbmZone.eBelow; // 迁入下带 / enter the below zone
        ELSIF fIn > fHigh THEN   // 越过上界（严格大于）/ over the upper edge
            _eZone := E_DL_HbmZone.eAbove; // 迁入上带 / enter the above zone
        END_IF
    E_DL_HbmZone.eAbove:         // 上带 / the above zone
        IF fIn < fLow THEN       // 跨带跳变跌破下界 / a jump under the lower edge
            _eZone := E_DL_HbmZone.eBelow; // 一步迁入下带 / straight to the below zone
        ELSIF fIn < (fHigh - fHyst) THEN // 跌破上带迟滞恢复线 / under the upper recovery line
            _eZone := E_DL_HbmZone.eIn;    // 迁入中带 / enter the inside zone
        END_IF
    ELSE                         // 非法枚举值拦截（边界六：回中位 + 组态族合并码，R90 反证句见码表）/ the illegal enumeration guard
        _eZone := E_DL_HbmZone.eIn; // 强制回安全中位 / force back to the safe middle
        bErr := TRUE;            // 错误标志置位（禁静默）/ raise the error flag
        eErr := E_DL_HbmErr.eCfg; // 归并组态族一码（出口同形不可区分，R90）/ merged into the configuration code
END_CASE

// 段 6｜沿脉冲与状态出口（边界四：基准 = 本拍前态快照，单拍有效）/ segment 6, the edges and the zone outlet
bBelowEdge := (_eZone = E_DL_HbmZone.eBelow) AND (_eZonePrev <> E_DL_HbmZone.eBelow); // 进入下带沿 / the below entry edge
bAboveEdge := (_eZone = E_DL_HbmZone.eAbove) AND (_eZonePrev <> E_DL_HbmZone.eAbove); // 进入上带沿 / the above entry edge
eZone := _eZone;                 // 状态出口（名实双出口同源，R191）/ the zone outlet
END_FUNCTION_BLOCK
