import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render_sound_assets.swift <output-directory>\n", stderr)
    exit(2)
}

let sampleRate = 44_100
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let designs: [(fileName: String, segments: [(frequency: Double, duration: Double)])] = [
    ("Done-Beacon.wav", [(659.25, 0.11), (987.77, 0.18)]),
    ("Done-Chime.wav", [(523.25, 0.10), (659.25, 0.10), (783.99, 0.20)]),
    ("Done-Pulse.wav", [(783.99, 0.08), (0, 0.04), (1046.50, 0.16)]),
    ("Done-Alert.wav", [
        (880.00, 0.08), (0, 0.04), (659.25, 0.08), (0, 0.04), (440.00, 0.16)
    ]),
    ("Done-Resolve.wav", [(392.00, 0.08), (523.25, 0.10), (659.25, 0.18)]),
    ("Done-Knock.wav", [(196.00, 0.06), (0, 0.035), (174.61, 0.10)])
]

func appendASCII(_ value: String, to data: inout Data) {
    data.append(value.data(using: .ascii)!)
}

func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

for design in designs {
    var samples: [Int16] = []
    for segment in design.segments {
        let count = Int((segment.duration * Double(sampleRate)).rounded())
        for index in 0..<count {
            let elapsed = Double(index) / Double(sampleRate)
            let remaining = Double(count - index - 1) / Double(sampleRate)
            let attack = min(1, elapsed / 0.012)
            let release = min(1, remaining / 0.035)
            let envelope = max(0, min(attack, release))
            let wave = segment.frequency == 0
                ? 0
                : sin(2 * .pi * segment.frequency * elapsed) * envelope * 0.28
            samples.append(Int16((wave * Double(Int16.max)).rounded()))
        }
    }

    let payloadSize = UInt32(samples.count * MemoryLayout<Int16>.size)
    var wav = Data()
    appendASCII("RIFF", to: &wav)
    appendLittleEndian(UInt32(36) + payloadSize, to: &wav)
    appendASCII("WAVE", to: &wav)
    appendASCII("fmt ", to: &wav)
    appendLittleEndian(UInt32(16), to: &wav)
    appendLittleEndian(UInt16(1), to: &wav)
    appendLittleEndian(UInt16(1), to: &wav)
    appendLittleEndian(UInt32(sampleRate), to: &wav)
    appendLittleEndian(UInt32(sampleRate * 2), to: &wav)
    appendLittleEndian(UInt16(2), to: &wav)
    appendLittleEndian(UInt16(16), to: &wav)
    appendASCII("data", to: &wav)
    appendLittleEndian(payloadSize, to: &wav)
    for sample in samples {
        appendLittleEndian(sample, to: &wav)
    }
    try wav.write(to: outputDirectory.appendingPathComponent(design.fileName), options: .atomic)
}
