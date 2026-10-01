#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#if __has_include(<root-hide/root-hide.h>)
    #import <root-hide/root-hide.h>
#else
    #define jbroot(path) path
#endif

// iOS 17 PaperBoardUI 接口声明
@interface PBUIWallpaperController : NSObject
+ (id)sharedInstance;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations completionHandler:(void (^)(void))completionHandler;
@end

// 兼容 SBWallpaperController 声明
@interface SBWallpaperController : NSObject
+ (id)sharedInstance;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations completionHandler:(void (^)(void))completionHandler;
@end

static NSInteger gMode = 0; // 0: 网络直链, 1: 本地路径/文件夹
static NSString *gWallpaperURL = nil;
static NSString *gLocalPath = nil;
static NSTimer *gWallpaperTimer = nil;

static void setWallpaperImage(UIImage *image) {
    if (!image) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger locations = 3; // 1: 锁屏, 2: 主屏, 3: 锁屏+主屏
        id wallpaperController = nil;

        // 1. 优先获取 iOS 17 的 PBUIWallpaperController (PaperBoardUI.framework)
        Class PBUIWallpaperControllerClass = %c(PBUIWallpaperController);
        if (PBUIWallpaperControllerClass && [PBUIWallpaperControllerClass respondsToSelector:@selector(sharedInstance)]) {
            wallpaperController = [PBUIWallpaperControllerClass sharedInstance];
        }

        // 2. 回退机制：若未获取到则尝试获取 SBWallpaperController
        if (!wallpaperController) {
            Class SBWallpaperControllerClass = %c(SBWallpaperController);
            if (SBWallpaperControllerClass && [SBWallpaperControllerClass respondsToSelector:@selector(sharedInstance)]) {
                wallpaperController = [SBWallpaperControllerClass sharedInstance];
            }
        }

        if (!wallpaperController) {
            NSLog(@"[AutoOnlineWallpaper] ❌ 无法获取 WallpaperController 实例");
            return;
        }

        // 3. 执行壁纸更新逻辑
        if ([wallpaperController respondsToSelector:@selector(setWallpaperImage:forLocations:completionHandler:)]) {
            [wallpaperController setWallpaperImage:image forLocations:locations completionHandler:^{
                NSLog(@"[AutoOnlineWallpaper] ✅ iOS 17 壁纸更新成功 (completionHandler)");
            }];
        } else if ([wallpaperController respondsToSelector:@selector(setWallpaperImage:forLocations:)]) {
            [wallpaperController setWallpaperImage:image forLocations:locations];
            NSLog(@"[AutoOnlineWallpaper] ✅ iOS 17 壁纸更新成功 (setWallpaperImage:forLocations:)");
        } else {
            NSLog(@"[AutoOnlineWallpaper] ❌ 当前系统未找到兼容的壁纸设置 API");
        }
    });
}

static void downloadAndSetWallpaper(void) {
    if (!gWallpaperURL || gWallpaperURL.length == 0) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️️ 网络 URL 为空");
        return;
    }
    NSURL *url = [NSURL URLWithString:gWallpaperURL];
    if (!url) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️ URL 格式错误");
        return;
    }

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            NSLog(@"[AutoOnlineWallpaper] ❌ 网络图片下载失败: %@", err.localizedDescription);
            return;
        }
        if (!data) return;
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            setWallpaperImage(img);
        } else {
            NSLog(@"[AutoOnlineWallpaper] ❌ 图片解析失败");
        }
    }];
    [task resume];
}

static void setLocalWallpaper(void) {
    if (!gLocalPath || gLocalPath.length == 0) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️ 本地路径为空");
        return;
    }

    NSString *realPath = jbroot(gLocalPath);
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;

    if (![fm fileExistsAtPath:realPath isDirectory:&isDir]) {
        NSLog(@"[AutoOnlineWallpaper] ❌ 本地路径不存在: %@", realPath);
        return;
    }

    NSString *targetImagePath = nil;

    if (isDir) {
        NSArray *files = [fm contentsOfDirectoryAtPath:realPath error:nil];
        NSMutableArray *imageFiles = [NSMutableArray array];
        for (NSString *file in files) {
            NSString *ext = [file pathExtension].lowercaseString;
            if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
                [ext isEqualToString:@"png"] || [ext isEqualToString:@"heic"]) {
                [imageFiles addObject:[realPath stringByAppendingPathComponent:file]];
            }
        }

        if (imageFiles.count == 0) {
            NSLog(@"[AutoOnlineWallpaper] ⚠️ 该目录下没有发现可用图片文件");
            return;
        }

        uint32_t randomIndex = arc4random_uniform((uint32_t)imageFiles.count);
        targetImagePath = imageFiles[randomIndex];
    } else {
        targetImagePath = realPath;
    }

    UIImage *img = [UIImage imageWithContentsOfFile:targetImagePath];
    if (img) {
        NSLog(@"[AutoOnlineWallpaper] 🖼️ 加载本地图片: %@", targetImagePath);
        setWallpaperImage(img);
    } else {
        NSLog(@"[AutoOnlineWallpaper] ❌ 本地图片加载失败: %@", targetImagePath);
    }
}

static void triggerWallpaperChange(void) {
    if (gMode == 1) {
        setLocalWallpaper();
    } else {
        downloadAndSetWallpaper();
    }
}

static void readSettings(void) {
    NSString *plistPath = jbroot(@"/var/mobile/Library/Preferences/com.user.autoonlinewallpaper.plist");
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!cfg) cfg = @{};

    BOOL enable = [cfg[@"enable"] boolValue];
    gMode = [cfg[@"mode"] integerValue];
    gWallpaperURL = cfg[@"url"] ?: @"";
    gLocalPath = cfg[@"localPath"] ?: @"";
    NSTimeInterval interval = [cfg[@"interval"] doubleValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gWallpaperTimer) {
            [gWallpaperTimer invalidate];
            gWallpaperTimer = nil;
        }

        BOOL validConfig = (gMode == 0 && gWallpaperURL.length > 0) || (gMode == 1 && gLocalPath.length > 0);

        if (enable && validConfig) {
            if (interval < 10) interval = 60;
            gWallpaperTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
                triggerWallpaperChange();
            }];
            triggerWallpaperChange();
            NSLog(@"[AutoOnlineWallpaper] 🟢 iOS 17 启动定时器，模式: %ld，间隔: %.0f秒", (long)gMode, interval);
        } else {
            NSLog(@"[AutoOnlineWallpaper] 🔴 插件未启用或路径/URL未设置");
        }
    });
}

static void handleNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notifyName = (__bridge NSString *)name;
    if ([notifyName isEqualToString:@"com.user.autoonlinewallpaper.settingschanged"]) {
        NSLog(@"[AutoOnlineWallpaper] 📥 重载配置");
        readSettings();
    } else if ([notifyName isEqualToString:@"com.user.autoonlinewallpaper.triggernow"]) {
        NSLog(@"[AutoOnlineWallpaper] 🖱️ 用户手动触发更换");
        triggerWallpaperChange();
    }
}

%ctor {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        handleNotification,
        CFSTR("com.user.autoonlinewallpaper.settingschanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        handleNotification,
        CFSTR("com.user.autoonlinewallpaper.triggernow"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    readSettings();
}
%end#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#if __has_include(<root-hide/root-hide.h>)
    #import <root-hide/root-hide.h>
#else
    #define jbroot(path) path
#endif

// iOS 17 PaperBoardUI 接口声明
@interface PBUIWallpaperController : NSObject
+ (id)sharedInstance;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations completionHandler:(void (^)(void))completionHandler;
@end

// 兼容 SBWallpaperController 声明
@interface SBWallpaperController : NSObject
+ (id)sharedInstance;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations;
- (BOOL)setWallpaperImage:(UIImage *)image forLocations:(NSInteger)locations completionHandler:(void (^)(void))completionHandler;
@end

static NSInteger gMode = 0; // 0: 网络直链, 1: 本地路径/文件夹
static NSString *gWallpaperURL = nil;
static NSString *gLocalPath = nil;
static NSTimer *gWallpaperTimer = nil;

static void setWallpaperImage(UIImage *image) {
    if (!image) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger locations = 3; // 1: 锁屏, 2: 主屏, 3: 锁屏+主屏
        id wallpaperController = nil;

        // 1. 优先获取 iOS 17 的 PBUIWallpaperController (PaperBoardUI.framework)
        Class PBUIWallpaperControllerClass = %c(PBUIWallpaperController);
        if (PBUIWallpaperControllerClass && [PBUIWallpaperControllerClass respondsToSelector:@selector(sharedInstance)]) {
            wallpaperController = [PBUIWallpaperControllerClass sharedInstance];
        }

        // 2. 回退机制：若未获取到则尝试获取 SBWallpaperController
        if (!wallpaperController) {
            Class SBWallpaperControllerClass = %c(SBWallpaperController);
            if (SBWallpaperControllerClass && [SBWallpaperControllerClass respondsToSelector:@selector(sharedInstance)]) {
                wallpaperController = [SBWallpaperControllerClass sharedInstance];
            }
        }

        if (!wallpaperController) {
            NSLog(@"[AutoOnlineWallpaper] ❌ 无法获取 WallpaperController 实例");
            return;
        }

        // 3. 执行壁纸更新逻辑
        if ([wallpaperController respondsToSelector:@selector(setWallpaperImage:forLocations:completionHandler:)]) {
            [wallpaperController setWallpaperImage:image forLocations:locations completionHandler:^{
                NSLog(@"[AutoOnlineWallpaper] ✅ iOS 17 壁纸更新成功 (completionHandler)");
            }];
        } else if ([wallpaperController respondsToSelector:@selector(setWallpaperImage:forLocations:)]) {
            [wallpaperController setWallpaperImage:image forLocations:locations];
            NSLog(@"[AutoOnlineWallpaper] ✅ iOS 17 壁纸更新成功 (setWallpaperImage:forLocations:)");
        } else {
            NSLog(@"[AutoOnlineWallpaper] ❌ 当前系统未找到兼容的壁纸设置 API");
        }
    });
}

static void downloadAndSetWallpaper(void) {
    if (!gWallpaperURL || gWallpaperURL.length == 0) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️️ 网络 URL 为空");
        return;
    }
    NSURL *url = [NSURL URLWithString:gWallpaperURL];
    if (!url) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️ URL 格式错误");
        return;
    }

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            NSLog(@"[AutoOnlineWallpaper] ❌ 网络图片下载失败: %@", err.localizedDescription);
            return;
        }
        if (!data) return;
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            setWallpaperImage(img);
        } else {
            NSLog(@"[AutoOnlineWallpaper] ❌ 图片解析失败");
        }
    }];
    [task resume];
}

static void setLocalWallpaper(void) {
    if (!gLocalPath || gLocalPath.length == 0) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️ 本地路径为空");
        return;
    }

    NSString *realPath = jbroot(gLocalPath);
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;

    if (![fm fileExistsAtPath:realPath isDirectory:&isDir]) {
        NSLog(@"[AutoOnlineWallpaper] ❌ 本地路径不存在: %@", realPath);
        return;
    }

    NSString *targetImagePath = nil;

    if (isDir) {
        NSArray *files = [fm contentsOfDirectoryAtPath:realPath error:nil];
        NSMutableArray *imageFiles = [NSMutableArray array];
        for (NSString *file in files) {
            NSString *ext = [file pathExtension].lowercaseString;
            if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
                [ext isEqualToString:@"png"] || [ext isEqualToString:@"heic"]) {
                [imageFiles addObject:[realPath stringByAppendingPathComponent:file]];
            }
        }

        if (imageFiles.count == 0) {
            NSLog(@"[AutoOnlineWallpaper] ⚠️ 该目录下没有发现可用图片文件");
            return;
        }

        uint32_t randomIndex = arc4random_uniform((uint32_t)imageFiles.count);
        targetImagePath = imageFiles[randomIndex];
    } else {
        targetImagePath = realPath;
    }

    UIImage *img = [UIImage imageWithContentsOfFile:targetImagePath];
    if (img) {
        NSLog(@"[AutoOnlineWallpaper] 🖼️ 加载本地图片: %@", targetImagePath);
        setWallpaperImage(img);
    } else {
        NSLog(@"[AutoOnlineWallpaper] ❌ 本地图片加载失败: %@", targetImagePath);
    }
}

static void triggerWallpaperChange(void) {
    if (gMode == 1) {
        setLocalWallpaper();
    } else {
        downloadAndSetWallpaper();
    }
}

static void readSettings(void) {
    NSString *plistPath = jbroot(@"/var/mobile/Library/Preferences/com.user.autoonlinewallpaper.plist");
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!cfg) cfg = @{};

    BOOL enable = [cfg[@"enable"] boolValue];
    gMode = [cfg[@"mode"] integerValue];
    gWallpaperURL = cfg[@"url"] ?: @"";
    gLocalPath = cfg[@"localPath"] ?: @"";
    NSTimeInterval interval = [cfg[@"interval"] doubleValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gWallpaperTimer) {
            [gWallpaperTimer invalidate];
            gWallpaperTimer = nil;
        }

        BOOL validConfig = (gMode == 0 && gWallpaperURL.length > 0) || (gMode == 1 && gLocalPath.length > 0);

        if (enable && validConfig) {
            if (interval < 10) interval = 60;
            gWallpaperTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
                triggerWallpaperChange();
            }];
            triggerWallpaperChange();
            NSLog(@"[AutoOnlineWallpaper] 🟢 iOS 17 启动定时器，模式: %ld，间隔: %.0f秒", (long)gMode, interval);
        } else {
            NSLog(@"[AutoOnlineWallpaper] 🔴 插件未启用或路径/URL未设置");
        }
    });
}

static void handleNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notifyName = (__bridge NSString *)name;
    if ([notifyName isEqualToString:@"com.user.autoonlinewallpaper.settingschanged"]) {
        NSLog(@"[AutoOnlineWallpaper] 📥 重载配置");
        readSettings();
    } else if ([notifyName isEqualToString:@"com.user.autoonlinewallpaper.triggernow"]) {
        NSLog(@"[AutoOnlineWallpaper] 🖱️ 用户手动触发更换");
        triggerWallpaperChange();
    }
}

%ctor {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        handleNotification,
        CFSTR("com.user.autoonlinewallpaper.settingschanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        handleNotification,
        CFSTR("com.user.autoonlinewallpaper.triggernow"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    readSettings();
}
%end
