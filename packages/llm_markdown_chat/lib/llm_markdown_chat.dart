/// A ready AI chat screen on top of `llm_markdown`.
///
/// [LlmChatController] keeps the messages and asks your code for each reply;
/// [LlmChatView] shows them with an input box, send and stop.
/// [ChatListController] and [ChatListView] keep several chats, and
/// [SseChatBackend] gets the replies from a streaming HTTP endpoint.
library;

export 'src/chat_controller.dart';
export 'src/chat_list_controller.dart';
export 'src/chat_list_view.dart';
export 'src/chat_view.dart';
export 'src/sse_backend.dart';
