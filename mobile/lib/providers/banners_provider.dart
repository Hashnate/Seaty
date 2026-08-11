import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:seaty/providers/shared_providers.dart';

/// Hero carousel images for the passenger home screen.
///
/// Admin-managed via the console, so marketing imagery can change without an
/// app release. The bundled assets remain the fallback: if the request fails,
/// times out, or no banner is configured, the app shows what it shipped with
/// rather than an empty carousel.
class BannersState {
  final List<String> imageUrls;
  final bool isLoading;

  const BannersState({this.imageUrls = const [], this.isLoading = false});

  BannersState copyWith({List<String>? imageUrls, bool? isLoading}) {
    return BannersState(
      imageUrls: imageUrls ?? this.imageUrls,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class BannersNotifier extends Notifier<BannersState> {
  @override
  BannersState build() {
    Future.microtask(loadBanners);
    return const BannersState(isLoading: true);
  }

  /// Banner URLs come back server-relative (`/uploads/...`), so they need the
  /// API origin prepended - `apiBaseUrl` includes the `/api/v1` suffix.
  String _absoluteUrl(String rawUrl, String apiBaseUrl) {
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    final apiUri = Uri.tryParse(apiBaseUrl);
    if (apiUri == null) return rawUrl;
    final path = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
    return '${apiUri.scheme}://${apiUri.host}'
        '${apiUri.hasPort ? ':${apiUri.port}' : ''}$path';
  }

  Future<void> loadBanners() async {
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(Uri.parse('${settings.apiBaseUrl}/banners'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final urls = <String>[];
        for (final item in data) {
          if (item is! Map) continue;
          final raw = item['image_url']?.toString();
          if (raw == null || raw.isEmpty) continue;
          urls.add(_absoluteUrl(raw, settings.apiBaseUrl));
        }
        state = BannersState(imageUrls: urls, isLoading: false);
        return;
      }
    } catch (e) {
      debugPrint('Error loading hero banners: $e');
    }

    // Leave imageUrls empty - the UI falls back to bundled assets.
    state = state.copyWith(isLoading: false);
  }
}

final bannersProvider =
    NotifierProvider<BannersNotifier, BannersState>(() => BannersNotifier());
