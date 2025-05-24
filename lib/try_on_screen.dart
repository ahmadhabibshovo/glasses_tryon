import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

// Placeholder for GlassesSelectionWidget (replace with actual implementation)
class GlassesSelectionWidget extends StatelessWidget {
  final Function(String) onGlassesSelected;

  const GlassesSelectionWidget({super.key, required this.onGlassesSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      color: Colors.grey[200],
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildGlassesOption(context, 'assets/images/glasses1.png'),

          // Add more glasses options as needed
        ],
      ),
    );
  }

  Widget _buildGlassesOption(BuildContext context, String assetPath) {
    return GestureDetector(
      onTap: () => onGlassesSelected(assetPath),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Image.asset(assetPath, width: 80, height: 80,
            errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.error, size: 80);
        }),
      ),
    );
  }
}

class TryOnScreen extends StatefulWidget {
  final bool isLiveCamera;

  const TryOnScreen({super.key, required this.isLiveCamera});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  String? _cameraError;

  // Face Detection
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
      enableTracking: true,
    ),
  );
  bool _isDetectingFaces = false;
  List<Face> _detectedFaces = [];
  int _frameCounter = 0;
  static const int _processEveryNthFrame =
      3; // Process every 3rd frame for performance

  // Glasses Selection
  String? _selectedGlassesId;
  ui.Image? _selectedGlassesImage;

  Future<void> _loadGlassesImage(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Image? image = await decodeImageFromList(bytes);
      if (mounted) {
        setState(() {
          _selectedGlassesImage
              ?.dispose(); // Dispose previous image (if supported)
          _selectedGlassesImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedGlassesImage?.dispose();
          _selectedGlassesImage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load glasses image: $e')),
        );
      }
    }
  }

  void _onGlassesSelected(String glassesId) {
    setState(() {
      _selectedGlassesId = glassesId;
      if (_selectedGlassesId != null) {
        _loadGlassesImage(_selectedGlassesId!);
      } else {
        _selectedGlassesImage?.dispose();
        _selectedGlassesImage = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.isLiveCamera) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        CameraDescription? frontCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );

        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21,
        );
        await _cameraController!.initialize();
        if (!mounted) return;

        _cameraController!.startImageStream((CameraImage image) {
          if (_isDetectingFaces || _frameCounter++ % _processEveryNthFrame != 0)
            return;
          _isDetectingFaces = true;

          _getInputImage(image, frontCamera).then((inputImage) {
            if (inputImage != null) {
              _faceDetector.processImage(inputImage).then((faces) {
                if (!mounted) return;
                setState(() {
                  _detectedFaces = faces;
                });
              }).catchError((error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error processing image: $error')),
                  );
                }
              }).whenComplete(() {
                if (!mounted) return;
                Future.delayed(const Duration(milliseconds: 200), () {
                  if (mounted) {
                    _isDetectingFaces = false;
                  }
                });
              });
            } else {
              _isDetectingFaces = false;
            }
          });
        });

        setState(() {
          _isCameraInitialized = true;
          _cameraError = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _cameraError = 'No cameras available.';
        });
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Error initializing camera: ${e.description}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'An unexpected error occurred: $e';
      });
    }
  }

  Future<InputImage?> _getInputImage(
      CameraImage image, CameraDescription camera) async {
    final orientation =
        await NativeDeviceOrientationCommunicator().orientation();
    int rotationDegrees = camera.sensorOrientation;
    if (camera.lensDirection == CameraLensDirection.front) {
      switch (orientation) {
        case NativeDeviceOrientation.portraitUp:
          rotationDegrees = rotationDegrees % 360;
          break;
        case NativeDeviceOrientation.portraitDown:
          rotationDegrees = (180 + rotationDegrees) % 360;
          break;
        case NativeDeviceOrientation.landscapeLeft:
          rotationDegrees = (90 + rotationDegrees) % 360;
          break;
        case NativeDeviceOrientation.landscapeRight:
          rotationDegrees = (270 + rotationDegrees) % 360;
          break;
        default:
          rotationDegrees = rotationDegrees % 360;
      }
    } else {
      switch (orientation) {
        case NativeDeviceOrientation.portraitUp:
          rotationDegrees = rotationDegrees % 360;
          break;
        case NativeDeviceOrientation.portraitDown:
          rotationDegrees = (180 + rotationDegrees) % 360;
          break;
        case NativeDeviceOrientation.landscapeLeft:
          rotationDegrees = (90 + rotationDegrees) % 360;
          break;
        case NativeDeviceOrientation.landscapeRight:
          rotationDegrees = (270 + rotationDegrees) % 360;
          break;
        default:
          rotationDegrees = rotationDegrees % 360;
      }
    }

    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
        InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (format != InputImageFormat.nv21 &&
            format != InputImageFormat.yuv420)) {
      return null;
    }

    Uint8List allBytes;
    if (format == InputImageFormat.nv21 && image.planes.length >= 2) {
      final yBytes = image.planes[0].bytes;
      final vuBytes = image.planes[1].bytes;
      allBytes = Uint8List(yBytes.length + vuBytes.length);
      allBytes.setRange(0, yBytes.length, yBytes);
      allBytes.setRange(yBytes.length, yBytes.length + vuBytes.length, vuBytes);
    } else if (format == InputImageFormat.yuv420 && image.planes.length >= 3) {
      allBytes = Uint8List(
          image.planes.fold(0, (prev, plane) => prev + plane.bytes.length));
      int offset = 0;
      for (var plane in image.planes) {
        allBytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }
    } else {
      return null;
    }

    final inputImageMetadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: allBytes,
      metadata: inputImageMetadata,
    );
  }

  Future<void> _takeSnapshot() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    try {
      final XFile image = await _cameraController!.takePicture();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Snapshot saved!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking snapshot: $e')),
      );
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    _selectedGlassesImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glasses Try-On'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: widget.isLiveCamera
                  ? _buildLiveCameraPreview()
                  : const Center(
                      child: Text(
                        'Image Mode - Not Implemented',
                        style: TextStyle(fontSize: 20),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
            GlassesSelectionWidget(onGlassesSelected: _onGlassesSelected),
            if (_selectedGlassesId != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Selected: $_selectedGlassesId',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: widget.isLiveCamera
          ? FloatingActionButton(
              onPressed: _takeSnapshot,
              child: const Icon(Icons.camera),
            )
          : null,
    );
  }

  Widget _buildLiveCameraPreview() {
    if (_cameraError != null) {
      return Center(
        child: Text(
          'Error: $_cameraError',
          style: const TextStyle(color: Colors.red, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isCameraInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CameraPreview(_cameraController!),
        if (_detectedFaces.isNotEmpty &&
            _cameraController != null &&
            _cameraController!.value.isInitialized)
          CustomPaint(
            painter: FacePainter(
              faces: _detectedFaces,
              absoluteImageSize: Size(
                _cameraController!.value.previewSize!.height,
                _cameraController!.value.previewSize!.width,
              ),
              cameraLensDirection: _cameraController!.description.lensDirection,
              glassesImage: _selectedGlassesImage,
            ),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black.withOpacity(0.5),
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Faces detected: ${_detectedFaces.length}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize;
  final CameraLensDirection cameraLensDirection;
  final ui.Image? glassesImage;

  FacePainter({
    required this.faces,
    required this.absoluteImageSize,
    required this.cameraLensDirection,
    this.glassesImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint facePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    final Paint glassesPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.transparent;

    for (final Face face in faces) {
      final Rect boundingBox = face.boundingBox;
      final double scaleX = size.width / absoluteImageSize.width;
      final double scaleY = size.height / absoluteImageSize.height;

      // No mirroring for front camera
      final adjustedFaceBoundingBox = Rect.fromLTRB(
        boundingBox.left * scaleX,
        boundingBox.top * scaleY,
        boundingBox.right * scaleX,
        boundingBox.bottom * scaleY,
      );
      canvas.drawRect(adjustedFaceBoundingBox, facePaint);

      Rect glassesRect;
      final FaceLandmark? leftEyeLandmark =
          face.landmarks[FaceLandmarkType.leftEye];
      final FaceLandmark? rightEyeLandmark =
          face.landmarks[FaceLandmarkType.rightEye];

      if (leftEyeLandmark != null && rightEyeLandmark != null) {
        final Point<double> leftEyePos = Point(
            leftEyeLandmark.position.x.toDouble(),
            leftEyeLandmark.position.y.toDouble());
        final Point<double> rightEyePos = Point(
            rightEyeLandmark.position.x.toDouble(),
            rightEyeLandmark.position.y.toDouble());

        Point<double> scaledLeftEye =
            Point(leftEyePos.x * scaleX, leftEyePos.y * scaleY);
        Point<double> scaledRightEye =
            Point(rightEyePos.x * scaleX, rightEyePos.y * scaleY);

        final Point<double> eyeCenter = Point(
          (scaledLeftEye.x + scaledRightEye.x) / 2,
          (scaledLeftEye.y + scaledRightEye.y) / 2,
        );
        final double eyeDistance = (scaledRightEye.x - scaledLeftEye.x).abs();

        const double glassesWidthFactor = 2.3;
        const double glassesVerticalOffsetFactor = 0.4;

        double glassesWidth = eyeDistance * glassesWidthFactor;
        double glassesHeight = glassesImage != null && glassesImage!.width > 0
            ? glassesWidth *
                (glassesImage!.height.toDouble() /
                    glassesImage!.width.toDouble())
            : glassesWidth / 2.5;

        glassesRect = Rect.fromLTWH(
          eyeCenter.x - (glassesWidth / 2),
          eyeCenter.y - (glassesHeight * glassesVerticalOffsetFactor),
          glassesWidth,
          glassesHeight,
        );
      } else {
        double glassesWidth = adjustedFaceBoundingBox.width * 0.9;
        double glassesHeight = glassesImage != null && glassesImage!.width > 0
            ? glassesWidth *
                (glassesImage!.height.toDouble() /
                    glassesImage!.width.toDouble())
            : glassesWidth / 2.5;

        glassesRect = Rect.fromLTWH(
          adjustedFaceBoundingBox.left +
              (adjustedFaceBoundingBox.width - glassesWidth) / 2,
          adjustedFaceBoundingBox.top +
              adjustedFaceBoundingBox.height * 0.30 -
              glassesHeight / 2,
          glassesWidth,
          glassesHeight,
        );
      }

      if (glassesImage != null) {
        final Rect srcRect = Rect.fromLTWH(
          0,
          0,
          glassesImage!.width.toDouble(),
          glassesImage!.height.toDouble(),
        );
        canvas.drawImageRect(glassesImage!, srcRect, glassesRect, Paint());
      }
      canvas.drawRect(glassesRect, glassesPaint);
    }
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.absoluteImageSize != absoluteImageSize ||
        oldDelegate.cameraLensDirection != cameraLensDirection ||
        oldDelegate.glassesImage != glassesImage;
  }
}
