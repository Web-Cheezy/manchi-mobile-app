import 'dart:convert';
import 'package:flutter/material.dart';

/// Converts exceptions and error objects into short, user-friendly messages
/// suitable for production. Never exposes stack traces or raw API responses.
class UserFacingErrors {
  UserFacingErrors._();

  static const String _generic = 'Something went wrong. Please try again.';
  static const String _network = 'Please check your connection and try again.';
  static const String _session = 'Your session may have expired. Please sign in again.';

  /// Returns a short, safe message for display. Prefers [context] when the error
  /// is generic (e.g. connection/session).
  static String toUserFriendlyMessage(Object error, {String? context}) {
    final msg = error.toString().trim();
    if (msg.isEmpty) return context ?? _generic;

    final lower = msg.toLowerCase();
    if (lower.contains('api key') ||
        lower.contains('apikey') ||
        lower.contains('api_key') ||
        lower.contains('invalid api key') ||
        lower.contains('invalid key') ||
        lower.contains('key not valid') ||
        lower.contains('access not configured')) {
      return context ?? _generic;
    }

    if (_isFriendly(msg)) return _cleanMessage(msg);

    if (lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused')) {
      return _network;
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'This is taking longer than usual. Please try again.';
    }
    if (lower.contains('401') || lower.contains('unauthorized') || lower.contains('session')) {
      return context ?? _session;
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'You don\'t have permission to do that.';
    }
    if (lower.contains('404')) {
      return 'We couldn\'t find that. Please refresh and try again.';
    }
    if (lower.contains('422') || lower.contains('already') || lower.contains('exists')) {
      return 'That email may already be in use. Try signing in or use a different email.';
    }
    if (lower.contains('500') || lower.contains('server error')) {
      return 'Our servers are busy. Please try again in a moment.';
    }

    return context ?? _generic;
  }

  static bool _isFriendly(String msg) {
    if (msg.length > 120) return false;
    if (msg.contains('Exception:') && msg.length > 80) return false;
    if (msg.contains('Error:') && msg.contains(' at ')) return false;
    if (msg.contains('.dart:') || msg.contains('stack')) return false;
    return true;
  }

  static String _cleanMessage(String msg) {
    const prefixes = ['Exception: ', 'Error: '];
    for (final p in prefixes) {
      if (msg.startsWith(p)) return msg.substring(p.length).trim();
    }
    return msg;
  }

  /// Shows a SnackBar with a user-friendly error message. Use for catch blocks in UI.
  static void showErrorSnackBar(BuildContext context, Object error, {String? contextMessage}) {
    if (!context.mounted) return;
    final message = toUserFriendlyMessage(error, context: contextMessage);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Tries to extract a short user-facing message from an API response body.
  /// Returns null if body is not JSON or message looks technical.
  static String? messageFromResponseBody(int statusCode, String body) {
    if (body.isEmpty) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      final raw = (data['message'] ?? data['error'] ?? data['msg'])?.toString();
      if (raw == null || raw.isEmpty) return null;
      if (raw.length > 150) return null;
      if (raw.contains(' at ') || raw.contains('.dart') || raw.contains('stack')) return null;
      return raw.trim();
    } catch (_) {
      return null;
    }
  }
}
