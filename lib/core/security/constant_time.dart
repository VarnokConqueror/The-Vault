import 'dart:convert';

class ConstantTime {
  static bool equalsBytes(List<int> left, List<int> right) {
    var diff = left.length ^ right.length;
    final maxLength = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxLength; i++) {
      final leftByte = i < left.length ? left[i] : 0;
      final rightByte = i < right.length ? right[i] : 0;
      diff |= leftByte ^ rightByte;
    }
    return diff == 0;
  }

  static bool equalsUtf8(String left, String right) {
    return equalsBytes(utf8.encode(left), utf8.encode(right));
  }
}
