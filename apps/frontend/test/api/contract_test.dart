import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

void main() {
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
