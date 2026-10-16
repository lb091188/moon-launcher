// moon-launcher v1 · 批次一：搜索壳 + 已装应用数据源。
// 输入即筛（前缀优先于包含），Enter 启动第一条，点击行启动对应应用，
// 状态行回报索引量与启动结果。后续批次（方向键选中/托盘/热键/更多数据源）
// 见 README 路线图。

///| 显示名：本地化名优先于 Name。
fn entry_title(e : @sys.AppEntry) -> String {
  if e.locale_name.length() > 0 {
    e.locale_name
  } else {
    e.name
  }
}

///| 副标题：前两个分类，没有分类回退 desktop id。
fn entry_subtitle(e : @sys.AppEntry) -> String {
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

///| 匹配评分：0 不命中；3 显示名前缀；2 Name 前缀；1 包含（显示名或 Exec）；
/// 空查询给 1（全量参与，按显示名排序取前若干当默认列表）。
fn score_of(e : @sys.AppEntry, q : String) -> Int {
  if q.length() == 0 {
    return 1
  }
  let title = entry_title(e)
  if starts_fold(title, q) {
    return 3
  }
  if starts_fold(e.name, q) {
    return 2
  }
  if @sys.bh_contains_fold(title, q) || @sys.bh_contains_fold(e.exec, q) {
    return 1
  }
  0
}

///| 取前 limit 条：评分降序、显示名字典序稳定。
fn top_matches(
  apps : Array[@sys.AppEntry],
  q : String,
  limit : Int,
) -> Array[@sys.AppEntry] {
  let scored : Array[(Int, @sys.AppEntry)] = []
  for e in apps {
    let s = score_of(e, q)
    if s > 0 {
      scored.push((s, e))
    }
  }
  scored.sort_by(fn(a : (Int, @sys.AppEntry), b : (Int, @sys.AppEntry)) -> Int {
    if a.0 != b.0 {
      b.0 - a.0
    } else if entry_title(a.1) < entry_title(b.1) {
      -1
    } else {
      1
    }
  })
  let out : Array[@sys.AppEntry] = []
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

///|
fn main {
  // 应用索引：启动扫一次；平台不支持给空表，状态行说明
  let apps : Array[@sys.AppEntry] = match @sys.appfind_installed() {
    Ok(a) => a
    Err(_) => []
  }
  let apps_note = if apps.length() > 0 {
    ""
  } else {
    "（本平台暂不支持应用索引）"
  }
  let first = top_matches(apps, "", 9)
  let query = @core.Store::new("")
  let results = @core.ListStore::new(init=first)
  let status = @core.Store::new(
    "已索引 " +
    apps.length().to_string() +
    " 个应用" +
    apps_note +
    " · 显示 " +
    first.length().to_string() +
    " 条",
  )

  let launch : (@sys.AppEntry) -> Unit = fn(e : @sys.AppEntry) {
    let (prog, args) = exec_of(e.exec)
    if prog.length() == 0 {
      status.set("无可执行项：" + entry_title(e))
      return
    }
    match @sys.spawn_detached(prog, args) {
      Ok(_) => status.set("已启动 " + entry_title(e))
      Err(msg) => status.set("启动失败 " + entry_title(e) + "：" + msg)
    }
  }

  let refresh : (String) -> Unit = fn(q : String) {
    let top = top_matches(apps, q, 9)
    results.splice(0, results.length(), top)
    if q.length() > 0 && top.length() == 0 {
      status.set("无匹配，换个关键词")
    } else {
      status.set(
        "已索引 " +
        apps.length().to_string() +
        " 个应用" +
        apps_note +
        " · 显示 " +
        top.length().to_string() +
        " 条",
      )
    }
  }

  let on_enter_cb : () -> Unit = fn() {
    let cur = results.get()
    if cur.length() > 0 {
      launch(cur[0])
    } else {
      status.set("没有可启动的条目")
    }
  }

  let row_of : (@sys.AppEntry) -> @core.Node = fn(e : @sys.AppEntry) {
    @ui.col(
      [
        @ui.text(entry_title(e), font_size=14.0, weight=@text.SemiBold),
        @ui.text(entry_subtitle(e), font_size=11.0, color="#888888"),
      ],
      row_gap=2.0,
      padding=8.0,
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
                  launch(e)
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

  let app = match @ui.mount_window(
      [
        @ui.col(
          [
            @ui.input(
              query,
              placeholder="搜索应用，回车启动第一条",
              on_change=refresh,
              on_enter=on_enter_cb,
            ),
            @ui.col(
              [
                @ui.for_list(
                  results,
                  fn(e : @sys.AppEntry, _i : Int) -> @core.Node { row_of(e) },
                  key=fn(e : @sys.AppEntry) -> String { e.id },
                ),
              ],
              row_gap=4.0,
            ),
            @ui.text_dyn(status.signal(), font_size=11.0, color="#888888"),
          ],
          row_gap=10.0,
          padding=14.0,
        ),
      ],
      title="moon-launcher",
      width=520,
      height=480,
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
