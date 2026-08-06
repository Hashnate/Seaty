package lk.seaty.app

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Android 12+ plays its own exit animation on the system splash icon
        // (scale down + fade) before handing the window over. NormalTheme's
        // windowBackground already paints the same logo at the same size and
        // position underneath, so dropping the splash view outright is
        // invisible — whereas the default animation reads as the icon
        // "shrinking away" just before the Flutter splash appears.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashScreenView ->
                splashScreenView.remove()
            }
        }
    }
}
