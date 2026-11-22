import WidgetKit
import SwiftUI
import AppIntents

@main
struct AOTYWidgets: WidgetBundle {
    var body: some Widget {
        ListenWidget()
        ListenControl()
    }
}

// MARK: - Lock Screen widget (small circle)

struct ListenEntry: TimelineEntry { let date: Date }

struct ListenProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListenEntry { ListenEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ListenEntry) -> Void) { completion(ListenEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ListenEntry>) -> Void) {
        completion(Timeline(entries: [ListenEntry(date: .now)], policy: .never))
    }
}

struct ListenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ListenWidget", provider: ListenProvider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 22, weight: .semibold))
            }
            .widgetURL(URL(string: "aotybox://listen"))
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Identify a Song")
        .description("Opens AOTY and listens for the song playing around you.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Control (Lock Screen corner buttons / Control Center)

struct ListenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.harper.aotybox.listen") {
            ControlWidgetButton(action: ListenIntent()) {
                Label("Identify Song", systemImage: "waveform.and.mic")
            }
        }
        .displayName("Identify a Song")
        .description("Listens for a song and opens it in AOTY.")
    }
}
