import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

void main() {
  test('successful message actions report exact touched IDs, failed actions do not', () async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    final changed = <String>{};
    final repo = MessageRepository(api, onChanged: changed.add);
    await repo.getMessage(conferenceId: 'read', messageId: 'g#1');
    await repo.markAsRead(conferenceId: 'mark', messageId: 'g#1');
    await repo.markAsUnread(conferenceId: 'unread', messageId: 'g#1');
    await repo.markConferenceRead(conferenceId: 'bulk', operationId: 'bulk');
    await repo.sendMessage(
      conferenceId: 'sent',
      toName: 'All',
      toAddress: '',
      subject: 's',
      body: 'b',
    );
    await repo.sendCrosspost(
      conferenceId: 'primary',
      additionalConferenceIds: ['copy'],
      operationId: 'group',
      toName: 'All',
      toAddress: '',
      subject: 's',
      body: 'b',
    );
    expect(changed, {
      'read',
      'mark',
      'unread',
      'bulk',
      'sent',
      'primary',
      'copy',
    });
    api.unread = (_) async => throw const NetworkException();
    await expectLater(
      repo.markAsUnread(conferenceId: 'failed', messageId: 'g#1'),
      throwsA(isA<NetworkException>()),
    );
    expect(changed.contains('failed'), isFalse);
    api.bulkRead = (_) async {
      api.switchSession();
      return wire.MarkConferenceReadResponse();
    };
    await expectLater(
      repo.markConferenceRead(conferenceId: 'obsolete', operationId: 'old'),
      throwsA(isA<CancelledException>()),
    );
    expect(changed.contains('obsolete'), isFalse);
  });
}
