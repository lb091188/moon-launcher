// moon-launcher v1 · 批次二：无边框 + 键盘流 + 多数据源 + 托盘 + 单实例。
// - 无边框窗，输入框常驻焦点（显式 focus_id + 在 on_key 外层拦截 ↑↓/Esc）
// - 选中态：selected_id 驱动行高亮（主题色），默认选中第一条；↑↓ 移动，回车启动选中项
// - Esc：有查询词先清空，空查询退出
// - 数据源：已装应用 + 浏览器书签 + 浏览历史（@sys 的 appfind / bm_ / bh_）
// - 托盘：Linux SNI，点击唤回主窗口；单实例：DBus 名独占，二次启动 Wake 唤醒首实例
// - 已知边界：发布包 0.1.1 无 Window::hide，Esc 是「清空→退出」而非隐藏驻留（待库下一版）

const INPUT_FOCUS_ID : Int = 101

const APP_DBUS_ID : String = "io.github.lb091188.moon-launcher"

const RESULT_LIMIT : Int = 9

///| 结果条目：三源统一形态。url 非空走 open_url，否则 exec 解析后启动。
struct LItem {
  id : String
  title : String
  sub : String
  url : String
  exec : String
}

///| 前缀命中：大小写折算后逐字符比较。
fn starts_fold(hay : String, needle : String) -> Bool {
  if hay.length() < needle.length() {
    return false
  }
  let h = @sys.bh_lower_ascii(hay)
  let n = @sys.bh_lower_ascii(needle)
  for i in 0..<n.length() {
    if h[i] != n[i] {
      return false
    }
  }
  true
}

///| 评分：0 不命中；3 标题前缀；1 标题 / 副题 / 地址包含；空查询给 1（全量默认列表）。
fn score_of_item(it : LItem, q : String) -> Int {
  if q.length() == 0 {
    return 1
  }
  if starts_fold(it.title, q) {
    return 3
  }
  if @sys.bh_contains_fold(it.title, q) ||
    @sys.bh_contains_fold(it.sub, q) ||
    @sys.bh_contains_fold(it.url, q) {
    return 1
  }
  0
}

fn id_in(seen : Array[String], id : String) -> Bool {
  for s in seen {
    if s == id {
      return true
    }
  }
  false
}

///| 按 id 去重（跨浏览器 / 多 profile 的重复书签与历史）。
fn dedup_by_id(items : Array[LItem]) -> Array[LItem] {
  let seen : Array[String] = []
  let out : Array[LItem] = []
  for it in items {
    if !id_in(seen, it.id) {
      seen.push(it.id)
      out.push(it)
    }
  }
  out
}

fn take_items(items : Array[LItem], limit : Int) -> Array[LItem] {
  let out : Array[LItem] = []
  for i in 0..<items.length() {
    if i >= limit {
      break
    }
    out.push(items[i])
  }
  out
}

///| 已装应用（appfind）：本地化名优先。
fn load_apps() -> Array[LItem] {
  let out : Array[LItem] = []
  match @sys.appfind_installed() {
    Ok(entries) =>
      for e in entries {
        let title = if e.locale_name.length() > 0 {
          e.locale_name
        } else {
          e.name
        }
        out.push({ id: "app:" + e.id, title, sub: app_sub(e), url: "", exec: e.exec })
      }
    Err(_) => ()
  }
  out
}

///| 应用副标题：前两个分类，没有分类回退 desktop id。
fn app_sub(e : @sys.AppEntry) -> String {
  if e.categories.length() == 0 {
    return e.id
  }
  let buf = StringBuilder()
  let n = if e.categories.length() < 2 { e.categories.length() } else { 2 }
  for i in 0..<n {
    if i > 0 {
      buf.write_string(" / ")
    }
    buf.write_string(e.categories[i])
  }
  buf.to_string()
}

///| 书签根的中文名。
fn bm_root_label(root : String) -> String {
  match root {
    "bookmark_bar" => "书签栏"
    "other" => "其他"
    "synced" => "同步"
    _ => "书签"
  }
}

///| 浏览器书签：全部已探测 profile 展平，按 url 去重。
fn load_bookmarks() -> Array[LItem] {
  let out : Array[LItem] = []
  match @sys.bm_browsers() {
    Ok(profiles) =>
      for p in profiles {
        match @sys.bm_bookmarks(p.browser) {
          Ok(root) =>
            for node in @sys.bm_flatten(root) {
              match node.url {
                Some(u) =>
                  if u.length() > 0 {
                    let title = if node.name.length() > 0 { node.name } else { u }
                    out.push({
                      id: "bm:" + p.browser + ":" + u,
                      title,
                      sub: "书签 · " + bm_root_label(node.root),
                      url: u,
                      exec: "",
                    })
                  }
                None => ()
              }
            }
          Err(_) => ()
        }
      }
    Err(_) => ()
  }
  dedup_by_id(out)
}

///| 浏览历史：按最近访问时间降序取前 120，按 url 去重。
fn load_history() -> Array[LItem] {
  let out : Array[LItem] = []
  match @sys.bh_history(limit=120) {
    Ok(items) =>
      for it in items {
        if it.url.length() == 0 {
          continue
        }
        let title = if it.title.length() > 0 { it.title } else { it.url }
        out.push({
          id: "hi:" + it.url,
          title,
          sub: "历史 · 访问 " + it.visit_count.to_string() + " 次",
          url: it.url,
          exec: "",
        })
      }
    Err(_) => ()
  }
  dedup_by_id(out)
}

///| 空查询的默认列表：应用按显示名字典序。
fn sorted_default(apps : Array[LItem], limit : Int) -> Array[LItem] {
  let copy : Array[LItem] = []
  for a in apps {
    copy.push(a)
  }
  copy.sort_by(fn(a : LItem, b : LItem) -> Int {
    if a.title < b.title {
      -1
    } else {
      1
    }
  })
  take_items(copy, limit)
}

///| 命中列表：评分降序、标题字典序、id 字典序稳定。
fn top_matches(all : Array[LItem], q : String, limit : Int) -> Array[LItem] {
  let scored : Array[(Int, LItem)] = []
  for it in all {
    let s = score_of_item(it, q)
    if s > 0 {
      scored.push((s, it))
    }
  }
  scored.sort_by(
    fn(a : (Int, LItem), b : (Int, LItem)) -> Int {
      if a.0 != b.0 {
        b.0 - a.0
      } else if a.1.title < b.1.title {
        -1
      } else if a.1.title > b.1.title {
        1
      } else if a.1.id < b.1.id {
        -1
      } else {
        1
      }
    },
  )
  let out : Array[LItem] = []
  for i in 0..<scored.length() {
    if i >= limit {
      break
    }
    out.push(scored[i].1)
  }
  out
}

///| 从 Exec 串取（程序， 参数）：按空白拆词、剔除 % 字段码，首词为程序，
/// 其余以空格拼回。现状口径：不做引号处理。
fn exec_of(exec : String) -> (String, String) {
  let prog = Ref("")
  let args = Ref("")
  for piece in exec.split(" ") {
    let t = piece.to_owned()
    if t.length() == 0 || t[0] == '%' {
      continue
    }
    if prog.val.length() == 0 {
      prog.val = t
    } else if args.val.length() == 0 {
      args.val = t
    } else {
      args.val = args.val + " " + t
    }
  }
  (prog.val, args.val)
}

fn counts_text(apps : Int, bm : Int, hi : Int) -> String {
  "应用 " +
  apps.to_string() +
  " · 书签 " +
  bm.to_string() +
  " · 历史 " +
  hi.to_string()
}

///|
fn main {
  // —— 单实例：DBus 名独占；第二实例唤醒首实例后退出；无会话总线则跳过 ——
  match @dbus.claim_name(APP_DBUS_ID) {
    Ok(claim) =>
      match claim {
        @dbus.AlreadyExists => {
          let _ = @dbus.wake_existing(APP_DBUS_ID, ["toggle"])
          println("LAUNCHER-WAKE: 已唤起既有实例，本进程退出")
          return
        }
        _ => ()
      }
    Err(_) => ()
  }

  // —— 数据源 ——
  let apps = load_apps()
  let bookmarks = load_bookmarks()
  let history = load_history()
  let all : Array[LItem] = []
  for it in apps {
    all.push(it)
  }
  for it in bookmarks {
    all.push(it)
  }
  for it in history {
    all.push(it)
  }
  let counts = counts_text(apps.length(), bookmarks.length(), history.length())

  // —— 状态 ——
  let first = sorted_default(apps, RESULT_LIMIT)
  let query = @core.Store::new("")
  let results = @core.ListStore::new(init=first)
  let selected_id = @core.Store::new(if first.length() > 0 { first[0].id } else { "" })
  let status = @core.Store::new(counts + " · 显示 " + first.length().to_string() + " 条")

  let app_ref : Ref[@core.App?] = Ref(None)
  let focus_input = fn() {
    match app_ref.val {
      Some(app) => {
        let _ = app.focus.focus(INPUT_FOCUS_ID)
        ()
      }
      None => ()
    }
  }
  let show_window = fn() {
    match app_ref.val {
      Some(app) => {
        app.window.show()
        app.window.request_focus()
        let _ = app.focus.focus(INPUT_FOCUS_ID)
        app.schedule_paint()
        ()
      }
      None => ()
    }
  }

  // 首实例的唤起入口：第二实例 Wake（含托盘点击复用同一动作）
  @dbus.on_wake(fn(_args : Array[String]) { show_window() })

  let launch : (LItem) -> Unit = fn(it : LItem) {
    if it.url.length() > 0 {
      match @sys.open_url(it.url) {
        Ok(_) => status.set("已打开 " + it.title)
        Err(_) => status.set("打开失败 " + it.title)
      }
    } else {
      let (prog, args) = exec_of(it.exec)
      if prog.length() == 0 {
        status.set("无可执行项：" + it.title)
        return
      }
      match @sys.spawn_detached(prog, args) {
        Ok(_) => status.set("已启动 " + it.title)
        Err(msg) => status.set("启动失败 " + it.title + "：" + msg)
      }
    }
    focus_input()
  }

  let refresh : (String) -> Unit = fn(q : String) {
    let top = if q.length() == 0 {
      sorted_default(apps, RESULT_LIMIT)
    } else {
      top_matches(all, q, RESULT_LIMIT)
    }
    results.splice(0, results.length(), top)
    selected_id.set(if top.length() > 0 { top[0].id } else { "" })
    if q.length() > 0 && top.length() == 0 {
      status.set("无匹配，换个关键词")
    } else {
      status.set(counts + " · 显示 " + top.length().to_string() + " 条")
    }
  }

  let move_sel : (Int) -> Unit = fn(delta : Int) {
    let cur = results.get()
    if cur.length() == 0 {
      return
    }
    let sel = selected_id.get()
    let mut idx = 0
    for i in 0..<cur.length() {
      if cur[i].id == sel {
        idx = i
      }
    }
    idx = idx + delta
    if idx < 0 {
      idx = 0
    }
    if idx >= cur.length() {
      idx = cur.length() - 1
    }
    selected_id.set(cur[idx].id)
  }

  let on_enter_cb : () -> Unit = fn() {
    let cur = results.get()
    let sel = selected_id.get()
    for it in cur {
      if it.id == sel {
        launch(it)
        return
      }
    }
    if cur.length() > 0 {
      launch(cur[0])
    } else {
      status.set("没有可启动的条目")
    }
  }

  let on_esc : () -> Unit = fn() {
    if query.get().length() > 0 {
      query.set("")
      refresh("")
    } else {
      match app_ref.val {
        Some(app) => app.quit()
        None => ()
      }
    }
  }

  let row_body = fn(it : LItem, active : Bool) -> @core.Node {
    @ui.col(
      [
        @ui.text(
          it.title,
          font_size=14.0,
          weight=@text.SemiBold,
          color=if active { "" } else { "" },
        ),
        @ui.text(it.sub, font_size=11.0, color="#888888"),
      ],
      row_gap=2.0,
      padding=8.0,
      background_color=if active { @theme.theme_primary_light() } else { "" },
      border_color=if active { @theme.theme_primary() } else { "" },
      handle=fn(w : @core.Widget) {
        w.on_pointer = Some(
          fn(self : @core.Widget, ev : @core.PointerEvent) -> Bool {
            match ev.kind {
              @core.Down => true
              @core.Up => {
                let inside = ev.x >= 0.0 &&
                  ev.x <= self.rect.w &&
                  ev.y >= 0.0 &&
                  ev.y <= self.rect.h
                if inside {
                  launch(it)
                }
                false
              }
              _ => false
            }
          },
        )
      },
    )
  }

  let row_of : (LItem) -> @core.Node = fn(it : LItem) {
    @ui.when_else_store(
      selected_id,
      row_body(it, true),
      row_body(it, false),
      pred=fn(v : String) -> Bool { v == it.id },
    )
  }

  let app = match @ui.mount_window(
      [
        @ui.col(
          [
            @ui.input(
              query,
              placeholder="搜索应用 / 书签 / 历史，↑↓ 选择，回车启动，Esc 清空或退出",
              focus_id=INPUT_FOCUS_ID,
              width=528.0,
              on_change=refresh,
              on_enter=on_enter_cb,
              handle=fn(w : @core.Widget) {
                let orig = w.on_key
                w.on_key = Some(
                  fn(ev : @core.KeyEvent) -> Bool {
                    if ev.press {
                      if ev.keysym == @core.KS_DOWN {
                        move_sel(1)
                        return true
                      }
                      if ev.keysym == @core.KS_UP {
                        move_sel(-1)
                        return true
                      }
                      if ev.keysym == @core.KS_ESCAPE {
                        on_esc()
                        return true
                      }
                    }
                    match orig {
                      Some(f) => f(ev)
                      None => false
                    }
                  },
                )
              },
            ),
            @ui.col(
              [
                @ui.for_list(
                  results,
                  fn(it : LItem, _i : Int) -> @core.Node { row_of(it) },
                  key=fn(it : LItem) -> String { it.id },
                ),
              ],
              row_gap=4.0,
            ),
            @ui.text_dyn(status.signal(), font_size=11.0, color="#888888"),
          ],
          row_gap=10.0,
          padding=16.0,
        ),
      ],
      title="moon-launcher",
      width=560,
      height=520,
      handle=fn(app : @core.App) {
        app_ref.val = Some(app)
        app.window.set_borderless(true)
        let _ = app.focus.focus(INPUT_FOCUS_ID)
        if @core.Tray::is_supported() {
          match @core.Tray::new("moon-launcher") {
            Ok(tray) => {
              tray.set_icon_name("system-search")
              tray.set_tooltip("moon-launcher", "点击显示主窗口")
              tray.on_click(fn() { show_window() })
            }
            Err(_) => ()
          }
        }
      },
    ) {
    None => {
      println("LAUNCHER-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  refresh("")
  app.run()
}
