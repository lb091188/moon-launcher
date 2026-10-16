# moon-launcher 插件协议（protocol = 1）

## 设计原则

1. **协议当资产**：版本化；不兼容变更必须递增 `protocol` 并附迁移说明。
2. **一行一条**：默认档是制表符分隔的纯文本行，五行 bash 就能写一个插件。
3. **只传意图**：插件不给像素不给布局；渲染 / 主题 / 布局全部宿主负责。
4. **即时交互本地化**：滚动、悬停、输入过滤由宿主内建控件完成，跨进程只走语义事件。

## 插件清单 manifest.toml

每个插件目录一份：

```toml
name = "gh"             # 显示名
version = "0.1.0"
protocol = 1            # 遵循的本协议版本
triggers = ["gh"]       # 前缀激活；空数组 = 常驻结果列表
mode = "ondemand"       # ondemand: 每查询起一进程 | resident: 常驻
format = "tsv"          # tsv | toml（v2 起另有 views）
timeout_ms = 2000       # 超时即杀，本轮按无结果处理
command = "plugin.sh"   # 相对清单目录执行，可带固定参数
```

## v1 查询协议（TSV，默认档）

宿主 → 插件（stdin，逐行 UTF-8）：

```
q <关键词>           # 查询
e <动作id> [参数]    # 用户选中了插件回传的动作（cb:）
term                # 宿主即将关闭插件（仅 resident 档收得到）
```

插件 → 宿主（stdout，逐行）：

```
标题<TAB>副标题<TAB>图标<TAB>动作
```

- 字段允许留空（连续 TAB 即空字段）；`图标` 为图片路径或主题图标名。
- `#` 开头为指令行，v1 保留未定义。
- 动作语法：
  - `open:<url 或路径>`——宿主执行打开；
  - `cb:<动作id>`——回传插件：宿主向其 stdin 发 `e <动作id>`。
- 退出码：`0` 正常结束；非 `0` 视为「本轮无结果」并记录日志，不影响宿主。

### 示例：五行 bash 插件

```bash
#!/usr/bin/env bash
read -r line                 # q 关键词
case "$line" in
  q\ docs*) printf '打开文档\tREADME\t\topen:https://example.com/docs\n' ;;
  *)         printf '搜索 example\t%s\t\topen:https://example.com/?q=%s\n' "$line" "$line" ;;
esac
```

## 结构档（TOML 行）

`format = "toml"` 时启用。每行一个内联表，字段与 TSV 档同义：

```
item = { title = "打开仓库", sub = "GitHub", icon = "", act = "open:https://github.com" }
```

## v2 预留：视图 schema

- 插件声明视图树，词汇表为宿主控件集的有限子集（`column` / `list` / `text` / `input` / `button` / …）。
- 事件以 `event <view_id> <类型>` 回传插件；插件**整树重发**，宿主按 id 做 keyed diff。
- wasm 宿主复用同一 schema，传输从 stdio 行协议换成边界函数调用（宿主 import `render_view` / `emit_event`，插件 export `on_query` / `on_event`）。

## 与 Raycast script commands 的映射

| Raycast | 本协议 |
|---|---|
| shebang 注释里的元数据 | `manifest.toml` |
| stdout 逐行输出 | TSV 行 |
| argument placeholder | `q <关键词>` |

对齐目的：现有 Raycast 脚本命令补一份 manifest 即可迁移。

## 生命周期

- `ondemand`：查询即起，答案收完或超时即杀；
- `resident`：常驻；Esc 隐藏不杀，`term` 后杀；
- 插件崩溃 / 超时 / 被杀一律不影响宿主。
