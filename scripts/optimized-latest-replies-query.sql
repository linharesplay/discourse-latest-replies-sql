-- Query otimizada para buscar os últimos comentários
-- Esta query usa a view criada anteriormente para melhor performance

SELECT 
  id,
  post_number,
  raw,
  cooked,
  created_at,
  updated_at,
  topic_id,
  user_id,
  topic_title,
  topic_slug,
  category_id,
  category_name,
  category_color,
  category_text_color,
  username,
  display_name,
  avatar_template,
  tags,
  excerpt
FROM latest_replies_view
ORDER BY created_at DESC
LIMIT 15;

-- Query alternativa sem view (caso a view não esteja disponível)
-- Esta query pode ser usada diretamente no plugin

/*
SELECT 
  p.id,
  p.post_number,
  COALESCE(p.cooked, p.raw) as content,
  p.created_at,
  p.topic_id,
  t.title as topic_title,
  t.slug as topic_slug,
  t.category_id,
  c.name as category_name,
  c.color as category_color,
  u.username,
  u.name as display_name,
  u.avatar_template,
  -- Subquery para buscar tags
  (
    SELECT ARRAY_AGG(tag.name)
    FROM topic_tags tt
    INNER JOIN tags tag ON tt.tag_id = tag.id
    WHERE tt.topic_id = t.id
  ) as tags,
  -- Extrair excerpt removendo HTML
  LEFT(REGEXP_REPLACE(COALESCE(p.cooked, p.raw), '<[^>]*>', '', 'g'), 200) as excerpt
FROM posts p
INNER JOIN topics t ON p.topic_id = t.id
INNER JOIN users u ON p.user_id = u.id
LEFT JOIN categories c ON t.category_id = c.id
WHERE 
  p.post_number > 1 
  AND p.deleted_at IS NULL
  AND t.deleted_at IS NULL
  AND t.archetype = 'regular'
  AND t.visible = true
  AND p.hidden = false
  AND u.active = true
ORDER BY p.created_at DESC
LIMIT 15;
*/
