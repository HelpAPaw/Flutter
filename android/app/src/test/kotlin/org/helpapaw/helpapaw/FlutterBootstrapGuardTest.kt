package org.helpapaw.helpapaw

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Guards the native entrypoints into Dart against losing their FlutterLoader
 * initialization.
 *
 * Android delivers background location to a `BroadcastReceiver` in a process
 * that has no Flutter engine and never built an Activity, so nothing has called
 * `System.loadLibrary("flutter")`. Calling into `FlutterJNI` there — which
 * `FlutterCallbackInformation.lookupCallbackInformation` does — throws
 * `UnsatisfiedLinkError`, an `Error` rather than an `Exception`, which killed
 * the process on every location delivery until [HeadlessNearbyCheck] was given
 * an explicit `FlutterLoader` init.
 *
 * That failure is now caught, which is the reason this test has to exist: the
 * loud symptom is gone. A regression would leave the arrival catch-up
 * permanently dead while the app looks healthy — the same silent outage
 * [GeohashTest] and `test/firestore_settings_guard_test.dart` exist to prevent.
 *
 * This is a source scan rather than a behavioural test because no JVM unit test
 * can load `libflutter.so`, so `HeadlessNearbyCheck.run` cannot be exercised at
 * all. Scanning text is crude, but it catches the two edits that actually
 * reintroduce the bug: adding a new headless entrypoint without the init, and
 * reordering an existing one so the JNI call moves back above it.
 */
class FlutterBootstrapGuardTest {

    /**
     * Symbols that reach `FlutterJNI` and therefore need the native library
     * loaded first. `DartExecutor` is included because executing a Dart
     * callback is the other half of the same path.
     */
    private val jniEntrypoints = listOf(
        "FlutterCallbackInformation",
        "FlutterEngine(",
        "DartExecutor",
    )

    private val INIT = "ensureInitializationComplete"

    /**
     * `MainActivity` is exempt: it extends `FlutterActivity`, which runs the
     * loader for it before any of this is reachable. Every other file is not.
     */
    private val exempt = setOf("MainActivity.kt")

    private fun sourceFiles(): List<File> {
        // Gradle runs unit tests with the module directory as the working dir.
        val root = File("src/main/kotlin")
        assertTrue(
            "expected Kotlin sources at ${root.absolutePath} — has the module " +
                "layout or the test working directory changed?",
            root.isDirectory,
        )
        val files = root.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue("found no Kotlin sources to scan", files.isNotEmpty())
        return files
    }

    @Test
    fun `every file that calls into FlutterJNI also initializes FlutterLoader`() {
        for (file in sourceFiles()) {
            if (file.name in exempt) continue
            val source = file.readText()
            val used = jniEntrypoints.filter { source.contains(it) }
            if (used.isEmpty()) continue

            if (!source.contains(INIT)) {
                fail(
                    "${file.name} calls into FlutterJNI (${used.joinToString(", ")}) but never " +
                        "calls $INIT. In a process with no Activity the native library is not " +
                        "loaded, so this throws UnsatisfiedLinkError instead of running. Call " +
                        "FlutterInjector.instance().flutterLoader().startInitialization(context) " +
                        "and $INIT(context, null) on the main thread first.",
                )
            }
        }
    }

    @Test
    fun `HeadlessNearbyCheck initializes FlutterLoader before the callback lookup`() {
        val source = File("src/main/kotlin/org/helpapaw/helpapaw/HeadlessNearbyCheck.kt")
        assertTrue("HeadlessNearbyCheck.kt not found at ${source.absolutePath}", source.isFile)
        val text = source.readText()

        val initAt = text.indexOf(INIT)
        val lookupAt = text.indexOf("FlutterCallbackInformation.lookupCallbackInformation")
        assertTrue("$INIT not found in HeadlessNearbyCheck.kt", initAt >= 0)
        assertTrue("lookupCallbackInformation not found in HeadlessNearbyCheck.kt", lookupAt >= 0)

        assertTrue(
            "$INIT must come before lookupCallbackInformation: the lookup is a JNI call and " +
                "needs libflutter.so already loaded. Moving it above the init reintroduces an " +
                "UnsatisfiedLinkError on every background location delivery.",
            initAt < lookupAt,
        )
    }
}
