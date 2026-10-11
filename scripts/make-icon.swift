// Renders the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [output.icns]
import AppKit
import SwiftUI

let teal = Color(red: 0.14, green: 0.85, blue: 0.79)

struct Knurl: Shape {
    var count: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            p.move(to: CGPoint(x: c.x + cos(a) * (r - 24), y: c.y + sin(a) * (r - 24)))
            p.addLine(to: CGPoint(x: c.x + cos(a) * (r - 6), y: c.y + sin(a) * (r - 6)))
        }
        return p
    }
}

/// A light aluminium knob with the teal LED ring, on a dark squircle (Apple's 824/1024 icon grid).
struct Icon: View {
    var body: some View {
        let plate = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            plate
                .fill(LinearGradient(colors: [Color(red: 0.19, green: 0.20, blue: 0.23), Color(red: 0.07, green: 0.075, blue: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(plate.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 4))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)

            Circle().stroke(teal, lineWidth: 34).frame(width: 616, height: 616).blur(radius: 28).opacity(0.85)
            Circle().stroke(teal, lineWidth: 10).frame(width: 592, height: 592)

            Circle()
                .fill(RadialGradient(colors: [.white, Color(white: 0.94), Color(white: 0.79)],
                                     center: UnitPoint(x: 0.36, y: 0.28), startRadius: 10, endRadius: 440))
                .frame(width: 540, height: 540)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
            Circle()
                .fill(AngularGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0), .black.opacity(0.05),
                                               .white.opacity(0), .white.opacity(0.45), .white.opacity(0), .black.opacity(0.05),
                                               .white.opacity(0)], center: .center))
                .frame(width: 528, height: 528)
            Knurl(count: 120).stroke(Color.black.opacity(0.08), lineWidth: 3).frame(width: 540, height: 540)
            Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 3).frame(width: 540, height: 540)
            Capsule().fill(teal).frame(width: 26, height: 84).offset(y: -270 + 82)
        }
        .frame(width: 1024, height: 1024)
    }
}

func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
    precondition(p.terminationStatus == 0, "\(tool) failed")
}

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        fatalError("Rendering the icon failed")
    }
    let fm = FileManager.default
    let set = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? fm.removeItem(at: set)
    try! fm.createDirectory(at: set, withIntermediateDirectories: true)
    let master = set.appendingPathComponent("master.png")
    try! png.write(to: master)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = size * scale
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            run("/usr/bin/sips", ["-z", "\(px)", "\(px)", master.path, "--out", set.appendingPathComponent(name).path])
        }
    }
    try! fm.removeItem(at: master)
    try? fm.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
    run("/usr/bin/iconutil", ["-c", "icns", set.path, "-o", output])
    print("Wrote \(output)")
}
