import AVFoundation
import Foundation

final class AudioChunkCancellation {
  private let lock = NSLock()
  private var cancelled = false
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
  func check() throws {
    lock.lock(); let value = cancelled; lock.unlock()
    if value { throw AudioChunkError.cancelled }
  }
}

enum AudioChunkError: Error { case cancelled, unreadable, invalidFormat }

/// Decodes bounded portions without loading the podcast into memory.
/// Output timestamps stay on the original media timeline (no silence removal).
enum AudioChunkExtractor {
  static func extract(source: String, destination: String, startUs: Int64,
                      cancellation: AudioChunkCancellation) throws -> [String: Any] {
    try cancellation.check()
    let asset = AVURLAsset(url: URL(fileURLWithPath: source))
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw AudioChunkError.unreadable
    }
    let total = CMTimeGetSeconds(asset.duration)
    let start = Double(startUs) / 1_000_000
    guard total.isFinite, total > start, start >= 0 else { throw AudioChunkError.unreadable }
    let reader = try AVAssetReader(asset: asset)
    defer { reader.cancelReading() }
    let rate = 16_000
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: rate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw AudioChunkError.invalidFormat }
    reader.add(output)
    let stop = min(total, start + 120)
    reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1_000_000),
      end: CMTime(seconds: stop, preferredTimescale: 1_000_000))
    guard reader.startReading() else { throw AudioChunkError.unreadable }
    let url = URL(fileURLWithPath: destination)
    FileManager.default.createFile(atPath: destination, contents: Data(count: 44))
    let file = try FileHandle(forWritingTo: url)
    var succeeded = false
    defer {
      try? file.close()
      if !succeeded { try? FileManager.default.removeItem(at: url) }
    }
    try file.seek(toOffset: 44)
    var bytes = 0
    var firstUs: Int64?
    var endUs = startUs
    while let sample = output.copyNextSampleBuffer() {
      try cancellation.check()
      guard let format = CMSampleBufferGetFormatDescription(sample),
            let description = CMAudioFormatDescriptionGetStreamBasicDescription(format),
            description.pointee.mSampleRate == Double(rate),
            description.pointee.mChannelsPerFrame == 1,
            let buffer = CMSampleBufferGetDataBuffer(sample) else {
        throw AudioChunkError.invalidFormat
      }
      let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
      guard pts.isFinite else { throw AudioChunkError.unreadable }
      let frames = CMBlockBufferGetDataLength(buffer) / 2
      let skip = min(frames, max(0, Int(ceil((start - pts) * Double(rate)))))
      let available = max(0, min(frames - skip,
        Int(floor((stop - pts) * Double(rate))) - skip))
      let count = min(available, (20_000_000 - 44 - bytes) / 2)
      if count > 0 {
        var data = Data(count: count * 2)
        let status = data.withUnsafeMutableBytes { raw in
          CMBlockBufferCopyDataBytes(buffer, atOffset: skip * 2,
            dataLength: count * 2, destination: raw.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { throw AudioChunkError.unreadable }
        let sampleStart = Int64(((pts + Double(skip) / Double(rate)) * 1_000_000).rounded())
        if firstUs == nil { firstUs = sampleStart }
        try file.write(contentsOf: data)
        bytes += data.count
        endUs = sampleStart + Int64(Double(count) / Double(rate) * 1_000_000)
      }
      if count < available || Double(endUs) / 1_000_000 >= stop - 0.0001 { break }
    }
    try cancellation.check()
    guard reader.status != .failed, bytes > 0, let firstUs = firstUs else {
      throw AudioChunkError.unreadable
    }
    try file.seek(toOffset: 0)
    try file.write(contentsOf: waveHeader(bytes: bytes, rate: rate, channels: 1))
    try file.synchronize()
    succeeded = true
    return ["startUs": firstUs, "endUs": endUs,
            "sourceDurationUs": Int64((total * 1_000_000).rounded()),
            "isLast": Double(endUs) / 1_000_000 >= total - 0.05]
  }

  private static func waveHeader(bytes: Int, rate: Int, channels: Int) -> Data {
    var data = Data()
    func text(_ value: String) { data.append(contentsOf: value.utf8) }
    func number(_ value: Int, _ width: Int) {
      for shift in 0..<width { data.append(UInt8((value >> (shift * 8)) & 255)) }
    }
    text("RIFF"); number(bytes + 36, 4); text("WAVEfmt "); number(16, 4)
    number(1, 2); number(channels, 2); number(rate, 4)
    number(rate * channels * 2, 4); number(channels * 2, 2); number(16, 2)
    text("data"); number(bytes, 4)
    return data
  }
}
