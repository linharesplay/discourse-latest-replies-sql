-- Criar uma view otimizada para os últimos comentários
-- Esta view pode ser usada para melhorar a performance das queries

CREATE OR REPLACE VIEW latest_replies_view AS
SELECT 
  p.id,
  p.post_number,
  p.raw,
  p.cooked,
  p.created_at,
  p.updated_at,
  p.topic_id,
  p.user_id,
  t.title as topic_title,
  t.slug as topic_slug,
  t.category_id,
  c.name as category_name,
  c.color as category_color,
  c.text_color as category_text_color,
  u.username,
  u.name as display_name,
  u.avatar_template,
  -- Agregação de tags em uma única query
  COALESCE(
    ARRAY_AGG(DISTINCT tag.name) FILTER (WHERE tag.name IS NOT NULL), 
    ARRAY[]::text[]
  ) as tags,
  -- Calcular excerpt diretamente no SQL
  CASE 
    WHEN LENGTH(REGEXP_REPLACE(p.cooked, '<[^>]*>', '', 'g')) > 200 
    THEN LEFT(REGEXP_REPLACE(p.cooked, '<[^>]*>', '', 'g'), 200) || '...'
    ELSE REGEXP_REPLACE(p.cooked, '<[^>]*>', '', 'g')
  END as excerpt
FROM posts p
INNER JOIN topics t ON p.topic_id = t.id
INNER JOIN users u ON p.user_id = u.id
LEFT JOIN categories c ON t.category_id = c.id
LEFT JOIN topic_tags tt ON t.id = tt.topic_id
LEFT JOIN tags tag ON tt.tag_id = tag.id
WHERE 
  p.post_number > 1 
  AND p.deleted_at IS NULL
  AND t.deleted_at IS NULL
  AND t.archetype = 'regular'
  AND t.visible = true
  AND p.hidden = false
  AND u.active = true
GROUP BY 
  p.id, p.post_number, p.raw, p.cooked, p.created_at, p.updated_at,
  p.topic_id, p.user_id, t.title, t.slug, t.category_id,
  c.name, c.color, c.text_color, u.username, u.name, u.avatar_template;

-- Criar índices para otimizar a performance
CREATE INDEX IF NOT EXISTS idx_posts_latest_replies 
ON posts (created_at DESC, post_number) 
WHERE post_number > 1 AND deleted_at IS NULL AND hidden = false;

CREATE INDEX IF NOT EXISTS idx_topics_visible 
ON topics (visible, archetype, deleted_at) 
WHERE visible = true AND archetype = 'regular' AND deleted_at IS NULL;
