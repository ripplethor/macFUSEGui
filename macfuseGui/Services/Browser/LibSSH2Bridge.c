#include "LibSSH2Bridge.h"

/*
 BEGINNER FILE GUIDE
 Layer: Native C bridge for remote browser transport
 Purpose:
 - Execute libssh2 SSH/SFTP operations for directory browsing.
 - Enforce strict operation deadlines.
 - Return results/errors in a Swift-friendly structure.

 Maintenance notes:
 - This file uses manual memory management; free paths matter.
 - Error messages here are shown in diagnostics, so keep them clear.
*/

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <libssh2.h>
#include <libssh2_sftp.h>
#include <netdb.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static pthread_once_t g_libssh2_once = PTHREAD_ONCE_INIT;

/* libssh2 global initialization should happen exactly once per process. */
static void macfusegui_libssh2_global_init(void) {
    (void)libssh2_init(0);
}

typedef struct macfusegui_kbdint_context {
    const char *password;
} macfusegui_kbdint_context;

static char *macfusegui_strdup_len(const char *value, size_t len);

static LIBSSH2_USERAUTH_KBDINT_RESPONSE_FUNC(macfusegui_kbdint_response_callback) {
    (void)name;
    (void)name_len;
    (void)instruction;
    (void)instruction_len;
    (void)prompts;

    const char *password = "";
    if (abstract != NULL && *abstract != NULL) {
        macfusegui_kbdint_context *context = (macfusegui_kbdint_context *)(*abstract);
        if (context->password != NULL) {
            password = context->password;
        }
    }

    /* Keyboard-interactive can present multiple prompts; answer all with same password. */
    size_t password_len = strlen(password);
    for (int idx = 0; idx < num_prompts; idx += 1) {
        responses[idx].text = macfusegui_strdup_len(password, password_len);
        responses[idx].length = (unsigned int)password_len;
    }
}

static int64_t macfusegui_now_millis(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ((int64_t)ts.tv_sec * 1000LL) + ((int64_t)ts.tv_nsec / 1000000LL);
}

static void macfusegui_zero_list_result(macfusegui_libssh2_list_result *result) {
    memset(result, 0, sizeof(*result));
    result->status_code = -1;
    result->latency_ms = 0;
}

static char *macfusegui_strdup_len(const char *value, size_t len) {
    if (value == NULL) {
        return NULL;
    }

    char *copy = (char *)malloc(len + 1);
    if (copy == NULL) {
        /* Caller must handle NULL and unwind cleanup safely. */
        return NULL;
    }

    if (len > 0) {
        memcpy(copy, value, len);
    }
    copy[len] = '\0';
    return copy;
}

static char *macfusegui_strdup(const char *value) {
    if (value == NULL) {
        return NULL;
    }
    return macfusegui_strdup_len(value, strlen(value));
}

static char *macfusegui_build_session_error_string(LIBSSH2_SESSION *session, const char *fallback_message) {
    if (session != NULL) {
        char *raw = NULL;
        int raw_len = 0;
        int libssh2_error = libssh2_session_last_error(session, &raw, &raw_len, 0);

        if (raw != NULL && raw_len > 0) {
            char prefix[64];
            snprintf(prefix, sizeof(prefix), "libssh2 error %d: ", libssh2_error);

            size_t prefix_len = strlen(prefix);
            size_t total_len = prefix_len + (size_t)raw_len;
            char *buffer = (char *)malloc(total_len + 1);
            if (buffer != NULL) {
                memcpy(buffer, prefix, prefix_len);
                memcpy(buffer + prefix_len, raw, (size_t)raw_len);
                buffer[total_len] = '\0';
                return buffer;
            }
        }
    }

    return macfusegui_strdup(fallback_message != NULL ? fallback_message : "Unknown libssh2 error.");
}

static void macfusegui_set_error(macfusegui_libssh2_list_result *result, int32_t status_code, const char *message) {
    if (result == NULL) {
        return;
    }

    result->status_code = status_code;
    if (result->error_message != NULL) {
        free(result->error_message);
        result->error_message = NULL;
    }

    result->error_message = macfusegui_strdup(message != NULL ? message : "Unknown libssh2 error.");
}

static void macfusegui_set_session_error(
    macfusegui_libssh2_list_result *result,
    LIBSSH2_SESSION *session,
    int32_t fallback_status,
    const char *fallback_message
) {
    char *message = macfusegui_build_session_error_string(session, fallback_message);
    if (message != NULL) {
        macfusegui_set_error(result, fallback_status, message);
        free(message);
        return;
    }

    macfusegui_set_error(result, fallback_status, fallback_message);
}

static char *macfusegui_session_error_message(LIBSSH2_SESSION *session, const char *fallback_message) {
    return macfusegui_build_session_error_string(session, fallback_message);
}

static bool macfusegui_equals_ignore_case(char a, char b) {
    if (a == b) {
        return true;
    }

    if (a >= 'A' && a <= 'Z') {
        a = (char)(a + ('a' - 'A'));
    }
    if (b >= 'A' && b <= 'Z') {
        b = (char)(b + ('a' - 'A'));
    }

    return a == b;
}

static bool macfusegui_long_entry_indicates_directory(const char *long_entry) {
    if (long_entry == NULL || long_entry[0] == '\0') {
        return false;
    }

    if (long_entry[0] == 'd' || long_entry[0] == 'D') {
        // POSIX long-entry format.
        return true;
    }

    // Windows/OpenSSH style long entries can include "<DIR>" marker.
    for (const char *cursor = long_entry; *cursor != '\0'; cursor += 1) {
        if (*cursor != '<' && *cursor != '[') {
            continue;
        }

        char closing = (*cursor == '<') ? '>' : ']';
        if (cursor[1] == '\0' || cursor[2] == '\0' || cursor[3] == '\0' || cursor[4] == '\0') {
            continue;
        }

        if (macfusegui_equals_ignore_case(cursor[1], 'd') &&
            macfusegui_equals_ignore_case(cursor[2], 'i') &&
            macfusegui_equals_ignore_case(cursor[3], 'r') &&
            cursor[4] == closing) {
            return true;
        }
    }

    return false;
}

int32_t macfusegui_libssh2_classify_directory_entry(
    uint64_t attrs_flags,
    uint64_t permissions,
    const char *long_entry
) {
    if ((attrs_flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && LIBSSH2_SFTP_S_ISDIR(permissions)) {
        return 1;
    }

    if (macfusegui_long_entry_indicates_directory(long_entry)) {
        return 1;
    }

    return 0;
}

static void macfusegui_set_out_error(char **out_error_message, const char *message) {
    if (out_error_message == NULL) {
        return;
    }
    if (*out_error_message != NULL) {
        free(*out_error_message);
    }
    *out_error_message = macfusegui_strdup(message != NULL ? message : "Unknown libssh2 error.");
}

static void macfusegui_set_out_session_error(char **out_error_message, LIBSSH2_SESSION *session, const char *fallback_message) {
    if (out_error_message == NULL) {
        return;
    }
    if (*out_error_message != NULL) {
        free(*out_error_message);
        *out_error_message = NULL;
    }
    *out_error_message = macfusegui_session_error_message(session, fallback_message);
}

#define MACFUSEGUI_BRIDGE_WAIT_TIMEOUT (-900001)
#define MACFUSEGUI_CONNECT_ERROR_SOCKET_TIMEOUT_CONFIG (-900101)

static int64_t macfusegui_deadline_from_timeout_seconds(int32_t timeout_seconds) {
    return macfusegui_now_millis() + ((int64_t)timeout_seconds * 1000LL);
}

static int32_t macfusegui_remaining_timeout_ms(int64_t deadline_ms) {
    int64_t remaining = deadline_ms - macfusegui_now_millis();
    if (remaining <= 0) {
        return 0;
    }
    if (remaining > 2147483647LL) {
        return 2147483647;
    }
    return (int32_t)remaining;
}

static void macfusegui_format_timeout_message(char *buffer, size_t buffer_size, const char *stage, int32_t timeout_seconds) {
    if (buffer == NULL || buffer_size == 0) {
        return;
    }

    const char *effective_stage = (stage != NULL && stage[0] != '\0') ? stage : "libssh2 operation";
    snprintf(buffer, buffer_size, "Timed out during %s after %d second(s).", effective_stage, (int)timeout_seconds);
}

static void macfusegui_set_out_timeout_error(char **out_error_message, const char *stage, int32_t timeout_seconds) {
    char message[256];
    macfusegui_format_timeout_message(message, sizeof(message), stage, timeout_seconds);
    macfusegui_set_out_error(out_error_message, message);
}

static void macfusegui_set_result_timeout_error(
    macfusegui_libssh2_list_result *result,
    int32_t status_code,
    const char *stage,
    int32_t timeout_seconds
) {
    char message[256];
    macfusegui_format_timeout_message(message, sizeof(message), stage, timeout_seconds);
    macfusegui_set_error(result, status_code, message);
}

static int macfusegui_set_socket_blocking(int fd, bool blocking) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        return -1;
    }

    if (blocking) {
        flags &= ~O_NONBLOCK;
    } else {
        flags |= O_NONBLOCK;
    }

    return fcntl(fd, F_SETFL, flags);
}

static int macfusegui_connect_with_timeout(int sock, const struct sockaddr *addr, socklen_t addrlen, int timeout_seconds) {
    int connect_result = connect(sock, addr, addrlen);
    if (connect_result == 0) {
        return 0;
    }

    if (errno != EINPROGRESS) {
        return -1;
    }

    fd_set write_fds;
    FD_ZERO(&write_fds);
    FD_SET(sock, &write_fds);

    int64_t deadline_ms = macfusegui_deadline_from_timeout_seconds(timeout_seconds);
    int32_t remaining_ms = macfusegui_remaining_timeout_ms(deadline_ms);
    if (remaining_ms <= 0) {
        errno = ETIMEDOUT;
        return -1;
    }

    struct timeval timeout_value;
    timeout_value.tv_sec = (time_t)(remaining_ms / 1000);
    timeout_value.tv_usec = (suseconds_t)((remaining_ms % 1000) * 1000);

    int select_result = select(sock + 1, NULL, &write_fds, NULL, &timeout_value);
    if (select_result <= 0) {
        errno = (select_result == 0) ? ETIMEDOUT : errno;
        return -1;
    }

    int socket_error = 0;
    socklen_t socket_error_len = sizeof(socket_error);
    if (getsockopt(sock, SOL_SOCKET, SO_ERROR, &socket_error, &socket_error_len) != 0) {
        return -1;
    }

    if (socket_error != 0) {
        errno = socket_error;
        return -1;
    }

    return 0;
}

static int macfusegui_wait_socket(LIBSSH2_SESSION *session, int sock, int64_t deadline_ms) {
    int32_t remaining_ms = macfusegui_remaining_timeout_ms(deadline_ms);
    if (remaining_ms <= 0) {
        errno = ETIMEDOUT;
        return MACFUSEGUI_BRIDGE_WAIT_TIMEOUT;
    }

    /* Ask libssh2 whether it is blocked on read, write, or both. */
    int directions = session != NULL ? libssh2_session_block_directions(session) : 0;
    if (directions == 0) {
        directions = LIBSSH2_SESSION_BLOCK_INBOUND | LIBSSH2_SESSION_BLOCK_OUTBOUND;
    }

    fd_set read_fds;
    fd_set write_fds;
    FD_ZERO(&read_fds);
    FD_ZERO(&write_fds);

    if (directions & LIBSSH2_SESSION_BLOCK_INBOUND) {
        FD_SET(sock, &read_fds);
    }
    if (directions & LIBSSH2_SESSION_BLOCK_OUTBOUND) {
        FD_SET(sock, &write_fds);
    }

    struct timeval timeout_value;
    timeout_value.tv_sec = (time_t)(remaining_ms / 1000);
    timeout_value.tv_usec = (suseconds_t)((remaining_ms % 1000) * 1000);

    int select_result = select(sock + 1, &read_fds, &write_fds, NULL, &timeout_value);
    if (select_result == 0) {
        errno = ETIMEDOUT;
        return MACFUSEGUI_BRIDGE_WAIT_TIMEOUT;
    }
    if (select_result < 0) {
        return -1;
    }
    return 0;
}

static int macfusegui_connect_socket(const char *host, int32_t port, int32_t timeout_seconds, bool *out_timeout_config_failure) {
    if (out_timeout_config_failure != NULL) {
        *out_timeout_config_failure = false;
    }

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    char port_buffer[16];
    snprintf(port_buffer, sizeof(port_buffer), "%d", (int)port);

    struct addrinfo *resolved = NULL;
    int gai_result = getaddrinfo(host, port_buffer, &hints, &resolved);
    if (gai_result != 0) {
        return -1;
    }

    int connected_socket = -1;
    bool timeout_config_failure = false;

    for (struct addrinfo *cursor = resolved; cursor != NULL; cursor = cursor->ai_next) {
        int candidate = socket(cursor->ai_family, cursor->ai_socktype, cursor->ai_protocol);
        if (candidate < 0) {
            continue;
        }

        int one = 1;
        (void)setsockopt(candidate, SOL_SOCKET, SO_KEEPALIVE, &one, sizeof(one));

        /* Keep socket non-blocking after connect; bridge wait loops depend on this mode. */
        if (macfusegui_set_socket_blocking(candidate, false) != 0) {
            close(candidate);
            continue;
        }

        struct timeval tv;
        tv.tv_sec = timeout_seconds;
        tv.tv_usec = 0;
        if (setsockopt(candidate, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) != 0 ||
            setsockopt(candidate, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv)) != 0) {
            timeout_config_failure = true;
            close(candidate);
            continue;
        }

        if (macfusegui_connect_with_timeout(candidate, cursor->ai_addr, cursor->ai_addrlen, timeout_seconds) == 0) {
            connected_socket = candidate;
            break;
        }

        close(candidate);
    }

    freeaddrinfo(resolved);
    if (connected_socket < 0 && timeout_config_failure) {
        if (out_timeout_config_failure != NULL) {
            *out_timeout_config_failure = true;
        }
        return MACFUSEGUI_CONNECT_ERROR_SOCKET_TIMEOUT_CONFIG;
    }

    return connected_socket;
}

static int macfusegui_append_entry(
    macfusegui_libssh2_list_result *result,
    const char *name,
    uint8_t is_directory,
    uint8_t has_size,
    uint64_t size_bytes,
    uint8_t has_modified_at,
    int64_t modified_at_unix
) {
    if (result == NULL || name == NULL || name[0] == '\0') {
        return -1;
    }

    char *name_copy = macfusegui_strdup(name);
    if (name_copy == NULL) {
        return -1;
    }

    int32_t next_count = result->entry_count + 1;
    size_t bytes = (size_t)next_count * sizeof(macfusegui_libssh2_entry);

    macfusegui_libssh2_entry *resized = (macfusegui_libssh2_entry *)realloc(result->entries, bytes);
    if (resized == NULL) {
        free(name_copy);
        return -1;
    }

    result->entries = resized;

    macfusegui_libssh2_entry *entry = &result->entries[result->entry_count];
    memset(entry, 0, sizeof(*entry));

    entry->name = name_copy;
    entry->is_directory = is_directory;
    entry->has_size = has_size;
    entry->size_bytes = size_bytes;
    entry->has_modified_at = has_modified_at;
    entry->modified_at_unix = modified_at_unix;

    result->entry_count = next_count;
    return 0;
}

static int macfusegui_session_handshake_with_deadline(
    LIBSSH2_SESSION *session,
    int sock,
    int64_t deadline_ms
) {
    while (1) {
        int handshake_result = libssh2_session_handshake(session, sock);
        if (handshake_result == 0) {
            return 0;
        }
        if (handshake_result != LIBSSH2_ERROR_EAGAIN) {
            return handshake_result;
        }
        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            return wait_result;
        }
    }
}

static int macfusegui_password_auth_with_deadline(
    LIBSSH2_SESSION *session,
    int sock,
    const char *username,
    const char *password,
    int64_t deadline_ms
) {
    while (1) {
        int auth_result = libssh2_userauth_password_ex(
            session,
            username,
            (unsigned int)strlen(username),
            password,
            (unsigned int)strlen(password),
            NULL
        );
        if (auth_result == 0) {
            return 0;
        }
        if (auth_result != LIBSSH2_ERROR_EAGAIN) {
            return auth_result;
        }
        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            return wait_result;
        }
    }
}

static int macfusegui_kbdint_auth_with_deadline(
    LIBSSH2_SESSION *session,
    int sock,
    const char *username,
    const char *password,
    int64_t deadline_ms
) {
    macfusegui_kbdint_context *keyboard_context = (macfusegui_kbdint_context *)malloc(sizeof(*keyboard_context));
    if (keyboard_context == NULL) {
        return LIBSSH2_ERROR_ALLOC;
    }
    keyboard_context->password = password;

    void **session_abstract = libssh2_session_abstract(session);
    void *previous_abstract = NULL;
    if (session_abstract != NULL) {
        previous_abstract = *session_abstract;
        *session_abstract = keyboard_context;
    }

    int auth_result = LIBSSH2_ERROR_EAGAIN;
    while (1) {
        auth_result = libssh2_userauth_keyboard_interactive_ex(
            session,
            username,
            (unsigned int)strlen(username),
            macfusegui_kbdint_response_callback
        );
        if (auth_result == 0) {
            break;
        }
        if (auth_result != LIBSSH2_ERROR_EAGAIN) {
            break;
        }

        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            auth_result = wait_result;
            break;
        }
    }

    if (session_abstract != NULL) {
        *session_abstract = previous_abstract;
    }
    free(keyboard_context);
    return auth_result;
}

static int macfusegui_publickey_auth_with_deadline(
    LIBSSH2_SESSION *session,
    int sock,
    const char *username,
    const char *private_key_path,
    int64_t deadline_ms
) {
    while (1) {
        int auth_result = libssh2_userauth_publickey_fromfile_ex(
            session,
            username,
            (unsigned int)strlen(username),
            NULL,
            private_key_path,
            NULL
        );
        if (auth_result == 0) {
            return 0;
        }
        if (auth_result != LIBSSH2_ERROR_EAGAIN) {
            return auth_result;
        }
        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            return wait_result;
        }
    }
}

static LIBSSH2_SFTP *macfusegui_sftp_init_with_deadline(
    LIBSSH2_SESSION *session,
    int sock,
    int64_t deadline_ms,
    int *out_status
) {
    while (1) {
        LIBSSH2_SFTP *sftp = libssh2_sftp_init(session);
        if (sftp != NULL) {
            if (out_status != NULL) {
                *out_status = 0;
            }
            return sftp;
        }

        int last_error = libssh2_session_last_errno(session);
        if (last_error != LIBSSH2_ERROR_EAGAIN) {
            if (out_status != NULL) {
                *out_status = last_error;
            }
            return NULL;
        }

        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            if (out_status != NULL) {
                *out_status = wait_result;
            }
            return NULL;
        }
    }
}

static ssize_t macfusegui_sftp_realpath_with_deadline(
    LIBSSH2_SESSION *session,
    LIBSSH2_SFTP *sftp,
    int sock,
    const char *remote_path,
    char *buffer,
    size_t buffer_size,
    int64_t deadline_ms,
    int *out_status
) {
    if (buffer_size > (size_t)UINT_MAX) {
        if (out_status != NULL) {
            *out_status = LIBSSH2_ERROR_BUFFER_TOO_SMALL;
        }
        return LIBSSH2_ERROR_BUFFER_TOO_SMALL;
    }

    unsigned int buffer_size_u32 = (unsigned int)buffer_size;

    while (1) {
        ssize_t result = libssh2_sftp_realpath(sftp, remote_path, buffer, buffer_size_u32);
        if (result >= 0) {
            if (out_status != NULL) {
                *out_status = 0;
            }
            return result;
        }
        if (result != LIBSSH2_ERROR_EAGAIN) {
            if (out_status != NULL) {
                *out_status = (int)result;
            }
            return result;
        }

        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            if (out_status != NULL) {
                *out_status = wait_result;
            }
            return result;
        }
    }
}

static LIBSSH2_SFTP_HANDLE *macfusegui_sftp_opendir_with_deadline(
    LIBSSH2_SESSION *session,
    LIBSSH2_SFTP *sftp,
    int sock,
    const char *path,
    int64_t deadline_ms,
    int *out_status
) {
    while (1) {
        LIBSSH2_SFTP_HANDLE *handle = libssh2_sftp_opendir(sftp, path);
        if (handle != NULL) {
            if (out_status != NULL) {
                *out_status = 0;
            }
            return handle;
        }

        int last_error = libssh2_session_last_errno(session);
        if (last_error != LIBSSH2_ERROR_EAGAIN) {
            if (out_status != NULL) {
                *out_status = last_error;
            }
            return NULL;
        }

        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            if (out_status != NULL) {
                *out_status = wait_result;
            }
            return NULL;
        }
    }
}

static ssize_t macfusegui_sftp_readdir_with_deadline(
    LIBSSH2_SESSION *session,
    LIBSSH2_SFTP_HANDLE *directory_handle,
    int sock,
    char *file_name,
    size_t file_name_size,
    char *long_entry,
    size_t long_entry_size,
    LIBSSH2_SFTP_ATTRIBUTES *attrs,
    int64_t deadline_ms,
    int *out_status
) {
    while (1) {
        ssize_t result = libssh2_sftp_readdir_ex(
            directory_handle,
            file_name,
            file_name_size,
            long_entry,
            long_entry_size,
            attrs
        );
        if (result != LIBSSH2_ERROR_EAGAIN) {
            if (out_status != NULL) {
                *out_status = (result < 0) ? (int)result : 0;
            }
            return result;
        }

        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            if (out_status != NULL) {
                *out_status = wait_result;
            }
            return result;
        }
    }
}

static int macfusegui_sftp_stat_with_deadline(
    LIBSSH2_SESSION *session,
    LIBSSH2_SFTP *sftp,
    int sock,
    const char *path,
    LIBSSH2_SFTP_ATTRIBUTES *attrs,
    int64_t deadline_ms,
    int *out_status
) {
    while (1) {
        int stat_result = libssh2_sftp_stat_ex(
            sftp,
            path,
            (unsigned int)strlen(path),
            LIBSSH2_SFTP_STAT,
            attrs
        );
        if (stat_result != LIBSSH2_ERROR_EAGAIN) {
            if (out_status != NULL) {
                *out_status = 0;
            }
            return stat_result;
        }

        int wait_result = macfusegui_wait_socket(session, sock, deadline_ms);
        if (wait_result != 0) {
            if (out_status != NULL) {
                *out_status = wait_result;
            }
            return stat_result;
        }
    }
}

int32_t macfusegui_libssh2_bridge_version(void) {
    return 3;
}

static int macfusegui_knownhost_key_mask(int hostkey_type) {
    switch (hostkey_type) {
        case LIBSSH2_HOSTKEY_TYPE_RSA:
            return LIBSSH2_KNOWNHOST_KEY_SSHRSA;
        case LIBSSH2_HOSTKEY_TYPE_DSS:
            return LIBSSH2_KNOWNHOST_KEY_SSHDSS;
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_256:
            return LIBSSH2_KNOWNHOST_KEY_ECDSA_256;
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_384:
            return LIBSSH2_KNOWNHOST_KEY_ECDSA_384;
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_521:
            return LIBSSH2_KNOWNHOST_KEY_ECDSA_521;
        case LIBSSH2_HOSTKEY_TYPE_ED25519:
            return LIBSSH2_KNOWNHOST_KEY_ED25519;
        default:
            return 0;
    }
}

static char *macfusegui_hostkey_fingerprint(LIBSSH2_SESSION *session) {
    const char *hash = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_SHA256);
    if (hash == NULL) {
        return NULL;
    }

    char *out = (char *)malloc(32 * 3);
    if (out == NULL) {
        return NULL;
    }

    static const char hexdigits[] = "0123456789abcdef";
    size_t pos = 0;
    for (int i = 0; i < 32; i += 1) {
        unsigned char byte = (unsigned char)hash[i];
        if (i > 0) {
            out[pos++] = ':';
        }
        out[pos++] = hexdigits[(byte >> 4) & 0x0F];
        out[pos++] = hexdigits[byte & 0x0F];
    }
    out[pos] = '\0';
    return out;
}

static int macfusegui_ensure_ssh_dir(const char *home, char **out_error_message) {
    char dir[PATH_MAX];
    int written = snprintf(dir, sizeof(dir), "%s/.ssh", home);
    if (written < 0 || (size_t)written >= sizeof(dir)) {
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: could not resolve the ~/.ssh directory.");
        return -1;
    }

    if (mkdir(dir, 0700) == 0) {
        return 0;
    }

    if (errno == EEXIST) {
        struct stat statbuf;
        if (stat(dir, &statbuf) == 0 && S_ISDIR(statbuf.st_mode)) {
            return 0;
        }
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: ~/.ssh exists but is not a directory.");
        return -1;
    }

    macfusegui_set_out_error(out_error_message,
        "Host key verification failed: could not create ~/.ssh to persist the trusted host key.");
    return -1;
}

static int macfusegui_verify_host_key(
    LIBSSH2_SESSION *session,
    const char *host,
    int32_t port,
    char **out_error_message
) {
    size_t hostkey_len = 0;
    int hostkey_type = 0;
    const char *hostkey = libssh2_session_hostkey(session, &hostkey_len, &hostkey_type);
    if (hostkey == NULL || hostkey_len == 0) {
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: the server did not present a host key.");
        return -1;
    }

    int key_mask = macfusegui_knownhost_key_mask(hostkey_type);
    if (key_mask == 0) {
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: unsupported remote host key type.");
        return -1;
    }

    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') {
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: HOME is not set, so ~/.ssh/known_hosts cannot be checked.");
        return -1;
    }

    char known_hosts_path[PATH_MAX];
    int path_written = snprintf(known_hosts_path, sizeof(known_hosts_path), "%s/.ssh/known_hosts", home);
    if (path_written < 0 || (size_t)path_written >= sizeof(known_hosts_path)) {
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: could not resolve the ~/.ssh/known_hosts path.");
        return -1;
    }

    LIBSSH2_KNOWNHOSTS *known_hosts = libssh2_knownhost_init(session);
    if (known_hosts == NULL) {
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: could not initialize the known-hosts store.");
        return -1;
    }

    int read_result = libssh2_knownhost_readfile(known_hosts, known_hosts_path, LIBSSH2_KNOWNHOST_FILE_OPENSSH);
    if (read_result < 0 && read_result != LIBSSH2_ERROR_FILE) {
        libssh2_knownhost_free(known_hosts);
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: ~/.ssh/known_hosts exists but could not be read.");
        return -1;
    }

    int typemask = LIBSSH2_KNOWNHOST_TYPE_PLAIN | LIBSSH2_KNOWNHOST_KEYENC_RAW | key_mask;
    struct libssh2_knownhost *match = NULL;
    int check = libssh2_knownhost_checkp(known_hosts, host, (int)port, hostkey, hostkey_len, typemask, &match);

    if (check == LIBSSH2_KNOWNHOST_CHECK_MATCH) {
        libssh2_knownhost_free(known_hosts);
        return 0;
    }

    if (check == LIBSSH2_KNOWNHOST_CHECK_MISMATCH) {
        char *fingerprint = macfusegui_hostkey_fingerprint(session);
        char message[768];
        snprintf(message, sizeof(message),
            "Host key verification failed: the key offered by %s:%d does not match "
            "the trusted key in ~/.ssh/known_hosts. This may indicate a man-in-the-middle "
            "attack. Offered key SHA256 fingerprint: %s. If the host key changed legitimately, "
            "remove the old known_hosts entry and reconnect.",
            host, (int)port, fingerprint != NULL ? fingerprint : "unavailable");
        free(fingerprint);
        libssh2_knownhost_free(known_hosts);
        macfusegui_set_out_error(out_error_message, message);
        return -1;
    }

    if (check != LIBSSH2_KNOWNHOST_CHECK_NOTFOUND) {
        libssh2_knownhost_free(known_hosts);
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: could not check the remote host key.");
        return -1;
    }

    char hostid[NI_MAXHOST + 16];
    int hostid_written;
    if (port == 22) {
        hostid_written = snprintf(hostid, sizeof(hostid), "%s", host);
    } else {
        hostid_written = snprintf(hostid, sizeof(hostid), "[%s]:%d", host, (int)port);
    }
    if (hostid_written < 0 || (size_t)hostid_written >= sizeof(hostid)) {
        libssh2_knownhost_free(known_hosts);
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: host identifier is too long for known_hosts.");
        return -1;
    }

    int add_result = libssh2_knownhost_addc(
        known_hosts,
        hostid,
        NULL,
        hostkey,
        hostkey_len,
        NULL,
        0,
        typemask,
        NULL);

    if (add_result != 0) {
        libssh2_knownhost_free(known_hosts);
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: could not add the first-use key to known_hosts.");
        return -1;
    }

    if (macfusegui_ensure_ssh_dir(home, out_error_message) != 0) {
        libssh2_knownhost_free(known_hosts);
        return -1;
    }

    int write_result = libssh2_knownhost_writefile(known_hosts, known_hosts_path, LIBSSH2_KNOWNHOST_FILE_OPENSSH);
    libssh2_knownhost_free(known_hosts);
    if (write_result < 0) {
        macfusegui_set_out_error(out_error_message,
            "Host key verification failed: could not persist the first-use key to ~/.ssh/known_hosts.");
        return -1;
    }

    return 0;
}

int32_t macfusegui_libssh2_open_session(
    const char *host,
    int32_t port,
    const char *username,
    const char *password,
    const char *private_key_path,
    int32_t timeout_seconds,
    macfusegui_libssh2_session_handle **out_session,
    char **out_error_message
) {
    /*
     Open session flow:
     1) Connect TCP socket with timeout.
     2) Handshake SSH session.
     3) Authenticate (password/kbdint/private key).
     4) Initialize SFTP subsystem.
     5) Return persistent session handle.
    */
    if (out_session == NULL) {
        return -1;
    }
    *out_session = NULL;

    if (out_error_message != NULL) {
        *out_error_message = NULL;
    }

    if (host == NULL || username == NULL || port <= 0 || timeout_seconds <= 0) {
        macfusegui_set_out_error(out_error_message, "Invalid browser session open request.");
        return -100;
    }

    pthread_once(&g_libssh2_once, macfusegui_libssh2_global_init);

    int sock = -1;
    LIBSSH2_SESSION *session = NULL;
    LIBSSH2_SFTP *sftp = NULL;
    macfusegui_libssh2_session_handle *handle = NULL;
    int64_t deadline_ms = macfusegui_deadline_from_timeout_seconds(timeout_seconds);

    bool timeout_config_failure = false;
    sock = macfusegui_connect_socket(host, port, timeout_seconds, &timeout_config_failure);
    if (sock == MACFUSEGUI_CONNECT_ERROR_SOCKET_TIMEOUT_CONFIG || timeout_config_failure) {
        macfusegui_set_out_error(out_error_message, "Failed to configure socket send/receive timeouts.");
        goto cleanup_error;
    }
    if (sock < 0) {
        macfusegui_set_out_error(out_error_message, "Could not connect to remote host.");
        goto cleanup_error;
    }

    session = libssh2_session_init_ex(NULL, NULL, NULL, NULL);
    if (session == NULL) {
        macfusegui_set_out_error(out_error_message, "Failed to initialize libssh2 session.");
        goto cleanup_error;
    }

    libssh2_session_set_blocking(session, 0);
    libssh2_session_set_timeout(session, timeout_seconds * 1000);

    int handshake_result = macfusegui_session_handshake_with_deadline(session, sock, deadline_ms);
    if (handshake_result == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
        macfusegui_set_out_timeout_error(out_error_message, "SSH handshake", timeout_seconds);
        goto cleanup_error;
    }
    if (handshake_result != 0) {
        macfusegui_set_out_session_error(out_error_message, session, "SSH handshake failed.");
        goto cleanup_error;
    }

    if (macfusegui_verify_host_key(session, host, port, out_error_message) != 0) {
        goto cleanup_error;
    }

    if (password != NULL && password[0] != '\0') {
        int auth = macfusegui_password_auth_with_deadline(session, sock, username, password, deadline_ms);

        if (auth != 0) {
            if (auth == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
                macfusegui_set_out_timeout_error(out_error_message, "password authentication", timeout_seconds);
                goto cleanup_error;
            }

            int keyboard_auth = macfusegui_kbdint_auth_with_deadline(session, sock, username, password, deadline_ms);

            if (keyboard_auth != 0) {
                if (keyboard_auth == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
                    macfusegui_set_out_timeout_error(out_error_message, "keyboard-interactive authentication", timeout_seconds);
                    goto cleanup_error;
                }
                macfusegui_set_out_session_error(out_error_message, session, "Password authentication failed.");
                goto cleanup_error;
            }
        }
    } else if (private_key_path != NULL && private_key_path[0] != '\0') {
        int auth = macfusegui_publickey_auth_with_deadline(session, sock, username, private_key_path, deadline_ms);
        if (auth != 0) {
            if (auth == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
                macfusegui_set_out_timeout_error(out_error_message, "public-key authentication", timeout_seconds);
                goto cleanup_error;
            }
            macfusegui_set_out_session_error(out_error_message, session, "Private key authentication failed.");
            goto cleanup_error;
        }
    } else {
        macfusegui_set_out_error(out_error_message, "No authentication material provided.");
        goto cleanup_error;
    }

    int sftp_init_status = 0;
    sftp = macfusegui_sftp_init_with_deadline(session, sock, deadline_ms, &sftp_init_status);
    if (sftp == NULL) {
        if (sftp_init_status == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
            macfusegui_set_out_timeout_error(out_error_message, "SFTP subsystem initialization", timeout_seconds);
            goto cleanup_error;
        }
        macfusegui_set_out_session_error(out_error_message, session, "Unable to initialize SFTP subsystem.");
        goto cleanup_error;
    }

    handle = (macfusegui_libssh2_session_handle *)malloc(sizeof(*handle));
    if (handle == NULL) {
        macfusegui_set_out_error(out_error_message, "Failed to allocate libssh2 browser session.");
        goto cleanup_error;
    }

    handle->sock = sock;
    handle->session = session;
    handle->sftp = sftp;

    *out_session = handle;
    return 0;

cleanup_error:
    if (sftp != NULL) {
        (void)libssh2_sftp_shutdown(sftp);
        sftp = NULL;
    }

    if (session != NULL) {
        (void)libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "macfuseGui", "en");
        (void)libssh2_session_free(session);
        session = NULL;
    }

    if (sock >= 0) {
        close(sock);
        sock = -1;
    }

    if (handle != NULL) {
        free(handle);
        handle = NULL;
    }

    return -101;
}

int32_t macfusegui_libssh2_list_directories_with_session(
    macfusegui_libssh2_session_handle *session_handle,
    const char *remote_path,
    int32_t timeout_seconds,
    macfusegui_libssh2_list_result *out_result
) {
    /*
     List flow using existing session:
     1) Resolve canonical path (realpath).
     2) Open directory handle.
     3) Iterate readdir entries.
     4) Keep directory entries only.
     5) Return results + latency.
    */
    if (out_result == NULL) {
        return -1;
    }

    macfusegui_zero_list_result(out_result);

    if (session_handle == NULL || session_handle->session == NULL || session_handle->sftp == NULL ||
        remote_path == NULL || timeout_seconds <= 0) {
        macfusegui_set_error(out_result, -30, "Invalid libssh2 browse session state.");
        return out_result->status_code;
    }

    int64_t started_at = macfusegui_now_millis();
    int64_t deadline_ms = macfusegui_deadline_from_timeout_seconds(timeout_seconds);
    LIBSSH2_SFTP_HANDLE *directory_handle = NULL;

    libssh2_session_set_blocking(session_handle->session, 0);
    libssh2_session_set_timeout(session_handle->session, timeout_seconds * 1000);

    char real_path_buffer[4096];
    const char *effective_path = remote_path;
    int real_path_status = 0;
    ssize_t real_path_len = macfusegui_sftp_realpath_with_deadline(
        session_handle->session,
        session_handle->sftp,
        session_handle->sock,
        remote_path,
        real_path_buffer,
        sizeof(real_path_buffer) - 1,
        deadline_ms,
        &real_path_status
    );
    if (real_path_status == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
        macfusegui_set_result_timeout_error(out_result, -30, "SFTP realpath", timeout_seconds);
        goto cleanup;
    }
    if (real_path_len > 0 && real_path_len < (ssize_t)(sizeof(real_path_buffer) - 1)) {
        real_path_buffer[real_path_len] = '\0';
        effective_path = real_path_buffer;
    }

    out_result->resolved_path = macfusegui_strdup(effective_path);

    int opendir_status = 0;
    directory_handle = macfusegui_sftp_opendir_with_deadline(
        session_handle->session,
        session_handle->sftp,
        session_handle->sock,
        effective_path,
        deadline_ms,
        &opendir_status
    );
    if (directory_handle == NULL) {
        if (opendir_status == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
            macfusegui_set_result_timeout_error(out_result, -31, "SFTP opendir", timeout_seconds);
            goto cleanup;
        }
        macfusegui_set_session_error(out_result, session_handle->session, -31, "Unable to open remote directory.");
        goto cleanup;
    }

    while (1) {
        char file_name[2048];
        char long_entry[4096];
        LIBSSH2_SFTP_ATTRIBUTES attrs;
        memset(file_name, 0, sizeof(file_name));
        memset(long_entry, 0, sizeof(long_entry));
        memset(&attrs, 0, sizeof(attrs));

        int readdir_status = 0;
        ssize_t read_count = macfusegui_sftp_readdir_with_deadline(
            session_handle->session,
            directory_handle,
            session_handle->sock,
            file_name,
            sizeof(file_name) - 1,
            long_entry,
            sizeof(long_entry) - 1,
            &attrs,
            deadline_ms,
            &readdir_status
        );

        if (read_count > 0) {
            file_name[read_count] = '\0';

            if ((strcmp(file_name, ".") == 0) || (strcmp(file_name, "..") == 0)) {
                continue;
            }

            uint8_t is_directory = (uint8_t)macfusegui_libssh2_classify_directory_entry(
                attrs.flags,
                attrs.permissions,
                long_entry
            );

            if (is_directory == 0) {
                /* Browser is directories-only by product design. */
                continue;
            }

            uint8_t has_size = (attrs.flags & LIBSSH2_SFTP_ATTR_SIZE) ? 1 : 0;
            uint64_t size_bytes = has_size ? attrs.filesize : 0;
            uint8_t has_modified_at = (attrs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) ? 1 : 0;
            int64_t modified_at_unix = has_modified_at ? (int64_t)attrs.mtime : 0;

            if (macfusegui_append_entry(
                out_result,
                file_name,
                is_directory,
                has_size,
                size_bytes,
                has_modified_at,
                modified_at_unix
            ) != 0) {
                macfusegui_set_error(out_result, -32, "Failed to store SFTP directory entry.");
                goto cleanup;
            }

            continue;
        }

        if (read_count == 0) {
            break;
        }

        if (readdir_status == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
            macfusegui_set_result_timeout_error(out_result, -33, "SFTP readdir", timeout_seconds);
            goto cleanup;
        }

        macfusegui_set_session_error(out_result, session_handle->session, -33, "Failed while reading remote directory.");
        goto cleanup;
    }

    out_result->status_code = 0;

cleanup:
    if (directory_handle != NULL) {
        (void)libssh2_sftp_closedir(directory_handle);
        directory_handle = NULL;
    }

    if (out_result->status_code != 0 && out_result->error_message == NULL) {
        macfusegui_set_error(out_result, -34, "Unknown libssh2 browse error.");
    }

    int64_t elapsed_ms = macfusegui_now_millis() - started_at;
    out_result->latency_ms = (int32_t)(elapsed_ms > 0 ? elapsed_ms : 0);
    return out_result->status_code;
}

int32_t macfusegui_libssh2_ping_session(
    macfusegui_libssh2_session_handle *session_handle,
    const char *remote_path,
    int32_t timeout_seconds,
    char **out_error_message
) {
    /* Keepalive probe uses lightweight SFTP stat on current path. */
    if (out_error_message != NULL) {
        *out_error_message = NULL;
    }

    if (session_handle == NULL || session_handle->session == NULL || session_handle->sftp == NULL ||
        remote_path == NULL || timeout_seconds <= 0) {
        macfusegui_set_out_error(out_error_message, "Invalid libssh2 browser session state.");
        return -40;
    }

    int64_t deadline_ms = macfusegui_deadline_from_timeout_seconds(timeout_seconds);

    libssh2_session_set_blocking(session_handle->session, 0);
    libssh2_session_set_timeout(session_handle->session, timeout_seconds * 1000);

    LIBSSH2_SFTP_ATTRIBUTES attrs;
    memset(&attrs, 0, sizeof(attrs));

    int stat_status = 0;
    int stat_result = macfusegui_sftp_stat_with_deadline(
        session_handle->session,
        session_handle->sftp,
        session_handle->sock,
        remote_path,
        &attrs,
        deadline_ms,
        &stat_status
    );
    if (stat_status == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
        macfusegui_set_out_timeout_error(out_error_message, "SFTP stat", timeout_seconds);
        return -41;
    }
    if (stat_result == 0) {
        return 0;
    }

    size_t path_len = strlen(remote_path);
    if (path_len > 1 && remote_path[path_len - 1] == '/') {
        /* Compatibility fallback only: some servers fail stat on trailing slash paths. */
        char *trimmed = macfusegui_strdup(remote_path);
        if (trimmed != NULL) {
            while (path_len > 1 && trimmed[path_len - 1] == '/') {
                trimmed[path_len - 1] = '\0';
                path_len -= 1;
            }
            if (path_len > 0) {
                memset(&attrs, 0, sizeof(attrs));
                stat_status = 0;
                stat_result = macfusegui_sftp_stat_with_deadline(
                    session_handle->session,
                    session_handle->sftp,
                    session_handle->sock,
                    trimmed,
                    &attrs,
                    deadline_ms,
                    &stat_status
                );
            }
            free(trimmed);
            if (stat_status == MACFUSEGUI_BRIDGE_WAIT_TIMEOUT) {
                macfusegui_set_out_timeout_error(out_error_message, "SFTP stat", timeout_seconds);
                return -41;
            }
            if (stat_result == 0) {
                return 0;
            }
        }
    }

    macfusegui_set_out_session_error(out_error_message, session_handle->session, "SFTP keepalive check failed.");
    return -41;
}

void macfusegui_libssh2_close_session(macfusegui_libssh2_session_handle *session_handle) {
    /*
     Close flow is defensive:
     - Attempt graceful SFTP/session shutdown with bounded waits.
     - Shutdown socket last and always free handle resources.
    */
    if (session_handle == NULL) {
        return;
    }

    if (session_handle->sftp != NULL && session_handle->session != NULL && session_handle->sock >= 0) {
        int64_t shutdown_deadline = macfusegui_now_millis() + 1000;
        while (1) {
            int shutdown_result = libssh2_sftp_shutdown(session_handle->sftp);
            if (shutdown_result == 0 || shutdown_result != LIBSSH2_ERROR_EAGAIN) {
                break;
            }
            if (macfusegui_wait_socket(session_handle->session, session_handle->sock, shutdown_deadline) != 0) {
                break;
            }
        }
        session_handle->sftp = NULL;
    } else if (session_handle->sftp != NULL) {
        (void)libssh2_sftp_shutdown(session_handle->sftp);
        session_handle->sftp = NULL;
    }

    if (session_handle->session != NULL) {
        libssh2_session_set_blocking(session_handle->session, 0);
        int64_t disconnect_deadline = macfusegui_now_millis() + 1000;
        while (1) {
            int disconnect_result = libssh2_session_disconnect_ex(session_handle->session, SSH_DISCONNECT_BY_APPLICATION, "macfuseGui", "en");
            if (disconnect_result == 0 || disconnect_result != LIBSSH2_ERROR_EAGAIN) {
                break;
            }
            if (session_handle->sock < 0 ||
                macfusegui_wait_socket(session_handle->session, session_handle->sock, disconnect_deadline) != 0) {
                break;
            }
        }
        (void)libssh2_session_free(session_handle->session);
        session_handle->session = NULL;
    }

    if (session_handle->sock >= 0) {
        (void)shutdown(session_handle->sock, SHUT_RDWR);
        close(session_handle->sock);
        session_handle->sock = -1;
    }

    free(session_handle);
}

void macfusegui_libssh2_free_error(char *error_message) {
    free(error_message);
}

int32_t macfusegui_libssh2_list_directories(
    const char *host,
    int32_t port,
    const char *username,
    const char *password,
    const char *private_key_path,
    const char *remote_path,
    int32_t timeout_seconds,
    macfusegui_libssh2_list_result *out_result
) {
    /* One-shot convenience wrapper: open -> list -> close. */
    if (out_result == NULL) {
        return -1;
    }

    macfusegui_zero_list_result(out_result);

    if (host == NULL || username == NULL || remote_path == NULL || port <= 0 || timeout_seconds <= 0) {
        macfusegui_set_error(out_result, -10, "Invalid browser request for libssh2 transport.");
        return out_result->status_code;
    }

    int64_t started_at = macfusegui_now_millis();
    macfusegui_libssh2_session_handle *session_handle = NULL;
    char *open_error = NULL;

    int open_status = macfusegui_libssh2_open_session(
        host,
        port,
        username,
        password,
        private_key_path,
        timeout_seconds,
        &session_handle,
        &open_error
    );
    if (open_status != 0 || session_handle == NULL) {
        macfusegui_set_error(
            out_result,
            -11,
            open_error != NULL ? open_error : "Could not open libssh2 browser session."
        );
        if (open_error != NULL) {
            free(open_error);
            open_error = NULL;
        }
        int64_t elapsed_ms = macfusegui_now_millis() - started_at;
        out_result->latency_ms = (int32_t)(elapsed_ms > 0 ? elapsed_ms : 0);
        return out_result->status_code;
    }

    int32_t list_status = macfusegui_libssh2_list_directories_with_session(
        session_handle,
        remote_path,
        timeout_seconds,
        out_result
    );
    macfusegui_libssh2_close_session(session_handle);
    session_handle = NULL;

    if (open_error != NULL) {
        free(open_error);
        open_error = NULL;
    }

    int64_t elapsed_ms = macfusegui_now_millis() - started_at;
    /* Intentional: one-shot latency includes open + list + close end-to-end time. */
    out_result->latency_ms = (int32_t)(elapsed_ms > 0 ? elapsed_ms : 0);
    return list_status;
}

void macfusegui_libssh2_free_list_result(macfusegui_libssh2_list_result *result) {
    /* Releases all allocations created during list operation. */
    if (result == NULL) {
        return;
    }

    if (result->entries != NULL) {
        for (int32_t idx = 0; idx < result->entry_count; idx += 1) {
            if (result->entries[idx].name != NULL) {
                free(result->entries[idx].name);
                result->entries[idx].name = NULL;
            }
        }

        free(result->entries);
        result->entries = NULL;
    }

    if (result->resolved_path != NULL) {
        free(result->resolved_path);
        result->resolved_path = NULL;
    }

    if (result->error_message != NULL) {
        free(result->error_message);
        result->error_message = NULL;
    }

    result->entry_count = 0;
    result->status_code = 0;
    result->latency_ms = 0;
}
