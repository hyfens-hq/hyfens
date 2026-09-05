group = "dev.hyfens.hyfens_flutter_integration"
version = "1.0-SNAPSHOT"

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.hyfens.hyfens_flutter_integration"

    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 23
    }
}
