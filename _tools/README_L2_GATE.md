# L2 真编译闸（RuSTy）—— 使用与裁定口径

> 建立于第 R71 轮（2026-11-22）。此前 L1（机检 dl_gate 文本级）→ L2（真编译器语义级）之间
> 欠账连续 8 轮，本轮落地。本文档是闸门的唯一操作说明，**不属于代码库交付物**，不入 INDEX_REGISTRY。

## 1. 为什么是 RuSTy

| 候选 | 结论 |
|---|---|
| MatIEC (`iec2c`) | 官方无 Windows 预编译包，本机无 C 工具链，无法构建 → 放弃 |
| CODESYS / TwinCAT CLI | 闭源商业授权，不适合作为开源库的公开闸门 |
| **RuSTy (`plc.exe`)** | PLC-lang 开源项目（Apache-2.0），单文件 Windows x64 可执行，支持 `--check` 仅语义检查 → **采用** |

版本：`1.0.8 (Fri Nov 6 12:58:47 2026 +0100, d1f14ee)`，落盘 `_tools\rusty\plc.exe`。

## 2. 本机依赖坑（已解决，勿重踩）

`plc.exe` 是 MSVC 目标产物，导入表要求：

- `MSVCP140.dll` / `VCRUNTIME140.dll` / `VCRUNTIME140_1.dll`
- 10 个 `api-ms-win-crt-*.dll` UCRT API-set 转发库

本机 System32 **缺全部 `api-ms-win-crt-*` 且缺 vcruntime140**（`ucrtbase.dll` 在，但转发库不在）。
直接运行报 `api-ms-win-crt-locale-l1-1-0.dll 缺失`，退出码 127。

**解法（app-local 免安装，无需管理员）**：
1. 下载 `https://aka.ms/vs/17/release/vc_redist.x64.exe`（≈25 MB）。
2. 该文件是 WiX burn 包，内嵌两段 CAB。用 Python 定位第二个 `MSCF`（主载荷）切出 `.cab`。
3. `expand -F:* vcr_main.cab out` → 得 `a0..a13`；对 `a1..a8,a11..a13` 再 `expand` →
   得 `msvcp140.dll_amd64` / `vcruntime140.dll_amd64` / `vcruntime140_1.dll_amd64`
   与 `Windows6.1-KB2999226-x64.cab`。
4. 展开 KB2999226 cab → `amd64_microsoft-windows-u..rsalcrt-apifwd-win7_*` 目录内有全部
   15 个 `api-ms-win-crt-*.dll`。
5. 把上述 DLL 全部拷到 `_tools\rusty\`（与 plc.exe 同目录，app-local 解析优先）。

验证：`_tools\rusty\plc.exe --version` → `1.0.8 (...)`。

## 3. 标准件声明桩 `iec_std_stub.st`

RuSTy 不内建 IEC 标准函数/标准 FB 的声明，裸编译会把 `ABS` / `TON` / `R_TRIG` 判为
`E048 Could not resolve reference` / `E052 Unknown type`。方案：`{external}` 声明桩
（泛型 `ANY_NUM` / `ANY_ELEM` 表达，含 15 类数学、9 字符串、位串、32 条类型转换、
9 个标准 FB 空体声明）。**桩只声明接口、不含实现，不改变任何被检源码。**

## 4. 运行方式

```bash
python C:\Library\_tools\l2_check.py --sample 20 --seed 71 --out out.json   # 随机抽样
python C:\Library\_tools\l2_check.py C:\Library\DL_MathData\FC_DL_Xxx.st     # 指定件
```

`l2_check.py` 行为：
1. 恒附加 `iec_std_stub.st`；
2. **接口预筛**：先逐件自检 `I_DL_*.st`，只把自身能过的纳入依赖集（见 §5）；
3. **依赖回溯**：按报错里的 `Unknown type: X` / `Could not resolve reference to X`
   到 registry 直查同名组件取文件，未命中再全库扫定义形态，最多 3 轮；
4. 只做 `--check`，不生成目标码，不修改任何源文件。

## 5. 已知覆盖面缺口（假阳性来源，勿据此改码）

| 现象 | 归因 | 处理 |
|---|---|---|
| `E006 Missing expected Token KeywordEndInterface` / `E007 ... found PROPERTY` | RuSTy 对 `INTERFACE` 内 `PROPERTY` 支持不全；而 PROPERTY 是 IEC 61131-3 第 3 版**合法**语法，全库 21 个 `I_DL_*` 均用此形态 | 预筛排除，依赖该接口的件标为「编译器覆盖面缺口」，**不改库内代码**（改则破坏标准合规与 CODESYS/TwinCAT 可移植性） |

## 6. 首轮基线（R71，seed=71，n=20）

- **PASS 16 / FAIL 4（80%）**，4 例全为上述 PROPERTY 接口缺口。
- 结论：存量 1,199 件在语义层无成批硬错；L2 闸可作为后续每轮新增件的交付资格项。

## 7. 后续节律

- 每轮新增/修改件：**逐件 `--check` 必须 PASS**（或命中 §5 缺口并注明）；
- 全库抽样：每天最多 1 次（与「机检只扫增量」同口径），`--seed` 取当日日期保证可复现；
- 抽样 FAIL 且不属 §5 缺口的，登记 R 编号入 ROADMAP 返修账，不得沉默。
