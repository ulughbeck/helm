import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

Uri getInitialUriImpl(String Function(String) normalize) {
  final currentUri = Uri.parse(web.window.location.href);
  final normalizedPath = normalize(currentUri.path);

  if (normalizedPath != currentUri.path) {
    final newUrl = Uri(
      scheme: currentUri.scheme,
      host: currentUri.host,
      port: currentUri.port,
      path: normalizedPath,
      query: currentUri.query,
      fragment: currentUri.fragment,
    ).toString();
    web.window.history.replaceState(null, '', newUrl);
  }

  // ignore: prefer_const_constructors
  setUrlStrategy(PathUrlStrategy());

  return currentUri.replace(path: normalizedPath);
}
