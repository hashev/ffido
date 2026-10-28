/// Bounded installer outcomes. Android does not identify every blocker.
class AndroidInstallResult {
  AndroidInstallResult(this.outcome, this.status);
  factory AndroidInstallResult.parse(Object? value) {
    if (value is! Map ||
        !const {
          'success',
          'cancelled',
          'permission_denied',
          'blocked',
          'failed',
          'pending',
          'unknown',
        }.contains(value['outcome']) ||
        value['status'] != null && value['status'] is! int) {
      throw const FormatException('Некорректный результат установщика');
    }
    return AndroidInstallResult(
      value['outcome'] as String,
      value['status'] as int?,
    );
  }
  final String outcome;
  final int? status;
  String get message => switch (outcome) {
    'success' => 'Обновление установлено.',
    'cancelled' => 'Установка отменена; текущая версия сохранена.',
    'permission_denied' =>
      'Не разрешена установка обновления; текущая версия сохранена.',
    'blocked' => 'Android запретил установку обновления. Точная причина недоступна; текущая версия сохранена.',
    'pending' => 'Android ещё выполняет установку. Дождитесь результата системного установщика.',
    'unknown' => 'Результат установки недоступен. Проверьте установленную версию; причина отказа неизвестна.',
    _ => 'Не удалось установить обновление; текущая версия сохранена.',
  };
}
