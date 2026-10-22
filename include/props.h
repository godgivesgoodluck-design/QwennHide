#pragma once

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

} // namespace qwennhide
