import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:vestimate/core/theme/theme.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _errorMsg = 'No cameras found on this device.';
          _isInitializing = false;
        });
        return;
      }

      // Use the first available camera (usually rear)
      _controller = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'Failed to initialize camera: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    HapticFeedback.mediumImpact();

    try {
      final XFile image = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, image);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture image: $e'), backgroundColor: V.danger),
      );
      setState(() {
        _isCapturing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Positioned.fill(
            child: _buildCameraPreview(),
          ),

          // Header
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: V.s24, vertical: V.s16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'SCAN GARMENT',
                      style: V.label.copyWith(color: Colors.white, letterSpacing: 2),
                    ),
                    const SizedBox(width: 48), // Balance for centering
                  ],
                ),
              ),
            ),
          ),

          // Viewfinder Overlay
          Positioned.fill(
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.height * 0.6,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                  borderRadius: BorderRadius.circular(V.r24),
                ),
              ),
            ),
          ),

          // Capture Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 48.0),
              child: GestureDetector(
                onTap: _captureImage,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _isCapturing ? Colors.white54 : Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator(color: V.accent));
    }
    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(V.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: V.danger, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMsg!,
                style: V.body.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    if (_controller == null) return const SizedBox.shrink();

    // Scale to fill screen
    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    return Transform.scale(
      scale: _controller!.value.aspectRatio / deviceRatio,
      child: Center(
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }
}
