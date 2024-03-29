//
//  OneginiCordovaClient.m
//  OneginiCordovaPlugin
//
//  Created by Eduard on 13-01-15.
//
//

#import "OneginiCordovaClient.h"
#import "Reachability.h"
#import "XMLReader.h"
#import "PushConfirmationViewController.h"
#import "MessagesModel.h"
#import "PushWithPinConfirmationViewController.h"
#import "PushWithFingerprintConfirmationViewController.h"

NSString *const kHeaders = @"headers";

NSString *const kStatus = @"status";

NSString *const kURL = @"url";

NSString *const kBody = @"body";

NSString *const kReason = @"reason";

NSString *const kRemainingAttempts = @"remainingAttempts";

NSString *const kMethod = @"method";

NSString *const kMaxSimilarDigits = @"maxSimilarDigits";

@interface MainViewController ()

@property (nonatomic, readwrite, strong) NSArray *supportedOrientations;

@end

@interface OneginiCordovaClient ()

@property (nonatomic) NSUInteger supportedOrientations;

@end

@implementation OneginiCordovaClient {
    /**
     Identifies the current state of the PIN entry process.
     */
    PINEntryModes pinEntryMode;

    /**
     This indicates if the native PIN entry view should be used.
     The value is set in the top level application config.xml
     */
    BOOL useNativePinView;

    /** Temporary storage of the first PIN for verification with the second entry */
#warning TODO apply memory protection
    NSString *verifyPin;
}

@synthesize oneginiClient, pluginInitializedCommandTxId, authorizeCommandTxId, oneginiConfigDictionary;
@synthesize fetchResourceCommandsTxId, pinDialogCommandTxId, pinValidateCommandTxId, pinChangeCommandTxId;

#pragma mark -
#pragma mark overrides

- (void)dealloc
{
    verifyPin = nil;
}

- (void)pluginInitialize
{
#ifdef DEBUG
    NSLog(@"pluginInitialize");
    [CDVPluginResult setVerbose:YES];
#endif
    pinEntryMode = PINEntryModeUnknown;

    self.oneginiClient = [[OGOneginiClient alloc] initWithDelegate: self];

    NSString *const configModelClassName = @"OneginiConfigModel";
    NSString *const configurationMethodName = @"configuration";

    if ([NSClassFromString(configModelClassName) class]) {
        if ([NSClassFromString(configModelClassName) respondsToSelector:NSSelectorFromString(configurationMethodName)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            oneginiConfigDictionary = [NSClassFromString(configModelClassName) performSelector:NSSelectorFromString(configurationMethodName)];
#pragma clang diagnostic pop
        }
    }
    if (!oneginiConfigDictionary)
        @throw @"OneginiConfigModel class was not included or is invalid. Please use configuration tool to supply configuration to the project or use OGOneginiClient#initWithConfig:delegate instead.";

    if (self.oneginiClient) {
        useNativePinView = [self useNativePinScreen];
    }
    self.fetchResourceCommandsTxId = [NSMutableDictionary new];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(closeInAppBrowser) name:OGCloseWebViewNotification object:nil];
}

- (NSString *)readCordovaPreference:(NSString *)name
{
    NSString *configContent = [self loadConfigurationFile];
    NSDictionary *configuration = [XMLReader dictionaryForXMLString:configContent];
    NSDictionary *widget = [configuration objectForKey:@"widget"];
    if (widget == nil) {
        @throw @"Cordova config.xml invalid or unreadable.";
    }
    NSArray *preferences = [widget objectForKey:@"preference"];
    if (preferences == nil) {
        @throw @"Could not find any preferences in Cordova config.xml";
    }

    NSString *value;
    for (id pref in preferences) {
        if ([[pref valueForKey:@"name"] isEqualToString:name]) {
            value = [NSString stringWithUTF8String:[[pref valueForKey:@"value"] UTF8String]];
        }
    }

    return value;
}

- (BOOL)initializationSuccessful
{
    return self.oneginiClient && self.pinDialogInitalized && self.inAppBrowserInitialized;
}

- (BOOL)pinDialogInitalized
{
    return useNativePinView || pinDialogCommandTxId;
}

- (BOOL)inAppBrowserInitialized
{
    return oneginiConfigDictionary[@"kOGUseEmbeddedWebview"] || self.inAppBrowserCommandTxId;
}

- (BOOL)useNativePinScreen
{
    return [[self readCordovaPreference:@"kOGUseNativePinScreen"] boolValue] || [[self readCordovaPreference:@"OneginiNativeScreens"] boolValue];
}

- (NSString *)loadFileToString:(NSString *)path
{
    NSError *error;
    NSString *fileContent = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:path ofType:nil] encoding:NSUTF8StringEncoding error:&error];

    if (error) {
        NSLog(@"Error reading %@ file", path);
        return @"";
    }
    return fileContent;
}

- (NSString *)loadConfigurationFile
{
    NSString *configPath = @"config.xml";
    return [self loadFileToString:configPath];
}

- (void)handleOpenURL:(NSNotification *)notification
{
    [super handleOpenURL:notification];

    [[OGOneginiClient sharedInstance] handleAuthorizationCallback:notification.object];
}

- (void)closeInAppBrowser
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{kMethod : @"closeInAppBrowser"}];
    pluginResult.keepCallback = @(1);
    if (self.inAppBrowserCommandTxId) {
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.inAppBrowserCommandTxId];
    }
}

- (void)onAppTerminate
{
    [oneginiClient logoutWithDelegate:self];
}

#pragma mark -

- (void)resetAll
{
    self.pluginInitializedCommandTxId = nil;
    self.authorizeCommandTxId = nil;
    self.pinValidateCommandTxId = nil;
    self.pinChangeCommandTxId = nil;
    self.enrollmentCommandTxId = nil;
    self.fingerprintEnrollmentCommandTxId = nil;
}

- (void)authorizationErrorCallbackWIthReason:(NSString *)reason
{
    [self authorizationErrorCallbackWIthReason:reason error:nil];
}

- (void)authorizationErrorCallbackWIthReason:(NSString *)reason error:(NSError *)error
{
    if (authorizeCommandTxId == nil) {
        return;
    }

    NSDictionary *d = @{kReason : reason};

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:d];
    [self.commandDelegate sendPluginResult:result callbackId:authorizeCommandTxId];
    [self resetAll];
}

#pragma mark -
#pragma mark Cordova entry points

- (void)clearTokens:(CDVInvokedUrlCommand *)command
{
    NSError *error;
    if (![[OGOneginiClient sharedInstance] clearTokens:&error]) {
#ifdef DEBUG
        NSLog(@"clearTokens error %@", error);
#endif
    }
}

- (void)clearCredentials:(CDVInvokedUrlCommand *)command
{
    [[OGOneginiClient sharedInstance] clearCredentials];
}

- (void)awaitPluginInitialization:(CDVInvokedUrlCommand *)command
{
    self.pluginInitializedCommandTxId = command.callbackId;
    if (![self isConnected]) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"connectivityProblem"}];
        [self.commandDelegate sendPluginResult:result callbackId:self.pluginInitializedCommandTxId];
    }
    [self handleInitializationCallback];
}

- (void)initPinCallbackSession:(CDVInvokedUrlCommand *)command
{
    self.pinDialogCommandTxId = command.callbackId;

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    pluginResult.keepCallback = @(1);
    [self.commandDelegate sendPluginResult:pluginResult callbackId:pinDialogCommandTxId];

    [self handleInitializationCallback];
}

- (void)inAppBrowserControlSession:(CDVInvokedUrlCommand *)command
{
    self.inAppBrowserCommandTxId = command.callbackId;

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    pluginResult.keepCallback = @(1);
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.inAppBrowserCommandTxId];

    [self handleInitializationCallback];
}

- (void)handleInitializationCallback
{
    if (self.pluginInitializedCommandTxId && self.initializationSuccessful) {
        [self sendSuccessCallback:self.pluginInitializedCommandTxId];
        self.pluginInitializedCommandTxId = nil;
    }
}

- (void)isRegistered:(CDVInvokedUrlCommand *)command
{
    if (oneginiClient.isClientRegistered)
        [self sendSuccessCallback:command.callbackId];
    else
        [self sendErrorCallback:command.callbackId];
}

- (bool)isConnected
{
    Reachability *currentReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [currentReachability currentReachabilityStatus];

    if (networkStatus == ReachableViaWiFi || networkStatus == ReachableViaWWAN)
        return YES;
    else
        return NO;
}

- (void)authorize:(CDVInvokedUrlCommand *)command
{
    [self resetAll];
    self.authorizeCommandTxId = command.callbackId;

    if (![self isConnected]) {
        [self authorizationErrorCallbackWIthReason:@"connectivityProblem"];
        return;
    }
    id scopeArgument = [command.arguments firstObject];
    if ([scopeArgument isKindOfClass:[NSArray class]] && ((NSArray *)scopeArgument).count > 0) {
        [oneginiClient authorize:scopeArgument];
    } else {
        [oneginiClient authorize:nil];
    }
}

- (void)reauthorize:(CDVInvokedUrlCommand *)command
{
    [self resetAll];
    self.authorizeCommandTxId = command.callbackId;

    if (![self isConnected]) {
        [self authorizationErrorCallbackWIthReason:@"connectivityProblem"];
        return;
    }
    id scopeArgument = [command.arguments firstObject];
    if ([scopeArgument isKindOfClass:[NSArray class]] && ((NSArray *)scopeArgument).count > 0) {
        [oneginiClient reauthorize:scopeArgument];
    } else {
        [oneginiClient reauthorize:nil];
    }
}

- (void)isAuthorized:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:[oneginiClient isAuthorized]];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)confirmNewPin:(CDVInvokedUrlCommand *)command
{
    self.pinValidateCommandTxId = nil;
    self.pinChangeCommandTxId = nil;
    if (command.arguments.count != 1) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"expected 1 argument but received %lu", (unsigned long)command.arguments.count]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSString *pin = command.arguments.firstObject;

    [oneginiClient confirmNewPin:pin validation:self];
}

- (void)confirmCurrentPin:(CDVInvokedUrlCommand *)command
{
    if (![self isConnected]) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"connectivityProblem"}];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }

    if (command.arguments.count != 1) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"expected 1 argument but received %lu", (unsigned long)command.arguments.count]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
    if (self.fingerprintEnrollmentCommandTxId != nil && !useNativePinView) {
        [oneginiClient confirmCurrentPinForFingerprintAuthorization:command.arguments.firstObject];
        return;
    }

    NSString *pin = command.arguments.firstObject;

    [oneginiClient confirmCurrentPin:pin];
    [self sendSuccessCallback:command.callbackId];
}

- (void)changePin:(CDVInvokedUrlCommand *)command
{
    if (![self isConnected]) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"connectivityProblem"}];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }
    self.pinChangeCommandTxId = command.callbackId;
    self.pinValidateCommandTxId = nil;

    [oneginiClient changePinRequest:self];
}

- (void)cancelPinChange:(CDVInvokedUrlCommand *)command
{
    self.pinChangeCommandTxId = nil;
    self.pinValidateCommandTxId = nil;
    // TODO add cancel PIN change method to public API of OGOneginiClient in order to invalidate the state.
}

- (void)confirmCurrentPinForChangeRequest:(CDVInvokedUrlCommand *)command
{
    self.pinValidateCommandTxId = nil;

    if (command.arguments.count != 1) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"expected 1 argument but received %lu", (unsigned long)command.arguments.count]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSString *pin = command.arguments.firstObject;
    [oneginiClient confirmCurrentPinForChangeRequest:pin];
}

- (void)confirmNewPinForChangeRequest:(CDVInvokedUrlCommand *)command
{
    self.pinValidateCommandTxId = nil;

    if (command.arguments.count != 1) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"expected 1 argument but received %lu", (unsigned long)command.arguments.count]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    // Register the transaction id for validation callbacks.
    self.pinValidateCommandTxId = command.callbackId;
    NSString *pin = command.arguments.firstObject;

    [oneginiClient confirmNewPinForChangeRequest:pin validation:self];
}

- (void)validatePin:(CDVInvokedUrlCommand *)command
{
    if (command.arguments.count != 1) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"expected 1 argument but received %lu", (unsigned long)command.arguments.count]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSString *pin = command.arguments.firstObject;
    NSError *error;
    BOOL result = [oneginiClient isPinValid:pin error:&error];

    CDVPluginResult *pluginResult;
    if (result) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    if (![error.domain isEqualToString:@"com.onegini.PinValidation"]) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    self.pinValidateCommandTxId = command.callbackId;
    // TODO move error codes into OGPublicCommons public API
    switch (error.code) {
        case 0: {
            [self pinShouldNotBeASequence];
            break;
        }
        case 1: {
            NSNumber *n = error.userInfo[@"kMaxSimilarDigits"];
            [self pinShouldNotUseSimilarDigits:n.integerValue];
            break;
        }
        case 2: {
            [self pinTooShort];
            break;
        }
        case 3: {
            [self pinBlackListed];
            break;
        }
        default: {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }
}

- (void)fetchResource:(CDVInvokedUrlCommand *)command
{
    [self performResourceCall:command isAnonymous:NO];
}

- (void)fetchAnonymousResource:(CDVInvokedUrlCommand *)command
{
    [self performResourceCall:command isAnonymous:YES];
}

- (void)performResourceCall:(CDVInvokedUrlCommand *)command isAnonymous:(BOOL)isAnonymous
{
    if (![self isConnected]) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"connectivityProblem"}];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    NSString *path = [command.arguments objectAtIndex:0];
    NSString *requestMethodString = [command.arguments objectAtIndex:1];
    NSDictionary *params = [command.arguments objectAtIndex:2];
    NSDictionary *headers = [[command.arguments objectAtIndex:3] isKindOfClass:[NSNull class]] ? nil : [command.arguments objectAtIndex:3];

    NSDictionary *convertedHeaders = [self convertNumbersToStringsInDictionary:headers];

    NSString *requestId = nil;
    if (isAnonymous) {
        requestId = [oneginiClient fetchAnonymousResource:path requestMethod:requestMethodString params:params paramsEncoding:OGJSONParameterEncoding headers:convertedHeaders delegate:self];
    } else {
        requestId = [oneginiClient fetchResource:path requestMethod:requestMethodString params:params paramsEncoding:OGJSONParameterEncoding headers:convertedHeaders delegate:self];
    }
    [self.fetchResourceCommandsTxId setObject:command.callbackId forKey:requestId];
}

- (void)logout:(CDVInvokedUrlCommand *)command
{
    self.logoutCommandTxId = command.callbackId;
    [self.oneginiClient logoutWithDelegate:self];
}

- (void)disconnect:(CDVInvokedUrlCommand *)command
{
    self.disconnectCommandTxId = command.callbackId;
    [self.oneginiClient disconnectWithDelegate:self];
}

- (void)sendSuccessCallback:(NSString *)callbackId
{
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

- (void)sendErrorCallback:(NSString *)callbackId
{
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

- (void)enrollForFingerprintAuthentication:(CDVInvokedUrlCommand *)command
{
    self.fingerprintEnrollmentCommandTxId = command.callbackId;

    id scopeArgument = [command.arguments firstObject];
    if ([scopeArgument isKindOfClass:[NSArray class]] && ((NSArray *)scopeArgument).count > 0) {
        [self.oneginiClient enrollForFingerprintAuthentication:scopeArgument delegate:self];
    } else {
        [self.oneginiClient enrollForFingerprintAuthentication:nil delegate:self];
    }
}

- (void)disableFingerprintAuthentication:(CDVInvokedUrlCommand *)command
{
    [self.oneginiClient disableFingerprintAuthentication];
}

- (void)checkFingerpringAuthenticationState:(CDVInvokedUrlCommand *)command
{
    if ([self.oneginiClient isEnrolledForFingerprintAuthentication])
        [self sendSuccessCallback:command.callbackId];
    else
        [self sendErrorCallback:command.callbackId];
}

- (void)isFingerprintAuthenticationAvailable:(CDVInvokedUrlCommand *)command
{
    if (oneginiClient.isFingerprintAuthenticationAvailable) {
        [self sendSuccessCallback:command.callbackId];
    } else {
        [self sendErrorCallback:command.callbackId];
    }
}

- (void)readConfigProperty:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:oneginiConfigDictionary[@"kOGAppBaseURL"]];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark -
#pragma mark OGAuthorizationDelegate

- (void)requestAuthorization:(NSURL *)url
{
    if (oneginiConfigDictionary[@"kOGUseEmbeddedWebview"]) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{kMethod : @"requestAuthorization", @"url" : url.absoluteString}];
        result.keepCallback = @(1);

        [self.commandDelegate sendPluginResult:result callbackId:authorizeCommandTxId];
    } else {
        [[UIApplication sharedApplication] openURL:url];
    }
}

- (void)authorizationSuccess
{
    if (authorizeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"authorizationSuccess");
#endif
        [self resetAll];
        return;
    }

    [self closePinView];
    pinEntryMode = PINEntryModeUnknown;

    @try {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"authorizationSuccess"];
        result.keepCallback = @(0);
        [self.commandDelegate sendPluginResult:result callbackId:authorizeCommandTxId];
    } @finally {
        [self resetAll];
    }
}

- (void)authorizationError
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"connectivityProblem"];
}

- (void)authorizationErrorClientRegistrationFailed:(NSError *)error
{
    [self authorizationErrorCallbackWIthReason:@"authorizationErrorClientRegistrationFailed" error:error];
}

- (void)askForCurrentPin
{
    if (useNativePinView) {
        pinEntryMode = PINCheckMode;
        [self showPinEntryViewInMode:PINCheckMode];
    } else {
        if (pinDialogCommandTxId == nil) {
#ifdef DEBUG
            NSLog(@"askForCurrentPin: pinCommandTxId is nil");
#endif
            return;
        }
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{kMethod : @"askForCurrentPin"}];
        result.keepCallback = @(1);
        [self.commandDelegate sendPluginResult:result callbackId:pinDialogCommandTxId];
    }
}

- (void)askForNewPin:(NSUInteger)pinSize
{
    if (useNativePinView) {
        pinEntryMode = PINRegistrationMode;
        [self showPinEntryViewInMode:PINRegistrationMode];
    } else {
        if (pinDialogCommandTxId == nil) {
#ifdef DEBUG
            NSLog(@"askForNewPin: pinCommandTxId is nil");
#endif
            return;
        }
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{kMethod : @"askForNewPin"}];
        result.keepCallback = @(1);
        [self.commandDelegate sendPluginResult:result callbackId:pinDialogCommandTxId];
    }
}

- (void)askNewPinForChangeRequest:(NSUInteger)pinSize
{
    if (useNativePinView) {
        pinEntryMode = PINChangeNewPinMode;
        [self.pinViewController reset];
        self.pinViewController.mode = pinEntryMode;
    } else {
        if (pinDialogCommandTxId == nil) {
#ifdef DEBUG
            NSLog(@"askNewPinForChangeRequest: pinCommandTxId is nil");
#endif
            return;
        }
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{kMethod : @"askNewPinForChangeRequest"}];
        result.keepCallback = @(1);
        [self.commandDelegate sendPluginResult:result callbackId:pinDialogCommandTxId];
    }
}

- (void)askCurrentPinForChangeRequest
{
    if (useNativePinView) {
        pinEntryMode = PINChangeCheckMode;
        [self showPinEntryViewInMode:PINChangeCheckMode];
    } else {
        if (pinDialogCommandTxId == nil) {
#ifdef DEBUG
            NSLog(@"askCurrentPinForChangeRequest: pinCommandTxId is nil");
#endif
            return;
        }

        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{kMethod : @"askCurrentPinForChangeRequest"}];
        result.keepCallback = @(1);
        [self.commandDelegate sendPluginResult:result callbackId:pinDialogCommandTxId];
    }
}

- (void)authorizationErrorInvalidGrant:(NSUInteger)remaining
{
    if (authorizeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"authorizationErrorInvalidGrant: remaining attempts %d", remaining);
#endif
        return;
    }

    if (self.pinViewController == nil) {
        @try {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"authorizationErrorInvalidGrant", kRemainingAttempts : @(remaining)}];
            result.keepCallback = @(0);
            [self.commandDelegate sendPluginResult:result callbackId:authorizeCommandTxId];
        } @finally {
            [self resetAll];
        }
    } else {
        [self.pinViewController invalidPinWithReason:[NSString stringWithFormat:[MessagesModel messageForKey:@"AUTHORIZATION_ERROR_PIN_INVALID"], @(remaining)]];
    }
}

- (void)authorizationErrorTooManyPinFailures
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorTooManyPinFailures"];
}

- (void)authorizationErrorNotAuthenticated
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorNotAuthenticated"];
}

- (void)authorizationErrorInvalidScope
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorInvalidScope"];
}

- (void)authorizationErrorInvalidState
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorInvalidState"];
}

- (void)authorizationErrorNoAccessToken
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorNoAccessToken"];
}

- (void)authorizationErrorNotAuthorized
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorNotAuthorized"];
}

- (void)authorizationErrorInvalidRequest
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorInvalidRequest"];
}

- (void)authorizationErrorInvalidGrantType
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorInvalidGrantType"];
}

- (void)authorizationErrorNoAuthorizationGrant
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorNoAuthorizationGrant"];
}

- (void)authorizationErrorInvalidAppPlatformOrVersion
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"unsupportedAppVersion"];
}

- (void)askForPushAuthenticationConfirmation:(NSString *)message notificationType:(NSString *)notificationType confirm:(PushAuthenticationConfirmation)confirm
{
    PushConfirmationViewController *pushConfirmationViewController = [[PushConfirmationViewController alloc] initWithMessage:message confirmationBlock:confirm NibName:@"PushConfirmationViewController" bundle:nil];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:pushConfirmationViewController animated:NO completion:^{
    }];
}

- (void)askForPushAuthenticationWithPinConfirmation:(NSString *)message notificationType:(NSString *)notificationType pinSize:(NSUInteger)pinSize maxAttempts:(NSUInteger)maxAttempts retryAttempt:(NSUInteger)retryAttempt confirm:(PushAuthenticationWithPinConfirmation)confirm
{
    PushWithPinConfirmationViewController *pushWithPinConfirmationViewController = [[PushWithPinConfirmationViewController alloc] initWithMessage:message retryAttempts:retryAttempt maxAttempts:maxAttempts confirmationBlock:confirm NibName:@"PushWithPinConfirmationViewController" bundle:nil];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:pushWithPinConfirmationViewController animated:NO completion:^{
    }];
}

- (void)askForPushAuthenticationWithFingerprint:(NSString *)message notificationType:(NSString *)notificationType confirm:(PushAuthenticationConfirmation)confirm
{
    PushWithFingerprintConfirmationViewController *pushConfirmationViewController = [[PushWithFingerprintConfirmationViewController alloc] initWithMessage:message confirmationBlock:confirm NibName:@"PushWithFingerprintConfirmationViewController" bundle:nil];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:pushConfirmationViewController animated:NO completion:^{
    }];
}

- (void)authorizationErrorUnsupportedOS
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"authorizationErrorUnsupportedOS"];
}

- (void)authorizationClientConfigFailed
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"connectivityProblem"];
}

// @optional
- (void)authorizationError:(NSError *)error
{
    [self closePinView];

    [self authorizationErrorCallbackWIthReason:@"connectivityProblem"];
}

#pragma mark - OGDisconnectDelegate

- (void)disconnectSuccessful
{
    [self sendSuccessCallback:self.disconnectCommandTxId];
    [self resetAll];
}

- (void)disconnectFailureWithError:(NSError *)error
{
    [self sendSuccessCallback:self.disconnectCommandTxId];
    [self resetAll];
}

#pragma mark -
#pragma mark - OGLogoutDelegate

- (void)logoutSuccessful
{
    [self sendSuccessCallback:self.logoutCommandTxId];
    [self resetAll];
}

- (void)logoutFailureWithError:(NSError *)error
{
    [self sendSuccessCallback:self.logoutCommandTxId];
    [self resetAll];
}

#pragma mark -
#pragma mark OGResourceHandlerDelegate

- (void)resourceResponse:(NSHTTPURLResponse *)response body:(NSData *)body requestId:(NSString *)requestId
{
    CDVPluginResult *result;

    NSMutableDictionary *responseJSON = [NSMutableDictionary new];
    if (response.allHeaderFields)
        [responseJSON setObject:response.allHeaderFields forKey:kHeaders];
    if (response.URL.absoluteString)
        [responseJSON setObject:response.URL.absoluteString forKey:kURL];
    if (body)
        [responseJSON setObject:body.base64Encoding forKey:kBody];
    [responseJSON setObject:@(response.statusCode) forKey:kStatus];

    result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:responseJSON];

    NSString *callbackId = [self.fetchResourceCommandsTxId objectForKey:requestId];
    [self.fetchResourceCommandsTxId removeObjectForKey:requestId];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

- (void)resourceError:(NSError *)error requestId:(NSString *)requestId
{
    NSString *errorReason = nil;
    switch (error.code) {
        case OGResourceErrorCode_InvalidRequestMethod:
            errorReason = @"resourceErrorInvalidRequestMethod";
            break;
        case OGResourceErrorCode_Generic:
        default:
            errorReason = @"resourceCallError";
            break;
    }
    NSString *callbackId = [self.fetchResourceCommandsTxId objectForKey:requestId];
    [self.fetchResourceCommandsTxId removeObjectForKey:requestId];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : errorReason}];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

#pragma mark -
#pragma mark OGPinValidationHandler

/*
 PIN validation errors should not reset the transaction cause these errors allow for re entering the PIN
 */

#warning TODO use correct validation messages

- (void)pinBlackListed
{
    if (self.pinViewController != nil) {
        [self retryPinEntryAfterValidationFailure];
        [self.pinViewController invalidPinWithReason:[MessagesModel messageForKey:@"PIN_BLACK_LISTED"]];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"pinBlackListed"}];

        [self.commandDelegate sendPluginResult:result callbackId:pinValidateCommandTxId];
    }
}

- (void)pinShouldNotBeASequence
{
    if (self.pinViewController != nil) {
        [self retryPinEntryAfterValidationFailure];
        [self.pinViewController invalidPinWithReason:[MessagesModel messageForKey:@"PIN_SHOULD_NOT_BE_A_SEQUENCE"]];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"pinShouldNotBeASequence"}];
        [self.commandDelegate sendPluginResult:result callbackId:pinValidateCommandTxId];
    }
}

- (void)pinShouldNotUseSimilarDigits:(NSUInteger)count
{
    if (self.pinViewController != nil) {
        [self retryPinEntryAfterValidationFailure];
        [self.pinViewController invalidPinWithReason:[NSString stringWithFormat:[MessagesModel messageForKey:@"PIN_SHOULD_NOT_USE_SIMILAR_DIGITS"], @(count)]];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"pinShouldNotUseSimilarDigits", kMaxSimilarDigits : @(count)}];
        [self.commandDelegate sendPluginResult:result callbackId:pinValidateCommandTxId];
    }
}

- (void)pinTooShort
{
    if (self.pinViewController != nil) {
        [self retryPinEntryAfterValidationFailure];
        [self.pinViewController invalidPinWithReason:[MessagesModel messageForKey:@"PIN_TOO_SHORT"]];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"pinTooShort"}];
        [self.commandDelegate sendPluginResult:result callbackId:pinValidateCommandTxId];
    }
}

// @optional
- (void)pinEntryError:(NSError *)error
{
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"pinEntryError"}];
    [self.commandDelegate sendPluginResult:result callbackId:pinValidateCommandTxId];
}

#pragma mark -
#pragma mark OGChangePinDelegate

- (void)pinChangeError:(NSError *)error
{
    if (pinChangeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"pinChangeError: pinCommandTxId is nil, invocation is out of context");
#endif
        return;
    }
    if (self.pinViewController) {
        [self closePinView];
    }
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"connectivityProblem"}];
    [self.commandDelegate sendPluginResult:result callbackId:pinChangeCommandTxId];
    pinChangeCommandTxId = nil;
}

- (void)invalidCurrentPin
{
    if (pinChangeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"invalidCurrentPin: pinCommandTxId is nil");
#endif
        return;
    }
    if (self.pinViewController) {
        [self.pinViewController invalidPinWithReason:@"Invalid pin"];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"invalidCurrentPin"}];
        [self.commandDelegate sendPluginResult:result callbackId:pinChangeCommandTxId];
        pinChangeCommandTxId = nil;
    }
}

- (void)invalidCurrentPin:(NSUInteger)remaining
{
    if (pinChangeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"invalidCurrentPin: pinCommandTxId is nil");
#endif
        return;
    }
    if (self.pinViewController) {
        [self.pinViewController invalidPinWithReason:[NSString stringWithFormat:[MessagesModel messageForKey:@"AUTHORIZATION_ERROR_PIN_INVALID"], @(remaining)]];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"invalidCurrentPin", kRemainingAttempts : @(remaining)}];
        [self.commandDelegate sendPluginResult:result callbackId:pinChangeCommandTxId];
        pinChangeCommandTxId = nil;
    }
}

- (void)pinChangeErrorTooManyPinFailures
{
    if (pinChangeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"invalidCurrentPin: pinCommandTxId is nil");
#endif
        return;
    }
    [self closePinView];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"pinChangeErrorTooManyAttempts"}];
    [self.commandDelegate sendPluginResult:result callbackId:pinChangeCommandTxId];
    pinChangeCommandTxId = nil;
}

- (void)pinChanged
{
    if (pinChangeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"pinChanged: pinCommandTxId is nil");
#endif
        return;
    }

    [self closePinView];
    pinEntryMode = PINEntryModeUnknown;

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"pinChanged"];
    [self.commandDelegate sendPluginResult:result callbackId:pinChangeCommandTxId];
    pinChangeCommandTxId = nil;
}

- (void)pinChangeError
{
    if (pinChangeCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"pinChangeError: pinCommandTxId is nil");
#endif
        return;
    }
    if (self.pinViewController) {
        [self.pinViewController invalidPinWithReason:[MessagesModel messageForKey:@"AUTHORIZATION_ERROR_PIN_CHANGE_FAILED"]];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"pinChangeError"}];
        [self.commandDelegate sendPluginResult:result callbackId:pinChangeCommandTxId];
        pinChangeCommandTxId = nil;
    }
}

#pragma mark - FingerprintDelegate

- (void)askCurrentPinForFingerprintAuthentication
{
    if (useNativePinView) {
        pinEntryMode = PINFingerprintCheckMode;
        [self showPinEntryViewInMode:PINFingerprintCheckMode];
    } else {
        if (pinDialogCommandTxId == nil) {
#ifdef DEBUG
            NSLog(@"askForCurrentPin: pinCommandTxId is nil");
#endif
            return;
        }

        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{kMethod : @"askForCurrentPin"}];
        result.keepCallback = @(1);
        [self.commandDelegate sendPluginResult:result callbackId:pinDialogCommandTxId];
    }
}

- (void)fingerprintAuthenticationEnrollmentSuccessful
{
    if (self.fingerprintEnrollmentCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"fingerprint_enrolment_success");
#endif
        [self resetAll];
        return;
    }
    [self closePinView];
    @try {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"fingerprint_enrolment_success"];
        result.keepCallback = @(0);
        [self.commandDelegate sendPluginResult:result callbackId:self.fingerprintEnrollmentCommandTxId];
    } @finally {
        [self resetAll];
    }
}

- (void)fingerprintAuthenticationEnrollmentFailure
{
    if (self.fingerprintEnrollmentCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"fingerprint_enrolment_failure");
#endif
        [self resetAll];
        return;
    }
    @try {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"fingerprint_enrolment_failure"];
        result.keepCallback = @(0);
        [self.commandDelegate sendPluginResult:result callbackId:self.fingerprintEnrollmentCommandTxId];
    } @finally {
        [self resetAll];
    }
}

- (void)fingerprintAuthenticationEnrollmentErrorInvalidPin:(NSUInteger)attemptCount
{
    if (self.fingerprintEnrollmentCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"fingerprint_enrolment_failure");
#endif
        [self resetAll];
        return;
    }
    if (useNativePinView && self.pinViewController) {
        [self.pinViewController invalidPinWithReason:[NSString stringWithFormat:[MessagesModel messageForKey:@"AUTHORIZATION_ERROR_PIN_INVALID"], @(attemptCount)]];
    } else {
        @try {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{kReason : @"fingerprint_enrolment_failure_invalid_pin", kRemainingAttempts : @(attemptCount)}];
            result.keepCallback = @(1);
            [self.commandDelegate sendPluginResult:result callbackId:self.fingerprintEnrollmentCommandTxId];
        } @finally {
            [self resetAll];
        }
    }
}

- (void)fingerprintAuthenticationEnrollmentErrorTooManyPinFailures
{
    if (self.fingerprintEnrollmentCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"fingerprint_enrolment_failure");
#endif
        [self resetAll];
        return;
    }
    [self closePinView];
    @try {
        NSDictionary *message = @{kReason : @"fingerprint_enrolment_failure_too_many_attempts"};
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:message];
        result.keepCallback = @(0);
        [self.commandDelegate sendPluginResult:result callbackId:self.fingerprintEnrollmentCommandTxId];
    } @finally {
        [self resetAll];
    }
}

#pragma mark -
#pragma mark Util

- (OGHTTPClientParameterEncoding)parameterEncodingForString:(NSString *)paramsEncodingString
{
    if ([paramsEncodingString isEqualToString:@"FORM"]) {
        return OGFormURLParameterEncoding;
    } else if ([paramsEncodingString isEqualToString:@"JSON"]) {
        return OGJSONParameterEncoding;
    } else if ([paramsEncodingString isEqualToString:@"PROPERTY"]) {
        return OGPropertyListParameterEncoding;
    } else {
        return OGJSONParameterEncoding;
    }
}

- (void)setupScreenOrientation:(CDVInvokedUrlCommand *)command
{

    if ([[UIDevice currentDevice].model rangeOfString:@"iPhone"].location == NSNotFound) {
        ((MainViewController *)self.viewController).supportedOrientations = [NSArray arrayWithObjects:[NSNumber numberWithInteger:UIInterfaceOrientationLandscapeLeft], [NSNumber numberWithInteger:UIInterfaceOrientationLandscapeRight], nil];
        self.supportedOrientations = UIInterfaceOrientationMaskLandscapeLeft | UIInterfaceOrientationMaskLandscapeRight;
    } else {
        ((MainViewController *)self.viewController).supportedOrientations = [NSArray arrayWithObjects:[NSNumber numberWithInteger:UIInterfaceOrientationPortrait], [NSNumber numberWithInteger:UIInterfaceOrientationPortraitUpsideDown], nil];
        self.supportedOrientations = UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
    }
}


- (NSDictionary *)convertNumbersToStringsInDictionary:(NSDictionary *)dictionary
{
    if (!dictionary)
        return nil;
    NSMutableDictionary *convertedDictionary = [[NSMutableDictionary alloc] init];
    for (NSString *key in dictionary.allKeys) {
        id object = [dictionary objectForKey:key];
        if ([object isKindOfClass:[NSNumber class]])
            [convertedDictionary setValue:[object stringValue] forKey:key];
        else
            [convertedDictionary setValue:object forKey:key];
    }
    return convertedDictionary;
}

#pragma mark -
#pragma mark Custom PIN entry

/**
 Load the custom configuration and overlay the current view with the custom PIN entry view
 */

- (void)showPinEntryViewInMode:(PINEntryModes)mode
{
    if ([[UIScreen mainScreen] bounds].size.height == 480) {
        self.pinViewController = [[PinViewController alloc] initWithNibName:@"PINViewController" bundle:nil];
    } else {
        self.pinViewController = [[PinViewController alloc] initWithNibName:@"PINViewController" bundle:nil];
    }

    self.pinViewController.delegate = self;
    self.pinViewController.mode = mode;

    if (self.pluginInitializedCommandTxId) {
        if (self.initializationSuccessful)
            [self sendSuccessCallback:self.inAppBrowserCommandTxId];
        else
            [self sendErrorCallback:self.inAppBrowserCommandTxId];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:self.pinViewController animated:YES completion:nil];
    });
}

/**
 Close the custom PIN entry view
 */
- (void)closePinView
{
    if (self.pinViewController != nil) {
        [self.pinViewController reset];
        [self.viewController dismissViewControllerAnimated:YES completion:nil];
        self.pinViewController = nil;
    }

    pinEntryMode = PINEntryModeUnknown;
}

/**
 After a PIN validation error occurs the PIN entry must be reset to the state where the user can enter the first PIN again.
 */
- (void)retryPinEntryAfterValidationFailure
{
    if (pinEntryMode == PINRegistrationVerififyMode) {
        pinEntryMode = PINRegistrationMode;
    } else if (pinEntryMode == PINChangeNewPinVerifyMode) {
        pinEntryMode = PINChangeNewPinMode;
    }
}

- (bool)isPinValid:(NSString *)pin
{
    NSError *error;
    if (![oneginiClient isPinValid:verifyPin error:&error]) {
        switch (error.code) {
            case 0: {
                [self pinShouldNotBeASequence];
                break;
            }
            case 1: {
                NSNumber *n = error.userInfo[@"kMaxSimilarDigits"];
                [self pinShouldNotUseSimilarDigits:n.integerValue];
                break;
            }
            case 2: {
                [self pinTooShort];
                break;
            }
            case 3: {
                [self pinBlackListed];
                break;
            }
            default: {
                break;
            }
        }
        return NO;
    } else
        return YES;
}

#pragma mark -
#pragma mark PinEntryContainerViewControllerDelegate

- (void)pinEntered:(NSString *)pin
{
    switch (pinEntryMode) {
        case PINCheckMode: {
            [oneginiClient confirmCurrentPin:pin];
            break;
        }
        case PINFingerprintCheckMode: {
            [oneginiClient confirmCurrentPinForFingerprintAuthorization:pin];
            break;
        }
        case PINRegistrationMode: {
            verifyPin = [pin copy];

            if (![self isPinValid:verifyPin]) {
                [self.pinViewController reset];
            } else {
                // Switch to registration mode so the user can enter the second verification PIN
                pinEntryMode = PINRegistrationVerififyMode;
                self.pinViewController.mode = PINRegistrationVerififyMode;
                [self.pinViewController reset];
            }
            break;
        }
        case PINRegistrationVerififyMode: {
            if (![verifyPin isEqualToString:pin]) {
                // Perform a retry of the PIN entry
                verifyPin = nil;
                pinEntryMode = PINRegistrationMode;
                self.pinViewController.mode = PINRegistrationMode;
                [self.pinViewController invalidPinWithReason:[MessagesModel messageForKey:@"PIN_CODES_DIFFERS"]];
            } else {
                // The user entered the second verification PIN, check if they are equal and confirm the PIN
                verifyPin = nil;
                [oneginiClient confirmNewPin:pin validation:self];
            }

            break;
        }
        case PINChangeCheckMode: {
            [oneginiClient confirmCurrentPinForChangeRequest:pin];
            break;
        }
        case PINChangeNewPinMode: {
            verifyPin = [pin copy];
            if (![self isPinValid:verifyPin]) {
                [self.pinViewController reset];
            } else {
                pinEntryMode = PINChangeNewPinVerifyMode;

                self.pinViewController.mode = PINChangeNewPinVerifyMode;
                [self.pinViewController reset];
            }
            break;
        }
        case PINChangeNewPinVerifyMode: {
            if (![verifyPin isEqualToString:pin]) {
                // Perform a retry of the PIN entry
                verifyPin = nil;
                pinEntryMode = PINChangeNewPinMode;
                self.pinViewController.mode = PINChangeNewPinMode;
                [self.pinViewController reset];
                [self.pinViewController invalidPinWithReason:[MessagesModel messageForKey:@"PIN_CODES_DIFFERS"]];
            } else {
                // The user entered the second verification PIN, check if they are equal and confirm the PIN
                verifyPin = nil;
                [oneginiClient confirmNewPinForChangeRequest:pin validation:self];
            }
        }
        default: {
#ifdef DEBUG
            NSLog(@"pinEntered: unknown state");
#endif
        }
    }
}

- (void)pinForgotten
{
    [self closePinView];

    NSDictionary *d = @{kReason : @"authorizationErrorPinForgotten"};
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:d];
    if (authorizeCommandTxId != nil) {
        [self.commandDelegate sendPluginResult:result callbackId:authorizeCommandTxId];
        authorizeCommandTxId = nil;
    } else if (pinChangeCommandTxId != nil) {
        [self.commandDelegate sendPluginResult:result callbackId:pinChangeCommandTxId];
        pinChangeCommandTxId = nil;
    }
}

#pragma mark - Mobile authentication enrollment

- (void)enrollForMobileAuthentication:(CDVInvokedUrlCommand *)command
{
    [self resetAll];
    self.enrollmentCommandTxId = command.callbackId;
    id scopeArgument = [command.arguments firstObject];
    if ([scopeArgument isKindOfClass:[NSArray class]] && ((NSArray *)scopeArgument).count > 0) {
        [[OGOneginiClient sharedInstance] enrollForMobileAuthentication:scopeArgument delegate:self];
    } else {
        [[OGOneginiClient sharedInstance] enrollForMobileAuthentication:nil delegate:self];
    }
}

- (void)enrollmentSuccess
{
    if (self.enrollmentCommandTxId == nil) {
#ifdef DEBUG
        NSLog(@"enrollmentSuccess");
#endif
        [self resetAll];
        return;
    }
    @try {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"enrollmentSuccess"];
        result.keepCallback = @(0);
        [self.commandDelegate sendPluginResult:result callbackId:self.enrollmentCommandTxId];
    } @finally {
        [self resetAll];
    }
}

- (void)enrollmentErrorCallbackWIthReason:(NSString *)reason error:(NSError *)error
{
    if (self.enrollmentCommandTxId == nil) {
        return;
    }
    NSDictionary *d = @{kReason : reason};
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:d];
    [self.commandDelegate sendPluginResult:result callbackId:self.enrollmentCommandTxId];
    [self resetAll];
}

- (void)enrollmentError
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentError" error:nil];
}

- (void)enrollmentError:(NSError *)error
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentError" error:error];
}

- (void)enrollmentNotAvailable
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentErrorNotAvailable" error:nil];
}

- (void)enrollmentInvalidRequest
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentErrorInvalidRequest" error:nil];
}

- (void)enrollmentInvalidTransaction
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentErrorInvalidTransaction" error:nil];
}

- (void)enrollmentAuthenticationError
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentErrorAuthenticationError" error:nil];
}

- (void)enrollmentUserAlreadyEnrolled
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentErrorUserAlreadyEnrolled" error:nil];
}

- (void)enrollmentDeviceAlreadyEnrolled
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentErrorDeviceAlreadyEnrolled" error:nil];
}

- (void)enrollmentInvalidClientCredentials
{
    [self enrollmentErrorCallbackWIthReason:@"enrollmentErrorInvalidClientCredentials" error:nil];
}

@end
