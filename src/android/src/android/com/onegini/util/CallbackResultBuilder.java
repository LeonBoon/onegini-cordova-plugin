package com.onegini.util;

import static org.apache.cordova.PluginResult.Status.ERROR;
import static org.apache.cordova.PluginResult.Status.OK;

import java.util.HashMap;

import org.apache.cordova.PluginResult;
import org.json.JSONObject;

import android.text.TextUtils;

public class CallbackResultBuilder {

  private boolean shouldKeepCallback;
  private HashMap<String, String> payload;
  private PluginResult.Status status;
  private String message;

  public CallbackResultBuilder() {
    payload = new HashMap<String, String>();
  }

  public CallbackResultBuilder withSuccess() {
    status = OK;
    return this;
  }

  public CallbackResultBuilder withSuccessMethod(final String method) {
    status = OK;
    payload.put("method", method);
    return this;
  }

  public CallbackResultBuilder withSuccessMessage(final String message) {
    status = OK;
    this.message = message;
    return this;
  }

  public CallbackResultBuilder withError() {
    status = ERROR;
    return this;
  }

  public CallbackResultBuilder withErrorMessage(final String message) {
    status = ERROR;
    this.message = message;
    return this;
  }

  public CallbackResultBuilder withErrorReason(final String reason) {
    status = ERROR;
    payload.put("reason", reason);
    return this;
  }

  public CallbackResultBuilder withRemainingAttempts(final int remainingAttempts) {
    status = ERROR;
    payload.put("remainingAttempts", Integer.toString(remainingAttempts));
    return this;
  }

  public CallbackResultBuilder withMaxSimilarDigits(final int maxSimilar) {
    payload.put("maxSimilarDigits", Integer.toString(maxSimilar));
    return this;
  }

  public CallbackResultBuilder withCallbackKept() {
    shouldKeepCallback = true;
    return this;
  }

  public CallbackResultBuilder withURL(final String url) {
    payload.put("url", url);
    return this;
  }

  public PluginResult build() {
    final PluginResult result;
    if (TextUtils.isEmpty(message)) {
      result = new PluginResult(status, new JSONObject(payload));
    } else {
      result = new PluginResult(status, message);
    }
    result.setKeepCallback(shouldKeepCallback);
    return result;
  }
}
