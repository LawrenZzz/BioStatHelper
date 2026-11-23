import com.android.build.gradle.LibraryExtension
import org.gradle.api.Project
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory

fun Project.androidNamespaceFromManifest(): String? {
    val manifest = file("src/main/AndroidManifest.xml")
    if (!manifest.isFile) return null

    return runCatching {
        DocumentBuilderFactory
            .newInstance()
            .newDocumentBuilder()
            .parse(manifest)
            .documentElement
            .getAttribute("package")
            .takeIf { it.isNotBlank() }
    }.getOrNull()
}

fun Project.fallbackAndroidNamespace(): String {
    val cleanName = name
        .replace(Regex("[^A-Za-z0-9_]"), "_")
        .lowercase(Locale.ROOT)
    return "com.biostathelper.plugins.$cleanName"
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            compileSdk = 36

            if (namespace.isNullOrBlank()) {
                namespace = project.androidNamespaceFromManifest()
                    ?: project.fallbackAndroidNamespace()
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
