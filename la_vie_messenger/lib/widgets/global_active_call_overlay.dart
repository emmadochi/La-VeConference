import 'package:flutter/material.dart';
import '../services/active_call_manager.dart';
import 'floating_call_overlay.dart';

class GlobalActiveCallOverlay extends StatelessWidget {
  const GlobalActiveCallOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ActiveCallManager.instance,
      builder: (context, _) {
        final callManager = ActiveCallManager.instance;
        if (!callManager.hasActiveCall || !callManager.isMinimized) {
          return const SizedBox.shrink();
        }

        return const Stack(
          clipBehavior: Clip.none,
          children: [
            FloatingCallOverlay(),
          ],
        );
      },
    );
  }
}
