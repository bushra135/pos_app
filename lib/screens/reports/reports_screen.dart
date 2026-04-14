import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sales Analytics',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2A44),
                ),
              ),
              const SizedBox(height: 18),

              Row(
                children: const [
                  Expanded(
                    child: _TopStatCard(
                      icon: Icons.attach_money,
                      iconBg: Color(0xFF4FD1A5),
                      title: 'Today',
                      value: '\$1,247',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _TopStatCard(
                      icon: Icons.trending_up,
                      iconBg: Color(0xFF4C6FFF),
                      title: 'This Week',
                      value: '\$8,432',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _TopStatCard(
                      icon: Icons.shopping_bag_outlined,
                      iconBg: Color(0xFFB14CFF),
                      title: 'Orders',
                      value: '142',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: 'Daily Sales (This Week)',
                child: SizedBox(
                  height: 220,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      maxY: 1600,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: 400,
                        verticalInterval: 1,
                        getDrawingHorizontalLine: (value) {
                          return const FlLine(
                            color: Color(0xFFE8EDF5),
                            strokeWidth: 1,
                          );
                        },
                        getDrawingVerticalLine: (value) {
                          return const FlLine(
                            color: Color(0xFFE8EDF5),
                            strokeWidth: 1,
                          );
                        },
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          left: BorderSide(color: Color(0xFFD9E2EF)),
                          bottom: BorderSide(color: Color(0xFFD9E2EF)),
                          right: BorderSide.none,
                          top: BorderSide.none,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 400,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                  color: Color(0xFF98A2B3),
                                  fontSize: 11,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              const labels = [
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun'
                              ];
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  labels[value.toInt()],
                                  style: const TextStyle(
                                    color: Color(0xFF98A2B3),
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          isCurved: true,
                          color: const Color(0xFF5AC8B5),
                          barWidth: 3,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, bar, index) {
                              return FlDotCirclePainter(
                                radius: 4,
                                color: const Color(0xFF5AC8B5),
                                strokeWidth: 0,
                              );
                            },
                          ),
                          belowBarData: BarAreaData(show: false),
                          spots: const [
                            FlSpot(0, 850),
                            FlSpot(1, 900),
                            FlSpot(2, 1100),
                            FlSpot(3, 980),
                            FlSpot(4, 1350),
                            FlSpot(5, 1580),
                            FlSpot(6, 1450),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: 'Revenue Trends (2026)',
                child: SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      maxY: 22000,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 5500,
                        getDrawingHorizontalLine: (value) {
                          return const FlLine(
                            color: Color(0xFFE8EDF5),
                            strokeWidth: 1,
                          );
                        },
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          left: BorderSide(color: Color(0xFFD9E2EF)),
                          bottom: BorderSide(color: Color(0xFFD9E2EF)),
                          right: BorderSide.none,
                          top: BorderSide.none,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 5500,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                  color: Color(0xFF98A2B3),
                                  fontSize: 11,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              const labels = ['Jan', 'Feb', 'Mar', 'Apr'];
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  labels[value.toInt()],
                                  style: const TextStyle(
                                    color: Color(0xFF98A2B3),
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        _barGroup(0, 12000),
                        _barGroup(1, 14500),
                        _barGroup(2, 18500),
                        _barGroup(3, 21500),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: 'Best Selling Products',
                child: const Column(
                  children: [
                    _ProductProgressRow(
                      title: 'Organic Milk',
                      sold: '245 sold',
                      progress: 1.0,
                    ),
                    SizedBox(height: 14),
                    _ProductProgressRow(
                      title: 'Wheat Bread',
                      sold: '198 sold',
                      progress: 0.80,
                    ),
                    SizedBox(height: 14),
                    _ProductProgressRow(
                      title: 'Fresh Eggs',
                      sold: '167 sold',
                      progress: 0.67,
                    ),
                    SizedBox(height: 14),
                    _ProductProgressRow(
                      title: 'Olive Oil',
                      sold: '142 sold',
                      progress: 0.56,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static BarChartGroupData _barGroup(int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          width: 42,
          borderRadius: BorderRadius.circular(6),
          color: const Color(0xFF5AC8B5),
        ),
      ],
    );
  }
}

class _TopStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String value;

  const _TopStatCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 124,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF98A2B3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              color: Color(0xFF1F2A44),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2A44),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ProductProgressRow extends StatelessWidget {
  final String title;
  final String sold;
  final double progress;

  const _ProductProgressRow({
    required this.title,
    required this.sold,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF4B5565),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              sold,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF98A2B3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: const Color(0xFFE9EEF5),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF49C59D)),
          ),
        ),
      ],
    );
  }
}