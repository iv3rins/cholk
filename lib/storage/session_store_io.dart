import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chat_models.dart';

/// File-based storage: one JSON file per session plus an index file, and the
/// original attachment files under `files/`.
///
/// A file store keeps the implementation dependency-free and is plenty fast
/// for a chat client; large histories are loaded only when opened.
class SessionStore {
  Directory? _root;
  Future<void> _writeQueue = Future.value();

  Future<Directory> _ensureRoot() async {
    final existing = _root;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'deepseek_chat'));
    await root.create(recursive: true);
    await Directory(p.join(root.path, 'sessions')).create(recursive: true);
    await Directory(p.join(root.path, 'files')).create(recursive: true);
    _root = root;
    return root;
  }

  Future<File> _sessionFile(String id) async {
    if (!isSafeStorageId(id)) {
      throw ArgumentError.value(id, 'id', 'Unsafe session id');
    }
    final root = await _ensureRoot();
    return File(p.join(root.path, 'sessions', '$id.json'));
  }

  Future<File> _indexFile() async {
    final root = await _ensureRoot();
    return File(p.join(root.path, 'sessions_index.json'));
  }

  Future<File> _draftsFile() async {
    final root = await _ensureRoot();
    return File(p.join(root.path, 'drafts.json'));
  }

  Future<Map<String, dynamic>> loadDrafts() async {
    final file = await _draftsFile();
    if (!await file.exists()) return {};
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {
      // Ignore corrupt draft data.
    }
    return {};
  }

  Future<void> saveDrafts(Map<String, dynamic> data) =>
      _saveJson(_draftsFile, () => data);

  Directory? get filesDirectory =>
      _root == null ? null : Directory(p.join(_root!.path, 'files'));

  Future<List<SessionSummary>> loadIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) {
      return [];
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      final summaries = <SessionSummary>[];
      for (final item in raw) {
        final summary = SessionSummary.fromJson(item);
        if (summary != null) summaries.add(summary);
      }
      return summaries;
    } catch (_) {
      return [];
    }
  }

  Future<ChatSession?> loadSession(String id) async {
    final file = await _sessionFile(id);
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      return ChatSession.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  /// Rebuilds the index by reading the per-session files. Used when the index
  /// is missing or was written by an interrupted older run.
  Future<List<SessionSummary>> scanSessions() async {
    final root = await _ensureRoot();
    final dir = Directory(p.join(root.path, 'sessions'));
    final result = <SessionSummary>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is! Map) continue;
        final session = ChatSession.fromJson(Map<String, dynamic>.from(raw));
        if (session != null) result.add(session.toSummary());
      } catch (_) {
        // Ignore unreadable session files.
      }
    }
    return result;
  }

  Future<void> saveSession(ChatSession session) =>
      _saveJson(() => _sessionFile(session.id), session.toJson);

  Future<void> saveIndex(List<SessionSummary> sessions) => _saveJson(
    _indexFile,
    () => sessions.map((item) => item.toJson()).toList(),
  );

  Future<void> _enqueueMutation(Future<void> Function() mutate) {
    final operation = _writeQueue.then((_) => mutate());
    // The caller sees the outcome of this operation. The queue stays usable
    // for the next operation regardless of that outcome.
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _saveJson(
    Future<File> Function() location,
    Object? Function() data,
  ) =>
      _enqueueMutation(() async {
        final file = await location();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(jsonEncode(data()), flush: true);
        await temp.rename(file.path);
      }).catchError((Object error, StackTrace stackTrace) {
        developer.log(
          'Could not save chat data',
          name: 'deepseek_chat.storage',
          error: error,
          stackTrace: stackTrace,
        );
      });

  Future<void> deleteSession(String id) => _enqueueMutation(() async {
    final file = await _sessionFile(id);
    if (await file.exists()) {
      await file.delete();
    }
  });

  Future<FileAttachment> importAttachment({
    required String sourcePath,
    required String name,
    required int size,
    required bool isImage,
    required String mimeType,
  }) async {
    final root = await _ensureRoot();
    final id = newId();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File(p.join(root.path, 'files', '${id}_$safeName'));
    final source = File(sourcePath);
    await source.copy(target.path);
    return FileAttachment(
      id: id,
      name: name,
      size: size,
      isImage: isImage,
      mimeType: mimeType,
      localPath: target.path,
    );
  }

  Future<FileAttachment> importAttachmentBytes({
    required Uint8List bytes,
    required String name,
    required int size,
    required bool isImage,
    required String mimeType,
  }) async {
    final root = await _ensureRoot();
    final id = newId();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File(p.join(root.path, 'files', '${id}_$safeName'));
    await target.writeAsBytes(bytes, flush: true);
    return FileAttachment(
      id: id,
      name: name,
      size: size,
      isImage: isImage,
      mimeType: mimeType,
      localPath: target.path,
    );
  }

  Future<void> deleteAttachmentFile(FileAttachment attachment) async {
    final path = attachment.localPath;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Uint8List> readAttachment(FileAttachment attachment) async {
    final bytes = attachment.bytes;
    if (bytes != null) return bytes;
    final path = attachment.localPath;
    if (path == null || path.isEmpty) {
      throw StateError('Attachment is unavailable: ${attachment.name}');
    }
    return File(path).readAsBytes();
  }

  Future<void> clearAll() => _enqueueMutation(() async {
    final root = await _ensureRoot();
    for (final dirName in ['sessions', 'files']) {
      final dir = Directory(p.join(root.path, dirName));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
    }
    final index = await _indexFile();
    if (await index.exists()) {
      await index.delete();
    }
    final drafts = await _draftsFile();
    if (await drafts.exists()) {
      await drafts.delete();
    }
  });
}
