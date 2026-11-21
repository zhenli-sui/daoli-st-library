(*
  ==================================================================
  组件名 Component  : FC_DL_ArraySliceCopy
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0666（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : 数值数组段拷贝：把源数组的 [iStart, iStart + nLen - 1]
                      段整段拷入目标数组首段起（目标从下标 0 起承接），LREAL
                      主类型；供缓冲搬运、窗段提取、队列重组类调用方使用。
  开源溯源 Origin    : 西门子 LGF V5.3.0 Data Handling 组「定长缓冲搬运（无
                      动态内存）」分类学口径借鉴（R12 结论沿用，只借骨不抄
                      肉）；实现 clean-room，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.4 FOR 遍历与数组语义
  平台   Platform   : 纯 IEC 61131-3（FOR / 数组 / 比较），三平台通用
  依赖   Depends    : 无（零委托、零库件）
  分工声明 Split     : FC_DL_ArrayFindValue（值 → 下标查找）与本件互引；
                      本件只做段搬运不改序、不查值；数组裁剪压缩类需求由
                      调用方以本件 + 移位组合（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 入参域闸（逐项点名，R272）：nSrcCount < 1 或 > 256 /
                         iStart < 0 或 > nSrcCount - 1 / nLen < 1 或
                         nLen > nSrcCount - iStart（源溢出）或 nLen > 256
                         （目标容量溢出）→ 故障级 0666 + nCopied = 0 +
                         bValid = FALSE + 早退（禁任何写回，目标数组保持
                         原样）；四类越域出口组合完全相同，合并一码
                         （反证句见码表）；
                      二 重叠自检（中转缓冲两段式）：本件先把源段整段读入
                         局部中转缓冲，再整段写回目标——afSrc 与 afDst 为
                         同一数组且区间重叠的别名调用也不产生撕裂 / 串写
                         （快照语义，真实可达路径：调用方传同一数组做
                         前移压缩）；此为机制性防重叠，非永假防御；
                      三 拷贝序：中转缓冲承接后按下标 0 起顺序写回，循环
                         上界由段 1 域闸证明 ≤ 256，越界不可达；
                      四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      五 无除法；无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0001_0666【故障级】入参越域：nSrcCount / iStart / nLen 任一越出
                         合法域（源溢出或目标容量溢出，禁任何写回）
  码位反证 Note     :
    0666 合并四类越域（计数 / 起点 / 源溢出 / 容量溢出）的理由：四场景出口
    组合完全相同（nCopied = 0、bValid = FALSE、目标数组零写回），三组以内
    输出无法唯一还原该场景，按 R90 不另立码。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 源 [1,2,3,4,5]、iStart = 2、nLen = 3 → 目标 [3,4,5]、nCopied = 3
    V2 iStart = 0、nLen = nSrcCount → 全量拷贝
    V3 nLen = nSrcCount - iStart + 1（源溢出）→ 码 0666 + 早退、目标原样
    V4 iStart = nSrcCount（起点越界）→ 同码早退
    V5 nSrcCount = 0 / 257 → 同码早退
    V6 别名调用：afSrc = afDst 同数组、源段与目标首段重叠 → 中转缓冲两段式
       无撕裂（V1 结果断言不变）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 2 · 序号 5，LGF Data Handling 段拷贝补口）
  ==================================================================
*)
FUNCTION FC_DL_ArraySliceCopy : BOOL
VAR_IN_OUT
    afSrc : ARRAY[0..255] OF LREAL; // 源数组 [工程单位]，允许与目标同数组（别名调用走中转缓冲）/ the source array, may alias the target, the staging buffer covers it
    afDst : ARRAY[0..255] OF LREAL; // 目标数组 [工程单位]，从下标 0 起承接 / the target array, receives from the index zero
END_VAR
VAR_INPUT
    nSrcCount: DINT := 0; // 源有效长度 [个]，合法域 1..256 / the source effective length, legal one to two hundred fifty six
    iStart   : DINT := 0; // 源段起点 [下标]，合法域 0..nSrcCount - 1 / the source segment start index
    nLen     : DINT := 0; // 拷贝长度 [个]，合法域 1..min(nSrcCount - iStart, 256) / the copy length
END_VAR
VAR_OUTPUT
    nCopied: DINT;  // 实际拷贝数 [个]，失败 = 0 / the copied count, zero on failure
    bValid : BOOL;  // 结果可用 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    k         : DINT := 0;               // 遍历索引 [下标] / the traversal index
    afStaging : ARRAY[0..255] OF LREAL;  // 中转缓冲 [工程单位]，两段式防重叠撕裂 / the staging buffer for the overlap safe two stage copy
VAR CONSTANT
    DL_ASC_NMAX : DINT := 256; // 数组容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_ASC_ONE  : DINT := 1;   // 整型一常量 [个] / the integer one constant
    DL_ASC_ZERO : DINT := 0;   // 整型零常量 [个] / the integer zero constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_ArraySliceCopy := FALSE; // 返回值预置假 / preset the return false
nCopied := DL_ASC_ZERO; // 拷贝数预置零 [个] / preset the copied count zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
FOR k := DL_ASC_ZERO TO DL_ASC_NMAX - DL_ASC_ONE DO // 中转缓冲预清零（有界遍历全容量）/ preset the staging buffer zero over the full capacity
    afStaging[k] := 0.0; // 缓冲槽位显式清零 [工程单位] / clear the staging slot explicitly
END_FOR

// 段 2｜入参域闸（边界一：四类越域逐项点名，禁任何写回）/ segment 2, the input domain gate, no writeback on any violation
IF (nSrcCount < DL_ASC_ONE) OR (nSrcCount > DL_ASC_NMAX)
OR (iStart < DL_ASC_ZERO) OR (iStart > nSrcCount - DL_ASC_ONE)
OR (nLen < DL_ASC_ONE) OR (nLen > nSrcCount - iStart) OR (nLen > DL_ASC_NMAX) THEN // 计数 / 起点 / 长度任一越域 / the count or the start or the length is out of the domain
    eErr := 16#0001_0666; // 故障级：入参越域（四场景出口同形合并一码，R90）/ fault grade under the merged code
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，目标数组零写回 / early return, the target untouched
END_IF

// 段 3｜中转缓冲承接源段（边界二：两段式第一段，读侧快照）/ segment 3, the staging buffer takes the source segment
FOR k := DL_ASC_ZERO TO nLen - DL_ASC_ONE DO // 有界遍历（上界已证 ≤ 256 且 ≤ 源余量）/ the bounded traversal with a proven ceiling
    afStaging[k] := afSrc[iStart + k]; // 源段读入缓冲 [工程单位]（快照语义）/ read the source segment into the staging buffer
END_FOR

// 段 4｜缓冲写回目标（边界二：两段式第二段，写侧顺序落位）/ segment 4, the staging buffer lands on the target
FOR k := DL_ASC_ZERO TO nLen - DL_ASC_ONE DO // 有界遍历（上界同段 3 已证）/ the bounded traversal with the same proven ceiling
    afDst[k] := afStaging[k]; // 缓冲整段写回目标首段 [工程单位] / land the staging segment onto the target head
END_FOR

// 段 5｜统一出口 / segment 5, the unified outlet
nCopied := nLen; // 实拷贝数出口 [个] / the copied count outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_ArraySliceCopy := TRUE; // 返回成功 / return success
END_FUNCTION
