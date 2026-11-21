// ==============================================================================
// 组件名 Component  : FC_DL_ArrCopySeg
// 分类   Category   : DL_Base
// 前缀   Naming     : FC_DL_ ｜ b/n/i/f 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 低
// 功能   Purpose    : 定长 LREAL 数组段拷贝：把源数组 [iSrcFrom ..] 起的
//                      nCnt 个元素拷到目标数组 [iDstFrom ..] 起；nCnt <= 0
//                      零拷贝合法；源 / 目标越界自动截断 nCnt，bTrunc 置位
//                      报告截断，nCopied 反映实际拷贝数（bValid 保持 TRUE）。
//                      供缓冲搬运 / 窗段平移 / 队列重组类调用方使用。
// 开源溯源 Origin    : 西门子 LGF 分类语义借鉴，clean-room 重写（LGF
//                      Data Handling「定长缓冲搬运（无动态内存）」分类学
//                      口径借鉴，只借骨不抄肉，实现零代码复制）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6.4 FOR 遍历与数组语义
// 平台   Platform   : 纯 IEC 61131-3（FOR / 数组 / 比较），三平台通用
// 依赖   Depends    : 无（零委托、零库件）
// 分工声明 Split     : FC_DL_ArrFillEx（常数填充）与本件互引；本件为数组段
//                      搬运（源是数组），彼件为常数填充（源是标量），语义
//                      正交（R216）。与 FC_DL_ArraySliceCopy（DL_MathData）
//                      分工：彼件从下标 0 起承接且对越域判故障早退，本件
//                      支持任意目标起点且对越界截断续行（bTrunc 报告），
//                      口径不同勿混用（R216）。
// 归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 零拷贝闸：nCnt <= 0 → nCopied = 0、bValid = TRUE、数组零写回
//      （合法语义不是故障）；
//   二 截断闸（逐项点名，R272）：iSrcFrom < 0 / iDstFrom < 0 钳 0 置
//      bTrunc；nCnt 超过源余量（255 - iSrcC）或目标余量（255 - iDstC）
//      时截到较小余量并置 bTrunc；起点越出容量（> 255）时余量为负、
//      nUse <= 0 → 零拷贝 + bTrunc（bValid 保持 TRUE，截断是信息级）；
//   三 重叠自检（中转缓冲两段式）：先把源段整段读入局部 afStaging，再
//      整段写回目标——arrSrc 与 arrDst 为同一数组且区间重叠的别名调用
//      也不产生撕裂 / 串写（快照语义，真实可达：调用方传同一数组做段
//      平移）；此为机制性防重叠，非永假防御；
//   四 拷贝序：读侧 / 写侧循环上界由段 2 截断闸证明 <= 255，下标越界
//      不可达；
//   五 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
//   六 无除法、无浮点比较；无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0001_0745【信息级】段越界自动截断（起点钳位或 nCnt 截到余量，
//                bTrunc = TRUE、bValid = TRUE、nCopied 反映实际拷贝数）
//   注：本件引脚契约按任务定稿无独立 eErr 出口，截断语义经 bTrunc /
//   nCopied 双通道表达；零拷贝与截断为零的出口同形（bTrunc 区分），
//   不另设码（R90 反证句）。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 源 [1..5]、iSrcFrom = 1、iDstFrom = 10、nCnt = 3 → 目标槽 10..12
//      为 [2,3,4]、nCopied = 3、bTrunc = FALSE
//   V2 nCnt = 0 / 负数 → nCopied = 0、bValid = TRUE、bTrunc = FALSE
//   V3 iSrcFrom = 250、nCnt = 10 → 截到 6、bTrunc = TRUE
//   V4 iSrcFrom = -3 → 钳 0 续拷、bTrunc = TRUE
//   V5 iDstFrom = 300 → nCopied = 0、bTrunc = TRUE
//   V6 别名调用：同一数组段平移 → 中转缓冲两段式无撕裂（V1 断言不变）
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 1 · 序号 4，LGF Data Handling 补口）
// ==============================================================================
FUNCTION FC_DL_ArrCopySeg : BOOL
VAR_IN_OUT
    arrSrc : ARRAY[0..255] OF LREAL; // 源数组 [工程单位]，允许与目标同数组（别名调用走中转缓冲）/ the source array, may alias the target
    arrDst : ARRAY[0..255] OF LREAL; // 目标数组 [工程单位]，从 iDstFrom 起承接 / the target array receiving from iDstFrom
END_VAR
VAR_INPUT
    iSrcFrom : INT := 0;         // 源段起点 [下标]，负值钳 0 / the source start index, negative clamped
    iDstFrom : INT := 0;         // 目标段起点 [下标]，负值钳 0 / the target start index, negative clamped
    nCnt     : INT := 0;         // 请求拷贝数 [个]，<= 0 零拷贝合法 / the requested count, zero or less is a legal no op
END_VAR
VAR_OUTPUT
    nCopied : INT;               // 实际拷贝数 [个] / the actually copied count
    bValid  : BOOL;              // 结果可用 [-]，本件恒 TRUE（截断为信息级）/ the validity flag, always true here
    bTrunc  : BOOL;              // 截断报告 [-]，TRUE = 发生钳位或截断 / the truncation flag
END_VAR
VAR
    iSrcC     : INT;             // 钳位后的源起点 [下标] / the clamped source start
    iDstC     : INT;             // 钳位后的目标起点 [下标] / the clamped target start
    nAvail    : INT;             // 源 / 目标余量的较小值 [个] / the smaller of the two remainders
    nUse      : INT;             // 实际拷贝数暂存 [个] / the staged copy count
    k         : INT;             // 遍历索引 [下标] / the traversal index
    afStaging : ARRAY[0..255] OF LREAL; // 中转缓冲 [工程单位]，两段式防重叠撕裂 / the staging buffer for the overlap safe two stage copy
END_VAR
VAR CONSTANT
    DL_ACP_NMAX : INT := 255;    // 数组容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_ACP_ZERO : INT := 0;      // 整型零常量 [个] / the integer zero constant
END_VAR

// 段 1｜返回值与全部出口预置 + 中转缓冲清零（R45 四段式第一段）/ segment 1, the preset and the staging clear
FC_DL_ArrCopySeg := FALSE;       // 返回值预置假 / preset the return false
nCopied := DL_ACP_ZERO;          // 拷贝数预置零 [个] / preset the copied count zero
bValid  := TRUE;                 // 有效标志预置真（截断为信息级口径）/ preset valid
bTrunc  := FALSE;                // 截断标志预置假 / preset the truncation flag false
FOR k := DL_ACP_ZERO TO DL_ACP_NMAX DO // 中转缓冲全量预清零 / preset the staging buffer zero
    afStaging[k] := 0.0;         // 缓冲槽位显式清零 [工程单位] / clear the staging slot explicitly
END_FOR

// 段 2｜截断闸第一段：负起点钳 0 置 bTrunc（边界二，逐项点名）/ segment 2, the clamp of negative starts
iSrcC := iSrcFrom;               // 源起点接管 / take the source start
iDstC := iDstFrom;               // 目标起点接管 / take the target start
IF iSrcC < DL_ACP_ZERO THEN      // 源起点下越界 / the source start below the domain
    iSrcC := DL_ACP_ZERO;        // 钳 0 续拷（信息级 0745）/ clamp to zero and keep copying
    bTrunc := TRUE;              // 置截断报告 / raise the truncation flag
END_IF
IF iDstC < DL_ACP_ZERO THEN      // 目标起点下越界 / the target start below the domain
    iDstC := DL_ACP_ZERO;        // 钳 0 续拷（信息级 0745）/ clamp to zero and keep copying
    bTrunc := TRUE;              // 置截断报告 / raise the truncation flag
END_IF

// 段 3｜零拷贝闸（边界一：nCnt <= 0 合法，数组零写回）/ segment 3, the zero copy gate
IF nCnt <= DL_ACP_ZERO THEN      // 请求拷贝数非正 / the requested count non positive
    nCopied := DL_ACP_ZERO;      // 零拷贝 [个] / a zero copy
    FC_DL_ArrCopySeg := TRUE;    // 合法返回 / return success
    RETURN;                      // 早退，数组零写回 / early return untouched
END_IF

// 段 4｜截断闸第二段：nCnt 截到源 / 目标余量较小值（边界二）/ segment 4, the truncation to the smaller remainder
nAvail := DL_ACP_NMAX - iSrcC;   // 源余量 [个] / the source remainder
IF (DL_ACP_NMAX - iDstC) < nAvail THEN // 目标余量更小 / the target remainder smaller
    nAvail := DL_ACP_NMAX - iDstC; // 取目标余量 [个] / take the target remainder
END_IF
nUse := nCnt;                    // 请求拷贝数接管 [个] / take the requested count
IF iSrcC > DL_ACP_NMAX THEN      // 源起点越出容量 / the source start beyond the capacity
    bTrunc := TRUE;              // 置截断报告（余量为负，落零拷贝）/ raise the truncation flag
END_IF
IF iDstC > DL_ACP_NMAX THEN      // 目标起点越出容量 / the target start beyond the capacity
    bTrunc := TRUE;              // 置截断报告 / raise the truncation flag
END_IF
IF nUse > nAvail THEN            // 请求量超余量 / the request above the remainder
    nUse := nAvail;              // 截到余量（信息级 0745）/ truncate to the remainder
    bTrunc := TRUE;              // 置截断报告 / raise the truncation flag
END_IF
IF nUse <= DL_ACP_ZERO THEN      // 截断后为非正（起点越出容量路径）/ the truncated count non positive
    nCopied := DL_ACP_ZERO;      // 零拷贝 [个] / a zero copy
    FC_DL_ArrCopySeg := TRUE;    // 合法返回 / return success
    RETURN;                      // 早退，数组零写回 / early return untouched
END_IF

// 段 5｜中转缓冲承接源段（边界三：两段式第一段，读侧快照）/ segment 5, the staging takes the source segment
FOR k := DL_ACP_ZERO TO nUse - 1 DO // 有界遍历（上界 = nUse - 1 <= 254 已证）/ the bounded traversal
    afStaging[k] := arrSrc[iSrcC + k]; // 源段读入缓冲 [工程单位]（下标 <= 255 已证）/ read the source into the staging
END_FOR

// 段 6｜缓冲写回目标段（边界三：两段式第二段，写侧顺序落位）/ segment 6, the staging lands on the target
FOR k := DL_ACP_ZERO TO nUse - 1 DO // 有界遍历（上界同段 5 已证）/ the bounded traversal
    arrDst[iDstC + k] := afStaging[k]; // 缓冲整段写回目标 [工程单位]（下标 <= 255 已证）/ land the staging onto the target
END_FOR

// 段 7｜统一出口 / segment 7, the unified outlet
nCopied := nUse;                 // 实拷贝数出口 [个] / the copied count outlet
FC_DL_ArrCopySeg := TRUE;        // 返回成功 / return success
END_FUNCTION
