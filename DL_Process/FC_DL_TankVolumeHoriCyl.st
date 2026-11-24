// ==============================================================================
// 组件名 Component  : FC_DL_TankVolumeHoriCyl
// 分类   Category   : DL_Process
// 前缀   Naming     : FC_DL_ ｜ b/f 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 中
// 功能   Purpose    : 卧式圆柱罐液位 - 体积几何解析换算：弦高 → 弓形面积
//                      → 体积（fVol = L * (r²*acos((r-h)/r) − (r−h)*
//                      sqrt(max(0, 2rh − h²)))），h = fLevel 钳位 [0, 2r]；
//                      百分比出口按满罐体积归一。纵坡参数 fTiltDeg 本版
//                      按平面近似支持（> 0 时置 bApprox 提示近似）。
// 文件互引声明 Split : FB_DL_TankLevelStrapping（DL_Process）为查表标定法
//                      （折点表 + 标定核对），本件为几何解析法（公式直算，
//                      零折点依赖），两法勿混用——有标定表用查表件，无表
//                      用本件（R216 双向互引）。
// 开源溯源 Origin    : 道莅原创（弓形面积为公开几何公式，本实现 clean-room，
//                      未复制任何源码行）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6.2 函数语义；ACOS / SQRT 为 IEC
//                      标准数学函数；弓形面积公开几何公式（借定义，不抄实现）
// 平台   Platform   : 纯 IEC 61131-3（LREAL 四则 / ACOS / SQRT），三平台通用
// 依赖   Depends    : 无（零委托、零库件；ACOS / SQRT 为 IEC 标准函数）
// 归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 组态 / 输入闸（逐项点名，R272）：fDiam <= 0、fLength <= 0、
//      fDiam / fLength / fLevel 任一非有限（NaN 自反判 + Inf 差值自反判 +
//      幅值 1e30 上界）→ bValid = FALSE、双出口归零早退（故障级 303A）；
//   二 液位钳位：h 钳 [0, 2r]（负值钳 0、超高罐顶钳 2r，安全侧归一，
//      信息级 303C 文档语义——本件无 eErr 出口，钳位出口与正常出口
//      同形无独立通道，不另设出口位，R90 反证句）；
//   三 acos 定义域防护：(r - h) / r 钳 [-1, 1]（边界二钳位后 h/r 在
//      [0, 1]，q = 1 - h/r 在 [0, 1]，钳位为防御性双保险，防浮点边缘
//      越域）；除法分母 r > 0 已由组态闸证明；
//   四 被开方数 max(0, 2rh − h²)：h 在 [0, 2r] 已证非负，再叠 max(0,·)
//      双保险，SQRT 入参恒非负；
//   五 百分比分母防零：fVfull = PI*r²*L，由组态闸（fDiam > 0 → r > 0、
//      fLength > 0）证明 fVfull > 0，除法安全（反证句写死）；
//   六 纵坡近似口径：fTiltDeg > 0 → bApprox = TRUE（平面近似，体积按
//      平罐公式给出）；fTiltDeg 非有限 → 同置 bApprox = TRUE 并按 0
//      处理（信息级 303B）；
//   七 结果非有限防御：体积 / 百分比出口算后复检非有限（NaN / Inf /
//      幅值上界），越限即 bValid = FALSE、双出口归零（R273 连续量出口
//      非有限防护）；
//   八 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
//   九 除法仅两处（h/r 与 fVolM3/fVfull），分母已证非零；无全局、
//      无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0006_303A【故障级】组态 / 输入非法（fDiam / fLength 域非法或任一
//                引脚非有限），bValid = FALSE、双出口归零早退
//   16#0006_303B【信息级】纵坡非零（或非有限按 0 处理），平面近似口径
//                （bApprox = TRUE 通道）
//   16#0006_303C【信息级】液位越界已钳位 [0, 2r]（静默安全侧归一，
//                文档级语义，无独立出口通道）
//   注：本件引脚契约按任务定稿无独立 eErr 出口，故障语义经 bValid /
//   bApprox / 双出口组合表达。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 r=1、L=2、h=0 → 体积 0；h=2r → 满罐 PI*r²*L ≈ 6.283 m³、fPct = 100
//   V2 r=1、L=2、h=1（半罐）→ 弓形 = 半圆面积 PI/2 → 体积 ≈ 3.1416、fPct = 50
//   V3 fLevel = -0.5 → 钳 0；fLevel = 5（> 2r）→ 钳 2r
//   V4 fDiam = 0 / 负 → bValid = FALSE；fLevel = NaN → bValid = FALSE
//   V5 fTiltDeg = 3 → bApprox = TRUE（体积仍按平面近似给出）
//   V6 fTiltDeg = NaN → bApprox = TRUE、按 0 处理
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 3 · 序号 8）
// ==============================================================================
FUNCTION FC_DL_TankVolumeHoriCyl : BOOL
VAR_INPUT
    fLevel   : LREAL;            // 液位高度 [m]，罐底为 0 / the liquid level, the tank bottom is zero
    fDiam    : LREAL;            // 罐内径 [m]，须 > 0 / the inner diameter, above zero
    fLength  : LREAL;            // 罐筒体长度 [m]，须 > 0 / the shell length, above zero
    fTiltDeg : LREAL := 0.0;     // 纵坡 [deg]，本版平面近似，> 0 置 bApprox / the longitudinal tilt, plane approximation
END_VAR
VAR_OUTPUT
    fVolM3  : LREAL;             // 折算体积 [m³]，无效时 0.0 / the converted volume, zero when invalid
    fPct    : LREAL;             // 体积百分比 [%]，按满罐归一 / the volume percent of the full tank
    bValid  : BOOL;              // 结果可用 [-] / the result usable flag
    bApprox : BOOL;              // 近似口径提示 [-]，纵坡非零 / the approximation flag, a nonzero tilt
END_VAR
VAR
    r         : LREAL;           // 罐半径 [m] / the tank radius
    h         : LREAL;           // 钳位后弦高 [m] / the clamped chord height
    q         : LREAL;           // acos 入参（(r-h)/r）[-] / the acos argument
    fUnder    : LREAL;           // 被开方数 2rh − h² [m²] / the radicand
    fSegArea  : LREAL;           // 弓形截面积 [m²] / the circular segment area
    fVfull    : LREAL;           // 满罐体积 [m³] / the full tank volume
    bTiltBad  : BOOL;            // 纵坡非有限标志 [-] / the tilt fault flag
END_VAR
VAR CONSTANT
    DL_TVC_PI   : LREAL := 3.14159265358979; // 圆周率 [-] / the pi constant
    DL_TVC_FMAX : LREAL := 1.0E30;           // 非有限筛查幅值上限 [m] / the finiteness screening cap
END_VAR

// 段 1｜返回值与全部出口预置（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_TankVolumeHoriCyl := FALSE; // 返回值预置假 / preset the return false
fVolM3  := 0.0;                  // 体积出口预置零 [m³] / preset the volume zero
fPct    := 0.0;                  // 百分比出口预置零 [%] / preset the percent zero
bValid  := FALSE;                // 有效标志预置假 / preset the validity false
bApprox := FALSE;                // 近似提示预置假 / preset the approximation flag false

// 段 2｜组态 / 输入闸（边界一：域 + 非有限逐项点名，R272）/ segment 2, the configuration and input gate
IF (fDiam <= 0.0) OR (fLength <= 0.0)                             // 几何域非法 / an illegal geometry
OR (fLevel <> fLevel) OR ((fLevel - fLevel) <> 0.0) OR (ABS(fLevel) > DL_TVC_FMAX)   // fLevel 非有限 / fLevel non finite
OR (fDiam <> fDiam) OR ((fDiam - fDiam) <> 0.0) OR (ABS(fDiam) > DL_TVC_FMAX)        // fDiam 非有限 / fDiam non finite
OR (fLength <> fLength) OR ((fLength - fLength) <> 0.0) OR (ABS(fLength) > DL_TVC_FMAX) THEN // fLength 非有限 / fLength non finite
    fVolM3 := 0.0;               // 体积归零 [m³] / zero the volume
    fPct   := 0.0;               // 百分比归零 [%] / zero the percent
    bValid := FALSE;             // 故障级 303A：拒绝计算 / refuse the calculation
    RETURN;                      // 早退 / early return
END_IF

// 段 3｜纵坡近似口径（边界六：> 0 置近似，非有限按 0 处理并置近似）/ segment 3, the tilt approximation flag
bTiltBad := (fTiltDeg <> fTiltDeg) OR ((fTiltDeg - fTiltDeg) <> 0.0) OR (ABS(fTiltDeg) > DL_TVC_FMAX); // 纵坡非有限 / the tilt non finite
IF (fTiltDeg > 0.0) OR bTiltBad THEN // 纵坡生效或无效 / the tilt active or invalid
    bApprox := TRUE;             // 信息级 303B：平面近似口径 / the approximation flag raised
END_IF

// 段 4｜半径与液位钳位（边界二：h 钳 [0, 2r]）/ segment 4, the radius and the level clamp
r := fDiam / 2.0;                // 半径 [m]（分母 2.0 为常量，零除面消除）/ the radius, a constant divisor
h := fLevel;                     // 弦高接管 [m] / take the level as the chord height
IF h < 0.0 THEN                  // 液位低于罐底 / the level under the bottom
    h := 0.0;                    // 钳 0（信息级 303C）/ clamp to zero
END_IF
IF h > (2.0 * r) THEN            // 液位超过罐顶 / the level over the top
    h := 2.0 * r;                // 钳 2r（信息级 303C）/ clamp to the full bore
END_IF

// 段 5｜弓形面积解析（边界三 / 四：acos 定义域钳位 + 被开方数非负双保险）/ segment 5, the segment area
q := 1.0 - (h / r);              // acos 入参 (r - h)/r（分母 r > 0 已由组态闸证明）/ the acos argument, the divisor proven above zero
IF q > 1.0 THEN                  // 上越域防御（浮点边缘双保险）/ an upper domain defense
    q := 1.0;                    // 钳回 1.0 / clamp to one
END_IF
IF q < -1.0 THEN                 // 下越域防御 / a lower domain defense
    q := -1.0;                   // 钳回 -1.0 / clamp to minus one
END_IF
fUnder := (2.0 * r * h) - (h * h); // 被开方数 2rh − h² [m²] / the radicand
IF fUnder < 0.0 THEN             // 浮点边缘微负防御（边界四）/ a tiny negative defense
    fUnder := 0.0;               // 钳 0（max(0, ·) 口径）/ clamp to zero
END_IF
fSegArea := (r * r * ACOS(q)) - ((r - h) * SQRT(fUnder)); // 弓形面积公式 [m²] / the segment area formula

// 段 6｜体积与百分比折算（边界五：分母 fVfull > 0 反证已写死）/ segment 6, the volume and the percent
fVolM3 := fLength * fSegArea;    // 体积 = 长度 × 弓形面积 [m³] / the volume as length times the segment area
fVfull := DL_TVC_PI * r * r * fLength; // 满罐体积 [m³]（r > 0 与 L > 0 已证）/ the full volume, proven above zero
fPct   := (fVolM3 / fVfull) * 100.0;   // 百分比 [%]（分母已证非零）/ the percent, the divisor proven

// 段 7｜结果非有限防御（边界七：连续量出口 R273 防护）/ segment 7, the result finiteness defense
IF (fVolM3 <> fVolM3) OR ((fVolM3 - fVolM3) <> 0.0) OR (ABS(fVolM3) > DL_TVC_FMAX) THEN // 体积非有限 / a non finite volume
    fVolM3 := 0.0;               // 体积归零 [m³] / zero the volume
    fPct   := 0.0;               // 百分比归零 [%] / zero the percent
    bValid := FALSE;             // 拒绝输出 / refuse the output
    RETURN;                      // 早退 / early return
END_IF

// 段 8｜统一出口 / segment 8, the unified outlet
bValid := TRUE;                  // 结果可用 / the result usable
FC_DL_TankVolumeHoriCyl := TRUE; // 返回成功 / return success
END_FUNCTION
