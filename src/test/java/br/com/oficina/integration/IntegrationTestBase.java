package br.com.oficina.integration;

import io.restassured.RestAssured;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
public abstract class IntegrationTestBase {

  @LocalServerPort private int port;

  @BeforeEach
  void setUpRestAssured() {
    RestAssured.port = port;
    RestAssured.basePath = "";
  }

  protected String loginComoAdmin() {
    return loginComo("admin@oficina.local", "admin123");
  }

  protected String loginComo(String email, String senha) {
    return RestAssured.given()
        .contentType("application/json")
        .body("{\"email\":\"" + email + "\",\"senha\":\"" + senha + "\"}")
        .post("/auth/login")
        .then()
        .statusCode(200)
        .extract()
        .path("accessToken");
  }
}
