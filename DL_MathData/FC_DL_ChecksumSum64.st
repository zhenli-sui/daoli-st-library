// =====================================================================
// FC_DL_ChecksumSum64.st
// LWORD 数组 64 位累加和校验（纯函数, 模 2^64 自然回绕求和 + 越界守卫）
// 64-bit LWORD array additive checksum, pure function
// 所属子库: DL_MathData    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0001_048A ~ 16#0001_048D (本件独占 4 槽, FC 纯函数分型, 勿复用)
// 溯源: IEC 61131-3 标准语义的道莅防御性实现
//       来源组标签: checksum, data-integrity, pure-function, lword
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 19)
// 语义声明: 模 2^64 累加和由 LWORD 无符号加法自然回绕实现, 禁用取余运算;
//           与 FC_DL_ChecksumSum8 构成 8/64 位宽两件, 位宽变体不再扩充;
//           错误出口约定与 FC_DL_ChecksumSum8 现行 uErrorId 出口一致;
//           纯函数无内部状态, 码为返回拍瞬时值, 无锁存面
// =====================================================================
FUNCTION FC_DL_ChecksumSum64 : LWORD   // 返回累加和, 异常路径返回哨兵零值 / Returns sum, sentinel zero on fault
VAR_INPUT
    aData  : ARRAY[*] OF LWORD;     // 被校验数组（开数组, 实测边界）/ Data array, open bounds
    uCount : USINT;                 // 参与求和的元素个数 1~255 / Element count
END_VAR
VAR_OUTPUT
    uErrorId : UDINT;               // 错误码, 见码表 / Error code, see table
END_VAR
VAR
    uCap   : DINT := 0;             // 数组实测元素容量 / Measured array capacity
    uNum   : DINT := 0;             // 钳位后的求和个数 / Effective count
    iIdx   : DINT := 0;             // 循环下标 / Loop index
    iElem  : DINT := 0;             // 数组元素下标 / Element index
    lwSum  : LWORD := LWORD#0;      // 累加和 / Accumulated sum
    lwPrev : LWORD := LWORD#0;      // 上拍和快照（回绕检测）/ Previous sum for wrap detect
    xWrap  : BOOL := FALSE;         // 自然回绕发生标记 / Wraparound occurred flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0001_048A 信息 累加和计算完成（含自然回绕路径）
//   16#0001_048B 信息 空输入（计数为 0, 返回哨兵零值）
//   16#0001_048C 故障 计数越界（大于数组实测容量, 强制退出, 返回零值）,
//                纯函数无锁存面, 修正入参重新调用即解除
//   16#0001_048D 信息 求和自然回绕发生（本拍回绕旁证, 供数据链路诊断）
// ---------------------------------------------------------------------

// ---- 缺省返回哨兵零值 / Default sentinel zero ----
FC_DL_ChecksumSum64 := LWORD#0;

// ---- 容量实测（开数组边界实测, 不假设下标起点）/ Measured capacity ----
IF UPPER_BOUND(aData, 1) >= LOWER_BOUND(aData, 1) THEN
    uCap := (UPPER_BOUND(aData, 1) - LOWER_BOUND(aData, 1)) + 1;    // 元素个数 / Element count
END_IF

// ---- 空输入: 计数为 0, 返回哨兵零 + 信息码 / Empty input ----
IF uCount = 0 THEN
    uErrorId := 16#0001_048B;       // 空输入码 / Empty input code
    RETURN;                         // 返回零值 / Return zero
END_IF

// ---- 计数越界守护: 强制退出 / Count overrun guard: force exit ----
uNum := USINT_TO_DINT(uCount);
IF uNum > uCap THEN
    uErrorId := 16#0001_048C;       // 越界故障码 / Overrun fault code
    RETURN;                         // 强制退出返回零 / Force exit with zero
END_IF

// ---- 模 2^64 累加（LWORD 自然回绕, 禁用取余）/ Modulo sum by natural wrap ----
lwSum := LWORD#0;                   // 和清零 / Clear sum
xWrap := FALSE;                     // 回绕标记复位 / Reset wrap flag
FOR iIdx := 1 TO uNum DO
    iElem := LOWER_BOUND(aData, 1) + (iIdx - 1);    // 实测下标映射 / Measured index mapping
    lwPrev := lwSum;                // 上拍和快照 / Snapshot previous sum
    lwSum := lwSum + aData[iElem];  // 累加（无符号自然回绕）/ Accumulate with natural wrap
    IF lwSum < lwPrev THEN
        xWrap := TRUE;              // 无符号回绕旁证 / Unsigned wrap occurred
    END_IF
END_FOR

FC_DL_ChecksumSum64 := lwSum;       // 返回累加和 / Return sum
IF xWrap THEN
    uErrorId := 16#0001_048D;       // 回绕旁证码 / Wrap hint code
ELSE
    uErrorId := 16#0001_048A;       // 完成码 / Done code
END_IF

END_FUNCTION
