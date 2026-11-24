(*
    FC_DL_FiniteClassify —— LREAL 非有限分类原子
    ------------------------------------------------------------------
    组件名称  : FC_DL_FiniteClassify
    分类      : DL_MathData / FloatFiniteness
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（IEEE 754 NaN 自反性
                与 Inf 差值自反判据的原子化提取，判据即库内 R79 非有限
                双判的语义本体）；实现 / 引脚名 / 枚举 100% 自有；
                clean-room 声明 —— 零代码行复制，无闭源参考。
    平台      : 纯 IEC 61131-3（LREAL 比较 + 标准 ABS），无内建函数依赖，
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 1 · 序号 2）
    ------------------------------------------------------------------
    功能说明  : 把散落在库内各件的内联 R79 非有限判据提取为**全库首个
                非有限分类属主**，输出 IEEE 754 语义四态：eFinite / ePosInf /
                eNegInf / eNaN，并给 bFinite 布尔快照。真实工况：闸前置
                分类诊断文本（HMI 显示「断线 / 无穷 / 正常」）、诊断日志分桶。
                判据链（禁近似阈值，R79）：
                ① NaN 用自反性 x <> x 判（NaN 与任何值比较均为 FALSE，含自身）；
                ② Inf 用差值自反判 (x − x) <> 0（有限值差恒为 0，无穷处产 NaN），
                   判出后按符号二分（x > 0.0 → ePosInf，x < 0.0 → eNegInf；
                   x = 0.0 在非 NaN 前提下差值必为 0，不会落入本分支）；
                ③ 其余 eFinite。
                幅值常量 1.7976931348623157E308 只可作注释旁证（LREAL 最大
                有限值），**不得作为判据**——近似阈值会在 [近似值, 真实最大值]
                区间制造假阳性带（R79 教训）。
                与库内各件内联 R79 判据的关系 = 「原子提取」而非语义变更：
                各件可组合调用本件但不强制回改存量（存量回改挂账不改码，
                R333 口径）。本件不做幅值上界筛查——上界筛查属调用方业务
                语义，本件只分 IEEE 语义四态。
    错误码    : N/A —— 本件为全定义域全值函数（任何 LREAL 入参都得到确定
                分类），无故障 / 信息出口，无码位分配。
    码位总账  : 无（全值函数，四态穷尽 LREAL 全域）
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无沿检测实例 / 无数组下标 / 无除法 / 无循环，
                   零除零面与死循环面，周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 验收向量：V1 1.0 → eFinite + bFinite=TRUE；
                   V2 0.0 / 0.0（NaN）→ eNaN + bFinite=FALSE；
                   V3 1.0 / 0.0（+Inf）→ ePosInf + bFinite=FALSE；
                   V4 −1.0 / 0.0（−Inf）→ eNegInf + bFinite=FALSE；
                   V5 −0.0 → eFinite（负零是有限值，差值恒 0）。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 1 · 序号 2）
*)
TYPE E_DL_FiniteKind :
(
    eFinite := 0,                          // 有限值：正常数值 / finite, a normal numeric value
    ePosInf := 1,                          // 正无穷：+Inf，多为除零 / 上溢 / the positive infinity
    eNegInf := 2,                          // 负无穷：−Inf，多为下溢 / 负向除零 / the negative infinity
    eNaN    := 3                           // 非数：断线 / 无效运算结果 / the not a number class
);
END_TYPE

FUNCTION FC_DL_FiniteClassify : E_DL_FiniteKind
VAR_INPUT
    fVal : LREAL;                          (* 待分类值，[任意物理量纲，无量纲语义]，本件不解释量纲 / the value under test, dimension free, the FC never interprets units *)
END_VAR
VAR_OUTPUT
    bFinite : BOOL;                        (* 有限值快照：TRUE 当且仅当分类为 eFinite / the finite snapshot, TRUE iff eFinite *)
END_VAR

// 段 1｜返回值与状态预置（统一出口预置，R256）/ segment 1, preset the return and the status
FC_DL_FiniteClassify := E_DL_FiniteKind.eFinite; // 预置有限分类 / preset the finite class
bFinite := FALSE;                        // 预置非有限快照（段 3 正常出口翻转）/ preset the snapshot false

// 段 2｜NaN 自反判（NaN 与自身比较为 FALSE，R79 判据一）/ segment 2, the NaN reflexive test
IF fVal <> fVal THEN                     // 自比较为假即 NaN / a false self comparison means NaN
    FC_DL_FiniteClassify := E_DL_FiniteKind.eNaN; // 分类非数 / classify NaN
    bFinite := FALSE;                    // 快照非有限 / the snapshot false
    RETURN;                              // 结构早退 / structural exit
END_IF

// 段 3｜Inf 差值自反判（有限值差恒 0，无穷处产 NaN，R79 判据二）+ 符号二分 / segment 3, the infinity difference test and the sign split
IF (fVal - fVal) <> 0.0 THEN             // 差值非零即无穷 / a non zero difference means infinity
    IF fVal > 0.0 THEN                   // 正无穷支（NaN 已在段 2 排除，0.0 不会落入本支）/ the positive branch
        FC_DL_FiniteClassify := E_DL_FiniteKind.ePosInf; // 分类正无穷 / classify plus infinity
    ELSE                                 // 负无穷支 / the negative branch
        FC_DL_FiniteClassify := E_DL_FiniteKind.eNegInf; // 分类负无穷 / classify minus infinity
    END_IF
    bFinite := FALSE;                    // 快照非有限 / the snapshot false
    RETURN;                              // 结构早退 / exit
END_IF

// 段 4｜有限值正常出口（旁证注释：LREAL 最大有限值 1.7976931348623157E308，
//        仅注释不作判据，R79 禁近似阈值）/ segment 4, the finite outlet
FC_DL_FiniteClassify := E_DL_FiniteKind.eFinite; // 分类有限 / classify finite
bFinite := TRUE;                         // 快照有限 / the snapshot true
END_FUNCTION
