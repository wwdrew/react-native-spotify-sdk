package com.wwdrew.reactnativespotifysdk

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import java.util.HashMap

class ReactNativeSpotifySdkPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
    return if (name == ReactNativeSpotifySdkModule.NAME) {
      ReactNativeSpotifySdkModule(reactContext)
    } else {
      null
    }
  }

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
    mapOf(
      ReactNativeSpotifySdkModule.NAME to ReactModuleInfo(
        name = ReactNativeSpotifySdkModule.NAME,
        className = ReactNativeSpotifySdkModule.NAME,
        canOverrideExistingModule = false,
        needsEagerInit = false,
        isCxxModule = false,
        isTurboModule = true
      )
    )
  }
}
