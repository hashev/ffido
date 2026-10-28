import '../api/message_footer.dart';

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';

import '../api/api_transport.dart';
import '../api/api_exceptions.dart';
import '../api/uue_capabilities.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as wire;
import '../files/uue_file_types.dart';
import '../models/uue.dart';

class UueDraft {
  final String conference, operation, subject, body, toName, toAddress, reply;
  final SelectedUueFile file;
  final bool useFooter;
  UueDraft({
    required this.conference,
    required this.operation,
    required this.subject,
    required this.body,
    required this.toName,
    required this.toAddress,
    this.reply = '',
    this.useFooter = true,
    required this.file,
  });
}

class UueRepository {
  final ApiTransport api;
  late final _footers = MessageFooterSnapshots(api);
  UueRepository(this.api);
  int get epoch => api.epoch;
  Stream<int> get sessionChanges => api.sessionChanges;
  Future<UueCapabilities?>? _capabilities;
  int _capsEpoch = -1;
  Future<UueCapabilities?> capabilities() {
    if (_capsEpoch != epoch) {
      _capsEpoch = epoch;
      _capabilities = null;
    }
    return _capabilities ??= loadUueCapabilities(api).catchError((Object e) {
      _capabilities = null;
      throw e;
    });
  }

  void _check(int before, RpcCancellation? cancellation) {
    if (before != epoch || cancellation?.isCancelled == true) {
      throw const CancelledException();
    }
  }

  Future<List<UuePart>> messageParts(
    String conference,
    String message, {
    RpcCancellation? cancellation,
  }) async {
    final split = message.lastIndexOf('#');
    if (split <= 0) return [];
    final number = int.tryParse(message.substring(split + 1));
    if (number == null || number <= 0) return [];
    final before = epoch;
    final response = await api.searchUueParts(
      wire.SearchUuePartsRequest(
        conferenceId: conference,
        generation: message.substring(0, split),
        afterNumber: number - 1,
        limit: 1,
      ),
      cancellation: cancellation,
    );
    _check(before, cancellation);
    return response.parts
        .where((p) => p.source.message.messageId == message)
        .map(UuePart.fromWire)
        .toList();
  }

  Future<List<UuePart>> findParts(
    UuePart anchor, {
    RpcCancellation? cancellation,
    void Function(int)? progress,
  }) async {
    final before = epoch;
    var generation = '', after = 0, scanned = 0;
    final found = <String, UuePart>{};
    do {
      final response = await api.searchUueParts(
        wire.SearchUuePartsRequest(
          conferenceId: anchor.source.conference,
          generation: generation,
          afterNumber: after,
          limit: 50,
        ),
        cancellation: cancellation,
      );
      _check(before, cancellation);
      if (generation.isNotEmpty && response.generation != generation) {
        throw const ServerException(message: 'Поколение базы изменилось');
      }
      generation = response.generation;
      for (final raw in response.parts) {
        final part = UuePart.fromWire(raw);
        if (part.from != anchor.from ||
            part.to != anchor.to ||
            part.direction != anchor.direction) {
          continue;
        }
        if (anchor.verifiedFormat && part.transfer != anchor.transfer) continue;
        if (!anchor.verifiedFormat && part.verifiedFormat) continue;
        if (!anchor.verifiedFormat &&
            anchor.total > 1 &&
            (part.total != anchor.total ||
                part.subject.replaceFirst(RegExp(r'\s*\[\d+/\d+\]$'), '') !=
                    anchor.subject.replaceFirst(
                      RegExp(r'\s*\[\d+/\d+\]$'),
                      '',
                    ))) {
          continue;
        }
        found[part.source.key] = part;
        if (found.length > 1024) {
          throw const ApiException(
            message: 'Слишком много кандидатов UUE',
            statusCode: 8,
          );
        }
      }
      scanned += 50;
      progress?.call(scanned);
      if (!response.hasMore) break;
      if (response.nextNumber <= after || scanned > 100000) {
        throw const ServerException(message: 'Поиск частей не продвигается');
      }
      after = response.nextNumber;
    } while (true);
    return found.values.toList()..sort((a, b) => a.part.compareTo(b.part));
  }

  Future<UueAttachment> assemble(
    List<UuePart> parts, {
    bool confirmed = false,
    RpcCancellation? cancellation,
  }) async {
    final before = epoch;
    final result = await api.assembleUue(
      wire.AssembleUueRequest(
        sources: parts.map((p) => p.source.toWire()),
        explicitOrder: confirmed,
      ),
      cancellation: cancellation,
    );
    _check(before, cancellation);
    return UueAttachment.fromWire(result);
  }

  Future<Uint8List> download(
    UueAttachment attachment, {
    RpcCancellation? cancellation,
  }) async {
    if (attachment.state != UueFileState.ready) {
      throw const ValidationException(message: 'Файл ещё не собран');
    }
    final before = epoch;
    final limits = await capabilities();
    _check(before, cancellation);
    if (limits == null ||
        attachment.size < 0 ||
        attachment.size > limits.fileBytes) {
      throw uueFileLimit();
    }
    final bytes = BytesBuilder(copy: false);
    do {
      final response = await api.getUueChunk(
        wire.GetUueChunkRequest(
          attachmentId: attachment.id,
          offset: Int64(bytes.length),
          maxBytes: limits.chunkBytes,
        ),
        cancellation: cancellation,
      );
      _check(before, cancellation);
      if (response.offset.toInt() != bytes.length ||
          response.totalSize.toInt() != attachment.size ||
          response.data.length > limits.chunkBytes ||
          bytes.length + response.data.length > attachment.size ||
          (response.data.isEmpty && !response.eof)) {
        throw const ServerException(message: 'Некорректная порция UUE');
      }
      bytes.add(response.data);
      if (response.eof) {
        if (bytes.length != attachment.size) {
          throw const ServerException(message: 'Неполный файл UUE');
        }
        break;
      }
    } while (true);
    final result = bytes.takeBytes();
    if (sha256.convert(result).toString() != attachment.sha256) {
      throw const ServerException(message: 'Не совпадает SHA-256 файла');
    }
    return result;
  }

  Future<UueTransfer> send(
    UueDraft draft, {
    RpcCancellation? cancellation,
    void Function(int, int)? progress,
  }) async {
    final before = epoch;
    final footer = await _footers.capture(
      draft.operation,
      enabled: draft.useFooter,
    );
    _check(before, cancellation);
    final limits = await capabilities();
    _check(before, cancellation);
    if (limits == null) {
      throw const ApiException(
        message: 'Сервер не поддерживает UUE',
        statusCode: 12,
      );
    }
    if (draft.file.bytes.length > limits.fileBytes) throw uueFileLimit();
    var upload = true;
    final hash = sha256.convert(draft.file.bytes).toString();
    try {
      final status = await api.getUueSendStatus(
        wire.UueOperationReference(operationId: draft.operation),
        cancellation: cancellation,
      );
      _check(before, cancellation);
      if (status.filename != draft.file.name ||
          status.fileSize.toInt() != draft.file.bytes.length ||
          status.sha256 != hash) {
        throw const ApiException(
          message: 'Этот ключ передачи уже использован с другим файлом',
          statusCode: 6,
        );
      }
      upload = status.state == 'uploading';
    } on ApiException catch (error) {
      if (error.statusCode != 5) rethrow;
    }
    _check(before, cancellation);
    if (upload) {
      var offset = 0;
      do {
        final end = min(offset + limits.chunkBytes, draft.file.bytes.length);
        final result = await api.uploadUueChunk(
          wire.UploadUueChunkRequest(
            operationId: draft.operation,
            filename: draft.file.name,
            fileSize: Int64(draft.file.bytes.length),
            sha256: hash,
            offset: Int64(offset),
            data: draft.file.bytes.sublist(offset, end),
          ),
          cancellation: cancellation,
        );
        _check(before, cancellation);
        if (result.receivedBytes.toInt() < end ||
            result.receivedBytes.toInt() > draft.file.bytes.length) {
          throw const ServerException(
            message: 'Некорректное подтверждение загрузки',
          );
        }
        // A repeat can acknowledge previously persisted later chunks too.
        offset = result.receivedBytes.toInt();
        progress?.call(offset, draft.file.bytes.length);
        if (offset == draft.file.bytes.length) break;
      } while (true);
    }
    final response = await api.commitUue(
      wire.CommitUueRequest(
        message: wire.CreateMessageRequest(
          conferenceId: draft.conference,
          operationId: draft.operation,
          footer: footer,
          toName: draft.toName,
          toAddress: draft.toAddress,
          subject: draft.subject,
          body: draft.body,
          inReplyTo: draft.reply,
        ),
      ),
      cancellation: cancellation,
    );
    _check(before, cancellation);
    return UueTransfer.fromWire(response);
  }
}
