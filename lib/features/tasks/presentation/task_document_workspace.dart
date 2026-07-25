import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';

class TaskDocumentWorkspace extends ConsumerStatefulWidget {
  const TaskDocumentWorkspace({
    required this.task,
    required this.resource,
    super.key,
  });

  final LocalTask task;
  final LocalEntityRecord resource;

  @override
  ConsumerState<TaskDocumentWorkspace> createState() =>
      _TaskDocumentWorkspaceState();
}

class _TaskDocumentWorkspaceState extends ConsumerState<TaskDocumentWorkspace> {
  final _controller = PdfViewerController();
  Timer? _positionDebounce;
  int _page = 1;
  int _initialPage = 1;
  bool _loading = true;

  Map<String, Object?> get _resourceData =>
      ref.read(entityRecordRepositoryProvider).decode(widget.resource);

  String? get _localPath => _resourceData['local_path'] as String?;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPosition());
  }

  @override
  void dispose() {
    _positionDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPosition() async {
    final positions = await ref
        .read(entityRecordRepositoryProvider)
        .list(entityType: 'document_positions', parentId: widget.resource.id);
    final latest = positions
        .where(
          (record) =>
              ref
                  .read(entityRecordRepositoryProvider)
                  .decode(record)['position_kind'] ==
              'last_position',
        )
        .lastOrNull;
    final page = latest == null
        ? 1
        : (ref
                          .read(entityRecordRepositoryProvider)
                          .decode(latest)['page_number']
                      as num?)
                  ?.toInt() ??
              1;
    if (!mounted) return;
    setState(() {
      _page = page;
      _initialPage = page;
      _loading = false;
    });
  }

  void _saveLastPosition(int? page) {
    if (page == null || page <= 0 || page == _page) return;
    setState(() => _page = page);
    _positionDebounce?.cancel();
    _positionDebounce = Timer(const Duration(milliseconds: 500), () async {
      final entities = ref.read(entityRecordRepositoryProvider);
      final positions = await entities.list(
        entityType: 'document_positions',
        parentId: widget.resource.id,
      );
      final latest = positions
          .where(
            (record) =>
                entities.decode(record)['position_kind'] == 'last_position',
          )
          .lastOrNull;
      final data = <String, Object?>{
        'resource_id': widget.resource.id,
        'task_occurrence_id': widget.task.id,
        'page_number': _page,
        'position_kind': 'last_position',
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      };
      final payload = <String, Object?>{
        'resource_id': widget.resource.id,
        'page_number': _page,
        'position_value': 'page:$_page',
        'name': 'Last position',
        'is_bookmark': false,
        'note': null,
        'recorded_at': data['recorded_at'],
      };
      if (latest == null) {
        await entities.create(
          EntityRecordDraft(
            entityType: 'document_positions',
            parentId: widget.resource.id,
            secondaryParentId: widget.task.id,
            title: 'Last position',
            data: data,
            syncPayload: payload,
          ),
        );
      } else {
        await entities.update(latest, data: data, syncPayload: payload);
      }
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    });
  }

  Future<void> _addBookmark() async {
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bookmark page $_page'),
        content: TextField(
          controller: note,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name or note',
            hintText: 'Why is this page important?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, note.text.trim()),
            child: const Text('Save bookmark'),
          ),
        ],
      ),
    );
    note.dispose();
    if (result == null) return;
    final title = result.isEmpty ? 'Page $_page' : result;
    final now = DateTime.now().toUtc().toIso8601String();
    await ref
        .read(entityRecordRepositoryProvider)
        .create(
          EntityRecordDraft(
            entityType: 'document_positions',
            parentId: widget.resource.id,
            secondaryParentId: widget.task.id,
            title: title,
            data: {
              'resource_id': widget.resource.id,
              'task_occurrence_id': widget.task.id,
              'page_number': _page,
              'position_kind': 'bookmark',
              'name': title,
              'note': result,
              'recorded_at': now,
            },
            syncPayload: {
              'resource_id': widget.resource.id,
              'page_number': _page,
              'position_value': 'page:$_page',
              'name': title,
              'is_bookmark': true,
              'note': result,
              'recorded_at': now,
            },
          ),
        );
  }

  Future<void> _showBookmarks() async {
    final entities = ref.read(entityRecordRepositoryProvider);
    final records = await entities.list(
      entityType: 'document_positions',
      parentId: widget.resource.id,
    );
    final bookmarks = records
        .where(
          (record) => entities.decode(record)['position_kind'] == 'bookmark',
        )
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: bookmarks.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No bookmarks in this document yet')),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: bookmarks.length,
                itemBuilder: (context, index) {
                  final record = bookmarks[index];
                  final data = entities.decode(record);
                  final page = (data['page_number'] as num?)?.toInt() ?? 1;
                  return ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(record.title),
                    subtitle: Text('Page $page'),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_controller.goToPage(pageNumber: page));
                    },
                    trailing: IconButton(
                      tooltip: 'Delete bookmark',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await entities.softDelete(record);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localPath = _localPath;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.resource.title),
        actions: [
          Center(child: Text('Page $_page')),
          IconButton(
            tooltip: 'Add page bookmark',
            onPressed: _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: 'Show bookmarks',
            onPressed: _showBookmarks,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: 'Open with another application',
            onPressed: () =>
                ref.read(taskResourceServiceProvider).open(widget.resource),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: switch ((localPath, _loading)) {
        (_, true) => const Center(child: CircularProgressIndicator()),
        (null, _) => const _UnavailableDocument(),
        (final value, _) when !File(value!).existsSync() =>
          const _UnavailableDocument(),
        (final value, _) => PdfViewer.file(
          value!,
          controller: _controller,
          initialPageNumber: _initialPage,
          params: PdfViewerParams(
            onPageChanged: _saveLastPosition,
            enableKeyboardNavigation: true,
          ),
        ),
      },
    );
  }
}

class _UnavailableDocument extends StatelessWidget {
  const _UnavailableDocument();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'This document is not available on this device. '
          'Download the synchronized resource or attach it again.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
