import 'package:flutter/material.dart';

enum ClubType { wood, miniDriver, hybrid, iron, wedge, putter }

class Club {
  final String id;
  final String shortName;
  final String? manufacturer;
  final String? model;
  final Color color;

  const Club({
    required this.id,
    required this.shortName,
    this.manufacturer,
    this.model,
    required this.color,
  });

  /// Derived from the id — no stored field required.
  ClubType get type {
    if (id == 'dr') return ClubType.wood;
    if (id == 'mdr') return ClubType.miniDriver;
    if (id == 'pt') return ClubType.putter;
    // Named wedges must be checked before endsWith('w') to avoid pw/sw/lw
    // being misclassified as woods.
    if (id == 'pw' || id == 'gw' || id == 'sw' || id == 'lw')
      return ClubType.wedge;
    if (id.endsWith('w')) return ClubType.wood;
    if (id.endsWith('h')) return ClubType.hybrid;
    if (id.endsWith('i')) return ClubType.iron;
    // degree wedges (e.g. "50deg")
    return ClubType.wedge;
  }

  // ── Full club catalog (matches Foresight MyBag) ───────────────────────────

  static const List<Club> catalog = [
    // Mini Driver (own section)
    Club(id: 'mdr', shortName: 'Mini Dr', color: Color(0xFF38BDF8)),
    // Woods
    Club(id: 'dr', shortName: 'Dr', color: Color(0xFF2DD4B0)),
    Club(id: '2w', shortName: '2w', color: Color(0xFFF59E42)),
    Club(id: '3w', shortName: '3w', color: Color(0xFFA78BFA)),
    Club(id: '4w', shortName: '4w', color: Color(0xFF60A5FA)),
    Club(id: '5w', shortName: '5w', color: Color(0xFFF472B6)),
    Club(id: '6w', shortName: '6w', color: Color(0xFF34D399)),
    Club(id: '7w', shortName: '7w', color: Color(0xFFFBBF24)),
    Club(id: '9w', shortName: '9w', color: Color(0xFFEC4899)),
    Club(id: '11w', shortName: '11w', color: Color(0xFF818CF8)),
    // Hybrids
    Club(id: '1h', shortName: '1h', color: Color(0xFF67E8F9)),
    Club(id: '2h', shortName: '2h', color: Color(0xFF86EFAC)),
    Club(id: '3h', shortName: '3h', color: Color(0xFFFDE68A)),
    Club(id: '4h', shortName: '4h', color: Color(0xFFC4B5FD)),
    Club(id: '5h', shortName: '5h', color: Color(0xFFFCA5A5)),
    Club(id: '6h', shortName: '6h', color: Color(0xFF93C5FD)),
    Club(id: '7h', shortName: '7h', color: Color(0xFF6EE7B7)),
    Club(id: '8h', shortName: '8h', color: Color(0xFFFCD34D)),
    Club(id: '9h', shortName: '9h', color: Color(0xFF818CF8)),
    // Irons
    Club(id: '1i', shortName: '1i', color: Color(0xFF60A5FA)),
    Club(id: '2i', shortName: '2i', color: Color(0xFFF472B6)),
    Club(id: '3i', shortName: '3i', color: Color(0xFF34D399)),
    Club(id: '4i', shortName: '4i', color: Color(0xFFFBBF24)),
    Club(id: '5i', shortName: '5i', color: Color(0xFFEC4899)),
    Club(id: '6i', shortName: '6i', color: Color(0xFF818CF8)),
    Club(id: '7i', shortName: '7i', color: Color(0xFF6EE7B7)),
    Club(id: '8i', shortName: '8i', color: Color(0xFFFCA5A5)),
    Club(id: '9i', shortName: '9i', color: Color(0xFFFCD34D)),
    // Named wedges
    Club(id: 'pw', shortName: 'PW', color: Color(0xFFFCA5A5)),
    Club(id: 'gw', shortName: 'GW', color: Color(0xFFFCD34D)),
    Club(id: 'sw', shortName: 'SW', color: Color(0xFF93C5FD)),
    Club(id: 'lw', shortName: 'LW', color: Color(0xFFC4B5FD)),
    // Degree wedges
    Club(id: '50deg', shortName: '50°', color: Color(0xFF86EFAC)),
    Club(id: '52deg', shortName: '52°', color: Color(0xFF67E8F9)),
    Club(id: '54deg', shortName: '54°', color: Color(0xFFFDE68A)),
    Club(id: '56deg', shortName: '56°', color: Color(0xFFFBBF24)),
    Club(id: '58deg', shortName: '58°', color: Color(0xFFF59E42)),
    Club(id: '60deg', shortName: '60°', color: Color(0xFFF472B6)),
    Club(id: '62deg', shortName: '62°', color: Color(0xFFEC4899)),
    Club(id: '64deg', shortName: '64°', color: Color(0xFFC4B5FD)),
    // Putter
    Club(id: 'pt', shortName: 'P', color: Color(0xFFD1D5DB)),
  ];

  /// Starter bag — reasonable default set of 14 clubs.
  static const List<Club> defaults = [
    Club(id: 'dr', shortName: 'Dr', color: Color(0xFF2DD4B0)),
    Club(id: 'mdr', shortName: 'Mini Dr', color: Color(0xFF38BDF8)),
    Club(id: '3w', shortName: '3w', color: Color(0xFFA78BFA)),
    Club(id: '5w', shortName: '5w', color: Color(0xFFF472B6)),
    Club(id: '3h', shortName: '3H', color: Color(0xFFFF8C42)),
    Club(id: '4h', shortName: '4H', color: Color(0xFFFFB347)),
    Club(id: '4i', shortName: '4i', color: Color(0xFFFBBF24)),
    Club(id: '5i', shortName: '5i', color: Color(0xFFEC4899)),
    Club(id: '6i', shortName: '6i', color: Color(0xFF818CF8)),
    Club(id: '7i', shortName: '7i', color: Color(0xFF6EE7B7)),
    Club(id: '8i', shortName: '8i', color: Color(0xFFFCA5A5)),
    Club(id: '9i', shortName: '9i', color: Color(0xFFFCD34D)),
    Club(id: 'pw', shortName: 'PW', color: Color(0xFFFCA5A5)),
    Club(id: 'gw', shortName: 'GW', color: Color(0xFFFCD34D)),
    Club(id: 'sw', shortName: 'SW', color: Color(0xFF93C5FD)),
    Club(id: 'lw', shortName: 'LW', color: Color(0xFFC4B5FD)),
    Club(id: 'pt', shortName: 'P', color: Color(0xFFD1D5DB)),
  ];

  /// Group label for display in the bag picker.
  static String groupLabel(ClubType type) => switch (type) {
    ClubType.wood => 'WOODS',
    ClubType.miniDriver => 'MINI DRIVER',
    ClubType.hybrid => 'HYBRIDS',
    ClubType.iron => 'IRONS',
    ClubType.wedge => 'WEDGES',
    ClubType.putter => 'PUTTER',
  };

  Club copyWith({String? manufacturer, String? model}) {
    return Club(
      id: id,
      shortName: shortName,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      color: color,
    );
  }
}
