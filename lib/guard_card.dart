import 'package:flutter/material.dart';

import 'geofence_service.dart';

/// Guard info card driven by the SECURITY_GUARD table.
///   FULL_NAME    -> name
///   GUARD_NUMBER -> code under the name (e.g. 4123)
///   SHIFT_TIME   -> clock row (e.g. 07:00 - 15:00)
///   DUTY_STATUS  -> ON_DUTY (green) / OFF_DUTY (red) / REST (blue)
class GuardCard extends StatelessWidget {
  final SecurityGuard? guard;

  /// Current patrol round from PATROL_SCHEDULE (SCHEDULE_START / SCHEDULE_END).
  /// When null (no active round) the card falls back to SECURITY_GUARD.SHIFT_TIME.
  final ActiveSchedule? schedule;
  final bool isLoading;

  const GuardCard({
    super.key,
    required this.guard,
    this.schedule,
    this.isLoading = false,
  });

  static String? _hhmm(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// "10:00 – 10:30" from PATROL_SCHEDULE, else the guard's shift time.
  String get _timeText {
    final start = _hhmm(schedule?.scheduleStart);
    final end = _hhmm(schedule?.scheduleEnd);
    if (start != null && end != null) return '$start – $end';
    if (start != null) return start;
    return (guard?.shiftTime ?? '-').replaceAll(' - ', ' – ');
  }

  static const _borderBlue = Color(0xFF4A9BE0);
  static const _avatarBg = Color(0xFFCFE6F7);

  _StatusStyle _styleFor(String raw) {
    switch (raw.toUpperCase().trim()) {
      case 'ON_DUTY':
        return const _StatusStyle(
          label: 'ON DUTY',
          dot: Color(0xFF2ECC40),
          pillBg: Color(0xFFD9F5DC),
          text: Color(0xFF1B8E2D),
        );
      case 'REST':
        return const _StatusStyle(
          label: 'REST',
          dot: Color(0xFF1E7BFF),
          pillBg: Color(0xFFD6E8FB),
          text: Color(0xFF1E7BFF),
          icon: Icons.bed,
        );
      case 'OFF_DUTY':
      default:
        return const _StatusStyle(
          label: 'OFF DUTY',
          dot: Color(0xFFF03A3A),
          pillBg: Color(0xFFFDDADA),
          text: Color(0xFFE01B1B),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = guard;
    final style = _styleFor(g?.dutyStatus ?? 'OFF_DUTY');
    final name = isLoading ? 'Loading...' : (g?.fullName ?? '-');
    final number = g?.guardNumber ?? '-';
    final shift = _timeText;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderBlue, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // ── Avatar + status dot ───────────────────────────
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarBg,
                    ),
                    child: const Icon(
                      Icons.local_police,
                      size: 38,
                      color: Color(0xFF1F3B63),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: style.dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Colors.grey.shade300,
            ),
            const SizedBox(width: 14),

            // ── Name + guard number ───────────────────────────
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16213A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    number,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            // ── Status pill + shift time ──────────────────────
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: style.pillBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (style.icon != null) ...[
                          Icon(style.icon, size: 16, color: style.text),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          style.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: style.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time,
                          size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          shift,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color dot;
  final Color pillBg;
  final Color text;
  final IconData? icon;

  const _StatusStyle({
    required this.label,
    required this.dot,
    required this.pillBg,
    required this.text,
    this.icon,
  });
}