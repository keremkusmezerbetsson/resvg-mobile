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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    flavorDimensions += "features"
    productFlavors {
        create("full") {
            dimension = "features"
            isDefault = true
        }
        create("noImages") {
            dimension = "features"
        }
        create("noText") {
            dimension = "features"
        }
        create("minimal") {
            dimension = "features"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    publishing {
        multipleVariants {
            allVariants()
            withSourcesJar()
        }
    }

    sourceSets {
        getByName("full") {
            jniLibs.srcDirs("src/full/jniLibs")
        }
        getByName("noImages") {
            jniLibs.srcDirs("src/noImages/jniLibs")
        }
        getByName("noText") {
            jniLibs.srcDirs("src/noText/jniLibs")
        }
        getByName("minimal") {
            jniLibs.srcDirs("src/minimal/jniLibs")
        }
    }
}

dependencies {
    api("net.java.dev.jna:jna:5.15.0@aar")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
}

publishing {
    publications {
        fun MavenPublication.configurePom(artifact: String, desc: String) {
            groupId = "com.resvg"
            artifactId = artifact
            version = "0.1.0"
            pom {
                name.set(artifact)
                description.set(desc)
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
                    developerConnection.set("scm:git:ssh://git@github.com/keremkusmezerbetsson/resvg-mobile.git")
                    url.set("https://github.com/keremkusmezerbetsson/resvg-mobile")
                }
            }
        }

        create<MavenPublication>("fullRelease") {
            configurePom("resvg-mobile", "Cross-platform SVG rasterizer (full: text + images)")
            afterEvaluate { from(components["fullRelease"]) }
        }
        create<MavenPublication>("noImagesRelease") {
            configurePom("resvg-mobile-no-images", "resvg-mobile without JPEG/GIF/WebP codecs")
            afterEvaluate { from(components["noImagesRelease"]) }
        }
        create<MavenPublication>("noTextRelease") {
            configurePom("resvg-mobile-no-text", "resvg-mobile without font/text stack")
            afterEvaluate { from(components["noTextRelease"]) }
        }
        create<MavenPublication>("minimalRelease") {
            configurePom("resvg-mobile-minimal", "resvg-mobile without text and image codecs")
            afterEvaluate { from(components["minimalRelease"]) }
        }
    }
}

fun hasCargoNdk(): Boolean = try {
    providers.exec { commandLine("cargo", "ndk", "--version") }.result.get().exitValue == 0
} catch (_: Exception) {
    false
}

fun jniLibsPresent(): Boolean {
    val flavors = listOf("full", "noImages", "noText", "minimal")
    return flavors.any { flavor ->
        val root = file("src/$flavor/jniLibs")
        root.isDirectory && root.walkTopDown().any { it.isFile && it.extension == "so" }
    }
}

// Build Rust cdylibs via cargo-ndk (default: full flavor only; VARIANT=all for every size).
tasks.register<Exec>("cargoNdkBuild") {
    workingDir = file("../../")
    commandLine("bash", "scripts/build-android-variants.sh")
    environment("VARIANT", System.getenv("VARIANT") ?: "full")
    isIgnoreExitValue = false
    onlyIf {
        hasCargoNdk() && System.getenv("SKIP_CARGO_NDK") != "1"
    }
}

tasks.register("verifyJniLibs") {
    doLast {
        if (!jniLibsPresent()) {
            throw GradleException(
                "Missing libuniffi_resvg_mobile.so under src/<flavor>/jniLibs. " +
                    "Run ./scripts/build-android-variants.sh (requires cargo-ndk), " +
                    "or set VARIANT=full for a single flavor.",
            )
        }
    }
}

tasks.named("verifyJniLibs").configure {
    mustRunAfter("cargoNdkBuild")
}

tasks.named("preBuild").configure {
    dependsOn("cargoNdkBuild")
    dependsOn("verifyJniLibs")
}
