void main() {
  final original = DateTime.now();
  print("Original: $original");
  
  sleep(const Duration(milliseconds: 100));
  
  final copied = DateTime.now();
  print("Copied: $copied");
  print("Copied after original: ${copied.isAfter(original)}");
}

import 'dart:io';
