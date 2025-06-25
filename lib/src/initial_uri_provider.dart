import 'initial_uri_provider_vm.dart' if (dart.library.html) 'initial_uri_provider_web.dart';

Uri getInitialUri() => getInitialUriImpl(normalizeInitialPath);

String normalizeInitialPath(String path) {
  if (path.isEmpty || path == '/') return '/';
  String normalized = path.replaceFirst(RegExp(r'^/+'), '/');
  if (!normalized.startsWith('/')) normalized = '/$normalized';
  return normalized;
}
