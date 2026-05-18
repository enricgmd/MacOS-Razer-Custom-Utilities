import SwiftUI

public struct KeySwapperView: View {
    @ObservedObject var model: MacroAppModel
    @State private var selectedRuleID: UUID?

    public init(model: MacroAppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            KeySwapperBackdrop()
                .edgesIgnoringSafeArea(.all)

            VStack(alignment: .leading, spacing: 14) {
                header
                ruleList
                footer
            }
            .padding(15)
        }
        .frame(width: 430, height: 330)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Key Swapper")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: 5)
            Text("Replace one physical key with another while this app is running.")
                .font(.callout)
                .foregroundColor(Color.white.opacity(0.60))
                .offset(y: 3)
        }
    }

    private var ruleList: some View {
        VStack(spacing: 0) {
            KeySwapHeaderRow()

            if model.keySwapRules.isEmpty {
                Spacer()
                Text("No key swaps assigned")
                    .font(.callout.weight(.medium))
                    .foregroundColor(Color.white.opacity(0.48))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.keySwapRules.indices, id: \.self) { index in
                            let rule = model.keySwapRules[index]
                            KeySwapRuleRow(
                                rule: rule,
                                isSelected: selectedRuleID == rule.id,
                                isAlternate: index.isMultiple(of: 2)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if model.deviceConnected {
                                    selectedRuleID = rule.id
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.10, green: 0.15, blue: 0.12).opacity(1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.razerGreen.opacity(0.28), lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 8)
    }

    private var footer: some View {
            HStack(spacing: 6) {
            Button(action: {
                model.beginKeySwapRuleCapture()
            }) {
                Text("+")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24, height: 24, alignment: .top)
            }
                .offset (y: -5)
                .disabled(!model.deviceConnected)
            Button(action: {
                if let selectedRuleID {
                    model.removeKeySwapRule(id: selectedRuleID)
                    self.selectedRuleID = nil
                }
            }) {
                Text("-")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24, height: 24, alignment: .top)
            }
                .offset (y: -5)
                .disabled(!model.deviceConnected || selectedRuleID == nil)

                Spacer()
            }
            .padding(.bottom, 8)
            .opacity(model.deviceConnected ? 1.0 : 0.42)
        }
    }

private struct KeySwapperBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.42, blue: 0.20)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.razerGreen.opacity(0.6),
                    Color(red: 0.32, green: 0.60, blue: 0.51).opacity(0.44),
                    Color(red: 0.08, green: 0.10, blue: 0.25).opacity(0.52)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.00),
                    Color.black.opacity(0.30)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct KeySwapHeaderRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Source")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

            Rectangle()
                .fill(Color.razerGreen.opacity(0.34))
                .frame(width: 1)
            Text("Destination")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(Color.white.opacity(0.72))
        .frame(height: 35)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

private struct KeySwapRuleRow: View {
    let rule: KeySwapRule
    let isSelected: Bool
    let isAlternate: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(rule.source.displayName)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.leading, 14)

            Rectangle()
                .fill(Color.razerGreen.opacity(isSelected ? 0.58 : 0.28))
                .frame(width: 1)

            Text(rule.destination.displayName)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.leading, 14)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .background(rowBackground)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var rowBackground: Color {
        if isSelected {
            return Color(red: 0.1, green: 0.3, blue: 1.0).opacity(0.4)
        }
        return isAlternate
            ? Color.white.opacity(0.1)
            : Color.white.opacity(0.05)
    }
}

private extension Color {
    static let razerGreen = Color(red: 0.27, green: 0.84, blue: 0.17)
}

#if DEBUG
struct KeySwapperView_Previews: PreviewProvider {
    static var previews: some View {
        let model = MacroAppModel()
        model.keySwapRules = [
            KeySwapRule(source: KeyDescriptor(keyCode: 65), destination: KeyDescriptor(keyCode: 47)),
            KeySwapRule(source: KeyDescriptor(keyCode: 58), destination: KeyDescriptor(keyCode: 59))
        ]
        return KeySwapperView(model: model)
            .frame(width: 430, height: 330)
            .previewDisplayName("Key Swapper")
    }
}
#endif
