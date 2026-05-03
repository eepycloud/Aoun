import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../widgets/voice_input.dart';

/// Aoun Assistant — Chatbot Screen v4 (Mobile)
///
/// v4 switches voice input from the Web Speech API (Chrome only) to the
/// speech_to_text package, which works on Android and iOS.
///
/// Features:
/// - Mic button toggles voice listening session
/// - Interim transcripts appear in the text field in real time
/// - When the user stops speaking, a 3-second auto-send countdown appears
///   with a Cancel button
/// - Source panel shows which PDFs/FAQs grounded each response
/// - Thumbs up/down feedback updates RAG source weights in the backend
class ChatbotScreen extends StatefulWidget {
  final int patientId;
  const ChatbotScreen({super.key, required this.patientId});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _Source {
  final String sourceId;
  final String title;
  final String snippet;
  final String sourceType;
  final int? page;
  final String? category;

  _Source({
    required this.sourceId,
    required this.title,
    required this.snippet,
    required this.sourceType,
    this.page,
    this.category,
  });

  factory _Source.fromJson(Map<String, dynamic> j) => _Source(
        sourceId: j['source_id'] ?? '',
        title: j['title'] ?? 'Source',
        snippet: j['snippet'] ?? '',
        sourceType: j['source_type'] ?? 'knowledge',
        page: j['page'],
        category: j['category'],
      );
}

class _Msg {
  final String text;
  final bool isBot;
  final List<String> suggestions;
  final bool needsDoctor;
  final List<_Source> sources;
  final String messageId;
  final DateTime time;
  int rating;

  _Msg({
    required this.text,
    required this.isBot,
    this.suggestions = const [],
    this.needsDoctor = false,
    this.sources = const [],
    this.messageId = '',
    this.rating = 0,
  }) : time = DateTime.now();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const Color _brand = Color(0xFF1D9E75);

  final List<_Msg> _messages = [];
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  // -- Voice state --
  MobileVoiceInputController? _voiceController;
  bool _voiceSupported = false;
  bool _voiceListening = false;
  String _voiceInterim = '';
  bool _showCountdown = false;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _loadWelcome();
  }

  @override
  void dispose() {
    _voiceController?.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // -- Voice helpers --

  Future<void> _initVoice() async {
    // isSpeechRecognitionSupported() is async on mobile
    final supported = await isSpeechRecognitionSupported();
    if (!mounted) return;
    setState(() => _voiceSupported = supported);

    if (!supported) return;

    _voiceController = MobileVoiceInputController(
      language: 'en-US',
      onTranscript: (interim, finalText) {
        if (!mounted) return;
        setState(() {
          // Show whatever we have — interim while speaking, final when done
          _voiceInterim = interim;
          final display = finalText.isNotEmpty ? finalText : interim;
          _controller.text = display.trim();
          _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length));
        });
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _voiceListening = false;
          _voiceInterim = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
        ));
      },
      onEnd: () {
        if (!mounted) return;
        setState(() {
          _voiceListening = false;
          _voiceInterim = '';
        });
        // Trigger the auto-send countdown if something was captured
        if (_controller.text.trim().isNotEmpty) {
          setState(() => _showCountdown = true);
        }
      },
    );
  }

  void _toggleVoice() {
    if (_voiceListening) {
      _voiceController?.stop();
      return;
    }
    setState(() {
      _voiceListening = true;
      _voiceInterim = '';
      _showCountdown = false;
    });
    _voiceController?.start();
  }

  void _countdownSendNow() {
    setState(() => _showCountdown = false);
    _send(_controller.text);
  }

  void _countdownCancel() {
    setState(() => _showCountdown = false);
  }

  // -- Data helpers --

  List<_Source> _parseSources(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => _Source.fromJson(e))
          .toList();
    }
    return const [];
  }

  // -- API calls --

  Future<void> _loadWelcome() async {
    try {
      final reply = await ApiService.chatWelcome(widget.patientId);
      if (!mounted) return;
      setState(() => _messages.add(_Msg(
            text: reply['reply'] ?? 'Hello! How can I help?',
            isBot: true,
            suggestions: List<String>.from(reply['suggestions'] ?? []),
            needsDoctor: reply['needs_doctor'] ?? false,
            sources: _parseSources(reply['sources']),
            messageId: reply['message_id'] ?? '',
          )));
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.add(_Msg(
            text: "Hello! I'm your Aoun assistant. How can I help you today?",
            isBot: true,
            suggestions: const [
              "How am I doing?",
              "Show today's tips",
              "Any new alerts?",
            ],
          )));
    }
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _sending) return;

    setState(() {
      _messages.add(_Msg(text: msg, isBot: false));
      _sending = true;
      _showCountdown = false;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final reply = await ApiService.chatSend(widget.patientId, msg);
      if (!mounted) return;
      setState(() => _messages.add(_Msg(
            text: reply['reply'] ?? "Sorry, I didn't catch that.",
            isBot: true,
            suggestions: List<String>.from(reply['suggestions'] ?? []),
            needsDoctor: reply['needs_doctor'] ?? false,
            sources: _parseSources(reply['sources']),
            messageId: reply['message_id'] ?? '',
          )));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_Msg(
            text: "I'm having trouble connecting to the server. "
                "Please check your connection and try again.",
            isBot: true,
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _sendFeedback(_Msg msg, int rating) async {
    if (msg.messageId.isEmpty) return;
    final previous = msg.rating;
    setState(() => msg.rating = rating);

    try {
      final uri = Uri.parse(
          '${ApiService.baseUrl}/patient/${widget.patientId}/chat/feedback');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message_id': msg.messageId,
          'rating': rating,
        }),
      );
      if (!mounted) return;
      if (res.statusCode >= 300) {
        setState(() => msg.rating = previous);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Couldn't record feedback (${res.statusCode})"),
          duration: const Duration(seconds: 2),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(rating > 0
              ? "Thanks — I'll use this to improve answers."
              : "Got it — I'll deprioritize these sources."),
          duration: const Duration(seconds: 2),
          backgroundColor: rating > 0 ? _brand : Colors.grey.shade800,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => msg.rating = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Couldn't reach server: $e"),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSourceDialog(_Source s) {
    final icon = _iconForType(s.sourceType);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(icon, color: _brand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                _typeBadge(s.sourceType),
                if (s.page != null) ...[
                  const SizedBox(width: 8),
                  _pageBadge(s.page!),
                ],
                if (s.category != null) ...[
                  const SizedBox(width: 8),
                  _categoryBadge(s.category!),
                ],
              ]),
              const SizedBox(height: 12),
              Text(s.snippet,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF333333))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close',
                style: TextStyle(
                    color: _brand, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // -- Badge / icon helpers --

  IconData _iconForType(String t) {
    switch (t) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'conversation':
        return Icons.chat_bubble_outline;
      case 'faq':
      default:
        return Icons.menu_book_outlined;
    }
  }

  Color _colorForType(String t) {
    switch (t) {
      case 'pdf':
        return const Color(0xFFC0392B);
      case 'conversation':
        return const Color(0xFF8E44AD);
      case 'faq':
      default:
        return _brand;
    }
  }

  Widget _typeBadge(String t) {
    final label = t == 'pdf'
        ? 'PDF'
        : t == 'conversation'
            ? 'Past chat'
            : 'FAQ';
    final color = _colorForType(t);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _pageBadge(int page) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10)),
      child: Text('Page $page',
          style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 10.5,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _categoryBadge(String cat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10)),
      child: Text(cat,
          style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 10.5,
              fontWeight: FontWeight.w600)),
    );
  }

  // -- UI ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F7),
      appBar: AppBar(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        title: Row(children: const [
          CircleAvatar(
            backgroundColor: Colors.white24,
            child: Icon(Icons.smart_toy, color: Colors.white, size: 20),
          ),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aoun Assistant',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              Text('Online - here to help',
                  style:
                      TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Clear chat',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _messages.clear());
              _loadWelcome();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Disclaimer banner
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              Icon(Icons.info_outline,
                  color: Colors.amber.shade800, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "I'm not a doctor. For medical decisions, contact your oncologist.",
                  style: TextStyle(
                      color: Colors.amber.shade900, fontSize: 11),
                ),
              ),
            ]),
          ),
          // Message list
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_sending && i == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _buildMessage(_messages[i]);
                    },
                  ),
          ),
          // Voice listening banner
          if (_voiceListening)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(children: [
                Icon(Icons.mic, color: Colors.red.shade600, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _voiceInterim.isEmpty
                        ? "Listening… speak now"
                        : "Listening: $_voiceInterim",
                    style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _toggleVoice,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Stop',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          // Auto-send countdown
          if (_showCountdown)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: AutoSendCountdown(
                onSendNow: _countdownSendNow,
                onCancel: _countdownCancel,
                brand: _brand,
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessage(_Msg m) {
    if (m.isBot) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: _brand.withOpacity(0.15),
              child:
                  const Icon(Icons.smart_toy, size: 18, color: _brand),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border:
                          Border.all(color: Colors.grey.shade200),
                    ),
                    child: _FormattedText(text: m.text),
                  ),
                  if (m.sources.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _SourcesPanel(
                      sources: m.sources,
                      onTap: _showSourceDialog,
                      iconForType: _iconForType,
                      colorForType: _colorForType,
                    ),
                  ],
                  if (m.needsDoctor) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.medical_services,
                                size: 14,
                                color: Colors.red.shade700),
                            const SizedBox(width: 6),
                            Text('Please contact your doctor',
                                style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ]),
                    ),
                  ],
                  if (m.messageId.isNotEmpty && m.sources.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _FeedbackBar(
                      rating: m.rating,
                      onRate: (r) => _sendFeedback(m, r),
                    ),
                  ],
                  if (m.suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: m.suggestions
                          .map((s) => _SuggestionChip(
                                text: s,
                                onTap: () => _send(s),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    // User message — right aligned
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: _brand,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Text(m.text,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(children: [
          if (_voiceSupported) ...[
            MobileVoiceInputButton(
              listening: _voiceListening,
              enabled: !_sending,
              onTap: _toggleVoice,
              brand: _brand,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: _voiceListening
                    ? 'Listening…'
                    : 'Ask Aoun anything…',
                filled: true,
                fillColor: const Color(0xFFF2F4F3),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _brand,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sending ? null : () => _send(_controller.text),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child:
                    Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// -- Sub-widgets ------------------------------------------------

class _FeedbackBar extends StatelessWidget {
  final int rating;
  final void Function(int) onRate;
  const _FeedbackBar({required this.rating, required this.onRate});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Was this helpful?',
          style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500)),
      const SizedBox(width: 8),
      _FeedbackButton(
        icon: Icons.thumb_up_alt_outlined,
        activeIcon: Icons.thumb_up_alt,
        active: rating == 1,
        activeColor: const Color(0xFF1D9E75),
        onTap: () => onRate(1),
      ),
      const SizedBox(width: 4),
      _FeedbackButton(
        icon: Icons.thumb_down_alt_outlined,
        activeIcon: Icons.thumb_down_alt,
        active: rating == -1,
        activeColor: Colors.red.shade600,
        onTap: () => onRate(-1),
      ),
    ]);
  }
}

class _FeedbackButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _FeedbackButton({
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? activeColor.withOpacity(0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            active ? activeIcon : icon,
            size: 15,
            color: active ? activeColor : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

class _SourcesPanel extends StatefulWidget {
  final List<_Source> sources;
  final void Function(_Source) onTap;
  final IconData Function(String) iconForType;
  final Color Function(String) colorForType;

  const _SourcesPanel({
    required this.sources,
    required this.onTap,
    required this.iconForType,
    required this.colorForType,
  });

  @override
  State<_SourcesPanel> createState() => _SourcesPanelState();
}

class _SourcesPanelState extends State<_SourcesPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.sources.length;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF1D9E75).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Row(children: [
              const Icon(Icons.library_books_outlined,
                  size: 14, color: Color(0xFF1D9E75)),
              const SizedBox(width: 6),
              Text(
                'Based on $count source${count == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Color(0xFF1D9E75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                _expanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 18,
                color: const Color(0xFF1D9E75),
              ),
            ]),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.sources
                  .map((s) => _SourceChip(
                        source: s,
                        onTap: () => widget.onTap(s),
                        icon: widget.iconForType(s.sourceType),
                        color:
                            widget.colorForType(s.sourceType),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final _Source source;
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  const _SourceChip({
    required this.source,
    required this.onTap,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    String label = source.title;
    if (source.page != null) label += ' p.${source.page}';
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SuggestionChip(
      {required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1D9E75).withOpacity(0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 7),
          child: Text(text,
              style: const TextStyle(
                  color: Color(0xFF1D9E75),
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor:
              const Color(0xFF1D9E75).withOpacity(0.15),
          child: const Icon(Icons.smart_toy,
              size: 18, color: Color(0xFF1D9E75)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(0),
                  const SizedBox(width: 4),
                  _dot(1),
                  const SizedBox(width: 4),
                  _dot(2),
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _dot(int i) {
    final v = (_c.value * 3 - i).clamp(0.0, 1.0);
    final opacity =
        (v < 0.5 ? v * 2 : (1 - v) * 2).clamp(0.3, 1.0);
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF1D9E75),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _FormattedText extends StatelessWidget {
  final String text;
  const _FormattedText({required this.text});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final isBullet = line.trimLeft().startsWith('-') ||
            line.trimLeft().startsWith('*');
        return Padding(
          padding: EdgeInsets.only(
              left: isBullet ? 4 : 0, top: 2, bottom: 2),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 14,
                  height: 1.4),
              children: _parseBold(line),
            ),
          ),
        );
      }).toList(),
    );
  }

  List<InlineSpan> _parseBold(String line) {
    final parts = <InlineSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    int cursor = 0;
    for (final m in regex.allMatches(line)) {
      if (m.start > cursor) {
        parts.add(TextSpan(text: line.substring(cursor, m.start)));
      }
      parts.add(TextSpan(
        text: m.group(1),
        style:
            const TextStyle(fontWeight: FontWeight.bold),
      ));
      cursor = m.end;
    }
    if (cursor < line.length) {
      parts.add(TextSpan(text: line.substring(cursor)));
    }
    return parts;
  }
}
