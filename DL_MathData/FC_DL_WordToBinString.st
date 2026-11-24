(*
    FC_DL_WordToBinString —— WORD → 16 字符定长二进制文本（MSB-first）
    ------------------------------------------------------------------
    组件名称  : FC_DL_WordToBinString
    分类      : DL_MathData / BitText
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（WORD 位序 → '0'/'1'
                文本化的位掩码提取，与库内 FC_DL_DwordToHexString（十六进制
                文本化）同族反向补口）；实现 / 引脚名 / 码位 100% 自有；
                clean-room 声明 —— 零代码行复制，无闭源参考。
    平台      : 纯 IEC 61131-3（FOR + SHL + CONCAT），无内建函数依赖，
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 2 · 序号 5）
    ------------------------------------------------------------------
    功能说明  : 把 WORD 的 16 个位按 **MSB-first**（位 15 → 位 0）顺序拼接为
                16 字符定长二进制文本（'0101…'，字符 '1' = 位 1，'0' = 位 0）。
                真实工况：调试面板位诊断显示、协议帧人读文本、培训 / 文档
                向量打印。
                判据链：逐位提取（掩码法：uMask := SHL(WORD#1, uBit)，uBit 由
                常量界循环 0..15 生成，**全程无 64 位移位、移位量 ≤ 15 <
                WORD 位宽 16**（R48 移位量归一：结构性保证，非变量依赖））
                → 定长出口（16 字符恒定，无截断可能——与可截断族的口径差异：
                本件输出长度是输入位宽的常量函数，不随值变化）。
                位序口径声明：MSB-first（位 15 在串首），与网络字节序调试
                惯例一致；LSB-first 需求属另一语义（位序重排归
                FC_DL_ReverseBitsWord，不在本件）。
    错误码    : N/A —— 本件为全定义域全值函数（65536 个 WORD 值全部得到
                确定 16 字符输出），bValid 恒 TRUE 仅保留契约一致性，无故障 /
                信息出口，无码位分配。
    码位总账  : 无（全值函数）
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无沿检测实例 / 无除法，FOR 循环界为常量
                   0..15（无变量界，无死循环面，守卫计数器豁免），周期安全
                   规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 验收向量：V1 uWord = 16#0000 → '0000000000000000'（全 0 串）；
                   V2 uWord = 16#FFFF → '1111111111111111'（全 1 串）；
                   V3 uWord = 16#0001 → '0000000000000001'（LSB 在串尾，
                   MSB-first 口径自证）；V4 uWord = 16#8000 → '1000000000000000'。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    分工声明  : FC_DL_DwordToHexString（十六进制文本化）、FC_DL_ReverseBitsWord
                （位序重排非文本化）、FC_DL_FirstSetBit（位搜索）——本件只做
                WORD 的二进制文本化，三者均不替代本件。
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 2 · 序号 5）
*)
FUNCTION FC_DL_WordToBinString : STRING
VAR_INPUT
    uWord : WORD;                          (* 待文本化字，[位图]，本件不解释位语义 / the word under conversion, the FC never interprets bit semantics *)
END_VAR
VAR_OUTPUT
    bValid : BOOL;                         (* 输出可用标志，恒 TRUE（契约一致性保留）/ the outputs usable flag, always TRUE by contract *)
END_VAR
VAR CONSTANT
    DL_WBS_ONE   : STRING(1) := '1';       // 位 1 字符 [文本] / the bit one char
    DL_WBS_ZERO  : STRING(1) := '0';       // 位 0 字符 [文本] / the bit zero char
    DL_WBS_BITS  : INT := 16;              (* WORD 位宽（常量界循环上界 − 1）[位] / the word width *)
    DL_WBS_LAST  : INT := 15;              (* MSB-first 首位下标（位 15）[位] / the first bit index, MSB first *)
    DL_WBS_STEP  : INT := 1;               (* 循环步进 [位] / the loop step *)
    DL_WBS_ZEROI : INT := 0;               (* LSB 循环下界 [位] / the loop lower bound *)
END_VAR
VAR
    nI    : INT;                           (* 循环游标（0..15，常量界）[位] / the loop cursor *)
    uBit  : INT;                           (* 当前提取位号（15 − nI，MSB-first）[位] / the current bit index *)
    uMask : WORD;                          (* 当前位掩码 [位图] / the current bit mask *)
END_VAR

// 段 1｜返回值与状态预置（统一出口预置，R256）/ segment 1, preset the return and the status
FC_DL_WordToBinString := '';             // 预置空串，逐位拼接 / preset the empty string
bValid := FALSE;                         // 预置不可用，出口翻转 / preset unusable
nI    := DL_WBS_ZEROI;                   // 游标预置 / preset the cursor
uBit  := DL_WBS_LAST;                    // 位号预置（MSB-first 起点）/ preset the bit index
uMask := WORD#0;                         // 掩码清零 / clear the mask

// 段 2｜逐位提取拼接（位 15 → 位 0，MSB-first；移位量 uBit ∈ [0,15] 结构性
//        小于位宽 16，R48 归一豁免声明）/ segment 2, the bit by bit extraction
FOR nI := DL_WBS_ZEROI TO DL_WBS_LAST BY DL_WBS_STEP DO // 常量界循环（无变量界死循环面）/ the constant bound loop
    uBit := DL_WBS_LAST - nI;            // MSB-first 位号 / the MSB first bit index
    uMask := SHL(WORD#1, uBit);          // 掩码法取位（移位量 <= 15，结构性安全）/ the mask method
    IF (uWord AND uMask) <> WORD#0 THEN  // 位为 1 / the bit is one
        FC_DL_WordToBinString := CONCAT(FC_DL_WordToBinString, DL_WBS_ONE); // 拼 '1' / append the one char
    ELSE                                 // 位为 0 / the bit is zero
        FC_DL_WordToBinString := CONCAT(FC_DL_WordToBinString, DL_WBS_ZERO); // 拼 '0' / append the zero char
    END_IF
END_FOR

// 段 3｜统一出口（16 字符恒定，无截断可能）/ segment 3, the unified outlet
bValid := TRUE;                          // 全值函数恒可用 / the total function always usable
END_FUNCTION
