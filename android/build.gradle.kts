// Plugin versions are declared once, in settings.gradle.kts.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter expects every module to build into <project>/build/<module>, which
// is where `flutter build apk` then looks for the artifacts.
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
