import Flutter
import UIKit
import AVFoundation

public class SwiftDartDlpPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "hamas_dlp/muxer", binaryMessenger: registrar.messenger())
    let instance = SwiftDartDlpPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "mergeVideoAudio" {
      guard let args = call.arguments as? [String: Any],
            let videoPath = args["videoPath"] as? String,
            let audioPath = args["audioPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing paths", details: nil))
        return
      }

      mergeVideoAudio(videoPath: videoPath, audioPath: audioPath, outputPath: outputPath) { success, error in
        if success {
          result(outputPath)
        } else {
          result(FlutterError(code: "MUX_FAILED", message: error?.localizedDescription, details: nil))
        }
      }

    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  private func mergeVideoAudio(videoPath: String, audioPath: String, outputPath: String, completion: @escaping (Bool, Error?) -> Void) {
    let composition = AVMutableComposition()
    
    let videoUrl = URL(fileURLWithPath: videoPath)
    let audioUrl = URL(fileURLWithPath: audioPath)
    let outputUrl = URL(fileURLWithPath: outputPath)

    let videoAsset = AVURLAsset(url: videoUrl)
    let audioAsset = AVURLAsset(url: audioUrl)

    // Remove existing file
    if FileManager.default.fileExists(atPath: outputPath) {
      try? FileManager.default.removeItem(atPath: outputPath)
    }

    // 1. Add Video Track
    guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
          let assetVideoTrack = videoAsset.tracks(withMediaType: .video).first else {
      completion(false, NSError(domain: "DartDlp", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"]))
      return
    }

    do {
      try videoTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: videoAsset.duration), of: assetVideoTrack, at: .zero)
    } catch {
      completion(false, error)
      return
    }

    // 2. Add Audio Track
    if let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
       let assetAudioTrack = audioAsset.tracks(withMediaType: .audio).first {
      try? audioTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: videoAsset.duration), of: assetAudioTrack, at: .zero)
    }

    // 3. Export
    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
      completion(false, NSError(domain: "DartDlp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Exporter init failed"]))
      return
    }

    exporter.outputURL = outputUrl
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = false

    exporter.exportAsynchronously {
      DispatchQueue.main.async {
        switch exporter.status {
        case .completed:
          completion(true, nil)
        case .failed:
          completion(false, exporter.error)
        case .cancelled:
          completion(false, NSError(domain: "DartDlp", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cancelled"]))
        default:
          completion(false, NSError(domain: "DartDlp", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown status"]))
        }
      }
    }
  }
}
