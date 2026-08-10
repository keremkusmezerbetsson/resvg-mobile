plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    `maven-publish`
}

android {
    namespace = "com.resvg.mobile"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
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

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

dependencies {
    api("net.java.dev.jna:jna:5.15.0@aar")
}

publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "com.resvg"
            artifactId = "resvg-mobile"
            version = "0.1.0"
            afterEvaluate {
                from(components["release"])
            }
            pom {
                name.set("resvg-mobile")
                description.set("Cross-platform SVG rasterizer (resvg + UniFFI) for Android")
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

// Build Rust cdylib for Android ABIs via cargo-ndk when available.
tasks.register<Exec>("cargoNdkBuild") {
    workingDir = file("../../rust")
    commandLine(
        "cargo", "ndk",
        "-t", "arm64-v8a",
        "-t", "armeabi-v7a",
        "-t", "x86_64",
        "-o", "../android/resvg-mobile/src/main/jniLibs",
        "build", "-p", "resvg-mobile", "--release"
    )
    isIgnoreExitValue = false
    onlyIf {
        try {
            providers.exec { commandLine("cargo", "ndk", "--version") }.result.get().exitValue == 0
        } catch (_: Exception) {
            false
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn("cargoNdkBuild")
}
