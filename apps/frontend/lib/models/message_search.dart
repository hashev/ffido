import '../api/api_exceptions.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'message.dart';

class SearchRange {
  final int start, end;
  const SearchRange(this.start, this.end);
}

class MessageSearchResult {
  final Message message;
  final Map<int, List<SearchRange>> matches;
  const MessageSearchResult(this.message, this.matches);
  int get firstField => matches.keys.first;
  static Map<int, List<SearchRange>> validate(
    wire.FindMessageResponse response,
  ) {
    final m = response.message;
    final fields = [
      m.fromName,
      m.fromAddress,
      m.toName,
      m.toAddress,
      m.subject,
      m.body,
    ];
    final result = <int, List<SearchRange>>{};
    int previousField = 0;
    for (final match in response.matches) {
      final field = match.field_1.value;
      final start = match.startUtf16, end = start + match.lengthUtf16;
      if (field < 1 ||
          field > 6 ||
          field < previousField ||
          start < 0 ||
          match.lengthUtf16 <= 0 ||
          end > fields[field - 1].length ||
          (result[field]?.last.end ?? 0) > start ||
          !_boundary(fields[field - 1], start) ||
          !_boundary(fields[field - 1], end)) {
        throw const ServerException(message: 'Некорректные диапазоны поиска');
      }
      (result[field] ??= []).add(SearchRange(start, end));
      previousField = field;
    }
    if (result.isEmpty || m.id.isEmpty) {
      throw const ServerException(message: 'Некорректный результат поиска');
    }
    return result;
  }

  static bool _boundary(String text, int offset) =>
      offset == 0 ||
      offset == text.length ||
      !(text.codeUnitAt(offset) >= 0xdc00 && text.codeUnitAt(offset) <= 0xdfff);
}
