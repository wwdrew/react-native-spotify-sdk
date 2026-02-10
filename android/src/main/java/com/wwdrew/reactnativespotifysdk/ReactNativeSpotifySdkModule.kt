package com.wwdrew.reactnativespotifysdk

import com.facebook.react.bridge.ReactApplicationContext

class ReactNativeSpotifySdkModule(reactContext: ReactApplicationContext) :
  NativeReactNativeSpotifySdkSpec(reactContext) {

  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  companion object {
    const val NAME = NativeReactNativeSpotifySdkSpec.NAME
  }
}
