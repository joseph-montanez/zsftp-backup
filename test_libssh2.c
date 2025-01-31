#include <libssh2.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

int main() {
    const char *host = "127.0.0.1";
    const int port = 2222;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in server_addr;
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    inet_pton(AF_INET, host, &server_addr.sin_addr);

    if (connect(sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) != 0) {
        perror("Socket connection failed");
        return 1;
    }

    LIBSSH2_SESSION *session = libssh2_session_init();
    if (!session) {
        fprintf(stderr, "libssh2 session init failed\n");
        return 1;
    }

    libssh2_trace(session, LIBSSH2_TRACE_CONN | LIBSSH2_TRACE_TRANS);

    int rc = libssh2_session_handshake(session, sock);
    if (rc != 0) {
        fprintf(stderr, "Handshake failed: %d\n", rc);
        return 1;
    }

    printf("SSH handshake successful!\n");

    libssh2_session_disconnect(session, "Bye");
    libssh2_session_free(session);
    close(sock);
    libssh2_exit();

    return 0;
}
