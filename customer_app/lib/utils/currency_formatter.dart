import 'package:flutter/material.dart';

/// Helper class for formatting currency with proper peso symbol display
class CurrencyFormatter {
  /// Returns a widget that displays the peso symbol correctly
  /// Uses a font that supports the peso symbol (U+20B1)
  static Widget pesoSymbol({double? fontSize, Color? color, FontWeight? fontWeight}) {
    return Text(
      '\u20B1',
      style: TextStyle(
        fontFamily: 'Roboto', // Roboto supports peso symbol
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        fontFeatures: const [],
      ),
    );
  }

  /// Formats a price value with peso symbol
  /// Returns a widget that displays the price correctly
  static Widget formatPrice(
    double price, {
    TextStyle? style,
    int decimalPlaces = 2,
  }) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '\u20B1',
            style: (style ?? const TextStyle()).copyWith(
              fontFamily: 'Roboto', // Ensure peso symbol uses Roboto
            ),
          ),
          TextSpan(
            text: price.toStringAsFixed(decimalPlaces),
            style: style,
          ),
        ],
      ),
    );
  }

  /// Formats a price value as a string with peso symbol
  /// Uses Roboto font family for the peso symbol
  static String formatPriceString(double price, {int decimalPlaces = 2}) {
    return '\u20B1${price.toStringAsFixed(decimalPlaces)}';
  }
}

