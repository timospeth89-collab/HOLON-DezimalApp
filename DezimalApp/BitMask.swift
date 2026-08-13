import Foundation

/// Bildet die Rechenlogik aus `Software_VSM_Transitions_3_4_Lmo.xlsx` nach.
///
/// Excel-Vorbild:
/// * `C21`      – Eingabewert (Dependencies_vsm_NoSafetyFaults), z. B. 53759
/// * `B21:B36`  – `=IF(BITAND($C21;2^i)=0;0;1)` für i = 0 … 15 (LSB = B21)
/// * `N7`       – `=DEC2HEX(SUMPRODUCT((1-B21:B36)*2^(ROW(B21:B36)-ROW(B21)));4)`
/// * `O7`       – identisches Ergebnis über ein Python-Skript
///
/// `N7` invertiert alle 16 Bits und setzt sie wieder zu einer Zahl zusammen –
/// das ist exakt das 16-Bit-Einerkomplement des Eingabewerts.
enum BitMask {

    /// Anzahl der ausgewerteten Bits (B21 … B36).
    static let bitCount = 16

    /// Größter zulässiger Eingabewert (16 Bit).
    static let maxValue = 65535

    /// Signalbeschreibungen aus Spalte `A21:A36`, Index = Bitposition.
    static let signalNames: [String] = [
        "HVPowernet as NoFault",
        "LV1 & LV2 Powernet fault as NoFault",
        "ThermalErrLvl as NoFault",
        "PropulsionErrLvl as NoFault",
        "DoorErrLvl as NoFault",
        "RampErrLvl as NoFault",
        "CrashDetectionSysErrLvl as NoFault",
        "BCMErrLvl as NoFault",
        "SteeringErrLvl as NoFault",
        "AirSuspensionErrLvl as NoFault",
        "PrimaryBrakeErrLvl as NoFault",
        "SecondaryBrakeErrLvl as NoFault",
        "TelematicErrLvl as NoFault",
        "CGWErrLvl as NoFault",
        "placeholder",
        "placeholder",
    ]

    /// Entspricht `B21:B36` – Bit `index` des Eingabewerts (LSB = Index 0).
    static func bits(of value: UInt16) -> [Int] {
        (0..<bitCount).map { Int((value >> UInt16($0)) & 1) }
    }

    /// Entspricht `N7` / `O7` – alle 16 Bits invertiert, wieder als Zahl.
    static func mask(for value: UInt16) -> UInt16 {
        ~value
    }

    /// 4-stellige Hex-Darstellung, wie `DEC2HEX(...;4)`.
    static func hex4(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    /// 16-stellige Binärdarstellung (MSB links), nur zur Anzeige.
    static func binary16(_ value: UInt16) -> String {
        let raw = String(value, radix: 2)
        return String(repeating: "0", count: bitCount - raw.count) + raw
    }

    /// Prüft und wandelt eine Nutzereingabe in einen gültigen 16-Bit-Wert.
    static func parse(_ text: String) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(\.isNumber),
              let number = Int(trimmed),
              number >= 0, number <= maxValue
        else { return nil }
        return UInt16(number)
    }

    /// Das Python-Skript aus `O7`, mit dem konkreten Wert vorbelegt.
    static func pythonScript(for value: UInt16) -> String {
        """
        import numpy as np

        # Bits aus dem Dezimalwert holen (Bit0 = LSB)
        value_in = \(value)
        bits = np.array([(value_in >> i) & 1 for i in range(16)])

        # invertieren
        bits = 1 - bits

        # in Integer umrechnen (LSB = Index 0)
        value = sum(int(bit) << i for i, bit in enumerate(bits))

        # als 4-stelliger Hex-Wert zurückgeben
        format(value, "04X")   # -> \(hex4(mask(for: value)))
        """
    }
}
