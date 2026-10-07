import 'package:checkpoint/models/social_user.dart';

abstract final class MockSocial {
  static const users = <SocialUser>[
    SocialUser(id: 'u1', name: 'Mara Lindqvist', handle: '@maraplays', gamesLogged: 312, followers: 4820, startsFollowed: true),
    SocialUser(id: 'u2', name: 'Jonas Weber', handle: '@jonasw', gamesLogged: 148, followers: 1260, startsFollowed: true),
    SocialUser(id: 'u3', name: 'Priya Nair', handle: '@priyaquests', gamesLogged: 421, followers: 9340),
    SocialUser(id: 'u4', name: 'Tomasz Kowal', handle: '@kowal.exe', gamesLogged: 96, followers: 310, startsFollowed: true),
    SocialUser(id: 'u5', name: 'Sofia Alvarez', handle: '@sofiaplaysslow', gamesLogged: 203, followers: 2175),
    SocialUser(id: 'u6', name: 'Kenji Mori', handle: '@kenjiloops', gamesLogged: 587, followers: 15200),
    SocialUser(id: 'u7', name: 'Hannah Cole', handle: '@cozyhannah', gamesLogged: 174, followers: 880),
    SocialUser(id: 'u8', name: 'Dmitri Volkov', handle: '@dmitri_gg', gamesLogged: 265, followers: 3640),
  ];
}
