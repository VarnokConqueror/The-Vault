plugins {
  kotlin("jvm") version "2.2.20"
  application
}

repositories {
  mavenCentral()
  maven(url = "https://build-artifacts.signal.org/libraries/maven/")
}

dependencies {
  implementation(kotlin("stdlib"))
  implementation("org.signal:libsignal-client:0.91.0")
  implementation("com.google.code.gson:gson:2.13.1")
}

kotlin {
  jvmToolchain(21)
}

application {
  mainClass.set("com.theconquerorscourt.vault.bridge.VaultBridgeServerKt")
}

tasks.withType<Jar>().configureEach {
  duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}

val fatJar by tasks.registering(Jar::class) {
  group = "build"
  description = "Builds a self-contained helper jar for the Windows Vault bridge."
  archiveBaseName.set("vault-bridge-helper")
  archiveClassifier.set("all")
  duplicatesStrategy = DuplicatesStrategy.EXCLUDE
  manifest {
    attributes["Main-Class"] = application.mainClass.get()
  }
  from(sourceSets.main.get().output)
  dependsOn(configurations.runtimeClasspath)
  from({
    configurations.runtimeClasspath.get()
      .filter { it.name.endsWith(".jar") }
      .map { zipTree(it) }
  })
}

tasks.build {
  dependsOn(fatJar)
}
