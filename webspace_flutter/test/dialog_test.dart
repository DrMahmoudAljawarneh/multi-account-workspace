import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webspace_flutter/core/providers.dart';
import 'package:webspace_flutter/features/settings/settings_dialog.dart';
import 'package:webspace_flutter/features/vault/vault_dialog.dart';

/// Widget tests for the Settings and Vault dialogs: rendering, tab
/// navigation and the unsaved-changes guard. The keyring is mocked to an
/// empty store (real platform calls never settle in the fake-async test
/// zone), and Save is never tapped so config.json is untouched.
void main() {
  const keyring = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    initialProfiles = [
      const AppProfile(
        id: 'personal_google_gmail',
        name: 'Gmail',
        initialUrl: 'https://mail.google.com',
        group: 'Personal',
      ),
    ];
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(keyring, (call) async => <String, String>{});
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(keyring, null);
  });

  group('SettingsDialog', () {
    testWidgets('opens with its three tabs', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const SettingsDialog(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Profiles & Apps'), findsOneWidget);
      expect(find.text('Advanced JSON'), findsOneWidget);
      expect(find.text('THEME'), findsOneWidget); // section title is uppercased
    });

    testWidgets('switches to the Profiles & Apps editor', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const SettingsDialog(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profiles & Apps'));
      await tester.pumpAndSettle();

      expect(find.text('Group name'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Add app'), findsOneWidget);
    });

    testWidgets('closes immediately when nothing was edited',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const SettingsDialog(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsNothing);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('asks before discarding edits (and can keep editing)',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const SettingsDialog(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profiles & Apps'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Gmail'), 'Gmail edited');
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Keep editing → dialog stays
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(find.text('Gmail edited'), findsOneWidget);

      // Discard → dialog closes
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
    });
  });

  group('VaultDialog', () {
    testWidgets('renders empty state when the keyring is unavailable',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const VaultDialog(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Credential Vault'), findsOneWidget);
      expect(find.text('No credentials stored yet'), findsOneWidget);
      expect(find.text('0 credentials'), findsOneWidget);
    });

    testWidgets('untouched form closes without a prompt', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const VaultDialog(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add credential'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(VaultDialog), findsNothing);
    });

    testWidgets('guards the form against discarding typed credentials',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const VaultDialog(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add credential'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'App name (e.g. Gmail)'), 'Gmail');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Keep editing → the vault and the typed value survive
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(VaultDialog), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.any((f) => f.controller?.text == 'Gmail'), isTrue);

      // Discard → the dialog closes
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(VaultDialog), findsNothing);
    });
  });
}
