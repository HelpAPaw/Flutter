import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _nearbySignalsEnabled = true;
  double _notificationRadius = 5.0;
  String _mapType = 'normal';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _nearbySignalsEnabled = prefs.getBool('nearby_signals_enabled') ?? true;
      _notificationRadius = prefs.getDouble('notification_radius') ?? 5.0;
      _mapType = prefs.getString('map_type') ?? 'normal';
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const _SectionHeader(title: 'Notifications'),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications),
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Receive notifications about signals'),
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() => _notificationsEnabled = value);
                    _saveSetting('notifications_enabled', value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.location_on),
                  title: const Text('Nearby Signal Alerts'),
                  subtitle: const Text('Get notified when new signals appear nearby'),
                  value: _nearbySignalsEnabled,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _nearbySignalsEnabled = value);
                          _saveSetting('nearby_signals_enabled', value);
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.radar),
                  title: const Text('Notification Radius'),
                  subtitle: Text('${_notificationRadius.round()} km'),
                  enabled: _notificationsEnabled && _nearbySignalsEnabled,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 72),
                  child: Slider(
                    value: _notificationRadius,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${_notificationRadius.round()} km',
                    onChanged: _notificationsEnabled && _nearbySignalsEnabled
                        ? (value) {
                            setState(() => _notificationRadius = value);
                          }
                        : null,
                    onChangeEnd: (value) {
                      _saveSetting('notification_radius', value);
                    },
                  ),
                ),
                const Divider(),
                const _SectionHeader(title: 'Map'),
                ListTile(
                  leading: const Icon(Icons.map),
                  title: const Text('Map Type'),
                  subtitle: Text(_getMapTypeName(_mapType)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showMapTypeDialog(),
                ),
                const Divider(),
                const _SectionHeader(title: 'About'),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('About Help A Paw'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/about'),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy_policy'),
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy_policy'),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  String _getMapTypeName(String type) {
    switch (type) {
      case 'normal':
        return 'Standard';
      case 'satellite':
        return 'Satellite';
      case 'terrain':
        return 'Terrain';
      case 'hybrid':
        return 'Hybrid';
      default:
        return 'Standard';
    }
  }

  void _showMapTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('Standard'),
              value: 'normal',
              groupValue: _mapType,
              onChanged: (value) {
                setState(() => _mapType = value!);
                _saveSetting('map_type', value);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Satellite'),
              value: 'satellite',
              groupValue: _mapType,
              onChanged: (value) {
                setState(() => _mapType = value!);
                _saveSetting('map_type', value);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Terrain'),
              value: 'terrain',
              groupValue: _mapType,
              onChanged: (value) {
                setState(() => _mapType = value!);
                _saveSetting('map_type', value);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Hybrid'),
              value: 'hybrid',
              groupValue: _mapType,
              onChanged: (value) {
                setState(() => _mapType = value!);
                _saveSetting('map_type', value);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.orange[800],
        ),
      ),
    );
  }
}
