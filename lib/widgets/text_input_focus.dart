import 'package:flutter/widgets.dart';

/// Of een Flutter-tekstveld de primaire toetsenbordfocus heeft.
bool get textInputHasFocus {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.widget is EditableText ||
      context?.findAncestorWidgetOfExactType<EditableText>() != null;
}
