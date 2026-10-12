// lib/screens/assistant_screen.dart
//
// In-app help assistant: the user asks "how do I ... in the app?" and gets
// step-by-step instructions plus "Open" buttons for the right screens.
// Backend: POST /api/assistant/chat (answers only from the app's user guide;
// it never reads or changes business data).
//
// The conversation is kept in memory while the app runs, so leaving the page
// through an "Open" button and coming back keeps it. It is cleared when a
// different user logs in.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../assistant/assistant_navigation.dart';
import '../assistant/help_entry.dart';
import '../constants.dart';

const Color _kNavy = Color(0xff1a2a6c);
const Color _kAccent = Color(0xfffdbb2d);
const Color _kBg = Color(0xfff4f6fb);

final RegExp _arabic = RegExp(r'[؀-ۿݐ-ݿ]');
TextDirection _dirOf(String text) => _arabic.hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;

class _ScreenLink {
  final String id;
  final String title;
  const _ScreenLink(this.id, this.title);
}

class _Msg {
  final bool fromUser;
  final String text;
  final List<_ScreenLink> screens;
  final bool isError;
  final bool notInGuide;
  const _Msg.user(this.text)
      : fromUser = true,
        screens = const [],
        isError = false,
        notInGuide = false;
  const _Msg.bot(this.text, {this.screens = const [], this.notInGuide = false})
      : fromUser = false,
        isError = false;
  const _Msg.error(this.text)
      : fromUser = false,
        screens = const [],
        isError = true,
        notInGuide = false;
}

/// Conversation memory for the running app (one user at a time).
class _Memory {
  static String? userId;
  static final List<_Msg> messages = [];
  static List<String> suggestions = [];
  static bool? enabled;
}

class AssistantScreen extends StatefulWidget {
  /// Id of the screen the user came from (helps the assistant answer
  /// "on this page..." questions). Optional.
  final String? contextScreen;

  const AssistantScreen({super.key, this.contextScreen});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  bool _loadingStatus = false;
  TextDirection _inputDir = TextDirection.ltr;
  String? _lastQuestion;

  List<_Msg> get _messages => _Memory.messages;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final d = _input.text.trim().isEmpty ? TextDirection.ltr : _dirOf(_input.text);
      if (d != _inputDir) setState(() => _inputDir = d);
    });
    _init();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final uid = await ApiConfig.storage.read(key: 'user_id');
    if (uid != _Memory.userId) {
      _Memory.userId = uid;
      _Memory.messages.clear();
      _Memory.suggestions = [];
      _Memory.enabled = null;
    }
    if (mounted) setState(() {});
    _scrollToEnd();
    if (_Memory.enabled == null || _Memory.suggestions.isEmpty) await _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final res = await ApiConfig.dio.get('/assistant/status');
      final data = res.data;
      if (data is Map) {
        _Memory.enabled = data['enabled'] == true;
        _Memory.suggestions = (data['suggestions'] as List? ?? []).map((e) => '$e').toList();
      }
    } catch (_) {
      // Status is only a hint; the chat call reports real errors.
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  /// Last exchanges sent as context (the server keeps only the last 8).
  List<Map<String, String>> _history() {
    final items = _messages.where((m) => !m.isError).toList();
    final start = items.length > 8 ? items.length - 8 : 0;
    return [
      for (final m in items.sublist(start)) {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
    ];
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _sending) return;
    final history = _history();
    setState(() {
      _sending = true;
      _lastQuestion = q;
      _messages.add(_Msg.user(q));
    });
    _input.clear();
    _scrollToEnd();
    try {
      final res = await ApiConfig.dio.post(
        '/assistant/chat',
        data: {
          'question': q,
          'history': history,
          if (widget.contextScreen != null) 'context_screen': widget.contextScreen,
        },
        // The global client waits 10 s; an answer can take longer.
        options: Options(receiveTimeout: const Duration(seconds: 45)),
      );
      final data = res.data is Map ? res.data as Map : const {};
      final screens = [
        for (final s in (data['screens'] as List? ?? const []))
          if (s is Map && s['id'] != null) _ScreenLink('${s['id']}', '${s['title'] ?? s['id']}'),
      ];
      _messages.add(_Msg.bot(
        '${data['answer'] ?? ''}'.trim(),
        screens: screens,
        notInGuide: data['found_in_guide'] == false,
      ));
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg;
      if (data is Map && data['message'] != null) {
        msg = '${data['message']}';
        if (data['code'] == 'ASSISTANT_DISABLED') _Memory.enabled = false;
      } else if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) {
        msg = 'The assistant took too long to answer. Please try again.';
      } else {
        msg = 'Could not reach the server. Check your connection and try again.';
      }
      _messages.add(_Msg.error(msg));
    } catch (_) {
      _messages.add(const _Msg.error('Something went wrong. Please try again.'));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _retry() {
    final q = _lastQuestion;
    if (q == null || _sending) return;
    setState(() {
      // Remove the failed question and its error, then ask again.
      if (_messages.isNotEmpty && _messages.last.isError) _messages.removeLast();
      if (_messages.isNotEmpty && _messages.last.fromUser) _messages.removeLast();
    });
    _send(q);
  }

  void _clear() {
    setState(() => _messages.clear());
  }

  void _open(_ScreenLink s) {
    final ok = AssistantNavigation.open(context, s.id);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${s.title}" cannot be opened from here.')),
      );
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final disabled = _Memory.enabled == false;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Row(children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: _kAccent,
            child: Icon(Icons.support_agent_rounded, color: _kNavy, size: 20),
          ),
          SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Team Flow Assistant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('How do I… in the app?', style: TextStyle(fontSize: 11.5, color: Colors.white70)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Browse help topics',
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => HelpEntry.openHelpCenter(contextScreen: widget.contextScreen),
          ),
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _sending ? null : _clear,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(children: [
              if (disabled) _disabledBanner(),
              Expanded(child: _messages.isEmpty ? _welcome() : _conversation()),
              _composer(disabled),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _disabledBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'The AI assistant is not enabled yet. Use "Browse help topics" (book icon above) to search the help.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ]),
      );

  Widget _welcome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: _kNavy.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.support_agent_rounded, size: 38, color: _kNavy),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Ask me how to do anything in Team Flow',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: _kNavy),
        ),
        const SizedBox(height: 6),
        Text(
          'I show you the steps and open the right page for you.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 24),
        if (_loadingStatus)
          const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _Memory.suggestions)
                ActionChip(
                  avatar: const Icon(Icons.lightbulb_outline_rounded, size: 16, color: _kNavy),
                  label: Text(s, textDirection: _dirOf(s)),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: _kNavy.withValues(alpha: 0.18)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onPressed: _Memory.enabled == false || _sending ? null : () => _send(s),
                ),
            ],
          ),
      ],
    );
  }

  Widget _conversation() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) return _typing();
        final m = _messages[i];
        return m.fromUser ? _userBubble(m) : _botBubble(m, isLast: i == _messages.length - 1);
      },
    );
  }

  Widget _userBubble(_Msg m) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(left: 48, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: _kNavy,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: SelectableText(
          m.text,
          textDirection: _dirOf(m.text),
          style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.45),
        ),
      ),
    );
  }

  Widget _botBubble(_Msg m, {required bool isLast}) {
    final dir = _dirOf(m.text);
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: m.isError ? Colors.red.shade50 : _kAccent.withValues(alpha: 0.25),
              child: Icon(
                m.isError ? Icons.error_outline_rounded : Icons.support_agent_rounded,
                size: 16,
                color: m.isError ? Colors.red.shade700 : _kNavy,
              ),
            ),
          ),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              margin: const EdgeInsets.only(right: 24, bottom: 12),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: m.isError ? Colors.red.shade50 : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: m.isError ? Colors.red.shade100 : const Color(0xffe3e7f0)),
              ),
              child: Column(
                crossAxisAlignment: dir == TextDirection.rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    m.text,
                    textDirection: dir,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: m.isError ? Colors.red.shade900 : const Color(0xff1f2937),
                    ),
                  ),
                  if (m.screens.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in m.screens)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _kNavy.withValues(alpha: 0.08),
                              foregroundColor: _kNavy,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: Text('Open ${s.title}'),
                            onPressed: () => _open(s),
                          ),
                      ],
                    ),
                  ],
                  if (m.isError && isLast && !_sending) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typing() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 36, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xffe3e7f0)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kNavy)),
          const SizedBox(width: 10),
          Text('Thinking…', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _composer(bool disabled) {
    final canSend = !disabled && !_sending;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xffe3e7f0))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              enabled: !disabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 600,
              textDirection: _inputDir,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Type your question… e.g. How do I generate payroll?',
                filled: true,
                fillColor: _kBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            style: IconButton.styleFrom(backgroundColor: _kNavy, disabledBackgroundColor: Colors.grey.shade300),
            onPressed: canSend ? () => _send() : null,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'The assistant explains how to use the app. It cannot see or change your data.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ]),
    );
  }
}
