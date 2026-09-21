package dev.pages.abts

import android.content.Context
import com.umeng.commonsdk.UMConfigure
import io.flutter.app.FlutterApplication

/**
 * App Application：友盟统计合规预初始化。
 * preInit 不采集任何信息、不上报数据，仅用于注册；正式初始化在 Dart 侧
 * 用户同意《隐私政策》后调用 initCommon。当前按用户配置无隐私弹窗，
 * Dart 侧启动即初始化，preInit 保留以遵循官方建议并保证日活采集准确。
 */
class AbtsApplication : FlutterApplication() {

    companion object {
        private const val UMENG_APP_KEY = "6ab0a6c174319160830c0ea9"
        private const val UMENG_CHANNEL = "Umeng"
    }

    override fun onCreate() {
        super.onCreate()
        UMConfigure.setLogEnabled(false)
        UMConfigure.preInit(this, UMENG_APP_KEY, UMENG_CHANNEL)
    }
}