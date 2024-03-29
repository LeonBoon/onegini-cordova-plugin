package com.onegini.action;

import static com.onegini.response.GeneralResponse.CONNECTIVITY_PROBLEM;
import static com.onegini.util.DeviceUtil.isNotConnected;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.Config;
import org.json.JSONArray;

import android.content.Context;
import com.onegini.OneginiCordovaPlugin;
import com.onegini.model.OneginiCordovaPluginConfigModel;
import com.onegini.util.CallbackResultBuilder;

public class AwaitInitialization implements OneginiPluginAction {

  private static CallbackContext pluginInitializedCallback;

  public static void notifyIfPluginInitialized() {
    if (pluginInitializedCallback == null) {
      return;
    }

    if (isPluginInitializedSuccessfully()) {
      pluginInitializedCallback.success();
    }
  }

  private static boolean isPluginInitializedSuccessfully() {
    final OneginiCordovaPluginConfigModel oneginiCordovaPluginConfigModel = OneginiCordovaPluginConfigModel.from(Config.getPreferences());

    final boolean pinCallbackValid = shouldUseHTMLScreens(oneginiCordovaPluginConfigModel) ? isPinCallbackSessionSet() : true;
    final boolean browserControlCallbackValid = shouldUseEmbeddedWebview(oneginiCordovaPluginConfigModel) ? isInAppBrowserControlCallbackSessionSet() : true;

    return PluginInitializer.isConfigured() && pinCallbackValid && browserControlCallbackValid;
  }

  private static boolean shouldUseEmbeddedWebview(final OneginiCordovaPluginConfigModel oneginiCordovaPluginConfigModel) {
    return oneginiCordovaPluginConfigModel.useEmbeddedWebview();
  }

  private static boolean shouldUseHTMLScreens(final OneginiCordovaPluginConfigModel oneginiCordovaPluginConfigModel) {
    return !oneginiCordovaPluginConfigModel.useNativePinScreen();
  }

  public static void notifyPluginInitializationFailed() {
    if (pluginInitializedCallback == null) {
      return;
    }

    pluginInitializedCallback.error("Failed to initialize plugin.");
  }

  @Override
  public void execute(final JSONArray args, final CallbackContext callbackContext, final OneginiCordovaPlugin client) {
    pluginInitializedCallback = callbackContext;

    final CallbackResultBuilder callbackResultBuilder = new CallbackResultBuilder();
    final Context context = client.getCordova().getActivity().getApplication();

    if (isNotConnected(context)) {
      callbackContext.sendPluginResult(callbackResultBuilder
          .withErrorReason(CONNECTIVITY_PROBLEM.getName())
          .build());
      return;
    }

    notifyIfPluginInitialized();
  }

  private static boolean isPinCallbackSessionSet() {
    return PinCallbackSession.getPinCallback() != null;
  }

  private static boolean isInAppBrowserControlCallbackSessionSet() {
    return InAppBrowserControlSession.getInAppBrowserControlCallback() != null;
  }
}
