#pragma once

#include <sys/types.h>
#include <sys/stat.h>
#include <stdio.h>
#include <fcntl.h>

namespace qwennhide {

enum class Cmd : int {
    UNMOUNT_TARGET = 1,
    PING           = 2,
    SHUTDOWN       = 3,
};

namespace hooks {
    extern int  (*system_property_get)(const char *, char *);
    extern int  (*stat_fn)(const char *, struct stat *);
    extern int  (*lstat_fn)(const char *, struct stat *);
    extern int  (*access_fn)(const char *, int);
    extern int  (*faccessat_fn)(int, const char *, int, int);
    extern int  (*open_fn)(const char *, int, ...);
    extern int  (*openat_fn)(int, const char *, int, ...);
    extern ssize_t (*readlink_fn)(const char *, char *, size_t);
    extern FILE *(*fopen_fn)(const char *, const char *);
}

int fake_system_property_get(const char *name, char *value);
int fake_stat(const char *path, struct stat *sb);
int fake_lstat(const char *path, struct stat *sb);
int fake_access(const char *path, int mode);
int fake_faccessat(int dirfd, const char *path, int mode, int flags);
int fake_open(const char *path, int flags, ...);
int fake_openat(int dirfd, const char *path, int flags, ...);
ssize_t fake_readlink(const char *path, char *buf, size_t bufsiz);
FILE *fake_fopen(const char *path, const char *mode);

bool is_hidden_path(const char *path);

} // namespace qwennhide

extern "C" void qwennhide_companion_entry(int client);
