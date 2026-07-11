package br.com.oficina.adapter.notification;

import br.com.oficina.usecase.gateway.NotificacaoGateway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.mail.MailException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

/**
 * Envia notificações de status da OS por e-mail (SMTP) usando o {@link JavaMailSender} do Spring.
 *
 * <p>Ativado por {@code oficina.notificacao.tipo=smtp}. Quando ausente (ou {@code log}), o {@link
 * LogNotificacaoGateway} é usado no lugar, mantendo CI/testes sem dependência de servidor de e-mail.
 * As credenciais vêm das propriedades {@code spring.mail.*} (variáveis de ambiente).
 */
@Service
@ConditionalOnProperty(name = "oficina.notificacao.tipo", havingValue = "smtp")
public class SmtpNotificacaoGateway implements NotificacaoGateway {

  private static final Logger log = LoggerFactory.getLogger(SmtpNotificacaoGateway.class);

  private final JavaMailSender mailSender;
  private final String remetente;

  public SmtpNotificacaoGateway(
      JavaMailSender mailSender,
      @Value("${oficina.notificacao.remetente:nao-responder@oficina.local}") String remetente) {
    this.mailSender = mailSender;
    this.remetente = remetente;
  }

  @Override
  public void enviar(String destinatario, String assunto, String corpo) {
    SimpleMailMessage mensagem = new SimpleMailMessage();
    mensagem.setFrom(remetente);
    mensagem.setTo(destinatario);
    mensagem.setSubject(assunto);
    mensagem.setText(corpo);
    // A notificação é um efeito colateral: uma falha de SMTP não pode reverter a
    // transição de status da OS (este método roda dentro de @Transactional).
    try {
      mailSender.send(mensagem);
      log.info("E-mail de notificacao enviado para {} | Assunto: {}", destinatario, assunto);
    } catch (MailException ex) {
      log.error(
          "Falha ao enviar e-mail para {} | Assunto: {} | Erro: {}",
          destinatario,
          assunto,
          ex.getMessage(),
          ex);
    }
  }
}
