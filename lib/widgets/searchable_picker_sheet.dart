import 'package:flutter/material.dart';

class SearchablePickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final String? Function(T item)? subtitleBuilder;

  const SearchablePickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.labelBuilder,
    this.subtitleBuilder,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T item) labelBuilder,
    String? Function(T item)? subtitleBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SearchablePickerSheet<T>(
        title: title,
        items: items,
        labelBuilder: labelBuilder,
        subtitleBuilder: subtitleBuilder,
      ),
    );
  }

  @override
  State<SearchablePickerSheet<T>> createState() => _SearchablePickerSheetState<T>();
}

class _SearchablePickerSheetState<T> extends State<SearchablePickerSheet<T>> {
  final TextEditingController _searchController = TextEditingController();
  late List<T> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    _searchController.addListener(_filter);
  }

  void _filter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.items
          : widget.items
              .where((item) => widget.labelBuilder(item).toLowerCase().contains(query))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20, left: 20, right: 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Type to search...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No results found'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final item = _filtered[index];
                        final subtitle = widget.subtitleBuilder?.call(item);
                        return ListTile(
                          title: Text(widget.labelBuilder(item)),
                          subtitle: subtitle != null ? Text(subtitle) : null,
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}