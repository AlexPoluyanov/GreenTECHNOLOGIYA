import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditProfileContent extends StatefulWidget {
  const EditProfileContent({Key? key, required String initialName, required String initialEmail, required String initialPhone, required Future<Null> Function(dynamic name, dynamic email, dynamic phone) onSave}) : super(key: key);

  @override
  _EditProfileContentState createState() => _EditProfileContentState();
}

class _EditProfileContentState extends State<EditProfileContent> {
  late String name;
  late String phone;
  late String email;
  late String acType;
  late String dcType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      name = prefs.getString('userName') ?? 'Имя';
      phone = prefs.getString('userPhone') ?? '+7 999 999 99 99';
      email = prefs.getString('userEmail') ?? 'email@example.com';
      acType = prefs.getString('acType') ?? 'Type 2';
      dcType = prefs.getString('dcType') ?? 'GB/T DC';
      _isLoading = false;
    });
  }

  Future<void> _saveUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    await prefs.setString('userPhone', phone);
    await prefs.setString('userEmail', email);
    await prefs.setString('acType', acType);
    await prefs.setString('dcType', dcType);

    // Показываем уведомление об успешном сохранении
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Данные успешно сохранены'),
        backgroundColor: Colors.green,
      ),
    );

    // Закрываем экран редактирования
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEditableProfileInfoItem(
                  title: 'Имя',
                  value: name,
                  onChanged: (value) => setState(() => name = value),
                ),
                const SizedBox(height: 16),
                _buildEditableProfileInfoItem(
                  title: 'Телефон',
                  value: phone,
                  isPhone: true,
                  onChanged: (value) => setState(() => phone = value),
                ),
                const SizedBox(height: 16),
                _buildEditableProfileInfoItem(
                  title: 'E-mail',
                  value: email,
                  onChanged: (value) => setState(() => email = value),
                ),
                const SizedBox(height: 16),
                _buildChargerTypeItem(
                  title: 'Переменный ток',
                  currentValue: acType,
                  onChanged: (value) => setState(() => acType = value),
                ),
                const Divider(height: 24),
                _buildChargerTypeItem(
                  title: 'Постоянный ток',
                  currentValue: dcType,
                  onChanged: (value) => setState(() => dcType = value),
                ),
                const Divider(height: 24),
                _buildClickableItem(
                  title: 'Сменить пароль',
                  onTap: () => _showChangePasswordDialog(context),
                ),
                const SizedBox(height: 30),
                Center(
                  child: ElevatedButton(
                    onPressed: _saveUserData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7CFF),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Сохранить изменения',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableProfileInfoItem({
    required String title,
    required String value,
    bool isPhone = false,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (isPhone)
              const Icon(Icons.phone, size: 16, color: Colors.grey),
            if (isPhone) const SizedBox(width: 4),
            Expanded(
              child: TextFormField(
                cursorColor: Color(0xFF0D7CFF) ,
                initialValue: value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                ),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChargerTypeItem({
    required String title,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    return _buildClickableItem(
      title: title,
      value: currentValue,
      onTap: () async {
        final newValue = await _showChargerTypeDialog(context, title);
        if (newValue != null) {
          onChanged(newValue);
        }
      },
    );
  }

  Widget _buildClickableItem({
    required String title,
    String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (value != null)
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<String?> _showChargerTypeDialog(
      BuildContext context, String title) async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Выберите $title',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDialogOption('Type 1', context),
                _buildDialogOption('Type 2', context),
                _buildDialogOption('GB/T', context),
                _buildDialogOption('GB/T DC', context),
                _buildDialogOption('CCS', context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogOption(String value, BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          value,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Сменить пароль',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Текущий пароль',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Новый пароль',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Повторите новый пароль',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена', style: TextStyle(color: Colors.red),),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D7CFF),
                      ),
                      child: const Text('Сохранить', style: TextStyle(color: Colors.white),),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}