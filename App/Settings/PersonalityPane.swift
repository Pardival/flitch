import FlitchCore
import FlitchStage
import SwiftUI

struct PersonalityPane: View {
    @Bindable var settings: FlitchSettings

    var body: some View {
        Form {
            Section {
                ForEach(TonePreset.allCases, id: \.self) { tone in
                    Button {
                        settings.tone = tone
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: settings.tone == tone ? "largecircle.fill.circle" : "circle")
                                .font(.title3)
                                .foregroundStyle(settings.tone == tone ? FlitchColors.accentBright : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tone.title).fontWeight(.medium)
                                Text(tone.sample).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.tone == tone ? .isSelected : [])
                }
            } header: {
                Text("The tone Flitch uses to answer you.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Personality"))
    }
}

extension TonePreset {
    var title: LocalizedStringKey {
        switch self {
        case .enthusiastic: "Enthusiastic"
        case .calm: "Calm"
        case .professional: "Professional"
        case .funny: "Funny"
        case .teasing: "Teasing"
        }
    }

    var sample: LocalizedStringKey {
        switch self {
        case .enthusiastic: "“Oh, great question! So, listen to this…”"
        case .calm: "“Good question. Here's what I know.”"
        case .professional: "“In short: three points to remember.”"
        case .funny: "“Hold on to your pebble, this is going to be good!”"
        case .teasing: "“You again? Fine, I'll tell you everything.”"
        }
    }
}
