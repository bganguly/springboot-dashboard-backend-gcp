FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY gradlew gradlew.bat* ./
COPY gradle/ gradle/
COPY build.gradle.kts settings.gradle.kts ./
RUN ./gradlew dependencies --no-daemon -q
COPY src/ src/
RUN ./gradlew bootJar --no-daemon -q

FROM eclipse-temurin:21-jre-alpine AS runner
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app && apk add --no-cache netcat-openbsd
COPY --from=builder /app/build/libs/*.jar app.jar
COPY docker-entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh
USER app
EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
