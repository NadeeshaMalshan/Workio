import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/booking_model.dart';
import '../../models/worker_model.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class WorkerPerformanceScreen extends StatefulWidget {
  final WorkerModel? worker;

  const WorkerPerformanceScreen({super.key, this.worker});

  @override
  State<WorkerPerformanceScreen> createState() => _WorkerPerformanceScreenState();
}

class _WorkerPerformanceScreenState extends State<WorkerPerformanceScreen> {
  Map<String, dynamic>? _performance;
  List<BookingModel> _reviewedBookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPerformance();
  }

  Future<void> _fetchPerformance() async {
    final email = AuthService().currentUser?.email;
    if (email == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final worker = widget.worker ?? await ApiService().fetchMyWorkerProfile(email);
      if (worker != null) {
        final perf = await ApiService().fetchWorkerPerformance(worker.id);
        final allBookings = await ApiService().fetchWorkerBookings(email);
        final reviewed = allBookings
            .where((b) => b.status.toLowerCase() == 'reviewed' || (b.reviewRating != null && b.reviewRating! > 0))
            .toList();

        if (mounted) {
          setState(() {
            _performance = perf;
            _reviewedBookings = reviewed;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching worker performance: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    }

    final num? rawOverall = (_performance?['overallRating'] ?? _performance?['OverallRating'] ?? widget.worker?.overallRating) as num?;
    num? calculatedOverall = rawOverall;
    if ((calculatedOverall == null || calculatedOverall <= 0) && _reviewedBookings.isNotEmpty) {
      final ratings = _reviewedBookings
          .where((b) => b.reviewRating != null && b.reviewRating! > 0)
          .map((b) => b.reviewRating!)
          .toList();
      if (ratings.isNotEmpty) {
        calculatedOverall = ratings.reduce((a, b) => a + b) / ratings.length;
      }
    }
    final bool hasRating = calculatedOverall != null && calculatedOverall > 0;
    final double overallScore = hasRating ? calculatedOverall.toDouble() : 0.0;

    final rawQuality = (_performance?['qualityRating'] ?? _performance?['QualityRating'] ?? widget.worker?.qualityRating) as num?;
    final rawPunctuality = (_performance?['punctualityRating'] ?? _performance?['PunctualityRating'] ?? widget.worker?.punctualityRating) as num?;
    final rawCommunication = (_performance?['communicationRating'] ?? _performance?['CommunicationRating'] ?? widget.worker?.communicationRating) as num?;

    final rawCompletion = _performance?['completionRate'] ?? _performance?['CompletionRate'];
    final completionRate = (rawCompletion != null && rawCompletion.toString().isNotEmpty) ? rawCompletion.toString() : '100%';

    final rawAcceptance = _performance?['acceptanceRate'] ?? _performance?['AcceptanceRate'];
    final acceptanceRate = (rawAcceptance != null && rawAcceptance.toString().isNotEmpty) ? rawAcceptance.toString() : '100%';

    final rawCancellation = _performance?['cancellationRate'] ?? _performance?['CancellationRate'];
    final cancellationRate = (rawCancellation != null && rawCancellation.toString().isNotEmpty) ? rawCancellation.toString() : '0%';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchPerformance,
          color: Colors.black,
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Circular Back Button
                InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Performance &\nreviews',
                  style: GoogleFonts.dmSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    height: 1.15,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'Track your ratings, punctuality, completion rates, and client reviews.',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // 1. Hero Scorecard Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Large Rating Score
                          Text(
                            hasRating ? overallScore.toStringAsFixed(1) : 'N/A',
                            style: GoogleFonts.dmSans(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              letterSpacing: -1.0,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: List.generate(5, (starIdx) {
                                    return Icon(
                                      hasRating && starIdx < overallScore.round()
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      color: const Color(0xFFF59E0B),
                                      size: 20,
                                    );
                                  }),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _reviewedBookings.isNotEmpty
                                      ? 'Based on ${_reviewedBookings.length} ${_reviewedBookings.length == 1 ? "client review" : "client reviews"}'
                                      : 'No client reviews yet',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_rounded, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'PRO',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 16),

                      // 3 KPI Pills Row
                      Row(
                        children: [
                          _buildQuickMetric(
                            label: 'Completion',
                            value: completionRate,
                            icon: Icons.task_alt_rounded,
                          ),
                          Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                          _buildQuickMetric(
                            label: 'Acceptance',
                            value: acceptanceRate,
                            icon: Icons.handshake_outlined,
                          ),
                          Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                          _buildQuickMetric(
                            label: 'Cancellation',
                            value: cancellationRate,
                            icon: Icons.cancel_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 2. Rating Breakdown Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Rating breakdown',
                      style: GoogleFonts.dmSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '3 categories',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Breakdown Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildRatingRow(
                        icon: Icons.handyman_outlined,
                        label: 'Work quality & craftsmanship',
                        rating: rawQuality,
                      ),
                      const SizedBox(height: 18),
                      _buildRatingRow(
                        icon: Icons.schedule_rounded,
                        label: 'Punctuality & arrival time',
                        rating: rawPunctuality,
                      ),
                      const SizedBox(height: 18),
                      _buildRatingRow(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Communication & professionalism',
                        rating: rawCommunication,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 3. Resident Reviews Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Resident reviews (${_reviewedBookings.length})',
                      style: GoogleFonts.dmSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (_reviewedBookings.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 26,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No reviews yet',
                          style: GoogleFonts.dmSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'When residents complete and rate your jobs, their comments and star ratings will appear here.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _reviewedBookings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final b = _reviewedBookings[index];
                      final reviewDateStr = b.reviewedAt != null
                          ? '${b.reviewedAt!.day}/${b.reviewedAt!.month}/${b.reviewedAt!.year}'
                          : (b.scheduledDate != null
                              ? '${b.scheduledDate!.day}/${b.scheduledDate!.month}/${b.scheduledDate!.year}'
                              : 'Recently');
                      final rating = b.reviewRating ?? 5.0;

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  child: Text(
                                    b.residentName.isNotEmpty ? b.residentName[0].toUpperCase() : 'R',
                                    style: GoogleFonts.dmSans(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.residentName,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Text(
                                        reviewDateStr,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 11.5,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                      const SizedBox(width: 3),
                                      Text(
                                        rating.toStringAsFixed(1),
                                        style: GoogleFonts.dmSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (b.reviewComment != null && b.reviewComment!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                '"${b.reviewComment}"',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  fontStyle: FontStyle.italic,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                'Job: ${b.jobTitle}',
                                style: GoogleFonts.dmSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: Colors.black),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingRow({
    required IconData icon,
    required String label,
    required num? rating,
  }) {
    final hasRating = rating != null && rating > 0;
    final percent = hasRating ? (rating.toDouble() / 5.0).clamp(0.0, 1.0) : 0.0;
    final ratingStr = hasRating ? '${(rating.toDouble()).toStringAsFixed(1)} ★' : 'N/A';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(icon, size: 16, color: Colors.black),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            Text(
              ratingStr,
              style: GoogleFonts.dmSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: hasRating ? Colors.black : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 7,
            width: double.infinity,
            color: const Color(0xFFE2E8F0),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: percent > 0 ? percent : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
