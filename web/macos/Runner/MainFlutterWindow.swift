import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSMakeSize(1280, 800)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Core Keeper Dedicated Server Manager"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
