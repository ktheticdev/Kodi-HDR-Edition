/*
 *  Copyright (C) 2010-2018 Team Kodi
 *  This file is part of Kodi - https://kodi.tv
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 *  See LICENSES/README.md for more information.
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVAudioSession.h>

#import "XBMCApplication.h"
#import "XBMCController.h"
#import "IOSScreenManager.h"
#import "XBMCDebugHelpers.h"
#import <objc/runtime.h>

@implementation XBMCApplicationDelegate
XBMCController *m_xbmcController;

// - iOS6 rotation API - will be called on iOS7 runtime!--------
// - on iOS7 first application is asked for supported orientation
// - then the controller of the current view is asked for supported orientation
// - if both say OK - rotation is allowed
- (NSUInteger)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
  return [[window rootViewController] supportedInterfaceOrientations];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
  PRINT_SIGNATURE();

  [m_xbmcController pauseAnimation];
  [m_xbmcController becomeInactive];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
  PRINT_SIGNATURE();

  [m_xbmcController resumeAnimation];
  [m_xbmcController enterForeground];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
  PRINT_SIGNATURE();

  if (application.applicationState == UIApplicationStateBackground)
  {
    // the app is turn into background, not in by screen lock which has app state inactive.
    [m_xbmcController enterBackground];
  }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
  PRINT_SIGNATURE();

  [m_xbmcController stopAnimation];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
  PRINT_SIGNATURE();
}

- (void)screenDidConnect:(NSNotification *)aNotification
{
  [IOSScreenManager updateResolutions];
}

- (void)screenDidDisconnect:(NSNotification *)aNotification
{
  [[IOSScreenManager sharedInstance] screenDisconnect];
}

- (void)registerScreenNotifications:(BOOL)bRegister
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  if( bRegister )
  {
    //register to screen notifications
    [nc addObserver:self selector:@selector(screenDidConnect:) name:UIScreenDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(screenDidDisconnect:) name:UIScreenDidDisconnectNotification object:nil];
  }
  else
  {
    //deregister from screen notifications
    [nc removeObserver:self name:UIScreenDidConnectNotification object:nil];
    [nc removeObserver:self name:UIScreenDidDisconnectNotification object:nil];
  }
}

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
  PRINT_SIGNATURE();

  [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
  UIScreen *currentScreen = [UIScreen mainScreen];

  m_xbmcController = [[XBMCController alloc] initWithFrame: [currentScreen bounds] withScreen:currentScreen];
  [m_xbmcController startAnimation];
  [self registerScreenNotifications:YES];

  NSError *err = nil;
  if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&err])
  {
    ELOG(@"AVAudioSession setCategory failed: %@", err);
  }
  err = nil;
  if (![[AVAudioSession sharedInstance] setActive: YES error: &err])
  {
    ELOG(@"AVAudioSession setActive failed: %@", err);
  }
}

- (void)dealloc
{
  [self registerScreenNotifications:NO];
  [m_xbmcController stopAnimation];
  [m_xbmcController release];

  [super dealloc];
}
@end

//---------------- HOOK FOR BT KEYBOARD CURSORS KEYS START----------------
#define GSEVENT_TYPE 2
#define GSEVENT_FLAGS 12
#define GSEVENTKEY_KEYCODE_32_BIT 17
#define GSEVENTKEY_KEYCODE_64_BIT 13
#define GSEVENT_TYPE_KEYUP 11

static UniChar kGKKeyboardDirectionRight = 79;
static UniChar kGKKeyboardDirectionLeft = 80;
static UniChar kGKKeyboardDirectionDown = 81;
static UniChar kGKKeyboardDirectionUp = 82;

// pointer to the original hooked method
static void (*UIApplication$sendEvent$Orig)(id, SEL, UIEvent*);

void handleKeyCode(UniChar keyCode)
{
  XBMCKey key = XBMCK_UNKNOWN;
  //LOG(@"%s: tmp key %x", __PRETTY_FUNCTION__, keyCode);
  if      (keyCode == kGKKeyboardDirectionRight)
    key = XBMCK_RIGHT;
  else if (keyCode == kGKKeyboardDirectionLeft)
    key = XBMCK_LEFT;
  else if (keyCode == kGKKeyboardDirectionDown)
    key = XBMCK_DOWN;
  else if (keyCode == kGKKeyboardDirectionUp)
    key = XBMCK_UP;
  else
  {
    //LOG(@"%s: tmp key unsupported :(", __PRETTY_FUNCTION__);
    return; // not supported by us - return...
  }

  [g_xbmcController sendKey:key];
}

static void XBMCsendEvent(id _self, SEL _cmd, UIEvent *event)
{
  // call super implementation
  UIApplication$sendEvent$Orig(_self, _cmd, event);

  if ([event respondsToSelector:@selector(_gsEvent)])
  {
    // Key events come in form of UIInternalEvents.
    // They contain a GSEvent object which contains
    // a GSEventRecord among other things
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSInteger *eventMem = (NSInteger *)[event performSelector:@selector(_gsEvent)];
#pragma clang diagnostic pop

    if (eventMem)
    {
      // So far we got a GSEvent :)
      NSInteger eventType = eventMem[GSEVENT_TYPE];
      if (eventType == GSEVENT_TYPE_KEYUP)
      {
        // support 32 and 64bit arm here...
#if TARGET_RT_64_BIT
        int idx = GSEVENTKEY_KEYCODE_64_BIT;
#else
        int idx = GSEVENTKEY_KEYCODE_32_BIT;
#endif

        // Now we got a GSEventKey!

        // Read flags from GSEvent
        // for modifier keys if we want to use them somehow at a later time
        //int eventFlags = eventMem[GSEVENT_FLAGS];
        // Read keycode from GSEventKey
        UniChar tmp = (UniChar)eventMem[idx];
        handleKeyCode(tmp);
      }
    }
  }
}

// implicitly called constructor for hooking into handleKeyUIEvent
// this one hooks us into the keyboard events
__attribute__((constructor)) static void HookKeyboard(void)
{
#if TARGET_RT_64_BIT
    LOG(@"Detected 64bit system!!!");
#else
    LOG(@"Detected 32bit system!!!");
#endif

  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  {
    // Hook into handleKeyUIEvent: to get keyboard events.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([UIApplication instancesRespondToSelector:@selector(handleKeyUIEvent:)])
      *(IMP*)&UIApplication$sendEvent$Orig = method_setImplementation(class_getInstanceMethod(UIApplication.class, @selector(handleKeyUIEvent:)), (IMP)&XBMCsendEvent);
    else
      ELOG(@"HookKeyboard: Couldn't hook handleKeyUIEvent - cursor keys on btkeyboards won't work!");
#pragma clang diagnostic pop
  }
  [pool release];
}
//---------------- HOOK FOR BT KEYBOARD CURSORS KEYS END----------------

static void SigPipeHandler(int s)
{
  NSLog(@"We Got a Pipe Single :%d____________", s);
}

int main(int argc, char *argv[]) {
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  int retVal = 0;

  signal(SIGPIPE, SigPipeHandler);

  @try
  {
    retVal = UIApplicationMain(argc,argv,@"UIApplication",@"XBMCApplicationDelegate");
    //UIApplicationMain(argc, argv, nil, nil);
  }
  @catch (id theException)
  {
    ELOG(@"%@", theException);
  }
  @finally
  {
    ILOG(@"This always happens.");
  }

  [pool release];

  return retVal;

}
