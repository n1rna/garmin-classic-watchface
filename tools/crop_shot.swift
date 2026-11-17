// Crop the watch render out of a Connect IQ simulator window capture and make
// the white background around the watch transparent.
// usage: swift tools/crop_shot.swift <in.png> <out.png>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3,
      let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("usage: crop_shot <in.png> <out.png>")
}
let W = cg.width, H = cg.height
var px = [UInt8](repeating: 0, count: W * H * 4)
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * W + x) * 4
    return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
}
func white(_ p: (Int, Int, Int)) -> Bool { p.0 > 248 && p.1 > 248 && p.2 > 248 }
func black(_ p: (Int, Int, Int)) -> Bool { p.0 < 8 && p.1 < 8 && p.2 < 8 }

// panel = white area on the left (title bar on top, black LCD-preview area on the right)
var top = 0
while top < H && !white(at(4, top)) { top += 1 }
var bottom = top
while bottom < H && white(at(4, bottom)) { bottom += 1 }
let mid = (top + bottom) / 2
var right = W - 12   // skip the window border
while right > 0 && black(at(right, mid)) { right -= 1 }
while right > 0 && !white(at(right, mid)) { right -= 1 }   // panel divider
let left = 4
let cw = right + 1 - left, ch = bottom - top

// flood-fill the white background from the panel corners -> transparent
var seen = [Bool](repeating: false, count: W * H)
var stack: [(Int, Int)] = [(left, top + 1), (right, top + 1), (left, bottom - 2), (right, bottom - 2)]
while let (x, y) = stack.popLast() {
    if x < left || y < top || x > right || y >= bottom { continue }
    let k = y * W + x
    if seen[k] { continue }
    let p = at(x, y)
    if !(p.0 > 236 && p.1 > 236 && p.2 > 236) { continue }
    seen[k] = true
    px[k * 4] = 0; px[k * 4 + 1] = 0; px[k * 4 + 2] = 0; px[k * 4 + 3] = 0
    stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
}

let full = ctx.makeImage()!
let crop = full.cropping(to: CGRect(x: left, y: top, width: cw, height: ch))!
let rep = NSBitmapImageRep(cgImage: crop)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("\(args[2]): \(cw)x\(ch)")
