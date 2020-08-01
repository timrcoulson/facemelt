//
//  CaptureImageView.swift
//  facemelt
//
//  Created by Tim Coulson on 01/08/2020.
//  Copyright © 2020 Tim Coulson. All rights reserved.
//
import Cocoa
import SwiftUI
import AVFoundation
import Vision
import CoreMIDI

class ViewController: NSViewController {
    fileprivate var videoSession: AVCaptureSession!
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer!
    @IBOutlet weak var label1: NSTextField!

    private var midiPort: MIDIPortRef!
    private var midiClient: MIDIClientRef!
    private var midiEndpoint: MIDIEndpointRef!
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    
    fileprivate var cameraDevice: AVCaptureDevice!
    
    // Layer UI for drawing Vision results
    var rootLayer: CALayer?
    var detectionOverlayLayer: CALayer?
    var detectedFaceRectangleShapeLayer: CAShapeLayer?
    var detectedFaceLandmarksShapeLayer: CAShapeLayer?
    var rectangle: CALayer?

    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackObjectRequest]?
    var captureDeviceResolution: CGSize = CGSize()
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupMidi()
        // Do any additional setup after loading the view.
        self.prepareCamera()
        
        self.prepareVisionRequest()

        self.startSession()
        
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
 
}

extension ViewController {
    func startSession() {
        if let videoSession = videoSession {
            if !videoSession.isRunning {
                videoSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        if let videoSession = videoSession {
            if videoSession.isRunning {
                videoSession.stopRunning()
            }
        }
    }
    
    func setupMidi() {
        
        self.midiClient = MIDIClientRef()
        var result = MIDIClientCreate("facemelt" as CFString, nil, nil, &midiClient)
        print(result)

        self.midiPort = MIDIPortRef()
        result = MIDIOutputPortCreate(midiClient, "facemelt" as CFString, &self.midiPort);
        
        print(result)
    
        self.midiEndpoint = MIDIEndpointRef()
        result = MIDISourceCreate(midiClient, "facemelt" as CFString, &self.midiEndpoint)
        
        print(result)
        
        func getDisplayName(_ obj: MIDIObjectRef) -> String
               {
                   var param: Unmanaged<CFString>?
                   var name: String = "Error";
                   
                   let err: OSStatus = MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &param)
                   if err == OSStatus(noErr)
                   {
                       name =  param!.takeRetainedValue() as! String
                   }
                   
                   return name;
               }
               
               func getDestinationNames() -> [String]
               {
                   var names:[String] = [String]();
                   
                   let count: Int = MIDIGetNumberOfDestinations();
                   for i in 0 ..< count
                   {
                       let endpoint:MIDIEndpointRef = MIDIGetDestination(i);
                       if (endpoint != 0)
                       {
                           names.append(getDisplayName(endpoint));
                       }
                   }
                   return names;
               }
               
        
        let destinationNames = getDestinationNames()
        for (index,destName) in destinationNames.enumerated()
        {
            print("Destination #\(index): \(destName)")
            label1.stringValue += ("Destination #\(index): \(destName)\n")
          
            print(label1)
            
        }

//        var pkt = UnsafeMutablePointer<MIDIPacket>.alloc(1)
//        var pktList = UnsafeMutablePointer<MIDIPacketList>.alloc(1)
//        pkt = MIDIPacketListInit(pktList)
//        pkt = MIDIPacketListAdd(pktList, 1024, pkt, 0, 3, midiData)
    }
    
    fileprivate func prepareCamera() {
            self.videoSession = AVCaptureSession()
            self.videoSession.sessionPreset = AVCaptureSession.Preset.photo
            self.previewLayer = AVCaptureVideoPreviewLayer(session: videoSession)
            self.previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            
            if let devices = AVCaptureDevice.devices() as? [AVCaptureDevice] {
                for device in devices {
                    if device.hasMediaType(AVMediaType.video) {
                        self.cameraDevice = device
                        
                        if self.cameraDevice != nil  {
                            do {
                                let input = try AVCaptureDeviceInput(device: self.cameraDevice)
                                
                                
                                if videoSession.canAddInput(input) {
                                    videoSession.addInput(input)
                                }
                                
                                if let previewLayer = self.previewLayer {
//                                    if previewLayer.connection.isVideoMirroringSupported {
//                                        previewLayer.connection.automaticallyAdjustsVideoMirroring = false
//                                        previewLayer.connection.isVideoMirrored = true
//                                    }
                                    
                                    previewLayer.frame = self.view.bounds
                                    view.layer = previewLayer
                                    view.wantsLayer = true
                                    
                                    self.rootLayer = view.layer
                                }
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                    }
                }
                
                
                self.videoDataOutput = AVCaptureVideoDataOutput()
                self.videoDataOutputQueue = DispatchQueue(label: "sample buffer delegate", attributes: [])
                self.videoDataOutput!.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
                if videoSession.canAddOutput(self.videoDataOutput!) {
                    videoSession.addOutput(self.videoDataOutput!)
                }
           }
        }
    
        fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured.
        // A serial dispatch queue must be used to guarantee that video frames will be delivered in order.
        let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VisionFaceTrack")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        videoDataOutput.connection(with: .video)?.isEnabled = true
        

    }
    
    private func designatePreviewLayer(for captureSession: AVCaptureSession) {
       
    }
    
    
    fileprivate func prepareVisionRequest() {
        //self.trackingRequests = []
        var requests = [VNTrackObjectRequest]()
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in
            
            print("detection request")
            if error != nil {
                print("FaceDetection error: \(String(describing: error)).")
            }
            
            guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
                let results = faceDetectionRequest.results as? [VNFaceObservation] else {
                    return
            }
            DispatchQueue.main.async {
                // Add the observations to the tracking list
                for observation in results {
                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    requests.append(faceTrackingRequest)
                }
                self.trackingRequests = requests
            }
        })
        
        // Start with detection.  Find face, then track it.
        self.detectionRequests = [faceDetectionRequest]
        
        self.sequenceRequestHandler = VNSequenceRequestHandler()
        
        self.setupVisionDrawingLayers()
    }
    
    fileprivate func setupVisionDrawingLayers() {
        let captureDeviceResolution = self.captureDeviceResolution
        
        let captureDeviceBounds = CGRect(x: 0,
                                         y: 0,
                                         width: captureDeviceResolution.width,
                                         height: captureDeviceResolution.height)
        
        let captureDeviceBoundsCenterPoint = CGPoint(x: captureDeviceBounds.midX,
                                                     y: captureDeviceBounds.midY)
        
        let normalizedCenterPoint = CGPoint(x: 0.5, y: 0.5)
        
        guard let rootLayer = self.rootLayer else {
            print("no root layer")
            return
        }
        
        let overlayLayer = CALayer()
        overlayLayer.name = "DetectionOverlay"
        overlayLayer.masksToBounds = true
        overlayLayer.anchorPoint = normalizedCenterPoint
        overlayLayer.bounds = captureDeviceBounds
        overlayLayer.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        
        let faceRectangleShapeLayer = CAShapeLayer()
        faceRectangleShapeLayer.name = "RectangleOutlineLayer"
        faceRectangleShapeLayer.bounds = captureDeviceBounds
        faceRectangleShapeLayer.anchorPoint = normalizedCenterPoint
        faceRectangleShapeLayer.position = captureDeviceBoundsCenterPoint
        faceRectangleShapeLayer.fillColor = nil
        faceRectangleShapeLayer.strokeColor = NSColor.green.withAlphaComponent(0.7).cgColor
        faceRectangleShapeLayer.lineWidth = 5
        faceRectangleShapeLayer.shadowOpacity = 0.7
        faceRectangleShapeLayer.shadowRadius = 5
        
        let faceLandmarksShapeLayer = CAShapeLayer()
        faceLandmarksShapeLayer.name = "FaceLandmarksLayer"
        faceLandmarksShapeLayer.bounds = captureDeviceBounds
        faceLandmarksShapeLayer.anchorPoint = normalizedCenterPoint
        faceLandmarksShapeLayer.position = captureDeviceBoundsCenterPoint
        faceLandmarksShapeLayer.fillColor = nil
        faceLandmarksShapeLayer.strokeColor = NSColor.yellow.withAlphaComponent(0.7).cgColor
        faceLandmarksShapeLayer.lineWidth = 3
        faceLandmarksShapeLayer.shadowOpacity = 0.7
        faceLandmarksShapeLayer.shadowRadius = 5
        
        overlayLayer.addSublayer(faceRectangleShapeLayer)
        faceRectangleShapeLayer.addSublayer(faceLandmarksShapeLayer)
        rootLayer.addSublayer(overlayLayer)
        
        
        // TODO test
        let layer = CAGradientLayer()
        layer.frame = CGRect(x: 64, y: 64, width: 160, height: 160)
        layer.colors = [NSColor.red.cgColor, NSColor.black.cgColor]

        rootLayer.addSublayer(layer)
        self.rectangle = layer
        
        self.detectionOverlayLayer = overlayLayer
        self.detectedFaceRectangleShapeLayer = faceRectangleShapeLayer
        self.detectedFaceLandmarksShapeLayer = faceLandmarksShapeLayer
        
        self.updateLayerGeometry()
    }
    
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    /// - Tag: PerformRequests
    // Handle delegate method callback on receiving a sample buffer.
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
        
        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain a CVPixelBuffer for the current output frame.")
            return
        }
                
        guard let requests = self.trackingRequests, !requests.isEmpty else {
            // No tracking object detected, so perform initial detection
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            options: requestHandlerOptions)
            
            do {
                guard let detectRequests = self.detectionRequests else {
                    return
                }
                try imageRequestHandler.perform(detectRequests)
            } catch let error as NSError {
                NSLog("Failed to perform FaceRectangleRequest: %@", error)
            }
            return
        }
        
        do {
            try self.sequenceRequestHandler.perform(requests,
                                                     on: pixelBuffer)
        } catch let error as NSError {
            NSLog("Failed to perform SequenceRequest: %@", error)
        }
        
        // Setup the next round of tracking.
        var newTrackingRequests = [VNTrackObjectRequest]()
        
        for trackingRequest in requests {
            guard let results = trackingRequest.results else {
                return
            }
            
            guard let observation = results[0] as? VNDetectedObjectObservation else {
                return
            }
            
            if !trackingRequest.isLastFrame {
                if observation.confidence > 0.3 {
                    trackingRequest.inputObservation = observation
                } else {
                    trackingRequest.isLastFrame = true
                }
                newTrackingRequests.append(trackingRequest)
            }
        }
        self.trackingRequests = newTrackingRequests
        
        if newTrackingRequests.isEmpty {
            // Nothing to track, so abort.
            return
        }
        
        // Perform face landmark tracking on detected faces.
        var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
        var faceRectanglesRequests = [VNDetectFaceRectanglesRequest]()

        // Perform landmark detection on tracked faces.
        for trackingRequest in newTrackingRequests {
            
            let faceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request, error) in
                
                if error != nil {
                    print("FaceLandmarks error: \(String(describing: error)).")
                }
                
                guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
                    let results = landmarksRequest.results as? [VNFaceObservation] else {
                        return
                }
                
                // Perform all UI updates (drawing) on the main queue, not the background queue on which this handler is being called.
                DispatchQueue.main.async {
                    self.drawFaceObservations(results)
                }
            })
            
            let faceRectanglesRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in
                           
                           if error != nil {
                               print("FaceLandmarks error: \(String(describing: error)).")
                           }
                           
                           guard let landmarksRequest = request as? VNDetectFaceRectanglesRequest,
                               let results = landmarksRequest.results as? [VNFaceObservation] else {
                                   return
                           }
                           
                           // Perform all UI updates (drawing) on the main queue, not the background queue on which this handler is being called.
                           DispatchQueue.main.async {
                               self.drawFaceObservations(results)
                           }
                       })
            
            guard let trackingResults = trackingRequest.results else {
                return
            }
            
            guard let observation = trackingResults[0] as? VNDetectedObjectObservation else {
                return
            }
            let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
            faceLandmarksRequest.inputFaceObservations = [faceObservation]
            // Continue to track detected facial landmarks.
            faceLandmarkRequests.append(faceLandmarksRequest)
            faceRectanglesRequests.append(faceRectanglesRequest)
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            options: requestHandlerOptions)
            
            do {
                try imageRequestHandler.perform(faceLandmarkRequests)
//                try imageRequestHandler.perform(faceRectanglesRequests)
            } catch let error as NSError {
                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
            }
        }
    }
    
    /// - Tag: DrawPaths
       fileprivate func drawFaceObservations(_ faceObservations: [VNFaceObservation]) {
           guard let faceRectangleShapeLayer = self.detectedFaceRectangleShapeLayer,
               let faceLandmarksShapeLayer = self.detectedFaceLandmarksShapeLayer
               else {
               return
           }
        
           
           CATransaction.begin()
           
           CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
           
           let faceRectanglePath = CGMutablePath()
           let faceLandmarksPath = CGMutablePath()

           for faceObservation in faceObservations {
            
//            let width = faceObservation.boundingBox.maxX - faceObservation.boundingBox.minX
//            let height = faceObservation.boundingBox.maxY - faceObservation.boundingBox.minY
            
            let height = rootLayer?.bounds.height ?? 0
            let width = rootLayer?.bounds.width ?? 0
            
            let midX = ((faceObservation.boundingBox.maxX + faceObservation.boundingBox.minX) / 2) * width
            let midY = ((faceObservation.boundingBox.maxY + faceObservation.boundingBox.minY) / 2) * height
            
            self.rectangle!.frame =
                faceObservation.boundingBox.applying(CGAffineTransform(scaleX: width, y: height))
            
               self.addIndicators(to: faceRectanglePath,
                                  faceLandmarksPath: faceLandmarksPath,
                                  for: faceObservation)

            print("send midi")
            
            var packetList = MIDIPacketList()
            let midiDataToSend = [UInt8(0x9C),  UInt8(0x50), UInt8(0x7F)];
            var pkt = MIDIPacketListInit(&packetList);
            pkt = MIDIPacketListAdd(&packetList, 1024, pkt, 0, 3, midiDataToSend);
            MIDIReceived(self.midiEndpoint, &packetList)

            var result = MIDISend(self.midiPort, self.midiEndpoint, &packetList)
            print(result)
           }
        

        faceRectangleShapeLayer.path = faceRectanglePath
        faceLandmarksShapeLayer.path = faceLandmarksPath
                      
           CATransaction.commit()
       }
    
    fileprivate func addIndicators(to faceRectanglePath: CGMutablePath, faceLandmarksPath: CGMutablePath, for faceObservation: VNFaceObservation) {
        let displaySize = self.captureDeviceResolution
        
        let faceBounds = VNImageRectForNormalizedRect(faceObservation.boundingBox, Int(displaySize.width), Int(displaySize.height))
        faceRectanglePath.addRect(faceBounds)
        
        if let landmarks = faceObservation.landmarks {
            // Landmarks are relative to -- and normalized within --- face bounds
            let affineTransform = CGAffineTransform(translationX: faceBounds.origin.x, y: faceBounds.origin.y)
                .scaledBy(x: faceBounds.size.width, y: faceBounds.size.height)
            
            // Treat eyebrows and lines as open-ended regions when drawing paths.
            let openLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                landmarks.leftEyebrow,
                landmarks.rightEyebrow,
                landmarks.faceContour,
                landmarks.noseCrest,
                landmarks.medianLine
            ]
            for openLandmarkRegion in openLandmarkRegions where openLandmarkRegion != nil {
                self.addPoints(in: openLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: false)
            }
            
            // Draw eyes, lips, and nose as closed regions.
            let closedLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                landmarks.leftEye,
                landmarks.rightEye,
                landmarks.outerLips,
                landmarks.innerLips,
                landmarks.nose
            ]
            for closedLandmarkRegion in closedLandmarkRegions where closedLandmarkRegion != nil {
                self.addPoints(in: closedLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: true)
            }
        }
    }
    
    fileprivate func addPoints(in landmarkRegion: VNFaceLandmarkRegion2D, to path: CGMutablePath, applying affineTransform: CGAffineTransform, closingWhenComplete closePath: Bool) {
        let pointCount = landmarkRegion.pointCount
        if pointCount > 1 {
            let points: [CGPoint] = landmarkRegion.normalizedPoints
            path.move(to: points[0], transform: affineTransform)
            path.addLines(between: points, transform: affineTransform)
            if closePath {
                path.addLine(to: points[0], transform: affineTransform)
                path.closeSubpath()
            }
        }
    }
    
    fileprivate func updateLayerGeometry() {
        guard let overlayLayer = self.detectionOverlayLayer,
            let rootLayer = self.rootLayer,
            let previewLayer = self.previewLayer
            else {
            return
        }
        
        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
        
        let videoPreviewRect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        var rotation: CGFloat
        var scaleX: CGFloat
        var scaleY: CGFloat
        
        // Rotate the layer into screen orientation.
        rotation = 0
        scaleX = videoPreviewRect.width / captureDeviceResolution.width
        scaleY = videoPreviewRect.height / captureDeviceResolution.height
        
        // Scale and mirror the image to ensure upright presentation.
        let affineTransform = CGAffineTransform(rotationAngle: radiansForDegrees(rotation))
            .scaledBy(x: scaleX, y: -scaleY)
        overlayLayer.setAffineTransform(affineTransform)
        
        // Cover entire screen UI.
        let rootLayerBounds = rootLayer.bounds
        overlayLayer.position = CGPoint(x: rootLayerBounds.midX, y: rootLayerBounds.midY)
    }
    
    fileprivate func radiansForDegrees(_ degrees: CGFloat) -> CGFloat {
        return CGFloat(Double(degrees) * Double.pi / 180.0)
    }
    
}


extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    internal func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        print(Date())
    }
}
