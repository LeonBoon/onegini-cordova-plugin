package com.onegini.resource;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;

import com.onegini.dialog.PinScreenActivity;
import com.onegini.util.ResourcePluginResultBuilder;
import retrofit.Callback;
import retrofit.RetrofitError;
import retrofit.client.Response;

public class ResourceRequestCallback {

  private CallbackContext callbackContext;

  public ResourceRequestCallback(final CallbackContext callbackContext) {
    this.callbackContext = callbackContext;
  }

  public Callback<byte[]> buildResponseCallback() {
    return new Callback<byte[]>() {
      @Override
      public void success(final byte[] responseBody, final Response response) {
        sendCallbackResult(callbackContext, new ResourcePluginResultBuilder(responseBody, response).withSuccess().build());
      }

      @Override
      public void failure(final RetrofitError error) {
        if (error != null && error.getResponse() != null) {
          final byte[] responseBody = getErrorResponseBody(error.getResponse());
          sendCallbackResult(callbackContext, new ResourcePluginResultBuilder(responseBody, error.getResponse()).withError().build());
        } else {
          sendCallbackResult(callbackContext, new ResourcePluginResultBuilder("Failed to fetch resource").withError().build());
        }
      }

      private byte[] getErrorResponseBody(final Response errorResponse) {
        if (errorResponse.getBody() != null) {
          return RetrofitByteConverter.fromTypedInput(errorResponse.getBody());
        } else {
          return new byte[0];
        }
      }

    };
  }

  public static void sendCallbackResult(final CallbackContext callbackContext, final PluginResult result) {
    if (PinScreenActivity.getInstance() != null) {
      PinScreenActivity.getInstance().finish();
    }
    callbackContext.sendPluginResult(result);
  }

}