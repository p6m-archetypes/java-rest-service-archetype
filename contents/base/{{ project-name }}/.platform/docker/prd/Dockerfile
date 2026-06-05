# prd/Dockerfile — used for CI/CD production builds
# Builder stage
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /workspace

COPY . .
RUN ./mvnw -pl {{ project-name }}-server -am -q -DskipTests package

# Runtime stage
FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app

COPY --from=builder /workspace/{{ project-name }}-server/target/*.jar app.jar

USER appuser
EXPOSE {{ service_port }} {{ management_port }}
ENTRYPOINT ["java", "-jar", "app.jar"]
