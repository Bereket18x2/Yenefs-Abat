allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// share_plus 7.2.2 (pinned to dodge an unrelated native-asset build-hook
// crash on newer versions) hardcodes compileSdkVersion 33 in its own
// android/build.gradle, which is now too low for androidx.lifecycle 2.7.0.
// We can't edit that vendored file, so force every Android library
// subproject — including plugins like this one — onto the SDK version
// the app itself compiles against.
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileSdk = 36
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("../../build")
    .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}