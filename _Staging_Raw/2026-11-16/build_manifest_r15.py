# -*- coding: utf-8 -*-
"""R15 manifest 生成：20 个 T0 防御性包装组件的注册元数据 + 码位自动顺延（信息级 015E+ / 故障级 022C+）"""
import json, io, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

INFO_BASE = 0x015E
FAULT_BASE = 0x022C

# (name, tags, complexity, info_desc, fault_desc, instruction, arch)
ITEMS = [
 ("FC_DL_AbsEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "abs"], 2,
  "非有限输入归一 0.0",
  "负极大值取绝对值溢出钳位 ±1.797e308",
  "包装绝对值函数用于张力/偏差量计算，现场存在传感器断线产生的 NaN 与 -1.7e308 极值。要求：NaN 输入返回 0 并标记无效，-0.0 归一为 +0.0，负极大值取绝对值后不得溢出为 -Inf。",
  "单函数无状态，四段式：①非有限检测（x<>x 判 NaN，与 ±Inf 比较）②零归一 ③符号分支取绝对 ④错误码归并。防错点：不用平台 ABS() 直接套（对 -1.79e308 会溢出），先判边界再取负。"),
 ("FC_DL_SinEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "sin", "angle-reduce"], 4,
  "超大角度归约后精度降级、非有限输入拦截",
  "输入超出归约可表示范围",
  "旋转变换与轨迹插补需要正弦，但累计角度会无限增长到 1e9 量级，直接调 SIN 精度崩坏。要求：先按 2π 归约到 [0,2π)，归约后误差仍超容差时继续计算但标记 bValid=FALSE；NaN 输入返回 0。",
  "四段式：①非有限拦截 ②2π 归约（用 FLOOR 语义保证负角度也落入 [0,2π)）③委托内建 SIN ④错误码归并。归约不是重实现内核，只做相位折叠以保精度。防错：归约商用 DINT_TO_LREAL 前先判 |x|/2π 是否超 DINT 范围。"),
 ("FC_DL_CosEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "cos", "angle-reduce"], 4,
  "超大角度归约后精度降级、非有限输入拦截",
  "输入超出归约可表示范围",
  "正交分解与功率因数计算需要余弦，角度同样会累计增长。要求与 SinEx 完全一致的归约与降级策略，保证 sin/cos 在同一角度下结果自洽。",
  "复用 SinEx 的归约段实现（复制段落而非调用 SinEx，避免 90° 相位偏移引入二次误差），委托内建 COS。防错：归约常数用 LREAL 精度 6.283185307179586，不得用 REAL 常数。"),
 ("FC_DL_AsinEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "asin", "domain-clamp"], 3,
  "定义域 [-1,1] 外钳位并置无效",
  "非有限输入",
  "由归一化比值反解角度，测量噪声会让比值偶尔冲到 1.0001，直接调 ASIN 在部分平台返回 NaN 污染下游 PID。要求：越界钳到 ±1 后继续计算并置 0001，返回钳位结果但 bValid=FALSE。",
  "四段式：①非有限拦截 ②域检查与钳位（记录是否发生钳位）③委托内建 ASIN ④错误码归并。防错：钳位后必须仍返回可用角度（降级可用优于返回 NaN）。"),
 ("FC_DL_AcosEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "acos", "domain-clamp"], 3,
  "定义域 [-1,1] 外钳位并置无效",
  "非有限输入",
  "相位差与夹角计算需要反余弦，比值噪声同样会越界。要求与 AsinEx 同构的钳位降级策略，输入 0 时正确返回 π/2。",
  "同 AsinEx 四段式，委托内建 ACOS。防错：π/2 由 1.5707963267948966 常量给出，不用 ACOS(0) 二次计算。"),
 ("FC_DL_AtanEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "atan"], 2,
  "非有限输入",
  "无穷输入钳位后返回极限角",
  "斜率反解角度用，输入为任意实数（含极大斜率）。要求全实数域可用，返回值严格落在开区间 (-π/2, π/2)。",
  "四段式：①非有限检测 ②±Inf 直接返回 ±π/2 并置码 ③委托内建 ATAN ④错误码归并。防错：不用 y/x 再 ATAN（会丢象限且除零），单参数版本语义即为斜率。"),
 ("FC_DL_Atan2Ex", ["iec-std-wrapper", "iec-std-math", "t0-math", "atan2", "quadrant"], 5,
  "双零输入退化置信息码、象限判别",
  "无匹配分支兜底（理论不可达）",
  "平面定位需要四象限反正切（AGV 航向角、视觉偏移角），x/y 都可能为 0，且必须返回 (-π, π] 而不是 (-π/2, π/2)。要求：双零返回 0 且置信息码，x=0 特判 ±π/2，x<0 分 y 正负加/减 π。",
  "IF/ELSIF 链五分支 + 无条件 ELSE 兜底（返回 0 且 0005）。防错：①双零用 eps=1.0E-12 判，不用 =0.0 精确比较 ②x<0 且 y>=0 界限必须明确（y=0 归 +π）③分支顺序不能先判 x>0 后的 y 符号，否则象限错。"),
 ("FC_DL_ExpEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "exp", "overflow-guard"], 4,
  "下溢降级为 0 并保留可用性",
  "上溢钳位到 LREAL 极大值",
  "指数衰减/增长模型（温度响应、RC 充电）直接调 EXP，超范围时部分平台返回 Inf 污染整链运算。要求：入参 >709.78 钳到极大值置 0002，< -745.13 返回 0 置 0002 但 bValid 保持 TRUE（0 是有效物理值）。",
  "四段式：①上下溢预判（常数 709.782712893384 / -745.1332191019411）②委托内建 EXP ③错误码归并 ④有效性语义分离（bError 与 bValid 不同源）。防错：上溢钳位值必须是 1.7976931348623157E308 而非 1.0E308。"),
 ("FC_DL_ExptEx", ["iec-std-wrapper", "iec-std-math", "t0-math", "expt", "pow-guard"], 5,
  "0 的负次幂不可表示、负底数非整数指数无实数解",
  "结果上溢钳位",
  "流量孔板与泵功率曲线含幂律 base^exp，现场会传入 0 底数（空罐）与负底数（反向流量）配小数指数。要求：0 负幂返回 0 且置 0005，负底数非整数指数返回 0 且置 0003，上溢钳位。",
  "四段式：①非法组合前置判定（base=0&exp<0；base<0&frac≠0，frac 用 lrExp-TRUNC(lrExp)、容差 1.0E-9）②上溢预判 exp*LN(|base|)>709.78 ③委托内建 EXPT ④错误码归并。防错：负底数整数指数合法，必须放行（不能一律拦）。"),
 ("FC_DL_TruncEx", ["iec-std-wrapper", "iec-std-math", "t0-round", "trunc"], 3,
  "越界钳到 DINT 端点",
  "非有限输入",
  "点数换算需要向零取整，浮点累计误差会出现 2147483647.6 这种越界值。要求：向零截断，超 DINT 范围钳到端点并置 0002，NaN 返回 0。",
  "四段式：①非有限拦截 ②范围预判（±2147483647.0 比较，注意 DINT 下限 -2147483648 可精确表示）③委托内建 TRUNC ④错误码归并。防错：先判范围再 TRUNC，不能 TRUNC 后判（TRUNC 越界本身未定义）。"),
 ("FC_DL_FloorEx", ["iec-std-wrapper", "iec-std-math", "t0-round", "floor"], 3,
  "越界钳到 DINT 端点",
  "非有限输入",
  "托盘/料箱整箱数必须向下取整（-1.2 箱要算 -2，不能算 -1 否则超发）。要求：向 -∞ 取整，越界钳位置 0002。",
  "四段式同 TruncEx，委托内建 FLOOR。防错：负数结果的向下取整与向零截断不同，验收向量必须含 -1.2→-2、-0.5→-1。"),
 ("FC_DL_CeilEx", ["iec-std-wrapper", "iec-std-math", "t0-round", "ceil"], 3,
  "越界钳到 DINT 端点",
  "非有限输入",
  "装箱数/班次数必须向上取整（-1.2 → -1，0.1 → 1）。要求：向 +∞ 取整，越界钳位置 0002。",
  "四段式同 TruncEx，委托内建 CEIL。防错：验收向量含 0.1→1、-1.2→-1、恰为整数时不变。"),
 ("FC_DL_StringLenEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "len"], 3,
  "空串/首字符空符提前终止",
  "扫描越界守卫触发（255 上限）",
  "报文解析需要真实有效长度，STRING(255) 尾部常带空符与补齐空格，直接取固定长度会把垃圾字符算进报文。要求：遇 $00 提前终止，可选去尾随空格，返回 0~255 且绝不越界。",
  "WHILE 循环 + 双退出条件（遇 $00 / nI>255）+ 可选尾空格回退。防错：①循环体必须有 nI>255 EXIT 守卫（否则越界读）②sIn[nI] 下标 1-based，初值 nI:=1 ③去尾空格只回退到 >=1，不能到 0 以下。"),
 ("FC_DL_StringLeftEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "left"], 3,
  "nCount 越界钳位（<=0 返回空串、>长度返回全串）",
  "请求长度超实际长度（显式标记非完全满足）",
  "条码/工单号取前缀，nCount 来自配方参数可能为 0 或大于串长。要求：nCount<=0 返回空串置 0004，nCount>len 返回全串置 0001，bValid 反映是否完全满足。",
  "四段式：①参数检查 ②实际长度扫描（内联 len 逻辑，不调用本库其他 FC 以免跨依赖）③逐字符复制 + 目标串尾部置 $00 ④错误码归并。防错：复制后必须显式写 sResult[nI]:=$00 终结，否则残留旧内容。"),
 ("FC_DL_StringRightEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "right"], 3,
  "nCount 越界钳位",
  "请求长度超实际长度（显式标记非完全满足）",
  "取批次号后缀与流水号末位，nCount 可能超长。要求与 StringLeftEx 对称的钳位与有效性语义。",
  "同 StringLeftEx 四段式，起点由 len-nCount+1 计算，前置钳位保证 >=1。防错：len 与 nCount 同为 INT，减法前先判 nCount>len 避免负数下标。"),
 ("FC_DL_StringConcatEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "concat", "truncate-flag"], 4,
  "入参空串处理",
  "超 255 显式截断并置 bTruncated",
  "拼装设备号+工位号+时间戳，总长经常超 255；直接用 CONCAT 会静默回夹，导致上位机收到错位字符串且无任何告警（历史缺陷）。要求：超长时截断到 255 并显式置 bTruncated=TRUE、uErrorId=0002、bValid=FALSE。",
  "四段式：①两段有效长度扫描 ②总长预判 ③逐字符搬移（前段后段，双守卫）④截断标志显式置位。防错：bTruncated 必须在 VAR_OUTPUT 声明且每拍先复位为 FALSE 再判（单拍语义），不得只置不销。"),
 ("FC_DL_StringInsertEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "insert"], 4,
  "插入位置越界钳位（<1 钳 1、>len+1 钳 len+1）",
  "结果超 255 截断",
  "在报文指定位置插入校验字段，nPos 由上位机传入可能为 0 或超大。要求：位置钳位后插入，超长截断并置标志，绝不越界写。",
  "四段式：①位置与长度检查 ②三段搬移（前/插入/后）③$00 终结 ④错误码归并。防错：①插入位置合法域是 [1, len+1]（len+1 表示追加）②三段搬移各自独立越界守卫 ③目标下标必须 <=255。"),
 ("FC_DL_StringDeleteEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "delete"], 4,
  "nPos/nCount 越界钳位",
  "删除区间超串尾（截到串尾并置非完全满足）",
  "剔除报文中的冗余段，nPos+nCount 常越界。要求：nPos<1 钳 1，nCount<=0 原样返回置 0004，越尾截到串尾置 0001。",
  "四段式：①参数检查（含 nCount<=0 短路）②区间裁剪 ③前段保留 + 后段前移 ④$00 终结与错误码。防错：后段前移必须按新下标逐字符重算，不能用同一循环变量复用旧值。"),
 ("FC_DL_StringFindEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "find"], 5,
  "起点越界/空针返回 0",
  "无需故障码（未找到不是错误）",
  "报文关键字定位（找 ETX、找分隔符），nStart 用于跳过已处理段。要求：返回 1-based 首次位置，未找到返回 0 且不置错误；空针返回 0 置 0004。",
  "双层循环：外层 i 从 nStart 到 len-lenN+1，内层 j 逐字符比对，内层失配立即 EXIT 且外层 i 前进 1（不能漏回退或原地打转）。防错：①外层上界必须减 lenN 防越界读 ②匹配成功立即 RETURN ③空针必须先判，否则 lenN=0 会死循环。"),
 ("FC_DL_StringReplaceAtEx", ["iec-std-wrapper", "iec-std-string", "t0-string", "replace-at"], 4,
  "nPos 越界与替换段截断",
  "替换段被串尾截断（显式置标志）",
  "按固定偏移改写报文中的状态字（定长覆盖，总长不变），与全局替换语义不同。要求：从 nPos 起用 sRep 覆盖，覆盖长度受串尾限制，被截时置 bTruncated。",
  "四段式：①位置检查 ②覆盖长度=MIN(repLen, len-nPos+1) ③逐字符覆盖（不扩总长）④$00 终结与标志。防错：①总长不变是硬约束（覆盖不是插入）②nPos>len 时原样返回并置 0001，不得写越界。"),
]

def main():
    out = []
    for idx, (name, tags, cx, info_d, fault_d, instr, arch) in enumerate(ITEMS):
        info_code = INFO_BASE + idx
        fault_code = FAULT_BASE + idx
        seg = f"16#0001_{info_code:04X}(信息级：{info_d})"
        if fault_d and fault_d != "无需故障码（未找到不是错误）":
            seg += f" / 16#0001_{fault_code:04X}(故障级：{fault_d})"
        out.append({
            "name": name, "category": "DL_MathData", "type": "FC",
            "file_path": rf"C:\Library\DL_MathData\{name}.st",
            "function_tags": tags, "complexity": cx,
            "code_segment": seg,
            "instruction": instr, "architecture_thought": arch,
        })
    man = {"reg_version": "2.4.0", "items": out}
    p = r"C:\Library\_Staging_Raw\2026-11-16\manifest_r15.json"
    json.dump(man, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"[OK] manifest {len(out)} items -> {p}")
    for it in out:
        print(" ", it["name"], "|", it["code_segment"][:34])

if __name__ == "__main__":
    main()
