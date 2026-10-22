import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/news.dart';

/// Game news, from the `game-news` Supabase Edge Function: the gaming outlets'
/// latest articles, and Steam's news for a game. Only reachable by signed-in
/// members; nothing here is cached (the function caches, and the store holds what
/// is on screen).
class NewsApiService {
  /// Articles per request. The function allows up to 50.
  static const int pageSize = 20;

  /// Most Steam apps one request may name.
  static const int maxAppIds = 10;

  /// The news in the app's language: Russian outlets for Russian, English
  /// outlets for anything else.
  static String get _language => L10n.languageCode == 'ru' ? 'ru' : 'en';

  Future<Object?> _invoke(Map<String, Object> body) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'game-news',
        body: body,
      );
      final raw = res.data;
      return raw is String ? json.decode(raw) : raw;
    } catch (e) {
      debugPrint('game-news request failed: $e');
      return null;
    }
  }

  /// One page of the latest articles, newest first, from every outlet or just
  /// [sourceId]; null when the request failed. [offset] counts the articles of
  /// the pages before.
  Future<NewsPage?> latest({
    String? sourceId,
    int offset = 0,
    int limit = pageSize,
  }) async {
    final response = await _invoke({
      'mode': 'feed',
      'lang': _language,
      'source': ?sourceId,
      'limit': limit,
      'offset': offset,
    });
    return NewsPage.fromResponse(response, limit: limit);
  }

  /// Steam's news for the apps [appIds] (at most [maxAppIds]), newest first;
  /// null when the request failed.
  Future<List<NewsArticle>?> steamNews(
    List<int> appIds, {
    int limit = 30,
  }) async {
    if (appIds.isEmpty) return const [];
    final response = await _invoke({
      'mode': 'steam',
      'app_ids': appIds.take(maxAppIds).toList(),
      'limit': limit,
    });
    return NewsPage.fromResponse(response, limit: limit)?.articles;
  }
}
