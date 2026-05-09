import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'VESTIMATE',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: VestimateColors.accent,
                letterSpacing: 8.0,
              ),
            ),
            const SizedBox(height: VestimateSpacing.md),
            const Text('Luxury Wardrobe Management'),
          ],
        ),
      ),
    );
  }
}
