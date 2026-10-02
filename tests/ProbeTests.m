// SPDX-License-Identifier: MIT
#import "../HBProbe.h"

static int checks;
static void Check(BOOL ok, NSString *name) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", name.UTF8String); exit(1); }
    checks++;
}
static NSUInteger scenario;
@interface FixtureProtocol : NSURLProtocol
@end
@implementation FixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    Check(![self.request valueForHTTPHeaderField:@"Authorization"] && ![self.request valueForHTTPHeaderField:@"Cookie"], @"request has no credentials or cookies");
    NSURL *url = scenario == 4 ? [NSURL URLWithString:@"https://unexpected.invalid/"] : self.request.URL;
    NSInteger status = scenario == 5 ? 500 : [url.host isEqual:@"www.gstatic.com"] ? 204 : 200;
    NSDictionary *headers = scenario == 2 ? @{@"Content-Length":@"1000000000"} : @{};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (scenario == 3) {
        // Missing Content-Length, several individually small chunks.
        for (NSUInteger n = 0; n < 6; n++) [self.client URLProtocol:self didLoadData:[NSMutableData dataWithLength:1024]];
    } else if (scenario == 6) {
        [self.client URLProtocol:self didLoadData:[@"captive portal login" dataUsingEncoding:NSUTF8StringEncoding]];
    } else if (status == 200) {
        [self.client URLProtocol:self didLoadData:[@"<HTML><BODY>Success</BODY></HTML>" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void RunFixture(NSUInteger fixture, NSUInteger index, BOOL expected) {
    scenario = fixture;
    NSURLSessionConfiguration *config = HBProbeConfiguration();
    config.protocolClasses = @[FixtureProtocol.class];
    __block BOOL done = NO;
    HBProbe *probe = [[HBProbe alloc] initWithIndex:index configuration:config completion:^(BOOL reachable, NSTimeInterval seconds) {
        Check(reachable == expected, [NSString stringWithFormat:@"fixture %lu result", (unsigned long)fixture]);
        Check(seconds >= 0 && seconds < 5, @"bounded fixture completion");
        done = YES;
    }];
    [probe start];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(done, @"probe completes");
    Check(probe.bufferedBytes <= HBProbeBodyLimit, @"response buffer stays bounded");
}

int main(void) {
    @autoreleasepool {
        NSURLSessionConfiguration *config = HBProbeConfiguration();
        Check(!config.URLCache && !config.HTTPCookieStorage && !config.URLCredentialStorage && !config.HTTPShouldSetCookies, @"no cache, cookie, or credential storage");
        Check(config.timeoutIntervalForResource == 5 && config.timeoutIntervalForRequest == 4, @"resource deadlines");
        RunFixture(0, 0, YES);
        RunFixture(1, 1, YES);
        RunFixture(2, 0, NO);
        RunFixture(3, 0, NO);
        RunFixture(4, 0, NO);
        RunFixture(5, 0, NO);
        RunFixture(6, 0, NO);

        // Exercise redirect/auth delegate contracts directly, without sending
        // requests to a third party or weakening TLS for a local test server.
        __block BOOL completed = NO;
        HBProbe *probe = [[HBProbe alloc] initWithIndex:0 configuration:config completion:^(BOOL ok, NSTimeInterval seconds) { completed = YES; Check(!ok, @"redirect cannot produce success"); }];
        [probe URLSession:nil task:nil willPerformHTTPRedirection:nil newRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://unexpected.invalid/"]] completionHandler:^(NSURLRequest *request) { Check(request == nil, @"redirect is refused before contact"); }];
        NSHTTPURLResponse *success = [[NSHTTPURLResponse alloc] initWithURL:HBProbeURL(0) statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
        [probe URLSession:nil dataTask:nil didReceiveResponse:success completionHandler:^(NSURLSessionResponseDisposition disposition) { Check(disposition == NSURLSessionResponseCancel, @"redirect rejection cannot be reset"); }];
        [probe URLSession:nil task:nil didCompleteWithError:nil];
        Check(completed, @"rejected request reports failure");
        for (NSString *method in @[NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodNTLM, NSURLAuthenticationMethodNegotiate, NSURLAuthenticationMethodClientCertificate, NSURLAuthenticationMethodServerTrust]) {
            NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"captive.apple.com" port:443 protocol:@"https" realm:nil authenticationMethod:method];
            NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space proposedCredential:nil previousFailureCount:0 failureResponse:nil error:nil sender:nil];
            void (^answer)(NSURLSessionAuthChallengeDisposition, NSURLCredential *) = ^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential) {
                BOOL trust = [method isEqual:NSURLAuthenticationMethodServerTrust];
                Check(disposition == (trust ? NSURLSessionAuthChallengePerformDefaultHandling : NSURLSessionAuthChallengeCancelAuthenticationChallenge) && credential == nil, @"normal TLS trust, no other authentication");
            };
            [probe URLSession:nil didReceiveChallenge:challenge completionHandler:answer];
            [probe URLSession:nil task:nil didReceiveChallenge:challenge completionHandler:answer];
        }
        __block BOOL canceledCompletion = NO;
        HBProbe *canceled = [[HBProbe alloc] initWithIndex:0 configuration:config completion:^(BOOL ok, NSTimeInterval seconds) { canceledCompletion = YES; }];
        [canceled cancel];
        [canceled URLSession:nil task:nil didCompleteWithError:nil];
        Check(!canceledCompletion, @"cancel suppresses late callback");
        printf("PASS: %d probe security checks\n", checks);
    }
    return 0;
}
