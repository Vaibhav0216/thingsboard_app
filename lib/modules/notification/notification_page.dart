import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/modules/notification/filter_segmented_button.dart';
import 'package:thingsboard_app/modules/notification/notification_list.dart';
import 'package:thingsboard_app/modules/notification/notification_model.dart';
import 'package:thingsboard_app/utils/services/_tb_secure_storage.dart';
import 'package:thingsboard_app/utils/services/notification_service.dart';
import 'package:thingsboard_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_app/widgets/tb_progress_indicator.dart';

enum NotificationsFilter { all, unread }

class NotificationPage extends TbPageWidget {
  NotificationPage(TbContext tbContext) : super(tbContext);

  @override
  State<StatefulWidget> createState() => _NotificationPageState();
}

class _NotificationPageState extends TbPageState<NotificationPage> {
  final _isLoadingNotifier = ValueNotifier<bool>(true);
  List<NotificationModel> _notifications = [];
  NotificationsFilter notificationsFilter = NotificationsFilter.unread;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: Scaffold(
        appBar: TbAppBar(
          tbContext,
          title: const Text('Notifications'),
          actions: [
            TextButton(
              child: Text('Mark all as read'),
              onPressed: () {
                setState(() {
                  for (int i = 0; i < _notifications.length; ++i) {
                    if (!_notifications[i].read) {
                      _notifications[i] =
                          _notifications[i].copyWith(read: true);
                      NotificationService.clearNotificationBadgeCount();
                    }
                  }
                });

                final storage = tbContext.storage;
                storage.setItem(
                  NotificationService.notificationsListKey,
                  jsonEncode(
                    _notifications.map((e) => e.toJson()).toList(),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: StreamBuilder(
            stream: NotificationService.notificationsNumberStream.stream,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                if (_notifications.where((e) => !e.read).toList().length !=
                    snapshot.data) {
                  _refresh();
                }
              }

              return ValueListenableBuilder<bool>(
                valueListenable: _isLoadingNotifier,
                builder: (context, loading, _) {
                  if (loading) {
                    return SizedBox.expand(
                      child: Container(
                        color: Color(0x99FFFFFF),
                        child: Center(
                          child: TbProgressIndicator(
                            tbContext,
                            size: 50.0,
                          ),
                        ),
                      ),
                    );
                  } else {
                    if (_notifications.isEmpty) {
                      return Scaffold(
                        body: LayoutBuilder(
                          builder: (_, c) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: SizedBox(
                                height: c.maxHeight,
                                width: c.maxWidth,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'No notifications yet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w400,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 20),
                            child: FilterSegmentedButton(
                              selected: notificationsFilter,
                              onSelectionChanged: (newSelection) {
                                setState(() {
                                  notificationsFilter = newSelection;
                                });
                              },
                              segments: [
                                FilterSegments(
                                  label: 'Unread',
                                  value: NotificationsFilter.unread,
                                ),
                                FilterSegments(
                                  label: 'All',
                                  value: NotificationsFilter.all,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: NotificationsList(
                              notifications: _notifications.reversed.where((e) {
                                if (notificationsFilter ==
                                    NotificationsFilter.unread) {
                                  return !e.read;
                                }

                                return true;
                              }).toList(),
                              thingsboardClient: tbClient,
                              tbContext: tbContext,
                              onClearNotification: (id) {
                                final notification = _notifications.firstWhere(
                                  (e) => e.message.messageId == id,
                                );

                                if (!notification.read) {
                                  NotificationService
                                      .decreaseNotificationBadgeCount(
                                    notification.hashCode,
                                  );
                                }

                                setState(() {
                                  _notifications.removeWhere(
                                    (e) => e.message.messageId == id,
                                  );
                                });

                                final storage = tbContext.storage;
                                storage.setItem(
                                  NotificationService.notificationsListKey,
                                  jsonEncode(
                                    _notifications
                                        .map((e) => e.toJson())
                                        .toList(),
                                  ),
                                );
                              },
                              onReadNotification: (id) {
                                setState(() {
                                  final index = _notifications.indexWhere(
                                    (e) => e.message.messageId == id,
                                  );
                                  if (index != -1) {
                                    _notifications[index] =
                                        _notifications[index]
                                            .copyWith(read: true);

                                    NotificationService
                                        .decreaseNotificationBadgeCount(
                                      _notifications[index].hashCode,
                                    );
                                  }
                                });

                                final storage = tbContext.storage;
                                storage.setItem(
                                  NotificationService.notificationsListKey,
                                  jsonEncode(
                                    _notifications
                                        .map((e) => e.toJson())
                                        .toList(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    _isLoadingNotifier.value = true;
    _loadNotifications().whenComplete(
      () => _isLoadingNotifier.value = false,
    );
    super.initState();
  }

  Future<void> _loadNotifications() async {
    final storage = createAppStorage();
    final notifications = await storage.getItem(
      NotificationService.notificationsListKey,
    );

    if (notifications != null) {
      _notifications = json
          .decode(notifications)
          .map((e) => NotificationModel.fromJson(e))
          .toList()
          .cast<NotificationModel>();
    }
  }

  Future<void> _refresh() async {
    await _loadNotifications();
    if (mounted) {
      setState(() {});
    }
  }
}
