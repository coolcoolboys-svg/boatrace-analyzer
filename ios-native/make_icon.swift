import AppKit
import ImageIO
import UniformTypeIdentifiers

let dir = URL(fileURLWithPath: "Sources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("icon context") }
ctx.setFillColor(CGColor(red: 0.12, green: 0.52, blue: 0.70, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
ctx.setFillColor(CGColor(red: 1, green: 0.75, blue: 0.27, alpha: 1))
ctx.move(to: CGPoint(x: 480, y: 440))
ctx.addLines(between: [CGPoint(x: 480, y: 440), CGPoint(x: 480, y: 780), CGPoint(x: 700, y: 440)])
ctx.closePath(); ctx.fillPath()
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.move(to: CGPoint(x: 180, y: 410))
ctx.addLines(between: [CGPoint(x: 180, y: 410), CGPoint(x: 842, y: 410), CGPoint(x: 735, y: 290), CGPoint(x: 300, y: 290)])
ctx.closePath(); ctx.fillPath()
ctx.setStrokeColor(CGColor(red: 0.65, green: 0.9, blue: 0.95, alpha: 1)); ctx.setLineWidth(18); ctx.setLineCap(.round)
for y in [210, 160] { ctx.move(to: CGPoint(x: 220, y: y)); ctx.addLine(to: CGPoint(x: 800, y: y)); ctx.strokePath() }
guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("icon.png") as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("icon output") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("icon write") }
let json = """
{"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
