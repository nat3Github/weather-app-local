#import "wallpaper.h" // Include your own C-compatible header

#import <Foundation/Foundation.h> // For NSString, NSURL, etc.
#import <AppKit/AppKit.h>         // For NSWorkspace, NSScreen, etc.

// Define the C-callable function
int setWallpaperOnAllScreensAndSpacesC(const char *imagePathCStr) {
    // Always start with an autorelease pool when calling Objective-C from C
    // This ensures that temporary Objective-C objects are properly managed.
    @autoreleasepool {
        if (imagePathCStr == NULL) {
            NSLog(@"Error: C string image path is NULL.");
            return 1; // Indicate error
        }

        // Convert the null-terminated C string to an NSString object
        // UTF8String is generally safe for paths on macOS.
        NSString *imagePath = [NSString stringWithUTF8String:imagePathCStr];

        if (imagePath == nil) {
            NSLog(@"Error: Could not convert C string to NSString for path: %s", imagePathCStr);
            return 2; // Indicate error
        }

        // Convert the NSString path to an NSURL
        NSURL *fileURL = [NSURL fileURLWithPath:imagePath];

        if (!fileURL) {
            NSLog(@"Error: Invalid image path provided after NSString conversion: %@", imagePath);
            return 3; // Indicate error
        }

        // Get the shared NSWorkspace instance
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

        // Get an array of all available screens
        NSArray<NSScreen *> *screens = [NSScreen screens];

        // Define options for the desktop image
        NSMutableDictionary<NSWorkspaceDesktopImageOptionKey, id> *options = [NSMutableDictionary dictionary];

        // Example options (you can adjust these)
        options[NSWorkspaceDesktopImageScalingKey] = @(NSImageScaleProportionallyUpOrDown); // "Fill Screen"
        options[NSWorkspaceDesktopImageAllowClippingKey] = @(YES); // Allow clipping if needed for "Fill"
        // options[NSWorkspaceDesktopImageFillColorKey] = [NSColor blackColor]; // Optional background color

        int overallResult = 0; // 0 for success, non-zero for error

        // Loop through each screen and set its desktop image
        for (NSScreen *screen in screens) {
            NSError *error = nil; // Error object for receiving potential errors

            // Set the desktop image for the current screen
            BOOL success = [workspace setDesktopImageURL:fileURL
                                               forScreen:screen
                                                 options:options
                                                   error:&error];

            if (success) {
                // NSLog(@"Successfully set wallpaper for screen: %@", screen.localizedName);
            } else {
                NSLog(@"Error setting wallpaper for screen %@: %@", screen.localizedName, error.localizedDescription);
                overallResult = 4; // Indicate at least one screen failed
            }
        }
        return overallResult; // Return 0 if all successful, or 4 if any failed
    }
}

// New function: Get the current wallpaper path for the main screen.
// Returns a null-terminated C string (const char *).
// IMPORTANT: The caller (Zig) IS RESPONSIBLE for freeing this string using free().
const char* getCurrentWallpaperPathC(void) {
    @autoreleasepool {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        
        // Get the main screen (NSScreen representing the primary display)
        NSScreen *mainScreen = [NSScreen mainScreen];
        if (!mainScreen) {
            NSLog(@"Error: Could not get main screen.");
            return NULL;
        }

        NSError *error = nil;
        // This method returns the URL of the desktop image currently displayed on the specified screen.
        // It reflects the image for the *currently active space* on that screen.
        NSURL *imageURL = [workspace desktopImageURLForScreen:mainScreen];

        if (!imageURL) {
            NSLog(@"No desktop image URL found for main screen.");
            return NULL;
        }

        // Convert the NSURL to an NSString path
        NSString *imagePath = [imageURL path];
        if (!imagePath) {
            NSLog(@"Could not get path from image URL: %@", imageURL);
            return NULL;
        }

        // Convert the NSString to a C-style string (UTF8String)
        const char *cStringPath = [imagePath UTF8String];
        if (!cStringPath) {
            NSLog(@"Could not convert NSString path to C string: %@", imagePath);
            return NULL;
        }

        // Allocate memory for the C string and copy it.
        // The caller (Zig) is responsible for freeing this memory.
        size_t len = strlen(cStringPath);
        char *resultCStr = (char *)malloc(len + 1); // +1 for null terminator
        if (!resultCStr) {
            NSLog(@"Failed to allocate memory for C string path.");
            return NULL;
        }
        strcpy(resultCStr, cStringPath);

        return resultCStr;
    }
}