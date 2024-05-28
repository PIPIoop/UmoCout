import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class TimetableGroup extends StatefulWidget {
  final String selectedGroup;
  final List<String> directions;

  const TimetableGroup({Key? key, required this.selectedGroup, required this.directions}) : super(key: key);

  @override
  _TimetableGroupState createState() => _TimetableGroupState();
}

class _TimetableGroupState extends State<TimetableGroup> {
  late Future<List<Map<String, dynamic>>> _futureGroupSchedule;
  List<String> _groups = [];

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _futureGroupSchedule = fetchGroupSchedule(widget.selectedGroup);
  }

  Future<Map<String, dynamic>> _loadConfig() async {
    final String jsonString = await DefaultAssetBundle.of(context).loadString('assets/config.json');
    return jsonDecode(jsonString);
  }

  Future<void> fetchGroups(String directionId) async {
    try {
      final config = await _loadConfig();
      final response = await http.get(Uri.parse('${config['baseUrl']}:${config['port']}/group_name/$directionId'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print(data);
        if (data.isNotEmpty) {
          setState(() {
            _groups = data.map((item) => item['name'] as String).toList();
          });
        }
      } else {
        throw Exception('Failed to load groups: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching groups: $error');
    }
  }

  Future<List<Map<String, dynamic>>> fetchGroupSchedule(String groupName) async {
    try {
      final config = await _loadConfig();
      final response =
      await http.get(Uri.parse('${config['baseUrl']}:${config['port']}/schedule/group?group_name=$groupName'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          return data.map((item) => item as Map<String, dynamic>).toList();
        } else {
          return [];
        }
      } else {
        throw Exception('Failed to load group schedule: ${response.statusCode}');
      }
    } catch (error) {
      throw Exception('Error fetching group schedule: $error');
    }
  }

  Future<void> deleteScheduleItem(String id) async {
    try {
      final config = await _loadConfig();
      final response = await http.delete(
        Uri.parse('${config['baseUrl']}:${config['port']}/schedule/$id'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _futureGroupSchedule = fetchGroupSchedule(widget.selectedGroup);
        });
      } else {
        throw Exception('Failed to delete schedule item: ${response.statusCode}');
      }
    } catch (error) {
      print('Error deleting schedule item: $error');
    }
  }

  void _onRefreshPressed() {
    setState(() {
      _futureGroupSchedule = fetchGroupSchedule(widget.selectedGroup);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu_book),
              tooltip: 'Выбор направления',
              itemBuilder: (BuildContext context) {
                return widget.directions.map((direction) {
                  return PopupMenuItem<String>(
                    value: direction,
                    child: Text(direction),
                  );
                }).toList();
              },
              onSelected: (String value) async {
                try {
                  await fetchGroups(value);
                } catch (error) {
                  return;
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _onRefreshPressed,
              tooltip: 'Обновить',
            ),
            const Spacer(),
          ],
        ),
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: MediaQuery.of(context).size.width,
              child: _buildGroupColumns(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupColumns() {
  final groupListViewScrollController = ScrollController();

  return Scrollbar(
    interactive: true, // Сделать полосу прокрутки всегда интерактивной
    controller: groupListViewScrollController,
    thickness: 15,
    radius: Radius.circular(40),
    child: ListView(
      scrollDirection: Axis.horizontal,
      controller: groupListViewScrollController,
      children: [
        Row(
          children: [
            Scrollbar(
              interactive: true, // Сделать полосу прокрутки всегда интерактивной
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                itemCount: _groups.length,
                itemBuilder: (BuildContext context, int index) {
                  String groupName = _groups[index];
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchGroupSchedule(groupName),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      } else if (snapshot.hasData && snapshot.data!.isEmpty) {
                        return Center(child: Text('Расписание для группы $groupName не найдено.'));
                      } else {
                        final List<Map<String, dynamic>> schedule = snapshot.data ?? [];

                        final Map<String, List<Map<String, dynamic>>> groupedByDay = {};
                        for (var item in schedule) {
                          String key = '${item['day_of_the_week']}';
                          if (groupedByDay.containsKey(key)) {
                            groupedByDay[key]!.add(item);
                          } else {
                            groupedByDay[key] = [item];
                          }
                        }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Container(
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            width: _calculateGroupWidth(groupName),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  groupName,
                                  style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8.0),
                                ...groupedByDay.entries.map((dayEntry) {
                                  String dayOfWeek = dayEntry.key;
                                  List<Map<String, dynamic>> dayItems = dayEntry.value;

                                  final Map<String, List<Map<String, dynamic>>> groupedByPair = {};
                                  for (var item in dayItems) {
                                    String key = '${item['pair_name']}';
                                    if (groupedByPair.containsKey(key)) {
                                      groupedByPair[key]!.add(item);
                                    } else {
                                      groupedByPair[key] = [item];
                                    }
                                  }

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dayOfWeek,
                                        style: const TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                                      ),
                                      ...groupedByPair.entries.map((pairEntry) {
                                        String pairName = pairEntry.key;
                                        List<Map<String, dynamic>> items = pairEntry.value;

                                        return Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$pairName пара',
                                                style: const TextStyle(fontSize: 20.0),
                                              ),
                                              const SizedBox(height: 12.0),
                                              Container(
                                                padding: const EdgeInsets.all(8.0),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8.0),
                                                ),
                                                child: items.any((item) => item['subgroup'] != 'нет разделения' && item['subgroup'] != 'не определена')
                                                    ? Row(
                                                  children: [
                                                    if (items.any((item) => item['subgroup'] == '1'))
                                                      Expanded(
                                                        flex: 1,
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: items
                                                              .where((item) => item['subgroup'] == '1')
                                                              .map((item) => _buildScheduleItem(item, TextAlign.start))
                                                              .toList(),
                                                        ),
                                                      ),
                                                    if (items.any((item) => item['subgroup'] == '2'))
                                                      Expanded(
                                                        flex: 1,
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.end,
                                                          children: items
                                                              .where((item) => item['subgroup'] == '2')
                                                              .map((item) => _buildScheduleItem(item, TextAlign.end))
                                                              .toList(),
                                                        ),
                                                      ),
                                                  ],
                                                )
                                                    : Column(
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: items.map((item) => SizedBox(
                                                    width: 900,
                                                    child: _buildScheduleItem(item, TextAlign.center),
                                                  )).toList(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
      ],
    ),
    );
  }

  Widget _buildScheduleItem(Map<String, dynamic> item, TextAlign textAlign) {
    return Column(
      crossAxisAlignment: textAlign == TextAlign.center ? CrossAxisAlignment.center :
      textAlign == TextAlign.end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: RichText(
                textAlign: textAlign,
                text: TextSpan(
                  children: [
                    WidgetSpan(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 0.0),
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Color.fromARGB(128, 12, 12, 12)),
                          onPressed: () async {
                            await deleteScheduleItem(item['id'].toString());
                          },
                          tooltip: 'Удалить запись:${item['discipline']}',
                          iconSize: 20.0,
                          constraints: const BoxConstraints.tightFor(
                            width: 28.0,
                            height: 28.0,
                          ),
                        ),
                      ),
                    ),
                    TextSpan(
                      text: '${item['discipline'].split(' ').take(item['discipline'].split(' ').length - 1).join(' ')}',
                      style: const TextStyle(fontSize: 20.0, color: Colors.black),
                    ),
                    TextSpan(
                      text: ' ${item['discipline'].split(' ').last}',
                      style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10.0),
        Text(
          'Неделя: ${item['week']}',
          style: const TextStyle(fontSize: 16.0),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          textAlign: textAlign,
        ),
        Text(
          'Аудитория: ${item['classroom']}',
          style: const TextStyle(fontSize: 16.0),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          textAlign: textAlign,
        ),
        Text(
          'Преподаватель: ${item['teacher_name']}',
          style: const TextStyle(fontSize: 16.0),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          textAlign: textAlign,
        ),
      ],
    );
  }



  double _calculateGroupWidth(String groupName) {
    final textWidth = TextPainter(
      text: TextSpan(text: groupName, style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    return textWidth.width + 800.0;
  }
}