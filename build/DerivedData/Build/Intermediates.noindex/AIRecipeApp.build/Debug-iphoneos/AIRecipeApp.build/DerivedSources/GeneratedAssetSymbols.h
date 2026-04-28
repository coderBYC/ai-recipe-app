#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.airecipe.app";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "InstagramIcon" asset catalog image resource.
static NSString * const ACImageNameInstagramIcon AC_SWIFT_PRIVATE = @"InstagramIcon";

/// The "LoadingMeme" asset catalog image resource.
static NSString * const ACImageNameLoadingMeme AC_SWIFT_PRIVATE = @"LoadingMeme";

/// The "TikTokIcon" asset catalog image resource.
static NSString * const ACImageNameTikTokIcon AC_SWIFT_PRIVATE = @"TikTokIcon";

/// The "YouTubeIcon" asset catalog image resource.
static NSString * const ACImageNameYouTubeIcon AC_SWIFT_PRIVATE = @"YouTubeIcon";

#undef AC_SWIFT_PRIVATE
