import 'package:flutter/material.dart';
import 'package:rive/rive.dart';
import 'package:vestimate/features/wardrobe/domain/task_polling_provider.dart';

class ProcessingOverlay extends StatefulWidget {
  final TaskStatus status;

  const ProcessingOverlay({
    super.key,
    required this.status,
  });

  @override
  State<ProcessingOverlay> createState() => _ProcessingOverlayState();
}

class _ProcessingOverlayState extends State<ProcessingOverlay> {
  StateMachineController? _controller;
  SMIBool? _isProcessing;
  SMIBool? _onSuccess;
  SMIBool? _onError;

  void _onRiveInit(Artboard artboard) {
    _controller = StateMachineController.fromArtboard(
      artboard,
      'State Machine 1', // Common default name, adjust as needed
    );
    if (_controller != null) {
      artboard.addController(_controller!);
      _isProcessing = _controller!.findSMI('isProcessing');
      _onSuccess = _controller!.findSMI('onSuccess');
      _onError = _controller!.findSMI('onError');
      
      _updateAnimationState();
    }
  }

  void _updateAnimationState() {
    if (_controller == null) return;

    switch (widget.status) {
      case TaskStatus.pending:
      case TaskStatus.processing:
        _isProcessing?.value = true;
        break;
      case TaskStatus.complete:
        _isProcessing?.value = false;
        _onSuccess?.value = true;
        break;
      case TaskStatus.failed:
        _isProcessing?.value = false;
        _onError?.value = true;
        break;
    }
  }

  @override
  void didUpdateWidget(ProcessingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _updateAnimationState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: RiveAnimation.asset(
            'assets/animations/wardrobe_processing.riv',
            onInit: _onRiveInit,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
