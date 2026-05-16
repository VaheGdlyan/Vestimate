import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/home_tab.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/closet_tab.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/stylist_tab.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/outfits_tab.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/profile_tab.dart';
import 'package:vestimate/core/router/nav_provider.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final List<Widget> _tabs = const [
    HomeTab(),
    ClosetTab(),
    StylistTab(),
    OutfitsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(bottomNavProvider);
    
    // We restrict the maximum width to emulate a mobile device perfectly on Web/Desktop.
    return Scaffold(
      backgroundColor: Colors.black, // Dark outer background for web
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450), // Mobile width constraint
          decoration: BoxDecoration(
            color: V.bg,
            boxShadow: [
              BoxShadow(
                color: V.accent.withOpacity(0.05),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
            border: Border.symmetric(
              vertical: BorderSide(color: V.border, width: 1),
            ),
          ),
          child: Scaffold(
            backgroundColor: V.bg,
            body: IndexedStack(
              index: currentIndex,
              children: _tabs,
            ),
            floatingActionButton: currentIndex == 1
              ? FloatingActionButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    // Navigate to Home tab where the Scan/Upload button lives
                    ref.read(bottomNavProvider.notifier).state = 0;
                  },
                  child: const Icon(Icons.camera_alt_rounded),
                )
              : null,
            bottomNavigationBar: Container(
              decoration: const BoxDecoration(
                color: V.bg,
                border: Border(top: BorderSide(color: V.border, width: 0.5)),
              ),
              child: SafeArea(
                top: false,
                child: BottomNavigationBar(
                  currentIndex: currentIndex,
                  onTap: (i) {
                    HapticFeedback.selectionClick();
                    ref.read(bottomNavProvider.notifier).state = i;
                  },
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedItemColor: V.accent, // Luxury gold active tab
                  unselectedItemColor: Colors.white30,
                  type: BottomNavigationBarType.fixed,
                  selectedFontSize: 10,
                  unselectedFontSize: 10,
                  selectedLabelStyle: const TextStyle(
                    fontFamily: V.fontFamily,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: V.fontFamily,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                  ),
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_outlined, size: 24),
                      activeIcon: Icon(Icons.home_rounded, size: 24),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.checkroom_outlined, size: 24),
                      activeIcon: Icon(Icons.checkroom, size: 24),
                      label: 'Closet',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.auto_awesome_outlined, size: 24),
                      activeIcon: Icon(Icons.auto_awesome, size: 24),
                      label: 'Stylist',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.style_outlined, size: 24),
                      activeIcon: Icon(Icons.style, size: 24),
                      label: 'Outfits',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline, size: 24),
                      activeIcon: Icon(Icons.person, size: 24),
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
