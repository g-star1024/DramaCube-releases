import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// 收藏条目（对齐 macOS 版 FavoriteItem）。
class Favorites extends Table {
  TextColumn get dramaId => text()();
  TextColumn get title => text()();
  TextColumn get coverURL => text().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {dramaId};
}

/// 历史 / 播放进度条目（对齐 macOS 版 HistoryItem）。
class Histories extends Table {
  TextColumn get key => text()(); // dramaId + ":" + episodeId
  TextColumn get dramaId => text()();
  TextColumn get episodeId => text()();
  TextColumn get title => text()();
  TextColumn get episodeTitle => text()();
  TextColumn get coverURL => text().nullable()();
  RealColumn get position => real().withDefault(const Constant(0))();
  RealColumn get duration => real().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Favorites, Histories])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'dramacube'));

  @override
  int get schemaVersion => 1;

  // MARK: 收藏

  Future<List<Favorite>> allFavorites() =>
      (select(favorites)..orderBy([(t) => OrderingTerm.desc(t.addedAt)])).get();

  Future<bool> isFavorite(String dramaId) async =>
      await (select(favorites)..where((t) => t.dramaId.equals(dramaId))).getSingleOrNull() != null;

  Future<void> toggleFavorite(String dramaId, String title, String? coverURL) async {
    if (await isFavorite(dramaId)) {
      await (delete(favorites)..where((t) => t.dramaId.equals(dramaId))).go();
    } else {
      await into(favorites).insert(FavoritesCompanion.insert(
        dramaId: dramaId, title: title, coverURL: Value(coverURL),
      ));
    }
  }

  Future<void> removeFavorite(String dramaId) =>
      (delete(favorites)..where((t) => t.dramaId.equals(dramaId))).go();

  // MARK: 历史 / 进度

  Future<List<History>> allHistories() =>
      (select(histories)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();

  Future<void> saveProgress({
    required String dramaId,
    required String episodeId,
    required String title,
    required String episodeTitle,
    String? coverURL,
    required double position,
    required double duration,
  }) async {
    final key = '$dramaId:$episodeId';
    await into(histories).insertOnConflictUpdate(HistoriesCompanion.insert(
      key: key,
      dramaId: dramaId,
      episodeId: episodeId,
      title: title,
      episodeTitle: episodeTitle,
      coverURL: Value(coverURL),
      position: Value(position),
      duration: Value(duration),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<History?> progressOf(String dramaId, String episodeId) =>
      (select(histories)..where((t) => t.key.equals('$dramaId:$episodeId'))).getSingleOrNull();

  Future<void> clearHistory() => delete(histories).go();
}
