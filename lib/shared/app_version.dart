/// App version shown in the UI.
///
/// Kept as a Dart constant (rather than package_info_plus) so version display
/// stays pure-Dart and can ship via Shorebird patches — a native plugin would
/// be dead code until the next full store release.
///
/// KEEP IN SYNC with `version:` in pubspec.yaml when cutting a release.
const String appVersion = '1.0.18+20';
