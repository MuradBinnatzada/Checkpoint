import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';

/// End-of-list row of a paged list. Being built means the end of the list is
/// near, so it asks for the next page (after the current frame, never during
/// build). The store ignores the call when a page is already on its way. A failed
/// page stops that and shows a retry button instead.
class LoadMoreFooter extends StatefulWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.failed,
    required this.onLoadMore,
  });
  final bool loading;
  final bool failed;
  final VoidCallback? onLoadMore;

  @override
  State<LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends State<LoadMoreFooter> {
  @override
  void initState() {
    super.initState();
    _requestNextPage();
  }

  @override
  void didUpdateWidget(LoadMoreFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A page just landed and the footer is still in view: keep going.
    _requestNextPage();
  }

  void _requestNextPage() {
    if (widget.loading || widget.failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.loading && !widget.failed) widget.onLoadMore?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton.icon(
            onPressed: widget.onLoadMore,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.loadMoreFailed),
          ),
        ),
      );
    }
    return const SizedBox(
      height: 56,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
