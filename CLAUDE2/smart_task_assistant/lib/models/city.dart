/// 城市信息模型
class CityInfo {
  final String name; // 城市名称（中文）
  final String nameEn; // 城市名称（英文，用于API）
  final String province; // 所属省份

  CityInfo({
    required this.name,
    required this.nameEn,
    required this.province,
  });

  /// 从JSON创建
  factory CityInfo.fromJson(Map<String, dynamic> json) {
    return CityInfo(
      name: json['name'] as String,
      nameEn: json['nameEn'] as String,
      province: json['province'] as String,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'nameEn': nameEn,
      'province': province,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CityInfo && other.nameEn == nameEn;
  }

  @override
  int get hashCode => nameEn.hashCode;
}

/// 中国城市列表（按省份分组）
class ChinaCities {
  static final List<CityInfo> cities = [
    // 直辖市
    CityInfo(name: '长沙', nameEn: 'Changsha', province: '湖南'),
    CityInfo(name: '北京', nameEn: 'Beijing', province: '直辖市'),
    CityInfo(name: '上海', nameEn: 'Shanghai', province: '直辖市'),
    CityInfo(name: '天津', nameEn: 'Tianjin', province: '直辖市'),
    CityInfo(name: '重庆', nameEn: 'Chongqing', province: '直辖市'),

    // 广东省
    CityInfo(name: '广州', nameEn: 'Guangzhou', province: '广东省'),
    CityInfo(name: '深圳', nameEn: 'Shenzhen', province: '广东省'),
    CityInfo(name: '珠海', nameEn: 'Zhuhai', province: '广东省'),
    CityInfo(name: '佛山', nameEn: 'Foshan', province: '广东省'),
    CityInfo(name: '东莞', nameEn: 'Dongguan', province: '广东省'),
    CityInfo(name: '惠州', nameEn: 'Huizhou', province: '广东省'),
    CityInfo(name: '中山', nameEn: 'Zhongshan', province: '广东省'),
    CityInfo(name: '江门', nameEn: 'Jiangmen', province: '广东省'),
    CityInfo(name: '汕头', nameEn: 'Shantou', province: '广东省'),
    CityInfo(name: '湛江', nameEn: 'Zhanjiang', province: '广东省'),
    CityInfo(name: '肇庆', nameEn: 'Zhaoqing', province: '广东省'),
    CityInfo(name: '茂名', nameEn: 'Maoming', province: '广东省'),
    CityInfo(name: '揭阳', nameEn: 'Jieyang', province: '广东省'),
    CityInfo(name: '清远', nameEn: 'Qingyuan', province: '广东省'),

    // 江苏省
    CityInfo(name: '南京', nameEn: 'Nanjing', province: '江苏省'),
    CityInfo(name: '苏州', nameEn: 'Suzhou', province: '江苏省'),
    CityInfo(name: '无锡', nameEn: 'Wuxi', province: '江苏省'),
    CityInfo(name: '常州', nameEn: 'Changzhou', province: '江苏省'),
    CityInfo(name: '徐州', nameEn: 'Xuzhou', province: '江苏省'),
    CityInfo(name: '南通', nameEn: 'Nantong', province: '江苏省'),
    CityInfo(name: '扬州', nameEn: 'Yangzhou', province: '江苏省'),
    CityInfo(name: '泰州', nameEn: 'Taizhou', province: '江苏省'),
    CityInfo(name: '镇江', nameEn: 'Zhenjiang', province: '江苏省'),
    CityInfo(name: '盐城', nameEn: 'Yancheng', province: '江苏省'),
    CityInfo(name: '淮安', nameEn: 'Huaian', province: '江苏省'),
    CityInfo(name: '连云港', nameEn: 'Lianyungang', province: '江苏省'),
    CityInfo(name: '宿迁', nameEn: 'Suqian', province: '江苏省'),

    // 浙江省
    CityInfo(name: '杭州', nameEn: 'Hangzhou', province: '浙江省'),
    CityInfo(name: '宁波', nameEn: 'Ningbo', province: '浙江省'),
    CityInfo(name: '温州', nameEn: 'Wenzhou', province: '浙江省'),
    CityInfo(name: '绍兴', nameEn: 'Shaoxing', province: '浙江省'),
    CityInfo(name: '嘉兴', nameEn: 'Jiaxing', province: '浙江省'),
    CityInfo(name: '台州', nameEn: 'Taizhou', province: '浙江省'),
    CityInfo(name: '金华', nameEn: 'Jinhua', province: '浙江省'),
    CityInfo(name: '湖州', nameEn: 'Huzhou', province: '浙江省'),
    CityInfo(name: '衢州', nameEn: 'Quzhou', province: '浙江省'),
    CityInfo(name: '丽水', nameEn: 'Lishui', province: '浙江省'),
    CityInfo(name: '舟山', nameEn: 'Zhoushan', province: '浙江省'),

    // 四川省
    CityInfo(name: '成都', nameEn: 'Chengdu', province: '四川省'),
    CityInfo(name: '绵阳', nameEn: 'Mianyang', province: '四川省'),
    CityInfo(name: '德阳', nameEn: 'Deyang', province: '四川省'),
    CityInfo(name: '宜宾', nameEn: 'Yibin', province: '四川省'),
    CityInfo(name: '南充', nameEn: 'Nanchong', province: '四川省'),
    CityInfo(name: '泸州', nameEn: 'Luzhou', province: '四川省'),
    CityInfo(name: '达州', nameEn: 'Dazhou', province: '四川省'),
    CityInfo(name: '内江', nameEn: 'Neijiang', province: '四川省'),
    CityInfo(name: '乐山', nameEn: 'Leshan', province: '四川省'),
    CityInfo(name: '眉山', nameEn: 'Meishan', province: '四川省'),
    CityInfo(name: '自贡', nameEn: 'Zigong', province: '四川省'),
    CityInfo(name: '广元', nameEn: 'Guangyuan', province: '四川省'),
    CityInfo(name: '遂宁', nameEn: 'Suining', province: '四川省'),
    CityInfo(name: '攀枝花', nameEn: 'Panzhihua', province: '四川省'),
    CityInfo(name: '雅安', nameEn: 'Yaan', province: '四川省'),

    // 湖北省
    CityInfo(name: '武汉', nameEn: 'Wuhan', province: '湖北省'),
    CityInfo(name: '宜昌', nameEn: 'Yichang', province: '湖北省'),
    CityInfo(name: '襄阳', nameEn: 'Xiangyang', province: '湖北省'),
    CityInfo(name: '荆州', nameEn: 'Jingzhou', province: '湖北省'),
    CityInfo(name: '十堰', nameEn: 'Shiyan', province: '湖北省'),
    CityInfo(name: '黄石', nameEn: 'Huangshi', province: '湖北省'),
    CityInfo(name: '鄂州', nameEn: 'Ezhou', province: '湖北省'),
    CityInfo(name: '荆门', nameEn: 'Jingmen', province: '湖北省'),
    CityInfo(name: '孝感', nameEn: 'Xiaogan', province: '湖北省'),
    CityInfo(name: '咸宁', nameEn: 'Xianning', province: '湖北省'),
    CityInfo(name: '黄冈', nameEn: 'Huanggang', province: '湖北省'),
    CityInfo(name: '恩施', nameEn: 'Enshi', province: '湖北省'),

    // 福建省
    CityInfo(name: '福州', nameEn: 'Fuzhou', province: '福建省'),
    CityInfo(name: '厦门', nameEn: 'Xiamen', province: '福建省'),
    CityInfo(name: '泉州', nameEn: 'Quanzhou', province: '福建省'),
    CityInfo(name: '漳州', nameEn: 'Zhangzhou', province: '福建省'),
    CityInfo(name: '莆田', nameEn: 'Putian', province: '福建省'),
    CityInfo(name: '龙岩', nameEn: 'Longyan', province: '福建省'),
    CityInfo(name: '三明', nameEn: 'Sanming', province: '福建省'),
    CityInfo(name: '南平', nameEn: 'Nanping', province: '福建省'),
    CityInfo(name: '宁德', nameEn: 'Ningde', province: '福建省'),

    // 湖南省
    CityInfo(name: '株洲', nameEn: 'Zhuzhou', province: '湖南省'),
    CityInfo(name: '湘潭', nameEn: 'Xiangtan', province: '湖南省'),
    CityInfo(name: '衡阳', nameEn: 'Hengyang', province: '湖南省'),
    CityInfo(name: '邵阳', nameEn: 'Shaoyang', province: '湖南省'),
    CityInfo(name: '岳阳', nameEn: 'Yueyang', province: '湖南省'),
    CityInfo(name: '常德', nameEn: 'Changde', province: '湖南省'),
    CityInfo(name: '张家界', nameEn: 'Zhangjiajie', province: '湖南省'),
    CityInfo(name: '益阳', nameEn: 'Yiyang', province: '湖南省'),
    CityInfo(name: '郴州', nameEn: 'Chenzhou', province: '湖南省'),
    CityInfo(name: '永州', nameEn: 'Yongzhou', province: '湖南省'),
    CityInfo(name: '怀化', nameEn: 'Huaihua', province: '湖南省'),
    CityInfo(name: '娄底', nameEn: 'Loudi', province: '湖南省'),
    CityInfo(name: '湘西', nameEn: 'Xiangxi', province: '湖南省'),

    // 河南省
    CityInfo(name: '郑州', nameEn: 'Zhengzhou', province: '河南省'),
    CityInfo(name: '洛阳', nameEn: 'Luoyang', province: '河南省'),
    CityInfo(name: '开封', nameEn: 'Kaifeng', province: '河南省'),
    CityInfo(name: '南阳', nameEn: 'Nanyang', province: '河南省'),
    CityInfo(name: '新乡', nameEn: 'Xinxiang', province: '河南省'),
    CityInfo(name: '焦作', nameEn: 'Jiaozuo', province: '河南省'),
    CityInfo(name: '安阳', nameEn: 'Anyang', province: '河南省'),
    CityInfo(name: '濮阳', nameEn: 'Puyang', province: '河南省'),
    CityInfo(name: '许昌', nameEn: 'Xuchang', province: '河南省'),
    CityInfo(name: '平顶山', nameEn: 'Pingdingshan', province: '河南省'),
    CityInfo(name: '漯河', nameEn: 'Luohe', province: '河南省'),
    CityInfo(name: '三门峡', nameEn: 'Sanmenxia', province: '河南省'),
    CityInfo(name: '周口', nameEn: 'Zhoukou', province: '河南省'),
    CityInfo(name: '驻马店', nameEn: 'Zhumadian', province: '河南省'),
    CityInfo(name: '商丘', nameEn: 'Shangqiu', province: '河南省'),
    CityInfo(name: '信阳', nameEn: 'Xinyang', province: '河南省'),
    CityInfo(name: '鹤壁', nameEn: 'Hebi', province: '河南省'),

    // 山东省
    CityInfo(name: '济南', nameEn: 'Jinan', province: '山东省'),
    CityInfo(name: '青岛', nameEn: 'Qingdao', province: '山东省'),
    CityInfo(name: '淄博', nameEn: 'Zibo', province: '山东省'),
    CityInfo(name: '烟台', nameEn: 'Yantai', province: '山东省'),
    CityInfo(name: '潍坊', nameEn: 'Weifang', province: '山东省'),
    CityInfo(name: '临沂', nameEn: 'Linyi', province: '山东省'),
    CityInfo(name: '济宁', nameEn: 'Jining', province: '山东省'),
    CityInfo(name: '泰安', nameEn: 'Taian', province: '山东省'),
    CityInfo(name: '威海', nameEn: 'Weihai', province: '山东省'),
    CityInfo(name: '德州', nameEn: 'Dezhou', province: '山东省'),
    CityInfo(name: '东营', nameEn: 'Dongying', province: '山东省'),
    CityInfo(name: '枣庄', nameEn: 'Zaozhuang', province: '山东省'),
    CityInfo(name: '日照', nameEn: 'Rizhao', province: '山东省'),
    CityInfo(name: '聊城', nameEn: 'Liaocheng', province: '山东省'),
    CityInfo(name: '滨州', nameEn: 'Binzhou', province: '山东省'),
    CityInfo(name: '菏泽', nameEn: 'Heze', province: '山东省'),

    // 河北省
    CityInfo(name: '石家庄', nameEn: 'Shijiazhuang', province: '河北省'),
    CityInfo(name: '唐山', nameEn: 'Tangshan', province: '河北省'),
    CityInfo(name: '秦皇岛', nameEn: 'Qinhuangdao', province: '河北省'),
    CityInfo(name: '邯郸', nameEn: 'Handan', province: '河北省'),
    CityInfo(name: '保定', nameEn: 'Baoding', province: '河北省'),
    CityInfo(name: '张家口', nameEn: 'Zhangjiakou', province: '河北省'),
    CityInfo(name: '承德', nameEn: 'Chengde', province: '河北省'),
    CityInfo(name: '廊坊', nameEn: 'Langfang', province: '河北省'),
    CityInfo(name: '沧州', nameEn: 'Cangzhou', province: '河北省'),
    CityInfo(name: '衡水', nameEn: 'Hengshui', province: '河北省'),
    CityInfo(name: '邢台', nameEn: 'Xingtai', province: '河北省'),

    // 陕西省
    CityInfo(name: '西安', nameEn: 'Xian', province: '陕西省'),
    CityInfo(name: '宝鸡', nameEn: 'Baoji', province: '陕西省'),
    CityInfo(name: '咸阳', nameEn: 'Xianyang', province: '陕西省'),
    CityInfo(name: '渭南', nameEn: 'Weinan', province: '陕西省'),
    CityInfo(name: '汉中', nameEn: 'Hanzhong', province: '陕西省'),
    CityInfo(name: '榆林', nameEn: 'Yulin', province: '陕西省'),
    CityInfo(name: '延安', nameEn: 'Yanan', province: '陕西省'),
    CityInfo(name: '安康', nameEn: 'Ankang', province: '陕西省'),
    CityInfo(name: '铜川', nameEn: 'Tongchuan', province: '陕西省'),
    CityInfo(name: '商洛', nameEn: 'Shangluo', province: '陕西省'),

    // 辽宁省
    CityInfo(name: '沈阳', nameEn: 'Shenyang', province: '辽宁省'),
    CityInfo(name: '大连', nameEn: 'Dalian', province: '辽宁省'),
    CityInfo(name: '鞍山', nameEn: 'Anshan', province: '辽宁省'),
    CityInfo(name: '抚顺', nameEn: 'Fushun', province: '辽宁省'),
    CityInfo(name: '本溪', nameEn: 'Benxi', province: '辽宁省'),
    CityInfo(name: '丹东', nameEn: 'Dandong', province: '辽宁省'),
    CityInfo(name: '锦州', nameEn: 'Jinzhou', province: '辽宁省'),
    CityInfo(name: '营口', nameEn: 'Yingkou', province: '辽宁省'),
    CityInfo(name: '阜新', nameEn: 'Fuxin', province: '辽宁省'),
    CityInfo(name: '辽阳', nameEn: 'Liaoyang', province: '辽宁省'),
    CityInfo(name: '盘锦', nameEn: 'Panjin', province: '辽宁省'),
    CityInfo(name: '铁岭', nameEn: 'Tieling', province: '辽宁省'),
    CityInfo(name: '朝阳', nameEn: 'Chaoyang', province: '辽宁省'),
    CityInfo(name: '葫芦岛', nameEn: 'Huludao', province: '辽宁省'),

    // 黑龙江省
    CityInfo(name: '哈尔滨', nameEn: 'Harbin', province: '黑龙江省'),
    CityInfo(name: '齐齐哈尔', nameEn: 'Qiqihar', province: '黑龙江省'),
    CityInfo(name: '鸡西', nameEn: 'Jixi', province: '黑龙江省'),
    CityInfo(name: '鹤岗', nameEn: 'Hegang', province: '黑龙江省'),
    CityInfo(name: '双鸭山', nameEn: 'Shuangyashan', province: '黑龙江省'),
    CityInfo(name: '大庆', nameEn: 'Daqing', province: '黑龙江省'),
    CityInfo(name: '伊春', nameEn: 'Yichun', province: '黑龙江省'),
    CityInfo(name: '佳木斯', nameEn: 'Jiamusi', province: '黑龙江省'),
    CityInfo(name: '七台河', nameEn: 'Qitaihe', province: '黑龙江省'),
    CityInfo(name: '牡丹江', nameEn: 'Mudanjiang', province: '黑龙江省'),
    CityInfo(name: '黑河', nameEn: 'Heihe', province: '黑龙江省'),
    CityInfo(name: '绥化', nameEn: 'Suihua', province: '黑龙江省'),
    CityInfo(name: '大兴安岭', nameEn: 'Daxinganling', province: '黑龙江省'),

    // 吉林省
    CityInfo(name: '长春', nameEn: 'Changchun', province: '吉林省'),
    CityInfo(name: '吉林', nameEn: 'Jilin', province: '吉林省'),
    CityInfo(name: '四平', nameEn: 'Siping', province: '吉林省'),
    CityInfo(name: '辽源', nameEn: 'Liaoyuan', province: '吉林省'),
    CityInfo(name: '通化', nameEn: 'Tonghua', province: '吉林省'),
    CityInfo(name: '白山', nameEn: 'Baishan', province: '吉林省'),
    CityInfo(name: '松原', nameEn: 'Songyuan', province: '吉林省'),
    CityInfo(name: '白城', nameEn: 'Baicheng', province: '吉林省'),
    CityInfo(name: '延边', nameEn: 'Yanbian', province: '吉林省'),

    // 安徽省
    CityInfo(name: '合肥', nameEn: 'Hefei', province: '安徽省'),
    CityInfo(name: '芜湖', nameEn: 'Wuhu', province: '安徽省'),
    CityInfo(name: '蚌埠', nameEn: 'Bengbu', province: '安徽省'),
    CityInfo(name: '淮南', nameEn: 'Huainan', province: '安徽省'),
    CityInfo(name: '马鞍山', nameEn: 'Maanshan', province: '安徽省'),
    CityInfo(name: '淮北', nameEn: 'Huaibei', province: '安徽省'),
    CityInfo(name: '铜陵', nameEn: 'Tongling', province: '安徽省'),
    CityInfo(name: '安庆', nameEn: 'Anqing', province: '安徽省'),
    CityInfo(name: '黄山', nameEn: 'Huangshan', province: '安徽省'),
    CityInfo(name: '滁州', nameEn: 'Chuzhou', province: '安徽省'),
    CityInfo(name: '阜阳', nameEn: 'Fuyang', province: '安徽省'),
    CityInfo(name: '宿州', nameEn: 'Suzhou', province: '安徽省'),
    CityInfo(name: '六安', nameEn: 'Luan', province: '安徽省'),
    CityInfo(name: '亳州', nameEn: 'Bozhou', province: '安徽省'),
    CityInfo(name: '池州', nameEn: 'Chizhou', province: '安徽省'),
    CityInfo(name: '宣城', nameEn: 'Xuancheng', province: '安徽省'),

    // 山西省
    CityInfo(name: '太原', nameEn: 'Taiyuan', province: '山西省'),
    CityInfo(name: '大同', nameEn: 'Datong', province: '山西省'),
    CityInfo(name: '阳泉', nameEn: 'Yangquan', province: '山西省'),
    CityInfo(name: '长治', nameEn: 'Changzhi', province: '山西省'),
    CityInfo(name: '晋城', nameEn: 'Jincheng', province: '山西省'),
    CityInfo(name: '朔州', nameEn: 'Shuozhou', province: '山西省'),
    CityInfo(name: '晋中', nameEn: 'Jinzhong', province: '山西省'),
    CityInfo(name: '运城', nameEn: 'Yuncheng', province: '山西省'),
    CityInfo(name: '忻州', nameEn: 'Xinzhou', province: '山西省'),
    CityInfo(name: '临汾', nameEn: 'Linfen', province: '山西省'),
    CityInfo(name: '吕梁', nameEn: 'Lvliang', province: '山西省'),

    // 江西省
    CityInfo(name: '南昌', nameEn: 'Nanchang', province: '江西省'),
    CityInfo(name: '景德镇', nameEn: 'Jingdezhen', province: '江西省'),
    CityInfo(name: '萍乡', nameEn: 'Pingxiang', province: '江西省'),
    CityInfo(name: '九江', nameEn: 'Jiujiang', province: '江西省'),
    CityInfo(name: '新余', nameEn: 'Xinyu', province: '江西省'),
    CityInfo(name: '鹰潭', nameEn: 'Yingtan', province: '江西省'),
    CityInfo(name: '赣州', nameEn: 'Ganzhou', province: '江西省'),
    CityInfo(name: '吉安', nameEn: 'Jian', province: '江西省'),
    CityInfo(name: '宜春', nameEn: 'Yichun', province: '江西省'),
    CityInfo(name: '抚州', nameEn: 'Fuzhou', province: '江西省'),
    CityInfo(name: '上饶', nameEn: 'Shangrao', province: '江西省'),

    // 云南省
    CityInfo(name: '昆明', nameEn: 'Kunming', province: '云南省'),
    CityInfo(name: '曲靖', nameEn: 'Qujing', province: '云南省'),
    CityInfo(name: '玉溪', nameEn: 'Yuxi', province: '云南省'),
    CityInfo(name: '保山', nameEn: 'Baoshan', province: '云南省'),
    CityInfo(name: '昭通', nameEn: 'Zhaotong', province: '云南省'),
    CityInfo(name: '丽江', nameEn: 'Lijiang', province: '云南省'),
    CityInfo(name: '普洱', nameEn: 'Pu\'er', province: '云南省'),
    CityInfo(name: '临沧', nameEn: 'Lincang', province: '云南省'),

    // 贵州省
    CityInfo(name: '贵阳', nameEn: 'Guiyang', province: '贵州省'),
    CityInfo(name: '六盘水', nameEn: 'Liupanshui', province: '贵州省'),
    CityInfo(name: '遵义', nameEn: 'Zunyi', province: '贵州省'),
    CityInfo(name: '安顺', nameEn: 'Anshun', province: '贵州省'),
    CityInfo(name: '毕节', nameEn: 'Bijie', province: '贵州省'),
    CityInfo(name: '铜仁', nameEn: 'Tongren', province: '贵州省'),

    // 广西壮族自治区
    CityInfo(name: '南宁', nameEn: 'Nanning', province: '广西壮族自治区'),
    CityInfo(name: '柳州', nameEn: 'Liuzhou', province: '广西壮族自治区'),
    CityInfo(name: '桂林', nameEn: 'Guilin', province: '广西壮族自治区'),
    CityInfo(name: '梧州', nameEn: 'Wuzhou', province: '广西壮族自治区'),
    CityInfo(name: '北海', nameEn: 'Beihai', province: '广西壮族自治区'),
    CityInfo(name: '防城港', nameEn: 'Fangchenggang', province: '广西壮族自治区'),
    CityInfo(name: '钦州', nameEn: 'Qinzhou', province: '广西壮族自治区'),
    CityInfo(name: '贵港', nameEn: 'Guigang', province: '广西壮族自治区'),
    CityInfo(name: '玉林', nameEn: 'Yulin', province: '广西壮族自治区'),
    CityInfo(name: '百色', nameEn: 'Baise', province: '广西壮族自治区'),
    CityInfo(name: '贺州', nameEn: 'Hezhou', province: '广西壮族自治区'),
    CityInfo(name: '河池', nameEn: 'Hechi', province: '广西壮族自治区'),
    CityInfo(name: '来宾', nameEn: 'Laibin', province: '广西壮族自治区'),
    CityInfo(name: '崇左', nameEn: 'Chongzuo', province: '广西壮族自治区'),

    // 海南省
    CityInfo(name: '海口', nameEn: 'Haikou', province: '海南省'),
    CityInfo(name: '三亚', nameEn: 'Sanya', province: '海南省'),
    CityInfo(name: '三沙', nameEn: 'Sansha', province: '海南省'),
    CityInfo(name: '儋州', nameEn: 'Danzhou', province: '海南省'),
    CityInfo(name: '五指山', nameEn: 'Wuzhishan', province: '海南省'),
    CityInfo(name: '琼海', nameEn: 'Qionghai', province: '海南省'),
    CityInfo(name: '文昌', nameEn: 'Wenchang', province: '海南省'),
    CityInfo(name: '万宁', nameEn: 'Wanning', province: '海南省'),
    CityInfo(name: '东方', nameEn: 'Dongfang', province: '海南省'),

    // 内蒙古自治区
    CityInfo(name: '呼和浩特', nameEn: 'Hohhot', province: '内蒙古自治区'),
    CityInfo(name: '包头', nameEn: 'Baotou', province: '内蒙古自治区'),
    CityInfo(name: '乌海', nameEn: 'Wuhai', province: '内蒙古自治区'),
    CityInfo(name: '赤峰', nameEn: 'Chifeng', province: '内蒙古自治区'),
    CityInfo(name: '通辽', nameEn: 'Tongliao', province: '内蒙古自治区'),
    CityInfo(name: '鄂尔多斯', nameEn: 'Ordos', province: '内蒙古自治区'),
    CityInfo(name: '呼伦贝尔', nameEn: 'Hulunbuir', province: '内蒙古自治区'),
    CityInfo(name: '巴彦淖尔', nameEn: 'Bayannur', province: '内蒙古自治区'),
    CityInfo(name: '乌兰察布', nameEn: 'Ulanqab', province: '内蒙古自治区'),
    CityInfo(name: '兴安盟', nameEn: 'Hinggan', province: '内蒙古自治区'),
    CityInfo(name: '锡林郭勒盟', nameEn: 'Xilingol', province: '内蒙古自治区'),
    CityInfo(name: '阿拉善盟', nameEn: 'Alxa', province: '内蒙古自治区'),

    // 新疆维吾尔自治区
    CityInfo(name: '乌鲁木齐', nameEn: 'Urumqi', province: '新疆维吾尔自治区'),
    CityInfo(name: '克拉玛依', nameEn: 'Karamay', province: '新疆维吾尔自治区'),
    CityInfo(name: '吐鲁番', nameEn: 'Turpan', province: '新疆维吾尔自治区'),
    CityInfo(name: '哈密', nameEn: 'Hami', province: '新疆维吾尔自治区'),
    CityInfo(name: '昌吉', nameEn: 'Changji', province: '新疆维吾尔自治区'),
    CityInfo(name: '博尔塔拉', nameEn: 'Bortala', province: '新疆维吾尔自治区'),
    CityInfo(name: '巴音郭楞', nameEn: 'Bayingolin', province: '新疆维吾尔自治区'),
    CityInfo(name: '阿克苏', nameEn: 'Aksu', province: '新疆维吾尔自治区'),
    CityInfo(name: '克孜勒苏', nameEn: 'Kizilsu', province: '新疆维吾尔自治区'),
    CityInfo(name: '喀什', nameEn: 'Kashgar', province: '新疆维吾尔自治区'),
    CityInfo(name: '和田', nameEn: 'Hotan', province: '新疆维吾尔自治区'),
    CityInfo(name: '伊犁', nameEn: 'Ili', province: '新疆维吾尔自治区'),
    CityInfo(name: '塔城', nameEn: 'Tacheng', province: '新疆维吾尔自治区'),
    CityInfo(name: '阿勒泰', nameEn: 'Altay', province: '新疆维吾尔自治区'),

    // 西藏自治区
    CityInfo(name: '拉萨', nameEn: 'Lhasa', province: '西藏自治区'),
    CityInfo(name: '日喀则', nameEn: 'Shigatse', province: '西藏自治区'),
    CityInfo(name: '昌都', nameEn: 'Chamdo', province: '西藏自治区'),
    CityInfo(name: '林芝', nameEn: 'Nyingchi', province: '西藏自治区'),
    CityInfo(name: '山南', nameEn: 'Shannan', province: '西藏自治区'),
    CityInfo(name: '那曲', nameEn: 'Nagqu', province: '西藏自治区'),

    // 宁夏回族自治区
    CityInfo(name: '银川', nameEn: 'Yinchuan', province: '宁夏回族自治区'),
    CityInfo(name: '石嘴山', nameEn: 'Shizuishan', province: '宁夏回族自治区'),
    CityInfo(name: '吴忠', nameEn: 'Wuzhong', province: '宁夏回族自治区'),
    CityInfo(name: '固原', nameEn: 'Guyuan', province: '宁夏回族自治区'),
    CityInfo(name: '中卫', nameEn: 'Zhongwei', province: '宁夏回族自治区'),

    // 青海省
    CityInfo(name: '西宁', nameEn: 'Xining', province: '青海省'),
    CityInfo(name: '海东', nameEn: 'Haidong', province: '青海省'),

    // 甘肃省
    CityInfo(name: '兰州', nameEn: 'Lanzhou', province: '甘肃省'),
    CityInfo(name: '嘉峪关', nameEn: 'Jiayuguan', province: '甘肃省'),
    CityInfo(name: '金昌', nameEn: 'Jinchang', province: '甘肃省'),
    CityInfo(name: '白银', nameEn: 'Baiyin', province: '甘肃省'),
    CityInfo(name: '天水', nameEn: 'Tianshui', province: '甘肃省'),
    CityInfo(name: '武威', nameEn: 'Wuwei', province: '甘肃省'),
    CityInfo(name: '张掖', nameEn: 'Zhangye', province: '甘肃省'),
    CityInfo(name: '平凉', nameEn: 'Pingliang', province: '甘肃省'),
    CityInfo(name: '酒泉', nameEn: 'Jiuquan', province: '甘肃省'),
    CityInfo(name: '庆阳', nameEn: 'Qingyang', province: '甘肃省'),
    CityInfo(name: '定西', nameEn: 'Dingxi', province: '甘肃省'),
    CityInfo(name: '陇南', nameEn: 'Longnan', province: '甘肃省'),
  ];

  /// 按省份分组城市
  static Map<String, List<CityInfo>> get citiesByProvince {
    final Map<String, List<CityInfo>> grouped = {};
    for (final city in cities) {
      if (!grouped.containsKey(city.province)) {
        grouped[city.province] = [];
      }
      grouped[city.province]!.add(city);
    }
    return grouped;
  }

  /// 搜索城市
  static List<CityInfo> searchCities(String query) {
    if (query.isEmpty) return cities;
    final lowerQuery = query.toLowerCase();
    return cities.where((city) {
      return city.name.toLowerCase().contains(lowerQuery) ||
          city.nameEn.toLowerCase().contains(lowerQuery) ||
          city.province.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// 根据英文名查找城市
  static CityInfo? getCityByNameEn(String nameEn) {
    try {
      return cities.firstWhere((city) => city.nameEn == nameEn);
    } catch (e) {
      return null;
    }
  }
}
