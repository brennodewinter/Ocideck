import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NewDeckDialog extends StatefulWidget {
  const NewDeckDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewDeckDialog(),
    );
  }

  @override
  State<NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends State<NewDeckDialog> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: const Text('Nieuwe presentatie'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 380,
            child: TextFormField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Titel',
                hintText: 'Bijv. Kwartaalupdate Q4',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Vul een titel in' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(onPressed: _submit, child: const Text('Aanmaken')),
        ],
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _ctrl.text.trim());
    }
  }
}
