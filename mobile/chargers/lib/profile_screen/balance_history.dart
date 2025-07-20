import 'package:flutter/material.dart';

class BalanceHistoryContent extends StatefulWidget {
  const BalanceHistoryContent();

  @override
  State<BalanceHistoryContent> createState() => _BalanceHistoryContentState();
}

class _BalanceHistoryContentState extends State<BalanceHistoryContent> {
  int _currentTab = 0; // 0 - Все, 1 - Пополнения, 2 - Платежи
  final List<Transaction> _transactions = [
    Transaction(DateTime(2023, 2, 1), 'Пополнение', 200000, true),
    Transaction(DateTime(2023, 2, 1), 'Пополнение', 200000, true),
    Transaction(DateTime(2023, 1, 28), 'Пополнение', 100000, true),
    Transaction(DateTime(2023, 1, 25), 'Пополнение', 100000, true),
    Transaction(DateTime(2023, 1, 23), 'Пополнение', 50000, true),
    Transaction(DateTime(2023, 1, 20), 'Станция Амурт', 15000, false),
    Transaction(DateTime(2023, 2, 1), 'Пополнение', 200000, true),
    Transaction(DateTime(2023, 1, 28), 'Пополнение', 100000, true),
    Transaction(DateTime(2023, 1, 25), 'Пополнение', 100000, true),
    Transaction(DateTime(2023, 1, 23), 'Пополнение', 50000, true),
    Transaction(DateTime(2023, 1, 20), 'Станция Амурт', 15000, false),

    Transaction(DateTime(2023, 1, 28), 'Пополнение', 100000, true),
    Transaction(DateTime(2023, 1, 25), 'Пополнение', 100000, true),
    Transaction(DateTime(2023, 1, 23), 'Пополнение', 50000, true),
    Transaction(DateTime(2023, 2, 20), 'Станция Амурт', 15000, false),
  ];

  @override
  Widget build(BuildContext context) {
    final filteredTransactions = _transactions.where((t) {
      if (_currentTab == 0) return true;
      if (_currentTab == 1) return t.isIncome;
      return !t.isIncome;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: Color(0xFF0D7CFF), // Установлен белый фон
      body: Column(
        children: [
          // Вкладки фильтрации
          Container(
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTabButton('Все', 0),
                _buildTabButton('Пополнения', 1),
                _buildTabButton('Платежи', 2),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Список транзакций или заглушка
          Expanded(
            child: filteredTransactions.isEmpty
                ? const Center(
              child: Text(
                'Нет операций',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(0),
              itemCount: filteredTransactions.length,
              itemBuilder: (context, index) {
                final transaction = filteredTransactions[index];
                final isFirstInGroup = index == 0 ||
                    !_isSameDay(
                        transaction.date,
                        filteredTransactions[index - 1].date
                    );

                return Column(
                  children: [
                    if (isFirstInGroup)
                      Container(

                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            _formatDateHeader(transaction.date),
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    _buildTransactionCard(transaction),
                  ],
                );
              },
            ),
          ),
        ],
      ),);
  }

  Widget _buildTabButton(String text, int tabIndex) {
    final isSelected = _currentTab == tabIndex;
    return TextButton(
      onPressed: () => setState(() => _currentTab = tabIndex),
      style: TextButton.styleFrom(
        foregroundColor: isSelected ? const Color(0xFF0D7CFF) : Colors.grey,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      elevation: 10, // Добавлено значение elevation для тени
      shadowColor: Colors.black, // Цвет тени
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), // Закругленные углы
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8), // Закругленные углы для InkWell
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsScreen(transaction: transaction),
            ),
          );
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(
            transaction.isIncome ? Icons.add_circle : Icons.remove_circle,
            color: transaction.isIncome ? Colors.green : Colors.red,
            size: 32,
          ),
          title: Text(
            transaction.description,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          trailing: Text(
            '${transaction.amount.toStringAsFixed(0)} ₽',
            style: TextStyle(
              color: transaction.isIncome ? Colors.green : Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateHeader(DateTime date) {
    final months = [
      'Января', 'Февраля', 'Марта', 'Апреля', 'Мая', 'Июня',
      'Июля', 'Августа', 'Сентября', 'Октября', 'Ноября', 'Декабря'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class Transaction {
  final DateTime date;
  final String description;
  final double amount;
  final bool isIncome;

  Transaction(this.date, this.description, this.amount, this.isIncome);
}

class TransactionDetailsScreen extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailsScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.isIncome;
    final Color primaryColor = isIncome ? Colors.green : Colors.red;
    final String transactionType = isIncome ? 'Пополнение' : 'Платеж';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryColor.withOpacity(0.7),
        title: Text(
          'Детали транзакции',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 2.8,
            colors: [
              primaryColor.withOpacity(0.7),
              Color(0xFFFFFFFF),
            ],
            stops: [0.4, 0.5],
          ),
        ),
        child: ClipPath(

          clipper: JaggedClipper(),
          child: Container(
            width: MediaQuery.of(context).size.width ,
            height:  MediaQuery.of(context).size.height,
            margin: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),

              border: Border.all(color: Colors.grey.shade300),
            ),
            child:  Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      'Транзакция',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: Text(
                      'ID: ${transaction.hashCode.toRadixString(16).padLeft(8, '0')}',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  Divider(height: 32, color: primaryColor),

                  Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        transactionType,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  _buildDetailRow('Имя:', 'Alex Popovich'),
                  _buildDetailRow('Дата:', '${transaction.date.day.toString().padLeft(2, '0')}.${transaction.date.month.toString().padLeft(2, '0')}.${transaction.date.year}'),
                  _buildDetailRow('Время:', '${transaction.date.hour.toString().padLeft(2, '0')}:${transaction.date.minute.toString().padLeft(2, '0')}'),
                  _buildDetailRow('Сумма:', '${transaction.amount.toStringAsFixed(2)} ₽'),
                  _buildDetailRow('Комиссия:', '0.00 ₽'),
                  _buildDetailRow('Налог:', '0.00 ₽'),
                  _buildDetailRow('Адрес:', 'Онлайн'),
                  _buildDetailRow('Изменения баланса:', '${transaction.amount.toStringAsFixed(2)} ₽'),

                  Divider(height: 32, color: primaryColor),

                  Center(
                    child: Text(
                      'Итоговая сумма:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${transaction.amount.toStringAsFixed(2)} ₽',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),


                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}


class JaggedClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final Path path = Path();
    const double radius = 8;
    const int count = 15; // Общее число сегментов (не выемок!)
    final double step = size.width / count;

    // Верхняя кривая
    path.moveTo(0, 0);
    for (int i = 0; i < count; i++) {
      final double x = step * (i + 1);
      if (i % 2 == 0) {
        path.arcToPoint(
          Offset(x, 0),
          radius: Radius.circular(radius),
          clockwise: false,
        );
      } else {
        path.lineTo(x, 0);
      }
    }

    // Правый край
    path.lineTo(size.width, size.height);

    // Нижняя кривая (в обратном порядке, зеркально)
    for (int i = count; i > 0; i--) {
      final double x = step * (i - 1);
      if ((i - 1) % 2 == 0) {
        path.arcToPoint(
          Offset(x, size.height),
          radius: Radius.circular(radius),
          clockwise: false,
        );
      } else {
        path.lineTo(x, size.height);
      }
    }

    // Левый край
    path.lineTo(0, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

