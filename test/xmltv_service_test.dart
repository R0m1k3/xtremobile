import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtremobile/features/iptv/services/xmltv_service.dart';

/// Fixture shaped exactly like the community dumps the fallback consumes
/// (channel ids with dots, `+0200` offsets, base-less titles).
String _fixture(DateTime now) {
  String stamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final utc = value.toUtc();
    return '${utc.year}${two(utc.month)}${two(utc.day)}'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)} +0000';
  }

  final airingStart = now.subtract(const Duration(minutes: 20));
  final airingEnd = now.add(const Duration(minutes: 40));
  final nextEnd = airingEnd.add(const Duration(minutes: 50));
  final farFuture = now.add(const Duration(days: 4));

  return '''<?xml version="1.0" encoding="UTF-8" ?>
<tv generator-info-name="none">
  <channel id="TF1.fr">
    <display-name lang="fr">TF1</display-name>
  </channel>
  <channel id="France.3.-.Nord.Pas-de-Calais.fr">
    <display-name lang="fr">France 3 - Nord Pas-de-Calais</display-name>
  </channel>
  <channel id="Cine.Premier.fr">
    <display-name lang="fr">Ciné+ Premier</display-name>
  </channel>
  <programme channel="TF1.fr" start="${stamp(airingStart)}" stop="${stamp(airingEnd)}">
    <title lang="fr">Journal de 20h</title>
    <desc lang="fr">Le rendez-vous d'information.</desc>
  </programme>
  <programme channel="TF1.fr" start="${stamp(airingEnd)}" stop="${stamp(nextEnd)}">
    <title lang="fr">Film du mardi</title>
  </programme>
  <programme channel="France.3.-.Nord.Pas-de-Calais.fr" start="${stamp(airingStart)}" stop="${stamp(airingEnd)}">
    <title lang="fr">Ici 19/20</title>
  </programme>
  <programme channel="Cine.Premier.fr" start="${stamp(farFuture)}" stop="${stamp(farFuture.add(const Duration(hours: 1)))}">
    <title lang="fr">Hors fenêtre</title>
  </programme>
</tv>''';
}

Stream<List<int>> _bytes(String xml) => Stream.value(utf8.encode(xml));

void main() {
  group('parseXmltvTime', () {
    test('applies the trailing UTC offset', () {
      final parsed = XmltvService.parseXmltvTime('20260811183000 +0200');
      expect(parsed, isNotNull);
      expect(
        parsed!.toUtc(),
        DateTime.utc(2026, 8, 11, 16, 30),
        reason: '18:30 at +0200 is 16:30 UTC',
      );
    });

    test('handles a negative offset', () {
      final parsed = XmltvService.parseXmltvTime('20260811183000 -0430');
      expect(parsed!.toUtc(), DateTime.utc(2026, 8, 11, 23, 0));
    });

    test('treats a missing offset as UTC', () {
      final parsed = XmltvService.parseXmltvTime('20260811183000');
      expect(parsed!.toUtc(), DateTime.utc(2026, 8, 11, 18, 30));
    });

    test('rejects malformed input', () {
      expect(XmltvService.parseXmltvTime(null), isNull);
      expect(XmltvService.parseXmltvTime(''), isNull);
      expect(XmltvService.parseXmltvTime('2026081118'), isNull);
      expect(XmltvService.parseXmltvTime('not-a-timestamp!'), isNull);
    });
  });

  group('normalizeName', () {
    test('collapses quality suffixes', () {
      expect(XmltvService.normalizeName('TF1 HD'), 'tf1');
      expect(XmltvService.normalizeName('tf1-fhd'), 'tf1');
      expect(XmltvService.normalizeName('TF1 4K'), 'tf1');
      expect(XmltvService.normalizeName('TF1'), 'tf1');
    });

    test('strips country prefixes in both forms', () {
      expect(XmltvService.normalizeName('FR: TF1'), 'tf1');
      expect(XmltvService.normalizeName('|FR| TF1 HD'), 'tf1');
      expect(XmltvService.normalizeName('[FR] TF1'), 'tf1');
    });

    test('keeps a dash-separated name intact', () {
      // "Ciné - Premier" must not lose its first word to prefix stripping.
      expect(XmltvService.normalizeName('Ciné - Premier'), 'cinepremier');
    });

    test('folds accents and keeps the plus sign', () {
      expect(XmltvService.normalizeName('Ciné+ Émotion'), 'cine+emotion');
    });

    test('is empty for a blank label', () {
      expect(XmltvService.normalizeName('   '), '');
    });
  });

  group('indexFromBytes + lookup', () {
    late XmltvService service;
    late DateTime now;

    setUp(() async {
      service = XmltvService(Directory.systemTemp.path);
      now = DateTime.now();
      final indexed = await service.indexFromBytes(
        _bytes(_fixture(now)),
        now: now,
      );
      expect(indexed, isTrue);
    });

    test('matches on epg_channel_id', () {
      final epg = service.shortEpgFor(
        streamId: '123',
        epgChannelId: 'TF1.fr',
        channelName: 'anything',
      );
      expect(epg, isNotNull);
      expect(epg!.title, 'Journal de 20h');
      expect(epg.id, '123');
      expect(epg.description, "Le rendez-vous d'information.");
    });

    test('falls back to the channel name when the id is unknown', () {
      final epg = service.shortEpgFor(
        streamId: '456',
        epgChannelId: '',
        channelName: 'FR: TF1 HD',
      );
      expect(epg, isNotNull);
      expect(epg!.title, 'Journal de 20h');
    });

    test('matches a name reconstructed from a dotted channel id', () {
      final epg = service.shortEpgFor(
        streamId: '789',
        epgChannelId: 'not-in-guide',
        channelName: 'France 3 - Nord Pas-de-Calais',
      );
      expect(epg, isNotNull);
      expect(epg!.title, 'Ici 19/20');
    });

    test('returns the currently airing programme, not the next one', () {
      final programme = service.programmeFor(
        epgChannelId: 'TF1.fr',
        at: now,
      );
      expect(programme!.title, 'Journal de 20h');
      expect(programme.covers(now), isTrue);
    });

    test('falls forward to the next entry when nothing is airing', () {
      // 10 minutes into the gap-free schedule's second slot.
      final during = now.add(const Duration(minutes: 50));
      final programme = service.programmeFor(
        epgChannelId: 'TF1.fr',
        at: during,
      );
      expect(programme!.title, 'Film du mardi');
    });

    test('drops programmes outside the retention window', () {
      // The Ciné+ entry is 4 days out — beyond windowForward, so the channel
      // holds no programme at all.
      final epg = service.shortEpgFor(
        streamId: '999',
        epgChannelId: 'Cine.Premier.fr',
      );
      expect(epg, isNull);
    });

    test('returns null for a channel absent from the guide', () {
      final epg = service.shortEpgFor(
        streamId: '000',
        epgChannelId: 'unknown.channel',
        channelName: 'Chaîne Inconnue',
      );
      expect(epg, isNull);
    });

    test('parses a gzipped payload transparently', () async {
      final gzipped = XmltvService(Directory.systemTemp.path);
      final compressed = gzip.encode(utf8.encode(_fixture(now)));
      final indexed = await gzipped.indexFromBytes(
        Stream.value(compressed),
        now: now,
      );
      expect(indexed, isTrue);
      expect(
        gzipped.shortEpgFor(streamId: '1', epgChannelId: 'TF1.fr')?.title,
        'Journal de 20h',
      );
    });

    test('reports failure on a payload with no programme', () async {
      final empty = XmltvService(Directory.systemTemp.path);
      final indexed = await empty.indexFromBytes(
        _bytes('<?xml version="1.0"?><tv></tv>'),
      );
      expect(indexed, isFalse);
      expect(empty.isLoaded, isFalse);
    });
  });
}
