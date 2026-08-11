import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
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

class _TaskDocumentWorkspaceState extends ConsumerState<TaskDocumentWorkspace>
    with WidgetsBindingObserver {
  final _controller = PdfViewerController();
  Timer? _positionDebounce;
  Future<void> _positionWriteChain = Future<void>.value();
  _LocalDocumentPosition? _localPosition;
  bool _positionDirty = false;
  bool _positionBoundaryFlushInFlight = false;
  String? _lastPositionLabel;
  int _page = 1;
  int _initialPage = 1;
  bool _loading = true;

  Map<String, Object?> get _resourceData =>
      ref.read(entityRecordRepositoryProvider).decode(widget.resource);

  String? get _localPath => _resourceData['local_path'] as String?;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPosition());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastPositionLabel = context.l10n.text('document_last_position');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionDebounce?.cancel();
    // Leaving a document is an explicit sync boundary. The position itself is
    // already durable locally, so page turns never need to wait for the
    // network or create an outbox command.
    unawaited(_synchronizeLastPositionAtBoundary());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    unawaited(_synchronizeLastPositionAtBoundary());
  }

  String get _positionStorageKey =>
      'taskmaster.document_position.${widget.resource.id}';

  Future<void> _loadPosition() async {
    final entities = ref.read(entityRecordRepositoryProvider);
    final results = await Future.wait<Object?>([
      entities.list(
        entityType: 'document_positions',
        parentId: widget.resource.id,
      ),
      _readLocalPosition(),
    ]);
    final positions = results[0]! as List<LocalEntityRecord>;
    final local = results[1] as _LocalDocumentPosition?;
    final latest = _lastSyncedPosition(positions, entities);
    final remote = latest == null
        ? null
        : _LocalDocumentPosition(
            page:
                (entities.decode(latest)['page_number'] as num?)?.toInt() ?? 1,
            recordedAt:
                _recordedAt(entities.decode(latest)) ??
                latest.updatedAt.toUtc(),
            pendingSync: false,
          );
    // The device checkpoint wins while it is newer or still awaiting the next
    // deliberate sync boundary. It avoids a remote pull moving a reader back
    // to an earlier page after a local page turn.
    final preferred =
        local != null &&
            (remote == null ||
                local.pendingSync ||
                local.recordedAt.isAfter(remote.recordedAt))
        ? local
        : remote;
    final page = preferred?.page ?? 1;
    if (!mounted) return;
    setState(() {
      _page = page;
      _initialPage = page;
      _loading = false;
    });
    _localPosition = local;
    _positionDirty = local?.pendingSync == true;
  }

  void _saveLastPosition(int? page) {
    if (page == null || page <= 0 || page == _page) return;
    setState(() => _page = page);
    _localPosition = _LocalDocumentPosition(
      page: page,
      recordedAt: DateTime.now().toUtc(),
      pendingSync: true,
    );
    _positionDirty = true;
    _positionDebounce?.cancel();
    _positionDebounce = Timer(
      const Duration(milliseconds: 850),
      () => unawaited(_persistLastPositionLocally()),
    );
  }

  Future<void> _persistLastPositionLocally() async {
    _positionDebounce?.cancel();
    final position = _localPosition;
    if (position == null) return;
    await _queuePositionWrite(() => _writeLocalPosition(position));
  }

  Future<void> _synchronizeLastPositionAtBoundary() async {
    if (_positionBoundaryFlushInFlight) return;
    _positionBoundaryFlushInFlight = true;
    // Capture providers before the asynchronous work so an explicit route exit
    // can finish its already-started local/remote boundary flush safely.
    final entities = ref.read(entityRecordRepositoryProvider);
    final synchronizer = ref.read(syncServiceProvider);
    try {
      await _persistLastPositionLocally();
      final pending = _localPosition;
      if (pending == null || (!_positionDirty && !pending.pendingSync)) {
        return;
      }
      var queuedRemoteCommand = false;
      await _queuePositionWrite(() async {
        final current = _localPosition;
        if (current == null || !current.sameObservation(pending)) return;
        final positions = await entities.list(
          entityType: 'document_positions',
          parentId: widget.resource.id,
        );
        final latest = _lastSyncedPosition(positions, entities);
        final lastPositionLabel =
            _lastPositionLabel ??
            'Last position'; // Context may already be disposed on route exit.
        final data = <String, Object?>{
          'resource_id': widget.resource.id,
          'task_occurrence_id': widget.task.id,
          'page_number': pending.page,
          'position_kind': 'last_position',
          'recorded_at': pending.recordedAt.toIso8601String(),
        };
        final payload = <String, Object?>{
          'resource_id': widget.resource.id,
          'page_number': pending.page,
          'position_value': 'page:${pending.page}',
          'name': lastPositionLabel,
          'is_bookmark': false,
          'note': null,
          'recorded_at': data['recorded_at'],
        };
        final latestPage = latest == null
            ? null
            : (entities.decode(latest)['page_number'] as num?)?.toInt();
        if (latest == null) {
          await entities.create(
            EntityRecordDraft(
              entityType: 'document_positions',
              parentId: widget.resource.id,
              secondaryParentId: widget.task.id,
              title: lastPositionLabel,
              data: data,
              syncPayload: payload,
            ),
          );
          queuedRemoteCommand = true;
        } else if (latestPage != pending.page) {
          await entities.update(
            latest,
            title: lastPositionLabel,
            data: data,
            syncPayload: payload,
          );
          queuedRemoteCommand = true;
        }
        // Do not erase a newer page turn which arrived while this boundary was
        // waiting on local storage or the database.
        if (_localPosition?.sameObservation(pending) == true) {
          _localPosition = pending.markSynchronized();
          _positionDirty = false;
          await _writeLocalPosition(_localPosition!);
        }
      });
      if (queuedRemoteCommand) {
        unawaited(synchronizer.drainOutbox());
      }
    } finally {
      _positionBoundaryFlushInFlight = false;
    }
  }

  LocalEntityRecord? _lastSyncedPosition(
    List<LocalEntityRecord> positions,
    EntityRecordRepository entities,
  ) {
    return positions
        .where(
          (record) =>
              entities.decode(record)['position_kind'] == 'last_position',
        )
        .lastOrNull;
  }

  DateTime? _recordedAt(Map<String, Object?> data) {
    final raw = data['recorded_at']?.toString();
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<_LocalDocumentPosition?> _readLocalPosition() async {
    final preferences = await SharedPreferences.getInstance();
    return _LocalDocumentPosition.fromStorage(
      preferences.getString(_positionStorageKey),
    );
  }

  Future<void> _writeLocalPosition(_LocalDocumentPosition position) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_positionStorageKey, position.toStorage());
  }

  Future<void> _queuePositionWrite(Future<void> Function() action) {
    final queued = _positionWriteChain.then<void>(
      (_) => action(),
      onError: (Object _, StackTrace _) => action(),
    );
    _positionWriteChain = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return queued;
  }

  Future<void> _addBookmark() async {
    final note = TextEditingController();
    final pageTitle = context.l10n.format('document_page', {'page': _page});
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.format('document_bookmark_page', {'page': _page}),
        ),
        content: TextField(
          controller: note,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.text('document_bookmark_name'),
            hintText: context.l10n.text('document_bookmark_reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, note.text.trim()),
            child: Text(context.l10n.text('document_save_bookmark')),
          ),
        ],
      ),
    );
    note.dispose();
    if (result == null) return;
    final title = result.isEmpty ? pageTitle : result;
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
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(context.l10n.text('document_no_bookmarks')),
                ),
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
                    subtitle: Text(
                      context.l10n.format('document_page', {'page': page}),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_controller.goToPage(pageNumber: page));
                    },
                    trailing: IconButton(
                      tooltip: context.l10n.text('browser_delete_bookmark'),
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
          Center(
            child: Text(context.l10n.format('document_page', {'page': _page})),
          ),
          IconButton(
            tooltip: context.l10n.text('document_add_bookmark'),
            onPressed: _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: context.l10n.text('document_show_bookmarks'),
            onPressed: _showBookmarks,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: context.l10n.text('document_open_other_app'),
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

class _LocalDocumentPosition {
  const _LocalDocumentPosition({
    required this.page,
    required this.recordedAt,
    required this.pendingSync,
  });

  final int page;
  final DateTime recordedAt;
  final bool pendingSync;

  _LocalDocumentPosition markSynchronized() => _LocalDocumentPosition(
    page: page,
    recordedAt: recordedAt,
    pendingSync: false,
  );

  bool sameObservation(_LocalDocumentPosition other) =>
      page == other.page && recordedAt == other.recordedAt;

  String toStorage() => jsonEncode({
    'page': page,
    'recorded_at': recordedAt.toIso8601String(),
    'pending_sync': pendingSync,
  });

  static _LocalDocumentPosition? fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final page = decoded['page'] is num
          ? (decoded['page'] as num).toInt()
          : int.tryParse(decoded['page']?.toString() ?? '');
      final recordedAt = DateTime.tryParse(
        decoded['recorded_at']?.toString() ?? '',
      )?.toUtc();
      if (page == null || page <= 0 || recordedAt == null) return null;
      return _LocalDocumentPosition(
        page: page,
        recordedAt: recordedAt,
        pendingSync: decoded['pending_sync'] == true,
      );
    } catch (_) {
      // Local resume state is optional. A malformed legacy preference simply
      // falls back to the canonical position instead of interrupting reading.
      return null;
    }
  }
}

class _UnavailableDocument extends StatelessWidget {
  const _UnavailableDocument();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          context.l10n.text('document_unavailable'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
