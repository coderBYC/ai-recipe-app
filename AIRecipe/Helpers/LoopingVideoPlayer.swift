import SwiftUI
import AVFoundation

struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    let videoType: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        context.coordinator.attachPlayer(
            to: view,
            videoName: videoName,
            videoType: videoType,
            videoGravity: videoGravity
        )
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attachPlayer(
            to: uiView,
            videoName: videoName,
            videoType: videoType,
            videoGravity: videoGravity
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
        private var loadedKey: String?

        func attachPlayer(
            to view: UIView,
            videoName: String,
            videoType: String,
            videoGravity: AVLayerVideoGravity
        ) {
            let key = "\(videoName).\(videoType)|\(videoGravity.rawValue)"
            if loadedKey == key, playerLayer?.superlayer === view.layer {
                DispatchQueue.main.async { [weak self] in
                    self?.playerLayer?.frame = view.bounds
                }
                return
            }

            loadedKey = key
            looper = nil
            playerLayer?.removeFromSuperlayer()

            guard let path = Bundle.main.path(forResource: videoName, ofType: videoType) else {
                print("❌ LoopingVideoPlayer: missing \(videoName).\(videoType)")
                return
            }

            let url = URL(fileURLWithPath: path)
            let asset = AVAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let queuePlayer = AVQueuePlayer(playerItem: item)
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

            let layer = AVPlayerLayer(player: queuePlayer)
            layer.videoGravity = videoGravity
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            playerLayer = layer
            queuePlayer.isMuted = true
            queuePlayer.play()
        }
    }
}
