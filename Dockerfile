# ============================================================
# Dockerfile Multi-Stage untuk Railway Deployment
# ============================================================
# Stage 1 (builder): Compile & package dengan Maven
# Stage 2 (runtime): Jalankan JAR dengan JRE minimal
#
# Keunggulan vs Nixpacks:
# - MAVEN_OPTS mengontrol heap Maven → tidak OOM
# - Layer caching: dependency download hanya sekali
# - Image final lebih kecil (JRE alpine, bukan JDK)
# ============================================================

# ---- STAGE 1: BUILD ----
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

WORKDIR /app

# Copy pom.xml lebih dulu — manfaatkan Docker layer cache.
# Jika pom.xml tidak berubah, "mvn dependency:go-offline"
# tidak dijalankan ulang di deploy berikutnya.
COPY pom.xml .
COPY mvnw .
COPY .mvn .mvn

# Download semua dependency dengan batas memori eksplisit.
# -Xmx512m: cukup untuk resolve dependency Spring Boot
# --no-transfer-progress: kurangi output log yang membanjiri Railway
RUN MAVEN_OPTS="-Xmx512m -XX:MaxMetaspaceSize=256m -XX:+UseSerialGC" \
    mvn dependency:go-offline -B --no-transfer-progress

# Copy source code (dilakukan SETELAH dependency download agar cache optimal)
COPY src ./src

# Build JAR, skip tests (Railway bukan env untuk testing)
RUN MAVEN_OPTS="-Xmx512m -XX:MaxMetaspaceSize=256m -XX:+UseSerialGC" \
    mvn clean package -DskipTests -B --no-transfer-progress

# ---- STAGE 2: RUNTIME ----
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Buat user non-root dan folder data dengan ownership yang benar
RUN addgroup -S spring && adduser -S spring -G spring && \
    mkdir -p /app/data /app/uploads && \
    chown -R spring:spring /app
USER spring:spring

# Copy hanya JAR dari stage builder
COPY --chown=spring:spring --from=builder /app/target/*.jar app.jar

# Port dideklarasikan (Railway override via $PORT)
EXPOSE 8080

# Jalankan app:
# -Xmx256m        : batas heap runtime (Railway free: 512MB total)
# -Xms64m         : heap awal kecil, biarkan JVM tumbuh sesuai kebutuhan
# -XX:+UseSerialGC: GC ringan untuk container kecil
# -Dserver.port   : ambil PORT dari Railway env var
ENTRYPOINT ["java", \
  "-Xmx256m", "-Xms64m", \
  "-XX:+UseSerialGC", \
  "-XX:MaxMetaspaceSize=128m", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]
