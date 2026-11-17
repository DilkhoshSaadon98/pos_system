/// Shared loading lifecycle used by every state class in the app.
///
/// Four values, one meaning each: nothing asked for yet, waiting, showing real
/// data, and stopped on an error. A screen that needs a fifth state usually
/// needs a second boolean instead (`isSaving`), because "ready but a dialog is
/// working" is not a different kind of ready.
enum AppStatus { initial, loading, ready, failure }

extension AppStatusX on AppStatus {
  bool get isInitial => this == AppStatus.initial;
  bool get isLoading => this == AppStatus.loading;
  bool get isReady => this == AppStatus.ready;
  bool get isFailure => this == AppStatus.failure;

  /// True while the first load is still in flight — the moment a screen shows
  /// a skeleton rather than an empty table.
  bool get isBusyFirstTime => this == AppStatus.initial || this == AppStatus.loading;
}
