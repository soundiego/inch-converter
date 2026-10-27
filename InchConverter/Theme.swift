// The MateLabs look ("Scope", Boom-And-Lav Sync docs/matelabs-visual-style.md), on iPhone:
// always dark, near-black indigo, panels with a 1-pt edge, a header band with the icon and an
// oscilloscope grid, figures in a fixed-width font. The accent comes from this app's icon: the
// sun's gold (#FABA41, the average of its bright pixels), with a deep orange (#B8520A) for fills
// under white text. Contrast: accent on a panel 10.7:1, white on the deep accent 4.9:1.
import SwiftUI
import UIKit

enum Theme {
    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let background = rgb(0x0B0A14)
    static let panel = rgb(0x14121F)
    static let panelHigh = rgb(0x1B1830)  // the top of a panel's gradient
    static let headerTop = rgb(0x120F21)
    static let edge = rgb(0x2C2747)
    static let dim = rgb(0x8F89AB)
    static let accent = rgb(0xFABA41)      // the icon's sun
    static let accentDeep = rgb(0xB8520A)  // fills under white text
    static let accentDeepUI = UIColor(red: 0xB8 / 255, green: 0x52 / 255, blue: 0x0A / 255, alpha: 1)

    /// The chosen segment of every segmented control in the deep accent, its words white.
    static func applyAppearance() {
        let segments = UISegmentedControl.appearance()
        segments.selectedSegmentTintColor = accentDeepUI
        segments.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }
}

/// The band at the top of the screen: the icon, the name, what the app does, the version.
struct HeaderBand: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            Image("HeaderIcon")
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("INCH ")
                        .foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 6)
                    Text("CONVERTER")
                }
                .font(.system(size: 15, weight: .semibold))
                .tracking(3)
                Text("Inches, fractions and centimeters")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            RulerTicks()
                .stroke(Theme.accent, lineWidth: 2)
                .shadow(color: Theme.accent, radius: 3)
                .frame(width: 56, height: 22)
                .opacity(0.6)
                .accessibilityHidden(true)
            Text(version)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .accessibilityLabel("Version \(version)")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            ZStack {
                LinearGradient(colors: [Theme.headerTop, Theme.background], startPoint: .top, endPoint: .bottom)
                Graticule().stroke(Theme.accent.opacity(0.07), lineWidth: 1)
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { Theme.edge.frame(height: 1) }
    }
}

/// The oscilloscope grid behind the header: a line every 22 points.
private struct Graticule: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX
        while x <= r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += 22 }
        var y = r.minY
        while y <= r.maxY { p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)); y += 22 }
        return p
    }
}

/// The ruler on the icon's horizon: a baseline with ticks, the tallest in the middle.
private struct RulerTicks: Shape {
    func path(in r: CGRect) -> Path {
        let heights: [CGFloat] = [0.5, 0.3, 0.3, 0.7, 0.3, 0.3, 1, 0.3, 0.3, 0.7, 0.3, 0.3, 0.5]
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        for (i, h) in heights.enumerated() {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(heights.count - 1)
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x, y: r.maxY - r.height * h))
        }
        return p
    }
}

extension View {
    /// A panel: a little lighter than the background, ruled off with the edge colour. The
    /// active one is outlined in the accent, with a glow.
    func themePanel(active: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Theme.panelHigh, Theme.panel], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(active ? Theme.accent : Theme.edge, lineWidth: active ? 2 : 1)
                .shadow(color: active ? Theme.accent.opacity(0.55) : .clear, radius: 4)
        }
    }
}
