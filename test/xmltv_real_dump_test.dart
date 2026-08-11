import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtremobile/features/iptv/services/xmltv_service.dart';

/// Parses a real community XMLTV dump end to end.
///
/// Skipped unless `XMLTV_FIXTURE` points at a `.xml`/`.xml.gz` file, so CI and
/// day-to-day runs stay offline and fast:
///
///   flutter test test/xmltv_real_dump_test.dart \
///     --dart-define=XMLTV_FIXTURE=C:\path\epg_ripper_FR1.xml.gz
const String _fixturePath = String.fromEnvironment('XMLTV_FIXTURE');

void main() {
  test(
    'indexes a real XMLTV dump within a mobile memory budget',
    () async {
      final file = File(_fixturePath);
      expect(file.existsSync(), isTrue, reason: 'fixture not found');

      final service = XmltvService(Directory.systemTemp.path);
      final started = DateTime.now();

      final indexed = await service.indexFromBytes(file.openRead());

      final elapsed = DateTime.now().difference(started);
      final peakMb = ProcessInfo.maxRss / 1048576;

      // ignore: avoid_print
      print(
        'channels=${service.channelCount} '
        'time=${elapsed.inMilliseconds}ms '
        'peakRss=${peakMb.toStringAsFixed(1)}MB',
      );

      expect(indexed, isTrue);
      expect(service.channelCount, greaterThan(100));

      // The whole point of the streaming parse: a ~46 MB document must never
      // be resident. Generous ceiling to stay stable across VM versions.
      expect(peakMb, lessThan(400));

      // Spot-check the matching paths with labels shaped the way an Xtream
      // provider reports them.
      const probes = <List<String>>[
        ['', 'TF1 HD'],
        ['', 'FR: France 2'],
        ['', 'M6 FHD'],
        ['', '|FR| France 5'],
        ['', 'Arte'],
      ];

      var hits = 0;
      for (final probe in probes) {
        final epg = service.shortEpgFor(
          streamId: 'x',
          epgChannelId: probe[0],
          channelName: probe[1],
        );
        // ignore: avoid_print
        print('  ${probe[1].padRight(16)} -> ${epg?.title ?? "NO MATCH"}');
        if (epg != null) hits++;
      }

      expect(hits, greaterThanOrEqualTo(4),
          reason: 'name matching should resolve mainstream French channels');
    },
    skip: _fixturePath.isEmpty ? 'set --dart-define=XMLTV_FIXTURE' : false,
  );
}
