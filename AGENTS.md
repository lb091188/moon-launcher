# AGENTS.md — moon-launcher AI 协作规则

moon-launcher（`NoahLiu/moon-launcher`）：轻量原生跨平台桌面启动器，[native-gui](https://github.com/lb091188/moonbit-native-gui) 的旗舰应用。宿主自绘，插件为子进程，只生产数据与动作。

## 硬性规则

1. **与用户交流、提交信息全部中文**；提交沿用「【标签】范围：说明」格式，主题行百字上下：改动一句 + 验证一句。
2. **门禁**：`moon check` 零错误零警告、`moon build --target native` 通过方可提交；启动冒烟（进程存活 + 退出行为）允许在本机做，视觉与交互验证一律给操作步骤清单由用户真机执行并等待反馈。
3. **依赖一律来自 mooncakes 注册表**（`NoahLiu/native-gui` / `NoahLiu/yoga-mbt`），本仓库存在的意义之一就是持续自证「`moon add` 后零配置可跑」。跨仓库联调需要消费库的未发布改动时，本地写 `moon.work` 把 `../moonbit-native-gui/gui` 挂为路径成员——**该文件不入库**，提交前删除。
4. **协议当资产**：改 `PROTOCOL.md` 必须评估是否递增 `protocol` 版本；不兼容变更必须附迁移说明。`protocol = 1` 冻结前只加指令行、不加字段。
5. **两条架构红线不许破**：插件只给意图不给像素；即时交互本地化、语义事件上行。任何「让插件画界面 / 每次按键跨进程」的提议都先对照红线。
6. **路线图阶段纪律**：v1（内置命令 + 子进程行协议）→ v2（声明式 UI）→ v3（Vue 子集转译）。v3 编译器动工的前置条件：v2 视图 schema 已被真实插件使用并冻结。

## 常用命令

```sh
moon check                    # 静态检查（零错误零警告）
moon build --target native    # 构建
moon run . --target native    # 运行（需显示服务）
```

## 文档地图

- 插件协议（本仓库核心资产）：`PROTOCOL.md`
- 路线图与定位：`README.md`
- GUI 库本体与适配经验：https://github.com/lb091188/moonbit-native-gui
