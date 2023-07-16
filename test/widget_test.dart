import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:help_a_paw/main.dart';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Widget Test', (WidgetTester tester) async {
    // Build application and trigger a frame
    await tester.pumpWidget(const HelpAPaw());
  });
}
