import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/sri_lanka_locations.dart';
import '../../models/booking_model.dart';
import '../../models/worker_model.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'worker_performance_screen.dart';


class WorkerDashboardScreen extends StatefulWidget {
  final WorkerModel? worker;
  final bool isOnline;
  final VoidCallback? onToggleOnline;
  final Function(int tabIndex)? onNavigateTab;

  const WorkerDashboardScreen({
    super.key,
    this.worker,
    this.isOnline = false,
    this.onToggleOnline,
    this.onNavigateTab,
  });

  @override
  State<WorkerDashboardScreen> createState() => _WorkerDashboardScreenState();
}

class _WorkerDashboardScreenState extends State<WorkerDashboardScreen> {
  WorkerModel? _worker;
  Map<String, dynamic>? _performance;
  BookingModel? _recentReview;
  List<BookingModel> _allBookings = [];
  bool _isLoading = true;
  String _selectedOverviewPeriod = 'All time';
  String _currentLocation = 'Colombo';

  @override
  void initState() {
    super.initState();
    _worker = widget.worker;
    if (_worker?.primaryServiceArea != null && _worker!.primaryServiceArea!.trim().isNotEmpty) {
      _currentLocation = _worker!.primaryServiceArea!.trim();
    }
    _loadDashboardData();
  }

  @override
  void dispose() {
    super.dispose();
  }


  @override
  void didUpdateWidget(covariant WorkerDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.worker != oldWidget.worker) {
      _worker = widget.worker;
      if (_worker?.primaryServiceArea != null && _worker!.primaryServiceArea!.trim().isNotEmpty) {
        _currentLocation = _worker!.primaryServiceArea!.trim();
      }
    }
  }

  Future<void> _loadDashboardData() async {
    final email = AuthService().currentUser?.email;
    if (email == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final worker = _worker ?? await ApiService().fetchMyWorkerProfile(email);
      if (worker != null) {
        final perf = await ApiService().fetchWorkerPerformance(worker.id);
        final allBookings = await ApiService().fetchWorkerBookings(email);

        final reviewed = allBookings
            .where((b) =>
                (b.status.toLowerCase() == 'reviewed' || b.reviewRating != null) &&
                (b.reviewComment?.isNotEmpty ?? false))
            .toList();

        if (mounted) {
          setState(() {
            _worker = worker;
            _performance = perf;
            _allBookings = allBookings;
            if (reviewed.isNotEmpty) {
              _recentReview = reviewed.first;
            }
            if (worker.primaryServiceArea != null && worker.primaryServiceArea!.trim().isNotEmpty) {
              _currentLocation = worker.primaryServiceArea!.trim();
            }
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading worker dashboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _showChangeLocationSheet() {
    final areas = SriLankaLocations.districts;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Primary Service Area',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Saved in your worker table for job matching & alerts.',
                style: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: areas.length,
                  itemBuilder: (context, index) {
                    final area = areas[index];
                    final isSelected = area.toLowerCase() == _currentLocation.toLowerCase();
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: Icon(
                        Icons.near_me_outlined,
                        color: isSelected ? Colors.black : const Color(0xFF94A3B8),
                        size: 20,
                      ),
                      title: Text(
                        area,
                        style: GoogleFonts.dmSans(
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.black : const Color(0xFF475569),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: Colors.black, size: 20)
                          : null,
                      onTap: () async {
                        setState(() => _currentLocation = area);
                        Navigator.of(ctx).pop();
                        final workerId = (_worker ?? widget.worker)?.id;
                        if (workerId != null) {
                          final currentRadius = (_worker ?? widget.worker)?.coverageRadiusKm ?? 10.0;
                          await ApiService().updateWorkerServiceArea(
                            workerId,
                            serviceArea: area,
                            radiusKm: currentRadius,
                          );
                          _loadDashboardData();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPeriodFilterMenu() {
    final periods = ['All time', 'This month', 'This week', 'Today'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Metric Timeframe',
                style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              ...periods.map((p) {
                final isSelected = p == _selectedOverviewPeriod;
                return ListTile(
                  leading: Icon(
                    Icons.calendar_today_outlined,
                    color: isSelected ? Colors.black : const Color(0xFF94A3B8),
                    size: 18,
                  ),
                  title: Text(
                    p,
                    style: GoogleFonts.dmSans(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.black : const Color(0xFF334155),
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_rounded, color: Colors.black, size: 20)
                      : null,
                  onTap: () {
                    setState(() => _selectedOverviewPeriod = p);
                    Navigator.of(ctx).pop();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    final worker = _worker ?? widget.worker;
    final fullName = worker?.name ?? AuthService().currentUser?.name ?? 'Super';
    final firstName = (fullName.trim().split(' ').first).isNotEmpty ? fullName.trim().split(' ').first : 'Super';

    // Performance metrics
    num? rawOverall = (_performance?['overallRating'] ??
        _performance?['OverallRating'] ??
        worker?.overallRating) as num?;

    // If worker profile has no rating stored yet, compute directly from real reviewed bookings
    if ((rawOverall == null || rawOverall <= 0) && _allBookings.isNotEmpty) {
      final ratings = _allBookings
          .where((b) => b.reviewRating != null && b.reviewRating! > 0)
          .map((b) => b.reviewRating!)
          .toList();
      if (ratings.isNotEmpty) {
        rawOverall = ratings.reduce((a, b) => a + b) / ratings.length;
      }
    }

    final overallStr = (rawOverall != null && rawOverall > 0)
        ? rawOverall.toDouble().toStringAsFixed(1)
        : 'N/A';

    final rawCompletion =
        _performance?['completionRate'] ?? _performance?['CompletionRate'];
    final completionStr = (rawCompletion != null && rawCompletion.toString().isNotEmpty)
        ? rawCompletion.toString()
        : '0.0%';

    final rawCompletedJobs = _performance?['completedJobs'] ??
        _performance?['CompletedJobs'] ??
        worker?.completedJobs ??
        0;

    final rawAcceptance =
        _performance?['acceptanceRate'] ?? _performance?['AcceptanceRate'];
    final acceptanceStr = (rawAcceptance != null && rawAcceptance.toString().isNotEmpty)
        ? rawAcceptance.toString()
        : 'N/A';

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: Colors.black,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Time-based Greeting
            Text(
              _getTimeGreeting(),
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),

            // 2. Welcome back, \n Super
            Text(
              'Welcome back,\n$firstName',
              style: GoogleFonts.dmSans(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                height: 1.15,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 16),

            // 3. Location Pill
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: _showChangeLocationSheet,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.near_me_outlined,
                        size: 16,
                        color: Colors.black,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _currentLocation,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 4. Online Availability Black Card
            GestureDetector(
              onTap: () => widget.onToggleOnline?.call(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: widget.isOnline
                                    ? const Color(0xFF00C853)
                                    : const Color(0xFF71717A),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.isOnline ? "You're online" : "You're offline",
                              style: GoogleFonts.dmSans(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.isOnline
                              ? 'Residents can book your services'
                              : 'Toggle on when ready to work',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    Transform.scale(
                      scale: 0.95,
                      child: Switch(
                        value: widget.isOnline,
                        onChanged: (_) => widget.onToggleOnline?.call(),
                        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return const Color(0xFF00C853);
                          }
                          return const Color(0xFF27272A);
                        }),
                        thumbColor: WidgetStateProperty.all(Colors.white),
                        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                        thumbIcon: WidgetStateProperty.all(const Icon(null)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // 5. Overview Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overview',
                  style: GoogleFonts.dmSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                InkWell(
                  onTap: _showPeriodFilterMenu,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedOverviewPeriod,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 6. 2x2 Grid of Metric Cards (Clone)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.05,
              children: [
                _buildOverviewMetricCard(
                  icon: Icons.star_outline_rounded,
                  value: overallStr,
                  label: 'Overall rating',
                ),
                _buildOverviewMetricCard(
                  icon: Icons.check_circle_outline_rounded,
                  value: (completionStr == '0.0%' || completionStr.isEmpty) ? 'N/A' : completionStr,
                  label: 'Completion rate',
                ),
                _buildOverviewMetricCard(
                  icon: Icons.work_outline_rounded,
                  value: '$rawCompletedJobs',
                  label: 'Completed jobs',
                ),
                _buildOverviewMetricCard(
                  icon: Icons.thumb_up_alt_outlined,
                  value: (acceptanceStr.isEmpty || acceptanceStr == '0.0%') ? 'N/A' : acceptanceStr,
                  label: 'Acceptance rate',
                ),
              ],
            ),

            // Optional: Recent Review if present
            if (_recentReview != null) ...[
              const SizedBox(height: 24),
              Text(
                'Recent Client Review',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _recentReview!.residentName,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        Row(
                          children: List.generate(5, (starIdx) {
                            final rating = _recentReview!.reviewRating ?? 5.0;
                            return Icon(
                              starIdx < rating.round()
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: Colors.black,
                              size: 16,
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"${_recentReview!.reviewComment}"',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Bottom Performance & Reviews Navigation Button
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WorkerPerformanceScreen(worker: widget.worker),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.star_outline_rounded,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Performance',
                            style: GoogleFonts.dmSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Ratings, stats and client reviews',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF262626),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewMetricCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, color: Colors.black, size: 18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  height: 1.1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
