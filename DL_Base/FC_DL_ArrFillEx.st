// ==============================================================================
// 组件名 Component  : FC_DL_ArrFillEx
// 分类   Category   : DL_Base
// 前缀   Naming     : FC_DL_ ｜ b/n/i/f 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 低
// 功能   Purpose    : 定长 LREAL 数组区间填充：把 [iFrom, iTo] 闭区间各槽位
//                      写为 fVal；区间越界自动钳位（iFrom < 0 钳 0、
//                      iTo > 255 钳 255），iFrom > iTo 零填充合法返回；
//                      bFillNaN = FALSE 且 fVal 非有限时拒绝填充
//                      （bValid = FALSE，数组零写回）。供清屏 / 预置 /
//                      坏点填充类调用方使用。
// 开源溯源 Origin    : 西门子 LGF 分类语义借鉴，clean-room 重写（LGF
//                      Data Handling「定长缓冲批量写」分类学口径借鉴，只借
//                      骨不抄肉，实现零代码复制）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6.4 FOR 遍历与数组语义
// 平台   Platform   : 纯 IEC 61131-3（FOR / 数组 / 比较），三平台通用
// 依赖   Depends    : 无（零委托、零库件）
// 分工声明 Split     : FC_DL_ArrCopySeg（段拷贝）与本件互引；本件为常数填充
//                      （源是标量），彼件为数组段搬运（源是数组），语义正交
//                      （R216）。
// 归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 区间钳位闸（逐项点名，R272）：iFrom < 0 钳 0、iTo > 255 钳 255，
//      钳位后照常填充（信息级语义，bValid 保持 TRUE）；iFrom / iTo 反向
//      （含钳位后反向）→ 零填充合法返回（nFilled = 0、bValid = TRUE）；
//   二 非有限闸：fVal 为 NaN（自反判 x <> x）或 ±Inf（差值自反判
//      (x - x) <> (x - x)）且 bFillNaN = FALSE → bValid = FALSE、
//      nFilled = 0、数组零写回早退（R272 非有限防护）；bFillNaN = TRUE
//      时允许显式填充 NaN / Inf（调用方自担，bValid 保持 TRUE）；
//   三 填充序：FOR 闭区间顺序写，上界 iToC <= 255、下界 iFromC >= 0 已证
//      （钳位闸证明），下标越界不可达；
//   四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
//   五 无除法；无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0001_0743【信息级】区间越界已钳位续填（iFrom 钳 0 / iTo 钳 255，
//                bValid = TRUE，nFilled 反映实际填充数）
//   16#0001_0744【故障级】fVal 非有限且 bFillNaN = FALSE，拒绝填充
//                （bValid = FALSE、nFilled = 0、数组零写回）
//   注：本件引脚契约按任务定稿无独立 eErr 出口，上述码位为文档级语义，
//   经 bValid / nFilled 通道表达；钳位续填与正常填充出口同形（仅区间
//   收窄），无独立输出通道可承载，不另设出口位（R90 反证句）。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 iFrom = 10、iTo = 20、fVal = 5.0 → 槽位 10..20 全为 5.0、nFilled = 11
//   V2 iFrom = -5 → 钳 0 续填；iTo = 300 → 钳 255 续填
//   V3 iFrom > iTo → nFilled = 0、bValid = TRUE、数组原样
//   V4 fVal = NaN、bFillNaN = FALSE → bValid = FALSE、零写回
//   V5 fVal = NaN、bFillNaN = TRUE → 填入 NaN、bValid = TRUE
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 1 · 序号 3，LGF Data Handling 补口）
// ==============================================================================
FUNCTION FC_DL_ArrFillEx : BOOL
VAR_IN_OUT
    arrDst : ARRAY[0..255] OF LREAL; // 目标数组 [工程单位]，闭区间填充 / the target array filled over the closed range
END_VAR
VAR_INPUT
    iFrom    : INT;              // 填充起点 [下标]，闭区间含端点 / the fill start index, inclusive
    iTo      : INT;              // 填充终点 [下标]，闭区间含端点 / the fill end index, inclusive
    fVal     : LREAL;            // 填充值 [工程单位] / the fill value
    bFillNaN : BOOL := FALSE;    // 允许非有限填充开关 [-]，TRUE 时允许填 NaN / Inf / the non finite fill switch
END_VAR
VAR_OUTPUT
    nFilled : INT;               // 实际填充槽位数 [个] / the actually filled slot count
    bValid  : BOOL;              // 结果可用 [-]，拒绝填充为 FALSE / the result usable flag
END_VAR
VAR
    iFromC     : INT;            // 钳位后的填充起点 [下标] / the clamped fill start
    iToC       : INT;            // 钳位后的填充终点 [下标] / the clamped fill end
    k          : INT;            // 遍历索引 [下标] / the traversal index
    xNonFinite : BOOL;           // fVal 非有限标志 [-] / the non finite flag of fVal
END_VAR
VAR CONSTANT
    DL_AFE_NMAX : INT := 255;    // 数组容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_AFE_ZERO : INT := 0;      // 整型零常量 [个] / the integer zero constant
END_VAR

// 段 1｜返回值与全部出口预置（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_ArrFillEx := FALSE;        // 返回值预置假 / preset the return false
nFilled := DL_AFE_ZERO;          // 填充数预置零 [个] / preset the filled count zero
bValid  := TRUE;                 // 有效标志预置真（零填充合法口径）/ preset valid, a legal zero fill

// 段 2｜区间钳位闸（边界一：iFrom 钳 0 / iTo 钳 255，逐项点名）/ segment 2, the range clamp gate
iFromC := iFrom;                 // 起点接管 / take the start
iToC   := iTo;                   // 终点接管 / take the end
IF iFromC < DL_AFE_ZERO THEN     // 起点下越界 / the start below the domain
    iFromC := DL_AFE_ZERO;       // 钳 0 续填（信息级 0743）/ clamp to zero and keep filling
END_IF
IF iToC > DL_AFE_NMAX THEN       // 终点上越界 / the end above the domain
    iToC := DL_AFE_NMAX;         // 钳 255 续填（信息级 0743）/ clamp to the cap and keep filling
END_IF

// 段 3｜反向区间闸：零填充合法返回（边界一）/ segment 3, the reversed range gate, a legal zero fill
IF iFromC > iToC THEN            // 起点 > 终点（含钳位后反向）/ the start above the end
    nFilled := DL_AFE_ZERO;      // 零填充 [个] / a zero fill
    FC_DL_ArrFillEx := TRUE;     // 合法返回 / return success
    RETURN;                      // 早退，数组零写回 / early return untouched
END_IF

// 段 4｜非有限闸（边界二：NaN 自反判 + Inf 差值自反判，R272）/ segment 4, the non finite gate
xNonFinite := (fVal <> fVal) OR ((fVal - fVal) <> 0.0); // NaN 或 ±Inf / NaN or infinity
IF (NOT bFillNaN) AND xNonFinite THEN // 未允许且非有限 / not allowed and non finite
    bValid  := FALSE;            // 拒绝填充（故障级 0744）/ refuse the fill
    nFilled := DL_AFE_ZERO;      // 填充数归零 [个] / zero the count
    FC_DL_ArrFillEx := FALSE;    // 返回失败 / return failure
    RETURN;                      // 早退，数组零写回 / early return untouched
END_IF

// 段 5｜闭区间顺序填充（边界三：上界已证 <= 255、下界已证 >= 0）/ segment 5, the ordered closed range fill
FOR k := iFromC TO iToC DO       // 有界遍历 / the bounded traversal
    arrDst[k] := fVal;           // 槽位写入 [工程单位] / write the slot
END_FOR

// 段 6｜统一出口 / segment 6, the unified outlet
nFilled := iToC - iFromC + 1;    // 实际填充数 [个] / the actually filled count
FC_DL_ArrFillEx := TRUE;         // 返回成功 / return success
END_FUNCTION
