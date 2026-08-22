allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// In modern Gradle/Kotlin DSL, use layout.buildDirectory instead of the deprecated buildDir
rootProject.layout.buildDirectory.set(rootProject.file("../build"))

subprojects {
    evaluationDependsOn(":app")

    if (!projectDir.path.contains("C:\\")) {
        // Appends the subproject's name to the root build directory
        layout.buildDirectory.set(rootProject.layout.buildDirectory.dir(name))
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}