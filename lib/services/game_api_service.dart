import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:checkpoint/models/game.dart';

class GameApiService {
  // PASTE YOUR TWITCH CREDENTIALS HERE:
  final String clientId = 'TWITCH_CLIENT_ID';
  final String clientSecret = 'TWITCH_CLIENT_SECRET';
  
  String? _accessToken;

  // 1. Authenticate with Twitch
  Future<void> _authenticate() async {
    if (_accessToken != null) return;
    final res = await http.post(Uri.parse(
        'https://id.twitch.tv/oauth2/token?client_id=$clientId&client_secret=$clientSecret&grant_type=client_credentials'));
    if (res.statusCode == 200) {
      _accessToken = json.decode(res.body)['access_token'];
    }
  }

  // 2. Pad IGDB integers into strict Supabase UUIDs
  String _igdbToUuid(int id) {
    final padded = id.toString().padLeft(12, '0');
    return '00000000-0000-4000-8000-$padded';
  }

  // 3. Fetch from IGDB
  Future<List<Game>> searchGames(String query) async {
    if (query.trim().isEmpty) return [];
    await _authenticate();
    
    final res = await http.post(
      Uri.parse('https://api.igdb.com/v4/games'),
      headers: {
        'Client-ID': clientId,
        'Authorization': 'Bearer $_accessToken',
      },
      body: 'search "$query"; fields name, cover.url, first_release_date, platforms.name, genres.name, summary, involved_companies.company.name; limit 20;',
    );

    if (res.statusCode != 200) return [];

    final List<dynamic> data = json.decode(res.body);
    return data.map((json) {
      String? coverUrl;
      if (json['cover'] != null && json['cover']['url'] != null) {
        coverUrl = 'https:${json['cover']['url']}'.replaceAll('t_thumb', 't_cover_big');
      }

      int year = 0;
      if (json['first_release_date'] != null) {
        year = DateTime.fromMillisecondsSinceEpoch(json['first_release_date'] * 1000).year;
      }

      final genres = (json['genres'] as List?)?.map((g) => g['name'].toString()).toList() ?? [];
      
      String company = 'Unknown Publisher';
      if (json['involved_companies'] != null && (json['involved_companies'] as List).isNotEmpty) {
        company = json['involved_companies'][0]['company']['name'] ?? company;
      }

      return Game(
        id: _igdbToUuid(json['id']),
        title: json['name'] ?? 'Unknown',
        developer: company,
        publisher: company,
        releaseYear: year,
        platforms: const [], 
        genres: genres,
        synopsis: json['summary'] ?? '',
        coverColors: const [Color(0xFF2C2C2C), Color(0xFF1A1A1A)],
        coverIcon: Icons.sports_esports_rounded,
        coverUrl: coverUrl,
      );
    }).toList();
  }
}