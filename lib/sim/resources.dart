/// Resource definitions for Ports Ahoy!
///
/// Pure Dart — no Flutter imports anywhere under lib/sim/ so the whole
/// economy can be exercised by `dart test` without a widget tree.
library;

enum ResourceCategory { raw, good, food, contraband }

enum Resource {
  timber('Timber', ResourceCategory.raw, 2.0, '🪵', 0.4),
  grain('Grain', ResourceCategory.food, 3.0, '🌾', 0.4),
  fish('Fish', ResourceCategory.food, 3.0, '🐟', 0.4),
  flax('Flax', ResourceCategory.raw, 4.0, '🌿', 0.4),
  ore('Ore', ResourceCategory.raw, 5.0, '⛏️', 0.4),
  planks('Planks', ResourceCategory.good, 7.0, '🪚', 0.6),
  rope('Rope', ResourceCategory.good, 12.0, '🪢', 0.8),
  barrels('Barrels', ResourceCategory.good, 20.0, '🛢️', 1.0),
  sailcloth('Sailcloth', ResourceCategory.good, 22.0, '⛵', 1.1),
  tools('Tools', ResourceCategory.good, 40.0, '🔨', 4.0),

  // Contraband. None of these can be bought from a ship — spirits and powder
  // are manufactured in sheds you staffed, silk only ever arrives as prize
  // cargo. A port that never builds a dark shed never sees any of them.
  spirits('Spirits', ResourceCategory.contraband, 34.0, '🥃', 1.0),
  powder('Powder', ResourceCategory.contraband, 55.0, '💥', 1.6);

  const Resource(
      this.label, this.category, this.basePrice, this.icon, this.heatWeight);

  final String label;
  final ResourceCategory category;

  /// Coin per unit at a neutral market index of 1.0.
  final double basePrice;
  final String icon;

  /// How conspicuous a unit of this is when it moves through your quay.
  ///
  /// Legitimate goods carry real weights, not zero: a port importing tools off
  /// a smuggler is noticed, a port importing planks barely is. Zeroing these
  /// would silently switch off the dark-purchase heat rule entirely.
  final double heatWeight;

  bool get isFood => category == ResourceCategory.food;
  bool get isContraband => category == ResourceCategory.contraband;

  static Resource byId(String id) =>
      Resource.values.firstWhere((r) => r.name == id);

  static List<Resource> get contraband =>
      Resource.values.where((r) => r.isContraband).toList();
}

/// Raw materials a coin-fed import berth may land.
///
/// Never a finished good and never food: coin buys throughput INTO your chains,
/// never a leg of the win condition and never a way out of a famine. Every
/// plank, rope, sailcloth and tool the lighthouse wants still has to pass
/// through a shed you built and staffed.
const List<Resource> kImportables = [
  Resource.timber,
  Resource.flax,
  Resource.ore,
];

/// A mutable bag of resource quantities. Quantities are doubles so production
/// can accrue in per-tick fractions without rounding losses piling up.
class ResourceBag {
  ResourceBag([Map<Resource, double>? initial])
      : _amounts = {for (final r in Resource.values) r: 0.0} {
    if (initial != null) initial.forEach((k, v) => _amounts[k] = v);
  }

  final Map<Resource, double> _amounts;

  double operator [](Resource r) => _amounts[r] ?? 0.0;
  void operator []=(Resource r, double v) => _amounts[r] = v < 0 ? 0.0 : v;

  void add(Resource r, double v) => this[r] = this[r] + v;
  void remove(Resource r, double v) => this[r] = this[r] - v;

  bool has(Resource r, double v) => this[r] >= v - 1e-9;

  /// True when every entry in [cost] is affordable.
  bool canAfford(Map<Resource, double> cost) =>
      cost.entries.every((e) => has(e.key, e.value));

  void payAll(Map<Resource, double> cost) =>
      cost.forEach((r, v) => remove(r, v));

  Map<String, double> toJson() =>
      _amounts.map((k, v) => MapEntry(k.name, double.parse(v.toStringAsFixed(4))));

  static ResourceBag fromJson(Map<String, dynamic> json) {
    final bag = ResourceBag();
    json.forEach((k, v) {
      try {
        bag[Resource.byId(k)] = (v as num).toDouble();
      } on StateError {
        // Resource removed in a later version of the game — drop it.
      }
    });
    return bag;
  }

  ResourceBag copy() => ResourceBag(Map.of(_amounts));
}
