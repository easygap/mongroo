class User {
  const User({
    required this.id,
    required this.email,
    required this.nickname,
    required this.timezone,
    required this.seedBalance,
    required this.streakDays,
  });

  final int id;
  final String email;
  final String nickname;
  final String timezone;
  final int seedBalance;
  final int streakDays;

  User copyWith({int? seedBalance, int? streakDays}) => User(
        id: id,
        email: email,
        nickname: nickname,
        timezone: timezone,
        seedBalance: seedBalance ?? this.seedBalance,
        streakDays: streakDays ?? this.streakDays,
      );

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        email: (json['email'] as String?) ?? '',
        nickname: (json['nickname'] as String?) ?? '',
        timezone: (json['timezone'] as String?) ?? 'Asia/Seoul',
        seedBalance: (json['seed_balance'] as int?) ?? 0,
        streakDays: (json['streak_days'] as int?) ?? 0,
      );
}
