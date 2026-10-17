#import <Foundation/Foundation.h>

@interface MetalSprocketsParticles_BundleFinder : NSObject
@end

@implementation MetalSprocketsParticles_BundleFinder
@end

@implementation NSBundle (MetalSprocketsParticles)

+ (NSBundle *)metalSprocketsParticlesShadersBundle {
    static NSBundle *moduleBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleName = @"MetalSprocketsParticles_MetalSprocketsParticlesShaders";
        NSMutableArray<NSURL *> *candidates = [NSMutableArray array];

        // Detect SPM CLI test mode (swift test command)
        // When true, mainBundle is swiftpm-testing-helper instead of the actual test bundle
        BOOL isSPMTestMode = [[[NSProcessInfo processInfo] processName] isEqualToString:@"swiftpm-testing-helper"];

#if DEBUG
        // Environment variable override for development/debugging
        NSDictionary *env = [[NSProcessInfo processInfo] environment];
        NSString *overridePath = env[@"PACKAGE_RESOURCE_BUNDLE_PATH"] ?: env[@"PACKAGE_RESOURCE_BUNDLE_URL"];
        if (overridePath) {
            [candidates addObject:[NSURL fileURLWithPath:overridePath]];
        }
#endif

        // Standard SPM bundle locations (works for Xcode tests, regular apps, and production)
        [candidates addObject:[NSBundle mainBundle].resourceURL];
        [candidates addObject:[[NSBundle bundleForClass:[MetalSprocketsParticles_BundleFinder class]] resourceURL]];
        [candidates addObject:[NSBundle mainBundle].bundleURL];

        if (isSPMTestMode) {
            // SPM CLI test workaround: Find the actual test .xctest bundle in loaded bundles,
            // then check its parent directory where sibling .bundle files live
            // Structure: .build/debug/Foo.xctest and .build/debug/Bar.bundle are siblings
            for (NSBundle *loadedBundle in [NSBundle allBundles]) {
                NSURL *bundleURL = loadedBundle.bundleURL;
                if (bundleURL && [[bundleURL pathExtension] isEqualToString:@"xctest"]) {
                    NSURL *parentDir = [bundleURL URLByDeletingLastPathComponent];
                    [candidates addObject:parentDir];
                }
            }
        }

        // Search all candidate locations
        for (NSURL *candidate in candidates) {
            if (!candidate) continue;

            NSURL *bundlePath = [candidate URLByAppendingPathComponent:[bundleName stringByAppendingString:@".bundle"]];
            NSBundle *bundle = [NSBundle bundleWithURL:bundlePath];
            if (bundle) {
                moduleBundle = bundle;
                return;
            }
        }

        // Bundle not found
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"Unable to find bundle named %@", bundleName]
                                     userInfo:nil];
    });

    return moduleBundle;
}

@end
