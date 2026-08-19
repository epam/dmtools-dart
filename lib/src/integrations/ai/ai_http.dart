/// Shared HTTP configuration for AI provider clients.
///
/// Every provider client ([GeminiClient], [OpenAIClient], [OllamaClient])
/// creates its transport through [createDefaultAiDio] so timeouts stay
/// uniform across the AI integration and the Dio construction is not
/// duplicated per provider.
library;

import 'package:dio/dio.dart';

/// Creates a [Dio] with the standard 60-second timeouts used by all AI
/// provider clients.
Dio createDefaultAiDio() => Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
