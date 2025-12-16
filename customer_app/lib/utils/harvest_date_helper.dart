import 'package:flutter/foundation.dart';

class HarvestDateHelper {
  /// Calculate next Friday-Saturday harvest dates (same as web dashboard)
  /// Web dashboard uses: getDay() where 0=Sunday, 5=Friday, 6=Saturday
  /// Dart uses: weekday where 1=Monday, 5=Friday, 6=Saturday, 7=Sunday
  static Map<String, DateTime> getNextHarvestDates() {
    final today = DateTime.now();
    // Convert Dart weekday (1=Mon..7=Sun) to JavaScript getDay() format (0=Sun..6=Sat)
    final currentDayJs = today.weekday == 7 ? 0 : today.weekday;
    
    // Calculate days until next Friday (same logic as web dashboard)
    // JavaScript: daysUntilFriday = (5 - currentDay + 7) % 7;
    int daysUntilFriday = (5 - currentDayJs + 7) % 7;
    if (daysUntilFriday == 0 && currentDayJs != 5) {
      daysUntilFriday = 7; // If it's not Friday, go to next Friday
    }
    
    final nextFriday = DateTime(today.year, today.month, today.day).add(Duration(days: daysUntilFriday));
    final nextSaturday = nextFriday.add(const Duration(days: 1));
    
    // Reset to midnight
    final fridayDate = DateTime(
      nextFriday.year,
      nextFriday.month,
      nextFriday.day,
    );
    final saturdayDate = DateTime(
      nextSaturday.year,
      nextSaturday.month,
      nextSaturday.day,
    );
    
    return {
      'friday': fridayDate,
      'saturday': saturdayDate,
    };
  }
  
  /// Format harvest date range for display
  /// Shows "Friday, Jan 15 - Saturday, Jan 16" format
  static String formatHarvestDateRange(DateTime? harvestDate) {
    if (harvestDate == null) {
      return 'N/A';
    }
    
    final dates = getNextHarvestDates();
    final friday = dates['friday']!;
    final saturday = dates['saturday']!;
    
    // Format: "Friday, Jan 15 - Saturday, Jan 16"
    final fridayStr = _formatDateDisplay(friday);
    final saturdayStr = _formatDateDisplay(saturday);
    
    return '$fridayStr - $saturdayStr';
  }
  
  /// Format single date for display (e.g., "Friday, Jan 15")
  static String _formatDateDisplay(DateTime date) {
    const weekdays = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final weekday = weekdays[date.weekday];
    final month = months[date.month];
    final day = date.day;
    
    return '$weekday, $month $day';
  }
  
  /// Get harvest date range as a simple string (for display)
  /// Returns "Jan 15 - Jan 16" format
  static String getHarvestDateRangeSimple() {
    final dates = getNextHarvestDates();
    final friday = dates['friday']!;
    final saturday = dates['saturday']!;
    
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final fridayStr = '${months[friday.month]} ${friday.day}';
    final saturdayStr = '${months[saturday.month]} ${saturday.day}';
    
    return '$fridayStr - $saturdayStr';
  }
}

