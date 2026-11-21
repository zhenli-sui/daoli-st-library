# -*- coding: utf-8 -*-
"""R16 manifest 生成：20 个 T0 防御性包装组件（饱和转换/BCD/泛型选择/TIME 算术）
码位自动顺延：信息级 01C0+（每件 2 槽）、故障级 028E+（每件 3 槽）"""
import json, io, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

INFO_BASE = 0x01C0
FAULT_BASE = 0x028E
D = r"C:\Library\DL_MathData"

# (name, tags, complexity, info_codes list[(hex_off,desc)], fault_codes list, instruction, arch)
ITEMS = [
 ("FC_DL_LrealToRealSat", ["iec-std-wrapper", "sat-convert", "t0-convert"], 2,
  ["超 REAL 域饱和方向记录"], ["输入非有限"],
  "LREAL 到 REAL 的饱和转换用于配置下发与跨精度接口：上位机 LREAL 物理量要写进只支持 REAL 的从站参数。现场存在传感器断线 NaN 与超出 REAL 域的 1e39 量级值，直接 _TO_ 转换部分平台返回 Inf 污染整链。要求：非有限输入返回 0 并标记故障，超 REAL 域按方向饱和到 ±3.402823E38 并置信息级码。",
  "四段式：①非有限拦截（x<>x 判 NaN，幅值比较判 Inf）②域判定 ③委托平台 _TO_ 转换 ④错误码归并。防错：域限值提常量 DL_REAL_MAX（LREAL 承载防常量自溢），先判域再转换，禁止转换后再判 Inf。"),
 ("FC_DL_LrealToDintSat", ["iec-std-wrapper", "sat-convert", "t0-convert"], 2,
  ["DINT 域外饱和方向记录"], ["输入非有限"],
  "LREAL 到 DINT 的饱和转换用于把浮点设定值写入整数型计数器/定位寄存器。越界截断在部分平台是未定义行为。要求：非有限故障返回 0；超 DINT 域按符号钳到 ±2147483648 并置信息级码，取整取向为向零截断后钳位。",
  "四段式：①非有限拦截 ②域判定先行（防越界 TRUNC 的 UB）③委托 TRUNC+转换 ④错误码归并。防错：域限值用 LREAL 常量 DL_DINT_MAX/MIN 承载，先判域再 TRUNC。"),
 ("FC_DL_RealToUdintSat", ["iec-std-wrapper", "sat-convert", "t0-convert"], 2,
  ["负值钳 0", "上溢饱和 4294967295 记录"], ["输入非有限"],
  "REAL 到 UDINT 的饱和转换用于把浮点产量/长度写进无符号寄存器。负值与超 4.29e9 值直接转换部分平台回绕成小整数，危险且难察觉。要求：非有限故障返回 0；负值钳 0、上溢钳 4294967295，均为信息级记录。",
  "四段式：①非有限拦截 ②负值闸 ③上溢闸 ④委托转换。防错：上域常量用 LREAL 承载（DL_UDINT_MAX := 4.294967295E9），REAL 常量装不下 4294967295 精度。"),
 ("FC_DL_RealToUintSat", ["iec-std-wrapper", "sat-convert", "t0-convert"], 2,
  ["负值钳 0", "上溢饱和 65535 记录"], ["输入非有限"],
  "REAL 到 UINT 的饱和转换用于模拟量标定后的工程量写寄存器（0~65535 原始码域）。要求：非有限故障返回 0；负值钳 0、上溢钳 65535，信息级记录，输出保证永远落在 UINT 合法域内。",
  "同 RealToUdintSat 四段式同构，域限值 65535。防错：钳位与记录码一一对应，不得共用一码。"),
 ("FC_DL_RealToByteSat", ["iec-std-wrapper", "sat-convert", "t0-convert"], 2,
  ["负值钳 0", "上溢饱和 255 记录"], ["输入非有限"],
  "REAL 到 BYTE 的饱和转换用于把占空比/比例量（0.0~1.0 标定后乘 255）写进串口/PWM 字节域。要求：非有限故障返回 0；负值钳 0、上溢钳 255，信息级记录，输出永远落在 0~255。",
  "同构四段式，域限值 255，头注释注明串口/PWM 占空比字节域用途。"),
 ("FC_DL_DintToUintSat", ["iec-std-wrapper", "sat-convert", "t0-convert"], 1,
  ["负值钳 0", "上溢饱和 65535 记录"], ["无（整数域三槽预留禁用）"],
  "DINT 到 UINT 的饱和转换用于把有符号计数差值安全降域为无符号寄存器值。负差值直接转换会回绕成大数。要求：负值钳 0、上溢钳 65535，信息级记录；整数域无故障态。",
  "纯整数域两闸 + 委托转换，无浮点段。防错：故障级三槽全部标注预留禁用，不得挪用。"),
 ("FC_DL_UdintToDintChk", ["iec-std-wrapper", "sat-convert", "t0-convert"], 1,
  ["上溢饱和 2147483647 记录"], ["无（三槽预留禁用）"],
  "UDINT 到 DINT 的检查转换用于把大计数器读数接入有符号运算链。超 2147483647 直接转换部分平台变为负数。要求：上溢钳 2147483647 并置信息级码，其余域内直转。",
  "单闸 + 委托转换。防错：比较阈值用 UDINT 域内的 2147483647 直接字面量即可，无需浮点。"),
 ("FC_DL_LintToLrealChk", ["iec-std-wrapper", "sat-convert", "t0-convert"], 2,
  ["超 2^53 精度丢失记录"], ["无（三槽预留禁用）"],
  "LINT 到 LREAL 的检查转换用于把 64 位长计数接入浮点曲线拟合。IEEE 754 双精度尾数仅 53 位，|x|>2^53 后低位丢失。要求：|nIn|>9007199254740992 时值照转但置信息级码提示精度丢失。",
  "两段式：①精度域双侧比较（nIn > MAX OR nIn < -MAX，不用 ABS 防 LINT 极值取负回绕）②委托转换。防错：ABS(LINT_MIN) 回绕是经典陷阱，必须双侧比较。"),
 ("FC_DL_BcdToUdint", ["iec-std-wrapper", "bcd-convert", "t0-convert"], 3,
  ["两槽预留禁用"], ["非法 BCD 半字节（返回 0）", "两槽预留禁用"],
  "8 位十进制 BCD 码到 UDINT 的解码用于读万用表/电表/温控仪的 BCD 原始帧。非法半字节（A~F）代表帧损坏，直接按位加权会得到错误读数。要求：逐半字节校验 0~9，任一半字节 >9 故障返回 0；域内按半字节加权累加，值域 0~99999999。",
  "循环 k=0..7 逐半字节（SHR+AND），先校验后累加。防错：32 位容器只有 8 个半字节，k=8..15 不存在且移位量 >=32 属未定义行为，不越界校验；乘子权重提常量或循环内计算，零魔法数。"),
 ("FC_DL_UdintToBcd", ["iec-std-wrapper", "bcd-convert", "t0-convert"], 3,
  ["超 99999999 饱和记录"], ["无（三槽预留禁用）"],
  "UDINT 到 8 位十进制 BCD 码的编码用于写拨码设定/BCD 显示仪表。要求：nIn>99999999 饱和输出 16#99999999 并置信息级码（与 R9 WordToBcd 的 9999 饱和口径一致，域扩大 4 位）；域内除 10 取余逐位拼装。",
  "循环 8 拍：nIn MOD 10 拼装 + nIn 整除 10 前进，除子常量 10 天然非零。防错：饱和口径与 R9 一致性；拼装用 SHL 加权，禁止乘 16 的魔法数。"),
 ("FC_DL_SelEx", ["iec-std-wrapper", "sel-mux", "t0-generic"], 3,
  ["未选中通道非有限记录"], ["选中通道非有限"],
  "IEC SEL 防御包装用于双通道信号选择（主备传感器切换）。故障语义：选中通道坏则本拍输出必须失效；备用通道坏不影响本拍但应提示维护。要求：选中通道非有限故障返回 0；未选中通道非有限置信息级码记录。",
  "两段式：①未选中通道体检（置信息码不置故障）②按 bG 委托选择输出。防错：体检与选择分离，未选中通道绝不影响本拍 bValid。"),
 ("FC_DL_Mux2Ex", ["iec-std-wrapper", "sel-mux", "t0-generic"], 2,
  ["选择子越界钳位记录"], ["选中通道非有限"],
  "IEC MUX(2) 防御包装用于二通道数据切换。要求：选择子 uK>1 钳 1 并置信息级码（输出总有定义）；选中通道非有限故障返回 0。",
  "三段式：①选择子钳位 ②选中通道体检 ③委托选择。防错：钳位在体检之前，保证索引恒合法。"),
 ("FC_DL_Mux4Ex", ["iec-std-wrapper", "sel-mux", "t0-generic"], 3,
  ["选择子越界钳位记录"], ["选中通道非有限"],
  "IEC MUX(4) 防御包装用于四通道（四工位/四季/四档）数据切换。要求：uK>3 钳 3 信息级；选中通道非有限故障返回 0。",
  "同 Mux2Ex 同构扩展，钳位上限 3。防错：USINT 上界远大于 3，钳位判据必须显式 >3。"),
 ("FC_DL_MinEx", ["iec-std-wrapper", "minmax-limit", "t0-generic"], 1,
  ["两槽预留禁用"], ["任一输入非有限"],
  "IEC MIN 防御包装用于双值取小（双限幅/成本择优）。NaN 参与比较在部分平台恒返回某侧，污染下游。要求：任一输入非有限故障返回 0；域内委托 < 运算取小。",
  "两段式：①双输入非有限体检 ②委托比较。防错：NaN 参与任何比较均为 FALSE，不能用比较结果反推有效性，必须先体检。"),
 ("FC_DL_MaxEx", ["iec-std-wrapper", "minmax-limit", "t0-generic"], 1,
  ["两槽预留禁用"], ["任一输入非有限"],
  "IEC MAX 防御包装用于双值取大（峰值保持/容量择大）。要求与 MinEx 完全同构：任一输入非有限故障返回 0；域内委托比较取大。",
  "同 MinEx 两段式镜像。"),
 ("FC_DL_LimitEx", ["iec-std-wrapper", "minmax-limit", "t0-generic"], 3,
  ["上下限倒置自动交换记录"], ["任一输入非有限"],
  "IEC LIMIT 防御包装用于工程量限幅（阀位/设定域）。现场参数手输常出现上下限倒置。要求：fMin>fMax 自动交换并置信息级码（与各平台分歧行为统一为防御性交换）；三输入任一非有限故障返回 0。",
  "三段式：①三输入体检 ②倒置检测与交换 ③委托限幅钳位。防错：交换必须同时更新双变量，交换后再限幅；体检先于交换（非有限值不可比较）。"),
 ("FC_DL_TimeAddSat", ["iec-std-wrapper", "time-arith", "t0-time"], 3,
  ["和溢出饱和记录"], ["无（三槽预留禁用）"],
  "TIME 饱和加法用于把各段耗时累加成总节拍（累计器场景超 TIME 上限 49 天会回绕成小值）。要求：溢出预判用减法比较（tA > MAX - tB，禁止先加后判防回绕），超限饱和到 T#49d17h2m47s295ms 并置信息级码。",
  "两段式：①减法比较预判溢出 ②委托加法或直接饱和。防错：预判减法 MAX - tB 不下溢（tB <= MAX 保证）；TIME 常量字面量用 T#49D17H2M47S295MS 并注释等价 ms 口径。"),
 ("FC_DL_TimeSubSat", ["iec-std-wrapper", "time-arith", "t0-time"], 2,
  ["负差钳 0 方向记录"], ["无（三槽预留禁用）"],
  "TIME 饱和减法用于计算剩余时间/节拍差。TIME 无符号语义，负差在部分平台回绕成近 49 天的极大值。要求：tB>tA 时差钳 T#0s 并置信息级码。",
  "两段式：①方向判定 ②委托减法或钳 0。防错：判定必须显式 tB > tA，不得用减法结果符号位（TIME 无符号）。"),
 ("FC_DL_TimeScaleSat", ["iec-std-wrapper", "time-arith", "t0-time"], 3,
  ["乘积溢出饱和记录", "负乘子已钳 0 记录"], ["无（三槽预留禁用）"],
  "TIME 乘法用于按倍率缩放节拍（慢动作演示 10 倍、快速仿真 0.1 倍）。要求：负乘子输出钳 T#0s 并置信息级码（TIME 无负语义）；nScale=0 输出 T#0s 合法无码；溢出预判 tIn > MAX / nScale（除子非零已保证）后饱和。",
  "四段式：①负乘子闸（信息级+钳 0）②零乘子直通 ③除法预判溢出 ④委托乘法或饱和。防错：预判除法在 nScale>0 分支内，除子恒非零；INT 乘子域 0~32767 无 INT 溢出。"),
 ("FC_DL_TimeDivChk", ["iec-std-wrapper", "time-arith", "t0-time"], 3,
  ["负除子取绝对值记录"], ["除零守卫", "两槽预留禁用"],
  "TIME 除法用于按工位数平分节拍或按缩放系数反算周期。要求：nDiv=0 除零故障返回 T#0s 且 bValid=FALSE；nDiv<0 取模长参与运算并置信息级码（TIME 无负语义，方向取模长）。",
  "三段式：①除零故障闸（升位 DINT 判定防 INT 最小值陷阱）②负除子取模长（升位 DINT 后取负再降回 INT，规避 -32768 取负回绕）③委托除法。防错：INT 最小值 -32768 取负仍是 -32768，必须升位处理。"),
]

def hx(v):
    return "16#%04X_%04X" % (v >> 16, v & 0xFFFF)

def main():
    items = []
    info = INFO_BASE
    fault = FAULT_BASE
    for name, tags, cx, infos, faults, instr, arch in ITEMS:
        segs = []
        for d in infos:
            segs.append("%s(信息级：%s)" % (hx(info), d)); info += 1
        for d in faults:
            segs.append("%s(故障级：%s)" % (hx(fault), d)); fault += 1
        items.append({
            "name": name, "category": "DL_MathData", "type": "FC",
            "file_path": "%s\\%s.st" % (D, name),
            "function_tags": tags, "complexity": cx,
            "instruction": instr, "architecture_thought": arch,
            "code_segment": " / ".join(segs),
        })
    man = {"reg_version": "2.5.0", "items": items,
           "info_cursor_next": hx(info), "fault_cursor_next": hx(fault)}
    out = r"C:\Library\_Staging_Raw\2026-11-16\manifest_r16.json"
    json.dump(man, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("[OK] manifest_r16.json 20 items; info cursor ->", hx(info), "; fault cursor ->", hx(fault))

if __name__ == "__main__":
    main()
