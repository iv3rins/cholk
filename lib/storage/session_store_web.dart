import 'dart:typed_data';

import '../models/chat_models.dart';

/// In-memory storage used by the Flutter Web build. It exists so the UI can be
/// reviewed in a browser without path_provider or dart:io. Data is lost when
/// the page reloads, and attachments only live for the current session.
class SessionStore {
  final Map<String, ChatSession> _sessions = {};
  final Map<String, Uint8List> _files = {};
  List<SessionSummary> _index = [];
  Map<String, dynamic> _drafts = {};

  Future<List<SessionSummary>> loadIndex() async => List.of(_index);

  Future<List<SessionSummary>> scanSessions() async =>
      _sessions.values.map((session) => session.toSummary()).toList();

  Future<ChatSession?> loadSession(String id) async => _sessions[id];

  Future<void> saveSession(ChatSession session) async {
    _sessions[session.id] = session;
  }

  Future<void> saveIndex(List<SessionSummary> sessions) async {
    _index = List.of(sessions);
  }

  Future<void> deleteSession(String id) async {
    _sessions.remove(id);
  }

  Future<Map<String, dynamic>> loadDrafts() async => _drafts;

  Future<void> saveDrafts(Map<String, dynamic> data) async {
    _drafts = Map.of(data);
  }

  Future<FileAttachment> importAttachment({
    required String sourcePath,
    required String name,
    required int size,
    required bool isImage,
    required String mimeType,
  }) {
    throw UnsupportedError('Use importAttachmentBytes on web');
  }

  Future<FileAttachment> importAttachmentBytes({
    required Uint8List bytes,
    required String name,
    required int size,
    required bool isImage,
    required String mimeType,
  }) async {
    final id = newId();
    final attachment = FileAttachment(
      id: id,
      name: name,
      size: size,
      isImage: isImage,
      mimeType: mimeType,
      localPath: 'memory://$id',
      bytes: Uint8List.fromList(bytes),
    );
    _files[id] = attachment.bytes!;
    return attachment;
  }

  Future<void> deleteAttachmentFile(FileAttachment attachment) async {
    _files.remove(attachment.id);
  }

  Future<Uint8List> readAttachment(FileAttachment attachment) async {
    final bytes = attachment.bytes ?? _files[attachment.id];
    if (bytes == null) {
      throw StateError('Attachment is unavailable: ${attachment.name}');
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> clearAll() async {
    _sessions.clear();
    _index.clear();
    _files.clear();
    _drafts.clear();
  }
}
