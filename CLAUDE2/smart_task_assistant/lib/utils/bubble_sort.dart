// ignore_for_file: avoid_print

/// 冒泡排序算法实现
///
/// 时间复杂度：
/// - 最优情况（已排序）: O(n)
/// - 平均情况: O(n²)
/// - 最坏情况（逆序）: O(n²)
///
/// 空间复杂度: O(1) - 原地排序
library;

import 'dart:math';

/// 基础冒泡排序
List<T> bubbleSort<T extends Comparable>(List<T> list) {
  final sortedList = List<T>.from(list);

  for (int i = 0; i < sortedList.length - 1; i++) {
    for (int j = 0; j < sortedList.length - 1 - i; j++) {
      if (sortedList[j].compareTo(sortedList[j + 1]) > 0) {
        // 交换元素
        final temp = sortedList[j];
        sortedList[j] = sortedList[j + 1];
        sortedList[j + 1] = temp;
      }
    }
  }

  return sortedList;
}

/// 优化版冒泡排序（提前终止）
List<T> bubbleSortOptimized<T extends Comparable>(List<T> list) {
  final sortedList = List<T>.from(list);
  bool swapped;

  for (int i = 0; i < sortedList.length - 1; i++) {
    swapped = false;

    for (int j = 0; j < sortedList.length - 1 - i; j++) {
      if (sortedList[j].compareTo(sortedList[j + 1]) > 0) {
        final temp = sortedList[j];
        sortedList[j] = sortedList[j + 1];
        sortedList[j + 1] = temp;
        swapped = true;
      }
    }

    // 如果一轮遍历没有交换，说明已经有序，提前终止
    if (!swapped) break;
  }

  return sortedList;
}

/// 记录最后交换位置的冒泡排序（进一步优化）
List<T> bubbleSortWithBoundary<T extends Comparable>(List<T> list) {
  final sortedList = List<T>.from(list);
  int boundary = sortedList.length - 1;
  int lastSwapIndex;

  while (boundary > 0) {
    lastSwapIndex = 0;

    for (int j = 0; j < boundary; j++) {
      if (sortedList[j].compareTo(sortedList[j + 1]) > 0) {
        final temp = sortedList[j];
        sortedList[j] = sortedList[j + 1];
        sortedList[j + 1] = temp;
        lastSwapIndex = j;
      }
    }

    boundary = lastSwapIndex;
  }

  return sortedList;
}

/// 鸡尾酒排序（双向冒泡排序）
List<T> cocktailShakerSort<T extends Comparable>(List<T> list) {
  final sortedList = List<T>.from(list);
  int left = 0;
  int right = sortedList.length - 1;
  bool swapped;

  while (left < right) {
    swapped = false;

    // 从左向右冒泡
    for (int i = left; i < right; i++) {
      if (sortedList[i].compareTo(sortedList[i + 1]) > 0) {
        final temp = sortedList[i];
        sortedList[i] = sortedList[i + 1];
        sortedList[i + 1] = temp;
        swapped = true;
      }
    }
    if (!swapped) break;
    right--;

    swapped = false;

    // 从右向左冒泡
    for (int i = right; i > left; i--) {
      if (sortedList[i - 1].compareTo(sortedList[i]) > 0) {
        final temp = sortedList[i - 1];
        sortedList[i - 1] = sortedList[i];
        sortedList[i] = temp;
        swapped = true;
      }
    }
    if (!swapped) break;
    left++;
  }

  return sortedList;
}

// 测试函数
void main() {
  print('===== 冒泡排序算法演示 =====\n');

  // 测试数据
  final numbers = [64, 34, 25, 12, 22, 11, 90];
  print('原始数组: $numbers\n');

  // 基础冒泡排序
  final sorted1 = bubbleSort(numbers);
  print('基础冒泡排序: $sorted1');

  // 优化版冒泡排序
  final sorted2 = bubbleSortOptimized(numbers);
  print('优化冒泡排序: $sorted2');

  // 边界优化版
  final sorted3 = bubbleSortWithBoundary(numbers);
  print('边界优化版: $sorted3');

  // 鸡尾酒排序
  final sorted4 = cocktailShakerSort(numbers);
  print('鸡尾酒排序: $sorted4\n');

  // 性能测试
  print('===== 性能测试 =====');
  final random = Random(42);
  final largeList = List.generate(1000, (_) => random.nextInt(10000));

  final stopwatch = Stopwatch()..start();
  bubbleSort(largeList);
  stopwatch.stop();
  print('基础冒泡排序 (1000元素): ${stopwatch.elapsedMicroseconds} μs');

  stopwatch.reset();
  stopwatch.start();
  bubbleSortOptimized(largeList);
  stopwatch.stop();
  print('优化冒泡排序 (1000元素): ${stopwatch.elapsedMicroseconds} μs');

  stopwatch.reset();
  stopwatch.start();
  bubbleSortWithBoundary(largeList);
  stopwatch.stop();
  print('边界优化版 (1000元素): ${stopwatch.elapsedMicroseconds} μs');

  stopwatch.reset();
  stopwatch.start();
  cocktailShakerSort(largeList);
  stopwatch.stop();
  print('鸡尾酒排序 (1000元素): ${stopwatch.elapsedMicroseconds} μs');

  // 字符串排序示例
  print('\n===== 字符串排序示例 =====');
  final words = ['banana', 'apple', 'orange', 'grape', 'pear'];
  print('原始字符串: $words');
  print('排序后: ${bubbleSort(words)}');
}