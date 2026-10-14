import 'package:flutter/material.dart';

import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';

void openGame(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameDetailScreen(gameId: id)));
