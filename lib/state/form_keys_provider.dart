// De redactiesleutel van de organisator (FORM_INTAKE.md §5.9) als dienst: één plek, zodat een
// test hem kan vervangen en de rest van de app niet zelf de sleutelhanger hoeft te kennen.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/form/form_keys.dart';
import 'secret_store_provider.dart';

final formKeyServiceProvider = Provider<FormKeyService>(
  (ref) => FormKeyService(ref.read(secretStoreProvider)),
);
