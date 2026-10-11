/// 数据模型（对齐 macOS 版 Swift HongguoCore）。
library;

/// 剧集（列表项）。
class Drama {
  final String id;
  final String title;
  final String? coverURL;
  final int? episodeCount;
  final String? remark;

  const Drama({
    required this.id,
    required this.title,
    this.coverURL,
    this.episodeCount,
    this.remark,
  });

  factory Drama.fromJson(Map<String, dynamic> json) => Drama(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        coverURL: json['coverURL'] as String?,
        episodeCount: json['episodeCount'] as int?,
        remark: json['remark'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (coverURL != null) 'coverURL': coverURL,
        if (episodeCount != null) 'episodeCount': episodeCount,
        if (remark != null) 'remark': remark,
      };
}

/// 分集。
class Episode {
  final String id;
  final int index;
  final String title;
  final String? playURL;

  const Episode({
    required this.id,
    required this.index,
    required this.title,
    this.playURL,
  });

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String? ?? '',
        index: json['index'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        playURL: json['playURL'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'index': index,
        'title': title,
        if (playURL != null) 'playURL': playURL,
      };
}

/// 剧集详情（含分集列表）。
class DramaDetail {
  final Drama drama;
  final List<Episode> episodes;

  const DramaDetail({required this.drama, required this.episodes});

  factory DramaDetail.fromJson(Map<String, dynamic> json) => DramaDetail(
        drama: Drama.fromJson(json['drama'] as Map<String, dynamic>? ?? {}),
        episodes: (json['episodes'] as List<dynamic>? ?? [])
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'drama': drama.toJson(),
        'episodes': episodes.map((e) => e.toJson()).toList(),
      };
}

/// TVBox 站点。
class TVBoxSite {
  final String key;
  final String name;
  final String api;

  const TVBoxSite({required this.key, required this.name, required this.api});

  factory TVBoxSite.fromJson(Map<String, dynamic> json) => TVBoxSite(
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        api: json['api'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'api': api};
}

/// 直播源。
class LiveSource {
  final String id;
  final String url;
  final String name;
  final bool enabled;
  final String? userAgent;

  const LiveSource({
    required this.id,
    required this.url,
    required this.name,
    required this.enabled,
    this.userAgent,
  });

  factory LiveSource.fromJson(Map<String, dynamic> json) => LiveSource(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        userAgent: json['userAgent'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'enabled': enabled,
        if (userAgent != null) 'userAgent': userAgent,
      };
}

/// 直播频道。
class LiveChannel {
  final String id;
  final String name;
  final String? logo;
  final String group;
  final String url;

  const LiveChannel({
    required this.id,
    required this.name,
    this.logo,
    required this.group,
    required this.url,
  });

  factory LiveChannel.fromJson(Map<String, dynamic> json) => LiveChannel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        logo: json['logo'] as String?,
        group: json['group'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (logo != null) 'logo': logo,
        'group': group,
        'url': url,
      };
}

/// NAS 资源库。
class NASLibrary {
  final String id;
  final String name;
  final String type; // webdav / mount
  final String baseURL;
  final String? username;
  final String? password;
  final bool enabled;

  const NASLibrary({
    required this.id,
    required this.name,
    required this.type,
    required this.baseURL,
    this.username,
    this.password,
    required this.enabled,
  });

  factory NASLibrary.fromJson(Map<String, dynamic> json) => NASLibrary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'webdav',
        baseURL: json['baseURL'] as String? ?? '',
        username: json['username'] as String?,
        password: json['password'] as String?,
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'baseURL': baseURL,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        'enabled': enabled,
      };
}
