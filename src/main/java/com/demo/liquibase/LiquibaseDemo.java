package com.demo.liquibase;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ApplicationContext;

@SpringBootApplication
public class LiquibaseDemo {

  public static void main(String[] args) {
    // Added a new line for testing.
    // Added a new line for testing.
    final ApplicationContext context = SpringApplication.run(LiquibaseDemo.class, args);
    System.exit(SpringApplication.exit(context, () -> 0));
  }
}
