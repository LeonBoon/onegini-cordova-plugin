# Configuration

This chapter explains how to configure the Onegini Cordova plugin in your Cordova application.

## Properties

The Cordova plugin is mostly automatically configured by the Onegini SDK Configurator. However, a few properties need to be specified manually:
- Native or PIN screens (`OneginiNativeScreens`) - Specifies whether native (authentication) screens or html authentication screens are used. `true` for native, 
`false` for html. If `true` is specified you need to also install the `onegini-cordova-native-screens` plugin. See also the 
[native or HTML Screens page](screens.md) page
- Android GCM sender ID (`OneginiGcmSenderId`) - The Google Cloud Messaging sender ID that you received when registering an application for GCM
- Root detection (`OneginiRootDetectionEnabled`) - Specifies whether root detection must be enabled or disabled. `true` for root detection enabled or `false` 
for root detection disabled.
- Debug detection (`OneginiDebugDetectionEnabled`)- Specifies whether debug detection must be enabled or disabled. `true` for debug detection enabled or 
`false` for debug detection disabled.

>**NB** After you have changed the `OneginiRootDetectionEnabled` or `OneginiDebugDetectionEnabled` properties you must remove and add your platforms again 
because the SDK configurator uses these values to determine whether root or debug detection must be enabled or disabled.

These properties must be specified in the [Cordova application configuration](https://cordova.apache.org/docs/en/latest/config_ref/index.html) file: 
`config.xml`. 

Below you see an example of these properties in the format required for the `config.xml` file.

```xml
  <!-- Onegini Cordova Plugin configuration -->
  <preference name="OneginiNativeScreens" value="true"/>
  <preference name="OneginiGcmSenderId" value="000000000"/>
  <preference name="OneginiRootDetectionEnabled" value="false"/>
  <preference name="OneginiDebugDetectionEnabled" value="false"/>
```

## iOS 9 and Xcode 7 requirements

In order to allow an application to communicate with a backend that does not support TLS 1.2 on iOS version 9.0 and greater an explicit permission needs to be 
added to your iOS application configuration plist file.

We recommend that you add the update platform config hook to your application. An 
[article on Stackoverflow](http://stackoverflow.com/questions/28198983/ionic-cordova-add-intent-filter-using-config-xml) gives the hook code and describes how 
to configure this. When you have configure the hook you can add the following code snippet to your `config.xml`.

```xml
    <config-file platform="ios" target="*-Info.plist" parent="NSAppTransportSecurity">
      <key>NSAppTransportSecurity</key>
      <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
      </dict>
    </config-file>
```

Please also note that if you are using Xcode 7.0 or newer you will have disable bitcode (`ENABLE_BITCODE = false`) in the .xcodeproj generated by Cordova 
framework.