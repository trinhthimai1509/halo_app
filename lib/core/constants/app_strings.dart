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
      'The on-device model is not installed. See docs/LOCAL_AI.md.';
  static const String generationFailed =
      'Something went wrong while generating a reply.';
  static const String loadConversationFailed =
      'This conversation could not be opened.';
  static const String voiceFailed = 'Voice input is not available right now.';
  static const String micPermissionDenied =
      'Voice input needs microphone access. Allow it in Settings.';
  static const String speechModelUnavailable =
      'The on-device speech model is not installed. See docs/SPEECH.md.';
  static const String noSpeechDetected =
      "Didn't catch that. Please try speaking again.";
  static const String historyLoadFailed = 'Your history could not be loaded.';
  static const String deleteFailed = 'The conversation could not be deleted.';

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
