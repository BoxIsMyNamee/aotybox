import SwiftUI

extension View {
    /// Tab-root title drawn in the toolbar row (same line as the buttons), so there's no
    /// empty bar above a separate large title. Pushed screens still get the normal back title.
    func tabTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .inlineNavTitle()
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    Text(title)
                        #if os(macOS)
                        .font(.title2.bold())
                        #else
                        .font(.largeTitle.bold())
                        #endif
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }

    /// Tab root that shows the AOTY wordmark top-left instead of a text title.
    func tabLogo(backTitle: String) -> some View {
        self
            .navigationTitle(backTitle)
            .inlineNavTitle()
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    Group {
                        if let img = PlatformImage(named: "aoty-logo") {
                            Image(platformImage: img).renderingMode(.template).resizable().scaledToFit()
                        } else {
                            Text("AOTY").font(.title2.bold())
                        }
                    }
                    #if os(macOS)
                    .frame(height: 22)
                    #else
                    .frame(height: 30)
                    #endif
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Album of the Year")
                    .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
