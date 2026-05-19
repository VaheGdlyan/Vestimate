import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/core/network/dio_provider.dart';
import 'package:vestimate/features/recommendation/domain/recommendation_provider.dart';

class StylistTab extends ConsumerStatefulWidget {
  const StylistTab({super.key});

  @override
  ConsumerState<StylistTab> createState() => _StylistTabState();
}

class _StylistTabState extends ConsumerState<StylistTab> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [
    _Message(
      text: "Hey! I'm your AI Stylist ✨\n\nI can help you put together outfits, suggest what to wear based on weather and occasion, or give you style advice. What's on your mind?",
      isAI: true,
    ),
  ];
  bool _isTyping = false;

  final List<String> _suggestions = [
    "Suggest a casual weekend outfit",
    "Help me dress for a job interview",
    "What goes with my blue jeans?",
    "Generate a new outfit for today",
  ];

  void _send(String text) {
    if (text.trim().isEmpty || _isTyping) return;
    setState(() {
      _messages.add(_Message(text: text, isAI: false));
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();
    
    final lower = text.toLowerCase();
    if (lower.contains('generate') || lower.contains('new outfit')) {
      ref.invalidate(todayRecommendationProvider);
    }

    _callChatAPI(text);
  }

  Future<void> _callChatAPI(String userMessage) async {
    // Build message history for context (last 10 messages)
    final history = _messages
        .where((m) => m.text != _messages.first.text) // exclude opening greeting
        .take(10)
        .map((m) => {'role': m.isAI ? 'assistant' : 'user', 'content': m.text})
        .toList();

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post('/chat', data: {
        'messages': history,
      });
      final reply = (response.data['reply'] as String?) ?? "I'm not sure how to respond to that. Try asking about outfits or style!";
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_Message(text: reply, isAI: true));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_Message(
            text: "I had trouble connecting. Check that the server is running and try again!",
            isAI: true,
          ));
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AI STYLIST', style: V.label),
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: V.accent, size: 20),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(V.s20),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _buildTypingIndicator();
                }
                return _buildMessage(_messages[index]);
              },
            ),
          ),
          _buildSuggestions(),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessage(_Message message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V.s16),
      child: Row(
        mainAxisAlignment: message.isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.isAI) ...[
            _glassAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: message.isAI ? Colors.white.withOpacity(0.05) : V.accent,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(message.isAI ? 4 : 20),
                  bottomRight: Radius.circular(message.isAI ? 20 : 4),
                ),
                border: message.isAI ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
              ),
              child: Text(
                message.text,
                style: V.body.copyWith(
                  color: message.isAI ? Colors.white : Colors.black,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (!message.isAI) ...[
            const SizedBox(width: 8),
            _userAvatar(),
          ],
        ],
      ),
    ).animate().fade(duration: 400.ms).slideX(begin: message.isAI ? -0.05 : 0.05);
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: V.s16),
      child: Row(
        children: [
          _glassAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                _Dot(), _Dot(), _Dot(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(_suggestions[index], style: V.label.copyWith(fontSize: 10, color: Colors.white70)),
              backgroundColor: Colors.white.withOpacity(0.05),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
              onPressed: () => _send(_suggestions[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                controller: _controller,
                style: V.body,
                decoration: const InputDecoration(
                  hintText: 'Ask anything...',
                  hintStyle: TextStyle(color: Colors.white24),
                  border: InputBorder.none,
                ),
                onSubmitted: _send,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: V.accent,
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
              onPressed: () => _send(_controller.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassAvatar() {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: V.accent.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: V.accent.withOpacity(0.2)),
      ),
      child: const Icon(Icons.auto_awesome, color: V.accent, size: 16),
    );
  }

  Widget _userAvatar() {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: Colors.white10,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person_outline, color: Colors.white60, size: 16),
    );
  }
}

class _Message {
  final String text;
  final bool isAI;
  _Message({required this.text, required this.isAI});
}

class _Dot extends StatefulWidget {
  const _Dot();
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
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
      builder: (context, child) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 4, height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3 + (_controller.value * 0.4)),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
