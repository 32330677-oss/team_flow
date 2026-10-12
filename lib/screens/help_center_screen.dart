// lib/screens/help_center_screen.dart
//
// Help Center: searchable "how do I ..." topics for the user's role, with an
// "Open" button that takes the user to the right screen.
// No AI and no API key needed: the topics come from the app's user guide on
// the server (GET /api/assistant/guide, filtered by role), so updating the
// guide updates the help for everyone without a new app release.

import 'package:flutter/material.dart';

import '../assistant/assistant_navigation.dart';
import '../assistant/help_entry.dart';
import '../constants.dart';

const Color _kNavy = Color(0xff1a2a6c);
const Color _kAccent = Color(0xfffdbb2d);
const Color _kBg = Color(0xfff4f6fb);
const Color _kInk = Color(0xff1f2937);
const Color _kLine = Color(0xffe3e7f0);

class HelpSection {
  final String id;
  final String title;
  final String body;
  final List<String> keywords;
  final String? screenId;
  final String? screenTitle;

  // Search tokens, computed once.
  late final List<String> _titleWords = _words(title);
  late final List<String> _keywordWords = _words(keywords.join(' '));
  late final List<String> _bodyWords = _words(body);

  HelpSection({
    required this.id,
    required this.title,
    required this.body,
    required this.keywords,
    this.screenId,
    this.screenTitle,
  });

  factory HelpSection.fromJson(Map json) {
    final screen = json['screen'];
    return HelpSection(
      id: '${json['id']}',
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      keywords: [for (final k in (json['keywords'] as List? ?? const [])) '$k'],
      screenId: screen is Map ? '${screen['id']}' : null,
      screenTitle: screen is Map ? '${screen['title']}' : null,
    );
  }

  /// First sentence of the body without formatting, for list subtitles.
  String get preview {
    final first = body.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return first.replaceFirst(RegExp(r'^(\d+\.|-)\s*'), '').replaceAll('"', '');
  }
}

// ------------------------------------------------------------------ search

const Set<String> _stopWords = {
  'how', 'do', 'does', 'i', 'to', 'a', 'an', 'the', 'in', 'on', 'my', 'can', 'what', 'where', 'is', 'are',
  'for', 'of', 'and', 'it', 'me', 'with', 'we', 'you', 'be', 'this', 'that', 'there', 'at', 'or', 'please',
  'want', 'need', 'should', 'when', 'from', 'by', 'up', 'get', 'make', 'as', 'not', 'give', 'new', 'some',
  'all', 'set', 'use', 'done', 'doing', 'way', 'help', 'app',
};

/// Very small English stemmer: "mapped" → "map", "approving" → "approv",
/// "salaries" → "salar". Matching is by prefix, so this is enough.
String _stem(String w) {
  var s = w;
  for (final suffix in const ['ing', 'ies', 'ed', 'es', 's']) {
    if (s.length - suffix.length >= 3 && s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
      break;
    }
  }
  // "mapp" → "map", "cancell" → "cancel"
  if (s.length >= 4 && s[s.length - 1] == s[s.length - 2]) s = s.substring(0, s.length - 1);
  return s;
}

List<String> _words(String text) =>
    text.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 2).toList();

/// "workers" matches "worker", "approve" matches "approved"...
bool _wordMatches(String word, String term) {
  if (word == term) return true;
  if (term.length >= 3 && word.startsWith(term)) return true;
  if (word.length >= 4 && term.startsWith(word)) return true;
  return false;
}

class _Hit {
  final HelpSection section;
  final int score;
  final int matched;
  final bool allTerms;
  _Hit(this.section, this.score, this.matched, this.allTerms);
}

/// Returns (results, exact): exact is false when no topic matched every word
/// and the results are only related topics.
(List<HelpSection>, bool) searchHelp(List<HelpSection> sections, String query) {
  final terms = _words(query).where((t) => !_stopWords.contains(t)).map(_stem).toList();
  if (terms.isEmpty) return (sections, true);
  final hits = <_Hit>[];
  for (final s in sections) {
    var score = 0;
    var matched = 0;
    for (final t in terms) {
      var termScore = 0;
      if (s._titleWords.any((w) => _wordMatches(w, t))) termScore += 6;
      if (s._keywordWords.any((w) => _wordMatches(w, t))) termScore += 4;
      if (s._bodyWords.any((w) => _wordMatches(w, t))) termScore += 1;
      if (termScore > 0) matched++;
      score += termScore;
    }
    if (score > 0) hits.add(_Hit(s, score, matched, matched == terms.length));
  }
  final exact = hits.where((h) => h.allTerms).toList();
  final list = exact.isNotEmpty ? exact : hits;
  // More matched words first, then the higher score.
  list.sort((a, b) => a.matched != b.matched ? b.matched.compareTo(a.matched) : b.score.compareTo(a.score));
  return ([for (final h in list.take(15)) h.section], exact.isNotEmpty);
}

// ------------------------------------------------------------------ data

class _HelpData {
  static String? userId;
  static List<HelpSection> sections = [];
  static List<String> popular = [];
}

// ------------------------------------------------------------------ Help Center

class HelpCenterScreen extends StatefulWidget {
  /// Screen the user came from: its topics are shown first ("On this page").
  final String? contextScreen;

  const HelpCenterScreen({super.key, this.contextScreen});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final uid = await ApiConfig.storage.read(key: 'user_id');
    if (!force && uid == _HelpData.userId && _HelpData.sections.isNotEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await ApiConfig.dio.get('/assistant/guide');
      final data = res.data is Map ? res.data as Map : const {};
      _HelpData.userId = uid;
      _HelpData.sections = [
        for (final s in (data['sections'] as List? ?? const []))
          if (s is Map) HelpSection.fromJson(s),
      ];
      _HelpData.popular = [for (final p in (data['popular'] as List? ?? const [])) '$p'];
    } catch (_) {
      _error = 'Could not load the help topics. Check your connection and try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTopic(HelpSection s) {
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: HelpEntry.topicRoute),
      builder: (_) => HelpTopicScreen(section: s),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Help Center', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text('How do I… in Team Flow', style: TextStyle(fontSize: 11.5, color: Colors.white70)),
        ]),
        actions: [
          if (HelpEntry.aiEnabled == true)
            IconButton(
              tooltip: 'Ask the AI assistant',
              icon: const Icon(Icons.support_agent_rounded),
              onPressed: () => HelpEntry.openAssistantChat(contextScreen: widget.contextScreen),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(children: [
              _searchBar(),
              Expanded(child: _content()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: _kNavy,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search: payroll, attendance, advance, transfer…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: _search.clear),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kNavy));
    if (_error != null) {
      return _message(Icons.cloud_off_rounded, _error!, action: TextButton.icon(
        onPressed: () => _load(force: true),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ));
    }
    final all = _HelpData.sections;
    if (all.isEmpty) return _message(Icons.menu_book_rounded, 'No help topics are available for your account.');

    final q = _search.text.trim();
    if (q.isNotEmpty) {
      final (results, exact) = searchHelp(all, q);
      if (results.isEmpty) {
        return _message(Icons.search_off_rounded,
            'No topic matches "$q".\nTry another word, for example "payroll", "attendance" or "transfer".');
      }
      return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        _sectionLabel(exact ? '${results.length} topic${results.length == 1 ? '' : 's'} found' : 'No exact match. Related topics:'),
        _topicCard(results),
      ]);
    }

    final here = widget.contextScreen == null
        ? <HelpSection>[]
        : all.where((s) => s.screenId == widget.contextScreen).toList();
    final popular = [
      for (final id in _HelpData.popular)
        ...all.where((s) => s.id == id && !here.contains(s)),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      if (here.isNotEmpty) ...[
        _sectionLabel('On this page'),
        _topicCard(here),
        const SizedBox(height: 20),
      ],
      if (popular.isNotEmpty) ...[
        _sectionLabel('Popular topics'),
        _topicCard(popular),
        const SizedBox(height: 20),
      ],
      _sectionLabel('All topics (${all.length})'),
      _topicCard(all),
    ]);
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
      );

  Widget _topicCard(List<HelpSection> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kLine),
      ),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 56, color: _kLine),
          ListTile(
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: _kNavy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(9)),
              child: Icon(items[i].screenId == null ? Icons.info_outline_rounded : Icons.article_outlined, size: 19, color: _kNavy),
            ),
            title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: _kInk)),
            subtitle: Text(items[i].preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: () => _openTopic(items[i]),
          ),
        ],
      ]),
    );
  }

  Widget _message(IconData icon, String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 8), action],
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ topic

class HelpTopicScreen extends StatelessWidget {
  final HelpSection section;

  const HelpTopicScreen({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final related = _HelpData.sections
        .where((s) => s.id != section.id && s.screenId != null && s.screenId == section.screenId)
        .take(4)
        .toList();
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Help', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 24), children: [
              Text(section.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: _kNavy)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kLine),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final line in section.body.split('\n')) if (line.trim().isNotEmpty) _line(line.trim())],
                ),
              ),
              if (section.screenId != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kNavy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text('Open ${section.screenTitle}'),
                    onPressed: () {
                      final ok = AssistantNavigation.open(context, section.screenId!);
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('"${section.screenTitle}" cannot be opened from here.')),
                        );
                      }
                    },
                  ),
                ),
              ],
              if (related.isNotEmpty) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('RELATED TOPICS',
                      style: TextStyle(fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                ),
                for (final r in related)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kLine)),
                    child: ListTile(
                      dense: true,
                      title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600, color: _kInk)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                        settings: const RouteSettings(name: HelpEntry.topicRoute),
                        builder: (_) => HelpTopicScreen(section: r),
                      )),
                    ),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  /// One line of the guide: numbered step, bullet or paragraph.
  Widget _line(String line) {
    final step = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
    final bullet = RegExp(r'^-\s+(.*)$').firstMatch(line);
    Widget lead;
    String text;
    if (step != null) {
      lead = Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.only(top: 1),
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: _kNavy, shape: BoxShape.circle),
        child: Text(step.group(1)!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      );
      text = step.group(2)!;
    } else if (bullet != null) {
      lead = Container(
        width: 24,
        alignment: Alignment.center,
        padding: const EdgeInsets.only(top: 8),
        child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle)),
      );
      text = bullet.group(1)!;
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(_rich(line), style: const TextStyle(fontSize: 14.5, height: 1.5, color: _kInk)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        lead,
        const SizedBox(width: 10),
        Expanded(child: Text.rich(_rich(text), style: const TextStyle(fontSize: 14.5, height: 1.5, color: _kInk))),
      ]),
    );
  }

  /// Button and screen names are written "like this" in the guide: show them bold.
  TextSpan _rich(String text) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'"([^"]+)"');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700, color: _kNavy),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(children: spans);
  }
}
