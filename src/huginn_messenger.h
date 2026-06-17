#include <stdint.h>
#include <stdlib.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

// Messenger lifecycle
FFI_PLUGIN_EXPORT long messenger_create(const char* username, const char* muninn_addr, const char* db_path, const char* chunk_ttl);
FFI_PLUGIN_EXPORT void messenger_destroy(long handle);
FFI_PLUGIN_EXPORT long messenger_is_peer_online(long handle, const char* peer_id);

// Getters (return JSON strings, must be freed with messenger_free_string)
FFI_PLUGIN_EXPORT char* messenger_get_me(long handle);
FFI_PLUGIN_EXPORT char* messenger_get_peers(long handle);
FFI_PLUGIN_EXPORT char* messenger_search_peers(long handle, const char* query);
FFI_PLUGIN_EXPORT char* messenger_get_messages(long handle, const char* peer_id);
FFI_PLUGIN_EXPORT char* messenger_get_config(long handle);
FFI_PLUGIN_EXPORT char* messenger_get_downloads_dir(long handle);
FFI_PLUGIN_EXPORT char* messenger_get_file_path(long handle, const char* file_id);

// Actions (return JSON: {"status":"ok"} or {"error":"..."})
FFI_PLUGIN_EXPORT char* messenger_send_message(long handle, const char* to, const char* text, int ttl);
FFI_PLUGIN_EXPORT char* messenger_send_file(long handle, const char* to, const char* text, const char* file_path, int ttl);
FFI_PLUGIN_EXPORT char* messenger_save_config(long handle, const char* json_config);

// Events (polling, returns JSON event or empty string if none)
FFI_PLUGIN_EXPORT char* messenger_get_event(long handle, int timeout_ms);

// Memory management
FFI_PLUGIN_EXPORT void messenger_free_string(char* s);
