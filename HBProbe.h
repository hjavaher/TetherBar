// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern const NSUInteger HBProbeBodyLimit;
NSURL *HBProbeURL(NSUInteger index);
NSURLSessionConfiguration *HBProbeConfiguration(void);

// One bounded request. All methods and callbacks run on the main thread.
@interface HBProbe : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, readonly) NSUInteger bufferedBytes;
- (instancetype)initWithIndex:(NSUInteger)index
                configuration:(NSURLSessionConfiguration *)configuration
                   completion:(void (^)(BOOL reachable, NSTimeInterval seconds))completion;
- (void)start;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
