(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SwapBytes16
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 SHL / SHR / AND / OR，零厂商方言
 * 功能描述 (Function)   : 16 位字高低字节互换。低字节左移 8 位升为高字节，
 *                         高字节右移 8 位降为低字节，两者按位或合成结果。
 *                         纯函数：不修改入参、无内部状态、相同输入必得相同输出；
 *                         自逆性成立，连续调用两次还原原值。
 *                         单寄存器字节序（Profibus 从站状态字、串口仪表读数）的原子构件，
 *                         同时是 32 位四排布转换的底层原子。
 * 开源溯源 (Origin)     : 原创实现。字节序定义参照 modbus.org 公开协议说明中
 *                         "单寄存器内部为大端"的事实约定；算法为公开的移位掩码法，
 *                         未复制任何厂商私有库源码，不构成衍生作品。
 * 本文件内含       : FC    FC_DL_SwapBytes16（单 POU，无配套类型）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: SHL / SHR
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯标准位运算，无字节访问方言 ｜ R4 N/A（无除法/数组/循环/浮点）
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯函数，无状态机）
 *                         R7 N/A（无定时器/边沿实例）｜ R8 ✓ 移位量与掩码全常量化
 *
 * 【错误码豁免声明 / Error-code exemption】
 *   本函数不设 uErrorId 输出引脚。理由：16 位字节互换的全定义域均为合法输入，
 *   不存在任何运行期失败路径；恒为 0 的错误码引脚只会增加调用方噪音。
 *   沿用首轮 FC_DL_PackBitsToWord 的显式豁免先例（ROUND_PLAN_R2 §2.8 决策 P3）。
 *
 * 【实现选择 / Implementation choice】
 *   仅用移位 + 掩码 + 按位或，禁止任何按字节访问的厂商方言语法（R3 关键考点）。
 *   移位量经 VAR CONSTANT 统一给出，避免字面量散落造成口径漂移。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 A）
 *============================================================================*)
FUNCTION FC_DL_SwapBytes16 : WORD
VAR_INPUT
    uValue : WORD;                       // 原始 16 位字 / Source word
END_VAR
VAR
    uLow   : WORD;                       // 低字节缓存（左移后成为高字节）/ Low byte buffer, shifted up to the high byte
    uHigh  : WORD;                       // 高字节缓存（右移后成为低字节）/ High byte buffer, shifted down to the low byte
END_VAR
VAR CONSTANT
    DL_SWAP_SHIFT8 : UDINT := 8;         // 字节移位量 [bit]，全库统一口径 / Byte shift width [bit], unified library-wide
    DL_MASK_LOW8   : WORD := 16#00FF;    // 低 8 位掩码 / Low-byte mask
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（P-01 范式）：任何异常路径返回原值，绝不返回 0
 *      Safe preset: every exceptional path returns the source value, never zero
 *-----------------------------------------------------------------------------*)
FC_DL_SwapBytes16 := uValue;

(*------------------------------------------------------------------------------
 * 段 2｜字节分离与重装（边界 B1/B5）：全程在 WORD 域内运算，无跨类型转换
 *      Byte separation and reassembly: WORD domain only, no cross-type conversion
 *      低位字节左移 8 位升为高位，高位字节右移 8 位降为低位，再按位或合成
 *      Low byte shifts up by 8, high byte shifts down by 8, then bitwise OR
 *-----------------------------------------------------------------------------*)
uLow  := SHL(uValue AND DL_MASK_LOW8, DL_SWAP_SHIFT8);
uHigh := SHR(uValue, DL_SWAP_SHIFT8);

(*------------------------------------------------------------------------------
 * 段 3｜结果回写（边界 B4）：纯函数出口唯一，无副作用
 *      Result write-back: single exit, no side effect
 *      验收向量：16#1A2B → 16#2B1A；自逆性 Swap(Swap(x)) = x 对全字域成立
 *      Acceptance vector: 16#1A2B -> 16#2B1A; self-inverse over the whole word domain
 *-----------------------------------------------------------------------------*)
FC_DL_SwapBytes16 := uLow OR uHigh;
END_FUNCTION
