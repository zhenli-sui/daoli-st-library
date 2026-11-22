# 编译验证工程师 · 进化账本（COMPILE_VERIFIER_EVOLUTION）

> 归口：编译验证工程师（daoli-compile-verifier）
> 工具：本地 RuSTy 1.0.8（_tools\rusty\plc.exe，Apache-2.0）+ 声明桩 iec_std_stub.st；CI 侧 MatIEC（.github/workflows/iec-compile.yml）
> 权限：**入库一票否决**

## 一、运行状态
| 项 | 值 |
|---|---|
| 本地真编译引擎 | RuSTy 1.0.8（已验证可用） |
| 云端真编译引擎 | MatIEC（CI workflow 就绪，**待配 git remote 方可触发**） |
| 本机 C 工具链 | 全缺（gcc/bison/flex/make 均无）→ MatIEC 无法本地构建 |
| 上次固化轮次 | — |
| 累计新增规则 | 0 |

## 二、沉淀格式（每轮 ≤5 条）
```
[R<轮次>] <类型> | <现象> | <教训> | <规则编号或观察项>
```
类型枚举：`方言缺口` / `假阳性` / `假阴性` / `桩维护` / `豁免升级` / `工具链`

## 三、已沉淀条目
_（等待 R73 起写入。首批应记录：R71 抽检 20 件中 E006 Missing expected Token 的具体成因归类、INTERFACE PROPERTY 缺口的稳定判据）_

## 四、编译器缺口台账（假阳性豁免依据）
| 错误码 | 现象 | 是否合法 IEC 语法 | 处理 | 连续豁免轮数 |
|---|---|---|---|---|
| E006/E007 | INTERFACE 内 PROPERTY 不被支持 | 是（第3版合法） | 逐件豁免留档 | 待累计 |
| E048/E052 | 未声明标准函数（ABS/TON/R_TRIG 等） | 桩已覆盖 | 附加 iec_std_stub.st | — |

## 五、MatIEC 本地化可行方案（持续维护）
1. 下载 w64devkit（单文件 zip，含 gcc/make/binutils）或 MSYS2 基础包；
2. 补 bison + flex（w64devkit 不含，需单独构建或取预编译）；
3. `git clone https://github.com/beremiz/matiec && autoreconf -i && ./configure && make`；
4. 风险：matiec 依赖 POSIX 路径与 libtool，MSYS2 成功率高、纯 MinGW 需打补丁。
5. 备选：配 git remote 让 CI 跑 MatIEC（云端 Ubuntu 一条 apt 命令即可）。

## 六、进化纪律
1. 每轮 ≤5 条；豁免必须逐件列名，同一错误码连续 3 轮豁免 → 升级 P0 必须解决。
2. 通过率 < 90% 必须在战报顶部标红，不得隐藏。
3. 禁止用"命中已知缺口"作为放过新缺陷的借口。
