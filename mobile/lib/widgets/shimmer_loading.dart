import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SeatyShimmer extends StatelessWidget {
  final Widget child;

  const SeatyShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFF8FAFC),
      child: child,
    );
  }
}

/// Shimmer skeleton for Trip Cards
class TripCardSkeleton extends StatelessWidget {
  const TripCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SeatyShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// Shimmer skeleton for Passenger Manifest Item
class ManifestSkeleton extends StatelessWidget {
  const ManifestSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SeatyShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

/// Shimmer skeleton for Stat Tile
class StatTileSkeleton extends StatelessWidget {
  const StatTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SeatyShimmer(
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
