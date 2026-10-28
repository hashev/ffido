import 'package:flutter_test/flutter_test.dart';
import 'package:fido/utils/message_links.dart';

void main() {
  test('ranges preserve Unicode, query, fragment, whitespace and punctuation', () {
    const body =
        '  AB> (https://example.org/путь_(x)?q=a%20b#часть).\nwww.example.org/a, https://other.org!';
    final links = messageLinks(body);
    expect(links.length, 3);
    expect(
      body.substring(links[0].start, links[0].end),
      'https://example.org/путь_(x)?q=a%20b#часть',
    );
    expect(links[1].uri.toString(), 'https://www.example.org/a');
    expect(links[2].uri.host, 'other.org');
    expect(
      messageLinks("https://e.org/O'Brien?q='a'#f").single.uri.query,
      "q='a'",
    );
    const quoted = "'https://e.org/O'Brien'";
    final inside = messageLinks(quoted).single;
    expect(quoted.substring(inside.start, inside.end), "https://e.org/O'Brien");

    expect(messageLinks('https://e.org/a(b(c))]').single.uri.path, '/a(b(c))');
  });
  test('reject userinfo, dangerous schemes, embedded controls and UUE', () {
    for (final value in [
      'https://user:pass@e.org',
      'javascript:https://e.org',
      'file:///tmp/a',
      'data:www.e.org',
      'https://e.org\u0001bad',
      'https://e.org\u007fbad',
      'https://e.org/%0dheader',
      'https://e.org\\x',
    ]) {
      expect(messageLinks(value), isEmpty, reason: value);
    }
    const body = 'begin 644 image.bin\nHTTPS://EXAMPLE.ORG\nend\nhttps://e.org';
    expect(messageLinks(body).map((e) => e.uri.host), ['e.org']);
  });
}
