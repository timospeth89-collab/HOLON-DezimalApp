import SwiftUI
import UIKit

struct ContentView: View {
    @State private var input: String = ""
    @State private var showPython = false
    @FocusState private var inputFocused: Bool

    private var value: UInt16? { BitMask.parse(input) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    inputCard
                    if let value {
                        resultCard(for: value)
                        bitTable(for: value)
                        pythonCard(for: value)
                    } else if !input.isEmpty {
                        hintCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dezimal → Hex")
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Fertig") { inputFocused = false }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Eingabe (entspricht C21)

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dezimalwert (C21)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("z. B. 53759", text: $input)
                .keyboardType(.numberPad)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .focused($inputFocused)
                .onChange(of: input) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    input = String(digits.prefix(5))
                }

            Text("0 – 65535 (16 Bit)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var hintCard: some View {
        Label("Bitte einen Wert zwischen 0 und 65535 eingeben.", systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Ergebnis (entspricht N7 / O7)

    private func resultCard(for value: UInt16) -> some View {
        let mask = BitMask.mask(for: value)
        let hex = BitMask.hex4(mask)

        return VStack(alignment: .leading, spacing: 14) {
            Text("BitMask (N7)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("0x")
                    .font(.system(size: 26, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(hex)
                    .font(.system(size: 46, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tint)
                Spacer()
                Button {
                    UIPasteboard.general.string = hex
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Hex-Wert kopieren")
            }

            Divider()

            detailRow("Eingabe dezimal", "\(value)")
            detailRow("Eingabe hex", "0x" + BitMask.hex4(value))
            detailRow("Eingabe binär", BitMask.binary16(value))
            detailRow("BitMask dezimal", "\(mask)")
            detailRow("BitMask binär", BitMask.binary16(mask))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func detailRow(_ title: String, _ detail: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.system(.subheadline, design: .monospaced))
        }
    }

    // MARK: - Bit-Tabelle (entspricht B21:B36)

    private func bitTable(for value: UInt16) -> some View {
        let bits = BitMask.bits(of: value)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Signal")
                Spacer()
                Text("set")
                    .frame(width: 34, alignment: .center)
                Text("mask")
                    .frame(width: 40, alignment: .center)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ForEach(Array(bits.enumerated()), id: \.offset) { index, bit in
                HStack(spacing: 8) {
                    Text("\(index)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)

                    Text(BitMask.signalNames[index])
                        .font(.footnote)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    bitBadge(bit, highlight: bit == 0)
                        .frame(width: 34)
                    bitBadge(1 - bit, highlight: bit == 0)
                        .frame(width: 40)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if index < bits.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func bitBadge(_ bit: Int, highlight: Bool) -> some View {
        Text("\(bit)")
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
            .foregroundStyle(highlight ? Color.orange : Color.primary)
    }

    // MARK: - Python-Skript (entspricht O7)

    private func pythonCard(for value: UInt16) -> some View {
        let script = BitMask.pythonScript(for: value)

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { showPython.toggle() }
            } label: {
                HStack {
                    Text("Python-Skript (O7)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showPython ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if showPython {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(script)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }

                Button {
                    UIPasteboard.general.string = script
                } label: {
                    Label("Skript kopieren", systemImage: "doc.on.doc")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
