#FROM openjdk:11-jre-slim
FROM amazoncorretto:11-alpine
RUN mkdir -p /opt/target
COPY target/liquibase-demo-1.0-SNAPSHOT.jar /opt/target/
WORKDIR /opt/target
CMD ["java", "-jar", "liquibase-demo-1.0-SNAPSHOT.jar"]
