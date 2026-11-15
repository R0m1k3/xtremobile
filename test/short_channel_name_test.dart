import 'package:flutter_test/flutter_test.dart';
import 'package:xtremobile/features/iptv/widgets/live_widgets.dart';

void main() {
  test('drops the country prefix, quality tags and brackets', () {
    expect(
      shortChannelName(
        'FR| BEIN SPORTS MAX 10 FHD HEVC MULTI-AUDIO (ÉVÉNEMENTS EN DIRECT)',
      ),
      'BEIN SPORTS MAX 10',
    );
    expect(shortChannelName('CANAL+ SPORT 360 FHD'), 'CANAL+ SPORT 360');
    expect(shortChannelName('UK: SKY SPORTS F1 UHD'), 'SKY SPORTS F1');
    expect(shortChannelName("L'ÉQUIPE"), "L'ÉQUIPE");
  });

  test('keeps the name when nothing else is left', () {
    expect(shortChannelName('FHD'), 'FHD');
  });
}
