import 'dart:math';
import 'dart:typed_data';
import 'package:synchronized/synchronized.dart';
import 'package:pointycastle/api.dart' show SecureRandom, CipherParameters;

class MutexPair<T> {
  final Lock lock = Lock();
  final T res;

  MutexPair(this.res);
}

//Thanks to LaskaDart for reference implementation
class DartRandomSecure implements SecureRandom {
  final Random rng = Random.secure();

  @override
  String get algorithmName => 'DartRandomSecure';

  @override
  BigInt nextBigInteger(int bitLength) {
    int fullBytes = bitLength ~/ 8;

    // Generate a number from the full bytes.
    Uint8List bytes = nextBytes(fullBytes);
    BigInt res = BigInt.from(bytes.last);
    for(int i = 0; i<bytes.length-1; ++i)
      res += BigInt.from(bytes[i])<<(8*(bytes.length-1-i));

    // Adding remaining bits
    res += BigInt.from(rng.nextInt(pow(2, bitLength-fullBytes*8))) << bytes.length;
    return res;
  }

  @override
  Uint8List nextBytes(int count) {
    Uint8List list = Uint8List(count);

    for (int i = 0; i < list.length; i++)
      list[i] = nextUint8();

    return list;
  }

  @override
  int nextUint16() => rng.nextInt(pow(2, 16));

  @override
  int nextUint32() => rng.nextInt(pow(2, 32));

  @override
  int nextUint8() => rng.nextInt(pow(2, 8));

  @override
  void seed(CipherParameters params) {}
}