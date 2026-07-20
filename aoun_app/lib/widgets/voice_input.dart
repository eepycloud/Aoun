import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

// ── CONTROLLER ────────────────────────────────────────────────
class MobileVoiceInputController {
  final String language;
  final void Function(String interim, String finalText) onTranscript;
  final void Function(String error) onError;
  final VoidCallback onEnd;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isAvailable = false;
  String _currentText = '';

  MobileVoiceInputController({
    this.language = 'en-US',
    required this.onTranscript,
    required this.onError,
    required this.onEnd,
  }) {
    _initializeSpeech();
  }

  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;

  Future<void> _initializeSpeech() async {
    _speech = stt.SpeechToText();

    // Request microphone permission before trying to initialize
    final permission = await Permission.microphone.status;
    if (permission.isDenied) {
      final result = await Permission.microphone.request();
      if (result.isDenied) {
        onError('Microphone permission required for voice input.');
        return;
      }
    }

    try {
      _isAvailable = await _speech.initialize(
        onError: (error) =>
            onError('Speech recognition error: ${error.errorMsg}'),
        onStatus: (status) {
          // 'done' fires when the device stops capturing (silence timeout)
          if (status == 'done' && _isListening) {
            _stopListening();
          }
        },
      );
    } catch (e) {
      onError('Could not initialize speech recognition: $e');
    }
  }

  Future<void> start() async {
    if (!_isAvailable) {
      onError('Speech recognition is not available on this device.');
      return;
    }
    if (_isListening) return;

    _currentText = '';

    try {
      await _speech.listen(
        onResult: (result) {
          _currentText = result.recognizedWords;
          if (result.finalResult) {
            // Confirmed final transcript — pass to screen
            onTranscript('', _currentText);
          } else {
            // Interim result — update text field in real time
            onTranscript(_currentText, '');
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: language,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );
      _isListening = true;
    } catch (e) {
      onError('Could not start listening: $e');
    }
  }

  void stop() {
    if (!_isListening) return;
    _stopListening();
  }

  void _stopListening() {
    _speech.stop();
    _isListening = false;
    onEnd();
  }

  void abort() {
    if (_isListening) {
      _speech.cancel();
      _isListening = false;
    }
  }

  void dispose() {
    abort();
  }
}

// ── MIC BUTTON ────────────────────────────────────────────────
class MobileVoiceInputButton extends StatelessWidget {
  final bool listening;
  final bool enabled;
  final VoidCallback onTap;
  final Color brand;

  const MobileVoiceInputButton({
    super.key,
    required this.listening,
    required this.enabled,
    required this.onTap,
    this.brand = const Color(0xFF1D9E75),
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = listening
        ? Colors.red.shade50
        : (enabled ? Colors.transparent : Colors.grey.shade100);

    final fgColor = listening
        ? Colors.red.shade600
        : (enabled ? Colors.grey.shade600 : Colors.grey.shade400);

    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: listening
              ? _PulsingMic(color: fgColor)
              : Icon(Icons.mic_none, size: 20, color: fgColor),
        ),
      ),
    );
  }
}

class _PulsingMic extends StatefulWidget {
  final Color color;
  const _PulsingMic({required this.color});

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final scale = 1.0 + 0.15 * _controller.value;
        final opacity = 0.7 + 0.3 * _controller.value;
        return Transform.scale(
          scale: scale,
          child: Icon(
            Icons.mic,
            size: 20,
            color: widget.color.withOpacity(opacity),
          ),
        );
      },
    );
  }
}

// ── AUTO-SEND COUNTDOWN ───────────────────────────────────────
class AutoSendCountdown extends StatefulWidget {
  final Duration duration;
  final VoidCallback onSendNow;
  final VoidCallback onCancel;
  final Color brand;

  const AutoSendCountdown({
    super.key,
    this.duration = const Duration(seconds: 3),
    required this.onSendNow,
    required this.onCancel,
    this.brand = const Color(0xFF1D9E75),
  });

  @override
  State<AutoSendCountdown> createState() => _AutoSendCountdownState();
}

class _AutoSendCountdownState extends State<AutoSendCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration)
          ..forward();
    _timer = Timer(widget.duration, () {
      if (mounted) widget.onSendNow();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    _timer?.cancel();
    _controller.stop();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.brand.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.brand.withOpacity(0.3)),
      ),
      child: Row(children: [
        SizedBox(
          width: 22,
          height: 22,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => CircularProgressIndicator(
              value: 1.0 - _controller.value,
              strokeWidth: 2.5,
              color: widget.brand,
              backgroundColor: widget.brand.withOpacity(0.2),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Sending in a moment…',
            style: TextStyle(
              color: widget.brand,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: _cancel,
          style: TextButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── SUPPORT CHECK ─────────────────────────────────────────────
/// Returns true if speech recognition is available on this device.
/// Must be awaited — initializes the plugin to probe availability.
Future<bool> isSpeechRecognitionSupported() async {
  final speech = stt.SpeechToText();
  try {
    return await speech.initialize();
  } catch (e) {
    return false;
  }
}
