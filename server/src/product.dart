import 'package:collection/collection.dart' show DeepCollectionEquality;

int intTotal(Iterable<Item> items) => items.fold(0, (prev, e)=>prev+e.intTotal);
String prettyPrintPrice(int price) => "${price~/100},${price%100 < 10 ? 0 : ''}${price%100}";

enum ListKind {
  Radio, Check
}

class VariationList {
  ListKind listKind;
  List<String> variations;

  VariationList(this.listKind, this.variations);
  VariationList.fromJson(Map<String, dynamic> obj)
    : this(ListKind.values[obj['kind']], obj['variations'].cast<String>());

  Map<String, dynamic> toJson() => {
    'kind': listKind.index,
    'variations': variations
  };
}

class Product {
  final String imagePath;
  final String name;
  final int intPrice;
  final Map<String, VariationList> variations;
  double get price => intPrice/100;
  String get stringPrice => prettyPrintPrice(intPrice);

  Product(String image, String name, double price, Map<String, VariationList> variations)
    :this.constant(
      image,
      name.toUpperCase(),
      (price*100).toInt(),
      variations
    );

  Product.fromJson(Map<String, dynamic> obj)
    : this.constant(
      obj['image'],
      obj['name'],
      obj['price'],
      obj['variations'].map<String, VariationList>((String k, v)=>MapEntry(k, VariationList.fromJson(v)))
    );

  const Product.constant(this.imagePath, this.name, this.intPrice, [this.variations])
    :assert(name != null), assert(intPrice != null);

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': intPrice,
    'image': imagePath,
    'variations': variations
  };
}

class Item {
  final Product product;
  int quantity = 0;
  /*dynamic is either a string or a list of strings
    if ListKind.Check then it's a list of strings
    if ListKind.Radio then it's a single string
  */
  final Map<String, dynamic> chosvar;
  int get intTotal => product.intPrice*quantity;
  double get total => intTotal/100;
  String get stringTotal => prettyPrintPrice(intTotal);

  Item(this.product, this.chosvar, this.quantity): assert(product != null);
  Item.fromJson(Map<String, dynamic> obj): this(Product.fromJson(obj['product']), obj['chosvar'], obj['quantity']);

  @override
  String toString()=>'${product.name}($quantity)';

  Map<String, dynamic> toJson() => {
    'product': product,
    'chosvar': chosvar,
    'quantity': quantity
  };

  static const equal = DeepCollectionEquality.unordered();

  @override
  bool operator ==(dynamic other){
    if(other is Item)return product==other.product && equal.equals(chosvar, other.chosvar);
    else return false;
  }
}