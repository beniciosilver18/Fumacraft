# Fumacraft

Plataforma de lojas online para pequenos negócios, com catálogo, carrinho e pedidos enviados pelo WhatsApp.

## Experiência de clientes e vendedores

- Visitantes podem explorar lojas, produtos e serviços sem criar conta.
- Cada vendedor cria e gere a sua loja através de uma conta própria.
- O catálogo suporta produtos e serviços com foto, preço, descrição e categoria.
- Lojas de produtos podem receber pedidos para entrega ou levantamento.
- Negócios de serviços podem escolher atendimento por marcação. O cliente indica uma preferência de dia e hora; o vendedor confirma a disponibilidade directamente no WhatsApp.
- O Fumacraft regista o pedido e gera um código. O WhatsApp é usado para continuar a conversa com o negócio.
- O checkout e as marcações não representam uma confirmação automática de pagamento ou de agenda.
- O login com Google depende de o fornecedor Google estar activo nas definições de autenticação do projecto Supabase.

## Estrutura

- `public/index.html` — aplicação principal (página inicial, explorar, autenticação, painel do vendedor, pedidos e lojas).
- `public/manifest.json`, `public/sw.js` e `public/icon-*` — instalação PWA e ícones.
- `functions/` — funções Edge do Supabase (runtime Deno). Esta pasta não pertence ao frontend do Cloudflare Pages.
- `schema.sql` — esquema de referência da base de dados.
- `docs/` — decisões de arquitetura e fases do projecto.

## Publicação

O frontend é publicado pelo projecto Cloudflare Pages `fumacraft`, ligado à branch `main`. A raiz do projecto Pages é `/public` e o directório de saída é `.`, sem comando de construção.

Não executar `npx wrangler deploy` para publicar este frontend: esse comando publica Workers. A publicação do site deve usar Cloudflare Pages.

O lançamento permanece gratuito. A monetização e os pagamentos de subscrição continuam desligados.
