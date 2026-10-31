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
// 토스 결제위젯 SDK 의 웹뷰 플러그인(tosspayments_webview_flutter 1.0.6)이 compileSdk 31 로 고정돼 있어,
// 의존 androidx(fragment 1.7 등)가 요구하는 34 이상으로 올린다. 패키지 파일은 고치지 않는다.
subprojects {
    if (name == "tosspayments_webview_flutter") {
        afterEvaluate {
            extensions.getByType(com.android.build.api.dsl.LibraryExtension::class.java).compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
