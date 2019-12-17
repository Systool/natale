import 'package:synchronized/synchronized.dart';

class MutexPair<T> {
  final Lock lock = Lock();
  final T res;

  MutexPair(this.res);
}