import 'package:chargers/profile_screen/balance.dart';
import 'package:chargers/profile_screen/balance_history.dart';
import 'package:chargers/profile_screen/edit_profile.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../auth_screen/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? initialScreen;

  const ProfileScreen({super.key, this.initialScreen});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late String _currentScreen;
  String? userName;
  String? userEmail;
  String? userPhone;
  String? userPhotoUrl;
  double userBalance = 0.0;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _currentScreen = widget.initialScreen ?? 'profile';
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('No auth token');
      }

      // Проверяем, есть ли данные в SharedPreferences
      final cachedName = prefs.getString('userName');
      final cachedEmail = prefs.getString('userEmail');
      final cachedPhone = prefs.getString('userPhone');
      final cachedPhoto = prefs.getString('userPhotoUrl');
      final cachedBalance = prefs.getDouble('userBalance');

      if (cachedName != null && cachedEmail != null) {
        // Используем кэшированные данные
        setState(() {
          userName = cachedName;
          userEmail = cachedEmail;
          userPhone = cachedPhone;
          userPhotoUrl = cachedPhoto;
          userBalance = cachedBalance ?? 0.0;
          _isLoading = false;
        });
      }

      // В любом случае делаем запрос к серверу для актуальных данных
      final response = await http.get(
        Uri.parse('http://192.168.31.215:5000/api/auth/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await prefs.setString('userName', data['name'] ?? 'Имя пользователя');
        await prefs.setString('userEmail', data['email'] ?? 'example@mail.com');
        await prefs.setString('userPhone', data['phone'] ?? '+79099999999');
        await prefs.setString('userPhotoUrl', data['photo_url'] ??
            'https://img.freepik.com/free-vector/blue-circle-with-white-user_78370-4707.jpg?semt=ais_hybrid&w=740');
        await prefs.setDouble('userBalance', double.tryParse(data['balance']) ?? 0.0);

        setState(() {
          userName = data['name'] ?? 'Имя пользователя';
          userEmail = data['email'] ?? 'example@mail.com';
          userPhone = data['phone'] ?? '+79099999999';
          userPhotoUrl = data['photo_url'] ??
              'https://img.freepik.com/free-vector/blue-circle-with-white-user_78370-4707.jpg?semt=ais_hybrid&w=740';
          userBalance = double.tryParse(data['balance']) ?? 0.0;
          _isLoading = false;
          _hasError = false;
        });
      } else {
        throw Exception('Failed to load user data');
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _retryLoadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    await _loadUserData();
  }

  Widget _getCurrentBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF0D7CFF),
            ),
            const SizedBox(height: 20),
            Text(
              'Загрузка данных...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 50),
            const SizedBox(height: 20),
            const Text(
              'Не удалось загрузить данные',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
              ),
              onPressed: _retryLoadData,
              child: const Text(
                'Повторить попытку',
                style: TextStyle(color: Color(0xFF0D7CFF)),
              ),
            ),
          ],
        ),
      );
    }

    switch (_currentScreen) {
      case 'edit':
        return EditProfileContent(
          initialName: userName ?? 'Имя пользователя',
          initialEmail: userEmail ?? 'example@mail.com',
          initialPhone: userPhone ?? '+79099999999',
          onSave: (name, email, phone) async {
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('token');

            try {
              final response = await http.put(
                Uri.parse('http://192.168.31.215:5000/api/user/profile'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: json.encode({
                  'name': name,
                  'email': email,
                  'phone': phone,
                }),
              );

              if (response.statusCode == 200) {
                await prefs.setString('userName', name);
                await prefs.setString('userEmail', email);
                await prefs.setString('userPhone', phone);

                setState(() {
                  userName = name;
                  userEmail = email;
                  userPhone = phone;
                  _currentScreen = 'profile';
                });
              } else {
                throw Exception('Failed to update profile');
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ошибка при обновлении профиля: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        );
      case 'balance':
        return BalanceContent(
          balance: userBalance,
          onHistoryPressed: () => setState(() => _currentScreen = 'history'),
          onBalanceUpdated: (newBalance) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('userBalance', newBalance);
            setState(() {
              userBalance = newBalance;
            });
          },
        );
      case 'history':
        return const BalanceHistoryContent();
      default:
        return _buildProfileContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D7CFF),
        centerTitle: true,
        title: Text(
          _currentScreen == 'profile'
              ? 'Аккаунт'
              : _currentScreen == 'edit'
              ? 'Редактировать профиль'
              : _currentScreen == 'balance'
              ? 'Пополнить баланс'
              : 'История транзакций',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: _currentScreen != 'profile'
            ? IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _currentScreen = 'profile'),
        )
            : null,
      ),
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 2.8,
            center: Alignment.topCenter,
            colors: [Color(0xFF0D7CFF), Color(0xFFFFFFFF)],
            stops: [0.4, 0.5],
          ),
        ),
        child: _getCurrentBody(),
      ),
    );
  }

  Widget _buildProfileContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x88272727),
                    blurRadius: 5,
                    spreadRadius: 1,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundImage: NetworkImage(userPhotoUrl ?? ''),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            userName ?? 'Имя пользователя',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey,
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildProfileItem(
                    icon: Icons.edit,
                    text: 'Редактировать профиль',
                    isFirst: true,
                    onTap: () => setState(() => _currentScreen = 'edit'),
                  ),
                  _buildProfileItem(
                    icon: Icons.account_balance_wallet,
                    text: 'Пополнить баланс',
                    onTap: () => setState(() => _currentScreen = 'balance'),
                  ),
                  _buildProfileItem(
                    icon: Icons.history,
                    text: 'История транзакций',
                    onTap: () => setState(() => _currentScreen = 'history'),
                  ),
                  _buildProfileItem(
                    icon: Icons.exit_to_app,
                    text: 'Выход',
                    isLast: true,
                    textColor: Colors.red,
                    iconColor: Colors.red,
                    onTap: () => _showLogoutDialog(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildProfileItem({
    required IconData icon,
    required String text,
    bool isFirst = false,
    bool isLast = false,
    Color textColor = Colors.black,
    Color iconColor = Colors.black,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        borderRadius: isFirst || isLast
            ? BorderRadius.vertical(
          top: isFirst ? const Radius.circular(20) : Radius.zero,
          bottom: isLast ? const Radius.circular(20) : Radius.zero,
        )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: isFirst || isLast
              ? BorderRadius.vertical(
            top: isFirst ? const Radius.circular(20) : Radius.zero,
            bottom: isLast ? const Radius.circular(20) : Radius.zero,
          )
              : null,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            child: Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 16),
                Text(text, style: TextStyle(fontSize: 18, color: textColor)),
                const Spacer(),
                if (!isLast) const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Center(
            child: Text(
              'Подтверждение выхода',
              textAlign: TextAlign.center,
            ),
          ),
          content: const Text(
            'Вы уверены, что хотите выйти из аккаунта?',
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Отмена',
                style: TextStyle(color: Color(0xFF0D7CFF)),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Выйти', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('token');
                await prefs.remove('userId');

                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                        (Route<dynamic> route) => false,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}