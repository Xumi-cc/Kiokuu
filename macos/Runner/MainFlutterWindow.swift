import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    
    // Enable custom title bar with native traffic light buttons
    // This allows Flutter to render content in the title bar area
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    
    // Set minimum size for the window
    self.minSize = NSSize(width: 800, height: 600)
    
    // Make the window background match Flutter's background
    self.backgroundColor = NSColor.black
    self.isOpaque = false
  }
}
