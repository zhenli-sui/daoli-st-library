(* ===========================================================================
   组件名   : FC_DL_HashCollisionProbe
   分类     : DL_Algo / 哈希冲突线性探测
   一句话   : 给定起始桶与占用表，线性探测返回首个空桶，含满表检测与回绕
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : iStartBucket 起始桶号（可为任意整数，内部归一化）
              axOccupied 占用表 [1..64]，TRUE=已占用；iTableSize 表长 1..64（自动钳位）
   输出契约 : 返回值 = 首个空桶号（1..iTableSize）；xFound 是否找到空桶
              xTableFull 满表标志；iProbes 探测次数；iFirstFree 同返回值显式输出
   算法说明 : 探测序列 idx = ((start−1 + k) MOD size) + 1，k 从 0 递增至 size−1；
              起始桶先做双重取模归一，消除负值与越界；环形回绕由取模天然完成
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_HashCollisionProbe : INT
VAR_INPUT
    iStartBucket : INT := 1;           // 起始桶号 | start bucket index
    axOccupied : ARRAY[1..64] OF BOOL; // 占用表 TRUE=占用 | occupancy table
    iTableSize : INT := 64;            // 表长 1..64 | table size 1..64
END_VAR
VAR_OUTPUT
    xFound : BOOL;                     // 找到空桶 | free bucket found
    xTableFull : BOOL;                 // 满表 | table full
    iProbes : INT;                     // 探测次数 | probe count
    iFirstFree : INT;                  // 首个空桶号（重复输出） | first free bucket
END_VAR
VAR
    _iSize : INT;                      // 钳位后表长 | clamped table size
    _iIdx : INT;                       // 当前探测下标 | current probe index
    _iBase : INT;                      // 起始偏移 | start offset
    _k : INT;                          // 探测步下标 | probe step index
    _iOut : INT;                       // 结果桶号 | result bucket index
END_VAR

// ---- 输出预置 ----
xFound := FALSE;
xTableFull := FALSE;
iProbes := 0;
iFirstFree := 0;
FC_DL_HashCollisionProbe := 0;

// ---- 表长钳位：至少 1，至多 64；为 0 时直接判满表，禁止取模 ----
_iSize := iTableSize;
IF _iSize < 1 THEN
    xTableFull := TRUE;                            // 表长为零等价于无处可放
    RETURN;
END_IF
IF _iSize > 64 THEN
    _iSize := 64;
END_IF

// ---- 起始桶归一化：(x−1) 双重取模，兼容负值与超范围 ----
_iBase := (iStartBucket - 1) MOD _iSize;
IF _iBase < 0 THEN
    _iBase := _iBase + _iSize;                     // 负余数归一
END_IF

// ---- 线性探测：最多探测表长次，天然回绕 ----
FOR _k := 0 TO (_iSize - 1) DO
    IF NOT xFound THEN
        _iIdx := (_iBase + _k) MOD _iSize + 1;     // 下标 1.._iSize
        IF _iIdx < 1 THEN
            _iIdx := 1;                            // 下标钳位，防越界读
        ELSIF _iIdx > _iSize THEN
            _iIdx := _iSize;
        END_IF
        IF NOT axOccupied[_iIdx] THEN
            _iOut := _iIdx;
            xFound := TRUE;                        // 命中首个空桶即停止
            iProbes := _k + 1;
        END_IF
    END_IF
END_FOR

// ---- 结果出口 ----
IF xFound THEN
    iFirstFree := _iOut;
    FC_DL_HashCollisionProbe := _iOut;
ELSE
    xTableFull := TRUE;                            // 探测满表长仍未命中即判满表
    iFirstFree := 0;
    FC_DL_HashCollisionProbe := 0;
END_IF
END_FUNCTION
