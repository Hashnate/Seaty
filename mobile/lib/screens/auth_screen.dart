import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/screens/passenger_main_screen.dart';
import 'package:seaty/screens/owner/owner_main_screen.dart';
import 'package:seaty/screens/conductor/conductor_main_screen.dart';

// =====================================================================
// 3. AUTHENTICATION & WRAPPER SCREEN (Role Selection Screen)
// =====================================================================
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) {
      return const PhoneAuthScreen();
    }
    final userRole = auth.role.toLowerCase();
    if (userRole == 'owner') {
      return const OwnerMainScreen();
    } else if (userRole == 'conductor') {
      return const ConductorMainScreen();
    } else {
      return const PassengerMainScreen();
    }
  }
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Display app_logo.png instead of app_icon.png
              Image.asset(
                'assets/images/app_logo.png',
                height: 190,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.explore_rounded,
                  size: 80,
                  color: Color(0xFF0A2540),
                ),
              ),
              const SizedBox(height: 48),

              const Text(
                'Select Your Account Role',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A2540),
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'Choose how you want to proceed into Seaty',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 36),

              // Role selection cards
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Row(
                  children: [
                    // Passenger Card
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            SeatyPageRoute(
                              page: const PhoneAuthScreen(initialRole: 'passenger'),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6F9),
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Image.asset(
                                'assets/images/passenger_icon.png',
                                height: 85,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.directions_bus_rounded,
                                      size: 48,
                                      color: Color(0xFF0A2540),
                                    ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Passenger',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF0A2540),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Book & track luxury buses',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Owner Card
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            SeatyPageRoute(
                              page: const PhoneAuthScreen(initialRole: 'owner'),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6F9),
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Image.asset(
                                'assets/images/owner_icon.png',
                                height: 85,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.airport_shuttle_rounded,
                                      size: 48,
                                      color: Color(0xFF0A2540),
                                    ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Owner',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF0A2540),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Confirm & manage bookings',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}

// =====================================================================
// MOBILE & OTP AUTHENTICATION PROCESS
// =====================================================================
enum PhoneAuthState { enterPhone, register, verifyOtp }

class PhoneAuthScreen extends ConsumerStatefulWidget {
  final String? initialRole;
  const PhoneAuthScreen({super.key, this.initialRole});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  PhoneAuthState _authState = PhoneAuthState.enterPhone;
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();
  String _generatedOtp = '';
  bool _isNewUser = false;
  String _currentUserName = '';
  late String _dynamicRole;

  @override
  void initState() {
    super.initState();
    _dynamicRole = widget.initialRole ?? 'passenger';
  }

  void _generateAndSendOtp(BuildContext context, String name, String phone) {
    final random = DateTime.now().millisecondsSinceEpoch % 1000000;
    _generatedOtp = random.toString().padLeft(6, '0');
    _otpController.text = _generatedOtp; // Auto-complete verification code

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.sms_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'SMS: Seaty Verification Code',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Your OTP code is: $_generatedOtp'),
                    ],
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 10),
            backgroundColor: const Color(0xFF0A2540),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _authState == PhoneAuthState.enterPhone
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Color(0xFF0A2540),
                  size: 36,
                ),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  if (_authState == PhoneAuthState.register) {
                    setState(() => _authState = PhoneAuthState.enterPhone);
                  } else if (_authState == PhoneAuthState.verifyOtp) {
                    if (_isNewUser) {
                      setState(() => _authState = PhoneAuthState.register);
                    } else {
                      setState(() => _authState = PhoneAuthState.enterPhone);
                    }
                  }
                },
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildStateContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent() {
    switch (_authState) {
      case PhoneAuthState.enterPhone:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.phone_iphone_rounded,
                size: 64,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Welcome to Seaty',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter your mobile number to receive verification code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                hintText: 'e.g. 0771234567',
                prefixIcon: const Icon(
                  Icons.phone_iphone_rounded,
                  color: Color(0xFF0A2540),
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final phone = _phoneController.text.trim();
                if (phone.length < 9) {
                  SeatyNotifications.show(
                    context,
                    'Please enter a valid mobile number.',
                    isError: true,
                  );
                  return;
                }

                // Show loading SnackBar or call API
                SeatyNotifications.show(
                  context,
                  'Verifying number...',
                  duration: const Duration(milliseconds: 600),
                );

                final checkResult = await ref.read(authProvider.notifier).checkPhoneDB(
                  phone,
                  preferredRole: widget.initialRole,
                );
                final bool exists = checkResult['exists'] ?? false;
                final String name = checkResult['name'] ?? 'Guest User';
                _dynamicRole = checkResult['role'] ?? 'passenger';

                if (exists) {
                  _isNewUser = false;
                  _currentUserName = name;
                  _generateAndSendOtp(context, name, phone);
                  setState(() => _authState = PhoneAuthState.verifyOtp);
                } else {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _isNewUser = true;
                    _dynamicRole = widget.initialRole ?? 'passenger';
                    _nameController.clear();
                    _authState = PhoneAuthState.register;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            if (_dynamicRole == 'passenger') ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _isNewUser = true;
                        _nameController.clear();
                        _authState = PhoneAuthState.register;
                      });
                    },
                    child: const Text(
                      'Register Now',
                      style: TextStyle(
                        color: Color(0xFF0A2540),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case PhoneAuthState.register:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.person_add_rounded,
                size: 64,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Register Account',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create a new Seaty account using your mobile number',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              keyboardType: TextInputType.text,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Full Name',
                hintText: 'Enter your full name',
                prefixIcon: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF0A2540),
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                prefixIcon: const Icon(
                  Icons.phone_iphone_rounded,
                  color: Color(0xFF0A2540),
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final name = _nameController.text.trim();
                final phone = _phoneController.text.trim();
                if (name.isEmpty) {
                  SeatyNotifications.show(
                    context,
                    'Please enter your full name.',
                    isError: true,
                  );
                  return;
                }
                if (phone.length < 9) {
                  SeatyNotifications.show(
                    context,
                    'Please enter a valid mobile number.',
                    isError: true,
                  );
                  return;
                }

                FocusScope.of(context).unfocus();
                // Show loading SnackBar or call API
                SeatyNotifications.show(
                  context,
                  'Creating account...',
                  duration: const Duration(milliseconds: 600),
                );

                _dynamicRole = 'passenger';
                await ref.read(authProvider.notifier).registerPhoneDB(name, phone, 'passenger');
                _isNewUser = true;
                _currentUserName = name;
                _generateAndSendOtp(context, name, phone);
                setState(() => _authState = PhoneAuthState.verifyOtp);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Register & Verify',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Already have an account? ",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                TextButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _isNewUser = false;
                      _authState = PhoneAuthState.enterPhone;
                    });
                  },
                  child: const Text(
                    'Login',
                    style: TextStyle(
                      color: Color(0xFF0A2540),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case PhoneAuthState.verifyOtp:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.mark_email_read_rounded,
                size: 64,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Enter OTP Code',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the 6-digit code sent to ${_phoneController.text}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                color: Colors.black87,
                letterSpacing: 8,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: '••••••',
                hintStyle: const TextStyle(
                  letterSpacing: 8,
                  color: Colors.grey,
                ),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final otp = _otpController.text.trim();
                if (otp != _generatedOtp) {
                  SeatyNotifications.show(
                    context,
                    'Invalid verification code. Please check the SMS.',
                    isError: true,
                  );
                  return;
                }

                final phone = _phoneController.text.trim();
                final name = _currentUserName.isNotEmpty
                    ? _currentUserName
                    : 'User';
                ref.read(authProvider.notifier).login(name, _dynamicRole, phone);
                _otpController.clear();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Verify & Login',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                final phone = _phoneController.text.trim();
                final name = _currentUserName.isNotEmpty
                    ? _currentUserName
                    : 'User';
                _generateAndSendOtp(context, name, phone);
                SeatyNotifications.show(context, 'A new OTP has been sent.');
              },
              child: const Text(
                'Resend Code',
                style: TextStyle(
                  color: Color(0xFF0A2540),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
    }
  }
}
