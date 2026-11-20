import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

void main() {
  test('Telegram extension preserves absence and typed wire values', () {
    expect(ServerCapabilities.fromBuffer([]).supportsTelegram, isFalse);
    final request = TelegramLoginRequest(
      initData: 'user=%7B%22id%22%3A123%7D&auth_date=100',
      address: '2:5015/1.2',
    );
    final restored = TelegramLoginRequest.fromBuffer(request.writeToBuffer());
    expect(restored.initData, request.initData);
    expect(restored.address, request.address);
    final binding = BindTelegramRequest(
      initData: request.initData,
      password: 'fixture',
      replaceExisting: true,
    );
    expect(
      BindTelegramRequest.fromBuffer(binding.writeToBuffer()).replaceExisting,
      isTrue,
    );
    final profiles = TelegramProfiles(
      profiles: [Profile(address: request.address)],
    );
    expect(
      TelegramProfiles.fromBuffer(profiles.writeToBuffer())
          .profiles
          .single
          .address,
      request.address,
    );
    expect(TelegramBinding.fromBuffer([]).bound, isFalse);
    expect(
      LoginRequest(name: 'A', address: 'B', password: 'C').writeToBuffer(),
      [10, 1, 65, 18, 1, 66, 26, 1, 67],
    );
  });
  test(
    'offline read fields preserve wire tags, defaults and arbitrary bytes',
    () {
      final session = SessionInfo(supportsOfflineSync: true);
      expect(session.writeToBuffer(), [0x28, 1]);
      expect(
        SessionInfo.fromBuffer(session.writeToBuffer()).supportsOfflineSync,
        isTrue,
      );
      expect(SessionInfo().supportsOfflineSync, isFalse);
      final conference = Conference(generation: 'g');
      expect(conference.writeToBuffer(), [0x8a, 1, 1, 0x67]);
      expect(Conference.fromBuffer(conference.writeToBuffer()).generation, 'g');
      expect(Conference().generation, isEmpty);
      final list = ListMessagesResponse(generation: 'g');
      expect(list.writeToBuffer(), [0x2a, 1, 0x67]);
      expect(
        ListMessagesResponse.fromBuffer(list.writeToBuffer()).generation,
        'g',
      );
      expect(ListMessagesResponse().generation, isEmpty);
      final request = ListMessagesRequest(afterMessageId: 'g');
      expect(request.writeToBuffer(), [0x3a, 1, 0x67]);
      expect(
        ListMessagesRequest.fromBuffer(request.writeToBuffer()).afterMessageId,
        'g',
      );
      expect(ListMessagesRequest().afterMessageId, isEmpty);
      final read = ReadArchiveMessageRequest(includeSubfields: true);
      expect(read.writeToBuffer(), [0x28, 1]);
      expect(
        ReadArchiveMessageRequest.fromBuffer(read.writeToBuffer())
            .includeSubfields,
        isTrue,
      );
      expect(ReadArchiveMessageRequest().includeSubfields, isFalse);
      final response = ReadArchiveMessageResponse(
        attributes2: 0x80000001,
        subfields: [
          MessageTechnicalSubfield(
            lowId: 65000,
            highId: 65535,
            value: [65, 0, 255],
          ),
        ],
      );
      final bytes = response.writeToBuffer();
      expect(bytes.first, 0x32);
      expect(bytes.sublist(bytes.length - 6), [
        0x38,
        0x81,
        0x80,
        0x80,
        0x80,
        8,
      ]);
      final restored = ReadArchiveMessageResponse.fromBuffer(bytes);
      expect(restored.attributes2, 0x80000001);
      expect(restored.subfields.single.value, [65, 0, 255]);
      expect(restored.subfields.single.highId, 65535);
      expect(ReadArchiveMessageResponse().subfields, isEmpty);
      expect(ReadArchiveMessageResponse().attributes2, 0);
      final sorted = ListMessagesRequest(
        sort: MessageSort.MESSAGE_SORT_NUMBER_ASCENDING,
      );
      expect(sorted.writeToBuffer(), [0x20, 3]);
      expect(
        ListMessagesRequest.fromBuffer(sorted.writeToBuffer()).sort,
        MessageSort.MESSAGE_SORT_NUMBER_ASCENDING,
      );
    },
  );

  test('footer extension distinguishes legacy absence and round-trips with session capability', () {
    expect(
      CreateMessageRequest.fromBuffer(
        CreateMessageRequest(body: 'legacy').writeToBuffer(),
      ).hasFooter(),
      isFalse,
    );
    final request = CreateMessageRequest(
      footer: MessageFooter(tagline: 'FFIDO 1.0.5', origin: 'Мой сайт'),
    );
    expect(
      CreateMessageRequest.fromBuffer(request.writeToBuffer()).footer.origin,
      'Мой сайт',
    );
    expect(SessionInfo.fromBuffer([]).supportsMessageFooter, isFalse);
    expect(
      SessionInfo.fromBuffer(
        SessionInfo(supportsMessageFooter: true).writeToBuffer(),
      ).supportsMessageFooter,
      isTrue,
    );
  });
  test('контракт сохраняет Unicode и UTC Timestamp', () {
    final original = Message(
      id: 'generation:42',
      subject: 'Проверка ёжика',
      body: 'Привет\nмир 🌍',
      ftnMessageId: '2:5020/1 abcdef',
      date: Timestamp(seconds: Int64(-1), nanos: 123456789),
    );
    final decoded = Message.fromBuffer(original.writeToBuffer());
    expect(decoded.subject, original.subject);
    expect(decoded.body, original.body);
    expect(decoded.ftnMessageId, original.ftnMessageId);
    expect(decoded.date.seconds, Int64(-1));
    expect(decoded.date.nanos, 123456789);
    expect(Message().hasDate(), isFalse);
  });

  test('Empty не требует тела ответа', () {
    expect(Empty().writeToBuffer(), isEmpty);
    expect(Empty.fromBuffer([]), isA<Empty>());
  });

  test('ошибки полей передаются типизированно без потери Unicode', () {
    final original = ErrorDetails(
      violations: [
        FieldViolation(field_1: 'body', message: 'Текст обязателен'),
        FieldViolation(
          field_1: 'to_address',
          message: 'Некорректный FTN-адрес',
        ),
      ],
    );
    final decoded = ErrorDetails.fromBuffer(original.writeToBuffer());
    expect(decoded.violations.map((v) => v.field_1), ['body', 'to_address']);
    expect(decoded.violations.first.message, 'Текст обязателен');
    expect(() => ErrorDetails.fromBuffer([0x0a, 0xff]), throwsException);
  });

  test('успех означает локальное сохранение и сохраняет ключ операции', () {
    final request = CreateMessageRequest(operationId: 'stable-operation');
    expect(
      CreateMessageRequest.fromBuffer(request.writeToBuffer()).operationId,
      'stable-operation',
    );
    final response = CreateMessageResponse(
      status: SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
    );
    expect(
      CreateMessageResponse.fromBuffer(response.writeToBuffer()).status,
      SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
    );
    expect(CreateMessageResponse().status, SaveStatus.SAVE_STATUS_UNSPECIFIED);
  });

  test('неизвестная enum не превращается в известную сортировку', () {
    // Поле sort=4, varint=12345. Unknown fields сохраняются при повторной записи.
    final bytes = [0x20, 0xb9, 0x60];
    final decoded = ListMessagesRequest.fromBuffer(bytes);
    expect(decoded.sort, MessageSort.MESSAGE_SORT_UNSPECIFIED);
    expect(decoded.writeToBuffer(), bytes);
  });
}
