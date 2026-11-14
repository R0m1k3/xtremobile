/// Splits an already sorted list into favourites and the rest, keeping the
/// existing order inside each part (alphabetical, geo-IP first, ...).
({List<T> favorites, List<T> others}) splitFavorites<T>(
  List<T> sorted,
  bool Function(T item) isFavorite,
) {
  final favorites = <T>[];
  final others = <T>[];
  for (final item in sorted) {
    (isFavorite(item) ? favorites : others).add(item);
  }
  return (favorites: favorites, others: others);
}
