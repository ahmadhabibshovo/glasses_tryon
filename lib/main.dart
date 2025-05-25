import 'dart:async';
import 'dart:io'; // For File and Platform check
import 'dart:math' as math; // For Point
import 'dart:typed_data';
import 'dart:ui' as ui; // For ui.Image

import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemChrome and rootBundle
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// Camera plugin can be removed if only static image mode is needed
// import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  bool photosPermissionGranted = true;

  runApp(
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => MyApp(photosPermissionGranted: photosPermissionGranted),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool photosPermissionGranted;
  const MyApp({super.key, required this.photosPermissionGranted});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) => MaterialApp(
        useInheritedMediaQuery: true, // <-- Important for DevicePreview
        locale: DevicePreview.locale(context),
        builder: DevicePreview.appBuilder,
        title: 'Glasses Try-On',
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: photosPermissionGranted
            ? const TryOnScreen()
            : const PermissionDeniedScreen(
                permissionMessage:
                    'Photo library permission is required to select images.',
              ),
      ),
    );
  }
}

class PermissionDeniedScreen extends StatelessWidget {
  final String permissionMessage;
  const PermissionDeniedScreen({super.key, required this.permissionMessage});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permission Denied')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                permissionMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  openAppSettings();
                },
                child: const Text('Open App Settings'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// GlassesSelectionWidget remains the same as the previous version
class GlassesSelectionWidget extends StatelessWidget {
  final Function(String) onGlassesSelected;
  final List<String> glassesAssets = const [
    'assets/images/glasses2.png', // Ensure this path is correct
    'assets/images/glasses1.png', // Ensure this path is correct
    'assets/images/glass4.png', // Ensure this path is correct
    // 'assets/images/glasses2.png',
  ];

  const GlassesSelectionWidget({super.key, required this.onGlassesSelected});

  @override
  Widget build(BuildContext context) {
    if (glassesAssets.isEmpty) {
      return SizedBox(
          height: 100.h,
          child: Center(
              child: Text("No glasses to show.",
                  style: TextStyle(fontSize: 16.sp))));
    }
    return Container(
      height: 100.h,
      color: Colors.grey[200],
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: glassesAssets.length,
        itemBuilder: (context, index) {
          return _buildGlassesOption(context, glassesAssets[index]);
        },
      ),
    );
  }

  Widget _buildGlassesOption(BuildContext context, String assetPath) {
    return GestureDetector(
      onTap: () => onGlassesSelected(assetPath),
      child: Padding(
        padding: EdgeInsets.all(8.0.w),
        child: Container(
          width: 80.w,
          height: 80.w,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Padding(
            padding: EdgeInsets.all(4.0.w),
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                if (kDebugMode) {
                  print("Error loading asset image $assetPath: $error");
                }
                return Container(
                  color: Colors.red.withOpacity(0.1),
                  child:
                      Icon(Icons.broken_image, size: 40.sp, color: Colors.red),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class TryOnScreen extends StatefulWidget {
  const TryOnScreen({super.key});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  // Static Image related
  XFile? _pickedImageFile;
  ui.Image?
      _displayedUiImage; // Decoded image for drawing and getting dimensions
  Size? _staticImageOriginalSize; // Original dimensions of the picked image
  List<Face> _detectedFacesOnStaticImage = [];
  bool _isProcessingStaticImage = false;

  // Face Detector (can be reused)
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate, // Accurate for static images
      enableLandmarks: true,
      enableTracking: false, // Tracking not needed for static images
    ),
  );

  // Glasses Selection
  String? _selectedGlassesAssetPath;
  ui.Image? _selectedGlassesUiImage; // Changed from _selectedGlassesImage

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // No camera initialization needed here for static image mode
  }

  Future<void> _loadGlassesImage(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _selectedGlassesUiImage?.dispose();
          _selectedGlassesUiImage = frame.image;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Failed to load glasses image $assetPath: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load glasses: $assetPath')),
        );
        setState(() => _selectedGlassesUiImage = null);
      }
    }
  }

  void _onGlassesSelected(String glassesAssetPath) {
    setState(() {
      _selectedGlassesAssetPath = glassesAssetPath;
      if (_selectedGlassesAssetPath != null) {
        _loadGlassesImage(_selectedGlassesAssetPath!);
      } else {
        _selectedGlassesUiImage?.dispose();
        _selectedGlassesUiImage = null;
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isProcessingStaticImage) return;
    setState(() => _isProcessingStaticImage = true);

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80, // Reduce quality slightly for performance
      );

      if (pickedFile != null) {
        // Clear previous results
        setState(() {
          _pickedImageFile = pickedFile;
          _displayedUiImage?.dispose();
          _displayedUiImage = null;
          _staticImageOriginalSize = null;
          _detectedFacesOnStaticImage = [];
        });

        // Load the image into a ui.Image to get its dimensions and for drawing
        final Uint8List imageBytes = await pickedFile.readAsBytes();
        final codec = await ui.instantiateImageCodec(imageBytes);
        final frame = await codec.getNextFrame();

        if (mounted) {
          setState(() {
            _displayedUiImage = frame.image;
            _staticImageOriginalSize = Size(
              _displayedUiImage!.width.toDouble(),
              _displayedUiImage!.height.toDouble(),
            );
          });
          await _detectFacesOnPickedImage();
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingStaticImage = false);
      }
    }
  }

  Future<void> _detectFacesOnPickedImage() async {
    if (_pickedImageFile == null || _staticImageOriginalSize == null) return;

    try {
      // For static images, rotation is usually handled by EXIF,
      // but ML Kit's fromFilePath should try to interpret it.
      // If issues arise, one might need to read EXIF manually and provide rotation.
      final inputImage = InputImage.fromFilePath(_pickedImageFile!.path);

      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _detectedFacesOnStaticImage = faces;
        });
        if (kDebugMode) {
          print('Detected ${faces.length} faces on static image.');
        }
        if (faces.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No faces detected in the selected image.')),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error detecting faces on static image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error detecting faces: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _faceDetector.close();
    _selectedGlassesUiImage?.dispose();
    _displayedUiImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glasses Try-On (Image)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: 'Pick from Gallery',
            onPressed: () => _pickImage(ImageSource.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Take Photo',
            onPressed: () => _pickImage(ImageSource.camera),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _buildImageDisplayArea(),
            ),
            if (_isProcessingStaticImage)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            GlassesSelectionWidget(onGlassesSelected: _onGlassesSelected),
            if (_selectedGlassesAssetPath != null)
              Padding(
                padding: EdgeInsets.all(4.0.w),
                child: Text(
                  'Selected: [32m[1m[4m[7m${_selectedGlassesAssetPath!.split('/').last}[0m',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageDisplayArea() {
    if (_pickedImageFile == null ||
        _displayedUiImage == null ||
        _staticImageOriginalSize == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_search, size: 80.sp, color: Colors.grey.shade400),
            SizedBox(height: 16.h),
            Text(
              'Pick an image from Gallery\nor take a new photo to start.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16.sp, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Use LayoutBuilder to get the available space for the image
    // and to size the CustomPaint overlay correctly.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the display size of the image, maintaining aspect ratio
        final double imageAspectRatio =
            _staticImageOriginalSize!.width / _staticImageOriginalSize!.height;
        double displayWidth = constraints.maxWidth;
        double displayHeight = displayWidth / imageAspectRatio;

        if (displayHeight > constraints.maxHeight) {
          displayHeight = constraints.maxHeight;
          displayWidth = displayHeight * imageAspectRatio;
        }
        final Size displaySize = Size(displayWidth, displayHeight);

        return Stack(
          alignment: Alignment.center, // Center the image and overlay
          children: [
            // Display the picked image
            SizedBox(
              width: displaySize.width,
              height: displaySize.height,
              child: Image.file(
                File(_pickedImageFile!.path),
                fit: BoxFit.contain,
              ),
            ),
            // Overlay for detected faces and glasses
            if (_detectedFacesOnStaticImage.isNotEmpty &&
                _selectedGlassesUiImage != null)
              SizedBox(
                width: displaySize.width,
                height: displaySize.height,
                child: CustomPaint(
                  painter: StaticImageFacePainter(
                    faces: _detectedFacesOnStaticImage,
                    originalImageSize: _staticImageOriginalSize!,
                    displayWidgetSize: displaySize,
                    glassesImage: _selectedGlassesUiImage!,
                  ),
                ),
              ),
            Positioned(
              bottom: 10.h,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  'Faces: [32m[1m[4m[7m${_detectedFacesOnStaticImage.length}[0m',
                  style: TextStyle(color: Colors.white, fontSize: 14.sp),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class StaticImageFacePainter extends CustomPainter {
  final List<Face> faces;
  final Size originalImageSize; // Actual dimensions of the picked image
  final Size displayWidgetSize; // Size the image is rendered at on screen
  final ui.Image glassesImage;

  StaticImageFacePainter({
    required this.faces,
    required this.originalImageSize,
    required this.displayWidgetSize,
    required this.glassesImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // `size` is CustomPaint's size, should match displayWidgetSize
    if (originalImageSize.isEmpty || displayWidgetSize.isEmpty) return;

    final Paint faceDebugPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.blue.withOpacity(0.7);

    // Scaling factors from original image coordinates to display widget coordinates
    final double scaleX = displayWidgetSize.width / originalImageSize.width;
    final double scaleY = displayWidgetSize.height / originalImageSize.height;

    for (final Face face in faces) {
      Rect boundingBox = face.boundingBox; // Relative to originalImageSize

      // For static images, mirroring is usually not needed as EXIF typically handles orientation.
      // If ML Kit is giving coordinates that seem flipped on some images,
      // one might need to inspect image EXIF orientation or provide a manual flip option.
      // For now, assume coordinates are correct as per the image file.
      final Rect scaledBoundingBox = Rect.fromLTRB(
        boundingBox.left * scaleX,
        boundingBox.top * scaleY,
        boundingBox.right * scaleX,
        boundingBox.bottom * scaleY,
      );
      // canvas.drawRect(scaledBoundingBox, faceDebugPaint); // Optional: draw face box

      final FaceLandmark? leftEyeLandmark =
          face.landmarks[FaceLandmarkType.leftEye];
      final FaceLandmark? rightEyeLandmark =
          face.landmarks[FaceLandmarkType.rightEye];

      if (leftEyeLandmark != null && rightEyeLandmark != null) {
        // Landmark positions (relative to originalImageSize)
        math.Point<double> leftEyePos = math.Point(
            leftEyeLandmark.position.x.toDouble(),
            leftEyeLandmark.position.y.toDouble());
        math.Point<double> rightEyePos = math.Point(
            rightEyeLandmark.position.x.toDouble(),
            rightEyeLandmark.position.y.toDouble());

        // Scale landmark positions to the displayWidgetSize
        final math.Point<double> scaledLeftEye =
            math.Point(leftEyePos.x * scaleX, leftEyePos.y * scaleY);
        final math.Point<double> scaledRightEye =
            math.Point(rightEyePos.x * scaleX, rightEyePos.y * scaleY);

        final double eyeDistanceOnScreen =
            (scaledRightEye.x - scaledLeftEye.x).abs();
        if (eyeDistanceOnScreen <= 0) continue;

        // --- Fine-tune these factors for your glasses assets ---
        const double glassesWidthToEyeDistanceRatio = 1.8;
        const double glassesVerticalOffsetFactor =
            0.15; // % of glasses height to shift up
        // ---

        double glassesWidth =
            eyeDistanceOnScreen * glassesWidthToEyeDistanceRatio;
        double glassesHeight = glassesWidth *
            (glassesImage.height.toDouble() / glassesImage.width.toDouble());

        final math.Point<double> eyeCenterOnScreen = math.Point(
          (scaledLeftEye.x + scaledRightEye.x) / 2,
          (scaledLeftEye.y + scaledRightEye.y) / 2,
        );

        final Rect glassesRect = Rect.fromCenter(
          center: Offset(
              eyeCenterOnScreen.x,
              eyeCenterOnScreen.y -
                  (glassesHeight * glassesVerticalOffsetFactor - 4)),
          width: glassesWidth,
          height: glassesHeight,
        );

        double rotation = math.atan2(scaledRightEye.y - scaledLeftEye.y,
            scaledRightEye.x - scaledLeftEye.x);

        canvas.save();
        canvas.translate(glassesRect.center.dx, glassesRect.center.dy);
        canvas.rotate(rotation);
        canvas.translate(-glassesRect.center.dx, -glassesRect.center.dy);

        final Rect srcGlassesRect = Rect.fromLTWH(0, 0,
            glassesImage.width.toDouble(), glassesImage.height.toDouble());
        canvas.drawImageRect(
            glassesImage, srcGlassesRect, glassesRect, Paint());
        canvas.restore();
      } else {
        // Fallback using bounding box (less accurate)
        double glassesWidth = scaledBoundingBox.width * 0.9;
        double glassesHeight = glassesWidth *
            (glassesImage.height.toDouble() / glassesImage.width.toDouble());
        final Rect glassesRectFallback = Rect.fromCenter(
            center: scaledBoundingBox.center
                .translate(0, -scaledBoundingBox.height * 0.1),
            width: glassesWidth,
            height: glassesHeight);
        final Rect srcGlassesRect = Rect.fromLTWH(0, 0,
            glassesImage.width.toDouble(), glassesImage.height.toDouble());
        canvas.drawImageRect(
            glassesImage, srcGlassesRect, glassesRectFallback, Paint());
      }
    }
  }

  @override
  bool shouldRepaint(StaticImageFacePainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.originalImageSize != originalImageSize ||
        oldDelegate.displayWidgetSize != displayWidgetSize ||
        oldDelegate.glassesImage != glassesImage;
  }
}
