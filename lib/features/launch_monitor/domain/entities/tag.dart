import 'package:flutter/material.dart';

class Tag {
  final int id;
  final String name;
  final Color color;

  const Tag({required this.id, required this.name, required this.color});

  /// 12-color palette for the tag picker.
  static const List<Color> palette = [
    Color(0xFFEF4444), // red
    Color(0xFFF97316), // orange
    Color(0xFFEAB308), // yellow
    Color(0xFF22C55E), // green
    Color(0xFF06B6D4), // cyan
    Color(0xFF3B82F6), // blue
    Color(0xFF8B5CF6), // violet
    Color(0xFFEC4899), // pink
    Color(0xFF6B7280), // gray
    Color(0xFF14B8A6), // teal
    Color(0xFFF59E0B), // amber
    Color(0xFF84CC16), // lime
  ];
}
