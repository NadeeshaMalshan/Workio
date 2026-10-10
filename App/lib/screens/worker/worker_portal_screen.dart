import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/worker_model.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat_signalr_service.dart';
import '../../theme/worker_colors.dart';
import '../../widgets/m3_bottom_nav_bar.dart';
import '../../widgets/availability_confirm_dialog.dart';
import 'worker_chats_screen.dart';
import 'worker_dashboard_screen.dart';
import 'worker_jobs_screen.dart';
import 'worker_profile_screen.dart';
import '../community_screen.dart';
import '../workio_ai_screen.dart';

class WorkerPortalScreen extends StatefulWidget {
  const WorkerPortalScreen({super.key});

  @override
  State<WorkerPortalScreen> createState() => _WorkerPortalScreenState();
}

class _WorkerPortalScreenState extends State<WorkerPortalScreen> {
  int _currentIndex = 0;
  WorkerModel? _worker;
  bool _isLoading = true;
  bool _isOnline = true;
  bool _isTogglingStatus = false;

  @override
  void initState() {
    super.initState();
    _loadWorker();
  }

  Future<void> _loadWorker() async {
    final email = AuthService().currentUser?.email;
    if (email == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final worker = await ApiService().fetchMyWorkerProfile(email);
      if (mounted) {
        setState(() {
          _worker = worker;
          _isOnline = worker?.isAvailable ?? true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading worker in portal: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAvailability() async {
    if (_isTogglingStatus || _worker == null) return;

    final targetOnline = !_isOnline;
    final confirmed = await showAvailabilityConfirmDialog(
      context,
      targetOnline: targetOnline,
    );
    if (!confirmed) return;

    setState(() {
      _isTogglingStatus = true;
      _isOnline = targetOnline;
    });

    final success = await ApiService().updateWorkerAvailability(
      _worker!.id,
      isAvailable: targetOnline,
    );

    if (mounted) {
      setState(() => _isTogglingStatus = false);
      if (!success) {
        // Rollback on failure
        setState(() => _isOnline = !targetOnline);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update availability on server.',
              style: GoogleFonts.dmSans(),
            ),
            backgroundColor: WorkerColors.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetOnline
                  ? '✓ You are now Available for new jobs!'
                  : 'You are now Currently Offline.',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
            ),
            backgroundColor: targetOnline
                ? WorkerColors.success
                : WorkerColors.onSurface,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _exitWorkerMode() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: WorkerColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: WorkerColors.primary),
        ),
      );
    }

    final pages = [
      WorkerDashboardScreen(
        worker: _worker,
        isOnline: _isOnline,
        onToggleOnline: _toggleAvailability,
        onNavigateTab: (index) => setState(() => _currentIndex = index),
      ),
      const WorkerJobsScreen(),
      const CommunityScreen(isWorkerMode: true),
      const WorkerChatsScreen(),
      WorkerProfileScreen(
        worker: _worker,
        isOnline: _isOnline,
        onAvailabilityChanged: (val) => setState(() => _isOnline = val),
        onWorkerUpdated: _loadWorker,
        onExitWorkerMode: _exitWorkerMode,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _currentIndex == 2
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 16,
              title: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/images/icon.png',
                      width: 22,
                      height: 22,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.bolt_rounded,
                        size: 20,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Workio',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF334155).withValues(alpha: 0.6),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 5),
                        Text(
                          'WORKER',
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      body: IndexedStack(index: _currentIndex, children: pages),
      floatingActionButton: (AuthService().currentUser != null && _currentIndex == 0)
          ? _buildAiFloatingButton(context)
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: ChatSignalRService().unreadChatCountNotifier,
        builder: (context, unreadChats, _) {
          return M3BottomNavigationBar(
            selectedIndex: _currentIndex,
            onItemSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: [
              const M3BottomNavItem(
                label: 'Dashboard',
                icon: Icons.space_dashboard_outlined,
                selectedIcon: Icons.space_dashboard_rounded,
              ),
              const M3BottomNavItem(
                label: 'My Jobs',
                icon: Icons.work_outline_rounded,
                selectedIcon: Icons.work_rounded,
              ),
              const M3BottomNavItem(
                label: 'Community',
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups_rounded,
              ),
              M3BottomNavItem(
                label: 'Chats',
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                hasBadge: unreadChats > 0,
                badgeColor: const Color(0xFFEF4444),
              ),
              const M3BottomNavItem(
                label: 'Profile',
                icon: Icons.manage_accounts_outlined,
                selectedIcon: Icons.manage_accounts_rounded,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAiFloatingButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, right: 2.0),
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkioAiScreen()),
            );
          },
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/images/Workio_Logo_Black_WithOut_Text.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stackTrace) => const Center(
                      child: Text(
                        'W',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Workio AI',
                  style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
