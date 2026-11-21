(*==============================================================================
 * 组件名称 (Component)  : FB_DL_Decouple2x2
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 2×2 强耦合回路静态解耦网：静态解耦注入式
 *                           fU1Eff = fU1 + fD21×fU2
 *                           fU2Eff = fU2 + fD12×fU1
 *                         fD12 / fD21 = 组态解耦系数 = Δu_i 对 j 回路的静态影响比（无量纲）。
 *                         Bristol 相对增益整定参考（写入注释供现场整定者）：
 *                           fD12 ≈ -K12/K11，fD21 ≈ -K21/K22（Kij 为开环静态增益阵元，
 *                           T21 = K12×K21/(K11×K22) 作耦合强弱组态参考，本件不计算 T 值）。
 * 接口     (Interface)  : 输入 fU1/fU2 两主控输出（0~100%）、fD12/fD21 解耦系数（无量纲，
 *                         域 |fD|<=1）、bEnable 使能、bReset 复位；输出 fU1Eff/fU2Eff
 *                         解耦后等效输出（0~100%）、bEnabled 生效指示、bCfgBad 组态非法
 *                         （锁存）、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做静态解耦注入与输出钳位，不做动态
 *                         补偿、不接管主控 PID**；主控输出由上层 PID 件给出。
 *                         ② bEnable=FALSE 直通：fU1Eff:=fU1、fU2Eff:=fU2（不冻结历史值，
 *                         直通即语义，头注释声明）。
 *                         ③ 输出钳 [0,100%]（解耦注入可能越出主控行程，钳位防执行器饱和
 *                         反卷积）；钳位不置故障（饱和不等于故障）。
 *                         ④ 非有限输入直通拒改（fU/fD 任一非有限当拍按直通处理，R245）；
 *                         fD 非有限属组态病 → 锁存 bCfgBad。
 *                         ⑤ 解耦系数域闸：|fD12|>1 或 |fD21|>1 → 锁存 bCfgBad（反向主导
 *                         说明组态颠倒，比静默错注入危险），直通运行，解除沿 = bReset 上升沿。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_CascadePid` 分工：解耦网（并联注入）≠ 串级（主从串联）；
 *                         二者可组合不可互替。
 * 来源标签 (Source Tag) : T2-1 ◐（公开 Bristol RGA 公式只借整定口径，解耦网实现自研）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 组 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 系数域闸 + 非有限直通 + 输出钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 2 · 序号 9）
 *                         验收向量：fD=0 → 直通；fD21=0.5、fU2=100 → U1Eff 钳 100；
 *                         |fD|=1.2 → bCfgBad 锁存直通。
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_Decouple2x2
VAR_INPUT
    fU1    : LREAL := 0.0;    // 主控 1 输出（解耦前） [%] / Controller 1 output before decoupling [%]
    fU2    : LREAL := 0.0;    // 主控 2 输出（解耦前） [%] / Controller 2 output before decoupling [%]
    fD12   : LREAL := 0.0;    // 解耦系数：u1 对回路 2 的静态影响比（域 |fD|<=1） [无量纲] / Decoupling factor u1 onto loop 2
    fD21   : LREAL := 0.0;    // 解耦系数：u2 对回路 1 的静态影响比（域 |fD|<=1） [无量纲] / Decoupling factor u2 onto loop 1
    bEnable: BOOL := FALSE;   // 使能（FALSE=直通） [-] / Enable, FALSE bypasses
    bReset : BOOL := FALSE;   // 复位，上升沿清 bCfgBad 锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    fU1Eff  : LREAL;          // 解耦后回路 1 等效输出（已钳 0~100%） [%] / Loop 1 effective output, clamped 0..100%
    fU2Eff  : LREAL;          // 解耦后回路 2 等效输出（已钳 0~100%） [%] / Loop 2 effective output, clamped 0..100%
    bEnabled: BOOL;           // 解耦生效指示（使能 ∧ 组态合法） [-] / Decoupling active indicator
    bCfgBad : BOOL;           // 组态非法（|fD|>1 或非有限系数，锁存） [-] / Illegal configuration, latched
    bError  : BOOL;           // 故障标志（与 bCfgBad 同源，R191 配对） [-] / Error flag, paired with bCfgBad
END_VAR
VAR
    _bCfgLatch: BOOL;         // 组态非法锁存位（解除沿 = bReset 上升沿） / Latched config fault, cleared by reset edge
    rtReset   : R_TRIG;       // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bNonFin  : BOOL;         // 输入非有限当拍量 [-] / Non-finite input this scan
    _fRaw1    : LREAL;        // 当拍回路 1 未钳解耦值 [%] / Unlimited decoupled value for loop 1
    _fRaw2    : LREAL;        // 当拍回路 2 未钳解耦值 [%] / Unlimited decoupled value for loop 2
END_VAR
VAR CONSTANT
    DL_DC2_UMIN : LREAL := 0.0;    // 输出行程下限 [%] / Output travel floor [%]
    DL_DC2_UMAX : LREAL := 100.0;  // 输出行程上限 [%] / Output travel ceiling [%]
    DL_DC2_ONE  : LREAL := 1.0;    // 系数域界（|fD| 上限） [无量纲] / Factor domain bound
    DL_DC2_EPS  : LREAL := 0.0;    // 非有限差值判零基准 [-] / Non-finite difference zero base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 沿刷新 —— *)
_bNonFin := (fU1 <> fU1) OR ((fU1 - fU1) <> DL_DC2_EPS)
         OR (fU2 <> fU2) OR ((fU2 - fU2) <> DL_DC2_EPS);        // 主控输出非有限（R245） / Non-finite controller outputs
IF (ABS(fD12) > DL_DC2_ONE) OR (ABS(fD21) > DL_DC2_ONE)
   OR (fD12 <> fD12) OR ((fD12 - fD12) <> DL_DC2_EPS)
   OR (fD21 <> fD21) OR ((fD21 - fD21) <> DL_DC2_EPS) THEN
    _bCfgLatch := TRUE;                                         // 系数越域/非有限：锁存（R188 解除沿 = bReset 上升沿） / Factor out of domain: latch
END_IF
rtReset(CLK := bReset);                                         // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bCfgLatch := FALSE;                                        // 清组态非法锁存 / Clear cfg latch
END_IF

(* —— 段 2：解耦主算（直通条件三支：未使能 / 组态非法 / 输出非有限） —— *)
IF (NOT bEnable) OR _bCfgLatch OR _bNonFin THEN
    fU1Eff := fU1;                                              // 直通：回路 1 原值（头注释②④声明） / Bypass loop 1
    fU2Eff := fU2;                                              // 直通：回路 2 原值 / Bypass loop 2
ELSE
    _fRaw1 := fU1 + fD21 * fU2;                                 // 静态解耦注入：u2 对回路 1 的影响补偿 / Static decoupling injection onto loop 1
    _fRaw2 := fU2 + fD12 * fU1;                                 // 静态解耦注入：u1 对回路 2 的影响补偿 / Static decoupling injection onto loop 2
    IF _fRaw1 > DL_DC2_UMAX THEN
        fU1Eff := DL_DC2_UMAX;                                  // 回路 1 上钳 100% / Clamp loop 1 high
    ELSIF _fRaw1 < DL_DC2_UMIN THEN
        fU1Eff := DL_DC2_UMIN;                                  // 回路 1 下钳 0% / Clamp loop 1 low
    ELSE
        fU1Eff := _fRaw1;                                       // 行程内接受 / In-travel accept
    END_IF
    IF _fRaw2 > DL_DC2_UMAX THEN
        fU2Eff := DL_DC2_UMAX;                                  // 回路 2 上钳 / Clamp loop 2 high
    ELSIF _fRaw2 < DL_DC2_UMIN THEN
        fU2Eff := DL_DC2_UMIN;                                  // 回路 2 下钳 / Clamp loop 2 low
    ELSE
        fU2Eff := _fRaw2;                                       // 行程内接受 / In-travel accept
    END_IF
END_IF

(* —— 段 3：出口单点映射（名实双出口同源，R191） —— *)
bEnabled := bEnable AND (NOT _bCfgLatch);                       // 生效指示 = 使能 ∧ 组态合法 / Active = enabled and config valid
bCfgBad  := _bCfgLatch;                                         // 组态非法出口 / Cfg fault outlet
bError   := _bCfgLatch;                                         // 故障标志与 bCfgBad 同源 / Error flag same source

END_FUNCTION_BLOCK
