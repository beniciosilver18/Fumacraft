# Organização profunda da Fumacraft

## Decisão de lançamento

- A plataforma começa 100% gratuita para clientes e vendedores.
- Não existe período experimental obrigatório, mensalidade, comissão nem bloqueio por falta de pagamento.
- O preço futuro definido pelo proprietário é US$ 9,99 por mês. Este valor é confidencial e deve aparecer apenas no painel Admin enquanto a monetização estiver desligada.
- O interruptor global do Admin controla apenas a preparação/apresentação do plano futuro. Não pode iniciar cobranças automaticamente.
- A cobrança internacional em USD será uma fase separada, sujeita a decisão explícita do proprietário e testes próprios.

## Diagnóstico do código atual

A aplicação principal está concentrada num único `index.html`, com HTML, CSS e JavaScript misturados. O backend usa Supabase: o esquema está em `schema.sql` e as Edge Functions estão em `functions/`. Há código antigo de assinatura que ainda mostra 7 dias grátis, 640 MT, links de pagamento e estados de loja que podem expirar. Essa lógica conflita com a decisão de lançar a plataforma gratuita.

## Arquitetura-alvo

```text
/
  index.html                 entrada HTML e metadados
  assets/
    css/                     estilos globais e componentes
    js/
      app.js                 entrada temporária da aplicação
      core/                  configuração, rotas e utilitários
      services/              autenticação e acesso ao Supabase
      features/
        public/              início, explorar e páginas de loja
        seller/              painel do vendedor, catálogo e pedidos
        admin/               administração e controlo do plano
  docs/
    ORGANIZACAO-PROFUNDA.md  decisões e fases do projeto
    sql/                    atualizações do banco versionadas
  functions/                 Edge Functions Supabase
  schema.sql                 esquema de referência acumulado
  manifest.json              configuração PWA
  sw.js                      service worker e notificações
```

A migração será gradual: preservar URLs públicos existentes, separar primeiro os ficheiros estáticos e depois dividir o JavaScript por responsabilidade. Não fazer uma reescrita total de uma só vez.

## Fases de trabalho

### Fase 1 — Lançamento gratuito e estabilização

- Remover preços e pagamentos das áreas de clientes e vendedores.
- Fazer com que lojas não expirem quando a monetização está desligada.
- Guardar o preço de US$ 9,99 apenas numa configuração administrativa.
- Criar no Admin um interruptor global, protegido no servidor, com estado inicial desligado.
- Bloquear no servidor os antigos endpoints de cobrança e impedir webhooks antigos de ativarem assinaturas.
- Testar cadastro, sessão, criação de loja, edição de produtos, pedidos, WhatsApp e notificações.

### Fase 2 — Separação do frontend

- Separar HTML, CSS e JavaScript.
- Dividir o JavaScript em módulos: core, serviços, público, vendedor e Admin.
- Manter os caminhos das lojas existentes e os links partilhados.
- Adicionar tratamento de erros, carregamento e estados vazios coerentes.

### Fase 3 — Backend e segurança

- Rever RLS por tabela e por papel: visitante, cliente, vendedor e administrador.
- Confirmar que cada vendedor só altera a própria loja, produtos, pedidos e subscrições de notificações.
- Rever funções `SECURITY DEFINER`, permissões `EXECUTE`, validação de parâmetros e registos de auditoria.
- Não expor segredos nem dados privados no frontend.
- Testar acesso não autorizado e operações administrativas.

### Fase 4 — Plataforma multi-negócio e internacional

- Suportar produtos e serviços de diferentes setores, não apenas alimentação.
- Normalizar país, província/estado, cidade e bairro.
- Melhorar pesquisa, categorias, filtros e apresentação mobile.
- Medir apenas visitas, contactos, pedidos e avaliações reais; não inventar métricas.

### Fase 5 — Monetização futura

- Confirmar primeiro que já existe uma base estável de vendedores ativos.
- Definir política de transição, período de aviso, cancelamento, reembolso, impostos e suporte.
- Integrar checkout internacional em USD e webhooks idempotentes.
- Só depois de testes completos, o administrador decide quando iniciar cobranças.
- O botão de desligar deve continuar disponível como mecanismo de emergência.

## Critérios para considerar a Fase 1 concluída

- Um vendedor e um cliente não encontram preço, plano, botão de pagamento nem mensagem de teste.
- Uma loja antiga não fica indisponível por data de teste ou `paid_until`.
- O Admin consegue ver o preço e o estado global, mas não consegue cobrar com um simples clique.
- Chamadas aos endpoints antigos de pagamento são recusadas enquanto a cobrança não estiver pronta.
- O webhook antigo não ativa planos.
- O fluxo completo funciona num telemóvel Android.

## Limite de acesso nesta sessão

O código da Fumacraft aponta para o projeto Supabase `hqjmkdfbwdtxgifkenew`, mas a ligação Supabase disponível nesta sessão não tem permissão para esse projeto. A lista devolveu outro projeto, que não deve ser alterado. Assim, alterações SQL e publicação de Edge Functions exigem a ligação correta ao projeto Supabase da Fumacraft. Não se deve aplicar nada ao projeto errado.
