import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

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
  var logger = Logger();
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
        logger.i(data);
        if (data.isNotEmpty) {
          setState(() {
            _groups = data.map((item) => item['name'] as String).toList();
          });
        }
      } else {
        throw Exception('Failed to load groups: ${response.statusCode}');
      }
    } catch (error) {
      logger.e('Error fetching groups: $error');
    }
  }

Future<List<Map<String, dynamic>>> fetchGroupSchedule(String groupName) async {
  try {
    final config = await _loadConfig();
    final response = await http.get(Uri.parse('${config['baseUrl']}:${config['port']}/schedule/group/$groupName'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      if (data.isNotEmpty) {
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        return [];
      }
    } else if (response.statusCode == 404) {
      throw Exception('Group schedule not found');
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
      logger.e('Error deleting schedule item: $error');
    }
  }

  Future<void> updateScheduleItem(String id, Map<String, dynamic> updatedItem) async {
    try {
      final config = await _loadConfig();
      final response = await http.put(
        Uri.parse('${config['baseUrl']}:${config['port']}/schedule/update/$id'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(updatedItem),
      );
      if (response.statusCode == 200) {
        setState(() {
          _futureGroupSchedule = fetchGroupSchedule(widget.selectedGroup);
        });
      } else {
        throw Exception('Failed to update schedule item: ${response.statusCode}');
      }
    } catch (error) {
      logger.e('Error updating schedule item: $error');
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

// Время проведения пар по номерам
final Map<int, String> lessonTimes = {
  1: '08:00 – 09:30',
  2: '09:40 – 11:10',
  3: '11:20 – 12:50',
  4: '13:15 – 14:45',
  5: '15:00 – 16:30',
  6: '16:40 – 18:10',
  7: '18:20 – 19:50',
  8: '19:55 – 21:25',
};

// Получаем время проведения пары по её номеру
String _getLessonTime(int? pairNumber) {
  if (pairNumber != null && lessonTimes.containsKey(pairNumber)) {
    return lessonTimes[pairNumber]!;
  }
  return 'Время не указано';
}

// Функция для парсинга времени (например, "08:00 – 09:30") в минуты с начала дня
int _parseTime(String time) {
  final regex = RegExp(r'[-–]');
  final timeParts = time.split(regex);
  final startTime = timeParts[0].trim();
  final startTimeValues = startTime.split(':');
  
  if (startTimeValues.length != 2) {
    throw FormatException('Некорректный формат времени: $time');
  }

  final hours = int.tryParse(startTimeValues[0]);
  final minutes = int.tryParse(startTimeValues[1]);

  if (hours == null || minutes == null) {
    throw FormatException('Не удалось разобрать часы или минуты: $time');
  }

  return hours * 60 + minutes; // Возвращаем время в минутах с начала дня
}

// Функция сравнения времени пар
int _compareLessonTimes(int pairA, int pairB) {
  String timeA = _getLessonTime(pairA);
  String timeB = _getLessonTime(pairB);

  try {
    final minutesA = _parseTime(timeA);
    final minutesB = _parseTime(timeB);

    return minutesA.compareTo(minutesB);
  } catch (e) {
    print('Ошибка парсинга времени: $e');
    return 0;
  }
}

Widget _buildGroupColumns() {
  final groupListViewScrollController = ScrollController();

  return Scrollbar(
    interactive: true,
    controller: groupListViewScrollController,
    thickness: 15,
    radius: const Radius.circular(40),
    child: ListView(
      scrollDirection: Axis.horizontal,
      controller: groupListViewScrollController,
      children: [
        Row(
          children: [
            ListView.builder(
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
                      return Center(child: Text('Ошибка: ${snapshot.error}'));
                    } else {
                      final List<Map<String, dynamic>> schedule = snapshot.data ?? [];

                      // Группировка расписания по дням недели
                      final Map<String, List<Map<String, dynamic>>> groupedByDay = {};
                      for (var item in schedule) {
                        String key = '${item['day_of_the_week'] ?? 'Не указано'}';
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
                                    String pairName = item['pair_name'] ?? 'Не указано';
                                    String week = item['week'] ?? 'все недели';
                                    String key = '$pairName - неделя $week';
                                    if (groupedByPair.containsKey(key)) {
                                      groupedByPair[key]!.add(item);
                                    } else {
                                      groupedByPair[key] = [item];
                                    }
                                  }

                                  // Сортировка пар по номеру
                                  final sortedPairs = groupedByPair.entries.toList()
                                    ..sort((a, b) => _compareLessonTimes(int.tryParse(a.key.split(' ')[0]) ?? 0, int.tryParse(b.key.split(' ')[0]) ?? 0));

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dayOfWeek,
                                        style: const TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                                      ),
                                      ...sortedPairs.map((pairEntry) {
                                        List<Map<String, dynamic>> items = pairEntry.value;
                                        String pairName = pairEntry.key.split(' ')[0];

                                        // Определяем пары для разных подгрупп и общие пары
                                        List<Map<String, dynamic>> subgroup1Items = items.where((item) => item['subgroup'] == '1').toList();
                                        List<Map<String, dynamic>> subgroup2Items = items.where((item) => item['subgroup'] == '2').toList();
                                        List<Map<String, dynamic>> commonItems = items.where((item) => item['subgroup'] == 'нет разделения' || item['subgroup'] == 'не определена').toList();

                                        // Проверка на наличие общих и отдельных пар
                                        bool hasCommonPair = commonItems.isNotEmpty;
                                        bool hasDifferentSubgroupPairs = subgroup1Items.isNotEmpty || subgroup2Items.isNotEmpty;
                                        if (hasCommonPair) {
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Column(
                                              children: [
                                                Text(
                                                  '$pairName пара (${_getLessonTime(int.tryParse(pairName))})',
                                                  style: const TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.all(12.0),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(8.0),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.grey.withOpacity(0.5),
                                                        spreadRadius: 3,
                                                        blurRadius: 5,
                                                        offset: Offset(0, 3),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: commonItems
                                                        .map((item) => _buildScheduleItem(item, TextAlign.center))
                                                        .toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        if (hasDifferentSubgroupPairs) {
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Container(
                                              padding: const EdgeInsets.all(12.0),  
                                              decoration: BoxDecoration(
                                                color: Colors.white,  
                                                borderRadius: BorderRadius.circular(8.0),  
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.grey.withOpacity(0.5),
                                                    spreadRadius: 3,
                                                    blurRadius: 5,
                                                    offset: Offset(0, 3), 
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    '$pairName пара (${_getLessonTime(int.tryParse(pairName))})',
                                                    style: const TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                                                  ),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Row(
                                                          children: [
                                                            if (subgroup1Items.isNotEmpty)
                                                              Expanded(
                                                                flex: 1,
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: subgroup1Items
                                                                      .map((item) => _buildScheduleItem(item, TextAlign.start))
                                                                      .toList(),
                                                                ),
                                                              ),
                                                            if (subgroup2Items.isNotEmpty)
                                                              Expanded(
                                                                flex: 1,
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                                  children: subgroup2Items
                                                                      .map((item)=> _buildScheduleItem(item, TextAlign.end))
                                                                       .toList(),
                                                                        ),
                                                                       ),
                                                                     ],
                                                                   ),
                                                                 ),
                                                               ],
                                                             ),
                                                           ],
                                                         ),
                                                       ),
                                                     );
                                                   }
                                    return SizedBox(); 
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
      ],
    ),
  ],
),
); }




  Widget _buildScheduleItem(Map<String, dynamic> item, TextAlign textAlign) {
    TextEditingController disciplineController = TextEditingController(text: item['discipline']);
    TextEditingController weekController = TextEditingController(text: item['week']);
    TextEditingController classroomController = TextEditingController(text: item['classroom']);
    TextEditingController teacherNameController = TextEditingController(text: item['teacher_name']);
    TextEditingController pairNameController = TextEditingController(text: item['pair_name']);

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
                    WidgetSpan(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 0.0),
                        child: IconButton(
                          icon: const Icon(Icons.edit, color: Color.fromARGB(128, 12, 12, 12)),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: const Text('Редактировать расписание'),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        TextField(
                                          controller: disciplineController,
                                          decoration: const InputDecoration(
                                            labelText: 'Дисциплина',
                                          ),
                                        ),
                                        TextField(
                                          controller: pairNameController,
                                          decoration: const InputDecoration(
                                            labelText: 'Номер пары',
                                          ),
                                        ),
                                        TextField(
                                          controller: weekController,
                                          decoration: const InputDecoration(
                                            labelText: 'Неделя',
                                          ),
                                        ),
                                        TextField(
                                          controller: classroomController,
                                          decoration: const InputDecoration(
                                            labelText: 'Аудитория',
                                          ),
                                        ),
                                        TextField(
                                          controller: teacherNameController,
                                          decoration: const InputDecoration(
                                            labelText: 'Преподаватель',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('Отмена'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () async {
                                        await updateScheduleItem(item['id'].toString(), {
                                          'discipline': disciplineController.text,
                                          'pair_name':pairNameController.text,
                                          'week': weekController.text,
                                          'classroom': classroomController.text,
                                          'teacher_name': teacherNameController.text,
                                        });
                                        // ignore: use_build_context_synchronously
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('Сохранить'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          tooltip: 'Редактирование записи:${item['discipline']}',
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