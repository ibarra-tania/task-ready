import 'package:intl/intl.dart';

/// Formatos de fecha legibles en español sin depender de datos de locale.
class Fmt {
  const Fmt._();

  static String relative(DateTime? date) {
    if (date == null) return 'nunca';
    final diff = DateTime.now().difference(date.toLocal());
    if (diff.inSeconds < 10) return 'justo ahora';
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds} s';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} d';
    return DateFormat('dd/MM/yyyy').format(date.toLocal());
  }

  static String time(DateTime date) => DateFormat('HH:mm:ss').format(date.toLocal());

  static String dateTime(DateTime date) =>
      DateFormat('dd/MM/yyyy HH:mm:ss').format(date.toLocal());
}
