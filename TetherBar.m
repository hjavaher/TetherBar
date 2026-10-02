// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#import "HBProbe.h"
#import <CoreWLAN/CoreWLAN.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dlfcn.h>

// Undocumented Apple interfaces: runtime availability is checked before use.
@interface HBWiFi : NSObject
- (void)activate;
- (void)invalidate;
- (NSString *)interfaceName;
- (NSString *)networkName;
- (id)currentScanResult;
@end
@interface HBScan : NSObject
- (BOOL)isPersonalHotspot;
@end
@interface HBHotspotSession : NSObject
- (void)setDelegate:(id)delegate;
- (void)startBrowsing;
- (void)stopBrowsing;
@end
@interface HBHotspotDevice : NSObject
- (NSString *)deviceName;
- (NSNumber *)signalStrength;
- (unsigned char)networkType;
- (BOOL)cachedDevice;
@end

static NSString *HBNetworkLabel(NSInteger type) {
    NSArray *labels = @[@"No service", @"1x", @"GPRS", @"EDGE", @"3G", @"HSDPA", @"4G", @"LTE", @"5G"];
    return type >= 0 && type < (NSInteger)labels.count ? labels[type] : @"Cellular";
}

// Testable decisions consume snapshots rather than contacting system services.
static NSDictionary *HBChooseConnection(NSArray<NSDictionary *> *services, NSString *primary) {
    BOOL primaryIsPhysical = primary.length && ![primary hasPrefix:@"utun"] && ![primary hasPrefix:@"ppp"] && ![primary hasPrefix:@"ipsec"];
    for (NSDictionary *s in services) {
        if (primaryIsPhysical && ![s[@"interface"] isEqual:primary]) continue;
        if (![s[@"active"] boolValue] || ![s[@"hasIP"] boolValue]) continue;
        // The first active physical service in system priority order is the
        // underlay candidate when a VPN owns the global primary interface.
        if ([s[@"usb"] boolValue]) return s;
        if ([s[@"personal"] boolValue]) return s;
        return nil;
    }
    return nil;
}

static NSDictionary *HBChooseReading(NSArray<NSDictionary *> *readings, NSDictionary *connection) {
    if (!connection) return nil;
    if ([connection[@"usb"] boolValue]) {
        // Never guess between multiple nearby phones on USB.
        return readings.count == 1 ? readings.firstObject : nil;
    }
    NSString *ssid = connection[@"ssid"];
    if (!ssid.length) return nil;
    NSArray *matches = [readings filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *r, NSDictionary *bindings) {
        return [r[@"name"] isEqual:ssid];
    }]];
    return matches.count == 1 ? matches.firstObject : nil;
}

static BOOL HBFreshReading(NSDictionary *reading, NSTimeInterval updated) {
    NSNumber *bars = reading[@"bars"];
    NSTimeInterval age = NSProcessInfo.processInfo.systemUptime - updated;
    return [bars isKindOfClass:NSNumber.class] && bars.doubleValue == bars.integerValue && bars.integerValue >= 0 && bars.integerValue <= 4 && updated > 0 && age >= 0 && age < 60;
}

typedef NS_ENUM(NSInteger, HBHealth) { HBHealthy, HBWeak, HBOffline };
typedef NS_ENUM(NSInteger, HBInternetState) {
    HBInternetChecking = -1, HBInternetOffline, HBInternetGood, HBInternetSlow, HBInternetUnstable
};
static const NSTimeInterval HBSlowResponseSeconds = 3;
typedef struct { unsigned recentBad; unsigned consecutiveGood; } HBInternetHistory;

static HBInternetState HBRecordInternetCheck(HBInternetHistory *history, BOOL reachable, NSTimeInterval seconds) {
    BOOL slow = reachable && seconds > HBSlowResponseSeconds;
    BOOL bad = !reachable || slow;
    history->recentBad = ((history->recentBad << 1) | (unsigned)bad) & 31;
    history->consecutiveGood = bad ? 0 : MIN(history->consecutiveGood + 1, 2U);
    if (!reachable) return HBInternetOffline;
    if (slow) return HBInternetSlow;
    // Two bad rounds in the last five indicate instability. Require two
    // consecutive responsive rounds to clear it, avoiding red/white flicker.
    if (__builtin_popcount(history->recentBad) >= 2 && history->consecutiveGood < 2) return HBInternetUnstable;
    return HBInternetGood;
}

static HBHealth HBConnectionHealth(NSDictionary *reading, BOOL fresh, NSInteger internet) {
    if (internet == HBInternetOffline || internet == HBInternetSlow || internet == HBInternetUnstable) return HBOffline;
    if (internet == HBInternetChecking || !fresh) return HBWeak;
    NSInteger type = [reading[@"type"] integerValue];
    NSInteger bars = [reading[@"bars"] integerValue];
    if (type <= 0 || type > 8 || bars <= (type == 8 ? 1 : 2)) return HBWeak;
    return HBHealthy;
}

static int HBSelfTest(void) {
    __block int count = 0;
    void (^check)(BOOL, NSString *) = ^(BOOL ok, NSString *name) {
        if (!ok) { fprintf(stderr, "FAIL: %s\n", name.UTF8String); exit(1); }
        count++;
    };
    NSDictionary *usb = @{@"interface":@"en10", @"active":@YES, @"hasIP":@YES, @"usb":@YES};
    NSDictionary *home = @{@"interface":@"en0", @"active":@YES, @"hasIP":@YES};
    NSDictionary *phone = @{@"interface":@"en0", @"active":@YES, @"hasIP":@YES, @"personal":@YES, @"ssid":@"Test Phone"};
    NSDictionary *r = @{@"name":@"Test Phone", @"bars":@0, @"type":@8};
    check(HBChooseConnection(@[], nil) == nil, @"offline stays hidden");
    check(HBChooseConnection(@[home], @"en0") == nil, @"ordinary Wi-Fi stays hidden");
    check(HBChooseConnection(@[phone], @"en0") != nil, @"Wi-Fi hotspot shows");
    check(HBChooseConnection(@[usb], @"en10") != nil, @"USB hotspot shows");
    check(HBChooseConnection(@[home, usb], @"en0") == nil, @"ordinary primary wins over plugged-in USB");
    check(HBChooseConnection(@[usb], @"utun4") != nil, @"VPN over USB shows");
    check(HBChooseConnection(@[home, usb], @"utun4") == nil, @"VPN over higher-priority ordinary Wi-Fi stays hidden");
    NSMutableDictionary *inactive = [usb mutableCopy]; inactive[@"active"] = @NO;
    check(HBChooseConnection(@[inactive], @"en10") == nil, @"retained inactive USB stays hidden");
    inactive[@"active"] = @YES; inactive[@"hasIP"] = @NO;
    check(HBChooseConnection(@[inactive], @"en10") == nil, @"charging-only USB stays hidden");
    check(HBChooseReading(@[r], nil) == nil, @"nearby phone alone never shows");
    check(HBChooseReading(@[r], phone) != nil, @"associated phone is matched");
    check(HBChooseReading(@[@{@"name":@"Other Phone"}], phone) == nil, @"unrelated phone is rejected");
    check(HBChooseReading(@[r, r], phone) == nil, @"duplicate names are ambiguous");
    check(HBChooseReading(@[r, r], usb) == nil, @"multiple USB candidates are ambiguous");
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    check(HBFreshReading(r, now), @"zero cellular bars remain valid");
    check(!HBFreshReading(r, now - 61), @"old readings expire");
    check(!HBFreshReading(@{@"bars":@5}, now), @"unexpected bar range is rejected");
    check(!HBFreshReading(@{@"bars":@"4"}, now), @"non-numeric signal is rejected");
    check(!HBFreshReading(@{@"bars":@1.5}, now), @"fractional signal is rejected");
    check(!HBFreshReading(r, now + 60), @"future timestamps are rejected");
    check([HBNetworkLabel(8) isEqual:@"5G"], @"5G never fabricates UW");
    check(HBConnectionHealth(@{@"bars":@4, @"type":@8}, YES, 1) == HBHealthy, @"strong 5G with internet is normal");
    check(HBConnectionHealth(@{@"bars":@1, @"type":@8}, YES, 1) == HBWeak, @"one bar of 5G is yellow");
    check(HBConnectionHealth(@{@"bars":@2, @"type":@8}, YES, 1) == HBHealthy, @"two bars of 5G is white");
    check(HBConnectionHealth(@{@"bars":@2, @"type":@7}, YES, 1) == HBWeak, @"two bars of LTE is yellow");
    check(HBConnectionHealth(@{@"bars":@3, @"type":@7}, YES, 1) == HBHealthy, @"three bars of LTE is white");
    check(HBConnectionHealth(@{@"bars":@4, @"type":@7}, YES, 1) == HBHealthy, @"full LTE with good internet is white");
    check(HBConnectionHealth(@{@"bars":@4, @"type":@8}, YES, 0) == HBOffline, @"no internet overrides strong bars with red");
    check(HBConnectionHealth(nil, NO, 0) == HBOffline, @"failed internet with missing signal is red");
    check(HBConnectionHealth(nil, NO, -1) == HBWeak, @"unverified connection does not claim healthy");
    check(HBConnectionHealth(@{@"bars":@4, @"type":@9}, YES, 1) == HBWeak, @"unknown network type is not assumed healthy 5G");
    check(HBConnectionHealth(@{@"bars":@4, @"type":@8}, YES, HBInternetSlow) == HBOffline, @"slow internet overrides full 5G with red");
    check(HBConnectionHealth(@{@"bars":@3, @"type":@7}, YES, HBInternetUnstable) == HBOffline, @"unstable internet overrides strong LTE with red");
    HBInternetHistory history = {0};
    check(HBRecordInternetCheck(&history, YES, 3) == HBInternetGood, @"three-second boundary remains responsive");
    check(HBRecordInternetCheck(&history, YES, 3.01) == HBInternetSlow, @"slow successful request is red");
    check(HBRecordInternetCheck(&history, YES, 0.2) == HBInternetGood, @"single slow round clears after responsive recovery");
    check(HBRecordInternetCheck(&history, NO, 4) == HBInternetOffline, @"failed check is red immediately");
    check(HBRecordInternetCheck(&history, YES, 0.2) == HBInternetUnstable, @"repeated bad rounds stay red through first recovery");
    check(HBRecordInternetCheck(&history, YES, 0.2) == HBInternetGood, @"second responsive recovery clears instability");
    history = (HBInternetHistory){0};
    check(HBRecordInternetCheck(&history, YES, 0.2) == HBInternetGood, @"new connection discards old failure history");
    printf("PASS: %d connection, signal, internet-quality, and color checks\n", count);
    return 0;
}

@interface HotspotBars : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property NSStatusItem *item;
@property NSMenuItem *summaryItem;
@property NSMenuItem *loginItem;
@property HBWiFi *wifi;
@property HBHotspotSession *session;
@property NSDictionary *connection;
@property NSDictionary *reading;
@property NSTimeInterval readingDate;
@property NSTimer *refreshTimer;
@property NSTimer *browseStopTimer;
@property BOOL sleeping;
@property BOOL diagnostic;
@property BOOL refreshScheduled;
@property NSString *lastDiagnostic;
@property SCDynamicStoreRef store;
@property HBProbe *internetProbe;
@property HBInternetState internetState;
@property HBInternetHistory internetHistory;
@property BOOL primaryWasSlow;
@property NSUInteger connectionGeneration;
- (void)scheduleConnectionRefresh;
@end

static void HBStoreChanged(SCDynamicStoreRef store, CFArrayRef keys, void *context) {
    [(__bridge HotspotBars *)context scheduleConnectionRefresh];
}

@implementation HotspotBars
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.diagnostic = [NSProcessInfo.processInfo.arguments containsObject:@"--diagnose"];
    dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_LAZY);
    Class wifiClass = NSClassFromString(@"CWFInterface");
    if ([wifiClass instancesRespondToSelector:@selector(activate)] && [wifiClass instancesRespondToSelector:@selector(invalidate)] && [wifiClass instancesRespondToSelector:@selector(interfaceName)] && [wifiClass instancesRespondToSelector:@selector(currentScanResult)] && [wifiClass instancesRespondToSelector:@selector(networkName)]) {
        self.wifi = [wifiClass new]; [self.wifi activate];
    }
    SCDynamicStoreContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    self.store = SCDynamicStoreCreate(NULL, CFSTR("TetherBar"), HBStoreChanged, &context);
    if (self.store) {
        NSArray *patterns = @[@"State:/Network/Interface/.*/(Link|AirPort)", @"State:/Network/Service/.*/IPv[46]", @"State:/Network/Global/IPv[46]", @"Setup:/Network/.*"];
        SCDynamicStoreSetNotificationKeys(self.store, NULL, (__bridge CFArrayRef)patterns);
        SCDynamicStoreSetDispatchQueue(self.store, dispatch_get_main_queue());
    }
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    [center addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [center addObserver:self selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [self refreshConnection];
    if (self.diagnostic) {
        [NSTimer scheduledTimerWithTimeInterval:25 repeats:NO block:^(NSTimer *timer) { [NSApp terminate:nil]; }];
    }
}

- (NSDictionary *)storeValue:(NSString *)key {
    if (!self.store) return nil;
    id value = CFBridgingRelease(SCDynamicStoreCopyValue(self.store, (__bridge CFStringRef)key));
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

- (NSDictionary *)readConnection {
    SCPreferencesRef prefs = SCPreferencesCreate(NULL, CFSTR("TetherBar"), NULL);
    if (!prefs) return nil;
    SCNetworkSetRef set = SCNetworkSetCopyCurrent(prefs);
    NSArray *order = set ? [(__bridge NSArray *)SCNetworkSetGetServiceOrder(set) copy] : @[];
    NSArray *services = CFBridgingRelease(SCNetworkServiceCopyAll(prefs));
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    for (id obj in services) {
        SCNetworkServiceRef service = (__bridge SCNetworkServiceRef)obj;
        byID[(__bridge NSString *)SCNetworkServiceGetServiceID(service)] = obj;
    }
    NSMutableArray *snapshots = [NSMutableArray array];
    NSString *wifiInterface = [self.wifi interfaceName];
    HBScan *scan = [self.wifi currentScanResult];
    BOOL isPersonal = [scan respondsToSelector:@selector(isPersonalHotspot)] && [scan isPersonalHotspot];
    NSString *ssid = [self.wifi networkName];
    if (![wifiInterface isKindOfClass:NSString.class]) wifiInterface = nil;
    if (![ssid isKindOfClass:NSString.class]) ssid = nil;
    for (NSString *sid in order) {
        SCNetworkServiceRef service = (__bridge SCNetworkServiceRef)byID[sid];
        if (!service || !SCNetworkServiceGetEnabled(service)) continue;
        SCNetworkInterfaceRef iface = SCNetworkServiceGetInterface(service);
        if (!iface) continue;
        NSString *name = (__bridge NSString *)SCNetworkInterfaceGetBSDName(iface);
        NSString *type = (__bridge NSString *)SCNetworkInterfaceGetInterfaceType(iface);
        if (!name || (![type isEqual:(__bridge NSString *)kSCNetworkInterfaceTypeEthernet] && ![type isEqual:(__bridge NSString *)kSCNetworkInterfaceTypeIEEE80211] && ![type isEqual:@"Bridge"])) continue;
        NSString *displayName = (__bridge NSString *)SCNetworkInterfaceGetLocalizedDisplayName(iface);
        NSDictionary *link = [self storeValue:[NSString stringWithFormat:@"State:/Network/Interface/%@/Link", name]];
        NSDictionary *ip4 = [self storeValue:[NSString stringWithFormat:@"State:/Network/Service/%@/IPv4", sid]];
        NSDictionary *ip6 = [self storeValue:[NSString stringWithFormat:@"State:/Network/Service/%@/IPv6", sid]];
        BOOL hasIP = [ip4[@"Addresses"] count] > 0 || [ip6[@"Addresses"] count] > 0;
        // Match the OS hardware description, not a user-renamed network service.
        BOOL usb = [type isEqual:(__bridge NSString *)kSCNetworkInterfaceTypeEthernet] && [displayName isEqualToString:@"iPhone USB"];
        [snapshots addObject:@{@"interface":name, @"active":@([link[@"Active"] boolValue]), @"hasIP":@(hasIP), @"usb":@(usb), @"personal":@(isPersonal && [name isEqual:wifiInterface]), @"ssid":ssid ?: @""}];
    }
    NSString *primary = [self storeValue:@"State:/Network/Global/IPv4"][@"PrimaryInterface"] ?: [self storeValue:@"State:/Network/Global/IPv6"][@"PrimaryInterface"];
    NSDictionary *result = HBChooseConnection(snapshots, primary);
    if (set) CFRelease(set);
    CFRelease(prefs);
    return result;
}

- (void)scheduleConnectionRefresh {
    if (self.refreshScheduled || self.sleeping) return;
    self.refreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        self.refreshScheduled = NO;
        if (!self.sleeping) [self refreshConnection];
    });
}

- (void)refreshConnection {
    NSDictionary *next = [self readConnection];
    if (![self.connection isEqual:next]) {
        self.connectionGeneration++;
        [self.internetProbe cancel]; self.internetProbe = nil;
        self.internetState = HBInternetChecking;
        self.internetHistory = (HBInternetHistory){0};
        [self stopDiscovery];
        [self.refreshTimer invalidate]; self.refreshTimer = nil;
        self.connection = next;
        self.reading = nil; self.readingDate = 0;
        if (next) {
            [self startDiscovery];
            [self checkInternet];
            self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:20 target:self selector:@selector(refreshSignal:) userInfo:nil repeats:YES];
            self.refreshTimer.tolerance = 3;
        }
    }
    [self render];
}

- (void)refreshSignal:(NSTimer *)timer {
    // Validate association before each short browsing window as a fallback for
    // any lost system notification. No timer exists off the hotspot.
    [self refreshConnection];
    if (self.connection) { [self startDiscovery]; [self checkInternet]; }
}

- (void)checkInternet {
    if (!self.connection || self.internetProbe || self.sleeping) return;
    self.primaryWasSlow = NO;
    [self checkEndpoint:0 generation:self.connectionGeneration];
}

- (void)checkEndpoint:(NSUInteger)index generation:(NSUInteger)generation {
    // Tiny HTTPS responses, no user data; confirm failures/slow responses with
    // a second provider so one struggling endpoint doesn't mean bad internet.
    // The same 20-second timer drives signal and connectivity checks.
    __weak HotspotBars *weakSelf = self;
    self.internetProbe = [[HBProbe alloc] initWithIndex:index configuration:HBProbeConfiguration() completion:^(BOOL good, NSTimeInterval seconds) {
            HotspotBars *strongSelf = weakSelf;
            if (!strongSelf || generation != strongSelf.connectionGeneration || !strongSelf.connection || strongSelf.sleeping) return;
            strongSelf.internetProbe = nil;
            if (index == 0 && (!good || seconds > HBSlowResponseSeconds)) {
                strongSelf.primaryWasSlow = good;
                [strongSelf checkEndpoint:1 generation:generation];
                return;
            }
            HBInternetHistory history = strongSelf.internetHistory;
            // If Apple was reachable but slow and the fallback fails, retain
            // the more accurate 'slow' result instead of claiming no internet.
            BOOL reachable = good || strongSelf.primaryWasSlow;
            NSTimeInterval duration = good ? seconds : strongSelf.primaryWasSlow ? HBSlowResponseSeconds + 1 : seconds;
            strongSelf.internetState = HBRecordInternetCheck(&history, reachable, duration);
            strongSelf.internetHistory = history;
            [strongSelf render];
    }];
    [self.internetProbe start];
}

- (void)startDiscovery {
    if (!self.connection || self.session || self.sleeping) return;
    Class cls = NSClassFromString(@"SFRemoteHotspotSession");
    if (![cls instancesRespondToSelector:@selector(startBrowsing)] || ![cls instancesRespondToSelector:@selector(stopBrowsing)] || ![cls instancesRespondToSelector:@selector(setDelegate:)]) return;
    self.session = [cls new];
    [self.session setDelegate:self];
    [self.session startBrowsing];
    self.browseStopTimer = [NSTimer scheduledTimerWithTimeInterval:4 target:self selector:@selector(endBrowsingWindow:) userInfo:nil repeats:NO];
    [self render];
}

- (void)endBrowsingWindow:(NSTimer *)timer { [self stopDiscovery]; }
- (void)stopDiscovery {
    [self.browseStopTimer invalidate]; self.browseStopTimer = nil;
    [self.session stopBrowsing]; [self.session setDelegate:nil]; self.session = nil;
}

- (void)session:(HBHotspotSession *)session updatedFoundDevices:(NSArray *)devices {
    // Sharing currently delivers on main; explicitly hop if this changes.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self session:session updatedFoundDevices:devices]; });
        return;
    }
    if (session != self.session || !self.connection) return;
    if (![devices isKindOfClass:NSArray.class] || devices.count > 64) {
        self.reading = nil; self.readingDate = 0; [self render];
        return;
    }
    NSMutableArray *readings = [NSMutableArray array];
    for (HBHotspotDevice *device in devices) {
        if (![device respondsToSelector:@selector(signalStrength)] || ![device respondsToSelector:@selector(networkType)] || ![device respondsToSelector:@selector(deviceName)] || ![device respondsToSelector:@selector(cachedDevice)]) continue;
        // Retain cached candidates for ambiguity checking, but don't refresh
        // our timestamp from cached data.
        NSNumber *bars = [device signalStrength];
        NSString *name = [device deviceName];
        if (![bars isKindOfClass:NSNumber.class] || ![name isKindOfClass:NSString.class] || name.length > 256) continue;
        [readings addObject:@{@"name":name, @"bars":bars, @"type":@([device networkType]), @"cached":@([device cachedDevice])}];
    }
    NSDictionary *reading = HBChooseReading(readings, self.connection);
    if (reading && ![reading[@"cached"] boolValue]) {
        self.reading = reading; self.readingDate = NSProcessInfo.processInfo.systemUptime;
    } else if (!reading) {
        self.reading = nil; self.readingDate = 0;
    }
    [self render];
}

- (void)seedPositionBesideWiFi:(BOOL)force {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *key = @"NSStatusItem Preferred Position TetherBar";
    if (!force && [defaults objectForKey:key]) return;
    NSNumber *wifiPosition = [defaults persistentDomainForName:@"com.apple.controlcenter"][@"NSStatusItem Preferred Position WiFi"];
    if ([wifiPosition isKindOfClass:NSNumber.class]) [defaults setDouble:wifiPosition.doubleValue + 1 forKey:key];
}

- (void)createItem {
    [self seedPositionBesideWiFi:NO];
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.item.autosaveName = @"TetherBar";
    self.item.button.font = [NSFont menuBarFontOfSize:11];
    NSMenu *menu = [NSMenu new]; menu.delegate = self;
    self.summaryItem = [menu addItemWithTitle:@"Reading cellular signal…" action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    self.loginItem = [menu addItemWithTitle:@"Launch at Login" action:@selector(toggleLogin:) keyEquivalent:@""];
    self.loginItem.target = self;
    NSMenuItem *position = [menu addItemWithTitle:@"Place Beside Wi-Fi" action:@selector(placeBesideWiFi:) keyEquivalent:@""];
    position.target = self;
    NSMenuItem *quit = [menu addItemWithTitle:@"Quit TetherBar" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    self.item.menu = menu;
}

- (NSImage *)barsImage:(NSInteger)bars color:(NSColor *)color {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(20, 15) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        if (bars < 0) {
            [@"?" drawAtPoint:NSMakePoint(5, 0) withAttributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:13], NSForegroundColorAttributeName:color ?: NSColor.blackColor}];
        } else {
            for (NSInteger i=0; i<4; i++) {
                [[(color ?: NSColor.blackColor) colorWithAlphaComponent:i < bars ? 1 : 0.22] setFill];
                [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1 + 5*i, 1, 3, 3 + 3*i) xRadius:0.6 yRadius:0.6] fill];
            }
        }
        return YES;
    }];
    image.template = color == nil;
    return image;
}

- (void)render {
    BOOL visible = self.connection != nil && !self.sleeping;
    if (visible && !self.item) [self createItem];
    if (self.item.visible != visible) self.item.visible = visible;
    BOOL fresh = HBFreshReading(self.reading, self.readingDate);
    NSInteger bars = fresh ? [self.reading[@"bars"] integerValue] : -1;
    NSString *label = fresh ? HBNetworkLabel([self.reading[@"type"] integerValue]) : @"";
    NSString *transport = [self.connection[@"usb"] boolValue] ? @"USB" : @"Wi-Fi";
    NSString *summary = fresh ? [NSString stringWithFormat:@"%ld of 4 bars · %@ · %@ hotspot", (long)bars, label, transport] : [NSString stringWithFormat:@"%@ hotspot · Signal unavailable", transport];
    HBHealth health = HBConnectionHealth(self.reading, fresh, self.internetState);
    NSString *internet = @"Checking internet…";
    switch (self.internetState) {
        case HBInternetGood: internet = @"Internet responsive"; break;
        case HBInternetOffline: internet = @"Internet check failed"; break;
        case HBInternetSlow: internet = @"Internet responding very slowly"; break;
        case HBInternetUnstable: internet = @"Internet unstable · Waiting for recovery"; break;
        case HBInternetChecking: break;
    }
    summary = [summary stringByAppendingFormat:@" · %@", internet];
    NSString *state = [NSString stringWithFormat:@"visible=%d transport=%@ bars=%ld network=%@ internet=%ld health=%ld", visible, visible ? transport : @"none", (long)bars, label, (long)self.internetState, (long)health];
    if (![state isEqual:self.lastDiagnostic]) {
        if (visible) {
            NSColor *color = health == HBOffline ? [NSColor colorWithSRGBRed:1 green:0.56 blue:0.54 alpha:1] : health == HBWeak ? [NSColor colorWithSRGBRed:1 green:0.84 blue:0.43 alpha:1] : nil;
            self.item.button.image = [self barsImage:bars color:color];
            NSString *title = label.length ? [@" " stringByAppendingString:label] : @"";
            self.item.button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:color ? @{NSForegroundColorAttributeName:color, NSFontAttributeName:self.item.button.font} : @{NSFontAttributeName:self.item.button.font}];
            self.item.button.toolTip = summary;
            self.item.button.accessibilityLabel = [@"TetherBar: " stringByAppendingString:summary];
            self.summaryItem.title = summary;
        }
        self.lastDiagnostic = state;
        if (self.diagnostic) { printf("%s\n", state.UTF8String); fflush(stdout); }
    }
}

- (void)menuWillOpen:(NSMenu *)menu {
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    self.loginItem.state = status == SMAppServiceStatusEnabled ? NSControlStateValueOn : status == SMAppServiceStatusRequiresApproval ? NSControlStateValueMixed : NSControlStateValueOff;
    self.loginItem.title = status == SMAppServiceStatusRequiresApproval ? @"Launch at Login — Approval Needed…" : @"Launch at Login";
}

- (void)setLoginEnabled:(BOOL)enabled {
    NSError *error = nil;
    BOOL ok = enabled ? [SMAppService.mainAppService registerAndReturnError:&error] : [SMAppService.mainAppService unregisterAndReturnError:&error];
    if (!ok) {
        NSAlert *alert = [NSAlert new]; alert.messageText = @"Couldn’t change Launch at Login";
        alert.informativeText = error.localizedDescription ?: @"Check System Settings → General → Login Items.";
        [alert runModal];
    } else if (SMAppService.mainAppService.status == SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems];
    }
}

- (void)toggleLogin:(id)sender {
    if (SMAppService.mainAppService.status == SMAppServiceStatusRequiresApproval) [SMAppService openSystemSettingsLoginItems];
    else [self setLoginEnabled:SMAppService.mainAppService.status != SMAppServiceStatusEnabled];
}

- (void)placeBesideWiFi:(id)sender {
    // AppKit has no public anchor-to-another-item API. Seed our own saved
    // position from Control Center; never modify the Wi-Fi item's preferences.
    self.item.autosaveName = nil;
    [NSStatusBar.systemStatusBar removeStatusItem:self.item]; self.item = nil;
    [self seedPositionBesideWiFi:YES];
    self.lastDiagnostic = nil;
    [self render];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (self.item.visible) { [self.item.button performClick:nil]; return NO; }
    NSAlert *alert = [NSAlert new]; alert.messageText = @"TetherBar is running";
    alert.informativeText = @"The menu bar indicator appears only while this Mac uses an iPhone hotspot. Open this app again any time to change login settings or quit.";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? @"Disable Launch at Login" : @"Enable Launch at Login"];
    [alert addButtonWithTitle:@"Quit"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertSecondButtonReturn) [self toggleLogin:nil];
    else if (response == NSAlertThirdButtonReturn) [NSApp terminate:nil];
    return NO;
}

- (void)willSleep:(NSNotification *)note {
    self.sleeping = YES;
    self.connectionGeneration++;
    [self.internetProbe cancel]; self.internetProbe = nil;
    self.internetState = HBInternetChecking;
    self.internetHistory = (HBInternetHistory){0};
    [self stopDiscovery]; [self.refreshTimer invalidate]; self.refreshTimer = nil;
    self.connection = nil; self.reading = nil; self.readingDate = 0;
    [self render];
}
- (void)didWake:(NSNotification *)note { self.sleeping = NO; [self scheduleConnectionRefresh]; }
- (void)applicationWillTerminate:(NSNotification *)note {
    [self.internetProbe cancel];
    [self stopDiscovery]; [self.refreshTimer invalidate]; [self.wifi invalidate];
    if (self.store) { SCDynamicStoreSetDispatchQueue(self.store, NULL); CFRelease(self.store); self.store = NULL; }
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"]) return HBSelfTest();
        NSArray *args = NSProcessInfo.processInfo.arguments;
        if ([args containsObject:@"--version"]) {
            NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            printf("TetherBar %s\n", version.UTF8String ?: "unknown");
            return 0;
        }
        if ([args containsObject:@"--login-status"] || [args containsObject:@"--enable-login"] || [args containsObject:@"--disable-login"]) {
            SMAppService *service = SMAppService.mainAppService;
            NSError *error = nil;
            if ([args containsObject:@"--enable-login"] && service.status != SMAppServiceStatusEnabled) [service registerAndReturnError:&error];
            if ([args containsObject:@"--disable-login"] && service.status != SMAppServiceStatusNotRegistered) [service unregisterAndReturnError:&error];
            printf("loginStatus=%ld (0=off, 1=enabled, 2=approval required, 3=not found)\n", (long)service.status);
            if (error) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return error ? 1 : 0;
        }
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        HotspotBars *delegate = [HotspotBars new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
