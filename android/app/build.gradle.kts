plugins {
    id("com.android.application")
}

android {
    namespace = "com.claudecodeacademy.course"

    // 35 = Android 15. Google Play requires new apps to target the level that
    // was current one year ago, and 35 is the floor from August 2025 onward.
    compileSdk = 35

    defaultConfig {
        applicationId = "com.claudecodeacademy.course"

        // 24 = Android 7.0. Below this the system WebView is old enough that
        // the deck's CSS (clamp(), env(), grid) starts failing in ways a
        // beginner would read as the course being broken. 24 still covers
        // essentially every device in use.
        minSdk = 24
        targetSdk = 35

        versionCode = 1
        versionName = "1.0"

        // No instrumentation tests ship with a WebView shell; the course itself
        // is the thing under test and it is verified in the browser build.
    }

    signingConfigs {
        create("release") {
            // Supplied out-of-band so no key material is ever committed. The
            // build falls back to unsigned if they are absent, which is what
            // you want on a machine that is not the release machine.
            val storePath = System.getenv("ACADEMY_KEYSTORE")
            if (storePath != null && file(storePath).exists()) {
                storeFile = file(storePath)
                storePassword = System.getenv("ACADEMY_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ACADEMY_KEY_ALIAS")
                keyPassword = System.getenv("ACADEMY_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (System.getenv("ACADEMY_KEYSTORE") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // course.html is already a single minified-by-hand file; compressing it
    // again inside the APK saves little and costs a decompress on every launch.
    androidResources {
        noCompress += listOf("html")
    }

    packaging {
        resources {
            excludes += setOf("/META-INF/{AL2.0,LGPL2.1}")
        }
    }

    lint {
        // The course is the product; a lint regression should stop a release.
        abortOnError = true
        warningsAsErrors = false
    }
}

// No dependencies at all — not even AndroidX. Everything used (WebView,
// Activity, WindowInsets) is in the platform. That is what keeps the APK
// around a megabyte over the course itself and makes an offline build possible.
dependencies {
}
