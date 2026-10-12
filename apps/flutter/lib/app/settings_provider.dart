import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观模式。
enum Appearance { system, light, dark }

/// 缓冲策略（对齐 macOS 版 preferredForwardBufferDuration 档位）。
enum BufferStrategy { low, medium, high }

/// 全局设置状态（对齐 macOS 版设置中心持久化项）。
class AppSettings {
  final Appearance appearance;
  final double cardScale; // 界面缩放 0.8 ~ 1.4
  final double defaultRate; // 默认倍速
  final bool autoPlayNext; // 自动连播
  final int introSkipSeconds; // 跳片头秒数（0 = 关闭）
  final BufferStrategy bufferStrategy;
  final int cacheHours; // 内容缓存时长（小时）
  final bool tvMode; // 电视模式（TV 独立版：Cinema Dark + 焦点引擎）

  const AppSettings({
    this.appearance = Appearance.system,
    this.cardScale = 1.0,
    this.defaultRate = 1.0,
    this.autoPlayNext = true,
    this.introSkipSeconds = 0,
    this.bufferStrategy = BufferStrategy.medium,
    this.cacheHours = 6,
    this.tvMode = false,
  });

  ThemeMode get themeMode => switch (appearance) {
        Appearance.system => ThemeMode.system,
        Appearance.light => ThemeMode.light,
        Appearance.dark => ThemeMode.dark,
      };

  AppSettings copyWith({
    Appearance? appearance,
    double? cardScale,
    double? defaultRate,
    bool? autoPlayNext,
    int? introSkipSeconds,
    BufferStrategy? bufferStrategy,
    int? cacheHours,
    bool? tvMode,
  }) =>
      AppSettings(
        appearance: appearance ?? this.appearance,
        cardScale: cardScale ?? this.cardScale,
        defaultRate: defaultRate ?? this.defaultRate,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        introSkipSeconds: introSkipSeconds ?? this.introSkipSeconds,
        bufferStrategy: bufferStrategy ?? this.bufferStrategy,
        cacheHours: cacheHours ?? this.cacheHours,
        tvMode: tvMode ?? this.tvMode,
      );
}

/// 设置持久化 + 状态通知（SharedPreferences 写穿）。
class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _prefs;

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      appearance: Appearance.values.asNameMap()[_prefs.getString('appearance')] ??
          Appearance.system,
      cardScale: _prefs.getDouble('cardScale') ?? 1.0,
      defaultRate: _prefs.getDouble('defaultRate') ?? 1.0,
      autoPlayNext: _prefs.getBool('autoPlayNext') ?? true,
      introSkipSeconds: _prefs.getInt('introSkipSeconds') ?? 0,
      bufferStrategy:
          BufferStrategy.values.asNameMap()[_prefs.getString('bufferStrategy')] ??
              BufferStrategy.medium,
      cacheHours: _prefs.getInt('cacheHours') ?? 6,
      tvMode: _prefs.getBool('tvMode') ?? false,
    );
  }

  Future<void> _write(String key, Object value) async {
    switch (value) {
      case final bool v:
        await _prefs.setBool(key, v);
      case final int v:
        await _prefs.setInt(key, v);
      case final double v:
        await _prefs.setDouble(key, v);
      case final String v:
        await _prefs.setString(key, v);
    }
  }

  void setAppearance(Appearance v) {
    state = state.copyWith(appearance: v);
    _write('appearance', v.name);
  }

  void setCardScale(double v) {
    state = state.copyWith(cardScale: v);
    _write('cardScale', v);
  }

  void setDefaultRate(double v) {
    state = state.copyWith(defaultRate: v);
    _write('defaultRate', v);
  }

  void setAutoPlayNext(bool v) {
    state = state.copyWith(autoPlayNext: v);
    _write('autoPlayNext', v);
  }

  void setIntroSkipSeconds(int v) {
    state = state.copyWith(introSkipSeconds: v);
    _write('introSkipSeconds', v);
  }

  void setBufferStrategy(BufferStrategy v) {
    state = state.copyWith(bufferStrategy: v);
    _write('bufferStrategy', v.name);
  }

  void setCacheHours(int v) {
    state = state.copyWith(cacheHours: v);
    _write('cacheHours', v);
  }

  void setTVMode(bool v) {
    state = state.copyWith(tvMode: v);
    _write('tvMode', v);
  }
}

/// 全局设置 Provider。
final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
