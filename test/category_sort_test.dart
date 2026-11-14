import 'package:flutter_test/flutter_test.dart';
import 'package:xtremobile/core/utils/category_sort.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';

void main() {
  group('splitFavorites', () {
    test('puts favourites first and keeps the existing order in each part', () {
      // Geo-sorted input: "France" groups first, then alphabetical.
      final sorted = ['FR Cinéma', 'FR Sport', 'BE Info', 'UK News', 'US Kids'];
      final favs = {'US Kids', 'FR Sport'};

      final split = splitFavorites(sorted, favs.contains);

      expect(split.favorites, ['FR Sport', 'US Kids']);
      expect(split.others, ['FR Cinéma', 'BE Info', 'UK News']);
    });

    test('no favourites leaves the list untouched', () {
      final split = splitFavorites(['A', 'B'], (_) => false);
      expect(split.favorites, isEmpty);
      expect(split.others, ['A', 'B']);
    });
  });

  test('favourite keys are scoped by playlist', () {
    expect(
      MobileFavoriteCategoriesNotifier.keyFor('p1', '12'),
      isNot(MobileFavoriteCategoriesNotifier.keyFor('p2', '12')),
    );
  });
}
