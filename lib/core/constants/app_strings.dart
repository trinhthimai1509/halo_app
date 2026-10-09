/// User-facing copy. Centralised so it can be moved to ARB / gen-l10n later
/// without hunting through widgets.
abstract final class AppStrings {
  static const String appName = 'Halo';
  static const String appTagline = 'On-device assistant';

  // Chat — empty state.
  static const String welcomeTitle = 'How can I help?';
  static const String welcomeSubtitle =
      'Private by design. Your conversations stay on this device.';

  // Chat — composer.
  static const String composerHint = 'Ask anything…';
  static const String listening = 'Listening…';
  static const String transcribing = 'Transcribing…';
  static const String thinking = 'Thinking';

  // Tooltips / semantic labels.
  static const String openHistory = 'Chat history';
  static const String newChat = 'New chat';
  static const String voiceInput = 'Voice input';
  static const String send = 'Send message';
  static const String stopGenerating = 'Stop generating';
  static const String cancelRecording = 'Cancel recording';
  static const String finishRecording = 'Finish recording';
  static const String back = 'Back';
  static const String search = 'Search conversations';
  static const String closeSearch = 'Close search';
  static const String youSaid = 'You';

  // History.
  static const String historyTitle = 'History';
  static const String historySearchHint = 'Search';
  static const String historyEmptyTitle = 'No conversations yet';
  static const String historyEmptyBody =
      'Start a conversation and it will appear here.';
  static const String historyNoResults = 'No matching conversations';
  static const String delete = 'Delete';
  static const String deleteConversation = 'Delete conversation';
  static const String cancel = 'Cancel';
  static const String conversationDeleted = 'Conversation deleted';
  static const String openConversationHint = 'Opens the conversation';
  static const String licenses = 'Open-source licences';

  // Errors.
  static const String modelUnavailable =
      'The on-device AI model is not installed yet.';
  static const String generationFailed =
      'Something went wrong while generating a reply.';
  static const String loadConversationFailed =
      'This conversation could not be opened.';
  static const String voiceFailed = 'Voice input is not available right now.';
  static const String micPermissionDenied =
      'Voice input needs microphone access. Allow it in Settings.';
  static const String speechModelUnavailable =
      'The Vietnamese speech model is not installed yet.';
  static const String noSpeechDetected =
      "Didn't catch that. Please try speaking again.";
  static const String historyLoadFailed = 'Your history could not be loaded.';
  static const String deleteFailed = 'The conversation could not be deleted.';

  // Model setup.
  static const String modelSetupTitle = 'AI models';
  static const String modelSetupIntro =
      'Halo runs entirely on this device and never downloads anything. '
      'Copy the model files to this device (for example to the Download '
      'folder), then import them here.';
  static const String llmModelHint =
      'Choose the file Qwen3.5-2B-Q4_K_M.gguf.';
  static const String speechModelHint =
      'Choose halo-stt-vi.zip, or select the four speech files together.';
  static const String modelInstalled = 'Installed';
  static const String modelInstalledDeveloper = 'Installed (developer copy)';
  static const String modelMissing = 'Not installed';
  static const String modelInvalid = 'Damaged: import again';
  static const String modelChecking = 'Checking…';
  static const String importAction = 'Import';
  static const String replaceAction = 'Replace';
  static const String retryAction = 'Try again';
  static const String cancelImport = 'Cancel import';
  static const String importDone = 'Imported and verified.';
  static const String importCancelled =
      'Import cancelled. Nothing was changed.';
  static const String importBusy = 'Another import is still running.';
  static const String importWrongLlmFile =
      "That isn't the expected model file. Choose Qwen3.5-2B-Q4_K_M.gguf.";
  static const String importWrongSpeechFile =
      "One of the files isn't the expected speech model file.";
  static const String importMissingSpeechFiles =
      'Some speech files are missing. Choose halo-stt-vi.zip, or select all '
      'four files: encoder, decoder, joiner and tokens.txt.';
  static String importNoSpace(String need, String free) =>
      'Not enough free space: $need needed, $free free. Free up space and '
      'try again.';
  static const String importCorrupt =
      'The file is damaged or a different version. Copy it to the device '
      'again and retry. Your previous model was kept.';
  static const String importIoError =
      'The file could not be read. Try again. Your previous model was kept.';
  static String storageNeeded(String size) => 'Needs about $size of storage';
  static const String setUpModels = 'Set up';

  // Relative dates.
  static const String today = 'Today';
  static const String yesterday = 'Yesterday';
  static const List<String> weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}
