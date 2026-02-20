import AVFoundation
import CoreMedia

class ScreenCameraCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID
    let layout: ScreenCameraLayout
    let bubblePosition: CameraBubblePosition
    let outputSize: CGSize

    init(
        timeRange: CMTimeRange,
        screenTrackID: CMPersistentTrackID,
        cameraTrackID: CMPersistentTrackID,
        layout: ScreenCameraLayout,
        bubblePosition: CameraBubblePosition,
        outputSize: CGSize
    ) {
        self.timeRange = timeRange
        self.screenTrackID = screenTrackID
        self.cameraTrackID = cameraTrackID
        self.layout = layout
        self.bubblePosition = bubblePosition
        self.outputSize = outputSize
        self.requiredSourceTrackIDs = [
            NSNumber(value: screenTrackID),
            NSNumber(value: cameraTrackID)
        ]
        super.init()
    }
}
