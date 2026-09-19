pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "resvg-mobile"
include(":resvg-mobile")
include(":resvg-mobile-ui")
include(":resvg-mobile-coil")
include(":demo")
include(":gallery")
