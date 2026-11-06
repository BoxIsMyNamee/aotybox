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
}
