package br.com.oficina.adapter.security;

import br.com.oficina.domain.enums.Papel;
import java.util.UUID;

public record AuthenticatedPrincipal(UUID userId, String email, Papel papel) {}
