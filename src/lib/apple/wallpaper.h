// src/lib/apple/wallpaper.h
#ifndef WALLPAPER_H
#define WALLPAPER_H

#include <stdint.h> // For int32_t

// Declare the C-callable function
// It takes a C-style null-terminated string (const char *)
// Returns 0 on success, non-zero on failure.
int32_t setWallpaperOnAllScreensAndSpacesC(const char *imagePathCStr);


// New function: Get the current wallpaper path for the main screen.
// Returns a null-terminated C string (const char *).
// IMPORTANT: The caller (Zig) IS RESPONSIBLE for freeing this string.
const char* getCurrentWallpaperPathC();

#endif // WALLPAPER_H