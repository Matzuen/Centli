import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// In-app Chinese privacy policy (asset: assets/legal/privacy_zh.txt).
class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  late final Future<String> _textFuture;

  @override
  void initState() {
    super.initState();
    _textFuture = rootBundle.loadString('assets/legal/privacy_zh.txt');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: FutureBuilder<String>(
        future: _textFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '无法加载隐私政策：${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final text = snap.data ?? '';
          return Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SelectableText(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
