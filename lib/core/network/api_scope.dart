import 'package:flutter/widgets.dart';

import 'api_client.dart';

/// Đưa [ApiClient] xuống cây widget.
class ApiScope extends InheritedWidget {
  const ApiScope({super.key, required this.client, required super.child});

  final ApiClient client;

  static ApiClient? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ApiScope>()?.client;

  static ApiClient of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ApiScope>();
    assert(scope != null, 'Thiếu ApiScope trên cây widget');
    return scope!.client;
  }

  @override
  bool updateShouldNotify(ApiScope oldWidget) => client != oldWidget.client;
}
