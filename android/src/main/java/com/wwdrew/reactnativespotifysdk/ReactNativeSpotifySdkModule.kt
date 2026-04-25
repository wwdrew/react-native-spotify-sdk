package com.wwdrew.reactnativespotifysdk

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.spotify.sdk.android.auth.AuthorizationClient
import com.spotify.sdk.android.auth.AuthorizationRequest
import com.spotify.sdk.android.auth.AuthorizationResponse
import com.spotify.sdk.android.auth.app.SpotifyNativeAuthUtil
import okhttp3.Call
import okhttp3.Callback
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException

class ReactNativeSpotifySdkModule(reactContext: ReactApplicationContext) :
  NativeReactNativeSpotifySdkSpec(reactContext) {

  private val requestCode = 2095
  private val httpClient = OkHttpClient()
  private var authPromise: Promise? = null
  private var authScopes: List<String> = emptyList()

  private val activityEventListener =
    object : ActivityEventListener {
      override fun onActivityResult(
        activity: Activity?,
        requestCode: Int,
        resultCode: Int,
        data: Intent?
      ) {
        if (requestCode != this@ReactNativeSpotifySdkModule.requestCode) return

        val promise = authPromise ?: return
        authPromise = null

        val authResponse = AuthorizationClient.getResponse(resultCode, data)

        when (authResponse.type) {
          AuthorizationResponse.Type.TOKEN -> {
            val expirationDate = System.currentTimeMillis() + authResponse.expiresIn * 1000
            promise.resolve(
              mapOf(
                "accessToken" to authResponse.accessToken,
                "refreshToken" to null,
                "expirationDate" to expirationDate,
                "scopes" to authScopes
              )
            )
          }

          AuthorizationResponse.Type.CODE -> {
            val tokenSwapURL = pendingTokenSwapURL
            if (tokenSwapURL.isNullOrBlank()) {
              promise.reject(
                "ERR_REACT_NATIVE_SPOTIFY_SDK",
                "Received authorization code but no tokenSwapURL was provided."
              )
              return
            }
            exchangeCodeForToken(tokenSwapURL, authResponse.code ?: "", promise)
          }

          AuthorizationResponse.Type.ERROR -> {
            promise.reject(
              "ERR_REACT_NATIVE_SPOTIFY_SDK",
              authResponse.error ?: "Spotify authentication failed."
            )
          }

          else -> {
            promise.reject(
              "ERR_REACT_NATIVE_SPOTIFY_SDK",
              "Spotify authentication cancelled or returned an unknown response."
            )
          }
        }
      }

      override fun onNewIntent(intent: Intent?) = Unit
    }

  private var pendingTokenSwapURL: String? = null

  init {
    reactContext.addActivityEventListener(activityEventListener)
  }

  override fun invalidate() {
    super.invalidate()
    reactApplicationContext.removeActivityEventListener(activityEventListener)
  }

  override fun isAvailable(): Boolean {
    return SpotifyNativeAuthUtil.isSpotifyInstalled(reactApplicationContext)
  }

  override fun authenticate(
    scopes: ReadableArray,
    tokenSwapURL: String?,
    tokenRefreshURL: String?,
    promise: Promise
  ) {
    val currentActivity = currentActivity
    if (currentActivity == null) {
      promise.reject(
        "ERR_REACT_NATIVE_SPOTIFY_SDK",
        "Activity doesn't exist while trying to authenticate."
      )
      return
    }

    val appInfo =
      try {
        reactApplicationContext.packageManager.getApplicationInfo(
          reactApplicationContext.packageName,
          PackageManager.GET_META_DATA
        )
      } catch (error: PackageManager.NameNotFoundException) {
        promise.reject(
          "ERR_REACT_NATIVE_SPOTIFY_SDK",
          "Unable to read AndroidManifest metadata for Spotify config.",
          error
        )
        return
      }

    val metadata = appInfo.metaData
    val clientId = metadata?.getString("spotifyClientId")
    val redirectUri = metadata?.getString("spotifyRedirectUri")

    if (clientId.isNullOrBlank() || redirectUri.isNullOrBlank()) {
      promise.reject(
        "ERR_REACT_NATIVE_SPOTIFY_SDK",
        "Missing Spotify metadata. Ensure spotifyClientId and spotifyRedirectUri are configured."
      )
      return
    }

    val scopeList = mutableListOf<String>()
    for (index in 0 until scopes.size()) {
      scopeList.add(scopes.getString(index) ?: "")
    }

    if (scopeList.isEmpty()) {
      promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", "scopes are required")
      return
    }

    val responseType =
      if (!tokenSwapURL.isNullOrBlank() || !tokenRefreshURL.isNullOrBlank()) {
        AuthorizationResponse.Type.CODE
      } else {
        AuthorizationResponse.Type.TOKEN
      }

    val request =
      AuthorizationRequest.Builder(clientId, responseType, redirectUri)
        .setScopes(scopeList.toTypedArray())
        .build()

    authPromise = promise
    authScopes = scopeList
    pendingTokenSwapURL = tokenSwapURL
    AuthorizationClient.openLoginActivity(currentActivity, requestCode, request)
  }

  private fun exchangeCodeForToken(tokenSwapURL: String, code: String, promise: Promise) {
    val body = FormBody.Builder().add("code", code).build()
    val request =
      Request.Builder()
        .url(tokenSwapURL)
        .post(body)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .build()

    httpClient.newCall(request).enqueue(
      object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", e.message, e)
        }

        override fun onResponse(call: Call, response: Response) {
          response.use {
            if (!response.isSuccessful) {
              promise.reject(
                "ERR_REACT_NATIVE_SPOTIFY_SDK",
                "Token swap failed with status ${response.code}"
              )
              return
            }

            val rawBody = response.body?.string()
            if (rawBody.isNullOrBlank()) {
              promise.reject(
                "ERR_REACT_NATIVE_SPOTIFY_SDK",
                "Token swap response was empty."
              )
              return
            }

            val json = JSONObject(rawBody)
            val accessToken = json.optString("access_token")
            val refreshToken = json.optString("refresh_token", null)
            val expiresIn = json.optLong("expires_in", 0)
            val scopeString = json.optString("scope", "")
            val normalizedScopes =
              if (scopeString.isBlank()) authScopes else scopeString.split(" ")

            val expirationDate = System.currentTimeMillis() + expiresIn * 1000
            promise.resolve(
              mapOf(
                "accessToken" to accessToken,
                "refreshToken" to refreshToken,
                "expirationDate" to expirationDate,
                "scopes" to normalizedScopes
              )
            )
          }
        }
      }
    )
  }

  companion object {
    const val NAME = NativeReactNativeSpotifySdkSpec.NAME
  }
}
