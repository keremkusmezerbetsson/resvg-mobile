plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    `maven-publish`
}

android {
    namespace = "com.resvg.mobile.ui"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    api(project(":resvg-mobile"))
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.compose.ui:ui:1.7.6")
    implementation("androidx.compose.foundation:foundation:1.7.6")
    implementation("androidx.compose.runtime:runtime:1.7.6")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}

publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "com.resvg"
            artifactId = "resvg-mobile-ui"
            version = "0.1.0"
            afterEvaluate {
                from(components["release"])
            }
            pom {
                name.set("resvg-mobile-ui")
                description.set("Compose / View wrappers for resvg-mobile")
                url.set("https://github.com/keremkusmezerbetsson/resvg-mobile")
                licenses {
                    license {
                        name.set("The Apache License, Version 2.0")
                        url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
                    }
                }
                developers {
                    developer {
                        id.set("keremkusmezer")
                        name.set("Kerem Kusmezer")
                    }
                }
                scm {
                    connection.set("scm:git:git://github.com/keremkusmezerbetsson/resvg-mobile.git")
                    developerConnection.set("scm:git:ssh://github.com:keremkusmezerbetsson/resvg-mobile.git")
                    url.set("https://github.com/keremkusmezerbetsson/resvg-mobile")
                }
            }
        }
    }
}
