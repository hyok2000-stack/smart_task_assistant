import 'package:flutter/material.dart';
import '../models/city.dart';

/// 城市选择对话框
///
/// 支持按省份分组浏览和搜索城市
class CitySelectorDialog extends StatefulWidget {
  final CityInfo? initialSelectedCity;

  const CitySelectorDialog({
    super.key,
    this.initialSelectedCity,
  });

  @override
  State<CitySelectorDialog> createState() => _CitySelectorDialogState();
}

class _CitySelectorDialogState extends State<CitySelectorDialog> {
  late CityInfo? _selectedCity;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _expandedProvinces = [];
  List<CityInfo> _filteredCities = ChinaCities.cities;
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    _selectedCity = widget.initialSelectedCity;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 切换省份展开/收起
  void _toggleProvince(String province) {
    setState(() {
      if (_expandedProvinces.contains(province)) {
        _expandedProvinces.remove(province);
      } else {
        _expandedProvinces.add(province);
      }
    });
  }

  /// 搜索城市
  void _searchCity(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCities = ChinaCities.cities;
        _isSearchMode = false;
      } else {
        _filteredCities = ChinaCities.searchCities(query);
        _isSearchMode = true;
      }
    });
  }

  /// 选择城市
  void _selectCity(CityInfo city) {
    setState(() {
      _selectedCity = city;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxHeight: 600,
          minHeight: 400,
        ),
        width: 400,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.location_city, size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '选择城市',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),

            // 搜索框
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索城市名称...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchCity('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: _searchCity,
            ),
            const SizedBox(height: 16),

            // 当前选择的城市
            if (_selectedCity != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前选择：${_selectedCity!.name}（${_selectedCity!.province}）',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedCity = null;
                        });
                      },
                      child: const Text('清除'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 城市列表
            Expanded(
              child: _buildCityList(),
            ),

            // 确定按钮
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(_selectedCity);
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建城市列表
  Widget _buildCityList() {
    if (_filteredCities.isEmpty) {
      return const Center(
        child: Text(
          '未找到匹配的城市',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_isSearchMode) {
      // 搜索模式：显示所有匹配的城市
      return ListView.builder(
        controller: _scrollController,
        itemCount: _filteredCities.length,
        itemBuilder: (context, index) {
          final city = _filteredCities[index];
          final isSelected = _selectedCity == city;
          return _buildCityTile(city, isSelected);
        },
      );
    } else {
      // 浏览模式：按省份分组
      final groupedCities = ChinaCities.citiesByProvince;
      final provinces = groupedCities.keys.toList()
        ..sort((a, b) => a.compareTo(b));

      return ListView.builder(
        controller: _scrollController,
        itemCount: provinces.length,
        itemBuilder: (context, index) {
          final province = provinces[index];
          final cities = groupedCities[province]!;
          final isExpanded = _expandedProvinces.contains(province);

          return Column(
            children: [
              // 省份标题
              InkWell(
                onTap: () => _toggleProvince(province),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        province,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${cities.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 城市列表
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Column(
                    children: cities.map((city) {
                      final isSelected = _selectedCity == city;
                      return _buildCityTile(city, isSelected);
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          );
        },
      );
    }
  }

  /// 构建城市卡片
  Widget _buildCityTile(CityInfo city, bool isSelected) {
    return InkWell(
      onTap: () => _selectCity(city),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? Colors.blue : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.blue.shade700 : Colors.black87,
                    ),
                  ),
                  Text(
                    city.province,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check, color: Colors.blue.shade700),
          ],
        ),
      ),
    );
  }
}
