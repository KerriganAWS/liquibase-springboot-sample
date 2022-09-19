#FROM openjdk:11-jre-slim
FROM amazoncorretto:11-alpine
RUN mkdir -p /opt/target
COPY target/liquibase-demo.jar /opt/target/
WORKDIR /opt/target
CMD ["java", "-jar", "liquibase-demo.jar"]
