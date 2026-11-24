// ==============================================================================
// 组件名 Component  : FC_DL_SortIndexInt
// 分类   Category   : DL_Base
// 前缀   Naming     : FC_DL_ ｜ b/n/f 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 中
// 功能   Purpose    : INT 数组稳定索引排序：输出按值排序后的原下标排列，
//                      不改 arrSrc（只读纪律）；bDesc = FALSE 升序 /
//                      TRUE 降序；等值元素保持原下标先后（稳定性判据 =
//                      严格比较 + 不交换等值对）。nUsed 钳位 [0, 64]。
// 开源溯源 Origin    : 道莅原创（与 DL_MathData 的 FC_DL_SortIndexLReal
//                      同族自研语义，索引间接排序实现，零代码复制）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6.4 FOR / WHILE 遍历语义
// 平台   Platform   : 纯 IEC 61131-3（FOR / WHILE / 比较 / 数组），三平台通用
// 依赖   Depends    : 无（零委托、零库件）
// 分工声明 Split     : FC_DL_SortIndexLReal（LREAL 版索引排序）为本件同族
//                      件，两件类型口径不同、语义同源，互引声明（R216）；
//                      本件只出索引排列不改数据，读写纪律与彼件一致。
// 归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 计数域闸：nUsed < 0 → 恒等索引早退合法返回（nSorted = 0）；nUsed
//      > 64 → 钳 64 续排（信息级语义，本件无 eErr 出口，钳位场景出口与
//      正常截断排序同形、无独立通道可承载，不另设码，R90 反证句）；
//   二 稳定性判据写死下标序：升序用严格大于、降序用严格小于前移，相等
//      元素不交换（插入序即下标序），升 / 降两向稳定性自证；
//   三 索引写出前已证在 [0, nUse-1] 内（arrIdx 恒等预置 + 插入原地移动），
//      回钳量不复判越界（R241）；
//   四 WHILE 护栏计数 nGuard（上界 32000，远大于最坏比较次数 64*63/2 =
//      2016，且 nGuard 为 INT 不溢出），护栏命中强制退出内层（结构性
//      不可达兜底，不静默死循环）；
//   五 INT 元素无非有限面（NaN / Inf 不适用于整型），非有限闸 N/A；
//   六 nUsed = 0 / 1 退化直返恒等索引（arrIdx[i] = i），bValid = TRUE；
//   七 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
//   八 无除法；无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0001_0746【信息级】nUsed 越域已钳位（< 0 恒等早退，> 64 钳 64 续排）
//   注：本件引脚契约按任务定稿无独立 eErr 出口，钳位语义为文档级。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 值 3/1/2 → 升序索引 1/2/0；V2 值 2/2/1 → 升序索引 2/0/1（稳定性）
//   V3 值 2/2/1 → 降序索引 0/1/2（降序稳定性同向自证）
//   V4 nUsed = 0 / 1 → 恒等索引；V5 nUsed = 100 → 钳 64 续排
//   V6 调用后 arrSrc 原样（只读纪律）
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 2 · 序号 5）
// ==============================================================================
FUNCTION FC_DL_SortIndexInt : BOOL
VAR_IN_OUT
    arrSrc : ARRAY[0..63] OF INT; // 待排序数值 [-]，只读纪律（不改调用方数组）/ the values to sort, read only
END_VAR
VAR_INPUT
    nUsed : INT := 0;            // 参与排序个数 [个]，合法域 0..64 / the count, legal zero to sixty four
    bDesc : BOOL := FALSE;       // 降序开关 [-]，FALSE 升序 / the descending switch, false is ascending
END_VAR
VAR_OUTPUT
    arrIdx  : ARRAY[0..63] OF INT; // 排序后索引排列（arrIdx[0] 为极值原下标）/ the sorted index permutation
    nSorted : INT;               // 实际排序个数 [个] / the actually sorted count
    bValid  : BOOL;              // 结果可用 [-] / the result usable flag
END_VAR
VAR
    k       : INT;               // 外层插入索引 [下标] / the outer insertion index
    m       : INT;               // 内层前移索引 [下标] / the inner shifting index
    nUse    : INT;               // 钳位后的个数 [个] / the clamped count
    nKey    : INT;               // 待插元素原下标暂存 [下标] / the key original index in staging
    nKeyVal : INT;               // 待插元素值暂存 [-] / the key value in staging
    nGuard  : INT;               // 护栏计数 [次] / the guard counter
END_VAR
VAR CONSTANT
    DL_SII_NMAX : INT := 64;     // 排序容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_SII_GMAX : INT := 32000;  // 护栏计数上界 [次]，大于最坏比较次数 2016 且 INT 不溢出 / the guard bound above the worst case
END_VAR

// 段 1｜返回值与全部出口预置 + 索引数组恒等预置（R45 / R254）/ segment 1, the preset and the identity preset
FC_DL_SortIndexInt := FALSE;     // 返回值预置假 / preset the return false
nSorted := 0;                    // 排序个数预置零 [个] / preset the sorted count zero
bValid  := FALSE;                // 有效标志预置假 / preset the validity false
nUse    := 0;                    // 个数预置零 [个] / preset the count zero
nKey    := 0;                    // 键下标预置零 [下标] / preset the key index zero
nKeyVal := 0;                    // 键值预置零 / preset the key value zero
nGuard  := 0;                    // 护栏预置零 [次] / preset the guard zero
FOR k := 0 TO DL_SII_NMAX - 1 DO // 索引数组全量预置恒等 / preset the index array to the identity
    arrIdx[k] := k;              // 恒等索引 / the identity index
END_FOR

// 段 2｜计数域闸（边界一：负数恒等早退，超容量钳位续排）/ segment 2, the count domain gate
IF nUsed < 0 THEN                // 负数非法 / a negative count
    bValid := TRUE;              // 空排列合法（arrIdx 已全量恒等）/ an empty permutation is legal
    FC_DL_SortIndexInt := TRUE;  // 返回成功 / return success
    RETURN;                      // 早退（信息级 0746 语义，文档级）/ early return
END_IF
nUse := nUsed;                   // 域内接管 / take the count
IF nUse > DL_SII_NMAX THEN       // 超容量 / above the capacity
    nUse := DL_SII_NMAX;         // 钳到容量（信息级 0746 语义）/ clamp to the capacity
END_IF

// 段 3｜稳定插入排序（索引间接，严格比较保稳定，边界二；护栏防死循环，边界四）/ segment 3, the stable insertion sort on the indices
FOR k := 1 TO nUse - 1 DO        // 有界外层 / the bounded outer loop
    nKey := arrIdx[k];           // 待插元素原下标 / the key original index
    nKeyVal := arrSrc[nKey];     // 待插元素值 / the key value
    m := k - 1;                  // 内层从前一位置起 / the inner scan starts here
    nGuard := 0;                 // 护栏清零 / reset the guard
    WHILE (m >= 0) AND (((NOT bDesc) AND (arrSrc[arrIdx[m]] > nKeyVal)) OR (bDesc AND (arrSrc[arrIdx[m]] < nKeyVal))) DO // 前驱按序更极才前移（严格比较，等值不交换，稳定性自证）/ shift while the predecessor is strictly more extreme
        arrIdx[m + 1] := arrIdx[m]; // 索引后移一位 / shift the index right
        m := m - 1;              // 内层前移 / step the inner scan left
        nGuard := nGuard + 1;    // 护栏计数推进 / advance the guard
        IF nGuard > DL_SII_GMAX THEN // 护栏命中（结构性不可达兜底）/ the guard tripped
            m := -1;             // 强制退出内层（不置码，结构兜底）/ force the inner loop out
        END_IF
    END_WHILE
    arrIdx[m + 1] := nKey;       // 键落位（m+1 已证在 [0, k] 内，边界三）/ the key lands with a proven bound
END_FOR

// 段 4｜出口（nUse = 0/1 时 arrIdx 已为恒等，边界六）/ segment 4, the outlet with the degenerate identity
nSorted := nUse;                 // 排序个数出口 [个] / the sorted count outlet
bValid := TRUE;                  // 结果可用 / the result usable
FC_DL_SortIndexInt := TRUE;      // 返回成功 / return success
END_FUNCTION
