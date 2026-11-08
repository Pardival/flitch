import FlitchCharacter
import FlitchCore
import FlitchStage
import SwiftUI

struct PersonalityPane: View {
    let app: AppController
    @Bindable var settings: FlitchSettings

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(AppController.availableCharacters, id: \.pack.id) { c in
                        CharacterCard(character: c, selected: settings.characterID == c.pack.id) {
                            settings.characterID = c.pack.id
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Who keeps you company.")
            }
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

struct CharacterCard: View {
    let character: LoadedCharacter
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                if let image = try? SpriteSheet(character: character).frame("idle", 0) {
                    Image(decorative: image, scale: 1).interpolation(.none).resizable().frame(width: 64, height: 64)
                }
                Text(verbatim: character.mascotName).fontWeight(.semibold)
                Text(verbatim: character.speciesName).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(
                selected
                    ? AnyShapeStyle(FlitchColors.accentBright.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: .rect(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    selected ? FlitchColors.accentBright : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(character.mascotName), \(character.speciesName)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension LoadedCharacter {
    /// "Flitch", "Pip"…
    var mascotName: String {
        switch pack.id {
        case "red-panda": "Pip"
        case "owl": "Hulo"
        case "axolotl": "Axo"
        default: "Flitch"
        }
    }

    var speciesName: String {
        switch pack.id {
        case "otter": String(localized: "Otter")
        case "red-panda": String(localized: "Red panda")
        case "owl": String(localized: "Little owl")
        case "axolotl": String(localized: "Axolotl")
        default: pack.name
        }
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
