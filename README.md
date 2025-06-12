# Plugin Discourse - Latest Replies com SQL

Este plugin para Discourse exibe os últimos comentários na página inicial usando queries SQL diretas ao banco de dados PostgreSQL.

## Características

- **Queries SQL Otimizadas**: Usa queries SQL diretas para melhor performance
- **Fallback para API REST**: Se as queries SQL falharem, usa a API REST como backup
- **Cache Inteligente**: Sistema de cache local para reduzir carga no servidor
- **Polling em Tempo Real**: Atualiza automaticamente os comentários
- **Interface Responsiva**: Design adaptável para diferentes tamanhos de tela
- **Suporte a Tags e Categorias**: Exibe tags e categorias com cores personalizadas

## Instalação

1. Copie o código do plugin para um arquivo `.js` no diretório de plugins do Discourse
2. Execute os scripts SQL para criar as views e índices otimizados
3. Ative o plugin no painel administrativo do Discourse

## Estrutura do Banco de Dados

O plugin utiliza as seguintes tabelas principais do Discourse:

- `posts` - Posts/comentários
- `topics` - Tópicos
- `users` - Usuários
- `categories` - Categorias
- `tags` - Tags
- `topic_tags` - Relacionamento tópico-tag

## Queries SQL Principais

### Query Principal para Últimos Comentários

\`\`\`sql
SELECT 
  p.id,
  p.post_number,
  p.raw,
  p.cooked,
  p.created_at,
  p.topic_id,
  t.title as topic_title,
  t.slug as topic_slug,
  c.name as category_name,
  u.username,
  u.avatar_template,
  ARRAY_AGG(DISTINCT tag.name) as tags
FROM posts p
INNER JOIN topics t ON p.topic_id = t.id
INNER JOIN users u ON p.user_id = u.id
LEFT JOIN categories c ON t.category_id = c.id
LEFT JOIN topic_tags tt ON t.id = tt.topic_id
LEFT JOIN tags tag ON tt.tag_id = tag.id
WHERE 
  p.post_number > 1 
  AND p.deleted_at IS NULL
  AND t.visible = true
GROUP BY p.id, t.title, t.slug, c.name, u.username, u.avatar_template
ORDER BY p.created_at DESC
LIMIT 15;
\`\`\`

## Configurações

- `POLLING_INTERVAL`: Intervalo de polling em milissegundos (padrão: 2000)
- `COMMENTS_TO_SHOW`: Número de comentários a exibir (padrão: 15)
- `CACHE_DURATION`: Duração do cache em milissegundos (padrão: 24 horas)

## Funcionalidades

1. **Exibição de Últimos Comentários**: Mostra os comentários mais recentes
2. **Informações do Usuário**: Avatar, nome de usuário e link para perfil
3. **Categorias e Tags**: Exibe categorias com cores e tags associadas
4. **Timestamps Relativos**: Mostra "há X minutos/horas/dias"
5. **Links Diretos**: Links diretos para o post específico
6. **Cache Local**: Armazena dados localmente para melhor performance
7. **Fallback Automático**: Usa API REST se SQL falhar

## Otimizações

- View `latest_replies_view` para queries mais rápidas
- Índices otimizados para posts e tópicos
- Cache local com expiração automática
- Agregação de tags em uma única query
- Extração de excerpt diretamente no SQL

## Compatibilidade

- Discourse versão 2.8+
- PostgreSQL 10+
- Requer permissões de administrador para executar queries SQL
