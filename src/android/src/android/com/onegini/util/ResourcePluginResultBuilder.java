package com.onegini.util;

import static org.apache.cordova.PluginResult.Status.ERROR;
import static org.apache.cordova.PluginResult.Status.OK;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import org.apache.cordova.PluginResult;
import org.apache.cordova.PluginResult.Status;
import org.bouncycastle.util.encoders.Base64;
import org.json.JSONObject;

import retrofit.client.Header;
import retrofit.client.Response;

public class ResourcePluginResultBuilder {

  private final byte[] responseBody;
  private final Response responseObject;
  private Status status;

  public ResourcePluginResultBuilder(final byte[] responseBody, final Response responseObject) {
    this.responseBody = responseBody;
    this.responseObject = responseObject;
  }

  public ResourcePluginResultBuilder(final String responseBody) {
    this.responseBody = responseBody.getBytes();
    this.responseObject = new Response("", 400, "", Collections.EMPTY_LIST, null);
  }

  public ResourcePluginResultBuilder withSuccess() {
    this.status = OK;

    return this;
  }

  public ResourcePluginResultBuilder withError() {
    this.status = ERROR;

    return this;
  }

  public PluginResult build() {
    final PluginResult result = new PluginResult(status, new JSONObject(buildSerializedResponse()));
    result.setKeepCallback(false);

    return result;
  }

  private Map<String, Object> buildSerializedResponse() {
    final Map<String, Object> response = new HashMap<String, Object>();
    response.put("headers", buildHeaders());
    response.put("status", responseObject.getStatus());
    response.put("reason", responseObject.getReason());
    response.put("url", responseObject.getUrl());
    response.put("body", buildSerializedBody());

    return response;
  }

  private String buildSerializedBody() {
    if (responseBody == null) {
      return "";
    } else {
      return Base64.toBase64String(responseBody);
    }
  }

  private Map<String, String> buildHeaders() {
    final Map<String, String> headers = new HashMap<String, String>();
    for (Header header : responseObject.getHeaders()) {
      headers.put(header.getName(), header.getValue());
    }

    return headers;
  }

}
