// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:superbass/main.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env').catchError((_) {
      dotenv.loadFromString(envString: 'API_URL=http://localhost:5000\n');
    });
  });

  testWidgets('SuperBassApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SuperBassApp());

    // Verify that the search headline exists
    expect(find.text('Find Trusted Community Pros'), findsOneWidget);
  });
}
