import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/strings_notice.dart';
import '../app_scope.dart';

const disclaimerAcceptedKey = 'disclaimer_accepted_v1';

Future<bool> disclaimerAccepted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(disclaimerAcceptedKey) ?? false;
}

Future<void> _acceptDisclaimer() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(disclaimerAcceptedKey, true);
}

/// Shows the disclaimer. With [requireAcceptance] the dialog can only be
/// closed through the accept button, which records the acceptance.
Future<void> showDisclaimer(
  BuildContext context, {
  bool requireAcceptance = false,
}) {
  final strings = AppScope.of(context).strings;
  return showDialog<void>(
    context: context,
    barrierDismissible: !requireAcceptance,
    builder: (context) => PopScope(
      canPop: !requireAcceptance,
      child: AlertDialog(
        key: const Key('disclaimer-dialog'),
        title: Text(strings.disclaimerTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final paragraph in strings.disclaimerParagraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(paragraph),
                ),
            ],
          ),
        ),
        actions: [
          if (requireAcceptance)
            FilledButton(
              key: const Key('disclaimer-accept'),
              onPressed: () async {
                await _acceptDisclaimer();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(strings.disclaimerAccept),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.close),
            ),
        ],
      ),
    ),
  );
}

/// Shows the disclaimer once over [child] on first launch.
class DisclaimerGate extends StatefulWidget {
  const DisclaimerGate({super.key, required this.child});

  final Widget child;

  @override
  State<DisclaimerGate> createState() => _DisclaimerGateState();
}

class _DisclaimerGateState extends State<DisclaimerGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showDisclaimer(context, requireAcceptance: true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
