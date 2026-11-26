# 云端看板同步规范（唯一权威版）

> 立规时间：2026-11-24 08:50 ｜ 创始人明确要求：「之后的改动请直接在这个资料库云端版本上更新」

## 一、权威版定义

| 项 | 值 |
|---|---|
| 云端节点 ID | `PUD2s8AwgtOg8otTa4Dyvl` |
| 链接 | https://www.workbuddy.cn/space/d/PUD2s8AwgtOg8otTa4Dyvl |
| 类型 | `web` 页面（kind=web） |
| 所属空间 | `7hdG5GrKqZnMHvi3p4eCTA` |
| 当前版本 | 1（2026-11-24 08:50 提交） |

**规则：云端节点是唯一权威版。** 本地 `C:\Library\_dashboard\index.html` 仅作源码草稿，任何改动必须提交到云端，不得只改本地就算完成。

## 二、为什么不能直接覆盖本地文件

云端页面被平台注入过 DOM 锚点（`data-page-node-id`、`<!--pnid:...-->`、`/page/page_comm/inject.js`），这些是**评论定位与元素编辑的依赖**。本地那份 41KB 文件没有这些属性，直接上传覆盖会丢失锚点，评论区与元素级编辑会失效。

所以流程必须是：**先拉云端 → 改 → 提交**，绝不能本地覆盖。

## 三、标准同步流程（3 步，必须按序）

```bash
SK="C:/Users/Administrator/AppData/Local/Programs/WorkBuddy/resources/app.asar.unpacked/resources/plugins/workbuddy-builtin/skills/library"

# 1. 拉取云端版本，建立本轮基线（会返回 work_dir 路径）
python3 "$SK/page/prepare_page_edit.py" --node-id PUD2s8AwgtOg8otTa4Dyvl
#    → KS_PAGE_EDIT_PREPARED {"work_dir":"...","paths":["index.html"],"baseVersion":N}

# 2. 只改 work_dir/index.html，然后预检（看 diff 是否只含本轮该改的内容）
python3 "$SK/page/finalize_page_edit.py" --check-only \
  --work-dir "<上一步的 work_dir>" --path index.html

# 3. 预检通过后提交（message ≤50 中文字符）
python3 "$SK/page/finalize_page_edit.py" \
  --work-dir "<work_dir>" --path index.html \
  --message "更新看板数据" [--pnid <目标元素 pnid>]
```

## 四、数据区刷新口径（每次同步必做）

看板数据集中在 `const DATA = { ... };`，字段与数据源对应：

| DATA 字段 | 数据源 | 口径 |
|---|---|---|
| `cats[].c` | `INDEX_REGISTRY.json` 按 `category` 计数 | 与 registry 严格一致，不用磁盘文件数 |
| `cats[].kids` | `function_tags` 聚合 | 取首个 tag 聚族，保留现有 6 大族结构 |
| `cmplx` | registry 的 `complexity` 字段 | 1~9 档计数 |
| `rounds` / `today` | `_Staging_Raw/<日期>/BATTLE_REPORT_R*.md` | 每轮新增数（不含修复件） |
| `stages[].ag` | 实际运行的 subagent 名 | **必须写真名**：团队包生效后用 `dlf-*`，未生效前用 `daoli-*`，不得写不存在的 ID |
| `stages[].stt` | 当日轮次战报 | 含轮次号与实际数字 |
| `experts[].path` | 专家包真实路径 | 团队包生效后指向 `daoli-lib-factory` 下的 `dlf-*.md` |
| `bottles` / `todos` | 当日 `DAILY_RETRO.md` | 瓶颈给量化依据，待办带优先级 |
| 页脚 | 同步时间 + registry 条数 + 今日数 | 每次同步必改 |

**一致性铁律**：页脚数字、`cats` 合计、registry 条数三者必须相等。不一致时以 registry 为准，并在页脚标注差异原因。

## 五、同步时机

1. **创始人提出看板改动** → 立即改云端，改完回复链接。
2. **每日末轮任务收尾** → 刷新一次数据区（当日累计、各轮产出、待办、瓶颈）。
3. 单轮内不重复同步（避免版本冲突与 60 分钟预算浪费）。

## 六、故障处理

- 提交报版本冲突 → 重新从 `prepare_page_edit.py` 开始，不得复用上一轮 work_dir 或上下文里的文件内容；同一任务连续 3 次冲突 → 停止并告知负责人「检测到并发编辑」。
- `--check-only` 报 lint 警告 → 先看是否本轮引入；历史存量警告不扩大范围顺手修。
- 预检 diff 出现本轮未要求的改动 → 一律回退，禁止提交夹带改动的版本。

## 七、不要做的事

1. 不把 `work_dir`、`.baseline/` 当产物上传或展示。
2. 不在看板里写 token、内部 URL、工具调用过程、本地绝对路径（专家 `path` 字段属展示用途，可保留）。
3. 不删除平台注入的 `data-page-node-id` 属性。
4. 不同步到发布态（该页面当前未发布；一旦发布，同步后需再问是否更新发布版本）。
