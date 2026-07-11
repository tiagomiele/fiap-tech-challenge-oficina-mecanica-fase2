package br.com.oficina.adapter.controller;

import br.com.oficina.adapter.dto.OrdemServicoResponse;
import br.com.oficina.adapter.dto.OrdemServicoStatusResponse;
import br.com.oficina.domain.exception.BusinessException;
import br.com.oficina.usecase.OrdemServicoServiceImpl;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * 04 - ClienteOficinaController — "Perfil de acesso do Cliente na Oficina".
 *
 * <p>Endpoints <strong>públicos</strong> (sem JWT) usados pelo cliente final para aprovar/rejeitar
 * orçamento e consultar o status da OS pelo número impresso no comprovante de abertura.
 *
 * <p>Mensagens de erro de status (409) são <em>traduzidas</em> para linguagem amigável neste
 * controller — internamente o domínio lança {@link BusinessException} com o código técnico {@code
 * ORDEM_SERVICO_STATUS_INVALIDO}; aqui ele é convertido para o código {@code
 * ORCAMENTO_NAO_DISPONIVEL} com texto orientado ao cliente.
 */
@RestController
@Tag(
    name = "04-Perfil de acesso do Cliente na Oficina",
    description =
        "Endpoints públicos voltados ao cliente final: aprovar/rejeitar orçamento e consultar"
            + " status da OS. Não exigem autenticação JWT.")
public class ClienteOficinaController {

  private static final String DESC_NUMERO_OS =
      "Número da Ordem de Serviço no formato OS-MMAAAA-NNNNNN, impresso no comprovante.";
  private static final String EXAMPLE_NUMERO_OS = "OS-042026-000001";

  private final OrdemServicoServiceImpl service;

  public ClienteOficinaController(OrdemServicoServiceImpl service) {
    this.service = service;
  }

  // ===== Schemas =====================================================================

  @Schema(
      description = "Motivo da rejeição informado pelo cliente.",
      example = "{\"motivo\":\"Valor acima do esperado\"}")
  public record RejeitarOsRequest(
      @Schema(description = "Motivo informado pelo cliente.", example = "Valor acima do esperado")
          @NotBlank
          String motivo) {}

  @Schema(
      description = "Dados para confirmação de pagamento de OS.",
      example = "{\"comprovante\":\"PIX-20260412-001\"}")
  public record ConfirmarPagamentoRequest(
      @Schema(
              description = "Identificador do comprovante (PIX/boleto/cartão).",
              example = "PIX-20260412-001")
          @NotBlank
          String comprovante) {}

  // ===== Endpoints ===================================================================

  @Operation(
      summary = "04.01 - Aprovar orçamento (público)",
      description =
          "Endpoint público (sem JWT) usado pelo cliente para aprovar o orçamento atual."
              + " Transição AGUARDANDO_APROVACAO → EM_EXECUCAO. Na primeira aprovação grava"
              + " `inicio_execucao`.")
  @ApiResponses({
    @ApiResponse(responseCode = "200", description = "Orçamento aprovado."),
    @ApiResponse(responseCode = "404", description = "OS não encontrada (OS_NAO_ENCONTRADA)."),
    @ApiResponse(
        responseCode = "409",
        description = "Orçamento não está disponível para aprovação (ORCAMENTO_NAO_DISPONIVEL).")
  })
  @PostMapping("/ordens-servico/{numeroOs}/aprovar")
  public OrdemServicoResponse aprovar(
      @Parameter(name = "numeroOs", description = DESC_NUMERO_OS, example = EXAMPLE_NUMERO_OS)
          @PathVariable("numeroOs")
          String numero) {
    return executarComMensagemAmigavel(() -> OrdemServicoResponse.de(service.aprovar(numero)));
  }

  @Operation(
      summary = "04.02 - Consultar status da OS (público)",
      description =
          "Endpoint público (sem autenticação) para o cliente acompanhar o andamento do reparo"
              + " informando o número da Ordem de Serviço impresso no comprovante.")
  @ApiResponses({
    @ApiResponse(
        responseCode = "200",
        description = "Status da OS.",
        content =
            @Content(
                mediaType = "application/json",
                schema = @Schema(implementation = OrdemServicoStatusResponse.class))),
    @ApiResponse(responseCode = "404", description = "OS não encontrada (OS_NAO_ENCONTRADA).")
  })
  @GetMapping("/consulta/ordens-servico/{numeroOs}/status")
  public OrdemServicoStatusResponse consultarStatus(
      @Parameter(name = "numeroOs", description = DESC_NUMERO_OS, example = EXAMPLE_NUMERO_OS)
          @PathVariable
          String numeroOs) {
    return OrdemServicoStatusResponse.de(service.consultar(numeroOs));
  }

  @Operation(
      summary = "04.03 - Rejeitar orçamento e solicitar refazer (público)",
      description =
          "Endpoint público. Estorna peças, abre um novo orçamento (id_orcamento + 1) e volta"
              + " à EM_DIAGNOSTICO.")
  @ApiResponses({
    @ApiResponse(responseCode = "200", description = "Orçamento rejeitado, novo orçamento aberto."),
    @ApiResponse(responseCode = "404", description = "OS não encontrada (OS_NAO_ENCONTRADA)."),
    @ApiResponse(
        responseCode = "409",
        description = "Orçamento não está disponível para rejeição (ORCAMENTO_NAO_DISPONIVEL).")
  })
  @PostMapping("/ordens-servico/{numeroOs}/rejeitar-refazer")
  public OrdemServicoResponse rejeitarRefazer(
      @Parameter(name = "numeroOs", description = DESC_NUMERO_OS, example = EXAMPLE_NUMERO_OS)
          @PathVariable("numeroOs")
          String numero,
      @Valid @RequestBody RejeitarOsRequest req) {
    return executarComMensagemAmigavel(
        () -> OrdemServicoResponse.de(service.rejeitarRefazer(numero, req.motivo())));
  }

  @Operation(
      summary = "04.04 - Rejeitar orçamento e cancelar OS (público)",
      description = "Endpoint público. Cancela a OS e estorna peças reservadas para o estoque.")
  @ApiResponses({
    @ApiResponse(responseCode = "200", description = "Orçamento rejeitado, OS cancelada."),
    @ApiResponse(responseCode = "404", description = "OS não encontrada (OS_NAO_ENCONTRADA)."),
    @ApiResponse(
        responseCode = "409",
        description = "Orçamento não está disponível para rejeição (ORCAMENTO_NAO_DISPONIVEL).")
  })
  @PostMapping("/ordens-servico/{numeroOs}/rejeitar-cancelar")
  public OrdemServicoResponse rejeitarCancelar(
      @Parameter(name = "numeroOs", description = DESC_NUMERO_OS, example = EXAMPLE_NUMERO_OS)
          @PathVariable("numeroOs")
          String numero,
      @Valid @RequestBody RejeitarOsRequest req) {
    return executarComMensagemAmigavel(
        () -> OrdemServicoResponse.de(service.rejeitarCancelar(numero, req.motivo())));
  }

  @Operation(
      summary = "04.05 - Confirmar pagamento de OS (público)",
      description =
          "Endpoint público (sem JWT) usado pelo cliente para registrar o próprio pagamento da"
              + " OS informando o identificador do comprovante (PIX/boleto/cartão). Transição"
              + " AGUARDANDO_PAGAMENTO → PAGA. Gera lançamento financeiro de Conta a Receber.")
  @ApiResponses({
    @ApiResponse(responseCode = "200", description = "Pagamento confirmado, OS marcada como PAGA."),
    @ApiResponse(responseCode = "404", description = "OS não encontrada (OS_NAO_ENCONTRADA)."),
    @ApiResponse(
        responseCode = "409",
        description =
            "OS não está disponível para confirmação de pagamento (ORCAMENTO_NAO_DISPONIVEL).")
  })
  @PostMapping("/ordens-servico/{numeroOs}/confirmar-pagamento")
  public OrdemServicoResponse confirmarPagamento(
      @Parameter(name = "numeroOs", description = DESC_NUMERO_OS, example = EXAMPLE_NUMERO_OS)
          @PathVariable("numeroOs")
          String numero,
      @Valid @RequestBody ConfirmarPagamentoRequest req) {
    return executarComMensagemAmigavel(
        () -> OrdemServicoResponse.de(service.confirmarPagamento(numero, req.comprovante())));
  }

  // ===== Helpers =====================================================================

  /**
   * Executa a ação e, se o domínio lançar status inválido, traduz para mensagem amigável ao cliente
   * final. Os demais erros (OS não encontrada, validação) seguem o fluxo padrão.
   */
  private <T> T executarComMensagemAmigavel(java.util.function.Supplier<T> acao) {
    try {
      return acao.get();
    } catch (BusinessException ex) {
      if ("ORDEM_SERVICO_STATUS_INVALIDO".equals(ex.getCodigo())) {
        throw new BusinessException(
            "ORCAMENTO_NAO_DISPONIVEL",
            "Esta operação não está disponível para a OS neste momento."
                + " Consulte o status atual da OS pelo endpoint de consulta pública.");
      }
      throw ex;
    }
  }
}
