import 'dart:typed_data'; // Required for BytesList
import 'dart:ui' as ui; // Import dart:ui
import 'package:flutter/foundation.dart'; // Required for foundation.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle; // Import rootBundle
import 'package:camera/camera.dart';
import 'package:google_ml_kit_face_detection/google_ml_kit_face_detection.dart';
import 'package:glasses_try_on/glasses_selection_widget.dart'; // Import GlassesSelectionWidget

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
      landmarkMode: FaceDetectorLandmarkMode.all, // Enable all landmarks
    ),
  );
  bool _isDetectingFaces = false;
  List<Face> _detectedFaces = [];

  // Glasses Selection
  String? _selectedGlassesId;
  ui.Image? _selectedGlassesImage; // State variable for the loaded glasses image

  Future<void> _loadGlassesImage(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Image? image = await decodeImageFromList(bytes);
      if (mounted) {
        setState(() {
          _selectedGlassesImage = image;
        });
        print("Glasses image '$assetPath' loaded successfully.");
      }
    } catch (e) {
      print("Error loading glasses image '$assetPath': $e");
      if (mounted) {
        setState(() {
          _selectedGlassesImage = null; // Reset if loading fails
        });
      }
    }
  }

  void _onGlassesSelected(String glassesId) {
    setState(() {
      _selectedGlassesId = glassesId;
      if (_selectedGlassesId != null) {
        _loadGlassesImage(_selectedGlassesId!);
      } else {
        _selectedGlassesImage = null; // Clear image if no glasses are selected
      }
    });
    print("Selected Glasses ID from TryOnScreen: $_selectedGlassesId");
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
          enableAudio: false, // Explicitly disable audio
          imageFormatGroup: ImageFormatGroup.nv21, // Recommended for ML Kit
        );
        await _cameraController!.initialize();
        if (!mounted) return;

        _cameraController!.startImageStream((CameraImage image) {
          if (_isDetectingFaces) return;

          _isDetectingFaces = true;

          final inputImage = _inputImageFromCameraImage(image, frontCamera);

          if (inputImage != null) {
            _faceDetector.processImage(inputImage).then((faces) {
              if (!mounted) return;
              setState(() {
                _detectedFaces = faces;
                // For debugging: print number of faces detected
                // print("Detected faces: ${_detectedFaces.length}");
              });
            }).catchError((error) {
              print("Error processing image: $error");
            }).whenComplete(() {
              if (!mounted) return;
              // Small delay before allowing next frame to be processed
              Future.delayed(const Duration(milliseconds: 100), () {
                 if (mounted) {
                    _isDetectingFaces = false;
                 }
              });
            });
          } else {
             _isDetectingFaces = false; // Reset if inputImage is null
          }
        });

        setState(() {
          _isCameraInitialized = true;
          _cameraError = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _cameraError = "No cameras available.";
        });
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = "Error initializing camera: ${e.description}";
      });
      print('Error initializing camera: ${e.description}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = "An unexpected error occurred: $e";
      });
      print('An unexpected error occurred: $e');
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription cameraDescription) {
    final orientation = cameraDescription.sensorOrientation; // degrees: 0, 90, 180, 270
    InputImageRotation rotation;
    // Simple logic for front camera, assuming portrait mode.
    // This might need adjustment based on device orientation.
    if (cameraDescription.lensDirection == CameraLensDirection.front) {
      // Front camera is often mirrored and rotated.
      // For portrait, a common rotation is 270deg.
      // If landscape, it might be 0 or 180.
      // This is a common point of failure, adjust as needed.
      rotation = InputImageRotationValue.fromRawValue(orientation) ?? InputImageRotation.rotation270deg;
      if (rotation == InputImageRotation.rotation90deg) rotation = InputImageRotation.rotation270deg;
      else if (rotation == InputImageRotation.rotation270deg) rotation = InputImageRotation.rotation90deg;

    } else { // Back camera
      rotation = InputImageRotationValue.fromRawValue(orientation) ?? InputImageRotation.rotation90deg;
    }

    // Get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || (format != InputImageFormat.nv21 && format != InputImageFormat.yuv420)) {
      print('Unsupported image format: ${image.format.group}');
      return null;
    }
    
    // NV21 has planes[0] for Y and planes[1] for VU (interleaved)
    // YUV420 has planes[0] for Y, planes[1] for U, planes[2] for V
    if (image.planes.length < (format == InputImageFormat.nv21 ? 2 : 3)) {
        print('Invalid plane count for image format: ${image.planes.length}');
        return null;
    }

    // Concatenate planes data if YUV420
    Uint8List allBytes;
    if (format == InputImageFormat.yuv420) { // YUV420_888
        allBytes = Uint8List(image.planes.fold(0, (prev, plane) => prev + plane.bytes.length));
        int D=0;
        for(Plane plane in image.planes) {
            allBytes.setRange(D, D + plane.bytes.length, plane.bytes);
            D += plane.bytes.length;
        }
    } else { // NV21
        allBytes = image.planes[0].bytes; // For NV21, only Y plane data is needed by some MLKit plugins, but for others, you might need to combine or pass planes separately
                                         // Google ML Kit's Face Detection for Flutter typically expects combined data or handles planes internally
                                         // For NV21, it often expects the Y plane (planes[0]) and the VU plane (planes[1])
                                         // Let's try passing the Y plane first, as some implementations handle it.
                                         // If it fails, we might need to concatenate image.planes[0].bytes and image.planes[1].bytes.
                                         // However, the InputImage.fromBytes constructor expects all bytes in one list.
        // Let's combine Y and VU planes for NV21 as it's more robust
        if (image.planes.length > 1) {
            final yBytes = image.planes[0].bytes;
            final vuBytes = image.planes[1].bytes;
            allBytes = Uint8List(yBytes.length + vuBytes.length);
            allBytes.setRange(0, yBytes.length, yBytes);
            allBytes.setRange(yBytes.length, yBytes.length + vuBytes.length, vuBytes);
        } else {
             allBytes = image.planes[0].bytes; // Fallback if only one plane for NV21
        }
    }


    final inputImageData = InputImageData(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      imageRotation: rotation,
      inputImageFormat: format,
      planeData: image.planes.map(
        (Plane plane) {
          return InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          );
        },
      ).toList(),
    );

    return InputImage.fromBytes(bytes: allBytes, inputImageData: inputImageData);
  }


  @override
  void dispose() {
    _cameraController?.stopImageStream(); // Stop stream before disposing controller
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glasses Try-On'),
      ),
      body: Column( // Main layout changed to Column
        children: <Widget>[
          Expanded( // Camera preview and face detection take up available space
            child: widget.isLiveCamera
                ? _buildLiveCameraPreview()
                : Center( // Placeholder for Image Mode
                    child: Text(
                      'Image Mode - Selected: ${_selectedGlassesId ?? "None"}',
                      style: const TextStyle(fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          // Glasses Selection Widget at the bottom
          GlassesSelectionWidget(onGlassesSelected: _onGlassesSelected),
          // Optional: Display selected glasses ID for verification
          if (_selectedGlassesId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Selected: $_selectedGlassesId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ],
      ),
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
    if (_cameraController == null || !_cameraController!.value.isInitialized || !_isCameraInitialized) {
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
        if (_detectedFaces.isNotEmpty && _cameraController != null && _cameraController!.value.isInitialized)
          CustomPaint(
            painter: FacePainter(
              faces: _detectedFaces,
              absoluteImageSize: Size(
                _cameraController!.value.previewSize!.height,
                _cameraController!.value.previewSize!.width,
              ),
              cameraLensDirection: _cameraController!.description.lensDirection,
              glassesImage: _selectedGlassesImage, // Pass the selected glasses image
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
        )
      ],
    );
  }
}

// Custom Painter for Face Bounding Boxes
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

    final Paint glassesRectPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      // ..color = Colors.blue; // No longer needed for glassesRect visualization
      ..color = Colors.transparent; // Make it transparent or remove

    for (final Face face in faces) {
      final Rect boundingBox = face.boundingBox;
      final double scaleX = size.width / absoluteImageSize.width;
      final double scaleY = size.height / absoluteImageSize.height;

      Rect adjustedFaceBoundingBox;
      if (cameraLensDirection == CameraLensDirection.front) {
        final mirroredLeft = size.width - (boundingBox.left * scaleX + boundingBox.width * scaleX);
        final mirroredRight = size.width - (boundingBox.left * scaleX);
        adjustedFaceBoundingBox = Rect.fromLTRB(
          mirroredLeft,
          boundingBox.top * scaleY,
          mirroredRight,
          boundingBox.bottom * scaleY,
        );
      } else {
        adjustedFaceBoundingBox = Rect.fromLTRB(
          boundingBox.left * scaleX,
          boundingBox.top * scaleY,
          boundingBox.right * scaleX,
          boundingBox.bottom * scaleY,
        );
      }
      canvas.drawRect(adjustedFaceBoundingBox, facePaint);

      // Glasses positioning logic
      Rect glassesRect;
      final FaceLandmark? leftEyeLandmark = face.landmarks[FaceLandmarkType.leftEye];
      final FaceLandmark? rightEyeLandmark = face.landmarks[FaceLandmarkType.rightEye];

      if (leftEyeLandmark != null && rightEyeLandmark != null) {
        final Point<double> leftEyePos = Point(leftEyeLandmark.position.x.toDouble(), leftEyeLandmark.position.y.toDouble());
        final Point<double> rightEyePos = Point(rightEyeLandmark.position.x.toDouble(), rightEyeLandmark.position.y.toDouble());

        Point<double> scaledLeftEye = Point(leftEyePos.x * scaleX, leftEyePos.y * scaleY);
        Point<double> scaledRightEye = Point(rightEyePos.x * scaleX, rightEyePos.y * scaleY);

        if (cameraLensDirection == CameraLensDirection.front) {
          scaledLeftEye = Point(size.width - scaledLeftEye.x, scaledLeftEye.y);
          scaledRightEye = Point(size.width - scaledRightEye.x, scaledRightEye.y);
          // Swap if mirroring caused left to be right of right
          if (scaledLeftEye.x > scaledRightEye.x) {
            final Point<double> temp = scaledLeftEye;
            scaledLeftEye = scaledRightEye;
            scaledRightEye = temp;
          }
        }
        
        final Point<double> eyeCenter = Point(
          (scaledLeftEye.x + scaledRightEye.x) / 2,
          (scaledLeftEye.y + scaledRightEye.y) / 2,
        );
        final double eyeDistance = (scaledRightEye.x - scaledLeftEye.x).abs();
        
        const double glassesWidthFactor = 2.3; // Tunable factor for glasses width relative to eye distance
        const double glassesHeightFactor = 0.8; // Tunable factor for glasses height relative to eye distance (eye to top of glasses frame)
                                              // This is not aspect ratio but vertical positioning relative to eye center.
        const double glassesVerticalOffsetFactor = 0.4; // How much of the glasses height is *above* the eye center. 0.5 means centered.


        double glassesWidth = eyeDistance * glassesWidthFactor;
        double glassesHeight;

        if (glassesImage != null && glassesImage!.width > 0 && glassesImage!.height > 0) {
          glassesHeight = glassesWidth * (glassesImage!.height.toDouble() / glassesImage!.width.toDouble());
        } else {
          glassesHeight = glassesWidth / 2.5; // Fallback aspect ratio
        }
        
        glassesRect = Rect.fromLTWH(
          eyeCenter.x - (glassesWidth / 2),
          eyeCenter.y - (glassesHeight * glassesVerticalOffsetFactor), // Shift up based on factor
          glassesWidth,
          glassesHeight,
        );

      } else { // Fallback to bounding box if landmarks are not available
        double glassesWidth = adjustedFaceBoundingBox.width * 0.9;
        double glassesHeight;

        if (glassesImage != null && glassesImage!.width > 0 && glassesImage!.height > 0) {
          glassesHeight = glassesWidth * (glassesImage!.height.toDouble() / glassesImage!.width.toDouble());
        } else {
          glassesHeight = glassesWidth / 2.5; // Fallback aspect ratio
        }
        
        glassesRect = Rect.fromLTWH(
          adjustedFaceBoundingBox.left + (adjustedFaceBoundingBox.width - glassesWidth) / 2,
          adjustedFaceBoundingBox.top + adjustedFaceBoundingBox.height * 0.30 - glassesHeight / 2, // Adjusted for better placement
          glassesWidth,
          glassesHeight,
        );
      }
      // canvas.drawRect(glassesRect, glassesRectPaint); // Remove or comment out the blue rect

      // Draw the glasses image if available
      if (glassesImage != null) {
        final Rect srcRect = Rect.fromLTWH(
          0,
          0,
          glassesImage!.width.toDouble(),
          glassesImage!.height.toDouble(),
        );
        canvas.drawImageRect(glassesImage!, srcRect, glassesRect, Paint());
      }
    }
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.faces != faces ||
           oldDelegate.absoluteImageSize != absoluteImageSize ||
           oldDelegate.cameraLensDirection != cameraLensDirection ||
           oldDelegate.glassesImage != glassesImage; // Added glassesImage to condition
  }
}
