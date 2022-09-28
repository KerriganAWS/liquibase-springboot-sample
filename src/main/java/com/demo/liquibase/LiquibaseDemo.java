package com.demo.liquibase;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ApplicationContext;

@SpringBootApplication
public class LiquibaseDemo {

  public static void main(String[] args) {
    // Added new lines for testing
    final ApplicationContext context = SpringApplication.run(LiquibaseDemo.class, args);
    System.exit(SpringApplication.exit(context, () -> 0));
  }
}
