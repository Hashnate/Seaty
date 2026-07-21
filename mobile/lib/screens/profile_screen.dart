import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart'; // import appStateProvider and global definitions
import 'package:seaty/screens/tracker_screen.dart'; // import BoldGradientHeroHeading

// Profile Edit Screen
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _nicController;
  late TextEditingController _phoneController;
  String _gender = 'Male';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(appStateProvider);
    _nameController = TextEditingController(text: state.userName);
    _nicController = TextEditingController(text: state.userNic);
    _phoneController = TextEditingController(
      text: state.userPhone.isEmpty
          ? (state.role == 'passenger' ? '0771234567' : '0777654321')
          : state.userPhone,
    );
    _gender = state.userGender.isEmpty ? 'Male' : state.userGender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final state = ref.read(appStateProvider);
    final success = await state.updateProfile(
      _nameController.text.trim(),
      _nicController.text.trim(),
      _gender,
      _phoneController.text.trim(),
    );

    if (mounted) {
      setState(() => _isSaving = false);
      SeatyNotifications.show(
        context,
        success
            ? 'Profile updated successfully!'
            : 'Failed to update profile. Please try again.',
        isError: !success,
      );
      if (success) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final initialLetter = state.userName.isNotEmpty
        ? state.userName[0].toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bold Gradient Hero Heading ──
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
              child: BoldGradientHeroHeading(
                title: 'Profile',
                subtitle: 'Manage your personal details and preferences.',
              ),
            ),
            const SizedBox(height: 10),

            // ── Avatar Card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0A2540).withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar circle
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE65100), Color(0xFFFF8A65)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          initialLetter,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.userName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0A2540),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFE65100,
                              ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              state.role.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE65100),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Personal Details Form ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section Title
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 16,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE65100), Color(0xFFFF8A65)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Personal Details',
                          style: TextStyle(
                            color: Color(0xFF0A2540),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Name Field
                    _buildFieldLabel('Full Name'),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(
                        color: Color(0xFF0A2540),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      decoration: _buildInputDecoration(
                        'Enter your full name',
                        Icons.person_outline,
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 8),

                    // Phone Field
                    _buildFieldLabel('Phone Number'),
                    TextFormField(
                      controller: _phoneController,
                      style: const TextStyle(
                        color: Color(0xFF0A2540),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      decoration: _buildInputDecoration(
                        'Enter phone number',
                        Icons.phone_android_outlined,
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Phone number is required'
                          : null,
                    ),
                    const SizedBox(height: 8),

                    // NIC Field
                    _buildFieldLabel('NIC Number'),
                    TextFormField(
                      controller: _nicController,
                      style: const TextStyle(
                        color: Color(0xFF0A2540),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      decoration: _buildInputDecoration(
                        'e.g. 199912345678 or 991234567V',
                        Icons.badge_outlined,
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'NIC number is required'
                          : null,
                    ),
                    const SizedBox(height: 8),

                    // Gender Field
                    _buildFieldLabel('Gender'),
                    DropdownButtonFormField<String>(
                      value: _gender,
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      style: const TextStyle(
                        color: Color(0xFF0A2540),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _buildInputDecoration(
                        'Select Gender',
                        Icons.face_outlined,
                      ),
                      items: ['Male', 'Female']
                          .map(
                            (g) => DropdownMenuItem(
                              value: g,
                              child: Text(
                                g,
                                style: const TextStyle(
                                  color: Color(0xFF0A2540),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _gender = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFFE65100,
                          ).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Sign Out Button
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: () => ref.read(appStateProvider).logout(),
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        label: const Text(
                          'Sign Out',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Colors.redAccent,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.04,
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    // Bottom clearance for floating nav bar
                    const SizedBox(height: 75),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0, left: 4.0),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: const Color(0xFF94A3B8).withValues(alpha: 0.6),
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE65100), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}
