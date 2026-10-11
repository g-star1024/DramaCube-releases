// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, Favorite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dramaIdMeta = const VerificationMeta(
    'dramaId',
  );
  @override
  late final GeneratedColumn<String> dramaId = GeneratedColumn<String>(
    'drama_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverURLMeta = const VerificationMeta(
    'coverURL',
  );
  @override
  late final GeneratedColumn<String> coverURL = GeneratedColumn<String>(
    'cover_u_r_l',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [dramaId, title, coverURL, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<Favorite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('drama_id')) {
      context.handle(
        _dramaIdMeta,
        dramaId.isAcceptableOrUnknown(data['drama_id']!, _dramaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_dramaIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_u_r_l')) {
      context.handle(
        _coverURLMeta,
        coverURL.isAcceptableOrUnknown(data['cover_u_r_l']!, _coverURLMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {dramaId};
  @override
  Favorite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favorite(
      dramaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}drama_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverURL: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_u_r_l'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class Favorite extends DataClass implements Insertable<Favorite> {
  final String dramaId;
  final String title;
  final String? coverURL;
  final DateTime addedAt;
  const Favorite({
    required this.dramaId,
    required this.title,
    this.coverURL,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['drama_id'] = Variable<String>(dramaId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverURL != null) {
      map['cover_u_r_l'] = Variable<String>(coverURL);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      dramaId: Value(dramaId),
      title: Value(title),
      coverURL: coverURL == null && nullToAbsent
          ? const Value.absent()
          : Value(coverURL),
      addedAt: Value(addedAt),
    );
  }

  factory Favorite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favorite(
      dramaId: serializer.fromJson<String>(json['dramaId']),
      title: serializer.fromJson<String>(json['title']),
      coverURL: serializer.fromJson<String?>(json['coverURL']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dramaId': serializer.toJson<String>(dramaId),
      'title': serializer.toJson<String>(title),
      'coverURL': serializer.toJson<String?>(coverURL),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  Favorite copyWith({
    String? dramaId,
    String? title,
    Value<String?> coverURL = const Value.absent(),
    DateTime? addedAt,
  }) => Favorite(
    dramaId: dramaId ?? this.dramaId,
    title: title ?? this.title,
    coverURL: coverURL.present ? coverURL.value : this.coverURL,
    addedAt: addedAt ?? this.addedAt,
  );
  Favorite copyWithCompanion(FavoritesCompanion data) {
    return Favorite(
      dramaId: data.dramaId.present ? data.dramaId.value : this.dramaId,
      title: data.title.present ? data.title.value : this.title,
      coverURL: data.coverURL.present ? data.coverURL.value : this.coverURL,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Favorite(')
          ..write('dramaId: $dramaId, ')
          ..write('title: $title, ')
          ..write('coverURL: $coverURL, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(dramaId, title, coverURL, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favorite &&
          other.dramaId == this.dramaId &&
          other.title == this.title &&
          other.coverURL == this.coverURL &&
          other.addedAt == this.addedAt);
}

class FavoritesCompanion extends UpdateCompanion<Favorite> {
  final Value<String> dramaId;
  final Value<String> title;
  final Value<String?> coverURL;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.dramaId = const Value.absent(),
    this.title = const Value.absent(),
    this.coverURL = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String dramaId,
    required String title,
    this.coverURL = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : dramaId = Value(dramaId),
       title = Value(title);
  static Insertable<Favorite> custom({
    Expression<String>? dramaId,
    Expression<String>? title,
    Expression<String>? coverURL,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dramaId != null) 'drama_id': dramaId,
      if (title != null) 'title': title,
      if (coverURL != null) 'cover_u_r_l': coverURL,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<String>? dramaId,
    Value<String>? title,
    Value<String?>? coverURL,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      dramaId: dramaId ?? this.dramaId,
      title: title ?? this.title,
      coverURL: coverURL ?? this.coverURL,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dramaId.present) {
      map['drama_id'] = Variable<String>(dramaId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverURL.present) {
      map['cover_u_r_l'] = Variable<String>(coverURL.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('dramaId: $dramaId, ')
          ..write('title: $title, ')
          ..write('coverURL: $coverURL, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoriesTable extends Histories
    with TableInfo<$HistoriesTable, History> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dramaIdMeta = const VerificationMeta(
    'dramaId',
  );
  @override
  late final GeneratedColumn<String> dramaId = GeneratedColumn<String>(
    'drama_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeIdMeta = const VerificationMeta(
    'episodeId',
  );
  @override
  late final GeneratedColumn<String> episodeId = GeneratedColumn<String>(
    'episode_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeTitleMeta = const VerificationMeta(
    'episodeTitle',
  );
  @override
  late final GeneratedColumn<String> episodeTitle = GeneratedColumn<String>(
    'episode_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverURLMeta = const VerificationMeta(
    'coverURL',
  );
  @override
  late final GeneratedColumn<String> coverURL = GeneratedColumn<String>(
    'cover_u_r_l',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<double> position = GeneratedColumn<double>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<double> duration = GeneratedColumn<double>(
    'duration',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    dramaId,
    episodeId,
    title,
    episodeTitle,
    coverURL,
    position,
    duration,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<History> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('drama_id')) {
      context.handle(
        _dramaIdMeta,
        dramaId.isAcceptableOrUnknown(data['drama_id']!, _dramaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_dramaIdMeta);
    }
    if (data.containsKey('episode_id')) {
      context.handle(
        _episodeIdMeta,
        episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_episodeIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('episode_title')) {
      context.handle(
        _episodeTitleMeta,
        episodeTitle.isAcceptableOrUnknown(
          data['episode_title']!,
          _episodeTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_episodeTitleMeta);
    }
    if (data.containsKey('cover_u_r_l')) {
      context.handle(
        _coverURLMeta,
        coverURL.isAcceptableOrUnknown(data['cover_u_r_l']!, _coverURLMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  History map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return History(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      dramaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}drama_id'],
      )!,
      episodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      episodeTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_title'],
      )!,
      coverURL: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_u_r_l'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}position'],
      )!,
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}duration'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $HistoriesTable createAlias(String alias) {
    return $HistoriesTable(attachedDatabase, alias);
  }
}

class History extends DataClass implements Insertable<History> {
  final String key;
  final String dramaId;
  final String episodeId;
  final String title;
  final String episodeTitle;
  final String? coverURL;
  final double position;
  final double duration;
  final DateTime updatedAt;
  const History({
    required this.key,
    required this.dramaId,
    required this.episodeId,
    required this.title,
    required this.episodeTitle,
    this.coverURL,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['drama_id'] = Variable<String>(dramaId);
    map['episode_id'] = Variable<String>(episodeId);
    map['title'] = Variable<String>(title);
    map['episode_title'] = Variable<String>(episodeTitle);
    if (!nullToAbsent || coverURL != null) {
      map['cover_u_r_l'] = Variable<String>(coverURL);
    }
    map['position'] = Variable<double>(position);
    map['duration'] = Variable<double>(duration);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  HistoriesCompanion toCompanion(bool nullToAbsent) {
    return HistoriesCompanion(
      key: Value(key),
      dramaId: Value(dramaId),
      episodeId: Value(episodeId),
      title: Value(title),
      episodeTitle: Value(episodeTitle),
      coverURL: coverURL == null && nullToAbsent
          ? const Value.absent()
          : Value(coverURL),
      position: Value(position),
      duration: Value(duration),
      updatedAt: Value(updatedAt),
    );
  }

  factory History.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return History(
      key: serializer.fromJson<String>(json['key']),
      dramaId: serializer.fromJson<String>(json['dramaId']),
      episodeId: serializer.fromJson<String>(json['episodeId']),
      title: serializer.fromJson<String>(json['title']),
      episodeTitle: serializer.fromJson<String>(json['episodeTitle']),
      coverURL: serializer.fromJson<String?>(json['coverURL']),
      position: serializer.fromJson<double>(json['position']),
      duration: serializer.fromJson<double>(json['duration']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'dramaId': serializer.toJson<String>(dramaId),
      'episodeId': serializer.toJson<String>(episodeId),
      'title': serializer.toJson<String>(title),
      'episodeTitle': serializer.toJson<String>(episodeTitle),
      'coverURL': serializer.toJson<String?>(coverURL),
      'position': serializer.toJson<double>(position),
      'duration': serializer.toJson<double>(duration),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  History copyWith({
    String? key,
    String? dramaId,
    String? episodeId,
    String? title,
    String? episodeTitle,
    Value<String?> coverURL = const Value.absent(),
    double? position,
    double? duration,
    DateTime? updatedAt,
  }) => History(
    key: key ?? this.key,
    dramaId: dramaId ?? this.dramaId,
    episodeId: episodeId ?? this.episodeId,
    title: title ?? this.title,
    episodeTitle: episodeTitle ?? this.episodeTitle,
    coverURL: coverURL.present ? coverURL.value : this.coverURL,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  History copyWithCompanion(HistoriesCompanion data) {
    return History(
      key: data.key.present ? data.key.value : this.key,
      dramaId: data.dramaId.present ? data.dramaId.value : this.dramaId,
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      title: data.title.present ? data.title.value : this.title,
      episodeTitle: data.episodeTitle.present
          ? data.episodeTitle.value
          : this.episodeTitle,
      coverURL: data.coverURL.present ? data.coverURL.value : this.coverURL,
      position: data.position.present ? data.position.value : this.position,
      duration: data.duration.present ? data.duration.value : this.duration,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('History(')
          ..write('key: $key, ')
          ..write('dramaId: $dramaId, ')
          ..write('episodeId: $episodeId, ')
          ..write('title: $title, ')
          ..write('episodeTitle: $episodeTitle, ')
          ..write('coverURL: $coverURL, ')
          ..write('position: $position, ')
          ..write('duration: $duration, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    key,
    dramaId,
    episodeId,
    title,
    episodeTitle,
    coverURL,
    position,
    duration,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is History &&
          other.key == this.key &&
          other.dramaId == this.dramaId &&
          other.episodeId == this.episodeId &&
          other.title == this.title &&
          other.episodeTitle == this.episodeTitle &&
          other.coverURL == this.coverURL &&
          other.position == this.position &&
          other.duration == this.duration &&
          other.updatedAt == this.updatedAt);
}

class HistoriesCompanion extends UpdateCompanion<History> {
  final Value<String> key;
  final Value<String> dramaId;
  final Value<String> episodeId;
  final Value<String> title;
  final Value<String> episodeTitle;
  final Value<String?> coverURL;
  final Value<double> position;
  final Value<double> duration;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const HistoriesCompanion({
    this.key = const Value.absent(),
    this.dramaId = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.title = const Value.absent(),
    this.episodeTitle = const Value.absent(),
    this.coverURL = const Value.absent(),
    this.position = const Value.absent(),
    this.duration = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoriesCompanion.insert({
    required String key,
    required String dramaId,
    required String episodeId,
    required String title,
    required String episodeTitle,
    this.coverURL = const Value.absent(),
    this.position = const Value.absent(),
    this.duration = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       dramaId = Value(dramaId),
       episodeId = Value(episodeId),
       title = Value(title),
       episodeTitle = Value(episodeTitle);
  static Insertable<History> custom({
    Expression<String>? key,
    Expression<String>? dramaId,
    Expression<String>? episodeId,
    Expression<String>? title,
    Expression<String>? episodeTitle,
    Expression<String>? coverURL,
    Expression<double>? position,
    Expression<double>? duration,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (dramaId != null) 'drama_id': dramaId,
      if (episodeId != null) 'episode_id': episodeId,
      if (title != null) 'title': title,
      if (episodeTitle != null) 'episode_title': episodeTitle,
      if (coverURL != null) 'cover_u_r_l': coverURL,
      if (position != null) 'position': position,
      if (duration != null) 'duration': duration,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoriesCompanion copyWith({
    Value<String>? key,
    Value<String>? dramaId,
    Value<String>? episodeId,
    Value<String>? title,
    Value<String>? episodeTitle,
    Value<String?>? coverURL,
    Value<double>? position,
    Value<double>? duration,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return HistoriesCompanion(
      key: key ?? this.key,
      dramaId: dramaId ?? this.dramaId,
      episodeId: episodeId ?? this.episodeId,
      title: title ?? this.title,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      coverURL: coverURL ?? this.coverURL,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (dramaId.present) {
      map['drama_id'] = Variable<String>(dramaId.value);
    }
    if (episodeId.present) {
      map['episode_id'] = Variable<String>(episodeId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (episodeTitle.present) {
      map['episode_title'] = Variable<String>(episodeTitle.value);
    }
    if (coverURL.present) {
      map['cover_u_r_l'] = Variable<String>(coverURL.value);
    }
    if (position.present) {
      map['position'] = Variable<double>(position.value);
    }
    if (duration.present) {
      map['duration'] = Variable<double>(duration.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoriesCompanion(')
          ..write('key: $key, ')
          ..write('dramaId: $dramaId, ')
          ..write('episodeId: $episodeId, ')
          ..write('title: $title, ')
          ..write('episodeTitle: $episodeTitle, ')
          ..write('coverURL: $coverURL, ')
          ..write('position: $position, ')
          ..write('duration: $duration, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $HistoriesTable histories = $HistoriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [favorites, histories];
}

typedef $$FavoritesTableCreateCompanionBuilder =
    FavoritesCompanion Function({
      required String dramaId,
      required String title,
      Value<String?> coverURL,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });
typedef $$FavoritesTableUpdateCompanionBuilder =
    FavoritesCompanion Function({
      Value<String> dramaId,
      Value<String> title,
      Value<String?> coverURL,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$FavoritesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get dramaId => $composableBuilder(
    column: $table.dramaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverURL => $composableBuilder(
    column: $table.coverURL,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoritesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get dramaId => $composableBuilder(
    column: $table.dramaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverURL => $composableBuilder(
    column: $table.coverURL,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get dramaId =>
      $composableBuilder(column: $table.dramaId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverURL =>
      $composableBuilder(column: $table.coverURL, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoritesTable,
          Favorite,
          $$FavoritesTableFilterComposer,
          $$FavoritesTableOrderingComposer,
          $$FavoritesTableAnnotationComposer,
          $$FavoritesTableCreateCompanionBuilder,
          $$FavoritesTableUpdateCompanionBuilder,
          (Favorite, BaseReferences<_$AppDatabase, $FavoritesTable, Favorite>),
          Favorite,
          PrefetchHooks Function()
        > {
  $$FavoritesTableTableManager(_$AppDatabase db, $FavoritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> dramaId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverURL = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion(
                dramaId: dramaId,
                title: title,
                coverURL: coverURL,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String dramaId,
                required String title,
                Value<String?> coverURL = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion.insert(
                dramaId: dramaId,
                title: title,
                coverURL: coverURL,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoritesTable,
      Favorite,
      $$FavoritesTableFilterComposer,
      $$FavoritesTableOrderingComposer,
      $$FavoritesTableAnnotationComposer,
      $$FavoritesTableCreateCompanionBuilder,
      $$FavoritesTableUpdateCompanionBuilder,
      (Favorite, BaseReferences<_$AppDatabase, $FavoritesTable, Favorite>),
      Favorite,
      PrefetchHooks Function()
    >;
typedef $$HistoriesTableCreateCompanionBuilder =
    HistoriesCompanion Function({
      required String key,
      required String dramaId,
      required String episodeId,
      required String title,
      required String episodeTitle,
      Value<String?> coverURL,
      Value<double> position,
      Value<double> duration,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$HistoriesTableUpdateCompanionBuilder =
    HistoriesCompanion Function({
      Value<String> key,
      Value<String> dramaId,
      Value<String> episodeId,
      Value<String> title,
      Value<String> episodeTitle,
      Value<String?> coverURL,
      Value<double> position,
      Value<double> duration,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$HistoriesTableFilterComposer
    extends Composer<_$AppDatabase, $HistoriesTable> {
  $$HistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dramaId => $composableBuilder(
    column: $table.dramaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverURL => $composableBuilder(
    column: $table.coverURL,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $HistoriesTable> {
  $$HistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dramaId => $composableBuilder(
    column: $table.dramaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverURL => $composableBuilder(
    column: $table.coverURL,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $HistoriesTable> {
  $$HistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get dramaId =>
      $composableBuilder(column: $table.dramaId, builder: (column) => column);

  GeneratedColumn<String> get episodeId =>
      $composableBuilder(column: $table.episodeId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get episodeTitle => $composableBuilder(
    column: $table.episodeTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverURL =>
      $composableBuilder(column: $table.coverURL, builder: (column) => column);

  GeneratedColumn<double> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<double> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$HistoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HistoriesTable,
          History,
          $$HistoriesTableFilterComposer,
          $$HistoriesTableOrderingComposer,
          $$HistoriesTableAnnotationComposer,
          $$HistoriesTableCreateCompanionBuilder,
          $$HistoriesTableUpdateCompanionBuilder,
          (History, BaseReferences<_$AppDatabase, $HistoriesTable, History>),
          History,
          PrefetchHooks Function()
        > {
  $$HistoriesTableTableManager(_$AppDatabase db, $HistoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> dramaId = const Value.absent(),
                Value<String> episodeId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> episodeTitle = const Value.absent(),
                Value<String?> coverURL = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<double> duration = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoriesCompanion(
                key: key,
                dramaId: dramaId,
                episodeId: episodeId,
                title: title,
                episodeTitle: episodeTitle,
                coverURL: coverURL,
                position: position,
                duration: duration,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String dramaId,
                required String episodeId,
                required String title,
                required String episodeTitle,
                Value<String?> coverURL = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<double> duration = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoriesCompanion.insert(
                key: key,
                dramaId: dramaId,
                episodeId: episodeId,
                title: title,
                episodeTitle: episodeTitle,
                coverURL: coverURL,
                position: position,
                duration: duration,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HistoriesTable,
      History,
      $$HistoriesTableFilterComposer,
      $$HistoriesTableOrderingComposer,
      $$HistoriesTableAnnotationComposer,
      $$HistoriesTableCreateCompanionBuilder,
      $$HistoriesTableUpdateCompanionBuilder,
      (History, BaseReferences<_$AppDatabase, $HistoriesTable, History>),
      History,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FavoritesTableTableManager get favorites =>
      $$FavoritesTableTableManager(_db, _db.favorites);
  $$HistoriesTableTableManager get histories =>
      $$HistoriesTableTableManager(_db, _db.histories);
}
