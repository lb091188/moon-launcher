// moon-launcher 入口：v0 壳——用发布包（moon add）出窗，自证「零配置 moon run」链路。
// 搜索界面与插件协议从 v1 批次开始落地（见 PROTOCOL.md 与 README 路线图）。

///|
fn main {
  let app = match @ui.mount_window(
    [
      @ui.text("moon-launcher", font_size=22.0),
      @ui.text("v0：发布链路自证（moon add → moon run 出窗）", font_size=12.0),
      @ui.text("v1 起接入搜索与插件协议，见 PROTOCOL.md", font_size=12.0),
    ],
    title="moon-launcher",
    width=480,
    height=200,
  ) {
    None => {
      println("LAUNCHER-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  app.run()
}
