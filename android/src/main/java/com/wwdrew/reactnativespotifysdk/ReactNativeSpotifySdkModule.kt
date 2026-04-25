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
import com.spotify.android.appremote.api.ConnectionParams
import com.spotify.android.appremote.api.Connector
import com.spotify.android.appremote.api.SpotifyAppRemote
import com.spotify.protocol.types.PlayerState
import com.spotify.protocol.types.Repeat
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
  private var appRemote: SpotifyAppRemote? = null

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

  override fun isSpotifyAppInstalled(): Boolean {
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

  override fun connect(accessToken: String, initialContextUri: String?, promise: Promise) {
    val metadata = readSpotifyMetadata(promise) ?: return
    if (accessToken.isBlank()) {
      promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", "connect requires accessToken")
      return
    }

    if (appRemote?.isConnected == true) {
      promise.resolve(null)
      return
    }

    val currentActivity = currentActivity
    if (currentActivity == null) {
      promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", "Activity doesn't exist while trying to connect.")
      return
    }

    val connectionParams =
      ConnectionParams.Builder(metadata.clientId)
        .setRedirectUri(metadata.redirectUri)
        .setAccessToken(accessToken)
        .showAuthView(true)
        .build()

    SpotifyAppRemote.connect(
      reactApplicationContext,
      connectionParams,
      object : Connector.ConnectionListener {
        override fun onConnected(spotifyAppRemote: SpotifyAppRemote) {
          appRemote = spotifyAppRemote
          if (!initialContextUri.isNullOrBlank()) {
            spotifyAppRemote.playerApi.play(initialContextUri)
          }
          promise.resolve(null)
        }

        override fun onFailure(error: Throwable) {
          promise.reject(
            "ERR_REACT_NATIVE_SPOTIFY_SDK",
            error.message ?: "Failed to connect to Spotify App Remote.",
            error
          )
        }
      }
    )
  }

  override fun disconnect(promise: Promise) {
    val remote = appRemote
    if (remote != null) {
      SpotifyAppRemote.disconnect(remote)
      appRemote = null
    }
    promise.resolve(null)
  }

  override fun isConnected(promise: Promise) {
    promise.resolve(appRemote?.isConnected == true)
  }

  override fun play(uri: String, index: Double, positionMs: Double, promise: Promise) {
    withPlayerApi(promise) { remote ->
      if (uri.isBlank()) {
        promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", "play requires uri")
        return@withPlayerApi
      }
      // Spotify App Remote API does not expose an index-based play call.
      val normalizedIndex = index.toInt()

      remote.playerApi
        .play(uri)
        .setResultCallback {
          val normalizedPositionMs = positionMs.toLong()
          if (normalizedPositionMs >= 0L) {
            remote.playerApi
              .seekTo(normalizedPositionMs)
              .setResultCallback { promise.resolve(null) }
              .setErrorCallback { error ->
                promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
              }
          } else {
            if (normalizedIndex >= 0) {
              // Keep parity with JS API without failing unsupported index input.
            }
            promise.resolve(null)
          }
        }
        .setErrorCallback { error ->
          promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
        }
    }
  }

  override fun pause(promise: Promise) {
    withPlayerApi(promise) { remote ->
      remote.playerApi.pause().setResultCallback { promise.resolve(null) }.setErrorCallback { error ->
        promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
      }
    }
  }

  override fun resume(promise: Promise) {
    withPlayerApi(promise) { remote ->
      remote.playerApi.resume().setResultCallback { promise.resolve(null) }.setErrorCallback { error ->
        promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
      }
    }
  }

  override fun skipNext(promise: Promise) {
    withPlayerApi(promise) { remote ->
      remote.playerApi.skipNext().setResultCallback { promise.resolve(null) }.setErrorCallback { error ->
        promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
      }
    }
  }

  override fun skipPrevious(promise: Promise) {
    withPlayerApi(promise) { remote ->
      remote.playerApi.skipPrevious().setResultCallback { promise.resolve(null) }
        .setErrorCallback { error ->
          promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
        }
    }
  }

  override fun seekTo(positionMs: Double, promise: Promise) {
    withPlayerApi(promise) { remote ->
      remote.playerApi.seekTo(positionMs.toLong()).setResultCallback { promise.resolve(null) }
        .setErrorCallback { error ->
          promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
        }
    }
  }

  override fun setShuffle(enabled: Boolean, promise: Promise) {
    withPlayerApi(promise) { remote ->
      remote.playerApi.setShuffle(enabled).setResultCallback { promise.resolve(null) }
        .setErrorCallback { error ->
          promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
        }
    }
  }

  override fun setRepeatMode(mode: String, promise: Promise) {
    withPlayerApi(promise) { remote ->
      val repeatMode =
        when (mode) {
          "track" -> Repeat.TRACK
          "context" -> Repeat.CONTEXT
          else -> Repeat.OFF
        }
      remote.playerApi.setRepeat(repeatMode).setResultCallback { promise.resolve(null) }
        .setErrorCallback { error ->
          promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
        }
    }
  }

  override fun getPlayerState(promise: Promise) {
    withPlayerApi(promise) { remote ->
      remote.playerApi.playerState.setResultCallback { state ->
        promise.resolve(serializePlayerState(state))
      }.setErrorCallback { error ->
        promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", error.message, error)
      }
    }
  }

  private fun withPlayerApi(promise: Promise, block: (SpotifyAppRemote) -> Unit) {
    val remote = appRemote
    if (remote == null || !remote.isConnected) {
      promise.reject("ERR_REACT_NATIVE_SPOTIFY_SDK", "Not connected to Spotify App Remote.")
      return
    }
    block(remote)
  }

  private fun serializePlayerState(state: PlayerState): Map<String, Any?> {
    val repeatMode =
      when (state.playbackOptions.repeatMode) {
        Repeat.TRACK -> "track"
        Repeat.CONTEXT -> "context"
        else -> "off"
      }

    return mapOf(
      "trackUri" to state.track.uri,
      "trackName" to state.track.name,
      "artistName" to state.track.artist.name,
      "albumName" to state.track.album.name,
      "durationMs" to state.track.duration.toDouble(),
      "positionMs" to state.playbackPosition.toDouble(),
      "isPaused" to state.isPaused,
      "shuffle" to state.playbackOptions.isShuffling,
      "repeatMode" to repeatMode,
      "contextUri" to state.playbackOptions.playbackContextUri
    )
  }

  private data class SpotifyMetadata(val clientId: String, val redirectUri: String)

  private fun readSpotifyMetadata(promise: Promise): SpotifyMetadata? {
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
        return null
      }

    val metadata = appInfo.metaData
    val clientId = metadata?.getString("spotifyClientId")
    val redirectUri = metadata?.getString("spotifyRedirectUri")
    if (clientId.isNullOrBlank() || redirectUri.isNullOrBlank()) {
      promise.reject(
        "ERR_REACT_NATIVE_SPOTIFY_SDK",
        "Missing Spotify metadata. Ensure spotifyClientId and spotifyRedirectUri are configured."
      )
      return null
    }
    return SpotifyMetadata(clientId, redirectUri)
  }

  companion object {
    const val NAME = NativeReactNativeSpotifySdkSpec.NAME
  }
}
