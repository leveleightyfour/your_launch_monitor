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
    if (id == 'pw' || id == 'gw' || id == 'sw' || id == 'lw') {
      return ClubType.wedge;
    }
    if (id.endsWith('w')) return ClubType.wood;
    if (id.endsWith('h')) return ClubType.hybrid;
    if (id.endsWith('i')) return ClubType.iron;
    // degree wedges (e.g. "50deg")
    return ClubType.wedge;
  }

  // ── Full club catalog (matches Foresight MyBag) ───────────────────────────

  static const List<Club> catalog = [
    // Mini Driver (own section)
    Club(id: 'mdr', shortName: 'Mini Dr', color: Color(0xFF3BF73B)),
    // Woods
    Club(id: 'dr', shortName: 'Dr', color: Color(0xFFD6815C)),
    Club(id: '2w', shortName: '2w', color: Color(0xFFD2EB70)),
    Club(id: '3w', shortName: '3w', color: Color(0xFFED3BF7)),
    Club(id: '4w', shortName: '4w', color: Color(0xFFC76BB5)),
    Club(id: '5w', shortName: '5w', color: Color(0xFF89FAFA)),
    Club(id: '6w', shortName: '6w', color: Color(0xFFF8AD62)),
    Club(id: '7w', shortName: '7w', color: Color(0xFFC76B70)),
    Club(id: '9w', shortName: '9w', color: Color(0xFFC7A26B)),
    Club(id: '11w', shortName: '11w', color: Color(0xFFC3D289)),
    // Hybrids
    Club(id: '1h', shortName: '1h', color: Color(0xFFA6FA89)),
    Club(id: '2h', shortName: '2h', color: Color(0xFFBC89FA)),
    Club(id: '3h', shortName: '3h', color: Color(0xFF9B89D2)),
    Club(id: '4h', shortName: '4h', color: Color(0xFFF7ED3B)),
    Club(id: '5h', shortName: '5h', color: Color(0xFFFAB189)),
    Club(id: '6h', shortName: '6h', color: Color(0xFFB1B8FC)),
    Club(id: '7h', shortName: '7h', color: Color(0xFFD2899F)),
    Club(id: '8h', shortName: '8h', color: Color(0xFFFACD89)),
    Club(id: '9h', shortName: '9h', color: Color(0xFF6AF862)),
    // Irons
    Club(id: '1i', shortName: '1i', color: Color(0xFFFA8F89)),
    Club(id: '2i', shortName: '2i', color: Color(0xFFC2F094)),
    Club(id: '3i', shortName: '3i', color: Color(0xFFD29B89)),
    Club(id: '4i', shortName: '4i', color: Color(0xFF8BC76B)),
    Club(id: '5i', shortName: '5i', color: Color(0xFFF5E2B8)),
    Club(id: '6i', shortName: '6i', color: Color(0xFFFA89B1)),
    Club(id: '7i', shortName: '7i', color: Color(0xFFF489FA)),
    Club(id: '8i', shortName: '8i', color: Color(0xFFB8CDF5)),
    Club(id: '9i', shortName: '9i', color: Color(0xFFD6BE5C)),
    // Named wedges
    Club(id: 'pw', shortName: 'PW', color: Color(0xFFF5B8BB)),
    Club(id: 'gw', shortName: 'GW', color: Color(0xFFB8F5C4)),
    Club(id: 'sw', shortName: 'SW', color: Color(0xFFF5B8F2)),
    Club(id: 'lw', shortName: 'LW', color: Color(0xFFF73BC8)),
    // Degree wedges
    Club(id: '50deg', shortName: '50°', color: Color(0xFFF862F1)),
    Club(id: '52deg', shortName: '52°', color: Color(0xFFA6DDC7)),
    Club(id: '54deg', shortName: '54°', color: Color(0xFF6B87C7)),
    Club(id: '56deg', shortName: '56°', color: Color(0xFFD289BC)),
    Club(id: '58deg', shortName: '58°', color: Color(0xFFAB6BC7)),
    Club(id: '60deg', shortName: '60°', color: Color(0xFFE1C4E9)),
    Club(id: '62deg', shortName: '62°', color: Color(0xFFF094E7)),
    Club(id: '64deg', shortName: '64°', color: Color(0xFFF8E962)),
    // Putter
    Club(id: 'pt', shortName: 'P', color: Color(0xFFD1D5DB)),
  ];

  /// Starter bag — reasonable default set of 14 clubs.
  static const List<Club> defaults = [
    Club(id: 'dr', shortName: 'Dr', color: Color(0xFFD6815C)),
    Club(id: 'mdr', shortName: 'Mini Dr', color: Color(0xFF3BF73B)),
    Club(id: '3w', shortName: '3w', color: Color(0xFFED3BF7)),
    Club(id: '5w', shortName: '5w', color: Color(0xFF89FAFA)),
    Club(id: '3h', shortName: '3H', color: Color(0xFF9B89D2)),
    Club(id: '4h', shortName: '4H', color: Color(0xFFF7ED3B)),
    Club(id: '4i', shortName: '4i', color: Color(0xFF8BC76B)),
    Club(id: '5i', shortName: '5i', color: Color(0xFFF5E2B8)),
    Club(id: '6i', shortName: '6i', color: Color(0xFFFA89B1)),
    Club(id: '7i', shortName: '7i', color: Color(0xFFF489FA)),
    Club(id: '8i', shortName: '8i', color: Color(0xFFB8CDF5)),
    Club(id: '9i', shortName: '9i', color: Color(0xFFD6BE5C)),
    Club(id: 'pw', shortName: 'PW', color: Color(0xFFF5B8BB)),
    Club(id: 'gw', shortName: 'GW', color: Color(0xFFB8F5C4)),
    Club(id: 'sw', shortName: 'SW', color: Color(0xFFF5B8F2)),
    Club(id: 'lw', shortName: 'LW', color: Color(0xFFF73BC8)),
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
