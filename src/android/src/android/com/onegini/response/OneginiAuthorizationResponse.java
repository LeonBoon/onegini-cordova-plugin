package com.onegini.response;


public enum OneginiAuthorizationResponse {

  // Authorization flow responses
  AUTHORIZATION_SUCCESS("authorizationSuccess"),
  AUTHORIZATION_REQUEST("requestAuthorization"),
  AUTHORIZATION_ERROR("authorizationError"),
  AUTHORIZATION_ERROR_CLIENT_REG_FAILED("authorizationErrorClientRegistrationFailed"),
  AUTHORIZATION_ERROR_INVALID_GRANT("authorizationErrorInvalidGrant"),
  AUTHORIZATION_ERROR_TOO_MANY_PIN_FAILURES("authorizationErrorTooManyPinFailures"),
  AUTHORIZATION_ERROR_NOT_AUTHENTICATED("authorizationErrorNotAuthenticated"),
  AUTHORIZATION_ERROR_INVALID_SCOPE("authorizationErrorInvalidScope"),
  AUTHORIZATION_ERROR_INVALID_STATE("authorizationErrorInvalidState"),
  AUTHORIZATION_ERROR_NOT_AUTHORIZED("authorizationErrorNotAuthorized"),
  AUTHORIZATION_ERROR_INVALID_REQUEST("authorizationErrorInvalidRequest"),
  AUTHORIZATION_ERROR_INVALID_GRANT_TYPE("authorizationErrorInvalidGrantType"),
  AUTHORIZATION_ERROR_PIN_FORGOTTEN("authorizationErrorPinForgotten"),
  AUTHORIZATION_ERROR_UNSUPPORTED_OS("authorizationErrorUnsupportedOS");

  private final String name;

  private OneginiAuthorizationResponse(final String name) {
    this.name = name;
  }

  public String getName() {
    return name;
  }

}
