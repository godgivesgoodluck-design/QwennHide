#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <sched.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>

#include "props.h"

#ifndef QH_DEBUG
#define QH_DEBUG 0
#endif

#if QH_DEBUG
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "QH-c", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "QH-c", __VA_ARGS__)
#else
#define LOGI(...) ((void)0)
#define LOGE(...) ((void)0)
#endif

namespace {

// Paths to unmount inside the target's mount namespace.
// These are the mount points Magisk/NeoZygisk create.
static const char *UNMOUNT_TARGETS[] = {
    "/system/bin/su",
    "/system/xbin/su",
    "/sbin/su",
    "/sbin/.magisk",
    "/system/bin/.magisk",
    "/system/bin/magisk",
    "/system/bin/magiskinit",
    "/system/bin/magiskpolicy",
    "/data/adb/magisk",
    "/data/adb/modules",
    "/data/adb/service.d",
    "/data/adb/post-fs-data.d",
    "/debug_ramdisk",
    "/dev/.magisk",
    "/dev/.magisk.unblock",
    "/dev/zygisk",
    nullptr,
};

// Enter the mount namespace of the given PID.
// Returns 0 on success.
int enter_namespace(pid_t pid) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/ns/mnt", pid);

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        LOGE("open %s: %s", path, strerror(errno));
        return -1;
    }

    int rc = setns(fd, CLONE_NEWNS);
    int saved = errno;
    close(fd);
    if (rc != 0) {
        LOGE("setns: %s", strerror(saved));
        errno = saved;
        return -1;
    }
    return 0;
}

// Unmount all tracked paths in the current (target's) namespace.
void do_unmounts() {
    for (int i = 0; UNMOUNT_TARGETS[i] != nullptr; i++) {
        const char *p = UNMOUNT_TARGETS[i];
        struct stat st;
        if (lstat(p, &st) != 0) continue;

        // Try lazy unmount first (MNT_DETACH).
        if (umount2(p, MNT_DETACH) == 0) {
            LOGI("unmounted %s", p);
            continue;
        }
        // Fallback: bind-mount /dev/null over it so any read returns empty.
        if (S_ISREG(st.st_mode)) {
            if (mount("/dev/null", p, nullptr, MS_BIND | MS_REC, nullptr) == 0) {
                LOGI("bind-mounted /dev/null over %s", p);
            }
        }
    }

    // Also hide /proc/self/mountinfo from revealing leftover mounts.
    // We do this by bind-mounting a filtered copy.
    // (Implemented as a simple approach: leave mountinfo alone for now;
    //  the companion already removed the sensitive mounts above.)
}

} // namespace

// Companion entry point. Called by the host when the module calls connectCompanion().
// Runs as root. Receives commands over the socket.
extern "C" void qwennhide_companion_entry(int client) {
    while (true) {
        int cmd = 0;
        ssize_t n = read(client, &cmd, sizeof(cmd));
        if (n <= 0) break;

        auto c = static_cast<qwennhide::Cmd>(cmd);
        switch (c) {
            case qwennhide::Cmd::UNMOUNT_TARGET: {
                pid_t target_pid = 0;
                if (read(client, &target_pid, sizeof(target_pid)) != sizeof(target_pid)) break;

                int ack = 0;
                if (enter_namespace(target_pid) == 0) {
                    do_unmounts();
                    ack = 1;
                } else {
                    ack = 0;
                }
                write(client, &ack, sizeof(ack));
                break;
            }

            case qwennhide::Cmd::PING: {
                int ack = 1;
                write(client, &ack, sizeof(ack));
                break;
            }

            case qwennhide::Cmd::SHUTDOWN: {
                int ack = 1;
                write(client, &ack, sizeof(ack));
                close(client);
                _exit(0);
            }

            default:
                break;
        }
    }
    close(client);
}
