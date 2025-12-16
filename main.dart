import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);
  runApp(const TuyapApp());
}

class ThemeModeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool _showGraphs = true;
  SharedPreferences? _prefs;

  bool get isDarkMode => _isDarkMode;
  bool get showGraphs => _showGraphs;

  ThemeModeProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs?.getBool('isDarkMode') ?? false;
    _showGraphs = _prefs?.getBool('showGraphs') ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _prefs?.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  Future<void> toggleGraphs() async {
    _showGraphs = !_showGraphs;
    await _prefs?.setBool('showGraphs', _showGraphs);
    notifyListeners();
  }

}

class TransactionEntry {
  final String id;
  final double amount;
  final bool isIncome;
  final String description;
  final DateTime timestamp;

  TransactionEntry({
    String? id,
    required this.amount,
    required this.isIncome,
    required this.description,
    required this.timestamp,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'isIncome': isIncome,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
  };

  factory TransactionEntry.fromJson(Map<String, dynamic> json) => TransactionEntry(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    amount: json['amount'],
    isIncome: json['isIncome'],
    description: json['description'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}




class TuyapData extends ChangeNotifier {
  double totalIncome = 0.0;
  double todayIncome = 0.0;
  String lastAdditionTime = '';
  List<TransactionEntry> transactionHistory = [];
  SharedPreferences? _prefs;
  
  // Cache için
  Map<int, double>? _cachedWeeklyData;
  Map<int, double>? _cachedMonthlyData;
  Map<int, double>? _cachedAllTimeData;
  DateTime? _lastCacheUpdate;

  TuyapData() {
    _loadData();
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();
    totalIncome = _prefs?.getDouble('totalIncome') ?? 0.0;
    lastAdditionTime = _prefs?.getString('lastAdditionTime') ?? DateFormat('HH:mm').format(DateTime.now());
    
    final String? transactionsJson = _prefs?.getString('transactionHistory');
    if (transactionsJson != null && transactionsJson.isNotEmpty) {
      try {
        transactionHistory = (json.decode(transactionsJson) as List)
            .map((item) => TransactionEntry.fromJson(item))
            .toList();
      } catch (e) {
        transactionHistory = [];
      }
    }
    
    // Bugünkü geliri HER ZAMAN transaction history'den hesapla
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    todayIncome = 0.0;
    
    for (var transaction in transactionHistory) {
      final transactionDate = DateTime(
        transaction.timestamp.year,
        transaction.timestamp.month,
        transaction.timestamp.day,
      );
      
      if (transactionDate == today) {
        if (transaction.isIncome) {
          todayIncome += transaction.amount;
        } else {
          todayIncome -= transaction.amount;
        }
      }
    }
    
    todayIncome = todayIncome.clamp(0.0, double.infinity);
    
    // Bugünkü geliri kaydet
    await _prefs?.setDouble('todayIncome', todayIncome);
    
    notifyListeners();
  }

  Future<void> _saveData() async {
    // Cache'i temizle
    _invalidateCache();
    
    await _prefs?.setDouble('totalIncome', totalIncome);
    await _prefs?.setDouble('todayIncome', todayIncome);
    await _prefs?.setString('lastAdditionTime', lastAdditionTime);
    await _prefs?.setString('transactionHistory', 
        json.encode(transactionHistory.map((t) => t.toJson()).toList()));
  }

  // Cache'i temizle
  void _invalidateCache() {
    _cachedWeeklyData = null;
    _cachedMonthlyData = null;
    _cachedAllTimeData = null;
    _lastCacheUpdate = null;
  }

  void addIncome(double amount, String description, [DateTime? customDate]) {
    final date = customDate ?? DateTime.now();
    totalIncome += amount;
    
    // Sadece bugünün tarihi seçildiyse bugünkü gelire ekle
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      todayIncome += amount;
    }
    
    lastAdditionTime = DateFormat('HH:mm').format(date);
    transactionHistory.insert(0, TransactionEntry(
      amount: amount,
      isIncome: true,
      description: description,
      timestamp: date,
    ));
    if (transactionHistory.length > 100) {
      transactionHistory = transactionHistory.sublist(0, 100);
    }
    _saveData();
    notifyListeners();
  }

  void removeIncome(double amount, String description, [DateTime? customDate]) {
    final date = customDate ?? DateTime.now();
    totalIncome = (totalIncome - amount).clamp(0.0, double.infinity);
    
    // Sadece bugünün tarihi seçildiyse bugünkü gelirden çıkar
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      todayIncome = (todayIncome - amount).clamp(0.0, double.infinity);
    }
    
    lastAdditionTime = DateFormat('HH:mm').format(date);
    transactionHistory.insert(0, TransactionEntry(
      amount: amount,
      isIncome: false,
      description: description,
      timestamp: date,
    ));
    if (transactionHistory.length > 100) {
      transactionHistory = transactionHistory.sublist(0, 100);
    }
    _saveData();
    notifyListeners();
  }

  Future<void> deleteTransaction(String transactionId) async {
    // İşlemi bul
    final transaction = transactionHistory.firstWhere((t) => t.id == transactionId);
    
    // İşlemi listeden sil
    transactionHistory.removeWhere((t) => t.id == transactionId);
    
    // Tüm istatistikleri yeniden hesapla (daha güvenilir)
    _recalculateAllStatistics();
    
    // Son işlem zamanını güncelle
    lastAdditionTime = DateFormat('HH:mm').format(DateTime.now());
    
    // Cache'i temizle (grafikler yeniden hesaplansın)
    _invalidateCache();
    
    // Verileri kaydet
    await _saveData();
    
    // UI'ı güncelle
    notifyListeners();
  }

  // Tüm istatistikleri sıfırdan hesapla
  void _recalculateAllStatistics() {
    // Sıfırla
    totalIncome = 0.0;
    todayIncome = 0.0;
    
    // Bugünün tarihini al
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Tüm işlemleri gez ve yeniden hesapla
    for (var transaction in transactionHistory) {
      final transactionDate = DateTime(
        transaction.timestamp.year,
        transaction.timestamp.month,
        transaction.timestamp.day,
      );
      
      if (transaction.isIncome) {
        // Gelir ise ekle
        totalIncome += transaction.amount;
        
        // Bugünün işlemiyse bugünkü gelire de ekle
        if (transactionDate == today) {
          todayIncome += transaction.amount;
        }
      } else {
        // Gider ise çıkar
        totalIncome -= transaction.amount;
        
        // Bugünün işlemiyse bugünkü gelirden de çıkar
        if (transactionDate == today) {
          todayIncome -= transaction.amount;
        }
      }
    }
    
    // Negatif değerleri engelle
    totalIncome = totalIncome.clamp(0.0, double.infinity);
    todayIncome = todayIncome.clamp(0.0, double.infinity);
  }

  Future<void> clearAllData() async {
    totalIncome = 0.0;
    todayIncome = 0.0;
    lastAdditionTime = DateFormat('HH:mm').format(DateTime.now());
    transactionHistory = [];
    _invalidateCache();
    await _prefs?.clear();
    notifyListeners();
  }

  // Cache kullanımı ile optimize edilmiş grafik dataları
  Map<int, double> getWeeklyData() {
    if (_cachedWeeklyData != null && _lastCacheUpdate != null) {
      final now = DateTime.now();
      if (now.difference(_lastCacheUpdate!).inMinutes < 5) {
        return _cachedWeeklyData!;
      }
    }

    final now = DateTime.now();
    final weeklyData = <int, double>{};
    final monday = now.subtract(Duration(days: now.weekday - 1));
    
    double runningTotal = 0.0;
    
    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      
      // Eğer gelecek bir tarihse 0 göster
      if (date.isAfter(DateTime(now.year, now.month, now.day, 23, 59))) {
        weeklyData[i] = runningTotal; // Bugünkü değeri tut
        continue;
      }
      
      final dayTransactions = transactionHistory.where((t) =>
          t.timestamp.year == date.year &&
          t.timestamp.month == date.month &&
          t.timestamp.day == date.day);
      
      final dayNet = dayTransactions.fold(0.0, (sum, t) {
        return sum + (t.isIncome ? t.amount : -t.amount);
      });
      
      runningTotal += dayNet;
      weeklyData[i] = runningTotal;
    }
    
    _cachedWeeklyData = weeklyData;
    _lastCacheUpdate = now;
    return weeklyData;
  }

  Map<int, double> getMonthlyData() {
    if (_cachedMonthlyData != null && _lastCacheUpdate != null) {
      final now = DateTime.now();
      if (now.difference(_lastCacheUpdate!).inMinutes < 5) {
        return _cachedMonthlyData!;
      }
    }

    final now = DateTime.now();
    final monthlyData = <int, double>{};
    
    double runningTotal = 0.0;
    
    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: 29 - i));
      
      // Eğer gelecek bir tarihse bugünkü değeri tut
      if (date.isAfter(DateTime(now.year, now.month, now.day, 23, 59))) {
        monthlyData[i] = runningTotal;
        continue;
      }
      
      final dayTransactions = transactionHistory.where((t) =>
          t.timestamp.year == date.year &&
          t.timestamp.month == date.month &&
          t.timestamp.day == date.day);
      
      final dayNet = dayTransactions.fold(0.0, (sum, t) {
        return sum + (t.isIncome ? t.amount : -t.amount);
      });
      
      runningTotal += dayNet;
      monthlyData[i] = runningTotal;
    }
    
    _cachedMonthlyData = monthlyData;
    _lastCacheUpdate = now;
    return monthlyData;
  }

  Map<int, double> getAllTimeData() {
    if (_cachedAllTimeData != null && _lastCacheUpdate != null) {
      final now = DateTime.now();
      if (now.difference(_lastCacheUpdate!).inMinutes < 5) {
        return _cachedAllTimeData!;
      }
    }

    if (transactionHistory.isEmpty) return {};
    
    final monthlyTotals = <String, double>{};
    
    for (var t in transactionHistory) {
      final key = DateFormat('yyyy-MM').format(t.timestamp);
      monthlyTotals[key] = (monthlyTotals[key] ?? 0) + (t.isIncome ? t.amount : -t.amount);
    }
    
    final sortedKeys = monthlyTotals.keys.toList()..sort();
    
    double runningTotal = 0.0;
    final cumulativeData = <int, double>{};
    
    for (int i = 0; i < sortedKeys.length; i++) {
      runningTotal += monthlyTotals[sortedKeys[i]]!;
      cumulativeData[i] = runningTotal;
    }
    
    _cachedAllTimeData = cumulativeData;
    _lastCacheUpdate = DateTime.now();
    return cumulativeData;
  }
}

class TuyapApp extends StatelessWidget {
  const TuyapApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TuyapData()),
        ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
      ],
      child: Consumer<ThemeModeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Tuyap Gelir Takip',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('tr', 'TR'),
          ],
          locale: const Locale('tr', 'TR'),
          theme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true,
            brightness: themeProvider.isDarkMode ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: themeProvider.isDarkMode 
                ? const Color(0xFF1C1C1E) 
                : const Color(0xFFF5F5F7),
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _HeaderWidget()),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(
                  child: Selector<TuyapData, double>(
                    selector: (_, data) => data.totalIncome,
                    builder: (_, totalIncome, __) => _TotalIncomeCard(totalIncome: totalIncome),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                Consumer<ThemeModeProvider>(
                  builder: (context, themeProvider, _) {
                    if (!themeProvider.showGraphs) return const SliverToBoxAdapter(child: SizedBox.shrink());
                    return SliverToBoxAdapter(
                      child: Consumer<TuyapData>(
                        builder: (_, tuyapData, __) => _ChartCard(tuyapData: tuyapData),
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Selector<TuyapData, ({double todayIncome, double totalIncome, List<TransactionEntry> transactions})>(
                    selector: (_, data) => (
                      todayIncome: data.todayIncome,
                      totalIncome: data.totalIncome,
                      transactions: data.transactionHistory.take(10).toList(),
                    ),
                    builder: (_, data, __) => _CombinedInfoCard(
                      todayIncome: data.todayIncome,
                      totalIncome: data.totalIncome,
                      transactions: data.transactions,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
            const _BottomNavBar(),
          ],
        ),
      ),
    );
  }
}

class _HeaderWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = context.read<ThemeModeProvider>();
    final now = DateTime.now();
    final dateText = DateFormat('d MMMM', 'tr_TR').format(now);
    final dayText = DateFormat('EEEE', 'tr_TR').format(now);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateText, style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
              )),
              const SizedBox(height: 4),
              Text(dayText, style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              )),
            ],
          ),
          Row(
            children: [
              _IconButton(
                icon: isDark ? Icons.light_mode : Icons.dark_mode,
                onTap: themeProvider.toggleTheme,
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              _IconButton(
                icon: Icons.settings_outlined,
                onTap: () => Navigator.push(context, 
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _IconButton({required this.icon, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )],
        ),
        child: Icon(icon, color: isDark ? Colors.grey[400] : Colors.grey[700], size: 22),
      ),
    );
  }
}

class _TotalIncomeCard extends StatelessWidget {
  final double totalIncome;
  const _TotalIncomeCard({required this.totalIncome});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF007AFF), const Color(0xFF0051D5)]
              : [const Color(0xFF007AFF), const Color(0xFF0062FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007AFF).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Toplam Kazancınız',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.85),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '₺${NumberFormat('#,##0', 'tr_TR').format(totalIncome)}',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatefulWidget {
  final TuyapData tuyapData;
  const _ChartCard({required this.tuyapData});

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> with AutomaticKeepAliveClientMixin {
  int _period = 0; // 0: Günlük, 1: Haftalık, 2: Aylık, 3: Tüm

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Map<int, double> data;
    String title;
    List<String> labels;

    switch (_period) {
      case 0:
        // Günlük: Son 7 gün
        data = widget.tuyapData.getWeeklyData();
        title = 'Son 7 Gün';
        labels = List.generate(7, (i) {
          final now = DateTime.now();
          final monday = now.subtract(Duration(days: now.weekday - 1));
          final date = monday.add(Duration(days: i));
          return DateFormat('EEE', 'tr_TR').format(date).substring(0, 3);
        });
        break;
      case 1:
        // Aylık: Son 30 gün
        data = widget.tuyapData.getMonthlyData();
        title = 'Son 30 Gün';
        labels = List.generate(6, (i) {
          final date = DateTime.now().subtract(Duration(days: 29 - (i * 5)));
          return DateFormat('d').format(date);
        });
        break;
      default:
        // Tüm zamanlar
        data = widget.tuyapData.getAllTimeData();
        title = 'Tüm Zamanlar';
        labels = [];
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık - Daha zarif
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 16),
          
          // Periyot butonları - Zarif chipler
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ChartPeriodChip('Hafta', 0, _period == 0, isDark, () => setState(() => _period = 0)),
                const SizedBox(width: 8),
                _ChartPeriodChip('Ay', 1, _period == 1, isDark, () => setState(() => _period = 1)),
                const SizedBox(width: 8),
                _ChartPeriodChip('Tümü', 2, _period == 2, isDark, () => setState(() => _period = 2)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Grafik
          data.isEmpty
              ? SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      'Henüz veri yok',
                      style: TextStyle(
                        color: isDark ? Colors.grey[600] : Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : RepaintBoundary(
                  child: SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: null,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: value == 0 
                                ? (isDark ? Colors.white.withOpacity(0.2) : Colors.grey.withOpacity(0.3))
                                : (isDark 
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.grey.withOpacity(0.1)),
                            strokeWidth: value == 0 ? 2 : 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= labels.length) return const Text('');
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  labels[idx],
                                  style: TextStyle(
                                    color: isDark ? Colors.grey[600] : Colors.grey[500],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                          )),
                          leftTitles: AxisTitles(sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            interval: null,
                            getTitlesWidget: (value, meta) {
                              final absValue = value.abs();
                              final sign = value < 0 ? '-' : '';
                              return Text(
                                absValue >= 1000 
                                    ? '$sign${(absValue/1000).toStringAsFixed(0)}k' 
                                    : '$sign${absValue.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: isDark ? Colors.grey[600] : Colors.grey[500],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
                          )),
                        ),
                        borderData: FlBorderData(show: false),
                        minX: 0,
                        maxX: (data.length - 1).toDouble(),
                        minY: () {
                          if (data.values.isEmpty) return 0.0;
                          final minValue = data.values.reduce((a, b) => a < b ? a : b);
                          // Negatifse, %15 daha aşağı git
                          return (minValue < 0 ? minValue * 1.15 : 0.0).toDouble();
                        }(),
                        maxY: () {
                          if (data.values.isEmpty) return 100.0;
                          final maxValue = data.values.reduce((a, b) => a > b ? a : b);
                          // Pozitifse %15 daha yukarı, negatifse 0'a kadar göster
                          return (maxValue > 0 ? maxValue * 1.15 : maxValue * 0.85).toDouble();
                        }(),
                        lineBarsData: [
                          LineChartBarData(
                            spots: data.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                            isCurved: true,
                            curveSmoothness: 0.35,
                            color: const Color(0xFF007AFF),
                            barWidth: 3,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) {
                                return FlDotCirclePainter(
                                  radius: 4,
                                  color: const Color(0xFF007AFF),
                                  strokeWidth: 2,
                                  strokeColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                );
                              },
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              cutOffY: 0, // 0 çizgisinden itibaren gradient
                              applyCutOffY: true,
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF007AFF).withOpacity(0.15),
                                  const Color(0xFF007AFF).withOpacity(0.05),
                                  const Color(0xFF007AFF).withOpacity(0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            aboveBarData: BarAreaData(
                              show: false,
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            tooltipBgColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                            tooltipBorder: BorderSide(
                              color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                              width: 1,
                            ),
                            tooltipRoundedRadius: 8,
                            getTooltipItems: (spots) => spots.map((spot) => LineTooltipItem(
                              '₺${NumberFormat('#,##0', 'tr_TR').format(spot.y)}',
                              TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// Zarif grafik periyot chip'i
class _ChartPeriodChip extends StatelessWidget {
  final String label;
  final int index;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ChartPeriodChip(this.label, this.index, this.isSelected, this.isDark, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF)
              : (isDark ? const Color(0xFF2C2C2E) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF007AFF)
                : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey[400] : Colors.grey[700]),
          ),
        ),
      ),
    );
  }
}



class _CombinedInfoCard extends StatelessWidget {
  final double todayIncome;
  final double totalIncome;
  final List<TransactionEntry> transactions;

  const _CombinedInfoCard({
    required this.todayIncome,
    required this.totalIncome,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Son 30 günün işlemlerini filtrele
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final recentTransactions = transactions
        .where((t) => t.timestamp.isAfter(thirtyDaysAgo))
        .take(8)
        .toList();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Son İşlemler',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Son 30 gün',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // İşlem listesi
          if (recentTransactions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 48,
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Henüz işlem yok',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[600] : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...recentTransactions.asMap().entries.map((entry) {
              final index = entry.key;
              final transaction = entry.value;
              return Column(
                children: [
                  _RecentTransactionItem(
                    transaction: transaction,
                    isDark: isDark,
                  ),
                  if (index < recentTransactions.length - 1)
                    Divider(
                      height: 24,
                      thickness: 1,
                      color: isDark 
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.1),
                    ),
                ],
              );
            }).toList(),
        ],
      ),
    );
  }
}

// Yeni zarif işlem item'ı
class _RecentTransactionItem extends StatelessWidget {
  final TransactionEntry transaction;
  final bool isDark;

  const _RecentTransactionItem({
    required this.transaction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM, HH:mm', 'tr_TR').format(transaction.timestamp);
    final color = transaction.isIncome ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
    final icon = transaction.isIncome ? Icons.add_circle_outline : Icons.remove_circle_outline;
    final prefix = transaction.isIncome ? '+' : '-';
    
    return Row(
      children: [
        // İkon
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        
        // Bilgiler
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.description.isEmpty 
                    ? (transaction.isIncome ? 'Gelir' : 'Gider')
                    : transaction.description,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: transaction.description.isEmpty 
                      ? color 
                      : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[600] : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
        
        // Tutar
        Text(
          '$prefix₺${NumberFormat('#,##0', 'tr_TR').format(transaction.amount)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar();

  @override
  Widget build(BuildContext context) {
    final tuyapData = context.read<TuyapData>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )],
        ),
        child: Row(
          children: [
            Expanded(child: _ActionButton(
              icon: Icons.add,
              label: 'Ekle',
              color: const Color(0xFF34C759),
              onTap: () => _showDialog(context, true, tuyapData),
            )),
            const SizedBox(width: 12),
            Expanded(child: _ActionButton(
              icon: Icons.remove,
              label: 'Çıkar',
              color: const Color(0xFFFF3B30),
              onTap: () => _showDialog(context, false, tuyapData),
            )),
          ],
        ),
      ),
    );
  }

  void _showDialog(BuildContext context, bool isAdd, TuyapData data) {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isAdd ? const Color(0xFF34C759) : const Color(0xFFFF3B30))
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isAdd ? Icons.add_circle_outline : Icons.remove_circle_outline,
                        color: isAdd ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(isAdd ? 'Gelir Ekle' : 'Gider Çıkar',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1C1C1E))),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
                  decoration: InputDecoration(
                    labelText: 'Tutar',
                    hintText: '0.00',
                    prefixText: '₺',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Açıklama (İsteğe bağlı)',
                    hintText: 'Örn: Günlük kazanç',
                    prefixIcon: const Icon(Icons.description_outlined),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      locale: const Locale('tr', 'TR'),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, 
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          size: 20),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('d MMMM yyyy', 'tr_TR').format(selectedDate),
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('İptal', style: TextStyle(fontSize: 16,
                          color: isDark ? Colors.grey[400] : Colors.grey[700])),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final amount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0.0;
                        if (amount > 0) {
                          if (isAdd) {
                            data.addIncome(amount, descController.text.trim(), selectedDate);
                          } else {
                            data.removeIncome(amount, descController.text.trim(), selectedDate);
                          }
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Row(
                              children: [
                                Icon(isAdd ? Icons.check_circle : Icons.remove_circle, 
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 12),
                                Text('₺${NumberFormat('#,##0', 'tr_TR').format(amount)} '
                                    '${isAdd ? "eklendi" : "çıkarıldı"}!'),
                              ],
                            ),
                            backgroundColor: isAdd ? const Color(0xFF34C759) 
                                : const Color(0xFFFF3B30),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            duration: const Duration(seconds: 2),
                          ));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAdd ? const Color(0xFF34C759) 
                            : const Color(0xFFFF3B30),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(isAdd ? 'Ekle' : 'Çıkar',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = context.watch<ThemeModeProvider>();
    final tuyapData = context.read<TuyapData>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  _IconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 16),
                  Text('Ayarlar', style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  )),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _SectionTitle('Görünüm', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.palette_outlined,
                    title: 'Karanlık Mod',
                    isDark: isDark,
                    trailing: Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (_) => themeProvider.toggleTheme(),
                      activeColor: const Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('İstatistik & Raporlar', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.bar_chart_outlined,
                    title: 'Grafik Gösterimi',
                    isDark: isDark,
                    trailing: Switch(
                      value: themeProvider.showGraphs,
                      onChanged: (_) => themeProvider.toggleGraphs(),
                      activeColor: const Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('Destek & İletişim', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.email_outlined,
                    title: 'Bize Ulaşın',
                    isDark: isDark,
                    onTap: () async {
                      final uri = Uri(
                        scheme: 'mailto',
                        path: 'muhametkoc@gmail.com',
                        query: 'subject=Tuyap Uygulama Desteği',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.star_outline,
                    title: 'Uygulamayı Değerlendir',
                    isDark: isDark,
                    onTap: () async {
                      final uri = Uri.parse(
                          'https://play.google.com/store/apps/details?id=com.tuyap.gelirtakip');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.ios_share,
                    title: 'Uygulamayı Paylaş',
                    isDark: isDark,
                    onTap: () => Share.share(
                      'Tuyap Gelir Takip uygulamasını deneyin!\n'
                      'https://play.google.com/store/apps/details?id=com.tuyap.gelirtakip'),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('Veri Yönetimi', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.delete_outline,
                    title: 'Tüm Verileri Sil',
                    isDark: isDark,
                    isDestructive: true,
                    onTap: () => _showClearDialog(context, tuyapData),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('Hakkında', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.info_outline,
                    title: 'Uygulama Versiyonu',
                    isDark: isDark,
                    trailing: Text('1.0.1', style: TextStyle(
                      fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  void _showClearDialog(BuildContext context, TuyapData data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B30), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Tüm Verileri Sil', style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E))),
            ),
          ],
        ),
        content: Text('Tüm veriler silinecek. Bu işlem geri alınamaz!',
            style: TextStyle(fontSize: 16, 
                color: isDark ? Colors.grey[400] : Colors.grey[700])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal', style: TextStyle(
                fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[700])),
          ),
          ElevatedButton(
            onPressed: () async {
              await data.clearAllData();
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 20),
                      SizedBox(width: 12),
                      Text('Tüm veriler silindi'),
                    ],
                  ),
                  backgroundColor: Color(0xFF34C759),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                  duration: Duration(seconds: 2),
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionTitle(this.title, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.grey[500] : Colors.grey[600],
      )),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.isDark,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isDestructive ? const Color(0xFFFF3B30) : const Color(0xFF007AFF))
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, 
                  color: isDestructive ? const Color(0xFFFF3B30) : const Color(0xFF007AFF), 
                  size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDestructive ? const Color(0xFFFF3B30) 
                    : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
              )),
            ),
            if (trailing != null) trailing!,
            if (onTap != null && trailing == null)
              Icon(Icons.arrow_forward_ios, size: 16, 
                  color: isDark ? Colors.grey[600] : Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
