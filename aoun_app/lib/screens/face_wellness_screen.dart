import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Facial Wellness Analyzer Screen
///
/// Captures a photo or video using the front-facing camera and sends it
/// to the ML service for OpenCV-based wellness analysis. Displays the
/// illness score (0-100) and the four clinical feature scores:
/// pallor, eye fatigue, skin uniformity, and skin dullness.
///
/// Analysis result is saved to the backend. If the result indicates
/// the patient appears unwell, a doctor alert is automatically created.

class FaceWellnessScreen extends StatefulWidget {
  final int patientId;
  const FaceWellnessScreen({super.key, required this.patientId});
  @override State<FaceWellnessScreen> createState() =>
      _FaceWellnessScreenState();
}

class _FaceWellnessScreenState extends State<FaceWellnessScreen> {
  // !! Replace with your actual PC IP !!
  static const String _mlUrl      = 'http://192.168.68.57:8001';
  static const String _backendUrl = 'http://192.168.68.57:8002';

  File?   _file;
  bool    _isVideo  = false;
  bool    _loading  = false;
  bool    _saving   = false;
  bool    _saved    = false;
  Map<String, dynamic>? _result;
  String? _error;
  final   _picker = ImagePicker();

  // ── PICK PHOTO (FRONT CAMERA) ─────────────────────────────
  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source:               ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality:         95,
      maxWidth:             1280,
    );
    if (picked != null) {
      setState(() {
        _file    = File(picked.path);
        _isVideo = false;
        _result  = null;
        _error   = null;
        _saved   = false;
      });
    }
  }

  // ── PICK PHOTO FROM GALLERY ───────────────────────────────
  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickImage(
      source:       ImageSource.gallery,
      imageQuality: 95,
      maxWidth:     1280,
    );
    if (picked != null) {
      setState(() {
        _file    = File(picked.path);
        _isVideo = false;
        _result  = null;
        _error   = null;
        _saved   = false;
      });
    }
  }

  // ── RECORD VIDEO ──────────────────────────────────────────
  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source:               ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxDuration:          const Duration(seconds: 10),
    );
    if (picked != null) {
      setState(() {
        _file    = File(picked.path);
        _isVideo = true;
        _result  = null;
        _error   = null;
        _saved   = false;
      });
    }
  }

  // ── ANALYZE ───────────────────────────────────────────────
  Future<void> _analyze() async {
    if (_file == null) return;
    setState(() {
      _loading = true;
      _result  = null;
      _error   = null;
      _saved   = false;
    });

    try {
      final endpoint = _isVideo ? '/analyze/video' : '/analyze/face';
      final uri      = Uri.parse('$_mlUrl$endpoint');
      final request  = http.MultipartRequest('POST', uri);
      if (_isVideo) {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          _file!.path,
          contentType: MediaType('video', 'mp4'),
        ));
      } else {
        // Detect file extension
        final ext = _file!.path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'png' : 'jpeg';
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          _file!.path,
          contentType: MediaType('image', mime),
        ));
      }

      final resp = await http.Response.fromStream(
          await request.send().timeout(const Duration(seconds: 45)));

      if (resp.statusCode == 200) {
        final result = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _result = result);
        await _saveResultToBackend(result);
      } else {
        // Parse FastAPI error
        try {
          final body = jsonDecode(resp.body);
          setState(() => _error = body['detail'] ?? 'Analysis failed (${resp.statusCode})');
        } catch (_) {
          setState(() => _error = 'Analysis failed. Status: ${resp.statusCode}');
        }
      }
    } catch (e) {
      setState(() => _error = 'Cannot reach ML service.\nCheck that backend is running.\n$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── SAVE RESULT TO BACKEND ────────────────────────────────
  Future<void> _saveResultToBackend(Map<String, dynamic> result) async {
    setState(() => _saving = true);
    try {
      final features = result['features'] as Map<String, dynamic>? ?? {};
      final body = {
        'prediction':    result['prediction'] ?? 'Unknown',
        'illness_score': result['illness_score'] ?? 0,
        'severity':      result['severity'] ?? 'low',
        'pallor_score':  features['pallor_score'],
        'eye_fatigue':   features['eye_fatigue'],
        'skin_dullness': features['skin_dullness'],
        'scan_type':     _isVideo ? 'video' : 'photo',
      };
      final res = await http.post(
        Uri.parse('$_backendUrl/patient/${widget.patientId}/wellness-scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (res.statusCode == 201) setState(() => _saved = true);
    } catch (_) {
      // Silent — result still shown even if save fails
    } finally {
      setState(() => _saving = false);
    }
  }

  // ── COLOR / ICON HELPERS ──────────────────────────────────
  Color _colorFor(String? code) {
    switch (code) {
      case 'green':  return Colors.green;
      case 'orange': return Colors.orange;
      case 'red':    return Colors.red;
      default:       return Colors.blueGrey;
    }
  }

  IconData _iconFor(String? code) {
    switch (code) {
      case 'green':  return Icons.sentiment_satisfied;
      case 'orange': return Icons.sentiment_neutral;
      case 'red':    return Icons.sentiment_very_dissatisfied;
      default:       return Icons.face;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FBF8),
      appBar: AppBar(
        title: const Text('Face Wellness Check'),
        backgroundColor: const Color(0xFF1D9E75),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // ── INFO CARD ──────────────────────────────────────
          Card(
            color: Colors.teal.shade50,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Row(children: [
                  Icon(Icons.face_retouching_natural,
                      color: Colors.teal),
                  SizedBox(width: 8),
                  Text('Visual Wellness Analysis',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                          fontSize: 15)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Take a clear front-facing selfie or a short 5–10 second '
                  'video. The camera will open in selfie mode. '
                  'Make sure your face is well-lit and fully visible.',
                  style: TextStyle(
                      color: Colors.teal.shade700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Icon(Icons.lock, color: Colors.orange, size: 14),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Your photo/video is NEVER stored. '
                        'Only the analysis score is saved.',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 12),

          // ── TIPS CARD ──────────────────────────────────────
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Row(children: [
                  Icon(Icons.tips_and_updates,
                      color: Colors.blue, size: 16),
                  SizedBox(width: 6),
                  Text('Tips for best results',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 13)),
                ]),
                const SizedBox(height: 6),
                _tipRow('Good natural or room lighting — no strong backlight'),
                _tipRow('Face the camera directly at eye level'),
                _tipRow('Hold phone at arm\'s length (40–60 cm)'),
                _tipRow('Remove glasses if possible'),
                _tipRow('Neutral expression, eyes open'),
              ]),
            ),
          ),

          const SizedBox(height: 16),

          // ── PREVIEW AREA ────────────────────────────────────
          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _file != null
                    ? const Color(0xFF1D9E75)
                    : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: _file == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.face,
                          size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text('No photo selected',
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Use one of the buttons below',
                          style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12)),
                    ])
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _isVideo
                        ? Center(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.videocam,
                                    size: 50,
                                    color: Color(0xFF1D9E75)),
                                const SizedBox(height: 8),
                                const Text('Video ready',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF1D9E75),
                                        fontWeight:
                                            FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                    _file!.path.split('/').last,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          )
                        : Image.file(_file!, fit: BoxFit.cover),
                  ),
          ),

          const SizedBox(height: 12),

          // ── CAPTURE BUTTONS ─────────────────────────────────
          Row(children: [
            Expanded(child: _outlineBtn(
                Icons.camera, 'Selfie\n(Front Cam)', _pickPhoto)),
            const SizedBox(width: 8),
            Expanded(child: _outlineBtn(
                Icons.photo_library, 'From\nGallery', _pickFromGallery)),
            const SizedBox(width: 8),
            Expanded(child: _outlineBtn(
                Icons.videocam, 'Record\nVideo', _pickVideo)),
          ]),

          const SizedBox(height: 20),

          // ── ANALYSE BUTTON ──────────────────────────────────
          if (_file != null)
            _loading
                ? Column(children: [
                    const CircularProgressIndicator(
                        color: Color(0xFF1D9E75)),
                    const SizedBox(height: 8),
                    Text(
                      _isVideo
                          ? 'Analysing video frames...'
                          : 'Analysing facial features...',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ])
                : SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _analyze,
                      icon: const Icon(Icons.analytics,
                          color: Colors.white),
                      label: const Text('Analyse Wellness',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF1D9E75),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                    ),
                  ),

          // ── ERROR ────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 16),
            _banner(_error!, Colors.red, Icons.error_outline),
          ],

          // ── SAVE STATUS ──────────────────────────────────────
          if (_saving) ...[
            const SizedBox(height: 12),
            const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Saving result...',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 12)),
                ]),
          ],
          if (_saved && !_saving) ...[
            const SizedBox(height: 12),
            const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle,
                      color: Colors.green, size: 16),
                  SizedBox(width: 6),
                  Text('Result saved — doctor notified if needed.',
                      style: TextStyle(
                          color: Colors.green, fontSize: 12)),
                ]),
          ],

          // ── RESULT ───────────────────────────────────────────
          if (_result != null) ...[
            const SizedBox(height: 24),
            _buildResult(_result!),
          ],

          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _tipRow(String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      const Icon(Icons.check, size: 13, color: Colors.blue),
      const SizedBox(width: 5),
      Expanded(child: Text(text,
          style: const TextStyle(color: Colors.blue, fontSize: 12))),
    ]),
  );

  Widget _buildResult(Map<String, dynamic> r) {
    final pred      = r['prediction'] as String? ?? 'Unknown';
    final score     = (r['illness_score'] as num?)?.toDouble() ?? 0.0;
    final colorCode = r['color_code']   as String? ?? 'green';
    final msg       = r['message']      as String? ?? '';
    final features  = r['features']     as Map<String, dynamic>? ?? {};
    final color     = _colorFor(colorCode);
    final icon      = _iconFor(colorCode);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            const Text('Wellness Result',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ]),
          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              Icon(icon, color: color, size: 40),
              const SizedBox(height: 8),
              Text(pred,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: score / 100,
                backgroundColor: color.withValues(alpha: 0.15),
                color: color,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 4),
              Text('Illness indicator: ${score.toStringAsFixed(0)}/100',
                  style: TextStyle(
                      color: color.withValues(alpha: 0.8),
                      fontSize: 12)),
            ]),
          ),

          if (features.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Feature breakdown',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 10),
            _featureRow('Skin pallor',
                (features['pallor_score'] as num?)?.toDouble() ?? 0,
                Colors.red),
            _featureRow('Eye fatigue',
                (features['eye_fatigue'] as num?)?.toDouble() ?? 0,
                Colors.orange),
            _featureRow('Skin uniformity',
                (features['skin_uniformity'] as num?)?.toDouble() ?? 0,
                Colors.purple),
            _featureRow('Skin dullness',
                (features['skin_dullness'] as num?)?.toDouble() ?? 0,
                Colors.brown),
          ],

          const SizedBox(height: 12),
          _banner(msg, color, Icons.info_outline),
          const SizedBox(height: 10),
          const Text(
            'Visual analysis only. Does not replace clinical assessment.',
            style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontStyle: FontStyle.italic),
          ),
        ]),
      ),
    );
  }

  Widget _featureRow(String label, double score, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Expanded(child: Text(label,
                style: const TextStyle(fontSize: 12))),
            Text('${score.toStringAsFixed(0)}/100',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 12)),
          ]),
          const SizedBox(height: 3),
          LinearProgressIndicator(
            value:           score / 100,
            backgroundColor: color.withValues(alpha: 0.12),
            color:           color,
            borderRadius:    BorderRadius.circular(4),
            minHeight:       5,
          ),
        ]),
      );

  Widget _outlineBtn(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF1D9E75)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: const Color(0xFF1D9E75), size: 20),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF1D9E75), fontSize: 11)),
        ]),
      );

  Widget _banner(String msg, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: TextStyle(color: color, fontSize: 13))),
        ]),
      );
}
