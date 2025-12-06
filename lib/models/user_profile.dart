import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  String? id;
  String name;
  double totalBalance;
  double monthlyIncome;
  DateTime createdAt;

  UserProfile({
    this.id,
    required this.name,
    required this.totalBalance,
    required this.monthlyIncome,
    required this.createdAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      id: doc.id,
      name: data['name'] ?? '',
      totalBalance: (data['totalBalance'] ?? 0.0).toDouble(),
      monthlyIncome: (data['monthlyIncome'] ?? 0.0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      id: data['id'],
      name: data['name'] ?? '',
      totalBalance: (data['totalBalance'] ?? 0.0).toDouble(),
      monthlyIncome: (data['monthlyIncome'] ?? 0.0).toDouble(),
      createdAt: data['createdAt'] is String
          ? DateTime.parse(data['createdAt'])
          : (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'totalBalance': totalBalance,
      'monthlyIncome': monthlyIncome,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'totalBalance': totalBalance,
      'monthlyIncome': monthlyIncome,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
