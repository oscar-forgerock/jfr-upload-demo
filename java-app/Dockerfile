#Multi-stage build

#Stage 1: initialize build and set base image for first stage
# FROM gradle:jdk17 AS build
FROM gradle:jdk17 AS build
WORKDIR /opt/app/


COPY . .

# compile the source code and package it in a jar file
RUN ./gradlew build

#Stage 2: set base image for second stage
FROM openjdk:26-ea-17-jdk-trixie

# set deployment directory
WORKDIR /opt/app/

COPY --from=build /opt/app/build/libs/spring-boot-docker-0.0.1-SNAPSHOT.jar /app.jar

USER 111111

RUN mkdir /tmp/jfr
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app.jar", "api"]