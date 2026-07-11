package br.com.oficina.usecase;

import br.com.oficina.domain.model.Cliente;
import br.com.oficina.domain.model.Documento;
import br.com.oficina.usecase.gateway.ClienteRepository;
import br.com.oficina.domain.exception.BusinessException;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClienteServiceImpl {

  private static final String ERRO_CLIENTE_NAO_CADASTRADO = "CLIENTE_NAO_CADASTRADO";
  private static final String MSG_CLIENTE_NAO_CADASTRADO = "Cliente não cadastrado";

  private final ClienteRepository repo;

  public ClienteServiceImpl(ClienteRepository repo) {
    this.repo = repo;
  }

  @Transactional
  public Cliente cadastrar(String nome, String documentoRaw, String email, String telefone) {
    Documento doc = Documento.de(documentoRaw);
    if (repo.existePorDocumento(doc)) {
      throw new BusinessException("CLIENTE_DUPLICADO", "Já existe cliente com esse documento");
    }
    return repo.salvar(Cliente.criar(nome, doc, email, telefone));
  }

  @Transactional
  public Cliente atualizar(Long id, String nome, String email, String telefone) {
    Cliente c =
        repo.porId(id)
            .orElseThrow(
                () ->
                    new BusinessException(ERRO_CLIENTE_NAO_CADASTRADO, MSG_CLIENTE_NAO_CADASTRADO));
    c.atualizar(nome, email, telefone);
    return repo.salvar(c);
  }

  @Transactional
  public void desativar(Long id) {
    Cliente c =
        repo.porId(id)
            .orElseThrow(
                () ->
                    new BusinessException(ERRO_CLIENTE_NAO_CADASTRADO, MSG_CLIENTE_NAO_CADASTRADO));
    if (repo.temOsAtiva(id)) {
      throw new BusinessException(
          "CLIENTE_COM_OS_ATIVA", "Cliente possui OS ativa e não pode ser desativado");
    }
    c.desativar();
    repo.salvar(c);
  }

  @Transactional(readOnly = true)
  public Cliente buscar(Long id) {
    return repo.porId(id)
        .orElseThrow(
            () -> new BusinessException(ERRO_CLIENTE_NAO_CADASTRADO, MSG_CLIENTE_NAO_CADASTRADO));
  }

  @Transactional(readOnly = true)
  public Cliente buscarPorDocumento(String documentoRaw) {
    return repo.porDocumento(Documento.de(documentoRaw))
        .orElseThrow(
            () -> new BusinessException(ERRO_CLIENTE_NAO_CADASTRADO, MSG_CLIENTE_NAO_CADASTRADO));
  }

  @Transactional(readOnly = true)
  public List<Cliente> listar() {
    return repo.listarTodos();
  }
}
