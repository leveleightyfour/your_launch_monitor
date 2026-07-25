import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/shared/services/shorebird_update_service.dart';

/// App-lifetime Shorebird update service. Non-autodispose (keepAlive) so the
/// poll timer survives navigation; starts polling on first read.
final shorebirdUpdateProvider = Provider<ShorebirdUpdateService>((ref) {
  final service = ShorebirdUpdateService()..start();
  ref.onDispose(service.dispose);
  return service;
});
