import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../widgets/agent_cards/agent_card_dispatcher.dart';

class WorkioAiScreen extends StatefulWidget {
  final Function(int tabIndex)? onNavigateToTab;

  const WorkioAiScreen({
    super.key,
    this.onNavigateToTab,
  });

  @override
  State<WorkioAiScreen> createState() => _WorkioAiScreenState();
}

class _WorkioAiScreenState extends State<WorkioAiScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  String _conversationId = 'conv_${DateTime.now().millisecondsSinceEpoch}';

  late List<Map<String, dynamic>> _messages;

  @override
  void initState() {
    super.initState();
    _initChat();
    _loadChatHistory();
  }

  void _initChat() {
    _conversationId = 'conv_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    final timeStr = _formatTime(now);

    _messages = [
      {
        'sender': 'assistant',
        'isWelcome': true,
        'time': timeStr,
        'text':
            'Hi! I can help you find workers, create a community post, view your bookings or rate technicians. What would you like to do?',
      },
    ];
  }

  dynamic _sanitizeForJson(dynamic value) {
    if (value is Map) {
      final Map<String, dynamic> result = {};
      value.forEach((k, v) {
        result[k.toString()] = _sanitizeForJson(v);
      });
      return result;
    } else if (value is List) {
      return value.map((v) => _sanitizeForJson(v)).toList();
    } else if (value is num || value is bool || value is String || value == null) {
      return value;
    }
    return value.toString();
  }

  Future<void> _saveChatHistory() async {
    try {
      final user = AuthService().currentUser;
      final email = (user?.email ?? 'guest').toLowerCase().trim();
      final prefs = await SharedPreferences.getInstance();

      final convKey = 'workio_ai_chat_conv_id_$email';
      final msgsKey = 'workio_ai_chat_messages_$email';

      await prefs.setString(convKey, _conversationId);
      final sanitized = _messages.map((m) => _sanitizeForJson(m)).toList();
      await prefs.setString(msgsKey, jsonEncode(sanitized));
    } catch (e) {
      debugPrint('[WorkioAiScreen] Failed to save chat history: $e');
    }
  }

  Future<void> _loadChatHistory() async {
    final user = AuthService().currentUser;
    final email = (user?.email ?? 'guest').toLowerCase().trim();

    // 1. Fast load from local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final convKey = 'workio_ai_chat_conv_id_$email';
      final msgsKey = 'workio_ai_chat_messages_$email';

      final savedConvId = prefs.getString(convKey);
      final savedMsgsJson = prefs.getString(msgsKey);

      if (savedMsgsJson != null && savedMsgsJson.trim().isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(savedMsgsJson);
        final List<Map<String, dynamic>> loadedList = [];
        for (final item in decoded) {
          if (item is Map) {
            loadedList.add(Map<String, dynamic>.from(_sanitizeForJson(item) as Map));
          }
        }

        if (loadedList.isNotEmpty && mounted) {
          setState(() {
            if (savedConvId != null && savedConvId.isNotEmpty) {
              _conversationId = savedConvId;
            }
            _messages = loadedList;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('[WorkioAiScreen] Failed to load local chat history: $e');
    }

    // 2. Sync with database (Neon PostgreSQL) via Agent Backend
    if (email.isNotEmpty && email != 'guest') {
      try {
        String targetConvId = _conversationId;
        final dbConvs = await AiService().listConversations(email);
        if (dbConvs.isNotEmpty) {
          final firstId = dbConvs.first['id']?.toString();
          if (firstId != null && firstId.isNotEmpty) {
            targetConvId = firstId;
          }
        }

        if (targetConvId.isNotEmpty) {
          final dbMsgs = await AiService().getConversationMessages(targetConvId);
          if (dbMsgs.isNotEmpty && mounted) {
            final List<Map<String, dynamic>> dbList = [];
            for (final m in dbMsgs) {
              final isUser = m['sender'] == 'user';
              final createdStr = m['created_at']?.toString();
              String timeStr = _formatTime(DateTime.now());
              if (createdStr != null) {
                final dt = DateTime.tryParse(createdStr);
                if (dt != null) timeStr = _formatTime(dt.toLocal());
              }

              dbList.add({
                'sender': isUser ? 'user' : 'assistant',
                'isWelcome': false,
                'time': timeStr,
                'text': m['message']?.toString() ?? '',
                if (!isUser && m['card_data'] != null) 'card_data': m['card_data'],
                if (!isUser && m['response_type'] != null) 'response_type': m['response_type'],
              });
            }

            if (dbList.isNotEmpty && mounted) {
              setState(() {
                _conversationId = targetConvId;
                _messages = dbList;
              });
              _scrollToBottom();
              _saveChatHistory();
            }
          }
        }
      } catch (e) {
        debugPrint('[WorkioAiScreen] Failed to sync with remote DB: $e');
      }
    }
  }

  Future<void> _resetChat() async {
    final oldConvId = _conversationId;
    final user = AuthService().currentUser;
    final email = (user?.email ?? 'guest').toLowerCase().trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      final convKey = 'workio_ai_chat_conv_id_$email';
      final msgsKey = 'workio_ai_chat_messages_$email';

      await prefs.remove(convKey);
      await prefs.remove(msgsKey);
    } catch (e) {
      debugPrint('[WorkioAiScreen] Failed to clear local chat: $e');
    }

    if (oldConvId.isNotEmpty && email.isNotEmpty && email != 'guest') {
      unawaited(AiService().deleteConversation(oldConvId, email));
    }

    if (mounted) {
      _inputController.clear();
      setState(() {
        _initChat();
      });
      _scrollToBottom();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'New chat started',
            style: GoogleFonts.dmSans(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text, {Map<String, dynamic>? metadata}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    _inputController.clear();
    final now = DateTime.now();

    setState(() {
      _messages.add({
        'sender': 'user',
        'isWelcome': false,
        'time': _formatTime(now),
        'text': clean,
      });
      _isLoading = true;
    });
    _scrollToBottom();
    _saveChatHistory();

    final user = AuthService().currentUser;
    final email = user?.email ?? 'guest@superbass.lk';
    final role = user?.activeRole ?? 'Resident';

    try {
      final res = await AiService().sendMessage(
        message: clean,
        email: email,
        userType: role,
        conversationId: _conversationId,
        metadata: metadata,
      );

      final respData = res['response'] as Map<String, dynamic>?;
      final replyMsg = respData?['message']?.toString() ??
          'I am processing your request. Please let me know how else I can help you.';

      if (mounted) {
        setState(() {
          _isLoading = false;
          _messages.add({
            'sender': 'assistant',
            'isWelcome': false,
            'time': _formatTime(DateTime.now()),
            'text': replyMsg,
            'card_data': respData?['card_data'],
            'response_type': respData?['response_type'],
          });
        });
        _scrollToBottom();
        _saveChatHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _messages.add({
            'sender': 'assistant',
            'isWelcome': false,
            'time': _formatTime(DateTime.now()),
            'text': 'I encountered an error connecting to the agent network. Please try again.',
          });
        });
        _scrollToBottom();
        _saveChatHistory();
      }
    }
  }

  void _handleActionCardTap(String actionKey) {
    if (actionKey == 'find_workers') {
      _sendMessage('Find top-rated verified professionals near me');
    } else if (actionKey == 'create_post') {
      _sendMessage('I want to create a community service request post');
    } else if (actionKey == 'see_bookings') {
      _sendMessage('Show my active bookings and schedule');
    } else if (actionKey == 'rate_workers') {
      _sendMessage('Show completed bookings to rate technicians');
    }
  }

  void _handleCardAction(String actionType, dynamic payload) {
    if (actionType == 'navigate') {
      final String route = payload?.toString() ?? '';
      if (route.contains('/find') || route.contains('find')) {
        if (widget.onNavigateToTab != null) {
          Navigator.pop(context);
          widget.onNavigateToTab!(0);
        } else {
          _sendMessage('Find top-rated workers near me');
        }
      } else if (route.contains('/community') || route.contains('community')) {
        if (widget.onNavigateToTab != null) {
          Navigator.pop(context);
          widget.onNavigateToTab!(1);
        } else {
          _sendMessage('Show recent community posts');
        }
      } else if (route.contains('/bookings') || route.contains('booking')) {
        if (widget.onNavigateToTab != null) {
          Navigator.pop(context);
          widget.onNavigateToTab!(2);
        } else {
          _sendMessage('Show my active bookings');
        }
      }
    } else if (actionType == 'select_post') {
      final postId = payload is Map ? (payload['id'] ?? payload['postId']) : payload;
      if (postId != null) {
        _sendMessage('Show details for post #$postId');
      }
    } else if (actionType == 'view_community') {
      if (widget.onNavigateToTab != null) {
        Navigator.pop(context);
        widget.onNavigateToTab!(1);
      } else {
        _sendMessage('Show community posts');
      }
    } else if (actionType == 'edit_post') {
      final p = payload is Map ? payload : {};
      final postId = p['id'] ?? p['postId'] ?? '1';
      setState(() {
        _messages.add({
          'sender': 'assistant',
          'isWelcome': false,
          'time': _formatTime(DateTime.now()),
          'text': "Please edit the details for post #$postId below and tap 'Save Changes':",
          'response_type': 'edit_community_post',
          'card_data': {
            'action': 'update',
            'postId': postId,
            'title': p['title'] ?? '',
            'content': p['content'] ?? '',
            'location': p['location'] ?? 'Colombo',
          },
        });
      });
      _scrollToBottom();
      _saveChatHistory();
    } else if (actionType == 'book_worker') {
      final w = payload is Map ? payload : {};
      final workerId = (w['id'] ?? w['workerId'] ?? '').toString();
      final workerName = w['name'] ?? 'technician';
      final idStr = workerId.isNotEmpty ? ' (Worker ID: $workerId)' : '';
      _sendMessage('I would like to book $workerName$idStr');
    } else if (actionType == 'view_worker') {
      final w = payload is Map ? payload : {};
      final name = w['name'] ?? 'Worker';
      final id = w['id'] ?? w['workerId'] ?? '';
      _sendMessage('Show details and reviews for $name (Worker ID: $id)');
    } else if (actionType == 'review_worker') {
      final b = payload is Map ? payload : {};
      final bId = (b['id'] ?? b['bookingId'] ?? '').toString();
      final workerName = b['workerName']?.toString() ?? 'technician';
      final workerId = (b['workerId'] ?? '').toString();
      final status = (b['status'] ?? '').toString().toLowerCase();
      final isCompleted = status.contains('complete') || status.contains('done') || status.contains('reviewed');

      if (bId.isNotEmpty && !isCompleted) {
        _sendMessage('Can I review booking #$bId with $workerName?');
      } else if (bId.isNotEmpty) {
        final wStr = workerId.isNotEmpty ? ' (Worker ID: $workerId)' : '';
        _sendMessage('I would like to review $workerName$wStr for completed booking #$bId');
      } else {
        _sendMessage('Show completed bookings to rate technicians');
      }
    } else if (actionType == 'send_prompt' ||
        actionType == 'confirm_post' ||
        actionType == 'confirm_update' ||
        actionType == 'confirm_booking') {
      if (payload is Map) {
        final prompt = (payload['prompt'] ?? payload['text'] ?? '').toString();
        final Map<String, dynamic> extraMeta = {};
        if (payload['bookingData'] != null) {
          extraMeta['booking_data'] = payload['bookingData'];
        }
        if (payload['postData'] != null) {
          extraMeta['post_data'] = payload['postData'];
        }
        if (payload['reviewData'] != null) {
          extraMeta['review_data'] = payload['reviewData'];
        }
        if (payload['action'] != null) {
          extraMeta['action'] = payload['action'];
        }
        _sendMessage(prompt, metadata: extraMeta);
      } else {
        _sendMessage(payload.toString());
      }
    } else if (actionType == 'retry') {
      final lastUserMsg = _messages.reversed.firstWhere(
        (m) => m['sender'] == 'user',
        orElse: () => {},
      );
      if (lastUserMsg['text'] != null) {
        _sendMessage(lastUserMsg['text']);
      }
    } else if (payload is String) {
      _sendMessage(payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Chat Stream
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDatePill('Today'),
                        const SizedBox(height: 16),
                        _buildMessageItem(_messages[0]),
                      ],
                    );
                  }

                  if (index < _messages.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _buildMessageItem(_messages[index]),
                    );
                  }

                  // Loading bubble
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _buildLoadingBubble(),
                  );
                },
              ),
            ),

            // Bottom Section: Input Bar
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Center(
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F3F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
      titleSpacing: 8,
      title: Row(
        children: [
          // Black Circular Logo with White W
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(7),
            child: Image.asset(
              'assets/images/Workio_Logo_White_WithOut_Text.png',
              fit: BoxFit.contain,
              errorBuilder: (_, error, stackTrace) => const Center(
                child: Text(
                  'W',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Workio AI',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Tooltip(
              message: 'New Chat',
              child: InkWell(
                onTap: _resetChat,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: const Color(0xFFF1F3F5),
          height: 1,
        ),
      ),
    );
  }

  Widget _buildDatePill(String text) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    final isAssistant = msg['sender'] == 'assistant';
    final isWelcome = msg['isWelcome'] == true;

    if (!isAssistant) {
      // User outgoing message
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              msg['text'] ?? '',
              style: GoogleFonts.dmSans(
                fontSize: 14.5,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            msg['time'] ?? '',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      );
    }

    // Assistant incoming message
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Small Circular Logo Avatar
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(top: 2),
          decoration: const BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(6),
          child: Image.asset(
            'assets/images/Workio_Logo_White_WithOut_Text.png',
            fit: BoxFit.contain,
            errorBuilder: (_, error, stackTrace) => const Center(
              child: Text(
                'W',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bubble
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Text(
                  msg['text'] ?? '',
                  style: GoogleFonts.dmSans(
                    fontSize: 14.5,
                    color: const Color(0xFF0F172A),
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),

              // Embedded Action Cards (shown on welcome message)
              // Embedded Action Cards (shown on welcome message) - Horizontally scrollable row
              if (isWelcome) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildActionCard(
                        title: 'Find workers',
                        subtitle: 'Trusted pros near you',
                        icon: Icons.search_rounded,
                        onTap: () => _handleActionCardTap('find_workers'),
                      ),
                      _buildActionCard(
                        title: 'Community post',
                        subtitle: 'Post your service needs',
                        icon: Icons.chat_bubble_outline_rounded,
                        onTap: () => _handleActionCardTap('create_post'),
                      ),
                      _buildActionCard(
                        title: 'My bookings',
                        subtitle: 'Upcoming & past jobs',
                        icon: Icons.calendar_today_outlined,
                        onTap: () => _handleActionCardTap('see_bookings'),
                      ),
                      _buildActionCard(
                        title: 'Rate workers',
                        subtitle: 'Review completed services',
                        icon: Icons.star_outline_rounded,
                        onTap: () => _handleActionCardTap('rate_workers'),
                      ),
                    ],
                  ),
                ),
              ],

              // Structured AI Response Cards
              if (!isWelcome && (msg['response_type'] != null || msg['card_data'] != null))
                AgentCardDispatcher(
                  responseType: msg['response_type']?.toString(),
                  cardData: msg['card_data'] is Map<String, dynamic>
                      ? msg['card_data'] as Map<String, dynamic>
                      : (msg['card_data'] is Map
                          ? Map<String, dynamic>.from(msg['card_data'] as Map)
                          : null),
                  message: msg['text']?.toString(),
                  onAction: _handleCardAction,
                ),

              const SizedBox(height: 4),
              Text(
                msg['time'] ?? '',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 195,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(6),
          child: Image.asset(
            'assets/images/Workio_Logo_White_WithOut_Text.png',
            fit: BoxFit.contain,
            errorBuilder: (_, error, stackTrace) => const Center(
              child: Text('W', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Workio AI is thinking...',
                style: GoogleFonts.dmSans(
                  fontSize: 13.5,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F3F5))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  style: GoogleFonts.dmSans(
                    fontSize: 14.5,
                    color: Colors.black,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sendMessage,
                  decoration: InputDecoration(
                    hintText: 'Ask anything or create a post',
                    hintStyle: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Solid Black Circular Send Button
            GestureDetector(
              onTap: () => _sendMessage(_inputController.text),
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
