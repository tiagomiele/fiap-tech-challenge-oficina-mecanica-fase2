package br.com.oficina;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.ComponentScan;

@SpringBootApplication
@ComponentScan(basePackages = "br.com.oficina")
public class OficinaApplication {

  public static void main(String[] args) {
    SpringApplication.run(OficinaApplication.class, args);
  }
}
