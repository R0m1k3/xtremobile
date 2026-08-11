/// XMLTV EPG fallback service
///
/// Used when the IPTV provider's `get_short_epg` returns nothing for a channel.
/// Resolution order is decided by the caller (see [XtremServiceMobile]); this
/// service only knows how to fetch, parse, index and cache one XMLTV source.
///
/// Design constraints:
/// - XMLTV dumps are routinely 50-300 MB uncompressed. Parsing is done as a
///   **streaming** pass (`toXmlEvents`) so the whole document is never held in
///   memory, and only programmes inside a short time window are kept.
/// - The reduced index is persisted to disk, so a cold start costs one small
///   JSON read instead of a multi-megabyte download.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'package:xtremobile/core/models/iptv_models.dart' as model;

/// One XMLTV source to try, in priority order.
class XmltvSource {
  /// Human-readable origin, surfaced in settings/diagnostics.
  final String label;
  final String url;
  final Map<String, String>? headers;

  const XmltvSource({
    required this.label,
    required this.url,
    this.headers,
  });
}

/// A single programme kept in the in-memory index.
class XmltvProgramme {
  final DateTime start;
  final DateTime end;
  final String title;
  final String description;

  const XmltvProgramme({
    required this.start,
    required this.end,
    required this.title,
    this.description = '',
  });

  bool covers(DateTime at) => !at.isBefore(start) && at.isBefore(end);

  List<dynamic> toCache() => [
        start.toIso8601String(),
        end.toIso8601String(),
        title,
        description,
      ];

  static XmltvProgramme? fromCache(dynamic raw) {
    if (raw is! List || raw.length < 4) return null;
    final start = DateTime.tryParse(raw[0].toString());
    final end = DateTime.tryParse(raw[1].toString());
    if (start == null || end == null) return null;
    return XmltvProgramme(
      start: start,
      end: end,
      title: raw[2].toString(),
      description: raw[3].toString(),
    );
  }
}

class XmltvService {
  XmltvService(this.cacheDir);

  final String cacheDir;

  /// How long a downloaded+indexed guide stays usable before a refetch.
  static const Duration cacheTtl = Duration(hours: 6);

  /// Only programmes overlapping [now - back, now + forward] are indexed.
  /// Keeps a national guide down to a few hundred KB instead of hundreds of MB.
  static const Duration windowBack = Duration(hours: 3);
  static const Duration windowForward = Duration(hours: 18);

  /// Hard ceiling on the download, so a hostile or broken URL can't fill
  /// the device storage or spin forever.
  static const int maxDownloadBytes = 220 * 1024 * 1024;

  final Map<String, List<XmltvProgramme>> _byChannelId = {};
  final Map<String, String> _normalizedNameToChannelId = {};

  String? _loadedSourceLabel;
  DateTime? _loadedAt;
  Future<bool>? _inFlight;

  /// True once at least one source has been indexed successfully.
  bool get isLoaded => _byChannelId.isNotEmpty;

  /// Label of the source currently backing the index (`null` if none).
  String? get loadedSourceLabel => _loadedSourceLabel;

  int get channelCount => _byChannelId.length;

  bool get _isStale {
    final at = _loadedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > cacheTtl;
  }

  /// Load the first source that yields a usable guide.
  ///
  /// Concurrent callers share a single in-flight attempt. Returns `false` when
  /// every source failed — callers should then simply render "no EPG".
  Future<bool> ensureLoaded(List<XmltvSource> sources) {
    if (isLoaded && !_isStale) return Future.value(true);
    return _inFlight ??= _loadFirstAvailable(sources).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<bool> _loadFirstAvailable(List<XmltvSource> sources) async {
    for (final source in sources) {
      if (source.url.trim().isEmpty) continue;
      try {
        if (await _loadFromDiskCache(source)) {
          _loadedSourceLabel = source.label;
          if (kDebugMode) {
            print(
              '✅ [XMLTV] Disk cache hit "${source.label}" '
              '($channelCount channels)',
            );
          }
          return true;
        }

        if (await _download(source)) {
          _loadedSourceLabel = source.label;
          _loadedAt = DateTime.now();
          unawaited(_writeDiskCache(source));
          if (kDebugMode) {
            print(
              '✅ [XMLTV] Indexed "${source.label}" '
              '($channelCount channels)',
            );
          }
          return true;
        }

        if (kDebugMode) {
          print('⚠️ [XMLTV] "${source.label}" returned no usable programme');
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ [XMLTV] "${source.label}" failed: $e');
      }
    }
    return false;
  }

  // ─── Lookup ────────────────────────────────────────────────────────────────

  /// Find the programme airing at [at] for a channel.
  ///
  /// Matching is tried on the Xtream `epg_channel_id` first (the reliable key),
  /// then on a normalized channel name, which is what rescues providers that
  /// ship empty or non-standard `epg_channel_id` values.
  XmltvProgramme? programmeFor({
    String? epgChannelId,
    String? channelName,
    DateTime? at,
  }) {
    final moment = at ?? DateTime.now();
    final programmes = _programmesFor(
      epgChannelId: epgChannelId,
      channelName: channelName,
    );
    if (programmes == null || programmes.isEmpty) return null;

    for (final programme in programmes) {
      if (programme.covers(moment)) return programme;
    }
    // Nothing airing right now (guide gap): fall back to the next entry so the
    // UI shows something meaningful rather than an empty slot.
    for (final programme in programmes) {
      if (programme.start.isAfter(moment)) return programme;
    }
    return null;
  }

  /// Same lookup, shaped as the app's [model.ShortEPG].
  model.ShortEPG? shortEpgFor({
    required String streamId,
    String? epgChannelId,
    String? channelName,
    DateTime? at,
  }) {
    final programme = programmeFor(
      epgChannelId: epgChannelId,
      channelName: channelName,
      at: at,
    );
    if (programme == null || programme.title.isEmpty) return null;

    return model.ShortEPG(
      id: streamId,
      title: programme.title,
      start: _formatLocal(programme.start),
      end: _formatLocal(programme.end),
      description: programme.description,
    );
  }

  List<XmltvProgramme>? _programmesFor({
    String? epgChannelId,
    String? channelName,
  }) {
    final id = epgChannelId?.trim().toLowerCase();
    if (id != null && id.isNotEmpty) {
      final direct = _byChannelId[id];
      if (direct != null && direct.isNotEmpty) return direct;
    }

    final normalized = normalizeName(channelName ?? '');
    if (normalized.isEmpty) return null;
    final mapped = _normalizedNameToChannelId[normalized];
    if (mapped == null) return null;
    return _byChannelId[mapped];
  }

  void clear() {
    _byChannelId.clear();
    _normalizedNameToChannelId.clear();
    _loadedSourceLabel = null;
    _loadedAt = null;
  }

  // ─── Download & streaming parse ────────────────────────────────────────────

  Future<bool> _download(XmltvSource source) async {
    final uri = Uri.tryParse(source.url.trim());
    if (uri == null || !uri.hasScheme) return false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      // `.xml.gz` bodies arrive as a gzip *payload*, not a gzip
      // Content-Encoding, so decompression is handled explicitly below.
      ..autoUncompress = false;

    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      request.headers.set(HttpHeaders.userAgentHeader, 'XtremFlow/1.0');
      source.headers?.forEach(request.headers.set);

      final response = await request.close().timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('⚠️ [XMLTV] HTTP ${response.statusCode} on ${source.label}');
        }
        return false;
      }

      return indexFromBytes(_capped(response));
    } on TimeoutException {
      if (kDebugMode) print('⏱️ [XMLTV] Timeout on ${source.label}');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Parse and index an XMLTV payload from a byte stream.
  ///
  /// Split out of [_download] so the parsing path is testable without HTTP.
  /// Gzip is detected from the payload itself, and only programmes overlapping
  /// the current window are retained.
  @visibleForTesting
  Future<bool> indexFromBytes(
    Stream<List<int>> bytes, {
    DateTime? now,
  }) async {
    final window = _Window.around(now ?? DateTime.now());
    final channelNames = <String, List<String>>{};
    final programmes = <String, List<XmltvProgramme>>{};

    final events = _decompressed(bytes)
        .transform(const Utf8Decoder(allowMalformed: true))
        .toXmlEvents()
        .normalizeEvents()
        .selectSubtreeEvents(
          (event) => event.name == 'channel' || event.name == 'programme',
        )
        .toXmlNodes()
        .flatten();

    await for (final node in events) {
      if (node is! XmlElement) continue;
      if (node.name.local == 'channel') {
        _indexChannelElement(node, channelNames);
      } else {
        _indexProgrammeElement(node, window, programmes);
      }
    }

    if (programmes.isEmpty) return false;

    _commit(programmes: programmes, channelNames: channelNames);
    _loadedAt = DateTime.now();
    return true;
  }

  void _indexChannelElement(
    XmlElement node,
    Map<String, List<String>> channelNames,
  ) {
    final id = node.getAttribute('id')?.trim().toLowerCase();
    if (id == null || id.isEmpty) return;
    final names = node
        .findElements('display-name')
        .map((e) => e.innerText.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (names.isEmpty) return;
    channelNames.putIfAbsent(id, () => []).addAll(names);
  }

  void _indexProgrammeElement(
    XmlElement node,
    _Window window,
    Map<String, List<XmltvProgramme>> programmes,
  ) {
    final channel = node.getAttribute('channel')?.trim().toLowerCase();
    if (channel == null || channel.isEmpty) return;

    final start = parseXmltvTime(node.getAttribute('start'));
    final end = parseXmltvTime(node.getAttribute('stop'));
    if (start == null || end == null) return;
    if (!window.overlaps(start, end)) return;

    final title = node
            .findElements('title')
            .map((e) => e.innerText.trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => '')
            .trim();
    if (title.isEmpty) return;

    final description = node
        .findElements('desc')
        .map((e) => e.innerText.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');

    programmes.putIfAbsent(channel, () => []).add(
          XmltvProgramme(
            start: start,
            end: end,
            title: title,
            description: description,
          ),
        );
  }

  void _commit({
    required Map<String, List<XmltvProgramme>> programmes,
    required Map<String, List<String>> channelNames,
  }) {
    _byChannelId
      ..clear()
      ..addAll(programmes);
    for (final list in _byChannelId.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }

    _normalizedNameToChannelId.clear();
    // Channel ids are themselves readable labels in most community dumps
    // (`France.2..fr`, `Trace.Toca.fr`), so they are indexed as name
    // candidates too — this rescues channels that carry no <display-name>.
    for (final id in _byChannelId.keys) {
      final fromId = normalizeName(_labelFromChannelId(id));
      if (fromId.isNotEmpty) {
        _normalizedNameToChannelId.putIfAbsent(fromId, () => id);
      }
    }
    channelNames.forEach((id, names) {
      if (!_byChannelId.containsKey(id)) return;
      for (final name in names) {
        final normalized = normalizeName(name);
        if (normalized.isEmpty) continue;
        _normalizedNameToChannelId[normalized] = id;
      }
    });
  }

  /// Enforce [maxDownloadBytes] mid-stream.
  Stream<List<int>> _capped(Stream<List<int>> input) async* {
    var total = 0;
    await for (final chunk in input) {
      total += chunk.length;
      if (total > maxDownloadBytes) {
        throw StateError('XMLTV payload exceeds ${maxDownloadBytes ~/ 1048576}MB');
      }
      yield chunk;
    }
  }

  /// Transparently gunzip when the payload starts with the gzip magic number.
  Stream<List<int>> _decompressed(Stream<List<int>> input) async* {
    final iterator = StreamIterator(input);
    try {
      if (!await iterator.moveNext()) return;

      var head = iterator.current;
      while (head.length < 2 && await iterator.moveNext()) {
        head = [...head, ...iterator.current];
      }

      Stream<List<int>> replayed() async* {
        yield head;
        while (await iterator.moveNext()) {
          yield iterator.current;
        }
      }

      final isGzip = head.length >= 2 && head[0] == 0x1f && head[1] == 0x8b;
      yield* isGzip ? gzip.decoder.bind(replayed()) : replayed();
    } finally {
      await iterator.cancel();
    }
  }

  // ─── Disk cache ────────────────────────────────────────────────────────────

  File _cacheFile(XmltvSource source) {
    final key = source.url.hashCode.toUnsigned(32).toRadixString(16);
    return File('$cacheDir${Platform.pathSeparator}xmltv_$key.json');
  }

  Future<bool> _loadFromDiskCache(XmltvSource source) async {
    final file = _cacheFile(source);
    if (!await file.exists()) return false;

    final fetchedAt = await file.lastModified();
    if (DateTime.now().difference(fetchedAt) > cacheTtl) return false;

    try {
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map) return false;

      final rawChannels = decoded['channels'];
      if (rawChannels is! Map) return false;

      final programmes = <String, List<XmltvProgramme>>{};
      rawChannels.forEach((id, entries) {
        if (entries is! List) return;
        final parsed = entries
            .map(XmltvProgramme.fromCache)
            .whereType<XmltvProgramme>()
            .toList();
        if (parsed.isNotEmpty) programmes[id.toString()] = parsed;
      });
      if (programmes.isEmpty) return false;

      final rawNames = decoded['names'];
      final channelNames = <String, List<String>>{};
      if (rawNames is Map) {
        rawNames.forEach((normalized, id) {
          channelNames
              .putIfAbsent(id.toString(), () => [])
              .add(normalized.toString());
        });
      }

      _commit(programmes: programmes, channelNames: channelNames);
      _loadedAt = fetchedAt;
      return true;
    } catch (e) {
      if (kDebugMode) print('⚠️ [XMLTV] Corrupt disk cache, ignoring: $e');
      return false;
    }
  }

  Future<void> _writeDiskCache(XmltvSource source) async {
    try {
      final payload = {
        'source': source.label,
        'url': source.url,
        'fetchedAt': DateTime.now().toIso8601String(),
        'channels': _byChannelId.map(
          (id, list) => MapEntry(id, list.map((p) => p.toCache()).toList()),
        ),
        'names': _normalizedNameToChannelId,
      };
      await _cacheFile(source).writeAsString(json.encode(payload), flush: true);
    } catch (e) {
      if (kDebugMode) print('⚠️ [XMLTV] Could not persist cache: $e');
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Parse an XMLTV timestamp: `20260811183000 +0200` (offset optional).
  static DateTime? parseXmltvTime(String? raw) {
    final value = raw?.trim();
    if (value == null || value.length < 14) return null;

    int? part(int start, int end) => int.tryParse(value.substring(start, end));

    final year = part(0, 4);
    final month = part(4, 6);
    final day = part(6, 8);
    final hour = part(8, 10);
    final minute = part(10, 12);
    final second = part(12, 14);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }

    final utc = DateTime.utc(year, month, day, hour, minute, second);

    final offset = value.substring(14).trim();
    if (offset.isEmpty) return utc.toLocal();

    final match = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(offset);
    if (match == null) return utc.toLocal();

    final sign = match.group(1) == '-' ? -1 : 1;
    final offsetDuration = Duration(
      hours: int.parse(match.group(2)!),
      minutes: int.parse(match.group(3)!),
    );
    return utc.subtract(offsetDuration * sign).toLocal();
  }

  /// Turn an XMLTV channel id into the label it encodes.
  ///
  /// `France.2..fr` → `France 2`, `Trace.Toca.fr` → `Trace Toca`.
  static String _labelFromChannelId(String id) {
    var value = id.replaceAll(
      RegExp(
        r'\.(fr|uk|us|de|es|it|be|ch|ca|nl|pt|pl|ar|br|tr|ma|dz|tn)$',
        caseSensitive: false,
      ),
      '',
    );
    return value.replaceAll('.', ' ').trim();
  }

  /// Reduce a channel label to a comparable key.
  ///
  /// Strips accents, quality suffixes (`HD`, `FHD`, `4K`, …) and any
  /// punctuation, so `TF1 HD`, `tf1-fhd` and `TF1` all collapse to `tf1`.
  static String normalizeName(String raw) {
    var value = raw.toLowerCase().trim();
    if (value.isEmpty) return '';

    const accents = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
    const plain = 'aaaaaaceeeeiiiinooooouuuuyy';
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final index = accents.indexOf(char);
      buffer.write(index >= 0 ? plain[index] : char);
    }
    value = buffer.toString();

    // Drop the country prefix providers prepend.
    // Bracketed form — "|FR| TF1", "[FR] TF1", "(FR) TF1".
    value = value.replaceFirst(
      RegExp(r'^\s*[\|\[\(][a-z]{2,4}[\|\]\)]\s*'),
      '',
    );
    // Bare form — "FR: TF1". A colon is required: accepting a dash too would
    // eat legitimate names like "Ciné - Premier".
    value = value.replaceFirst(RegExp(r'^\s*[a-z]{2,3}\s*:\s*'), '');

    value = value.replaceAll(RegExp(r'[^a-z0-9+]'), '');

    for (final suffix in const [
      'fullhd',
      'ultrahd',
      'uhd',
      'fhd',
      'hdr',
      '4k',
      '1080p',
      '720p',
      'hd',
      'sd',
    ]) {
      if (value.length > suffix.length && value.endsWith(suffix)) {
        value = value.substring(0, value.length - suffix.length);
        break;
      }
    }
    return value;
  }

  static String _formatLocal(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

class _Window {
  final DateTime from;
  final DateTime to;

  const _Window(this.from, this.to);

  factory _Window.around(DateTime now) => _Window(
        now.subtract(XmltvService.windowBack),
        now.add(XmltvService.windowForward),
      );

  bool overlaps(DateTime start, DateTime end) =>
      end.isAfter(from) && start.isBefore(to);
}
