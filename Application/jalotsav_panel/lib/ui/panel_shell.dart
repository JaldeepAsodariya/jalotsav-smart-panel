import 'package:flutter/material.dart';

import '../core/fake_device_gateway.dart';
import '../core/panel_controller.dart';
import 'screens/alarms_screen.dart';
import 'screens/live_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/trend_screen.dart';
import 'strings.dart';
import 'theme_controller.dart';
import 'widgets/glass.dart';
import 'widgets/status_bar.dart';

/// Panel layout: status bar on top, navigation rail on the left.
/// No routes/Navigator stack — a panel never needs a back button.
class PanelShell extends StatefulWidget {
  const PanelShell({
    required this.controller,
    required this.theme,
    this.simulator,
    super.key,
  });

  final PanelController controller;
  final ThemeController theme;
  final FakeDeviceGateway? simulator;

  @override
  State<PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends State<PanelShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // One BackdropGroup: every glass pane shares a single backdrop read.
    return GlassBackdrop(
      child: BackdropGroup(
        child: Scaffold(
          body: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              final screen = switch (_index) {
                0 => LiveScreen(controller: c),
                1 => TrendScreen(controller: c),
                2 => AlarmsScreen(controller: c),
                _ => SettingsScreen(
                  controller: c,
                  theme: widget.theme,
                  simulator: widget.simulator,
                ),
              };
              // Keeps the panel clear of a phone's camera cutout and system bars.
              return SafeArea(
                child: Column(
                  children: [
                    StatusBar(controller: c, theme: widget.theme),
                    Expanded(
                      child: Row(
                        children: [
                          _GlassRail(
                            builder: (compact) => NavigationRail(
                              selectedIndex: _index,
                              onDestinationSelected: (i) =>
                                  setState(() => _index = i),
                              // Short screens (e.g. a phone with its system bars
                              // showing): icons only.
                              labelType: compact
                                  ? NavigationRailLabelType.none
                                  : NavigationRailLabelType.all,
                              groupAlignment: 0,
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.speed),
                                  label: Text(S.live),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.show_chart),
                                  label: Text(S.trend),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(
                                    Icons.notifications_active_outlined,
                                  ),
                                  label: Text(S.alarms),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.tune),
                                  label: Text(S.settings),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: screen),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The navigation rail on its own glass pane, inset from the edges.
///
/// Below [_compactBelow] px of height the rail drops its labels, and it can
/// scroll as a last resort, so it never overflows on a short phone screen.
class _GlassRail extends StatelessWidget {
  const _GlassRail({required this.builder});

  final Widget Function(bool compact) builder;

  static const _compactBelow = 320.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      child: GlassSurface(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: builder(box.maxHeight < _compactBelow),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
