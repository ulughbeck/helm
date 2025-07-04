import 'initial_uri_provider_vm.dart' if (dart.library.html) 'initial_uri_provider_web.dart';

/// Feturns initial URI from platform
Uri getInitialUri() => getInitialUriImpl(_normalizeInitialPath);

String _normalizeInitialPath(String path) {
  if (path.isEmpty || path == '/') return '/';
  String normalized = path.replaceFirst(RegExp(r'^/+'), '/');
  if (!normalized.startsWith('/')) normalized = '/$normalized';
  return normalized;
}
