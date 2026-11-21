// ==============================================================================
// 组件名 Component  : FC_DL_AngleUnitConvert
// 分类   Category   : DL_MathData
// 前缀   Naming     : FC_DL_ ｜ b/f/e 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 低
// 功能   Purpose    : 角度单位换算（度 / 弧度 / 梯度）：统一转 rad 中间量
//                      再转目标单位，任意两单位直换（deg → grad 系数
//                      200/180 经 rad 中转自动成立）。非有限输入拒绝
//                      （bValid = FALSE、fOut = 0.0）。
// 开源溯源 Origin    : 道莅原创（角度单位定义为公开计量常识，本实现
//                      clean-room，未复制任何源码行；与 TempUnitConvert /
//                      PressUnitConvert / FlowUnitConvert 同族单位换算
//                      组织口径）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6.2 CASE 语义；角度单位换算公开
//                      计量定义（借定义，不抄实现）
// 平台   Platform   : 纯 IEC 61131-3（CASE / LREAL 四则），三平台通用
// 依赖   Depends    : 无（零委托、零库件；换算系数常量预乘，运行期零除法）
// 分工声明 Split     : FC_DL_AngleDiffWrap（角差归一）与 FC_DL_WrapAngleDeg
//                      （角度回绕）与本件互引；本件只做单位换算（不改
//                      角度主值、不回绕），归一 / 回绕语义归各自属主（R216）。
// 归属 Ownership     : E_DL_AngUnit 属主为本文件（全库唯一定义，R264）；
//                      引用件只引用不重声明。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 非有限闸：fVal 为 NaN（自反判 x <> x）或 ±Inf（差值自反判
//      (x - x) <> (x - x)）或幅值越 1e30 上界 → bValid = FALSE、
//      fOut = 0.0 早退（故障级 0749，R272 非有限防护）；
//   二 零除法面：四向系数全部预乘为常量（PI/180、180/PI、PI/200、
//      200/PI 编译期落定），运行期无除法（除零面结构性消除）；
//   三 枚举闸：eFrom / eTo 非法枚举值（CASE ELSE 兜底）→ bValid =
//      FALSE、fOut = 0.0 早退（与 0749 同形出口合并一码，R90 反证句：
//      现有输出组合不可区分两场景）；
//   四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
//   五 无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0001_0749【故障级】输入非有限或枚举非法（bValid = FALSE、
//                fOut = 0.0 早退）
//   注：本件引脚契约按任务定稿无独立 eErr 出口，故障语义经
//   bValid = FALSE + fOut = 0.0 组合表达。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 180 deg → rad = 3.14159265358979；V2 1 rad → deg = 57.2957795
//   V3 200 grad → rad = 3.14159265358979；V4 180 deg → grad = 200（200/180 系数）
//   V5 fVal = NaN → bValid = FALSE、fOut = 0.0
//   V6 eFrom 非法枚举 → bValid = FALSE、fOut = 0.0
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 2 · 序号 7）
// ==============================================================================
TYPE E_DL_AngUnit :
(
    eDeg  := 0, // 度 [deg]，一周 360 / degrees, 360 per turn
    eRad  := 1, // 弧度 [rad]，一周 2*PI / radians, two pi per turn
    eGrad := 2  // 梯度 [grad]，一周 400 / gradians, 400 per turn
);
END_TYPE

FUNCTION FC_DL_AngleUnitConvert : BOOL
VAR_INPUT
    fVal  : LREAL;               // 输入角值 [源单位] / the input angle in the source unit
    eFrom : E_DL_AngUnit;        // 源单位枚举 [单位] / the source unit
    eTo   : E_DL_AngUnit;        // 目标单位枚举 [单位] / the target unit
END_VAR
VAR_OUTPUT
    fOut   : LREAL;              // 输出角值 [目标单位]，无效时 0.0 / the output angle in the target unit, zero when invalid
    bValid : BOOL;               // 结果可用 [-]，非有限或枚举非法为 FALSE / the validity flag
END_VAR
VAR
    fRad : LREAL;                // 中间弧度量 [rad]（统一中转）/ the intermediate radian value
END_VAR
VAR CONSTANT
    DL_AUC_D2R  : LREAL := 0.0174532925199433;   // 度 → 弧度系数 [rad/deg]，PI/180 预乘 / the deg to rad factor, pi over one eighty
    DL_AUC_R2D  : LREAL := 57.2957795130823;     // 弧度 → 度系数 [deg/rad]，180/PI 预乘 / the rad to deg factor
    DL_AUC_G2R  : LREAL := 0.0157079632679490;   // 梯度 → 弧度系数 [rad/grad]，PI/200 预乘 / the grad to rad factor, pi over two hundred
    DL_AUC_R2G  : LREAL := 63.6619772367581;     // 弧度 → 梯度系数 [grad/rad]，200/PI 预乘 / the rad to grad factor
    DL_AUC_FMAX : LREAL := 1.0E30;               // 非有限筛查幅值上限 [源单位] / the finiteness screening cap
END_VAR

// 段 1｜返回值与全部出口预置（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_AngleUnitConvert := FALSE; // 返回值预置假 / preset the return false
fOut   := 0.0;                   // 输出预置零 [目标单位] / preset the output zero
bValid := FALSE;                 // 有效标志预置假 / preset the validity false
fRad   := 0.0;                   // 中间量预置零 [rad] / preset the intermediate zero

// 段 2｜非有限闸（边界一：NaN 自反判 + Inf 差值自反判 + 幅值上界，R272）/ segment 2, the non finite gate
IF (fVal <> fVal) OR ((fVal - fVal) <> 0.0) OR (ABS(fVal) > DL_AUC_FMAX) THEN // 输入非有限 / the input non finite
    fOut   := 0.0;               // 输出归零 [目标单位] / zero the output
    bValid := FALSE;             // 故障级 0749：拒绝换算 / refuse the conversion
    RETURN;                      // 早退 / early return
END_IF

// 段 3｜源单位归一到 rad（边界三：CASE 带 ELSE 兜底）/ segment 3, the source unit normalization to radians
CASE eFrom OF
    E_DL_AngUnit.eDeg:           // 度 → rad / degrees to radians
        fRad := fVal * DL_AUC_D2R; // 乘 PI/180 系数 [rad] / multiply the deg to rad factor
    E_DL_AngUnit.eRad:           // 弧度直通 / radians pass through
        fRad := fVal;            // 中转量即输入 [rad] / the intermediate is the input
    E_DL_AngUnit.eGrad:          // 梯度 → rad / gradians to radians
        fRad := fVal * DL_AUC_G2R; // 乘 PI/200 系数 [rad] / multiply the grad to rad factor
    ELSE                         // 非法枚举拦截（边界三）/ an illegal enumeration
        fOut   := 0.0;           // 输出归零 / zero the output
        bValid := FALSE;         // 故障级 0749 同形出口（R90 合并）/ the merged fault outlet
        RETURN;                  // 早退 / early return
END_CASE

// 段 4｜rad 转目标单位（边界三：CASE 带 ELSE 兜底）/ segment 4, the radians to the target unit
CASE eTo OF
    E_DL_AngUnit.eDeg:           // rad → 度 / radians to degrees
        fOut := fRad * DL_AUC_R2D; // 乘 180/PI 系数 [deg] / multiply the rad to deg factor
    E_DL_AngUnit.eRad:           // rad 直通 / radians pass through
        fOut := fRad;            // 输出即中转量 [rad] / the output is the intermediate
    E_DL_AngUnit.eGrad:          // rad → 梯度 / radians to gradians
        fOut := fRad * DL_AUC_R2G; // 乘 200/PI 系数（deg → grad 经此链自动得 200/180）[grad] / the rad to grad factor
    ELSE                         // 非法枚举拦截（边界三）/ an illegal enumeration
        fOut   := 0.0;           // 输出归零 / zero the output
        bValid := FALSE;         // 故障级 0749 同形出口（R90 合并）/ the merged fault outlet
        RETURN;                  // 早退 / early return
END_CASE

// 段 5｜统一出口 / segment 5, the unified outlet
bValid := TRUE;                  // 结果可用 / the result usable
FC_DL_AngleUnitConvert := TRUE;  // 返回成功 / return success
END_FUNCTION
