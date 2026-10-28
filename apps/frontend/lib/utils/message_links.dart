import 'uue_text.dart';

/// A range in the original UTF-16 text. Parsing never rewrites the body.
class MessageLink {
  final int start, end;
  final Uri uri;
  const MessageLink(this.start, this.end, this.uri);
}

bool webUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.hasAuthority &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    !RegExp(r'[\x00-\x20\x7f\\]').hasMatch(uri.toString()) &&
    !RegExp(
      r'%(?:0[0-9a-f]|1[0-9a-f]|7f|5c)',
      caseSensitive: false,
    ).hasMatch(uri.toString());

List<MessageLink> messageLinks(String text) {
  final result = <MessageLink>[];
  final pattern = RegExp(
    r'''(?:https?://|www\.)[^\s\x00-\x1f\x7f<>"«»“”]+''',
    caseSensitive: false,
  );
  var offset = 0, inUue = false;
  for (final line in text.split('\n')) {
    if (uueBeginLine.hasMatch(line)) inUue = true;
    // Suppress the complete encoded block, including malformed data lines.
    if (!inUue && !uueDataLine(line)) {
      for (final match in pattern.allMatches(line)) {
        if (match.start > 0 &&
            RegExp(r'[\w:/@.\\-]').hasMatch(line[match.start - 1])) {
          continue;
        }
        var value = match[0]!;
        final quoted = match.start > 0 && line[match.start - 1] == "'";
        while (value.isNotEmpty) {
          final last = value[value.length - 1];
          final open = {')': '(', ']': '[', '}': '{'}[last];
          if ((quoted && last == "'") ||
              '.!,;:'.contains(last) ||
              (open != null &&
                  last.allMatches(value).length >
                      open.allMatches(value).length)) {
            value = value.substring(0, value.length - 1);
          } else {
            break;
          }
        }
        // A control embedded in a URL must not turn its prefix into a link.
        if (match.end < line.length &&
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(line[match.end])) {
          continue;
        }
        if (value.contains(r'\')) continue;
        final uri = Uri.tryParse(
          value.toLowerCase().startsWith('www.') ? 'https://$value' : value,
        );
        if (uri != null && webUri(uri)) {
          result.add(
            MessageLink(
              offset + match.start,
              offset + match.start + value.length,
              uri,
            ),
          );
        }
      }
    }
    if (inUue && line.trimRight() == 'end') inUue = false;
    offset += line.length + 1;
  }
  return result;
}
