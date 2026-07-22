# local/Dockerfile — used with `kind load docker-image` for local cluster development
# Builder stage — a pinned Maven+JDK image: the render ships no maven wrapper, and the pinned
# image keeps the toolchain reproducible without carrying wrapper binaries in the template.
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /workspace

COPY . .
RUN mvn -q -B -pl {{ project-name }}-server -am -DskipTests package

# Runtime stage
FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app

COPY --from=builder /workspace/{{ project-name }}-server/target/*.jar app.jar

USER appuser
EXPOSE {{ service_port }} {{ management_port }}
ENTRYPOINT ["java", "-jar", "app.jar"]
