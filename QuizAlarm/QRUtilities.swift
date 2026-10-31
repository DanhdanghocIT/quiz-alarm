import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import UniformTypeIdentifiers

struct QRCodeShareItem: Transferable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.pngData
        }
    }
}

enum QRCodeGenerator {
    private static let context = CIContext()

    static func generateUIImage(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Phóng to mã QR sắc nét + thêm viền trắng để dễ quét
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledCIImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else {
            return nil
        }

        let size = CGSize(width: cgImage.width + 48, height: cgImage.height + 48)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cgImage).draw(
                in: CGRect(x: 24, y: 24, width: cgImage.width, height: cgImage.height)
            )
        }
    }
}

struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void
    var onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        controller.onPermissionDenied = onPermissionDenied
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.quizalarm.qrscanner")
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkPermissionAndSetup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self = self, self.isConfigured, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupSession()
                    } else {
                        self?.onPermissionDenied?()
                    }
                }
            }
        case .denied, .restricted:
            onPermissionDenied?()
        @unknown default:
            onPermissionDenied?()
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isConfigured else { return }

            guard let videoDevice = AVCaptureDevice.default(for: .video),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoInput) else {
                DispatchQueue.main.async {
                    self.onPermissionDenied?()
                }
                return
            }

            self.captureSession.beginConfiguration()
            self.captureSession.addInput(videoInput)

            let metadataOutput = AVCaptureMetadataOutput()
            if self.captureSession.canAddOutput(metadataOutput) {
                self.captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                    metadataOutput.metadataObjectTypes = [.qr]
                }
            }

            self.captureSession.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.view.bounds
                self.view.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }

            self.captureSession.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              readable.type == .qr,
              let stringValue = readable.stringValue else {
            return
        }
        onCodeScanned?(stringValue)
    }
}