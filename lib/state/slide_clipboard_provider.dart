import 'package:flutter_riverpod/legacy.dart';
import '../models/slide.dart';

/// Global clipboard for a single copied slide.
/// Lives in the root ProviderScope so it is accessible from any tab.
final slideClipboardProvider = StateProvider<Slide?>((ref) => null);

/// Bronmap van de dia in het globale klembord. De dia zelf reist tussen
/// tabbladen, maar de bronherkomst is nodig om assets veilig te adopteren.
final slideClipboardSourceProjectProvider = StateProvider<String?>(
  (ref) => null,
);
