import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:seaty/main.dart'; // import appStateProvider and global definitions
import 'package:seaty/screens/tracker_screen.dart'; // import BoldGradientHeroHeading
import 'package:seaty/widgets/seaty_bus_loading.dart';

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
    final auth = ref.read(authProvider);
    _nameController = TextEditingController(text: auth.userName);
    _nicController = TextEditingController(text: auth.userNic);
    _phoneController = TextEditingController(
      text: auth.userPhone.isEmpty
          ? (auth.role == 'passenger' ? '0771234567' : '0777654321')
          : auth.userPhone,
    );
    _gender = auth.userGender.isEmpty ? 'Male' : auth.userGender;
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

    final success = await ref.read(authProvider.notifier).updateProfile(
      _nameController.text.trim(),
      _nicController.text.trim().toUpperCase(),
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

  void _showMoreOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'More Options',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0A2540),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Delete Account',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                subtitle: const Text(
                  'Permanently remove your account and personal data',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showDeleteAccountDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Account?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A2540),
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to permanently delete your account? All your profile information, booking history, notifications, and preferences will be permanently erased.\n\nThis action cannot be undone.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF475569),
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _performAccountDeletion();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _performAccountDeletion() async {
    setState(() => _isSaving = true);

    final success = await ref.read(authProvider.notifier).deleteAccount();

    if (mounted) {
      setState(() => _isSaving = false);
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      SeatyNotifications.show(
        context,
        success
            ? 'Your account has been deleted.'
            : 'Account deletion initiated. Local session cleared.',
        isError: !success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final initialLetter = auth.userName.isNotEmpty
        ? auth.userName[0].toUpperCase()
        : 'U';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Bold Gradient Hero Heading ──
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
                child: BoldGradientHeroHeading(
                  title: 'Profile',
                  subtitle: 'Manage your personal details and preferences.',
                  trailingIcon: Icons.more_vert_rounded,
                  onTrailingTap: () => _showMoreOptionsMenu(context),
                ),
              ),
              const SizedBox(height: 12),

              // ── Avatar Card ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0A2540).withValues(alpha: 0.08),
                        blurRadius: 16,
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
                            colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
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
                              auth.userName,
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
                                  0xFF2563EB,
                                ).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                auth.role.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2563EB),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
              ),
              const SizedBox(height: 16),

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
                                colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
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
                      const SizedBox(height: 12),

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
                      const SizedBox(height: 12),

                      // Phone Field (Locked)
                      _buildFieldLabel('Phone Number'),
                      TextFormField(
                        controller: _phoneController,
                        readOnly: true,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        decoration: _buildInputDecoration(
                          'Enter phone number',
                          Icons.phone_android_outlined,
                          suffixIcon: const Icon(
                            Icons.lock_rounded,
                            color: Color(0xFF94A3B8),
                            size: 18,
                          ),
                          readOnly: true,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Phone number is required'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // NIC Field
                      _buildFieldLabel('NIC Number'),
                      TextFormField(
                        controller: _nicController,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          color: Color(0xFF0A2540),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        decoration: _buildInputDecoration(
                          'e.g. 199912345678 or 991234567V',
                          Icons.badge_outlined,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'NIC number is required';
                          }
                          final trimmed = val.trim();
                          final nicRegex = RegExp(r'^([0-9]{9}[vVxX]|[0-9]{12})$');
                          if (!nicRegex.hasMatch(trimmed)) {
                            return 'Invalid NIC format (12 digits or 9 digits ending with V/X)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Gender Field
                      _buildFieldLabel('Gender'),
                      DropdownButtonFormField<String>(
                        initialValue: _gender,
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
                      const SizedBox(height: 20),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(
                              0xFF2563EB,
                            ).withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? const Center(
                                  child: SeatyBusLoadingIndicator.small(
                                    busColor: Colors.white,
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
                      const SizedBox(height: 10),

                      // Sign Out Button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            // Awaited: logout is only durable once the
                            // SharedPreferences write has landed. Returning
                            // before that is what let a force-close undo it.
                            await ref.read(authProvider.notifier).logout();
                          },
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
                      const SizedBox(height: 12),

                      // Delete Account Action
                      Center(
                        child: TextButton.icon(
                          onPressed: _isSaving ? null : () => _showDeleteAccountDialog(context),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444),
                            size: 16,
                          ),
                          label: const Text(
                            'Delete Account',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ),

                      // Bottom clearance for floating nav bar
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

  InputDecoration _buildInputDecoration(
    String hint,
    IconData icon, {
    Widget? suffixIcon,
    bool readOnly = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: const Color(0xFF94A3B8).withValues(alpha: 0.6),
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: readOnly ? const Color(0xFFE2E8F0) : const Color(0xFF2563EB),
          width: readOnly ? 1.0 : 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}
