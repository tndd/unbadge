import Foundation
import ImageIO

// PNGをICNSの正式なサイズ別要素へ格納し、旧形式への変換で色が変わるのを避ける。
guard CommandLine.arguments.count == 3 else { exit(1) }
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let elements: [(String, String, Int)] = [
    ("icp4", "icon_16x16.png", 16), ("icp5", "icon_32x32.png", 32),
    ("icp6", "icon_32x32@2x.png", 64), ("ic07", "icon_128x128.png", 128),
    ("ic08", "icon_256x256.png", 256), ("ic09", "icon_512x512.png", 512),
    ("ic10", "icon_512x512@2x.png", 1024), ("ic11", "icon_16x16@2x.png", 32),
    ("ic12", "icon_32x32@2x.png", 64), ("ic13", "icon_128x128@2x.png", 256),
    ("ic14", "icon_256x256@2x.png", 512)
]
func integer(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var body = Data()
for (type, filename, size) in elements {
    let data = try Data(contentsOf: source.appendingPathComponent(filename))
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
          image.width == size, image.height == size else {
        fputs("アイコンの寸法またはPNG形式が不正です: \(filename)\n", stderr)
        exit(2)
    }
    body.append(Data(type.utf8))
    body.append(integer(data.count + 8))
    body.append(data)
}
var result = Data("icns".utf8)
result.append(integer(body.count + 8))
result.append(body)
try result.write(to: destination, options: .atomic)
