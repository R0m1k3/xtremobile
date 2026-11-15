import 'package:flutter_test/flutter_test.dart';
import 'package:xtremobile/core/utils/group_label.dart';

void main() {
  group('GroupLabel.parse', () {
    test('splits the usual provider prefixes', () {
      for (final raw in [
        'FR | Sport',
        'FR| Sport',
        '|FR| Sport',
        'FR - Sport',
        'FR: Sport',
        '[FR] Sport',
        '(FR) Sport',
        'fr | Sport',
      ]) {
        final label = GroupLabel.parse(raw);
        expect(label.name, 'Sport', reason: raw);
        expect(label.country, 'France', reason: raw);
      }
    });

    test('keeps an unknown upper-case code as is', () {
      final label = GroupLabel.parse('EXYU | Sport');
      expect(label.country, 'Ex-Yougoslavie');
      final unknown = GroupLabel.parse('XYZ | Films');
      expect(unknown.name, 'Films');
      expect(unknown.country, 'XYZ');
    });

    test('leaves names without a prefix untouched', () {
      expect(GroupLabel.parse('Sport').name, 'Sport');
      expect(GroupLabel.parse('Sport').country, isNull);
      expect(GroupLabel.parse('4K UHD').name, '4K UHD');
      // A lower-case word before a dash is not a country code.
      final label = GroupLabel.parse('Info - Monde');
      expect(label.name, 'Info - Monde');
      expect(label.country, isNull);
    });

    test('keeps the rest of the name intact', () {
      final label = GroupLabel.parse('BE | Infos | Wallonie');
      expect(label.name, 'Infos | Wallonie');
      expect(label.country, 'Belgique');
    });
  });

  group('GroupLabel.meta', () {
    test('joins country and channel count', () {
      const label = GroupLabel(name: 'Sport', country: 'France');
      expect(label.meta(channelCount: 36), 'France · 36 chaînes');
      expect(label.meta(channelCount: 1), 'France · 1 chaîne');
      expect(label.meta(), 'France');
      expect(
          const GroupLabel(name: 'Sport').meta(channelCount: 2), '2 chaînes');
      expect(const GroupLabel(name: 'Sport').meta(), '');
    });
  });
}
