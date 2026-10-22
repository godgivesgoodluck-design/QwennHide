#pragma once

#include <sys/types.h>  // Untuk dev_t, ino_t
#include <sys/stat.h>   // Untuk struct stat
#include <stdio.h>      // Untuk FILE

namespace qwennhide {

// Install PLT hooks for property spoofing & path hiding.
// Returns true if hooks were successfully committed.
bool install_hooks();

// Companion protocol: command codes sent over Unix socket
enum class Cmd : int {
    UNMOUNT_TARGET = 1,
    PING           = 2,
    SHUTDOWN       = 3,
};

// Hooked function pointers (exposed for main.cpp to register with Zygisk API)
namespace hooks {
    extern int  (*system_property_get)(const char *, char *);
    extern int  (*stat_fn)(const char *, struct stat *);
    extern int  (*access_fn)(const char *, int);
    extern FILE *(*fopen_fn)(const char *, const char *);
}

// Hooked function implementations (declared here, defined in props.cpp)
int fake_system_property_get(const char *name, char *value);
int fake_stat(const char *path, struct stat *sb);
int fake_access(const char *path, int mode);
FILE *fake_fopen(const char *path, const char *mode);

} // namespace qwennhide

// Companion entry point (defined in companion.cpp)
extern "C" void qwennhide_companion_entry(int client);
