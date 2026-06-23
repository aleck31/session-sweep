#!/usr/bin/env swift
//
// Renders the app icon to a 1024x1024 PNG using AppKit (no Xcode, no assets).
// Design: a rounded-square macOS tile with a blue→purple gradient, a chat
// bubble (the "session"), and a broom at the lower-right hinting at "cleanup".
//
// Usage:  swift scripts/make-icon.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/icon-1024.png"

let S: CGFloat = 1024
let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// — Rounded-square tile with a vertical gradient (Apple "squircle" corner ~22%).
let inset: CGFloat = S * 0.06
let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let corner = rect.width * 0.2237
let tile = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
tile.addClip()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.42, blue: 0.96, alpha: 1), // indigo
    NSColor(srgbRed: 0.55, green: 0.30, blue: 0.92, alpha: 1), // purple
])!
gradient.draw(in: rect, angle: -90)

// — Main chat bubble (rounded rect + a small tail).
func bubble(_ r: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

let bubbleW = rect.width * 0.52
let bubbleH = bubbleW * 0.74
let bx = rect.midX - bubbleW / 2
let by = rect.midY - bubbleH / 2 + rect.height * 0.06
let bubbleRect = CGRect(x: bx, y: by, width: bubbleW, height: bubbleH)
let bubblePath = bubble(bubbleRect, radius: bubbleW * 0.22)

// tail at bottom-left
let tail = NSBezierPath()
tail.move(to: CGPoint(x: bx + bubbleW * 0.22, y: by + bubbleH * 0.02))
tail.line(to: CGPoint(x: bx + bubbleW * 0.10, y: by - bubbleH * 0.20))
tail.line(to: CGPoint(x: bx + bubbleW * 0.42, y: by + bubbleH * 0.04))
tail.close()

NSColor.white.setFill()
bubblePath.fill()
tail.fill()

// — Three dots inside the bubble (a conversation).
let dotR = bubbleW * 0.055
let dotY = bubbleRect.midY - dotR
let gradientDots = NSColor(srgbRed: 0.42, green: 0.36, blue: 0.92, alpha: 1)
gradientDots.setFill()
for i in 0..<3 {
    let cx = bubbleRect.midX + CGFloat(i - 1) * bubbleW * 0.26 - dotR
    NSBezierPath(ovalIn: CGRect(x: cx, y: dotY, width: dotR * 2, height: dotR * 2)).fill()
}

// — A broom at the lower-right of the bubble (the "cleanup" motif).
// Drawn in a tilted local frame: handle points up, bristles fan downward.
func drawBroom() {
    ctx.saveGState()
    // Bigger unit + bolder shapes so the broom survives Dock-size scaling.
    let unit = rect.width * 0.020

    // Anchor the bristle head just below the bubble's bottom-right, tilted.
    let t = NSAffineTransform()
    t.translateX(by: bubbleRect.maxX - rect.width * 0.04,
                 yBy: bubbleRect.minY - rect.height * 0.02)
    t.rotate(byDegrees: -28)
    t.concat()

    // Handle: a thick wooden rounded rod rising from the bristle head.
    let handleW = unit * 2.4
    let handle = NSBezierPath(roundedRect:
        CGRect(x: -handleW / 2, y: 0, width: handleW, height: unit * 18),
        xRadius: handleW / 2, yRadius: handleW / 2)
    NSColor(srgbRed: 0.98, green: 0.74, blue: 0.33, alpha: 1).setFill() // amber wood
    handle.fill()

    // Binding collar where the bristles attach.
    let collar = NSBezierPath(roundedRect:
        CGRect(x: -unit * 3.0, y: -unit * 0.8, width: unit * 6.0, height: unit * 2.8),
        xRadius: unit * 0.8, yRadius: unit * 0.8)
    NSColor(srgbRed: 0.82, green: 0.52, blue: 0.18, alpha: 1).setFill() // darker band
    collar.fill()

    // Bristles: a downward-fanning trapezoid in straw/tan (pops off the bubble).
    let bristles = NSBezierPath()
    bristles.move(to: CGPoint(x: -unit * 2.7, y: -unit * 0.4))
    bristles.line(to: CGPoint(x: unit * 2.7, y: -unit * 0.4))
    bristles.line(to: CGPoint(x: unit * 5.2, y: -unit * 9.2))
    bristles.line(to: CGPoint(x: -unit * 5.2, y: -unit * 9.2))
    bristles.close()
    NSColor(srgbRed: 1.0, green: 0.88, blue: 0.55, alpha: 1).setFill() // straw
    bristles.fill()

    // Bristle texture: bold fanning strokes in a deeper straw tone.
    NSColor(srgbRed: 0.82, green: 0.52, blue: 0.18, alpha: 0.65).setStroke()
    for i in -2...2 {
        let line = NSBezierPath()
        line.move(to: CGPoint(x: CGFloat(i) * unit * 1.2, y: -unit * 0.8))
        line.line(to: CGPoint(x: CGFloat(i) * unit * 2.1, y: -unit * 8.9))
        line.lineWidth = unit * 0.55
        line.lineCapStyle = .round
        line.stroke()
    }

    ctx.restoreGState()
}
drawBroom()

image.unlockFocus()

// — Encode to PNG.
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
} catch {
    fatalError("write failed: \(error)")
}
