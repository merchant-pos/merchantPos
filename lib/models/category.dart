/// Named `ProductCategory` (not `Category`) because Flutter itself
/// already exports a `Category` annotation class from
/// package:flutter/foundation.dart, which would otherwise clash.
class ProductCategory {
  final String id;
  final String name;

  ProductCategory({required this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: map['id'] as String,
      name: map['name'] as String,
    );
  }
}
