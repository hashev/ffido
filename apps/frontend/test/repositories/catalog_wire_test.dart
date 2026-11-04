import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void main() {
  test(
    'old requests keep statistics and new options survive serialization',
    () {
      final old = wire.ListConferencesRequest.fromBuffer([]);
      expect(old.omitStatistics, isFalse);
      expect(old.bookmarkedOnly, isFalse);
      final request = wire.ListConferencesRequest(
        omitStatistics: true,
        bookmarkedOnly: true,
        sort: wire.ConferenceSort.CONFERENCE_SORT_CATALOG,
      );
      final result = wire.ListConferencesRequest.fromBuffer(
        request.writeToBuffer(),
      );
      expect(result.omitStatistics, isTrue);
      expect(result.bookmarkedOnly, isTrue);
      expect(result.sort.value, 4);
      expect(wire.ConferenceSort.CONFERENCE_SORT_UNREAD.value, 3);
      expect(
        wire.SessionInfo.fromBuffer([]).supportsLightweightConferenceCatalog,
        isFalse,
      );
      final session = wire.SessionInfo(
        supportsLightweightConferenceCatalog: true,
      );
      expect(
        wire.SessionInfo.fromBuffer(session.writeToBuffer())
            .supportsLightweightConferenceCatalog,
        isTrue,
      );
    },
  );
}
