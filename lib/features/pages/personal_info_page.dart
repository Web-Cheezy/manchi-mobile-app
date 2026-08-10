import 'package:flutter/material.dart';
import 'package:manchi_app/features/auth/auth_page.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  Map<String, dynamic>? _user;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;

  Future<void> _promptReauth() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your session expired. Please sign in again.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
    if (mounted) {
      await _loadProfile();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final user = await BackendService.getCurrentUser();
    _user = user;

    if (user != null && user['id'] != null) {
      try {
        final data = await BackendService.getProfile(user['id']);

        if (data != null && mounted) {
          final fullName = data['full_name'] ?? '';
          final phone = data['phone_number'] ?? '';
          final parts = fullName.split(' ');
          _firstNameController.text = parts.isNotEmpty ? parts.first : '';
          _lastNameController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
          _phoneController.text = _stripCountryCode(phone);
        }
      } catch (e) {
        if (BackendService.isSessionExpiredError(e)) {
          await _promptReauth();
        }
      }
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  String _formatPhoneNumber(String input) {
    var value = input.trim().replaceAll(' ', '');
    if (value.isEmpty) return value;
    if (value.startsWith('+234')) return value;
    if (value.startsWith('234')) {
      return '+$value';
    }
    if (value.startsWith('0') && value.length >= 11) {
      return '+234${value.substring(1)}';
    }
    if (!value.startsWith('+') && value.length == 10) {
      return '+234$value';
    }
    if (!value.startsWith('+234')) {
      return '+234$value';
    }
    return value;
  }

  String _stripCountryCode(String input) {
    var value = input.trim();
    if (value.startsWith('+234')) {
      return value.substring(4);
    }
    if (value.startsWith('234')) {
      return value.substring(3);
    }
    return value;
  }

  Future<void> _saveProfile() async {
    if (_user == null || _user!['id'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to update your profile.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    setState(() => _isSaving = true);

    try {
      final formattedPhone = _formatPhoneNumber(_phoneController.text);
      await BackendService.upsertProfile(
        id: _user!['id'],
        fullName: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim(),
        phoneNumber: formattedPhone,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (BackendService.isSessionExpiredError(e)) {
        await _promptReauth();
        return;
      }
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t save your details. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Information')),
      body: _isLoading 
          ? Center(
              // Force a square constraint so the spinner never renders as an oval.
              child: SizedBox.square(
                dimension: 48,
                child: const CircularProgressIndicator(),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(LucideIcons.user),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(LucideIcons.phone),
                      prefixText: '+234 ',
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
