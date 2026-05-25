#!/usr/bin/env swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let SIZE: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Icon-1024.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(SIZE),
    height: Int(SIZE),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("CGContext init failed") }

// Flip so y=0 is the top of the canvas (easier to reason about layout).
ctx.translateBy(x: 0, y: SIZE)
ctx.scaleBy(x: 1, y: -1)

// Jersey blue background.
let bgBlue = CGColor(red: 0x1E/255.0, green: 0x5F/255.0, blue: 0xBF/255.0, alpha: 1.0)
ctx.setFillColor(bgBlue)
ctx.fill(CGRect(x: 0, y: 0, width: SIZE, height: SIZE))

// Lift the bike+rider so it sits centered on the canvas (composition
// bounds run y=265..913 raw, ~77px below mid; 60 nudges it close to mid).
ctx.translateBy(x: 0, y: -60)

let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
ctx.setStrokeColor(black)
ctx.setFillColor(black)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// ── Geometry ──
let wheelR: CGFloat = 160
let rimW: CGFloat = 26
let rearHub  = CGPoint(x: 290, y: 740)
let frontHub = CGPoint(x: 754, y: 740)
let bb       = CGPoint(x: 522, y: 740)   // bottom bracket
let saddle   = CGPoint(x: 430, y: 480)   // top of seat tube
let headTube = CGPoint(x: 700, y: 510)   // top of fork / front of top tube
let stemTop  = CGPoint(x: 738, y: 460)   // bar mount

func stroke(_ build: (CGMutablePath) -> Void, width: CGFloat) {
    let p = CGMutablePath()
    build(p)
    ctx.setLineWidth(width)
    ctx.addPath(p)
    ctx.strokePath()
}

// Wheels (rims).
stroke({ p in
    p.addEllipse(in: CGRect(x: rearHub.x - wheelR,  y: rearHub.y  - wheelR, width: wheelR*2, height: wheelR*2))
    p.addEllipse(in: CGRect(x: frontHub.x - wheelR, y: frontHub.y - wheelR, width: wheelR*2, height: wheelR*2))
}, width: rimW)

// Frame: chain stays, seat stays, seat tube, down tube, top tube, fork, stem.
stroke({ p in
    p.move(to: bb);       p.addLine(to: rearHub)     // chain stay
    p.move(to: rearHub);  p.addLine(to: saddle)      // seat stay
    p.move(to: saddle);   p.addLine(to: bb)          // seat tube
    p.move(to: bb);       p.addLine(to: headTube)    // down tube
    p.move(to: saddle);   p.addLine(to: headTube)    // top tube
    p.move(to: headTube); p.addLine(to: frontHub)    // fork
    p.move(to: headTube); p.addLine(to: stemTop)     // stem
}, width: 22)

// Drop handlebar: hook curving forward and down from the stem.
stroke({ p in
    p.move(to: CGPoint(x: stemTop.x - 30, y: stemTop.y))
    p.addCurve(
        to:       CGPoint(x: stemTop.x + 50, y: stemTop.y + 55),
        control1: CGPoint(x: stemTop.x + 10, y: stemTop.y - 25),
        control2: CGPoint(x: stemTop.x + 70, y: stemTop.y + 5)
    )
}, width: 20)

// Crankset hub.
ctx.fillEllipse(in: CGRect(x: bb.x - 22, y: bb.y - 22, width: 44, height: 44))

// Visible crank arm (forward + slightly down — power-stroke position).
let pedal = CGPoint(x: 610, y: 760)
stroke({ p in
    p.move(to: bb); p.addLine(to: pedal)
}, width: 14)

// ── Rider ──
let hip      = CGPoint(x: 440, y: 480)
let shoulder = CGPoint(x: 590, y: 350)
let elbow    = CGPoint(x: 680, y: 415)
let grip     = CGPoint(x: stemTop.x + 35, y: stemTop.y + 45)  // on the drops
let knee     = CGPoint(x: 590, y: 595)
let headC    = CGPoint(x: 665, y: 320)
let headR: CGFloat = 55

// Leg halos — blue overstroke first to cut a visible gap through the frame.
// The black leg redraw covers the halo's interior; the 6px ring left over
// reads as the leg being clearly in front of the bike. Torso (drawn next)
// covers the halo at the hip end so the rider-on-saddle junction stays clean.
ctx.setStrokeColor(bgBlue)
stroke({ p in p.move(to: hip);  p.addLine(to: knee) },  width: 60)
stroke({ p in p.move(to: knee); p.addLine(to: pedal) }, width: 44)
ctx.setStrokeColor(black)
stroke({ p in p.move(to: hip);  p.addLine(to: knee) },  width: 48)
stroke({ p in p.move(to: knee); p.addLine(to: pedal) }, width: 32)

// Torso: hip → shoulder, thick capsule via stroked line.
stroke({ p in p.move(to: hip); p.addLine(to: shoulder) }, width: 72)

// Upper arm, lower arm.
stroke({ p in p.move(to: shoulder); p.addLine(to: elbow) }, width: 30)
stroke({ p in p.move(to: elbow);    p.addLine(to: grip) },  width: 26)

// Head.
ctx.fillEllipse(in: CGRect(x: headC.x - headR, y: headC.y - headR, width: headR*2, height: headR*2))

// ── Encode PNG ──
guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("CGImageDestination failed")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("PNG finalize failed") }
print("Wrote \(outputPath)")
