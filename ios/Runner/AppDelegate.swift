import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var audioDecoderChannel: FlutterMethodChannel?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Setup audio decoder method channel
        if let controller = window?.rootViewController as? FlutterViewController {
            audioDecoderChannel = FlutterMethodChannel(
                name: "com.musiccloud/audio_decoder",
                binaryMessenger: controller.binaryMessenger
            )
            
            audioDecoderChannel?.setMethodCallHandler { [weak self] call, result in
                switch call.method {
                case "decodeAudio":
                    if let args = call.arguments as? [String: Any],
                       let filePath = args["filePath"] as? String {
                        self?.decodeAudioFile(filePath: filePath, result: result)
                    } else {
                        result(FlutterError(code: "INVALID_ARGS", message: "File path is required", details: nil))
                    }
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func decodeAudioFile(filePath: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = URL(fileURLWithPath: filePath)
                let file = try AVAudioFile(forReading: url)
                
                let format = file.processingFormat
                let sampleRate = Int(format.sampleRate)
                let frameCount = UInt32(file.length)
                let duration = Int(Double(file.length) / format.sampleRate)
                
                // Limit to ~30 seconds for fingerprinting
                let maxFrames = min(frameCount, UInt32(sampleRate * 30))
                
                // Create buffer for reading
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: maxFrames
                ) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "DECODE_FAILED", message: "Failed to create buffer", details: nil))
                    }
                    return
                }
                
                try file.read(into: buffer, frameCount: maxFrames)
                
                // Convert to mono 16-bit PCM
                var samples = [Int16]()
                
                if let floatData = buffer.floatChannelData {
                    let channelCount = Int(format.channelCount)
                    let frameLength = Int(buffer.frameLength)
                    
                    for frame in 0..<frameLength {
                        var sum: Float = 0
                        for channel in 0..<channelCount {
                            sum += floatData[channel][frame]
                        }
                        let mono = sum / Float(channelCount)
                        
                        // Convert float (-1.0 to 1.0) to Int16
                        let sample = Int16(max(-32768, min(32767, Int(mono * 32767))))
                        samples.append(sample)
                    }
                }
                
                // Convert to Data
                let data = samples.withUnsafeBufferPointer { pointer in
                    Data(buffer: pointer)
                }
                
                DispatchQueue.main.async {
                    result([
                        "samples": FlutterStandardTypedData(bytes: data),
                        "sampleRate": sampleRate,
                        "duration": duration
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DECODE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
}
