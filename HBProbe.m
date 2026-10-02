// SPDX-License-Identifier: MIT
#import "HBProbe.h"

const NSUInteger HBProbeBodyLimit = 4096;
NSURL *HBProbeURL(NSUInteger index) {
    return [NSURL URLWithString:index == 0 ? @"https://captive.apple.com/hotspot-detect.html" : @"https://www.gstatic.com/generate_204"];
}
NSURLSessionConfiguration *HBProbeConfiguration(void) {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.URLCache = nil;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.URLCredentialStorage = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForRequest = 4;
    config.timeoutIntervalForResource = 5;
    config.HTTPMaximumConnectionsPerHost = 1;
    return config;
}

@interface HBProbe ()
@property NSUInteger index;
@property NSURLSessionConfiguration *configuration;
@property NSURLSession *session;
@property NSURLSessionDataTask *task;
@property NSMutableData *body;
@property(copy) void (^completion)(BOOL, NSTimeInterval);
@property NSTimeInterval started;
@property BOOL acceptedResponse;
@property BOOL rejected;
@end

@implementation HBProbe
- (instancetype)initWithIndex:(NSUInteger)index configuration:(NSURLSessionConfiguration *)configuration completion:(void (^)(BOOL, NSTimeInterval))completion {
    self = [super init];
    if (self) {
        _index = index;
        _configuration = configuration;
        _completion = [completion copy];
        _body = [NSMutableData data];
    }
    return self;
}
- (NSUInteger)bufferedBytes { return self.body.length; }
- (void)start {
    NSAssert(NSThread.isMainThread, @"Probe ownership requires the main thread");
    if (self.session || !self.completion) return;
    self.started = NSProcessInfo.processInfo.systemUptime;
    self.session = [NSURLSession sessionWithConfiguration:self.configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:HBProbeURL(self.index)];
    request.timeoutInterval = 4;
    request.HTTPShouldHandleCookies = NO;
    self.task = [self.session dataTaskWithRequest:request];
    [self.task resume];
}
- (void)cancel {
    self.completion = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    self.task = nil;
    [self.body setLength:0];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    self.acceptedResponse = !self.rejected && http &&
        [http.URL.absoluteString isEqualToString:HBProbeURL(self.index).absoluteString] &&
        http.statusCode == (self.index == 0 ? 200 : 204) &&
        http.expectedContentLength <= (int64_t)HBProbeBodyLimit;
    if (!self.acceptedResponse) self.rejected = YES;
    completionHandler(self.acceptedResponse ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    // Check before appending, including responses with absent/false lengths
    // and decompressed bodies. NSURLSession's internal buffers are OS-owned.
    if (!self.acceptedResponse || self.rejected || data.length > HBProbeBodyLimit - self.body.length) {
        self.rejected = YES;
        [task cancel];
        return;
    }
    [self.body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    self.rejected = YES;
    completionHandler(nil);
}
- (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge completion:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completion {
    // Keep Apple's normal certificate validation. Never supply passwords,
    // client certificates, or automatic HTTP/NTLM/Negotiate credentials.
    BOOL serverTrust = [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
    completion(serverTrust ? NSURLSessionAuthChallengePerformDefaultHandling : NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
}
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    [self handleChallenge:challenge completion:completionHandler];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    [self handleChallenge:challenge completion:completionHandler];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSString *body = [[NSString alloc] initWithData:self.body encoding:NSUTF8StringEncoding];
    BOOL good = !error && !self.rejected && self.acceptedResponse &&
        (self.index == 0 ? [body containsString:@"<BODY>Success</BODY>"] : self.body.length == 0);
    void (^completion)(BOOL, NSTimeInterval) = self.completion;
    self.completion = nil;
    [self.session finishTasksAndInvalidate];
    self.session = nil;
    self.task = nil;
    if (completion) completion(good, NSProcessInfo.processInfo.systemUptime - self.started);
}
@end
