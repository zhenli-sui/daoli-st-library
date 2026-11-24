(*
  ==================================================================
  组件名 Component  : FC_DL_ArrayFindValue
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0662（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : LREAL 数组无序线性查找：返回目标值首 / 末命中下标与命中
                      计数三口径；未命中以 -1 哨兵表达，供值定位、重复检测、
                      抽检核对类调用方使用。
  开源溯源 Origin    : 西门子 LGF V5.3.0 Data Handling 组「数组搜索」子族
                      「无序线性查找 + 首 / 末 / 计数三口径」功能分类借鉴
                      （只借骨不抄肉）；实现 clean-room，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.1 比较 / FOR 遍历语义
  平台   Platform   : 纯 IEC 61131-3（FOR / ABS / 比较），三平台通用
  依赖   Depends    : 无（零委托、零库件）
  分工声明 Split     : FC_DL_ArraySliceCopy（段拷贝）/ FC_DL_ArrayFindExtreme
                      （极值定位）与本件互引；本件为「值 → 下标」正向查找，
                      极值族为「无目标值」扫描，职责不同（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 nCount 越域（< 1 或 > 256）判故障早退（禁空遍历与
                         越界下标）；fValue 非有限判故障早退（禁 NaN 参与
                         容差比较）——两场景出口组合完全相同（三个计数均
                         哨兵值 + bValid = FALSE），合并一码（反证句见码表）；
                      二 样本非有限口径（声明）：afData 中的非有限样本
                         （NaN / ±Inf）**跳过**，不计命中也不报错（数组整体
                         仍可部分有效）；目标值 fValue 非有限则不在此口径内，
                         按边界一判故障；
                      三 命中判定用容差：ABS(样本 - 目标) < 1.0E-6，禁用
                         = / <> 判等（浮点判等红线）；
                      四 未命中哨兵：nFirst = -1 且 nLast = -1 且 nHits = 0，
                         bValid = TRUE（查找本身成功，无命中不是故障）；
                      五 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      六 无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0001_0662【故障级】nCount 越域（< 1 或 > 256）或目标值 fValue 非有限
  码位反证 Note     :
    0662 合并「计数越域」与「目标值非有限」的理由：两场景出口组合完全相同
    （nFirst = -1、nLast = -1、nHits = 0、bValid = FALSE），三组以内输出无法
    唯一还原该场景，按 R90 不另立码；未命中（边界四）出口 bValid = TRUE，
    与 0662 可由 bValid 唯一区分，不并入。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 数组 [5, 7, 5, 9]、目标 5 → nFirst 0 / nLast 2 / nHits 2
    V2 目标 8 → 三哨兵 -1 / -1 / 0、bValid = TRUE（未命中不是故障）
    V3 含 NaN 样本 [NaN, 5]、目标 5 → NaN 跳过、nFirst 1 / nHits 1
    V4 nCount = 0 → 码 0662 + 早退（禁空遍历）
    V5 nCount = 257 → 同码早退；V6 目标 NaN → 同码早退
    V7 单样本命中 → nFirst = nLast = 0、nHits 1
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 1 · 序号 2，LGF Data Handling 数组搜索子族）
  ==================================================================
*)
FUNCTION FC_DL_ArrayFindValue : BOOL
VAR_IN_OUT
    afData : ARRAY[0..255] OF LREAL; // 数据序列 [工程单位]，只读 / the data series, read only
END_VAR
VAR_INPUT
    nCount : DINT := 0;    // 有效样本数入参 [个]，合法域 1..256 / the sample count, legal one to two hundred fifty six
    fValue : LREAL := 0.0; // 查找目标值 [工程单位]，必须有限 / the target value, must be finite
END_VAR
VAR_OUTPUT
    nFirst : DINT;  // 首个命中下标 [下标]，未命中 = -1 哨兵 / the first hit index, minus one when no hit
    nLast  : DINT;  // 末个命中下标 [下标]，未命中 = -1 哨兵 / the last hit index, minus one when no hit
    nHits  : DINT;  // 命中计数 [个] / the hit count
    bValid : BOOL;  // 结果可用 [-]（未命中也是可用结果）/ the result usable, a no hit is still usable
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    k : DINT := 0; // 遍历索引 [下标] / the traversal index
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_AFP_NMAX : DINT := 256;       // 数组容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_AFP_ONE  : DINT := 1;         // 整型一常量 [个] / the integer one constant
    DL_AFP_NOHIT: DINT := -1;        // 未命中哨兵 [下标] / the no hit sentinel index
    DL_AFP_ZERO : DINT := 0;         // 整型零常量 [个] / the integer zero constant
    DL_AFP_EQEPS: LREAL := 1.0E-6;   // 命中容差 [工程单位]，禁用 = / <> 判等 / the hit tolerance, plain equality operators are forbidden
END_VAR

// 段 1｜返回值与全部出口预置哨兵值（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_ArrayFindValue := FALSE; // 返回值预置假 / preset the return false
nFirst := DL_AFP_NOHIT; // 首命中下标预置哨兵 -1 [下标] / preset the first hit to the sentinel
nLast := DL_AFP_NOHIT; // 末命中下标预置哨兵 -1 [下标] / preset the last hit to the sentinel
nHits := DL_AFP_ZERO; // 命中计数预置零 [个] / preset the hit count zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false

// 段 2｜入参域闸（边界一，早退禁空遍历与 NaN 比较）/ segment 2, the input domain gate
IF (nCount < DL_AFP_ONE) OR (nCount > DL_AFP_NMAX)
OR (fValue <> fValue) OR ((fValue - fValue) <> (fValue - fValue)) THEN // 计数越域或目标值非有限 / the count is out of the domain or the target is not finite
    eErr := 16#0001_0662; // 故障级：入参越域或目标非有限（出口同形合并一码，R90）/ fault grade under the merged code
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 3｜线性查找遍历（边界二：非有限样本跳过；边界三：容差判等）/ segment 3, the linear search traversal
FOR k := DL_AFP_ZERO TO nCount - DL_AFP_ONE DO // 有界遍历（上界已证 ≤ 256）/ the bounded traversal with a proven ceiling
    IF (afData[k] = afData[k]) AND ((afData[k] - afData[k]) = (afData[k] - afData[k])) THEN // 有限样本才参与（非有限跳过口径）/ only a finite sample participates
        IF ABS(afData[k] - fValue) < DL_AFP_EQEPS THEN // 容差命中（浮点禁判等）/ a hit inside the tolerance
            nHits := nHits + DL_AFP_ONE; // 命中计数推进 [个] / advance the hit count
            IF nFirst = DL_AFP_NOHIT THEN // 首个命中（哨兵未动过才写）/ the first hit only when the sentinel is intact
                nFirst := k; // 记首命中下标 [下标] / record the first hit index
            END_IF
            nLast := k; // 末命中下标随遍历自然收敛 [下标] / the last hit index converges along the traversal
        END_IF
    END_IF
END_FOR

// 段 4｜统一出口（未命中不是故障，边界四）/ segment 4, the unified outlet
bValid := TRUE; // 查找流程走完即可用（含未命中）/ the search completed, usable even with no hit
FC_DL_ArrayFindValue := TRUE; // 返回成功 / return success
END_FUNCTION
