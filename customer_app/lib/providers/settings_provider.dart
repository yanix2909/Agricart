import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

class SettingsProvider with ChangeNotifier {
  static const String _notificationsKey = 'notifications_enabled';
  static const String _darkModeKey = 'dark_mode_enabled';
  static const String _languageKey = 'language_english';
  
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _languageEnglish = true;
  bool _isLoading = false;

  bool get notificationsEnabled => _notificationsEnabled;
  bool get darkModeEnabled => _darkModeEnabled;
  bool get languageEnglish => _languageEnglish;
  bool get isLoading => _isLoading;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      _isLoading = true;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled = prefs.getBool(_notificationsKey) ?? true;
      _darkModeEnabled = prefs.getBool(_darkModeKey) ?? false;
      _languageEnglish = prefs.getBool(_languageKey) ?? true;
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (_notificationsEnabled == enabled) return;

    try {
      _notificationsEnabled = enabled;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notificationsKey, enabled);
    } catch (e) {
      debugPrint('Error saving notification settings: $e');
    }
  }

  Future<void> setDarkModeEnabled(bool enabled, {BuildContext? context}) async {
    if (_darkModeEnabled == enabled) return;

    try {
      _darkModeEnabled = enabled;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, enabled);
      
      // Update ThemeProvider if context is provided
      if (context != null) {
        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        if (enabled) {
          await themeProvider.setDarkMode();
        } else {
          await themeProvider.setLightMode();
        }
      }
    } catch (e) {
      debugPrint('Error saving dark mode settings: $e');
    }
  }

  Future<void> setLanguageEnglish(bool english) async {
    if (_languageEnglish == english) return;

    try {
      _languageEnglish = english;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_languageKey, english);
    } catch (e) {
      debugPrint('Error saving language settings: $e');
    }
  }

  String getLanguageDisplayName() {
    return _languageEnglish ? 'English' : 'Filipino';
  }

  String getLanguageShortName() {
    return _languageEnglish ? 'EN' : 'TL';
  }
}
