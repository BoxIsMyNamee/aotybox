import SwiftUI

extension View {
    /// Tab-root title drawn in the toolbar row (same line as the buttons), so there's no
    /// empty bar above a separate large title. Pushed screens still get the normal back title.
    func tabTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(.largeTitle.bold())
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Group {
                        if let img = UIImage(named: "aoty-logo") {
                            Image(uiImage: img).renderingMode(.template).resizable().scaledToFit()
                        } else {
                            Text("AOTY").font(.largeTitle.bold())
                        }
                    }
                    .frame(height: 30)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Album of the Year")
                    .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
