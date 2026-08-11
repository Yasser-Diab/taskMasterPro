import 'package:flutter/material.dart';

/// The application-wide observer lets shell-level policies reset transient
/// state whenever a pushed screen, dialog, or sheet takes over navigation.
final appRouteObserver = RouteObserver<ModalRoute<dynamic>>();
