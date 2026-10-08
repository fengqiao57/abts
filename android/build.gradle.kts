allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// umeng_common_sdk 1.3.1 同时打包了同名的 Kotlin 空壳与 Java 实现（都叫
// UmengCommonSdkPlugin），Kotlin 编译器会报 "Redeclaration"。
// 这里把 Kotlin 空壳从 Kotlin 源集中排除，保留功能完整的 Java 实现。
// 注意：必须在任何子项目被 evaluate 之前注册，否则 afterEvaluate 会抛异常。
subprojects {
    if (name != "umeng_common_sdk") return@subprojects
    afterEvaluate {
        val kotlinExt = extensions.findByName("kotlin") ?: return@afterEvaluate
        try {
            @Suppress("UNCHECKED_CAST")
            val sets = kotlinExt.javaClass.getMethod("getSourceSets")
                .invoke(kotlinExt) as org.gradle.api.NamedDomainObjectContainer<Any>
            val mainSet = sets.getByName("main")
            val kotlinDirs = mainSet.javaClass.getMethod("getKotlin").invoke(mainSet)
            val exclude = kotlinDirs.javaClass.getMethod("exclude", Array<String>::class.java)
            exclude.invoke(
                kotlinDirs,
                *arrayOf<Any>("com/umeng/umeng_common_sdk/UmengCommonSdkPlugin.kt"),
            )
            logger.lifecycle("[abts] 已排除 umeng_common_sdk 的重复 Kotlin 空壳")
        } catch (e: Exception) {
            logger.warn("[abts] 跳过 umeng Kotlin 源集过滤: ${e.message}")
        }
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
    project.evaluationDependsOn(":app")
}

// 统一所有子模块（含 Flutter 插件）的 JVM 目标为 17：
// 个别老插件（如 umeng_common_sdk）未声明 Java 17，会出现
// "Inconsistent JVM Target Compatibility Between Java and Kotlin Tasks" 导致构建失败。
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
