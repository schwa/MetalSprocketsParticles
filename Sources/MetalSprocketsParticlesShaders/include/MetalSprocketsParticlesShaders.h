#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NSBundle (MetalSprocketsParticles)
+ (NSBundle *)metalSprocketsParticlesShadersBundle;
@end
NS_ASSUME_NONNULL_END
#endif

#import "MetalSprocketsShaders.h"
#import "ParticleTypes.h"
