# Fumacraft

Plataforma de lojas online para pequenos negócios, com catálogo, carrinho e pedidos enviados pelo WhatsApp.

## Estrutura

- `public/index.html` — aplicação principal (página inicial, explorar, painel do vendedor e lojas).
- `public/manifest.json`, `public/sw.js` e `public/icon-*` — instalação PWA e ícones.
- `functions/` — funções Edge do Supabase (runtime Deno). Esta pasta não pertence ao frontend do Cloudflare Pages.
- `schema.sql` — esquema de referência da base de dados.
- `docs/` — decisões de arquitetura e fases do projeto.

## Publicação

O frontend é publicado pelo projeto Cloudflare Pages `fumacraft`, ligado à branch `main`. A raiz do projeto Pages é `/public` e o diretório de saída é `.`, sem comando de construção.

Não executar `npx wrangler deploy` para publicar este frontend: esse comando publica Workers. A publicação do site deve usar Cloudflare Pages.

O lançamento permanece gratuito. A monetização futura continua desligada.
