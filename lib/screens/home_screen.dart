import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/user_profile.dart';
import 'login_screen.dart';

// EXPENSE MODEL
class Expense {
  String? id;
  String name;
  double amount;
  DateTime date;
  String category;
  String? description;
  String userId;
  String type; // 'income' or 'expense'

  Expense({
    this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.category,
    this.description,
    required this.userId,
    required this.type,
  });

  factory Expense.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Expense(
      id: doc.id,
      name: data['name'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      category: data['category'] ?? 'Other',
      description: data['description'],
      userId: data['userId'] ?? '',
      type: data['type'] ?? 'expense',
    );
  }

  factory Expense.fromJson(Map<String, dynamic> data) {
    return Expense(
      id: data['id'],
      name: data['name'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      date: DateTime.parse(data['date']),
      category: data['category'] ?? 'Other',
      description: data['description'],
      userId: data['userId'] ?? '',
      type: data['type'] ?? 'expense',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'category': category,
      'description': description,
      'userId': userId,
      'type': type,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'date': date.toIso8601String(),
      'category': category,
      'description': description,
      'userId': userId,
      'type': type,
    };
  }
}

// EXPENSE CONTROLLER
class ExpenseController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _box = GetStorage();

  RxList<Expense> expenses = <Expense>[].obs;
  RxBool showFABMenu = false.obs;
  RxBool isOffline = false.obs;
  Rx<UserProfile?> userProfile = Rx<UserProfile?>(null);

  @override
  void onInit() {
    super.onInit();

    // Load local data first
    _loadLocalData();

    if (_auth.currentUser != null) {
      expenses.bindStream(expenseStream());
      fetchUserProfile();
    }
  }

  void _loadLocalData() {
    try {
      // Load Profile
      final profileData = _box.read<Map<String, dynamic>>('userProfile');
      if (profileData != null) {
        userProfile.value = UserProfile.fromMap(profileData);
      }

      // Load Expenses
      final expensesData = _box.read<List>('expenses');
      if (expensesData != null) {
        expenses.value = expensesData
            .map((e) => Expense.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('Error loading local data: $e');
    }
  }

  void _saveLocalData() {
    try {
      _box.write('expenses', expenses.map((e) => e.toJson()).toList());
      if (userProfile.value != null) {
        _box.write('userProfile', userProfile.value!.toJson());
      }
    } catch (e) {
      print('Error saving local data: $e');
    }
  }

  void fetchUserProfile() async {
    try {
      String uid = _auth.currentUser?.uid ?? 'mock_user_dev';
      var doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        userProfile.value = UserProfile.fromFirestore(doc);
        _saveLocalData(); // Sync to local
      }
    } catch (e) {
      print('Fetch Profile Error: $e');
    }
  }

  void saveLocalProfile(UserProfile profile) {
    userProfile.value = profile;
    isOffline.value = true;
    _saveLocalData();
  }

  Stream<List<Expense>> expenseStream() {
    String uid = _auth.currentUser?.uid ?? 'mock_user_dev';

    return _db
        .collection('users')
        .doc(uid)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .map((query) {
      isOffline.value = false;
      final list = query.docs.map((doc) => Expense.fromFirestore(doc)).toList();

      // Update local storage with fresh data from server
      // We need to be careful not to overwrite local optimistic updates if we want true offline sync,
      // but for this simple app, server-first with local fallback is safer.

      // Actually, bindStream will replace 'expenses' with this list.
      // So we should save this list to storage.
      // But we can't do it inside map easily without side effects.
      // We'll do it in the listener or just let the UI update and we save manually?
      // bindStream doesn't give a callback.

      // Better approach: Don't use bindStream if we want complex sync.
      // But bindStream is easy.
      // Let's just return the list, and use 'ever' to save.
      return list;
    }).handleError((error) {
      print('Firestore error: $error');
      if (error.toString().contains('permission-denied')) {
        isOffline.value = true;
        Get.snackbar(
          'Offline Mode',
          'Firebase permissions missing. Using local data.',
          backgroundColor: Colors.orange.withOpacity(0.8),
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
      // Return current local expenses instead of empty list so we don't wipe UI
      return expenses.toList();
    });
  }

  Future<void> addExpense(Expense expense) async {
    try {
      String uid = _auth.currentUser?.uid ?? 'mock_user_dev';

      // Optimistic update
      expenses.insert(0, expense);
      _saveLocalData();

      await _db
          .collection('users')
          .doc(uid)
          .collection('expenses')
          .add(expense.toMap());
    } catch (e) {
      print('Add Expense Error: $e');
      if (e.toString().contains('permission-denied')) {
        isOffline.value = true;
        Get.snackbar(
          'Saved Locally',
          'Data saved on device (Firebase permission denied)',
          backgroundColor: Colors.grey[800],
          colorText: Colors.white,
        );
      } else {
        // Keep it locally anyway for safety
        Get.snackbar('Saved Locally', 'Connection error, saved offline');
      }
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      String uid = _auth.currentUser?.uid ?? 'mock_user_dev';

      // Optimistic update
      expenses.removeWhere((e) => e.id == id);
      _saveLocalData();

      await _db
          .collection('users')
          .doc(uid)
          .collection('expenses')
          .doc(id)
          .delete();
    } catch (e) {
      print('Delete Error: $e');
      if (e.toString().contains('permission-denied')) {
        Get.snackbar('Deleted Locally', 'Transaction removed');
      }
    }
  }

  void logout() {
    _auth.signOut();
    _box.erase(); // Optional: clear data on logout
    Get.offAll(() => const LoginScreen());
  }

  double get totalExpense => expenses
      .where((e) => e.type == 'expense')
      .fold(0, (sum, item) => sum + item.amount);

  double get totalIncome => expenses
      .where((e) => e.type == 'income')
      .fold(0, (sum, item) => sum + item.amount);

  double get balance {
    double initialBalance = userProfile.value?.totalBalance ?? 0.0;
    // We assume the initial balance provided in onboarding is the starting point
    // So current balance = initial + income - expense
    // OR if the user meant "current available balance" in onboarding, we should treat it differently.
    // For now, let's assume it's the starting balance.
    return initialBalance + totalIncome - totalExpense;
  }

  List<Expense> get recentTransactions => expenses.take(10).toList();
}

// HOME SCREEN
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ExpenseController _controller = Get.put(ExpenseController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildDashboardCard(),
            _buildRecentTransactions(),
          ],
        ),
      ),
      floatingActionButton: Obx(() => _buildFloatingButtons()),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: Colors.white70,
            ),
          ),
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  color: Color(0xFF4A90E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _controller.logout(),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.settings,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard() {
    return Obx(() {
      final spent = _controller.totalExpense;
      final earned = _controller.totalIncome;
      final balance = _controller.balance;
      final total = spent + earned;
      final spentPercent = total > 0 ? spent / total : 0.0;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8B3A3A),
              Color(0xFF6B2828),
              Color(0xFF4A1818),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBalanceRow('Available balance', balance, Colors.white),
                  const SizedBox(height: 16),
                  Container(
                    height: 1,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  const SizedBox(height: 16),
                  _buildBalanceRow('Spent', spent, const Color(0xFFE8B4B4)),
                  const SizedBox(height: 16),
                  _buildBalanceRow('Earned', earned, const Color(0xFFE8B4B4)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            CustomPaint(
              size: const Size(120, 120),
              painter: DonutChartPainter(spentPercent),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildBalanceRow(String label, double amount, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.9),
                fontSize: 14,
              ),
            ),
            Text(
              '\$ ${amount.toStringAsFixed(0)}',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentTransactions() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent transactions',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.swap_vert,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              if (_controller.recentTransactions.isEmpty) {
                return const Center(
                  child: Text(
                    'No transactions yet',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }
              return ListView.builder(
                itemCount: _controller.recentTransactions.length,
                itemBuilder: (context, index) {
                  final expense = _controller.recentTransactions[index];
                  return _buildTransactionItem(expense);
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(Expense expense) {
    final isIncome = expense.type == 'income';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF6B2828),
            const Color(0xFF4A1818),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: Icon(
              _getCategoryIcon(expense.category),
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      expense.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isIncome ? Colors.green : Colors.red,
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  expense.description ?? expense.category,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'}\$${expense.amount.toStringAsFixed(0)}',
            style: TextStyle(
              color: isIncome ? Colors.green : Colors.red,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'travel':
        return Icons.flight;
      case 'food':
      case 'grocery':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'transport':
        return Icons.directions_car;
      case 'salary':
        return Icons.attach_money;
      default:
        return Icons.category;
    }
  }

  Widget _buildFloatingButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_controller.showFABMenu.value) ...[
          FloatingActionButton(
            heroTag: 'income',
            onPressed: () {
              _controller.showFABMenu.value = false;
              _showAddIncomeSheet();
            },
            backgroundColor: Colors.green,
            child: const Icon(Icons.arrow_upward),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'expense',
            onPressed: () {
              _controller.showFABMenu.value = false;
              _showAddExpenseSheet();
            },
            backgroundColor: Colors.red,
            child: const Icon(Icons.arrow_downward),
          ),
          const SizedBox(height: 16),
        ],
        FloatingActionButton(
          heroTag: 'main',
          onPressed: () {
            _controller.showFABMenu.value = !_controller.showFABMenu.value;
          },
          backgroundColor:
              _controller.showFABMenu.value ? Colors.black : Colors.red,
          child: Icon(
            _controller.showFABMenu.value ? Icons.close : Icons.add,
          ),
        ),
      ],
    );
  }

  void _showAddExpenseSheet() {
    _showTransactionSheet(isIncome: false);
  }

  void _showAddIncomeSheet() {
    _showTransactionSheet(isIncome: true);
  }

  void _showTransactionSheet({required bool isIncome}) {
    final amountController = TextEditingController();
    final nameController = TextEditingController();
    String selectedCategory = isIncome ? 'Salary' : 'Food';
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(isIncome ? 0xFF2C4A2C : 0xFF4A2C2C),
                Color(isIncome ? 0xFF1A2E1A : 0xFF2E1A1A),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    if (isIncome)
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4A90E2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet,
                          color: Colors.white,
                        ),
                      ),
                    const SizedBox(width: 16),
                    Text(
                      isIncome ? 'Add Income' : 'Add Expense',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                      color: Colors.white,
                      size: 28,
                    ),
                  ],
                ),
              ),

              // Amount Input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How much?',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(
                          color: Colors.white30,
                          fontSize: 48,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Form Fields
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildInputField(
                        label: isIncome ? 'Name' : 'Description',
                        controller: nameController,
                      ),
                      const SizedBox(height: 24),
                      _buildDropdownField(
                        label: 'Category',
                        value: selectedCategory,
                        items: isIncome
                            ? ['Salary', 'Bonus', 'Investment', 'Other']
                            : [
                                'Food',
                                'Travel',
                                'Shopping',
                                'Transport',
                                'Bills',
                                'Other'
                              ],
                        onChanged: (val) {
                          setModalState(() => selectedCategory = val!);
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildDateField(
                        label: 'Transaction Date',
                        date: selectedDate,
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setModalState(() => selectedDate = date);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Submit Button
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: GestureDetector(
                    onTap: () async {
                      if (amountController.text.isEmpty) {
                        Get.snackbar('Error', 'Please enter amount');
                        return;
                      }

                      final expense = Expense(
                        name: nameController.text.isEmpty
                            ? selectedCategory
                            : nameController.text,
                        amount: double.parse(amountController.text),
                        date: selectedDate,
                        category: selectedCategory,
                        description: nameController.text,
                        userId: FirebaseAuth.instance.currentUser?.uid ??
                            'mock_user_dev',
                        type: isIncome ? 'income' : 'expense',
                      );

                      await _controller.addExpense(expense);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Color(0xFF8B3A3A),
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: label,
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.5),
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
          ),
          DropdownButton<String>(
            value: value,
            dropdownColor: const Color(0xFF2E1A1A),
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            items: items.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              DateFormat('MMM dd, yyyy').format(date),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// DONUT CHART PAINTER
class DonutChartPainter extends CustomPainter {
  final double spentPercent;

  DonutChartPainter(this.spentPercent);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 20.0;

    // Background circle (earned - light pink)
    final bgPaint = Paint()
      ..color = const Color(0xFFE8B4B4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    // Foreground arc (spent - dark red)
    final fgPaint = Paint()
      ..color = const Color(0xFF6B2828)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * spentPercent;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -math.pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
