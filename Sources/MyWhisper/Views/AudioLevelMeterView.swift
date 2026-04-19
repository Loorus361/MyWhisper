import SwiftUI

struct AudioLevelMeterView: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)

                Capsule(style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: max(10, geometry.size.width * level))
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
